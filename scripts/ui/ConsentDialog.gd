class_name ConsentDialog
extends RefCounted
## The game's own ads consent dialog (no Google UMP). Shown once at first launch on Europe/UK
## devices (PrivacyService.needs_ads_consent_prompt) and from Settings > Privacy choices for
## everyone. Accept and decline are equally prominent; either answer is recorded and the game
## plays the same. The privacy policy opens without closing the dialog.
##
## closed results: obtained | denied | dismiss (Settings only)

static func open(parent: Node, from_settings: bool = false) -> ModalDialog:
	var t := LocalizationService.t
	var m := ModalDialog.open(parent, t.call("consent_title"), t.call("consent_body"), from_settings)
	if from_settings:
		var state := "consent_state_on" if PrivacyService.ads_consent() in ["obtained", "not_required"] else "consent_state_off"
		var current := UIKit.label(t.call(state), UITheme.FONT_SMALL, true, null, HORIZONTAL_ALIGNMENT_CENTER)
		current.custom_minimum_size.x = 380
		m.add_content(current)
	if PrivacyService.url("privacy_policy") != "":
		m.add_content(UIKit.button(t.call("privacy_policy"), "cream", "small", func() -> void: PrivacyService.open("privacy_policy")))
	m.add_action(t.call("consent_accept"), "obtained", "green", "large")
	m.add_action(t.call("consent_decline"), "denied", "cream", "large")
	if from_settings:
		m.add_action(t.call("cancel"), "dismiss", "cream", "small")
	m.closed.connect(func(result: String) -> void:
		if result in ["obtained", "denied"]:
			PrivacyService.record_ads_consent(result)
			AnalyticsService.track("ads_consent", {"status": result}))
	return m
