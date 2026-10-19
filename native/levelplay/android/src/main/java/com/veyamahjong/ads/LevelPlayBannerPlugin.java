package com.veyamahjong.ads;

import android.app.Activity;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.FrameLayout;

import com.unity3d.mediation.LevelPlay;
import com.unity3d.mediation.LevelPlayAdError;
import com.unity3d.mediation.LevelPlayAdInfo;
import com.unity3d.mediation.LevelPlayAdSize;
import com.unity3d.mediation.LevelPlayConfiguration;
import com.unity3d.mediation.LevelPlayInitError;
import com.unity3d.mediation.LevelPlayInitListener;
import com.unity3d.mediation.LevelPlayInitRequest;
import com.unity3d.mediation.banner.LevelPlayBannerAdView;
import com.unity3d.mediation.banner.LevelPlayBannerAdViewListener;
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAd;
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAdListener;
import com.unity3d.mediation.rewarded.LevelPlayReward;
import com.unity3d.mediation.rewarded.LevelPlayRewardedAd;
import com.unity3d.mediation.rewarded.LevelPlayRewardedAdListener;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TimeZone;
import java.util.concurrent.ConcurrentHashMap;

/**
 * LevelPlay ads for Godot: bottom banner, rewarded, interstitial and integration test suite.
 * Consent is asked by the game's own dialog (PrivacyService) and arrives via set_personalized.
 * Implements docs/NATIVE_ADS_API.md (the same contract as the iOS plugin).
 *
 * Banner: hosted with addContentView at the bottom, adaptive on phones, fixed 320x50 on wide
 * screens. The slot stays invisible until a real fill, then Godot grows the safe area.
 * Meta is a LevelPlay bidder only; this class never loads FAN directly.
 *
 * Rewarded / interstitial: one ad object per ad unit id; ready flags are cached for synchronous
 * queries; every show carries a token and its close/fail signal is emitted exactly once. The
 * rewarded result is emitted ~600 ms after close so a reward delivered after close still counts.
 * Nothing is granted natively and nothing reloads on its own (GDScript owns policy).
 */
public class LevelPlayBannerPlugin extends GodotPlugin {
    private static final long RETRY_MS = 30_000L;
    private static final String TAG = "LiShiAds";
    private static final long REWARD_SETTLE_MS = 600L;
    /** Tablet / unfolded foldable — keep the banner phone-width, same cutoff as Riftstrike. */
    private static final float WIDE_DP = 600f;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Godot godot;
    private final SignalInfo bannerVisibilitySignal = new SignalInfo("banner_visibility", Boolean.class, Integer.class);
    private final SignalInfo initFailedSignal = new SignalInfo("init_failed", String.class);
    private final SignalInfo sdkReadySignal = new SignalInfo("sdk_ready");
    private final SignalInfo rewardedLoadedSignal = new SignalInfo("rewarded_loaded", String.class);
    private final SignalInfo rewardedLoadFailedSignal = new SignalInfo("rewarded_load_failed", String.class, Integer.class);
    private final SignalInfo rewardedClosedSignal = new SignalInfo("rewarded_closed", Integer.class, Boolean.class, String.class);
    private final SignalInfo rewardedShowFailedSignal = new SignalInfo("rewarded_show_failed", Integer.class, String.class);
    private final SignalInfo interstitialLoadedSignal = new SignalInfo("interstitial_loaded", String.class);
    private final SignalInfo interstitialLoadFailedSignal = new SignalInfo("interstitial_load_failed", String.class, Integer.class);
    private final SignalInfo interstitialClosedSignal = new SignalInfo("interstitial_closed", Integer.class);
    private final SignalInfo interstitialShowFailedSignal = new SignalInfo("interstitial_show_failed", Integer.class, String.class);
    private final SignalInfo trackingResultSignal = new SignalInfo("tracking_result", String.class);

    private String appKey = "";
    private String adUnitId = "";
    private boolean personalized = false;
    private boolean enabled = true;
    private boolean bannerWanted = false;
    private boolean paused = false;
    private boolean initStarted = false;
    private volatile boolean sdkReady = false;
    private boolean loaded = false;
    private final List<Runnable> afterInit = new ArrayList<>();

    private int reservedHeightPx = 0;

    private FrameLayout strip;
    private LevelPlayBannerAdView banner;

