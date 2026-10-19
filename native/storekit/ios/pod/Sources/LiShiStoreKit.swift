// StoreKit 2 bridge for LiShi Mahjong (iOS 15+).
//
// Exposed to the Godot glue (native/storekit/ios/godot/) as plain C functions, so the glue needs
// no Swift header. Every result is reported as one JSON event string through the registered C
// callback, always on the main thread. Event shapes (consumed by
// scripts/services/iap/AppStoreProvider.gd):
//
//   {"type":"connected","can_make_payments":true}
//   {"type":"products","products":[{"id","price","title"}],"invalid":["id",...]}
//   {"type":"products_error","message":"..."}
//   {"type":"purchase_update","purchases":[P,...]}         purchase result / Transaction.updates
//   {"type":"purchase_failed","product_id":"...","reason":"cancelled|busy|unverified:...|unknown_product|..."}
//   {"type":"owned","purchases":[P,...]}                   Transaction.unfinished + currentEntitlements
//   {"type":"owned_error","message":"..."}                 e.g. AppStore.sync failed or was cancelled
//   {"type":"finished","transaction":"...","ok":true}
//
//   P = {"product_id","transaction","state":"purchased|pending","finished":bool}
//
// Nothing is finished automatically: consumables are finished by consume(), non-consumables by
// acknowledge() (both call lishi_sk_finish) after the game has saved the grant. An unfinished
// transaction is replayed by the next query_owned (Transaction.unfinished), so a grant lost to a
// crash is retried and the game's ledger blocks a double grant.

import Foundation
import StoreKit

public typealias LiShiStoreKitCallback = @convention(c) (UnsafePointer<CChar>) -> Void

/// Set and read on the main thread only.
private var gCallback: LiShiStoreKitCallback?

@available(iOS 15.0, *)
@MainActor
private final class StoreState {
    static let shared = StoreState()

    var products: [String: Product] = [:]
    /// Verified transactions waiting for finish(), keyed by String(transaction.id).
    var pending: [String: Transaction] = [:]
    var updatesTask: Task<Void, Never>?
    var purchasing = false

    func emit(_ event: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else { return }
        // Always asynchronous so a Godot call never re-enters GDScript synchronously.
        DispatchQueue.main.async {
            guard let cb = gCallback else { return }
            json.withCString { cb($0) }
        }
    }

    func entry(_ t: Transaction, finished: Bool) -> [String: Any] {
        return ["product_id": t.productID, "transaction": String(t.id), "state": "purchased", "finished": finished]
    }

