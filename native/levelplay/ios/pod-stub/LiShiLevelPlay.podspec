Pod::Spec.new do |s|
  s.name             = 'LiShiLevelPlay'
  s.version          = '1.0.0'
  s.summary          = 'Stub LevelPlay / ATT bridge for Appetize (no IronSource).'
  s.description      = 'No-op ads implementation so the x86_64 Godot simulator template can link without LevelPlay, which has no x86_64 simulator slice.'
  s.homepage         = 'https://mahjong.bylishi.com/'
  s.license          = { :type => 'Proprietary', :text => 'Part of LiShi Mahjong.' }
  s.author           = 'LiShi Mahjong'
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.source_files     = 'Sources/**/*.{h,m}'
  s.public_header_files = 'Sources/LSLevelPlayBridge.h'
  s.frameworks       = 'UIKit', 'Foundation', 'AppTrackingTransparency'
  s.requires_arc     = true
  s.static_framework = true
  # Intentionally no IronSourceSDK / Meta dependency.
end
