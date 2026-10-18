-keep class com.veyamahjong.ads.** { *; }
-keep class com.ironsource.adapters.** { *; }
-keep class com.ironsource.mediationsdk.** { *; }
-keep class com.facebook.ads.** { *; }
-keeppackagenames com.facebook.*
-dontwarn com.facebook.ads.internal.**
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
