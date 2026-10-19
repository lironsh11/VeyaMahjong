Pod::Spec.new do |s|
  # Not "LiShiStoreKit": that is the Godot xcframework (libLiShiStoreKit.a), which only
  # calls lishi_sk_*. A pod with the same product name makes ld open that archive for
  # -lLiShiStoreKit / -framework LiShiStoreKit and never the Swift objects that define them.
  s.name             = 'LiShiStoreKitBridge'
  s.version          = '1.0.0'
  s.summary          = 'StoreKit 2 bridge used by the LiShiStoreKit Godot iOS plugin.'
  s.description      = 'Swift StoreKit 2 code exposed as C functions (lishi_sk_*) to the Godot glue in ios/plugins/LiShiStoreKit.'
  s.homepage         = 'https://example.invalid/lishi-mahjong'
  s.license          = { :type => 'Proprietary', :text => 'Part of LiShi Mahjong.' }
  s.author           = 'LiShi Mahjong'
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.source_files     = 'Sources/**/*.swift'
  s.frameworks       = 'StoreKit', 'Foundation'
  s.static_framework = true
end
