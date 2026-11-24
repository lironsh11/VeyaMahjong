// Appetize / x86_64 simulator stub: same LSLevelPlayBridge API, no IronSource.
// Real ads stay in native/levelplay/ios/pod. ATT still works so PrivacyService can run.

#import "LSLevelPlayBridge.h"

#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <UIKit/UIKit.h>

@implementation LSLevelPlayBridge {
    BOOL _personalized;
}

+ (instancetype)shared {
    static LSLevelPlayBridge *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[LSLevelPlayBridge alloc] init];
    });
    return instance;
}

- (void)emit:(NSString *)signal args:(NSArray *)args {
    LSLevelPlayEventHandler handler = self.eventHandler;
    if (handler == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(signal, args ?: @[]);
    });
}

- (void)startWithAppKey:(NSString *)appKey bannerAdUnitId:(NSString *)adUnitId personalized:(BOOL)personalized {
    (void)appKey;
    (void)adUnitId;
    _personalized = personalized;
    [self emit:@"init_failed" args:@[ @"ads stubbed for Appetize simulator" ]];
}

- (void)setPersonalized:(BOOL)personalized {
    _personalized = personalized;
}

- (void)setEnabled:(BOOL)enabled {
    (void)enabled;
}

- (void)pause {
}

- (void)resume {
}

- (void)initSdkWithAppKey:(NSString *)appKey personalized:(BOOL)personalized {
    (void)appKey;
    _personalized = personalized;
    [self emit:@"init_failed" args:@[ @"ads stubbed for Appetize simulator" ]];
}

- (void)loadRewarded:(NSString *)adUnitId {
    [self emit:@"rewarded_load_failed" args:@[ adUnitId ?: @"", @(-1) ]];
}

- (BOOL)isRewardedReady:(NSString *)adUnitId {
    (void)adUnitId;
    return NO;
}

- (void)showRewarded:(NSString *)adUnitId placement:(NSString *)placementName token:(int64_t)token {
    (void)placementName;
    [self emit:@"rewarded_show_failed" args:@[ @(token), adUnitId ?: @"" ]];
}

- (void)loadInterstitial:(NSString *)adUnitId {
    [self emit:@"interstitial_load_failed" args:@[ adUnitId ?: @"", @(-1) ]];
}

- (BOOL)isInterstitialReady:(NSString *)adUnitId {
    (void)adUnitId;
    return NO;
}

- (void)showInterstitial:(NSString *)adUnitId placement:(NSString *)placementName token:(int64_t)token {
    (void)placementName;
    [self emit:@"interstitial_show_failed" args:@[ @(token), adUnitId ?: @"" ]];
}

- (void)setTestSuiteEnabled:(BOOL)enabled {
    (void)enabled;
}

- (void)launchTestSuite {
}

- (void)setMetadataKey:(NSString *)key value:(NSString *)value {
    (void)key;
    (void)value;
}

- (NSString *)deviceTimeZone {
    return NSTimeZone.localTimeZone.name ?: @"";
}

- (void)requestTrackingAuthorization {
    if (@available(iOS 14, *)) {
        [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(__unused ATTrackingManagerAuthorizationStatus status){
        }];
    }
}

@end
