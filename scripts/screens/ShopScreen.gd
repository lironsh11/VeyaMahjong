extends Screen
## Shop: boosters for coins (always available, offline too), free coins by watching a video
## (only when a real ad is loaded), and store products - starter bundle, coin packs, Remove
## Ads, themes - listed ONLY when the platform store returned them, with the store's own
## localized price. Without billing it shows an honest "not available" state for that part.

var _busy: bool = false
var _owned_labels: Dictionary = {}   ## item -> Label
var _buy_buttons: Array = []         ## [{button, item, qty}]


func _ready() -> void:
	super._ready()
	IAPService.products_updated.connect(_on_relayout)
	IAPService.entitlements_changed.connect(_on_relayout)
	IAPService.purchase_result.connect(_on_purchase_result)
	AdsService.availability_changed.connect(_on_relayout)
	EconomyService.wallet_changed.connect(_refresh_boosters)
	EconomyService.inventory_changed.connect(_on_inventory)
	AnalyticsService.track("shop_opened", {"from": str(Router.params.get("from", "nav"))})


func _exit_tree() -> void:
	for pair in [[AdsService.availability_changed, _on_relayout], [EconomyService.wallet_changed, _refresh_boosters], [EconomyService.inventory_changed, _on_inventory]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func build_background() -> void:
	UIKit.fullscreen_bg(self, ContentService.world_bg("crystal_nocturne", "gameplay", AccessibilityService.low_profile), 0.15, Color.WHITE)


func build() -> void:
	_owned_labels.clear()
	_buy_buttons.clear()
	var root := UIKit.vbox(10)
	safe.add_child(root)
	var head := UIKit.header(t("shop"), func() -> void: Router.back(), true)
	root.add_child(head)
	var coins_row := UIKit.hbox(0)
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coins_row.add_child(UIKit.coin_pill())
	root.add_child(coins_row)
	var list := UIKit.vbox(12)
	root.add_child(UIKit.scroll(list))
	if AdsService.is_rewarded_ready("shop_coins"):
		list.add_child(_free_coins_card())
	else:
		AdsService.load_rewarded("shop_coins")
	list.add_child(_boosters_card())
	_add_store_section(list)
	root.add_child(UIKit.bottom_nav("shop"))
	_refresh_boosters()


# --- free coins -----------------------------------------------------------------------

func _free_coins_card() -> Control:
	var p := UIKit.panel("Card")
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(UIKit.label(t("shop_free_coins"), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	var amount := int(EconomyService.rewarded_cfg("shop_coins").get("coins", 0))
	var b := UIKit.button(t("watch_ad_plus", {"count": amount}), "violet", "small")
	b.pressed.connect(func() -> void:
		b.disabled = true
		var gid := AdsService.next_grant_id("shop_coins")
		AdsService.rewarded_result.connect(func(placement: String, status: String) -> void:
			if placement != "shop_coins" or not is_instance_valid(b):
				return
			if status == "granted":
				AudioService.play("coin")
				_on_relayout()
			elif status == "not_completed":
				b.disabled = false
			else:
				Router.toast(t("ad_unavailable"))
				_on_relayout(), CONNECT_ONE_SHOT)
		AdsService.show_rewarded("shop_coins", gid, EconomyService.grant.bind(gid, {"coins": amount}, "ad_shop_coins")))
	v.add_child(b)
	v.add_child(UIKit.label(t("ads_left_today", {"count": AdsService.placement_remaining_today("shop_coins")}), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	return p


# --- boosters for coins ---------------------------------------------------------------

func _boosters_card() -> Control:
	var p := UIKit.panel("Card")
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(UIKit.label(t("shop_boosters"), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER))
	for item in EconomyService.items():
		var row := UIKit.hbox(8)
		row.add_child(UIKit.texrect(ContentService.icon(item), Vector2(36, 36)))
		var name_box := UIKit.vbox(0)
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_child(UIKit.label(t(item), UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_LEFT, false))
		var owned := UIKit.label("", UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_LEFT, false)
		_owned_labels[item] = owned
		name_box.add_child(owned)
		row.add_child(name_box)
		for qty in EconomyService.pack_sizes(item):
			row.add_child(_buy_button(item, qty))
		v.add_child(row)
	return p


func _buy_button(item: String, qty: int) -> Button:
	var price := EconomyService.price(item, qty)
	var b := UIKit.button("", "green", "small")
	b.custom_minimum_size = Vector2(118, UITheme.TOUCH_MIN)
	var h := UIKit.hbox(4)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_child(UIKit.label("\u200e×%s" % LocalizationService.format_number(qty), UITheme.FONT_SMALL, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false))
	h.add_child(UIKit.texrect(ContentService.icon("coin", true), Vector2(18, 18)))
	h.add_child(UIKit.label(LocalizationService.format_number(price), UITheme.FONT_SMALL, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false))
	b.add_child(h)
	AccessibilityService.set_access_name(b, "%s ×%d, %s" % [t(item), qty, t("a11y_coins", {"count": price})])
	b.pressed.connect(func() -> void:
		if EconomyService.buy(item, qty):
			AudioService.play("coin")
			Router.toast(t("booster_bought"))
		else:
			Router.toast(t("not_enough_coins")))
	_buy_buttons.append({"button": b, "item": item, "qty": qty})
	return b


func _on_inventory(_item: String) -> void:
	_refresh_boosters()


func _refresh_boosters() -> void:
	for item in _owned_labels:
		var l: Label = _owned_labels[item]
		if is_instance_valid(l):
			l.text = "\u200e×%s" % LocalizationService.format_number(EconomyService.count(item))
	for e in _buy_buttons:
		if is_instance_valid(e.button):
			e.button.disabled = not EconomyService.can_afford(e.item, e.qty)


# --- store products -------------------------------------------------------------------

func _add_store_section(list: VBoxContainer) -> void:
	var products := IAPService.offered_products()
	if products.is_empty():
		var p := UIKit.panel("Card")
		var v := UIKit.vbox(10)
		p.add_child(v)
		var reason := t("shop_connecting") if IAPService.status == IAPService.Status.CONNECTING else t("shop_unavailable")
		if IAPService.status == IAPService.Status.ERROR:
			reason = t("shop_error")
		v.add_child(UIKit.label(reason, UITheme.FONT_BODY, true, null, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UIKit.label(t("shop_iap_note"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
		list.add_child(p)
	else:
		var bundle: Array = []
		var packs: Array = []
		var others: Array = []
		for prod in products:
			if bool(prod.get("bundle", false)):
				if not IAPService.has_entitlement("remove_ads") and GameState.highest_completed() >= EconomyService.starter_bundle_min_level():
					bundle.append(prod)
			elif IAPService.is_consumable(prod):
				packs.append(prod)
			else:
				others.append(prod)
		for prod in bundle:
			list.add_child(_section_title(t("shop_bundle")))
			list.add_child(_product_card(prod))
		if not packs.is_empty():
			list.add_child(_section_title(t("shop_coin_packs")))
			for prod in packs:
				list.add_child(_product_card(prod))
		for prod in others:
			list.add_child(_product_card(prod))
		list.add_child(UIKit.label(t("shop_iap_note"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	if FeatureFlags.enabled("qa_mock_services") and OS.is_debug_build():
		list.add_child(UIKit.label("QA MOCK STORE - debug build only, no real transactions", UITheme.FONT_SMALL, true, UITheme.DANGER, HORIZONTAL_ALIGNMENT_CENTER))
	var restore := UIKit.button(t("restore_purchases"), "cream", "small", func() -> void:
		if IAPService.restore():
			Router.toast(t("restore_started"))
		else:
			Router.toast(t("restore_unavailable")))
	restore.disabled = IAPService.provider == null
	list.add_child(restore)
	var note := UIKit.panel("CardFlat")
	note.add_child(UIKit.label(t("restore_unavailable") if restore.disabled else t("shop_restore_note"), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	list.add_child(note)


func _section_title(text: String) -> Label:
	var l := UIKit.label(text, UITheme.FONT_H2, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	l.add_theme_color_override("font_outline_color", Color(UITheme.NAVY, 0.7))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _product_desc(prod: Dictionary) -> String:
	var c := EconomyService.iap_contents(str(prod.id))
	return t(str(prod.desc_key), {"count": int(c.get("coins", 0)), "coins": int(c.get("coins", 0)),
		"hint": int(c.get("hint", 0)), "shuffle": int(c.get("shuffle", 0)), "undo": int(c.get("undo", 0))})


func _product_card(prod: Dictionary) -> Control:
	var p := UIKit.panel("OfferCard")
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(UIKit.label(t(str(prod.title_key)), UITheme.FONT_H2, true))
	v.add_child(UIKit.label(_product_desc(prod), UITheme.FONT_SMALL, false, UITheme.text_soft()))
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
