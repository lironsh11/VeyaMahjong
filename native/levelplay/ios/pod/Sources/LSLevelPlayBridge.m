// LevelPlay ads + ATT for LiShi Mahjong on iOS (consent comes from the game's own dialog).
// iOS twin of native/levelplay/android/.../LevelPlayBannerPlugin.java; contract in
// docs/NATIVE_ADS_API.md. Written against IronSourceSDK 9.6 (LPM* API).
//
// Banner: added to the root view controller's view, centred, pinned to the bottom of the safe
// area (above the home indicator), adaptive width on phones and 320x50 on wide screens. The slot
// stays hidden until a real fill; banner_visibility reports its height in Godot window pixels.
// Meta is a LevelPlay bidder only; this class never loads Audience Network directly.
//
// Rewarded / interstitial: one ad object per ad unit id; ready flags are cached for synchronous
// queries; every show carries a token and its close/fail signal is emitted exactly once. The
// rewarded result is emitted ~600 ms after close so a reward delivered after close still counts.
// Nothing is granted natively and nothing reloads on its own (GDScript owns policy).

#import "LSLevelPlayBridge.h"

#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <IronSource/IronSource.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static const NSTimeInterval kRetrySeconds = 30.0;
static const NSTimeInterval kRewardSettleSeconds = 0.6;
/// Tablet width in points: keep the banner phone-sized there (same cutoff as Android's 600 dp).
static const CGFloat kWidePoints = 600.0;

static void LSRunOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

@class LSLevelPlayBridge;

@interface LSLevelPlayBridge ()
- (void)rewardedLoaded:(NSString *)unit;
- (void)rewardedLoadFailed:(NSString *)unit error:(NSError *)error;
- (void)rewardedEarned:(NSString *)unit;
- (void)rewardedDisplayFailed:(NSString *)unit;
- (void)rewardedClosed:(NSString *)unit;
- (void)interstitialLoaded:(NSString *)unit;
- (void)interstitialLoadFailed:(NSString *)unit error:(NSError *)error;
- (void)interstitialDisplayFailed:(NSString *)unit;
- (void)interstitialClosed:(NSString *)unit;
- (void)bannerLoaded;
- (void)bannerFailed;
@end

// --- per-ad delegates (LevelPlay holds delegates weakly; the bridge keeps these alive) -------

@interface LSRewardedListener : NSObject <LPMRewardedAdDelegate>
@property(nonatomic, copy) NSString *unit;
@property(nonatomic, weak) LSLevelPlayBridge *bridge;
@end

@implementation LSRewardedListener
- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
    [self.bridge rewardedLoaded:self.unit];
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    [self.bridge rewardedLoadFailed:self.unit error:error];
}
- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {
}
- (void)didRewardAdWithAdInfo:(LPMAdInfo *)adInfo reward:(LPMReward *)reward {
    [self.bridge rewardedEarned:self.unit];
}
- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
    [self.bridge rewardedDisplayFailed:self.unit];
}
- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
    [self.bridge rewardedClosed:self.unit];
}
@end

@interface LSInterstitialListener : NSObject <LPMInterstitialAdDelegate>
@property(nonatomic, copy) NSString *unit;
@property(nonatomic, weak) LSLevelPlayBridge *bridge;
@end

@implementation LSInterstitialListener
- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
    [self.bridge interstitialLoaded:self.unit];
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    [self.bridge interstitialLoadFailed:self.unit error:error];
}
- (void)didDisplayAdWithAdInfo:(LPMAdInfo *)adInfo {
}
- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
    [self.bridge interstitialDisplayFailed:self.unit];
}
- (void)didCloseAdWithAdInfo:(LPMAdInfo *)adInfo {
    [self.bridge interstitialClosed:self.unit];
}
@end

@interface LSBannerListener : NSObject <LPMBannerAdViewDelegate>
@property(nonatomic, weak) LSLevelPlayBridge *bridge;
@end

@implementation LSBannerListener
- (void)didLoadAdWithAdInfo:(LPMAdInfo *)adInfo {
    [self.bridge bannerLoaded];
}
- (void)didFailToLoadAdWithAdUnitId:(NSString *)adUnitId error:(NSError *)error {
    [self.bridge bannerFailed];
}
- (void)didFailToDisplayAdWithAdInfo:(LPMAdInfo *)adInfo error:(NSError *)error {
    [self.bridge bannerFailed];
}
@end

// --- bridge ---------------------------------------------------------------------------------

