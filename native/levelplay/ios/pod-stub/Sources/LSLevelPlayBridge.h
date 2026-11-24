// LevelPlay ads + ATT for LiShi Mahjong on iOS (consent comes from the game's own dialog).
//
// Pure Objective-C (no Godot headers): compiled by CocoaPods as the local pod `LiShiLevelPlay`,
// which also pulls IronSourceSDK. The Godot glue
// (native/levelplay/ios/godot/) owns the `LevelPlayBanner` singleton, forwards every method here
// and turns events into Godot signals. Contract: docs/NATIVE_ADS_API.md.
//
// All methods may be called from any thread; work hops to the main thread. Events are delivered
// asynchronously on the main thread as (signal name, args) where args holds NSString and
// NSNumber values. Booleans are @YES / @NO (CFBoolean) so the glue can tell them from ints.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LSLevelPlayEventHandler)(NSString *signal, NSArray *args);

@interface LSLevelPlayBridge : NSObject

+ (instancetype)shared;

@property(nonatomic, copy, nullable) LSLevelPlayEventHandler eventHandler;

// Banner (existing API).
- (void)startWithAppKey:(NSString *)appKey bannerAdUnitId:(NSString *)adUnitId personalized:(BOOL)personalized;
- (void)setPersonalized:(BOOL)personalized;
- (void)setEnabled:(BOOL)enabled;
- (void)pause;
- (void)resume;

// Shared SDK init.
- (void)initSdkWithAppKey:(NSString *)appKey personalized:(BOOL)personalized;

// Rewarded.
- (void)loadRewarded:(NSString *)adUnitId;
- (BOOL)isRewardedReady:(NSString *)adUnitId;
- (void)showRewarded:(NSString *)adUnitId placement:(NSString *)placementName token:(int64_t)token;

// Interstitial.
- (void)loadInterstitial:(NSString *)adUnitId;
- (BOOL)isInterstitialReady:(NSString *)adUnitId;
- (void)showInterstitial:(NSString *)adUnitId placement:(NSString *)placementName token:(int64_t)token;

// Test suite and metadata.
- (void)setTestSuiteEnabled:(BOOL)enabled;
- (void)launchTestSuite;
- (void)setMetadataKey:(NSString *)key value:(NSString *)value;

// Privacy helpers and tracking (ATT).
- (NSString *)deviceTimeZone;
- (void)requestTrackingAuthorization;

@end

NS_ASSUME_NONNULL_END
