plugins {
    id("com.android.application") version "9.3.1"
}

android {
    namespace = "ie.xav.tetherlink"
    compileSdk = 37

    defaultConfig {
        applicationId = "ie.xav.tetherlink"
        // SoftApConfiguration.Builder#setVendorElements is Android 13+.
        minSdk = 33
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    implementation("org.lsposed.hiddenapibypass:hiddenapibypass:6.1")
}
