plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.appbucket.adshield"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.appbucket.adshield"
        minSdk = 24
        targetSdk = 34
        versionCode = (System.getenv("GITHUB_RUN_NUMBER") ?: "1").toInt()
        versionName = "1.0.${System.getenv("GITHUB_RUN_NUMBER") ?: "0"}"
    }

    val ksPath = System.getenv("ADSHIELD_KEYSTORE")
    signingConfigs {
        if (ksPath != null) {
            create("appbucket") {
                storeFile = file(ksPath)
                storePassword = System.getenv("ADSHIELD_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ADSHIELD_KEY_ALIAS")
                keyPassword = System.getenv("ADSHIELD_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Signed with the AppBucket key when the secrets are set, else the debug key.
            signingConfig = if (ksPath != null) signingConfigs.getByName("appbucket")
                            else signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { buildConfig = true }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
}
