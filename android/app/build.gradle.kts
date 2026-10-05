plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Owner-provided signing values stay outside source control.
val releaseStore = providers.environmentVariable("FREKIHUB_KEYSTORE_PATH").orNull
val releaseStorePassword = providers.environmentVariable("FREKIHUB_KEYSTORE_PASSWORD").orNull
val releaseAlias = providers.environmentVariable("FREKIHUB_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("FREKIHUB_KEY_PASSWORD").orNull
val hasReleaseSigning = listOf(releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword).all { !it.isNullOrBlank() }

android {
    namespace = "com.frekihub.freki_hub"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.frekihub.freki_hub"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // HyperIsland ToolKit 0.4.0 requires Android 15 (API 35).
        minSdk = 35
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) create("release") {
            storeFile = file(releaseStore!!)
            storePassword = releaseStorePassword
            keyAlias = releaseAlias
            keyPassword = releaseKeyPassword
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.android.gms:play-services-location:21.4.0")
    // 0.4.4 removes the icon/action-key timer API; retain the existing clock-out control.
    implementation("io.github.d4viddf:hyperisland_kit:0.4.0")
}

val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    doLast {
        check(hasReleaseSigning && file(releaseStore!!).isFile) {
            "Release signing requires the owner's FREKIHUB_KEYSTORE_PATH, FREKIHUB_KEYSTORE_PASSWORD, FREKIHUB_KEY_ALIAS and FREKIHUB_KEY_PASSWORD."
        }
    }
}
tasks.configureEach {
    if (name.contains("Release") && name != "verifyReleaseSigning") dependsOn(verifyReleaseSigning)
}
