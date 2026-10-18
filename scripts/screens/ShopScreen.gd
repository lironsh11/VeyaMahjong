extends Screen
## Shop: lists ONLY products the platform store actually returned, with the store's own
## localized price. Without a configured billing integration it shows an honest, friendly
## "not available" state. The core game never depends on purchases.

var _busy: bool = false


func _ready() -> void:
	super._ready()
	IAPService.products_updated.connect(_on_relayout)
	IAPService.entitlements_changed.connect(_on_relayout)
	IAPService.purchase_result.connect(_on_purchase_result)


func build_background() -> void:
	UIKit.fullscreen_bg(self, ContentService.world_bg("crystal_nocturne", "gameplay", AccessibilityService.low_profile), 0.15, Color.WHITE)


func build() -> void:
	var root := UIKit.vbox(10)
	safe.add_child(root)
	root.add_child(UIKit.header(t("shop"), func() -> void: Router.back(), true))
	var list := UIKit.vbox(12)
	root.add_child(UIKit.scroll(list))
	var products := IAPService.offered_products()
	if products.is_empty():
		var p := UIKit.panel("Card")
		var v := UIKit.vbox(10)
		p.add_child(v)
		v.add_child(UIKit.texrect(ContentService.icon("shop"), Vector2(56, 56)))
		var reason := t("shop_connecting") if IAPService.status == IAPService.Status.CONNECTING else t("shop_unavailable")
		if IAPService.status == IAPService.Status.ERROR:
			reason = t("shop_error")
		v.add_child(UIKit.label(reason, UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UIKit.label(t("shop_free_promise"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
		list.add_child(p)
	else:
		for prod in products:
			list.add_child(_product_card(prod))
	if FeatureFlags.enabled("qa_mock_services") and OS.is_debug_build():
		list.add_child(UIKit.label("QA MOCK STORE - debug build only, no real transactions", UITheme.FONT_SMALL, true, UITheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER))
	var restore := UIKit.button(t("restore_purchases"), "cream", "small", func() -> void:
		if IAPService.restore():
			Router.toast(t("restore_started"))
		else:
			Router.toast(t("restore_unavailable")))
	restore.disabled = IAPService.provider == null
	list.add_child(restore)
	if restore.disabled:
		var note := UIKit.panel("CardFlat")
		note.add_child(UIKit.label(t("restore_unavailable"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
		list.add_child(note)
	root.add_child(UIKit.bottom_nav("shop"))


func _product_card(prod: Dictionary) -> Control:
	var p := UIKit.panel("OfferCard")
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(UIKit.label(t(str(prod.title_key)), UITheme.FONT_H2, true))
	v.add_child(UIKit.label(t(str(prod.desc_key)), UITheme.FONT_SMALL, false, UITheme.text_soft()))
	if IAPService.is_owned(prod):
		v.add_child(UIKit.chip(t("owned"), "ChipEmerald"))
	else:
		var price := IAPService.price_text(str(prod.id))
		var b := UIKit.button(t("buy_for", {"price": price}), "green", "small", func() -> void:
			if _busy:
				return
			_busy = true
			if not IAPService.purchase(str(prod.id)):
				_busy = false
				Router.toast(t("shop_unavailable")))
		v.add_child(b)
	return p


func _on_purchase_result(_pid: String, status: String, _msg: String) -> void:
	_busy = false
	var title := ""
	var body := ""
	match status:
		"success":
			title = t("purchase_success_title")
			body = t("purchase_success_body")
			AudioService.play("reward")
		"already_owned":
			title = t("purchase_owned_title")
			body = t("purchase_owned_body")
		"pending":
			title = t("purchase_pending_title")
			body = t("purchase_pending_body")
		"cancelled":
			return
		_:
			title = t("purchase_failed_title")
			body = t("purchase_failed_body")
	var m := ModalDialog.open(self, title, body)
	m.add_action(t("ok"), "ok", "green")
