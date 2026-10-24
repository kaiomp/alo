plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "chat.chama.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "chat.chama.app"
        // record and flutter_secure_storage need API 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // With --split-per-abi Flutter adds 1000 * ABI number to versionCode.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Dev release builds are signed with the debug key; the store key comes with M3.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// The UnifiedPush connector depends on Tink for the JVM; flutter_secure_storage
// already brings tink-android, which has the same classes.
configurations.all {
    exclude(group = "com.google.crypto.tink", module = "tink")
}

flutter {
    source = "../.."
}