@implementation LSLevelPlayBridge {
    NSString *_appKey;
    NSString *_bannerUnit;
    BOOL _personalized;
    BOOL _enabled;
    BOOL _bannerWanted;
    BOOL _paused;
    BOOL _initStarted;
    BOOL _sdkReady;
    BOOL _bannerLoaded;
    NSMutableArray<dispatch_block_t> *_afterInit;

    UIView *_strip;
    LPMBannerAdView *_banner;
    LSBannerListener *_bannerListener;
    NSInteger _bannerHeightPx;
    NSUInteger _retryGeneration;

    NSMutableDictionary<NSString *, LPMRewardedAd *> *_rewardedAds;
    NSMutableDictionary<NSString *, LSRewardedListener *> *_rewardedListeners;
    NSMutableDictionary<NSString *, LPMInterstitialAd *> *_interstitialAds;
    NSMutableDictionary<NSString *, LSInterstitialListener *> *_interstitialListeners;
    NSMutableDictionary<NSString *, NSNumber *> *_rewardedReady;
    NSMutableDictionary<NSString *, NSNumber *> *_interstitialReady;
    /// Ad unit id -> token of the ad currently on screen (or about to be).
    NSMutableDictionary<NSString *, NSNumber *> *_rewardedToken;
    NSMutableDictionary<NSString *, NSNumber *> *_interstitialToken;
    NSMutableSet<NSNumber *> *_earnedTokens;
    NSMutableSet<NSNumber *> *_finishedTokens;
    BOOL _fullscreenShowing;

    BOOL _trackingWaitingForActive;
}

+ (instancetype)shared {
    static LSLevelPlayBridge *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[LSLevelPlayBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _appKey = @"";
        _bannerUnit = @"";
        _enabled = YES;
        _afterInit = [NSMutableArray array];
        _rewardedAds = [NSMutableDictionary dictionary];
        _rewardedListeners = [NSMutableDictionary dictionary];
        _interstitialAds = [NSMutableDictionary dictionary];
        _interstitialListeners = [NSMutableDictionary dictionary];
        _rewardedReady = [NSMutableDictionary dictionary];
        _interstitialReady = [NSMutableDictionary dictionary];
        _rewardedToken = [NSMutableDictionary dictionary];
        _interstitialToken = [NSMutableDictionary dictionary];
        _earnedTokens = [NSMutableSet set];
        _finishedTokens = [NSMutableSet set];
    }
    return self;
}

#pragma mark - events

/// Always asynchronous on the main queue, so a GDScript call never re-enters GDScript.
- (void)emit:(NSString *)signal args:(NSArray *)args {
    dispatch_async(dispatch_get_main_queue(), ^{
        LSLevelPlayEventHandler handler = self.eventHandler;
        if (handler) {
            handler(signal, args);
        }
    });
}

- (void)reportBanner:(BOOL)visible height:(NSInteger)heightPx {
    [self emit:@"banner_visibility" args:@[ visible ? @YES : @NO, @(heightPx) ]];
}

#pragma mark - view controllers

- (UIWindow *)hostWindow {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
            if (fallback == nil && window.rootViewController != nil) {
                fallback = window;
            }
        }
    }
    if (fallback == nil) {
        id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
        if ([delegate respondsToSelector:@selector(window)]) {
            fallback = delegate.window;
        }
    }
    return fallback;
}

- (UIViewController *)rootViewController {
    return [self hostWindow].rootViewController;
}

/// The view controller to present full-screen content from (topmost presented one).
- (UIViewController *)presentingViewController {
    UIViewController *vc = [self rootViewController];
    while (vc.presentedViewController != nil && !vc.presentedViewController.isBeingDismissed) {
        vc = vc.presentedViewController;
    }
    return vc;
}

#pragma mark - banner (existing API)

- (void)startWithAppKey:(NSString *)appKey bannerAdUnitId:(NSString *)adUnitId personalized:(BOOL)personalized {
    LSRunOnMain(^{
        self->_appKey = appKey ?: @"";
        self->_bannerUnit = adUnitId ?: @"";
        self->_personalized = personalized;
        self->_enabled = YES;
        self->_bannerWanted = YES;
        [self ensureInit:^{
            [self ensureBanner];
        }];
    });
}

- (void)setPersonalized:(BOOL)personalized {
    LSRunOnMain(^{
        self->_personalized = personalized;
        if (self->_sdkReady) {
            [LPMPrivacySettings setGDPRConsent:personalized];
        }
    });
}

