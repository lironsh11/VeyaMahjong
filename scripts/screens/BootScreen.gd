extends Screen
## Splash / loading. Verifies content loaded, shows a retry state on failure, asks for ads
## consent once on Europe/UK devices, then routes to the interactive tutorial (first run) or
## Home. Kept deliberately short.

const MIN_SHOW_S := 0.6

var _status: Label
var _retry: Button


func build_background() -> void:
	# Same art as the store splash; softened so the tagline and status stay readable.
	UIKit.fullscreen_bg(self, ContentService.world_bg("aurora_garden", "world", AccessibilityService.low_profile), 0.35, UITheme.IVORY)


func build() -> void:
	var v := UIKit.vbox(18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	safe.add_child(v)
	var logo := UIKit.texrect(ContentService.art("branding/logo_ornate_large.png"), Vector2(320, 200))
	v.add_child(logo)
	v.add_child(UIKit.label(t("app_tagline"), UITheme.FONT_H2, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER))
	_status = UIKit.label(t("loading"), UITheme.FONT_BODY, false, UITheme.text_soft(), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_status)
	_retry = UIKit.button(t("retry"), "green", "large", _start)
	_retry.visible = false
	v.add_child(_retry)
	_start.call_deferred()


func _start() -> void:
	_retry.visible = false
	_status.text = t("loading")
	var t0 := Time.get_ticks_msec()
	if ContentService.level_count() == 0:
		ContentService.load_content()
	if ContentService.level_count() == 0 or ContentService.get_level(1) == null:
		_status.text = t("error_content")
		_retry.visible = true
		AnalyticsService.track("error_nonfatal", {"code": "content_load"})
		return
	if SaveService.last_load_source in ["tmp", "bak"]:
		Router.toast(t("save_recovered"), 3.0)
	if not bool(GameState.data.get("first_open_logged", false)):
		GameState.data.first_open_logged = true
		AnalyticsService.track("first_open")
		GameState.request_save()
	var wait := MIN_SHOW_S - (Time.get_ticks_msec() - t0) / 1000.0
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	if PrivacyService.needs_ads_consent_prompt():
		# Europe/UK only, once: the answer is recorded by the dialog itself.
		await ConsentDialog.open(self).closed
	if not bool(GameState.data.get("tutorial_done", false)):
		Router.replace("tutorial")
	else:
		Router.replace("home")
