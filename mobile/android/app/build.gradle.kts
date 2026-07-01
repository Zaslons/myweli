plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.myweli.myweli"
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
        // Application IDs are set per flavor (consumer / pro) below.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two published apps from one codebase (PRD §427): the consumer app
    // (lib/main.dart) and the pro app (lib/main_pro.dart). Build/run with:
    //   flutter run --flavor consumer -t lib/main.dart
    //   flutter run --flavor pro      -t lib/main_pro.dart
    flavorDimensions += "app"
    productFlavors {
        create("consumer") {
            dimension = "app"
            applicationId = "com.myweli.app"
            resValue("string", "app_name", "MyWeli")
        }
        create("pro") {
            dimension = "app"
            applicationId = "com.myweli.pro"
            resValue("string", "app_name", "MyWeli Pro")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