- (void)setEnabled:(BOOL)enabled {
    LSRunOnMain(^{
        self->_enabled = enabled;
        if (!enabled) {
            [self destroyBanner];
            [self reportBanner:NO height:0];
            return;
        }
        [self ensureInit:^{
            [self ensureBanner];
        }];
    });
}

- (void)pause {
    LSRunOnMain(^{
        self->_paused = YES;
        self->_retryGeneration++;
        [self->_banner pauseAutoRefresh];
    });
}

- (void)resume {
    LSRunOnMain(^{
        self->_paused = NO;
        if (!self->_enabled) {
            return;
        }
        if (self->_banner != nil) {
            [self->_banner resumeAutoRefresh];
            if (self->_sdkReady && !self->_bannerLoaded) {
                [self loadBanner];
            }
        } else {
            [self ensureInit:^{
                [self ensureBanner];
            }];
        }
    });
}

#pragma mark - shared SDK init

- (void)initSdkWithAppKey:(NSString *)appKey personalized:(BOOL)personalized {
    LSRunOnMain(^{
        if (appKey.length > 0) {
            self->_appKey = appKey;
        }
        self->_personalized = personalized;
        [self ensureInit:^{
            [self emit:@"sdk_ready" args:@[]];
        }];
    });
}

/// Runs onReady once the SDK is initialised (immediately if it already is). Main thread.
- (void)ensureInit:(dispatch_block_t)onReady {
    if (_sdkReady) {
        onReady();
        return;
    }
    [_afterInit addObject:[onReady copy]];
    if (_initStarted || _appKey.length == 0) {
        return;
    }
    _initStarted = YES;
    [LPMPrivacySettings setGDPRConsent:_personalized];
    // Meta reads the ATT state itself on recent iOS; keep the legacy flag in sync before init.
    [self applyMetaTrackingFlag];
    LPMInitRequestBuilder *builder = [[LPMInitRequestBuilder alloc] initWithAppKey:_appKey];
    LPMInitRequest *request = [builder build];
    __weak LSLevelPlayBridge *weakSelf = self;
    [LevelPlay initWithRequest:request
                    completion:^(LPMConfiguration *_Nullable config, NSError *_Nullable error) {
                        LSRunOnMain(^{
                            LSLevelPlayBridge *strongSelf = weakSelf;
                            if (strongSelf == nil) {
                                return;
                            }
                            if (error != nil) {
                                [strongSelf initFailed:error.localizedDescription];
                            } else {
                                [strongSelf initSucceeded];
                            }
                        });
                    }];
}

- (void)initFailed:(NSString *)message {
    _initStarted = NO;
    [self emit:@"init_failed" args:@[ message.length > 0 ? message : @"init failed" ]];
    __weak LSLevelPlayBridge *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetrySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf ensureInit:^{
        }];
    });
}

- (void)initSucceeded {
    _sdkReady = YES;
    [LPMPrivacySettings setGDPRConsent:_personalized];
    NSArray<dispatch_block_t> *pending = [_afterInit copy];
    [_afterInit removeAllObjects];
    for (dispatch_block_t block in pending) {
        block();
    }
}

#pragma mark - rewarded

- (void)loadRewarded:(NSString *)adUnitId {
    if (adUnitId.length == 0) {
        return;
    }
    LSRunOnMain(^{
        [self ensureInit:^{
            [[self rewardedAd:adUnitId] loadAd];
        }];
    });
}

- (BOOL)isRewardedReady:(NSString *)adUnitId {
    @synchronized(_rewardedReady) {
        return [_rewardedReady[adUnitId ?: @""] boolValue];
    }
}

- (void)setReady:(NSMutableDictionary<NSString *, NSNumber *> *)map unit:(NSString *)unit value:(BOOL)value {
    @synchronized(map) {
        map[unit] = @(value);
    }
}

- (void)showRewarded:(NSString *)adUnitId placement:(NSString *)placementName token:(int64_t)token {
    LSRunOnMain(^{
        NSString *unit = adUnitId ?: @"";
        LPMRewardedAd *ad = self->_rewardedAds[unit];
        UIViewController *vc = [self presentingViewController];
        if (vc == nil || ad == nil || ![ad isAdReady] || self->_fullscreenShowing) {
            [self emit:@"rewarded_show_failed" args:@[ @(token), unit ]];
            return;
        }
        self->_rewardedToken[unit] = @(token);
        [self setReady:self->_rewardedReady unit:unit value:NO];
        self->_fullscreenShowing = YES;
        [ad showAdWithViewController:vc placementName:(placementName.length > 0 ? placementName : nil)];
    });
}

