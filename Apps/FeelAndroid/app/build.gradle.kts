plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.feelplayer.companion"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.feelplayer.companion"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = (project.findProperty("versionName") as String?) ?: "1.0.0"
    }

    signingConfigs {
        create("release") {
            val path = System.getenv("FEEL_KEYSTORE")
            if (path != null) {
                storeFile = file(path)
                storePassword = System.getenv("FEEL_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("FEEL_KEY_ALIAS")
                keyPassword = System.getenv("FEEL_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (System.getenv("FEEL_KEYSTORE") != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    packaging {
        resources.excludes += setOf("META-INF/versions/**", "META-INF/*.kotlin_module", "META-INF/DEPENDENCIES", "META-INF/LICENSE*", "META-INF/NOTICE*")
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-ui:1.8.0")
    implementation("com.google.ai.edge.litert:litert:1.4.2")
    implementation("org.bouncycastle:bctls-jdk18on:1.80")
    implementation("org.bouncycastle:bcprov-jdk18on:1.80")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    implementation("com.feedbackjar:sdk:1.7.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
