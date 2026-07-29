import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

val uac4AppKey = providers.gradleProperty("UAC4_APP_KEY")
    .orElse(providers.environmentVariable("UAC4_APP_KEY"))
    .getOrElse("")
val uac4AppSecret = providers.gradleProperty("UAC4_APP_SECRET")
    .orElse(providers.environmentVariable("UAC4_APP_SECRET"))
    .getOrElse("")
val uac4Udid = providers.gradleProperty("UAC4_UDID")
    .orElse(providers.environmentVariable("UAC4_UDID"))
    .getOrElse("")

android {
    namespace = "ru.tander.smart_glasses"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        aidl = true
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ru.tander.smart_glasses"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
        ndk {
            abiFilters += "arm64-v8a"
        }
        buildConfigField("String", "UAC4_APP_KEY", "\"$uac4AppKey\"")
        buildConfigField("String", "UAC4_APP_SECRET", "\"$uac4AppSecret\"")
        buildConfigField("String", "UAC4_UDID", "\"$uac4Udid\"")
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let(rootProject::file)
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
    }
}

tasks.matching { it.name.contains("Release", ignoreCase = true) }.configureEach {
    doFirst {
        check(uac4AppKey.isNotBlank() && uac4AppSecret.isNotBlank() && uac4Udid.isNotBlank()) {
            "Release builds require UAC4_APP_KEY, UAC4_APP_SECRET, and UAC4_UDID."
        }
    }
}

dependencies {
    implementation(files("libs/glasses4mic-ssp-1.0.2.aar"))
    implementation(files("libs/unisound-active-release-v1.0.2-20260316.aar"))
    androidTestUtil("androidx.test:orchestrator:1.6.1")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