- (LPMRewardedAd *)rewardedAd:(NSString *)unit {
    LPMRewardedAd *ad = _rewardedAds[unit];
    if (ad != nil) {
        return ad;
    }
    ad = [[LPMRewardedAd alloc] initWithAdUnitId:unit];
    LSRewardedListener *listener = [[LSRewardedListener alloc] init];
    listener.unit = unit;
    listener.bridge = self;
    [ad setDelegate:listener];
    _rewardedAds[unit] = ad;
    _rewardedListeners[unit] = listener;
    return ad;
}

- (void)rewardedLoaded:(NSString *)unit {
    [self setReady:_rewardedReady unit:unit value:YES];
    [self emit:@"rewarded_loaded" args:@[ unit ]];
}

- (void)rewardedLoadFailed:(NSString *)unit error:(NSError *)error {
    [self setReady:_rewardedReady unit:unit value:NO];
    [self emit:@"rewarded_load_failed" args:@[ unit, @(error != nil ? (int64_t)error.code : -1) ]];
}

- (void)rewardedEarned:(NSString *)unit {
    LSRunOnMain(^{
        NSNumber *token = self->_rewardedToken[unit];
        if (token != nil) {
            [self->_earnedTokens addObject:token];
        }
    });
}

- (void)rewardedDisplayFailed:(NSString *)unit {
    LSRunOnMain(^{
        self->_fullscreenShowing = NO;
        NSNumber *token = self->_rewardedToken[unit];
        [self->_rewardedToken removeObjectForKey:unit];
        if (token != nil && ![self->_finishedTokens containsObject:token]) {
            [self->_finishedTokens addObject:token];
            [self emit:@"rewarded_show_failed" args:@[ token, unit ]];
        }
    });
}

- (void)rewardedClosed:(NSString *)unit {
    LSRunOnMain(^{
        self->_fullscreenShowing = NO;
        NSNumber *token = self->_rewardedToken[unit];
        if (token == nil) {
            return;
        }
        // Some networks deliver the reward just after close: wait briefly, then emit once.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRewardSettleSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self->_finishedTokens containsObject:token]) {
                return;
            }
            [self->_finishedTokens addObject:token];
            if ([token isEqualToNumber:(self->_rewardedToken[unit] ?: @(-1))]) {
                [self->_rewardedToken removeObjectForKey:unit];
            }
            BOOL earned = [self->_earnedTokens containsObject:token];
            [self->_earnedTokens removeObject:token];
            [self emit:@"rewarded_closed" args:@[ token, earned ? @YES : @NO, unit ]];
        });
    });
}

#pragma mark - interstitial

- (void)loadInterstitial:(NSString *)adUnitId {
    if (adUnitId.length == 0) {
        return;
    }
    LSRunOnMain(^{
        [self ensureInit:^{
            [[self interstitialAd:adUnitId] loadAd];
        }];
    });
}

- (BOOL)isInterstitialReady:(NSString *)adUnitId {
    @synchronized(_interstitialReady) {
        return [_interstitialReady[adUnitId ?: @""] boolValue];
    }
}

- (void)showInterstitial:(NSString *)adUnitId placement:(NSString *)placementName token:(int64_t)token {
    LSRunOnMain(^{
        NSString *unit = adUnitId ?: @"";
        LPMInterstitialAd *ad = self->_interstitialAds[unit];
        UIViewController *vc = [self presentingViewController];
        if (vc == nil || ad == nil || ![ad isAdReady] || self->_fullscreenShowing) {
            [self emit:@"interstitial_show_failed" args:@[ @(token), unit ]];
            return;
        }
        self->_interstitialToken[unit] = @(token);
        [self setReady:self->_interstitialReady unit:unit value:NO];
        self->_fullscreenShowing = YES;
        [ad showAdWithViewController:vc placementName:(placementName.length > 0 ? placementName : nil)];
    });
}

- (LPMInterstitialAd *)interstitialAd:(NSString *)unit {
    LPMInterstitialAd *ad = _interstitialAds[unit];
    if (ad != nil) {
        return ad;
    }
    ad = [[LPMInterstitialAd alloc] initWithAdUnitId:unit];
    LSInterstitialListener *listener = [[LSInterstitialListener alloc] init];
    listener.unit = unit;
    listener.bridge = self;
    [ad setDelegate:listener];
    _interstitialAds[unit] = ad;
    _interstitialListeners[unit] = listener;
    return ad;
}