    // Full-screen formats (UI thread only, except the ready flags).
    private final Map<String, LevelPlayRewardedAd> rewardedAds = new HashMap<>();
    private final Map<String, LevelPlayInterstitialAd> interstitialAds = new HashMap<>();
    private final Map<String, Boolean> rewardedReady = new ConcurrentHashMap<>();
    private final Map<String, Boolean> interstitialReady = new ConcurrentHashMap<>();
    /** Units with a load in flight: several placements share one unit, and a second loadAd()
     *  while one is pending fails with 627 "Load is already called". UI thread only. */
    private final Set<String> rewardedLoading = new HashSet<>();
    private final Set<String> interstitialLoading = new HashSet<>();
    /** Ad unit id -> token of the ad currently on screen (or about to be). */
    private final Map<String, Integer> rewardedToken = new HashMap<>();
    private final Map<String, Integer> interstitialToken = new HashMap<>();
    private final Set<Integer> earnedTokens = new HashSet<>();
    private final Set<Integer> finishedTokens = new HashSet<>();
    private boolean fullscreenShowing = false;

    public LevelPlayBannerPlugin(Godot godot) {
        super(godot);
        this.godot = godot;
    }

    @Override
    public String getPluginName() {
        return "LevelPlayBanner";
    }

    @Override
    public List<String> getPluginMethods() {
        return Arrays.asList("start", "set_personalized", "set_enabled", "on_pause", "on_resume",
                "init_sdk", "load_rewarded", "is_rewarded_ready", "show_rewarded",
                "load_interstitial", "is_interstitial_ready", "show_interstitial",
                "set_test_suite_enabled", "launch_test_suite", "set_metadata",
                "device_time_zone", "request_tracking_authorization");
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(bannerVisibilitySignal, initFailedSignal, sdkReadySignal,
                rewardedLoadedSignal, rewardedLoadFailedSignal, rewardedClosedSignal, rewardedShowFailedSignal,
                interstitialLoadedSignal, interstitialLoadFailedSignal, interstitialClosedSignal,
                interstitialShowFailedSignal, trackingResultSignal));
    }

    // --- banner (existing API) -------------------------------------------------------

    public void start(String appKey, String adUnitId, boolean personalized) {
        this.appKey = appKey == null ? "" : appKey;
        this.adUnitId = adUnitId == null ? "" : adUnitId;
        this.personalized = personalized;
        this.enabled = true;
        this.bannerWanted = true;
        runOnUiThread(() -> ensureInit(this::ensureBanner));
    }

    public void set_personalized(boolean personalized) {
        this.personalized = personalized;
        runOnUiThread(() -> {
            if (!sdkReady) {
                return;
            }
            LevelPlay.setConsent(personalized);
        });
    }

    public void set_enabled(boolean enabled) {
        this.enabled = enabled;
        runOnUiThread(() -> {
            if (!enabled) {
                destroyBanner();
                report(false, 0);
                return;
            }
            ensureInit(this::ensureBanner);
        });
    }

    public void on_pause() {
        paused = true;
        runOnUiThread(() -> {
            handler.removeCallbacks(retry);
            if (banner != null) {
                banner.pauseAutoRefresh();
            }
        });
    }

    public void on_resume() {
        paused = false;
        runOnUiThread(() -> {
            if (!enabled) {
                return;
            }
            if (banner != null) {
                banner.resumeAutoRefresh();
            }
            if (sdkReady && !loaded) {
                loadBanner();
            }
        });
    }

    @Override
    public void onMainPause() {
        // A full-screen ad pauses the Godot activity too; keep the banner state as it is so the
        // strip does not flicker or double-inset when the ad closes.
        if (!fullscreenShowing) {
            on_pause();
        }
    }

    @Override
    public void onMainResume() {
        if (!fullscreenShowing) {
            on_resume();
        }
    }

    @Override
    public void onMainDestroy() {
        runOnUiThread(this::destroyBanner);
    }

    // --- shared SDK init -------------------------------------------------------------

    public void init_sdk(String appKey, boolean personalized) {
        if (appKey != null && !appKey.isEmpty()) {
            this.appKey = appKey;
        }
        this.personalized = personalized;
        runOnUiThread(() -> ensureInit(() -> emitSignal(godot, getPluginName(), sdkReadySignal)));
    }

    /** Runs onReady once the SDK is initialised (immediately if it already is). UI thread. */
    private void ensureInit(Runnable onReady) {
        Activity activity = getActivity();
        if (sdkReady) {
            onReady.run();
            return;
        }
        afterInit.add(onReady);
        if (initStarted || activity == null || appKey.isEmpty()) {
            return;
        }
        initStarted = true;
        LevelPlay.setConsent(personalized);
        LevelPlayInitRequest request = new LevelPlayInitRequest.Builder(appKey).build();
        LevelPlay.init(activity, request, new LevelPlayInitListener() {
            @Override
            public void onInitFailed(LevelPlayInitError error) {
                initStarted = false;
                String message = error == null ? "init failed" : error.getErrorMessage();
                Log.w(TAG, "init failed: " + (error == null ? "?" : error.getErrorCode() + " " + message));
                emitSignal(godot, getPluginName(), initFailedSignal, message == null ? "init failed" : message);
                handler.postDelayed(() -> ensureInit(() -> { }), RETRY_MS);
            }

            @Override
            public void onInitSuccess(LevelPlayConfiguration configuration) {
                Log.i(TAG, "init ok");
                runOnUiThread(() -> {
                    sdkReady = true;
                    List<Runnable> pending = new ArrayList<>(afterInit);
                    afterInit.clear();
                    for (Runnable r : pending) {
                        r.run();
                    }
                });
            }
        });
    }

    // --- rewarded --------------------------------------------------------------------

    public void load_rewarded(String unitId) {
        if (unitId == null || unitId.isEmpty()) {
            return;
        }
        runOnUiThread(() -> ensureInit(() -> {
            if (Boolean.TRUE.equals(rewardedReady.get(unitId)) || !rewardedLoading.add(unitId)) {
                return;
            }
            rewardedAd(unitId).loadAd();
        }));
    }

    public boolean is_rewarded_ready(String unitId) {
        return Boolean.TRUE.equals(rewardedReady.get(unitId));
    }

    public void show_rewarded(String unitId, String placementName, int token) {
        runOnUiThread(() -> {
            Activity activity = getActivity();
            LevelPlayRewardedAd ad = rewardedAds.get(unitId);
            if (activity == null || ad == null || !ad.isAdReady() || fullscreenShowing) {
                emitSignal(godot, getPluginName(), rewardedShowFailedSignal, token, unitId);
                return;
            }
            rewardedToken.put(unitId, token);
            rewardedReady.put(unitId, false);
            fullscreenShowing = true;
            ad.showAd(activity, placementName == null || placementName.isEmpty() ? null : placementName);
        });
    }

    private LevelPlayRewardedAd rewardedAd(String unitId) {
        LevelPlayRewardedAd ad = rewardedAds.get(unitId);
        if (ad != null) {
            return ad;
        }
        ad = new LevelPlayRewardedAd(unitId);
        ad.setListener(new LevelPlayRewardedAdListener() {
            @Override
            public void onAdLoaded(LevelPlayAdInfo adInfo) {
                rewardedReady.put(unitId, true);
                runOnUiThread(() -> rewardedLoading.remove(unitId));
                Log.i(TAG, "rewarded loaded " + unitId + " via " + (adInfo == null ? "?" : adInfo.getAdNetwork()));
                emitSignal(godot, getPluginName(), rewardedLoadedSignal, unitId);
            }

            @Override
            public void onAdLoadFailed(LevelPlayAdError error) {
                rewardedReady.put(unitId, false);
                runOnUiThread(() -> rewardedLoading.remove(unitId));
                Log.w(TAG, "rewarded load failed " + unitId + ": " + error);
                emitSignal(godot, getPluginName(), rewardedLoadFailedSignal, unitId, error == null ? -1 : error.getErrorCode());
            }

            @Override
            public void onAdDisplayed(LevelPlayAdInfo adInfo) {
            }

            @Override
            public void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) {
                runOnUiThread(() -> {
                    Integer token = rewardedToken.get(unitId);
                    if (token != null) {
                        earnedTokens.add(token);
                    }
                });
            }

            @Override
            public void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
                runOnUiThread(() -> {
                    fullscreenShowing = false;
                    Integer token = rewardedToken.remove(unitId);
                    if (token != null && finishedTokens.add(token)) {
                        emitSignal(godot, getPluginName(), rewardedShowFailedSignal, token, unitId);
                    }
                });
            }

            @Override
            public void onAdClosed(LevelPlayAdInfo adInfo) {
                runOnUiThread(() -> {
                    fullscreenShowing = false;
                    Integer token = rewardedToken.get(unitId);
                    if (token == null) {
                        return;
                    }
                    // Some networks deliver the reward just after close: wait briefly, then emit once.
                    handler.postDelayed(() -> {
                        if (!finishedTokens.add(token)) {
                            return;
                        }
                        if (token.equals(rewardedToken.get(unitId))) {
                            rewardedToken.remove(unitId);
                        }
                        boolean earned = earnedTokens.remove(token);
                        emitSignal(godot, getPluginName(), rewardedClosedSignal, token, earned, unitId);
                    }, REWARD_SETTLE_MS);
                });
            }
        });
        rewardedAds.put(unitId, ad);
        return ad;
    }

    // --- interstitial ----------------------------------------------------------------

    public void load_interstitial(String unitId) {
        if (unitId == null || unitId.isEmpty()) {
            return;
        }
        runOnUiThread(() -> ensureInit(() -> {
            if (Boolean.TRUE.equals(interstitialReady.get(unitId)) || !interstitialLoading.add(unitId)) {
                return;
            }
            interstitialAd(unitId).loadAd();
        }));
    }

    public boolean is_interstitial_ready(String unitId) {
        return Boolean.TRUE.equals(interstitialReady.get(unitId));
    }

    public void show_interstitial(String unitId, String placementName, int token) {
        runOnUiThread(() -> {
            Activity activity = getActivity();
            LevelPlayInterstitialAd ad = interstitialAds.get(unitId);
            if (activity == null || ad == null || !ad.isAdReady() || fullscreenShowing) {
                emitSignal(godot, getPluginName(), interstitialShowFailedSignal, token, unitId);
                return;
            }
            interstitialToken.put(unitId, token);
            interstitialReady.put(unitId, false);
            fullscreenShowing = true;
            ad.showAd(activity, placementName == null || placementName.isEmpty() ? null : placementName);
        });
    }

    private LevelPlayInterstitialAd interstitialAd(String unitId) {
        LevelPlayInterstitialAd ad = interstitialAds.get(unitId);
        if (ad != null) {
            return ad;
        }
        ad = new LevelPlayInterstitialAd(unitId);
        ad.setListener(new LevelPlayInterstitialAdListener() {
            @Override
            public void onAdLoaded(LevelPlayAdInfo adInfo) {
                interstitialReady.put(unitId, true);
                runOnUiThread(() -> interstitialLoading.remove(unitId));
                Log.i(TAG, "interstitial loaded " + unitId + " via " + (adInfo == null ? "?" : adInfo.getAdNetwork()));
                emitSignal(godot, getPluginName(), interstitialLoadedSignal, unitId);
            }

            @Override
            public void onAdLoadFailed(LevelPlayAdError error) {
                interstitialReady.put(unitId, false);
                runOnUiThread(() -> interstitialLoading.remove(unitId));
                Log.w(TAG, "interstitial load failed " + unitId + ": " + error);
                emitSignal(godot, getPluginName(), interstitialLoadFailedSignal, unitId, error == null ? -1 : error.getErrorCode());
            }

            @Override
            public void onAdDisplayed(LevelPlayAdInfo adInfo) {
            }

            @Override
            public void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
                runOnUiThread(() -> {
                    fullscreenShowing = false;
                    Integer token = interstitialToken.remove(unitId);
                    if (token != null && finishedTokens.add(token)) {
                        emitSignal(godot, getPluginName(), interstitialShowFailedSignal, token, unitId);
                    }
                });
            }

            @Override
            public void onAdClosed(LevelPlayAdInfo adInfo) {
                runOnUiThread(() -> {
                    fullscreenShowing = false;
                    Integer token = interstitialToken.remove(unitId);
                    if (token != null && finishedTokens.add(token)) {
                        emitSignal(godot, getPluginName(), interstitialClosedSignal, token);
                    }
                });
            }
        });
        interstitialAds.put(unitId, ad);
        return ad;
    }

    // --- test suite and metadata ----------------------------------------------------

    public void set_test_suite_enabled(boolean enabled) {
        // Must run before LevelPlay.init.
        LevelPlay.setMetaData("is_test_suite", enabled ? "enable" : "disable");
    }

    public void launch_test_suite() {
        runOnUiThread(() -> {
            Activity activity = getActivity();
            if (activity != null && sdkReady) {
                LevelPlay.launchTestSuite(activity);
            }
        });
    }

    public void set_metadata(String key, String value) {
        if (key != null && value != null) {
            LevelPlay.setMetaData(key, value);
        }
    }

    // --- privacy helpers -------------------------------------------------------------

    /** IANA zone id such as "Europe/Berlin" (the game's consent dialog only shows in Europe/UK). */
    public String device_time_zone() {
        return TimeZone.getDefault().getID();
    }

    public void request_tracking_authorization() {
        // ATT is iOS only.
        emitSignal(godot, getPluginName(), trackingResultSignal, "unavailable");
    }

    // --- banner internals ------------------------------------------------------------

    private void ensureBanner() {
        if (!bannerWanted || !enabled || paused || !sdkReady || banner != null || adUnitId.isEmpty()) {
            return;
        }
        Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        LevelPlayAdSize adSize = resolveBannerAdSize(activity);
        float density = activity.getResources().getDisplayMetrics().density;
        reservedHeightPx = Math.max(1, Math.round(adSize.getHeight() * density));
        boolean wide = activity.getResources().getDisplayMetrics().widthPixels / density >= WIDE_DP;

        strip = new FrameLayout(activity);
        strip.setVisibility(View.INVISIBLE);
        FrameLayout.LayoutParams stripLp = new FrameLayout.LayoutParams(
                wide ? ViewGroup.LayoutParams.WRAP_CONTENT : ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        stripLp.bottomMargin = navigationBarBottom(activity);

        LevelPlayBannerAdView.Config config = new LevelPlayBannerAdView.Config.Builder()
                .setAdSize(adSize)
                .build();
        banner = new LevelPlayBannerAdView(activity, adUnitId, config);
        banner.setBannerListener(listener);
        FrameLayout.LayoutParams adLp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        strip.addView(banner, adLp);
        activity.addContentView(strip, stripLp);
        banner.loadAd();
    }

    /** Phones: adaptive. Wide screens: fixed BANNER (320x50), centered. */
    private LevelPlayAdSize resolveBannerAdSize(Activity activity) {
        float density = activity.getResources().getDisplayMetrics().density;
        float widthDp = activity.getResources().getDisplayMetrics().widthPixels / density;
        if (widthDp >= WIDE_DP) {
            return LevelPlayAdSize.BANNER;
        }
        try {
            LevelPlayAdSize adaptive = LevelPlayAdSize.createAdaptiveAdSize(activity);
            return adaptive != null ? adaptive : LevelPlayAdSize.BANNER;
        } catch (Throwable ignored) {
            return LevelPlayAdSize.BANNER;
        }
    }

    private void loadBanner() {
        if (banner != null && enabled && !paused) {
            banner.loadAd();
        }
    }

    private final Runnable retry = new Runnable() {
        @Override
        public void run() {
            loadBanner();
        }
    };

    private final LevelPlayBannerAdViewListener listener = new LevelPlayBannerAdViewListener() {
        @Override
        public void onAdLoaded(LevelPlayAdInfo adInfo) {
            loaded = true;
            Log.i(TAG, "banner loaded via " + (adInfo == null ? "?" : adInfo.getAdNetwork()));
            handler.removeCallbacks(retry);
            if (strip != null) {
                strip.setVisibility(View.VISIBLE);
            }
            report(true, reservedHeightPx);
        }

        @Override
        public void onAdLoadFailed(LevelPlayAdError error) {
            loaded = false;
            Log.w(TAG, "banner load failed: " + error);
            if (strip != null) {
                strip.setVisibility(View.GONE);
            }
            report(false, 0);
            scheduleRetry();
        }

        @Override
        public void onAdDisplayed(LevelPlayAdInfo adInfo) {
        }

        @Override
        public void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) {
            loaded = false;
            if (strip != null) {
                strip.setVisibility(View.GONE);
            }
            report(false, 0);
            scheduleRetry();
        }

        @Override
        public void onAdClicked(LevelPlayAdInfo adInfo) {
        }

        @Override
        public void onAdExpanded(LevelPlayAdInfo adInfo) {
        }

        @Override
        public void onAdCollapsed(LevelPlayAdInfo adInfo) {
        }

        @Override
        public void onAdLeftApplication(LevelPlayAdInfo adInfo) {
        }
    };

    private void scheduleRetry() {
        if (!enabled || paused) {
            return;
        }
        handler.removeCallbacks(retry);
        handler.postDelayed(retry, RETRY_MS);
    }

    private void destroyBanner() {
        handler.removeCallbacks(retry);
        loaded = false;
        if (banner != null) {
            banner.destroy();
            banner = null;
        }
        if (strip != null) {
            ViewGroup parent = (ViewGroup) strip.getParent();
            if (parent != null) {
                parent.removeView(strip);
            }
            strip = null;
        }
    }

    private void report(boolean visible, int heightPx) {
        emitSignal(godot, getPluginName(), bannerVisibilitySignal, visible, heightPx);
    }

    private static int navigationBarBottom(Activity activity) {
        View decor = activity.getWindow().getDecorView();
        WindowInsets insets = decor.getRootWindowInsets();
        if (insets == null) {
            return 0;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return insets.getInsets(WindowInsets.Type.navigationBars()).bottom;
        }
        return insets.getSystemWindowInsetBottom();
    }
}