    func listenForUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached(priority: .background) {
            for await result in Transaction.updates {
                await StoreState.shared.handleUpdate(result)
            }
        }
    }

    func handleUpdate(_ result: VerificationResult<Transaction>) {
        guard case .verified(let t) = result else { return }
        if t.revocationDate != nil {
            // Refund / revocation: report the authoritative owned list so the game revokes.
            Task { @MainActor in await StoreState.shared.queryOwned(sync: false) }
            return
        }
        pending[String(t.id)] = t
        emit(["type": "purchase_update", "purchases": [entry(t, finished: false)]])
    }

    func requestProducts(_ ids: [String]) async {
        do {
            let found = try await Product.products(for: ids)
            var list: [[String: Any]] = []
            var seen = Set<String>()
            for p in found {
                products[p.id] = p
                seen.insert(p.id)
                list.append(["id": p.id, "price": p.displayPrice, "title": p.displayName])
            }
            emit(["type": "products", "products": list, "invalid": ids.filter { !seen.contains($0) }])
        } catch {
            emit(["type": "products_error", "message": String(describing: error)])
        }
    }

    func purchase(_ productId: String) async {
        if purchasing {
            emit(["type": "purchase_failed", "product_id": productId, "reason": "busy"])
            return
        }
        purchasing = true
        defer { purchasing = false }
        var product: Product? = products[productId]
        if product == nil {
            let fetched: [Product]? = try? await Product.products(for: [productId])
            product = fetched?.first
        }
        guard let product = product else {
            emit(["type": "purchase_failed", "product_id": productId, "reason": "unknown_product"])
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let t):
                    pending[String(t.id)] = t
                    emit(["type": "purchase_update", "purchases": [entry(t, finished: false)]])
                case .unverified(_, let error):
                    emit(["type": "purchase_failed", "product_id": productId, "reason": "unverified:" + String(describing: error)])
                }
            case .userCancelled:
                emit(["type": "purchase_failed", "product_id": productId, "reason": "cancelled"])
            case .pending:
                // Ask to Buy / SCA: the approved transaction arrives later via Transaction.updates.
                emit(["type": "purchase_update", "purchases": [["product_id": productId, "transaction": "", "state": "pending", "finished": false]]])
            @unknown default:
                emit(["type": "purchase_failed", "product_id": productId, "reason": "unknown_result"])
            }
        } catch {
            emit(["type": "purchase_failed", "product_id": productId, "reason": String(describing: error)])
        }
    }

    func queryOwned(sync: Bool) async {
        if sync {
            // Restore button only: may show the Apple Account sign-in sheet.
            do {
                try await AppStore.sync()
            } catch {
                emit(["type": "owned_error", "message": String(describing: error)])
                return
            }
        }
        var list: [[String: Any]] = []
        var seen = Set<String>()
        // Unfinished first (consumables whose grant may not have been confirmed yet).
        for await result in Transaction.unfinished {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            let key = String(t.id)
            pending[key] = t
            if seen.insert(key).inserted {
                list.append(entry(t, finished: false))
            }
        }
        // Non-consumables the customer is entitled to (refunded ones are not included).
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            let key = String(t.id)
            if seen.insert(key).inserted {
                list.append(entry(t, finished: true))
            }
        }
        emit(["type": "owned", "purchases": list])
    }

    func finish(_ transactionId: String) async {
        var found: Transaction? = pending[transactionId]
        if found == nil {
            for await result in Transaction.unfinished {
                if case .verified(let u) = result, String(u.id) == transactionId {
                    found = u
                    break
                }
            }
        }
        guard let tx = found else {
            emit(["type": "finished", "transaction": transactionId, "ok": false])
            return
        }
        await tx.finish()
        pending.removeValue(forKey: transactionId)
        emit(["type": "finished", "transaction": transactionId, "ok": true])
    }
}

// MARK: - C entry points (called from the Godot glue on the main thread)

private func cString(_ p: UnsafePointer<CChar>?) -> String {
    guard let p = p else { return "" }
    return String(cString: p)
}

@_cdecl("lishi_sk_is_supported")
public func lishi_sk_is_supported() -> Bool {
    if #available(iOS 15.0, *) { return true }
    return false
}

@_cdecl("lishi_sk_set_callback")
public func lishi_sk_set_callback(_ cb: LiShiStoreKitCallback?) {
    gCallback = cb
}

@_cdecl("lishi_sk_start")
public func lishi_sk_start() {
    guard #available(iOS 15.0, *) else { return }
    Task { @MainActor in
        let s = StoreState.shared
        s.listenForUpdates()
        s.emit(["type": "connected", "can_make_payments": AppStore.canMakePayments])
    }
}

/// ids_json: a JSON array of product id strings.
@_cdecl("lishi_sk_request_products")
public func lishi_sk_request_products(_ idsJson: UnsafePointer<CChar>?) {
    guard #available(iOS 15.0, *) else { return }
    let raw = cString(idsJson)
    let parsed = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [Any] ?? []
    let ids = parsed.compactMap { $0 as? String }
    Task { @MainActor in await StoreState.shared.requestProducts(ids) }
}

@_cdecl("lishi_sk_purchase")
public func lishi_sk_purchase(_ productId: UnsafePointer<CChar>?) {
    guard #available(iOS 15.0, *) else { return }
    let id = cString(productId)
    Task { @MainActor in await StoreState.shared.purchase(id) }
}

@_cdecl("lishi_sk_query_owned")
public func lishi_sk_query_owned(_ sync: Bool) {
    guard #available(iOS 15.0, *) else { return }
    Task { @MainActor in await StoreState.shared.queryOwned(sync: sync) }
}

@_cdecl("lishi_sk_finish")
public func lishi_sk_finish(_ transactionId: UnsafePointer<CChar>?) {
    guard #available(iOS 15.0, *) else { return }
    let id = cString(transactionId)
    Task { @MainActor in await StoreState.shared.finish(id) }
}