- (void)interstitialLoaded:(NSString *)unit {
    [self setReady:_interstitialReady unit:unit value:YES];
    [self emit:@"interstitial_loaded" args:@[ unit ]];
}

- (void)interstitialLoadFailed:(NSString *)unit error:(NSError *)error {
    [self setReady:_interstitialReady unit:unit value:NO];
    [self emit:@"interstitial_load_failed" args:@[ unit, @(error != nil ? (int64_t)error.code : -1) ]];
}

- (void)interstitialDisplayFailed:(NSString *)unit {
    LSRunOnMain(^{
        self->_fullscreenShowing = NO;
        NSNumber *token = self->_interstitialToken[unit];
        [self->_interstitialToken removeObjectForKey:unit];
        if (token != nil && ![self->_finishedTokens containsObject:token]) {
            [self->_finishedTokens addObject:token];
            [self emit:@"interstitial_show_failed" args:@[ token, unit ]];
        }
    });
}

- (void)interstitialClosed:(NSString *)unit {
    LSRunOnMain(^{
        self->_fullscreenShowing = NO;
        NSNumber *token = self->_interstitialToken[unit];
        [self->_interstitialToken removeObjectForKey:unit];
        if (token != nil && ![self->_finishedTokens containsObject:token]) {
            [self->_finishedTokens addObject:token];
            [self emit:@"interstitial_closed" args:@[ token ]];
        }
    });
}

#pragma mark - test suite and metadata

- (void)setTestSuiteEnabled:(BOOL)enabled {
    // Must run before LevelPlay init.
    [LevelPlay setMetaDataWithKey:@"is_test_suite" value:(enabled ? @"enable" : @"disable")];
}

- (void)launchTestSuite {
    LSRunOnMain(^{
        UIViewController *vc = [self presentingViewController];
        if (vc != nil && self->_sdkReady) {
            [LevelPlay launchTestSuite:vc];
        }
    });
}

- (void)setMetadataKey:(NSString *)key value:(NSString *)value {
    if (key.length > 0 && value != nil) {
        [LevelPlay setMetaDataWithKey:key value:value];
    }
}

#pragma mark - privacy helpers

- (NSString *)deviceTimeZone {
    // IANA zone id such as "Europe/Berlin" (the game's consent dialog only shows in Europe/UK).
    return NSTimeZone.localTimeZone.name ?: @"";
}

#pragma mark - tracking (ATT)

- (void)requestTrackingAuthorization {
    LSRunOnMain(^{
        if (@available(iOS 14, *)) {
            // The system ignores the request unless the app is active (e.g. during launch).
            if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
                if (!self->_trackingWaitingForActive) {
                    self->_trackingWaitingForActive = YES;
                    [[NSNotificationCenter defaultCenter] addObserver:self
                                                             selector:@selector(appBecameActiveForTracking:)
                                                                 name:UIApplicationDidBecomeActiveNotification
                                                               object:nil];
                }
                return;
            }
            [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
                LSRunOnMain(^{
                    [self applyMetaTrackingFlag];
                    [self emit:@"tracking_result" args:@[ [self trackingStatusName:status] ]];
                });
            }];
        } else {
            [self emit:@"tracking_result" args:@[ @"authorized" ]];
        }
    });
}

- (void)appBecameActiveForTracking:(NSNotification *)note {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    _trackingWaitingForActive = NO;
    [self requestTrackingAuthorization];
}

- (NSString *)trackingStatusName:(ATTrackingManagerAuthorizationStatus)status {
    switch (status) {
        case ATTrackingManagerAuthorizationStatusAuthorized:
            return @"authorized";
        case ATTrackingManagerAuthorizationStatusDenied:
            return @"denied";
        case ATTrackingManagerAuthorizationStatusRestricted:
            return @"restricted";
        default:
            return @"not_determined";
    }
}

