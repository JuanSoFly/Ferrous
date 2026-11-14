# Flutter ProGuard Rules
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Generated Flutter plugins & Rust FFI bridge
-keep class com.juansofly.ferrous.** { *; }
-keep class androidx.documentfile.** { *; }
-dontwarn androidx.documentfile.**

# JNI native methods (libpdfium.so and librust_lib_ferrous.so)
-keepclasseswithmembernames class * {
    native <methods>;
}
