# iOS build

## Status (2026-10-18)

| Step | Result |
|---|---|
| iOS preset (`iOS`, Xcode project only) | Configured: bundle id `com.veyamahjong.app` (**placeholder**, owner must approve), min iOS 14.0, arm64, 1024 px icon from the pack, ivory launch background |
| Export with the real (empty) Team ID | **BLOCKED.** Godot refuses: "App Store Team ID not specified" |
| Pipeline check with an obviously fake placeholder Team ID, project-only export | **PASS.** Godot generated `VeyaMahjong.xcodeproj`, the `.pck`, the engine xcframeworks and `PrivacyInfo.xcprivacy`. The output was deleted and the preset reverted to an empty Team ID, so no placeholder credential remains |
| Xcode build, signing, simulator/device run, TestFlight | **NOT POSSIBLE HERE.** Requires macOS, Xcode 26+ (iOS 26 SDK; iOS 27 SDK from April 2027), an Apple Developer account and provisioning |

No iOS binary was built or signed. No IPA exists.

## Steps on a Mac (owner)

1. Install Godot 4.7.x + export templates and Xcode 26 or later.
2. Set `application/app_store_team_id` (Editor → Project → Export → iOS) and the bundle identifier.
   Keep signing identities and profiles out of git.
3. Export the project (`--export-debug "iOS"` with export_project_only, or uncheck it to let Godot
   build the IPA), open `VeyaMahjong.xcodeproj`, choose the team and run on a device.
4. Review `PrivacyInfo.xcprivacy` (required-reason APIs) and App Privacy answers ("Data Not
   Collected" for this build).
5. Archive and upload to App Store Connect, then test via TestFlight (internal, then external).
6. In-app purchases: no iOS store adapter is implemented yet (see MONETIZATION.md). The Shop
   shows its honest "not available" state on iOS.

## iOS-specific QA to run

Safe areas (notch, Dynamic Island, home indicator), audio interruption (call, Siri, headphone
unplug), background/foreground saving, haptics (`Input.vibrate_handheld` on iPhone), CJK and
Hebrew rendering with system fonts, VoiceOver behaviour (see QA_MATRIX accessibility notes),
iPad layout (portrait; the 4:3 layout was verified on desktop at 720×960).
