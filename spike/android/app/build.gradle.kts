import groovy.json.JsonSlurper
import java.io.File

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

// Mode single-commune : passer `-PcommuneId=<tenant-id>` à Gradle pour
// builder une app per-commune (lit `tenants/<id>/app.json` à la racine du
// repo). Sans le flag = build dev multi-tenant (picker actif).
val communeId: String? = (findProperty("communeId") as String?)?.takeIf { it.isNotBlank() }
val tenantConfig: Map<String, String> = communeId?.let {
    val f = File(rootProject.projectDir, "../../tenants/$it/app.json")
    require(f.exists()) { "tenants/$it/app.json introuvable: ${f.absolutePath}" }
    @Suppress("UNCHECKED_CAST")
    val parsed = JsonSlurper().parse(f) as Map<String, Any?>
    @Suppress("UNCHECKED_CAST")
    val build = parsed["build"] as Map<String, Any?>
    mapOf(
        "tenant" to (parsed["tenant"] as String),
        "firebase" to (parsed["firebase"] as String),
        "applicationId" to (build["bundleId"] as String),
        "displayName" to (build["displayName"] as String),
    )
} ?: emptyMap()

val effectiveAppId = tenantConfig["applicationId"] ?: "be.communesolutions.spike"
val effectiveTenantBaked = tenantConfig["tenant"] ?: ""
val effectiveFirebaseProjects = tenantConfig["firebase"] ?: ""
val effectiveLabel = tenantConfig["displayName"] ?: "Commune Spike"
// Pointe le SDK sur les emulators locaux quand ce flag est passé.
// Émulateur Android : 10.0.2.2 = host Mac dev. Device physique :
// utiliser l'IP réelle du Mac (mêmes ports 9099 + 8080).
val firebaseEmulatorHost: String = (findProperty("firebaseEmulatorHost") as String?)?.takeIf { it.isNotBlank() } ?: ""

android {
    namespace = "be.communesolutions.spike"
    compileSdk = 35

    defaultConfig {
        applicationId = effectiveAppId
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
        // Lus par MainActivity au démarrage. Vide = mode multi-tenant
        // dev (picker). Set = mode single-commune (no picker).
        buildConfigField("String", "COMMUNE_TENANT_ID", "\"$effectiveTenantBaked\"")
        buildConfigField("String", "COMMUNE_FIREBASE_PROJECTS", "\"$effectiveFirebaseProjects\"")
        buildConfigField("String", "FIREBASE_EMULATOR_HOST", "\"$firebaseEmulatorHost\"")
        resValue("string", "app_name", effectiveLabel)
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
        buildConfig = true
    }
}

dependencies {
    // Compose runtime + material themed root come transitively from :renderer (api).
    implementation(project(":renderer"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
}
