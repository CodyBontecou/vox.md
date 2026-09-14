# UniFFI binds these declarations to exported Rust symbols through JNA direct mapping.
# Renaming either side would make a release-only native bridge failure.
-keep class md.vox.core.** { *; }
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# JNA performs reflective structure and callback discovery for UniFFI records.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.Structure {
    <fields>;
    <methods>;
}

# JNA includes desktop-only AWT helpers in its cross-platform artifact. Android never calls them.
-dontwarn java.awt.Component
-dontwarn java.awt.GraphicsEnvironment
-dontwarn java.awt.HeadlessException
-dontwarn java.awt.Window

# sherpa-onnx's Kotlin API binds these exact class and native method names through JNI.
-keep class com.k2fsa.sherpa.onnx.** { *; }

# WorkManager instantiates this durability-critical phone-side Watch delivery worker.
-keep class md.vox.android.WearRecordingOnlyDeliveryWorker { public <init>(...); public *; }
