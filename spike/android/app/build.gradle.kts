plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "be.communesolutions.spike"
    compileSdk = 35

    defaultConfig {
        applicationId = "be.communesolutions.spike"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
    }

    sourceSets {
        getByName("main") {
            kotlin.srcDirs("src/main/kotlin")
            // Asset symlinks in `src/main/assets/` point at the repo's
            // `modules-official/` and `tenants/` directories, so the same
            // JSON sources feed iOS and Android.
            assets.srcDirs("src/main/assets")
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    // Compose runtime + material themed root come transitively from :renderer (api).
    implementation(project(":renderer"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
}