/// Meta Audience Network: FBAdSettings.setAdvertiserTrackingEnabled(status == authorized).
/// Called through the runtime so the bridge neither links nor imports FBAudienceNetwork (it
/// arrives through the LevelPlay Meta adapter pod) and keeps working if Meta removes the
/// deprecated method.
- (void)applyMetaTrackingFlag {
    BOOL authorized = YES;
    if (@available(iOS 14, *)) {
        authorized = ATTrackingManager.trackingAuthorizationStatus == ATTrackingManagerAuthorizationStatusAuthorized;
    }
    Class settings = NSClassFromString(@"FBAdSettings");
    SEL selector = NSSelectorFromString(@"setAdvertiserTrackingEnabled:");
    if (settings != nil && [settings respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(settings, selector, authorized);
    }
}

#pragma mark - banner internals

- (CGFloat)pixelScale:(UIView *)view {
    // Godot 4.7 reports window/safe-area pixels as points * UIScreen.scale (not nativeScale),
    // so report the banner height the same way.
    CGFloat scale = view.window.screen.scale;
    if (scale < 1.0) {
        scale = view.traitCollection.displayScale;
    }
    return scale >= 1.0 ? scale : 1.0;
}

- (void)ensureBanner {
    if (!_bannerWanted || !_enabled || _paused || !_sdkReady || _banner != nil || _bannerUnit.length == 0) {
        return;
    }
    UIViewController *root = [self rootViewController];
    UIView *host = root.view;
    if (host == nil) {
        return;
    }
    CGFloat widthPoints = host.bounds.size.width;
    BOOL wide = widthPoints >= kWidePoints;
    LPMAdSize *size = nil;
    if (!wide) {
        size = [LPMAdSize createAdaptiveAdSize];  // nil before init; we are after init here
    }
    if (size == nil) {
        size = [LPMAdSize bannerSize];
    }
    _bannerHeightPx = MAX(1, (NSInteger)lround((CGFloat)size.height * [self pixelScale:host]));

    _strip = [[UIView alloc] init];
    _strip.translatesAutoresizingMaskIntoConstraints = NO;
    _strip.hidden = YES;
    _strip.backgroundColor = UIColor.clearColor;
    [host addSubview:_strip];
    [NSLayoutConstraint activateConstraints:@[
        [_strip.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor],
        [_strip.centerXAnchor constraintEqualToAnchor:host.centerXAnchor],
        [_strip.widthAnchor constraintEqualToConstant:(CGFloat)size.width],
        [_strip.heightAnchor constraintEqualToConstant:(CGFloat)size.height],
    ]];

    LPMBannerAdViewConfigBuilder *builder = [[LPMBannerAdViewConfigBuilder alloc] init];
    [builder setWithAdSize:size];
    _banner = [[LPMBannerAdView alloc] initWithAdUnitId:_bannerUnit config:[builder build]];
    _bannerListener = [[LSBannerListener alloc] init];
    _bannerListener.bridge = self;
    [_banner setDelegate:_bannerListener];
    _banner.translatesAutoresizingMaskIntoConstraints = NO;
    [_strip addSubview:_banner];
    [NSLayoutConstraint activateConstraints:@[
        [_banner.leadingAnchor constraintEqualToAnchor:_strip.leadingAnchor],
        [_banner.trailingAnchor constraintEqualToAnchor:_strip.trailingAnchor],
        [_banner.topAnchor constraintEqualToAnchor:_strip.topAnchor],
        [_banner.bottomAnchor constraintEqualToAnchor:_strip.bottomAnchor],
    ]];
    [_banner loadAdWithViewController:root];
}

- (void)loadBanner {
    if (_banner != nil && _enabled && !_paused) {
        [_banner loadAdWithViewController:[self rootViewController]];
    }
}

- (void)bannerLoaded {
    LSRunOnMain(^{
        self->_bannerLoaded = YES;
        self->_retryGeneration++;
        if (self->_strip == nil) {
            return;
        }
        self->_strip.hidden = NO;
        [self reportBanner:YES height:self->_bannerHeightPx];
    });
}

- (void)bannerFailed {
    LSRunOnMain(^{
        self->_bannerLoaded = NO;
        self->_strip.hidden = YES;
        [self reportBanner:NO height:0];
        [self scheduleBannerRetry];
    });
}

- (void)scheduleBannerRetry {
    if (!_enabled || _paused) {
        return;
    }
    NSUInteger generation = ++_retryGeneration;
    __weak LSLevelPlayBridge *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetrySeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LSLevelPlayBridge *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_retryGeneration == generation) {
            [strongSelf loadBanner];
        }
    });
}

- (void)destroyBanner {
    _retryGeneration++;
    _bannerLoaded = NO;
    if (_banner != nil) {
        [_banner destroy];
        [_banner removeFromSuperview];
        _banner = nil;
    }
    _bannerListener = nil;
    if (_strip != nil) {
        [_strip removeFromSuperview];
        _strip = nil;
    }
}

@end
