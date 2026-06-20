# ── Flutter ────────────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ── Drift (SQLite ORM) ─────────────────────────────────────────────────────────
-keep class drift.** { *; }
-keep class com.squareup.sqldelight.** { *; }

# ── just_audio / AudioService ──────────────────────────────────────────────────
-keep class com.ryanheise.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# ── Geolocator / Location ──────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }

# ── Kotlin coroutines ──────────────────────────────────────────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# ── Keep Parcelables ───────────────────────────────────────────────────────────
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# ── Suppress warnings for known safe removals ──────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
