# Danger Emergence System - ProGuard Rules
# ==========================================

# Keep Flutter engine classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Kotlin classes used by MethodChannel
-keep class com.dangeremergence.app.** { *; }
-keep class com.dangeremergence.mesh.** { *; }
-keep class com.dangeremergence.security.** { *; }
-keep class com.dangeremergence.location.** { *; }

# Keep Android KeyStore classes
-keep class android.security.keystore.** { *; }
-keep class javax.crypto.** { *; }
-keep class java.security.** { *; }

# Keep Gson/JSON serialization
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }

# Keep WorkManager
-keep class androidx.work.** { *; }

# Keep Bluetooth serial classes
-keep class io.github.edufolly.flutterbluetoothserial.** { *; }

# Keep Biometric classes
-keep class androidx.biometric.** { *; }

# Keep location services
-keep class com.google.android.gms.location.** { *; }

# General AndroidX
-keep class androidx.** { *; }
-keep interface androidx.** { *; }

# Keep enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelable classes
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}

# Keep R8 full mode
-keep,allowobfuscation,allowshrinking class kotlin.Metadata
