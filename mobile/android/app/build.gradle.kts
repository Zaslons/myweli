import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. `android/key.properties` is gitignored and holds the upload
// keystore's coordinates; CI and a fresh clone do not have it.
//
// **The rule this encodes: never silently fall back to the debug key.** The
// Flutter template ships `signingConfig = signingConfigs.getByName("debug")`
// with a TODO, and that is why this app could not be uploaded — Play rejects a
// debug-signed bundle, and nothing about the build says so. Absent the
// properties file the release build is left UNSIGNED, which fails loudly at the
// point of signing rather than producing an artifact that looks shippable and
// is not.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasUploadKey = keystoreProperties.getProperty("storeFile") != null

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

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Signed with the upload key when key.properties is present, and
            // otherwise left UNSIGNED on purpose — see the note at the top of
            // this file. `flutter run --release` on a dev machine without the
            // keystore will refuse to install, which is the correct answer: the
            // alternative was an artifact indistinguishable from a shippable
            // one that the Play Console rejects.
            signingConfig = if (hasUploadKey) signingConfigs.getByName("upload") else null
            // R8 minifies and shrinks every release build (decision 112,
            // docs/design/android-play-release.md §3.3, §6). Flutter's Gradle
            // plugin already turns both on, with its own keep rules, unless
            // `--no-shrink` is passed (FlutterPlugin.kt 216–219 in 3.47.9) —
            // every Play build so far was R8'd. Written here so a plugin change
            // cannot turn them off silently; this block runs after the plugin
            // applies, so it is what wins. Java and Kotlin crash frames are
            // then renamed: tool/release_build.sh gives each build a mapping
            // UUID (SENTRY_PROGUARD_UUID) and refuses a build that left no
            // mapping.txt. Held by test/infra/android_release_r8_test.dart.
            // R8's risk is at runtime (a class reached only by reflection),
            // which is why the internal track's device pass covers push and
            // the plugins (android-play-release.md §5).
            isMinifyEnabled = true
            isShrinkResources = true
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
