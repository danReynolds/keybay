plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    constraints {
        implementation("com.google.guava:guava:33.7.1-android") {
            because("Flutter integration_test otherwise resolves vulnerable Guava 28.1")
        }
        implementation("junit:junit:4.13.2") {
            because("Flutter integration_test otherwise resolves vulnerable JUnit 4.12")
        }
    }
}

android {
    namespace = "dev.keybay.securityharness"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Dedicated test-only package. Device-security tooling may clear or
        // uninstall exactly this package to obtain a clean Keystore namespace;
        // it must never share an identity with a developer or consumer app.
        applicationId = "dev.keybay.securityharness"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // keybay requires Android 12 / API 31+ (AndroidKeyStore KEK path; see doc/platforms/android.md).
        minSdk = 31
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencyLocking {
    // Flutter engine artifacts vary by build host and device ABI. They are
    // pinned by the exact Flutter SDK in CI, so keep this lock focused on the
    // portable third-party runtime graph that the vulnerability watcher scans.
    ignoredDependencies.add("io.flutter:*")
}

configurations.configureEach {
    if (name == "debugRuntimeClasspath") {
        resolutionStrategy.activateDependencyLocking()
    }
}
