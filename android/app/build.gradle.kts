plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sign_bridge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.sign_bridge"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// MediaPipe tasks-vision 0.10.26 calls Any.Builder.build() expecting a
// covariant `Any` return, which protobuf-javalite:4.26.1 (its own transitive
// dep) no longer provides -> NoSuchMethodError at landmarker init. The full
// protobuf-java runtime keeps that covariant method AND is a superset that
// includes the lite classes MediaPipe uses, so swap javalite for it.
configurations.all {
    exclude(group = "com.google.protobuf", module = "protobuf-javalite")
}

flutter {
    source = "../.."
}

dependencies {
    // MediaPipe Holistic (hands + pose + face) for the Sign -> Text pipeline.
    implementation("com.google.mediapipe:tasks-vision:0.10.26")
    // Full protobuf runtime (see the exclude note above).
    implementation("com.google.protobuf:protobuf-java:3.25.5")
    // Sign classification runs in Dart via tflite_flutter (bundles its own
    // TensorFlow Lite runtime), so no native TFLite deps are needed here.
}