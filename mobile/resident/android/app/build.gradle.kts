import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}
// Release signing (industry pass, 7 Oct 2026). With android/key.properties
// (never committed: storeFile, storePassword, keyAlias, keyPassword) a
// release build is signed with the barangay's own key; without it, the
// debug key as before, so nothing changes until the key exists.
val releaseKey = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "ph.smartsumbong.resident"
    // 37, one above Flutter 3.47's default: flutter_secure_storage 11 and
    // permission_handler 13 (permission_handler_android 14) compile against
    // it. targetSdk stays Flutter's (36): moving it opts into Android 17
    // runtime behaviour, which needs testing on a phone first.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    compileOptions {
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "ph.smartsumbong.resident"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (releaseKey.containsKey("storeFile")) {
            create("release") {
                storeFile = file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
dependencies {
    // Backs the core library desugaring flag above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // AppCompat themes: the fingerprint prompt (local_auth / androidx.biometric)
    // misbehaves on older Android (Martin's Oppo A12, Android 9) under a
    // plain android:Theme.
    implementation("androidx.appcompat:appcompat:1.7.0")
}
flutter {
    source = "../.."
}
