import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore properties for release signing
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.equal.app.equal"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String? ?: "debug"
            keyPassword = keystoreProperties["keyPassword"] as String? ?: "android"
            storeFile = keystoreProperties["storeFile"]?.let { rootProject.file(it) } ?: rootProject.file("debug.keystore")
            storePassword = keystoreProperties["storePassword"] as String? ?: "android"
        }
    }

    // Packaging defaults (no keepDebugSymbols override). Let Flutter/Gradle handle symbol stripping.
    // packaging { }

    defaultConfig {
        applicationId = "com.equal.app.equal"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // App metadata for Play Store
        manifestPlaceholders["appName"] = "Equal"
        manifestPlaceholders["appDescription"] = "Revolutionary Social Media App"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // Disable code shrinking/minification and resource shrinking per user request to fix release bugs
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            
            // Use default NDK debug symbol handling (do not force level)
            // ndk { }
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

configurations.all {
    exclude(group = "com.google.firebase", module = "firebase-iid")
    // Exclude Play Core Common to prevent duplicate classes with Play Core
    exclude(group = "com.google.android.play", module = "core-common")
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:32.8.1"))
    implementation("com.google.firebase:firebase-messaging-ktx")
    implementation("com.google.firebase:firebase-analytics-ktx")
    // Removed deprecated Play Core library incompatible with targetSdk 34; add specific libraries if needed:
    // implementation("com.google.android.play:review:2.0.1")  // For in-app review
    // implementation("com.google.android.play:app-update:2.1.0") // For in-app updates
    // Include modern Feature Delivery API for splitinstall references used by Flutter engine
    implementation("com.google.android.play:feature-delivery:2.1.0")
    // Tasks API moved from Play Core to Google Play Services
    implementation("com.google.android.gms:play-services-tasks:18.2.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
