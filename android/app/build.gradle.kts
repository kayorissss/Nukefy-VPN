plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val libboxAar = file("libs/libbox.aar")

android {
    namespace = "com.nukefy.vpn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nukefy.vpn"
        // The product asked for API 21. Flutter 3.47's engine and several plugins
        // refuse anything below their own floor, so take the higher of the two.
        minSdk = maxOf(21, flutter.minSdkVersion)
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("main") {
            java.srcDir(if (libboxAar.exists()) "src/libbox/kotlin" else "src/nolibbox/kotlin")
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
    implementation("androidx.core:core-ktx:1.16.0")
    if (libboxAar.exists()) {
        implementation(files(libboxAar))
    }
}
