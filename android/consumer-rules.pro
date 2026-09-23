# =============================================================================
# TerraPay PayByWallet SDK
#
# The shipped payByWallet-release.aar contains NO proguard.txt, so the SDK's
# own consumer-rules.pro never reaches this app and R8 would happily obfuscate
# the SDK while minifying the release build. These rules are adapted from the
# SDK module's proguard-rules.pro and must be kept in step with it.
# =============================================================================

-keep class com.terrapay.payByWallet.network.** { *; }
-keep class com.terrapay.payByWallet.ui.** { *; }
-dontwarn com.terrapay.payByWallet.ui.**

# Gson maps the SDK's DTOs by FIELD NAME -- not one of the 35 classes under
# model/ carries @SerializedName. Members must therefore be kept verbatim;
# a weaker `-keep,allowobfuscation class ...model.**` would let R8 rename the
# fields and every request/response would (de)serialise to garbage at runtime,
# in release builds only. This matches line 6 of the SDK module's own
# proguard-rules.pro.
-keep class com.terrapay.payByWallet.model.** { *; }
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# The SDK's models are @Parcelize-annotated. The annotations have CLASS
# retention and are absent at runtime, which is harmless.
-dontwarn kotlinx.parcelize.**
-dontwarn kotlinx.android.parcel.**

# -----------------------------------------------------------------------------
# Retrofit / OkHttp
# -----------------------------------------------------------------------------
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keepattributes AnnotationDefault
-keepattributes *Annotation*

-dontwarn okhttp3.**
-dontwarn retrofit2.**
-dontwarn javax.annotation.**

-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-if interface * { @retrofit2.http.* <methods>; }
-keep,allowobfuscation interface <1>
-if interface * { @retrofit2.http.* <methods>; }
-keep,allowobfuscation interface * extends <1>
-if interface * { @retrofit2.http.* public *** *(...); }
-keep,allowoptimization,allowshrinking,allowobfuscation class <3>

-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation
-keep,allowobfuscation,allowshrinking class retrofit2.Response

# -----------------------------------------------------------------------------
# Gson
# -----------------------------------------------------------------------------
-dontwarn sun.misc.Unsafe
-dontwarn jdk.internal.misc.Unsafe

# -----------------------------------------------------------------------------
# Coroutines
# -----------------------------------------------------------------------------
-dontwarn kotlinx.coroutines.**

# -----------------------------------------------------------------------------
# Kotlin companions referenced reflectively by the SDK
# -----------------------------------------------------------------------------
-keepclassmembers class *$Companion {
    <fields>;
}
