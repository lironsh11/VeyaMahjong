package com.veyamahjong.ads;

import android.app.Activity;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
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

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Bottom LevelPlay banner, hosted the same way as Riftstrike:
 * addContentView at the bottom, adaptive on phones, fixed 320x50 on wide screens.
 * The slot stays invisible until a real fill, then Godot grows the safe area so the
 * nav is not covered. Meta is a LevelPlay bidder only; this class never loads FAN directly.
 */
public class LevelPlayBannerPlugin extends GodotPlugin {
    private static final long RETRY_MS = 30_000L;
    /** Tablet / unfolded foldable — keep the banner phone-width, same cutoff as Riftstrike. */
    private static final float WIDE_DP = 600f;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Godot godot;
    private final SignalInfo bannerVisibilitySignal = new SignalInfo("banner_visibility", Boolean.class, Integer.class);
    private final SignalInfo initFailedSignal = new SignalInfo("init_failed", String.class);

    private String appKey = "";
    private String adUnitId = "";
    private boolean personalized = false;
    private boolean enabled = true;
    private boolean paused = false;
    private boolean initStarted = false;
    private boolean sdkReady = false;
    private boolean loaded = false;

    private int reservedHeightPx = 0;

    private FrameLayout strip;
    private LevelPlayBannerAdView banner;

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
        return Arrays.asList("start", "set_personalized", "set_enabled", "on_pause", "on_resume");
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(bannerVisibilitySignal);
        signals.add(initFailedSignal);
        return signals;
    }

    public void start(String appKey, String adUnitId, boolean personalized) {
        this.appKey = appKey == null ? "" : appKey;
        this.adUnitId = adUnitId == null ? "" : adUnitId;
        this.personalized = personalized;
        this.enabled = true;
        runOnUiThread(this::begin);
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
            begin();
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
        on_pause();
    }

    @Override
    public void onMainResume() {
        on_resume();
    }

    @Override
    public void onMainDestroy() {
        runOnUiThread(this::destroyBanner);
    }

    private void begin() {
        Activity activity = getActivity();
        if (!enabled || activity == null || appKey.isEmpty() || adUnitId.isEmpty()) {
            return;
        }
        if (sdkReady) {
            ensureBanner();
            return;
        }
        if (initStarted) {
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
                emitSignal(godot, getPluginName(), initFailedSignal, message == null ? "init failed" : message);
                if (enabled && !paused) {
                    handler.postDelayed(() -> begin(), RETRY_MS);
                }
            }

            @Override
            public void onInitSuccess(LevelPlayConfiguration configuration) {
                sdkReady = true;
                ensureBanner();
            }
        });
    }

    private void ensureBanner() {
        if (!enabled || paused || !sdkReady || banner != null) {
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
            handler.removeCallbacks(retry);
            if (strip != null) {
                strip.setVisibility(View.VISIBLE);
            }
            report(true, reservedHeightPx);
        }

        @Override
        public void onAdLoadFailed(LevelPlayAdError error) {
            loaded = false;
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
