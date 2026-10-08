plugins {
    id("com.android.application") version "9.4.1"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.20"
}

// Release signing comes from the environment (CI decodes the keystore from repo secrets); without
// it, release builds fall back to the debug key so they still build locally.
val releaseKeystore: String? = System.getenv("TETHER_KEYSTORE")

android {
    namespace = "ie.xav.tetherlink"
    compileSdk = 37

    defaultConfig {
        applicationId = "ie.xav.tetherlink"
        // SoftApConfiguration.Builder#setVendorElements is Android 13+.
        minSdk = 33
        targetSdk = 37
        // Set from the release tag in CI: -PversionName=0.1.0 -PversionCode=100.
        versionCode = (findProperty("versionCode") as String?)?.toInt() ?: 1
        versionName = findProperty("versionName") as String? ?: "0.0.0-dev"
    }

    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("TETHER_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("TETHER_KEY_ALIAS")
                keyPassword = System.getenv("TETHER_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material3:material3:1.5.0-alpha24")
    implementation("androidx.compose.ui:ui-text-google-fonts")
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    implementation("org.lsposed.hiddenapibypass:hiddenapibypass:6.1")
}
