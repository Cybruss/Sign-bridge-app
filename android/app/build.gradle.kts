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

    buildFeatures {
        viewBinding = true
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

// Workaround: exclude transitive org.tensorflow artifacts to avoid duplicate
// classes between MediaPipe's litert and the TensorFlow Lite AARs brought
// in by other plugins (e.g. tflite_flutter). MediaPipe's litert provides the
// runtime classes and is compatible with the native usage in this app.
// Note: we keep select-tf-ops for flex delegate support in the GRU model.
configurations.all {
    exclude(group = "org.tensorflow", module = "tensorflow-lite")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-select-tf")
    exclude(group = "org.tensorflow", module = "tensorflow-lite-api")
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.mediapipe:tasks-vision:0.10.26")
    implementation("androidx.camera:camera-core:1.5.0")
    implementation("androidx.camera:camera-camera2:1.5.0")
    implementation("androidx.camera:camera-lifecycle:1.5.0")
    implementation("androidx.camera:camera-view:1.5.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")

    // AndroidX and Jetpack libraries required by the Kotlin sources
    implementation("androidx.activity:activity-ktx:1.7.2")
    implementation("androidx.fragment:fragment-ktx:1.5.7")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.6.1")
    implementation("androidx.navigation:navigation-fragment-ktx:2.5.3")
    implementation("androidx.navigation:navigation-ui-ktx:2.5.3")
    implementation("com.google.android.material:material:1.9.0")
    // TensorFlow Lite for on-device sign classification
    // Use MediaPipe's litert artifacts (provide the org.tensorflow.lite API-compatible classes)
    implementation("com.google.ai.edge.litert:litert-api:1.4.0")
    implementation("com.google.ai.edge.litert:litert:1.4.0")
    // Flex ops for custom TensorFlow operations in the GRU model
    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.14.0")
}