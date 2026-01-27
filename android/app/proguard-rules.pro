# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# Google ML Kit rules
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.** { *; }

# Keep all ML Kit text recognition classes
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }

# Keep Flutter and Dart related classes (targeted, avoid keeping entire engine to allow R8 to strip deferred components)
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
# Remove broad androidx keep to avoid preventing shrinker from removing unused classes
# (no explicit keep for androidx; rely on consumer rules)
-keep class androidx.** { *; }

# Prevent obfuscation of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Ignore missing optional ML Kit language-specific text recognition modules
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# Keep WebRTC classes to prevent R8 from stripping JNI/reflection-based APIs
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Keep flutter_webrtc plugin classes
-keep class com.cloudwebrtc.** { *; }
-dontwarn com.cloudwebrtc.**

# Keep camera plugin (avoid R8 stripping)
-keep class io.flutter.plugins.camera.** { *; }
-dontwarn io.flutter.plugins.camera.**

# Keep permission_handler plugin
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# Keep record plugin (AudioRecorder)
-keep class com.llfbandit.record.** { *; }
-dontwarn com.llfbandit.record.**

# Keep audioplayers plugin (old and new package names)
-keep class com.bluehub.audioplayers.** { *; }
-dontwarn com.bluehub.audioplayers.**
-keep class xyz.luan.audioplayers.** { *; }
-dontwarn xyz.luan.audioplayers.**

# Keep path_provider plugin (used by cache manager)
-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

# Keep video_player plugin and ExoPlayer
-keep class io.flutter.plugins.videoplayer.** { *; }
-dontwarn io.flutter.plugins.videoplayer.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Suppress optional Play Core (deprecated) references from Flutter engine's deferred components
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.splitinstall.**