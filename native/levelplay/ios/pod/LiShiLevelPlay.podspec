Pod::Spec.new do |s|
  s.name             = 'LiShiLevelPlay'
  s.version          = '1.0.0'
  s.summary          = 'LevelPlay / ATT bridge used by the LevelPlayBanner Godot iOS plugin.'
  s.description      = 'Objective-C implementation of docs/NATIVE_ADS_API.md, driven by the Godot glue in ios/plugins/LevelPlayBanner.'
  s.homepage         = 'https://example.invalid/lishi-mahjong'
  s.license          = { :type => 'Proprietary', :text => 'Part of LiShi Mahjong.' }
  s.author           = 'LiShi Mahjong'
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.source_files     = 'Sources/**/*.{h,m}'
  s.public_header_files = 'Sources/LSLevelPlayBridge.h'
  s.frameworks       = 'UIKit', 'Foundation', 'AppTrackingTransparency'
  s.requires_arc     = true
  s.static_framework = true

  # Keep in step with native/levelplay/android/build.gradle (LevelPlay 9.x).
  s.dependency 'IronSourceSDK', '~> 9.6'
end
