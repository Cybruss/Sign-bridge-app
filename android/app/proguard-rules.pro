# Disable method-inlining optimizations: protobuf-lite finds its caller by
# walking the stack, which breaks if R8 inlines methods.
-dontoptimize
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod

# MediaPipe Tasks + protobuf-lite rely on reflection over generated field
# names (e.g. platform_). Keep them so release/minified builds don't rename or
# strip them (which breaks landmarker initialization).
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**

# tflite_flutter / TensorFlow Lite
-keep class org.tensorflow.** { *; }
-dontwarn org.tensorflow.**
