extends Screen
## Tile theme gallery with real tile previews and Locked / Unlocked / Equipped states.
## Equipping applies immediately (next board render) and persists across launches.

const PREVIEW_FACES := ["dragon_red", "circle_5", "bamboo_1", "flower_plum"]


func build_background() -> void:
	UIKit.fullscreen_bg(self, ContentService.world_bg("aurora_garden", "gameplay", AccessibilityService.low_profile), 0.1, Color.WHITE)


func build() -> void:
	var root := UIKit.vbox(10)
	safe.add_child(root)
	root.add_child(UIKit.header(t("tile_collections"), func() -> void: Router.back(), true))
	var list := UIKit.vbox(12)
	root.add_child(UIKit.scroll(list))
	var equipped := ProgressionService.equipped_theme()
	for th in ContentService.themes():
		list.add_child(_theme_card(str(th.id), equipped))
	# Bloom summary (the other collectible)
	var p := UIKit.panel("CardFlat")
	var h := UIKit.hbox(10)
	p.add_child(h)
	h.add_child(UIKit.texrect(ContentService.tex("ui/rewards/flower.png"), Vector2(48, 48)))
	var lbl := UIKit.label(t("discoveries_found", {"found": ProgressionService.discoveries_unlocked_count(), "total": ContentService.all_discoveries().size()}), UITheme.FONT_BODY, true)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(lbl)
	h.add_child(UIKit.button(t("open"), "gold", "small", func() -> void: Router.go("bloom")))
	list.add_child(p)
	root.add_child(UIKit.bottom_nav("collection"))


func _theme_card(theme_id: String, equipped: String) -> Control:
	var unlocked := ProgressionService.is_theme_unlocked(theme_id)
	var is_eq := theme_id == equipped
	var p := UIKit.panel("Card")
	var v := UIKit.vbox(8)
	p.add_child(v)
	var top := UIKit.hbox(8)
	var name_l := UIKit.label(t("theme_" + theme_id), UITheme.FONT_H2, true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	if is_eq:
		top.add_child(UIKit.chip(t("equipped"), UITheme.GREEN))
	elif unlocked:
		top.add_child(UIKit.chip(t("unlocked"), UITheme.TEAL.darkened(0.15)))
	else:
		top.add_child(UIKit.chip(t("locked"), UITheme.NAVY_SOFT))
	v.add_child(top)
	var tiles_row := UIKit.hbox(6)
	tiles_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles_row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	for f in PREVIEW_FACES:
		var tr := UIKit.texrect(ContentService.tile_texture(theme_id, f, false), Vector2(64, 82))
		if not unlocked:
			tr.modulate = Color(1, 1, 1, 0.55)
		tiles_row.add_child(tr)
	v.add_child(tiles_row)
	if is_eq:
		pass
	elif unlocked:
		v.add_child(UIKit.button(t("equip"), "green", "small", func() -> void:
			if ProgressionService.equip_theme(theme_id):
				AudioService.play("reward")
				Router.toast(t("theme_equipped", {"name": t("theme_" + theme_id)}))
				_rebuild()))
	else:
		v.add_child(UIKit.label(ProgressionService.theme_unlock_hint(theme_id), UITheme.FONT_SMALL, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	return p
