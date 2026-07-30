plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (push — docs/design/push-notifications-app.md). The google-services
// plugin HARD-FAILS when a flavor's google-services.json is missing, so we
// apply it only once the config is actually there. That keeps a fresh clone —
// and every build before the Firebase project exists — working. The config is
// added per flavor (each has its own applicationId): see DEPLOYMENT.md §B4.
val hasFirebaseConfig = listOf("consumer", "pro").any {
    file("src/$it/google-services.json").exists()
}
if (hasFirebaseConfig) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.myweli.myweli"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Application IDs are set per flavor (consumer / pro) below.
        // Floor pinned for Firebase (23) + flutter_local_notifications (24).
        minSdk = maxOf(24, flutter.minSdkVersion)
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

dependencies {
    // Backs isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
