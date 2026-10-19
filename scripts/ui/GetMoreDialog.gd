class_name GetMoreDialog
extends RefCounted
## "Out of <booster>" dialog: buy a pack with coins, watch a video for one (only when a real ad
## is loaded), or open the shop. In a rescue context it also offers the free ways forward
## (rewind to the last solvable point, restart) so a player is never stuck behind a price.
##
## closed results: bought | ad_granted | shop | rewind | restart | dismiss

static func open(parent: Node, item: String, rescue_rewind: bool = false, rescue_restart: bool = false) -> ModalDialog:
	var t := LocalizationService.t
	var m := ModalDialog.open(parent, t.call("out_of_" + item), t.call("get_more_body"))
	var box := UIKit.vbox(10)
	var balance := UIKit.hbox(6)
	balance.alignment = BoxContainer.ALIGNMENT_CENTER
	balance.add_child(UIKit.texrect(ContentService.icon("coin"), Vector2(26, 26)))
	balance.add_child(UIKit.label(LocalizationService.format_number(EconomyService.coins()), UITheme.FONT_H2, true, null, HORIZONTAL_ALIGNMENT_CENTER, false))
	box.add_child(balance)
	for qty in EconomyService.pack_sizes(item):
		box.add_child(_buy_row(m, item, qty))
	if AdsService.is_rewarded_ready("booster"):
		var ad := UIKit.button(t.call("watch_ad_plus", {"count": int(EconomyService.rewarded_cfg("booster").get("item_qty", 1))}), "violet", "small")
		ad.pressed.connect(func() -> void: _watch_ad(m, ad, item))
		box.add_child(ad)
	else:
		AdsService.load_rewarded("booster")
	m.add_content(box)
	if rescue_rewind:
		m.add_action(t.call("rewind_free"), "rewind", "green", "small")
	m.add_action(t.call("shop"), "shop", "gold", "small")
	if rescue_restart:
		m.add_action(t.call("restart"), "restart", "cream", "small")
	m.add_action(t.call("cancel"), "dismiss", "cream", "small")
	AnalyticsService.track("booster_out", {"item": item, "level": 0})
	return m


static func _buy_row(m: ModalDialog, item: String, qty: int) -> Control:
	var price := EconomyService.price(item, qty)
	var b := UIKit.button("", "green", "small")
	var h := UIKit.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_child(UIKit.label("%s \u200e×%s" % [LocalizationService.t(item), LocalizationService.format_number(qty)], UITheme.FONT_BODY, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false))
	h.add_child(UIKit.texrect(ContentService.icon("coin", true), Vector2(22, 22)))
	h.add_child(UIKit.label(LocalizationService.format_number(price), UITheme.FONT_BODY, true, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false))
	b.add_child(h)
	b.disabled = not EconomyService.can_afford(item, qty)
	AccessibilityService.set_access_name(b, "%s ×%d, %s" % [LocalizationService.t(item), qty, LocalizationService.t("a11y_coins", {"count": price})])
	b.pressed.connect(func() -> void:
		if EconomyService.buy(item, qty):
			AudioService.play("coin")
			Router.toast(LocalizationService.t("booster_bought"))
			m.close("bought")
		else:
			Router.toast(LocalizationService.t("not_enough_coins")))
	return b


static func _watch_ad(m: ModalDialog, ad: Button, item: String) -> void:
	ad.disabled = true
	var gid := AdsService.next_grant_id("booster")
	var on_result := func(placement: String, status: String) -> void:
		if placement != "booster":
			return
		if status == "granted":
			if is_instance_valid(m):
				m.close("ad_granted")
		elif status in ["failed", "unavailable", "capped"]:
			Router.toast(LocalizationService.t("ad_unavailable"))
			if is_instance_valid(ad):
				ad.visible = false
		elif is_instance_valid(ad):
			ad.disabled = false
	AdsService.rewarded_result.connect(on_result, CONNECT_ONE_SHOT)
	AdsService.show_rewarded("booster", gid, EconomyService.grant.bind(gid, {item: int(EconomyService.rewarded_cfg("booster").get("item_qty", 1))}, "ad_booster"))
