plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key, from the environment (CI secret or a file outside the
// repo): CHAMA_KEYSTORE (path to a .jks or .p12 file), CHAMA_KEYSTORE_PASSWORD,
// CHAMA_KEY_ALIAS, CHAMA_KEY_PASSWORD. Without it a release build fails, unless
// CHAMA_ALLOW_DEBUG_KEY=1 asks for the debug key (local testing only: the
// stores refuse it, and a store-signed build cannot update it).
fun env(name: String) = System.getenv(name)?.takeIf { it.isNotEmpty() }
val keystore = env("CHAMA_KEYSTORE")?.let { file(it) }
val debugKey = keystore == null && env("CHAMA_ALLOW_DEBUG_KEY") == "1"

android {
    namespace = "chat.chama.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time on old Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "chat.chama.app"
        // record and flutter_secure_storage need API 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // pubspec.yaml `version: <name>+<code>`. With --split-per-abi Flutter
        // adds 1000 * ABI number (armeabi-v7a 1, arm64-v8a 2, x86_64 4).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "store"
    productFlavors {
        // F-Droid and direct downloads: no Google code. Push comes through the
        // user's UnifiedPush app (for example ntfy). Default (pubspec.yaml).
        create("fdroid") { dimension = "store" }
        // Play Store: adds FCM as a fallback push service, through the
        // UnifiedPush embedded FCM distributor (Web Push over FCM, no Firebase
        // SDK and no google-services.json).
        create("play") { dimension = "store" }
    }

    signingConfigs {
        if (keystore != null) {
            create("release") {
                storeFile = keystore
                storePassword = env("CHAMA_KEYSTORE_PASSWORD")
                keyAlias = env("CHAMA_KEY_ALIAS")
                keyPassword = env("CHAMA_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            if (keystore != null) {
                signingConfig = signingConfigs.getByName("release")
            } else if (debugKey) {
                signingConfig = signingConfigs.getByName("debug")
                // Shows in the version name (Settings, aapt2 dump badging).
                versionNameSuffix = "-debugkey"
            }
        }
    }
}

// Fail before compiling, with a clear message, instead of producing an
// unsigned or debug-signed release build nobody asked for.
gradle.taskGraph.whenReady {
    if (allTasks.none { it.project == project && it.name.endsWith("Release") } || debugKey) return@whenReady
    if (keystore == null) {
        throw GradleException(
            "Release builds need a signing key: set CHAMA_KEYSTORE, CHAMA_KEYSTORE_PASSWORD, CHAMA_KEY_ALIAS " +
                "and CHAMA_KEY_PASSWORD (app/README.md). For local testing only, CHAMA_ALLOW_DEBUG_KEY=1 " +
                "signs with the debug key.",
        )
    }
    if (!keystore.isFile) throw GradleException("CHAMA_KEYSTORE: no file at $keystore")
    val missing = listOf("CHAMA_KEYSTORE_PASSWORD", "CHAMA_KEY_ALIAS", "CHAMA_KEY_PASSWORD").filter { env(it) == null }
    if (missing.isNotEmpty()) throw GradleException("CHAMA_KEYSTORE is set but ${missing.joinToString()} not")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    add("playImplementation", "org.unifiedpush.android:embedded-fcm-distributor:3.1.0")
}

flutter {
    source = "../.."
}
