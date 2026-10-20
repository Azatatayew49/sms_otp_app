import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release signing ───────────────────────────────────────────────────────────
// The key lives OUTSIDE the repo. Looked up in this order:
//   1. env vars AK_ULAG_KEYSTORE_FILE, AK_ULAG_KEYSTORE_PASSWORD, AK_ULAG_KEY_ALIAS,
//      AK_ULAG_KEY_PASSWORD (CI / sandbox)
//   2. the properties file named by AK_ULAG_SIGNING_PROPS, else ~/ak-ulag-signing/key.properties
// A release build without the key FAILS instead of quietly using the debug key:
// Android refuses an update signed with a different key than the installed app.
val signingProps = Properties().apply {
    val path = System.getenv("AK_ULAG_SIGNING_PROPS")
        ?: "${System.getProperty("user.home")}/ak-ulag-signing/key.properties"
    val f = File(path)
    if (f.exists()) f.inputStream().use { load(it) }
}

fun signingValue(env: String, prop: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: signingProps.getProperty(prop)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("AK_ULAG_KEYSTORE_FILE", "storeFile")
val releaseStorePassword = signingValue("AK_ULAG_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("AK_ULAG_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("AK_ULAG_KEY_PASSWORD", "keyPassword")
val releaseSigningReady = releaseStoreFile != null && File(releaseStoreFile).exists() &&
    releaseStorePassword != null && releaseKeyAlias != null && releaseKeyPassword != null

android {
    namespace = "tm.ak_ulag.sms_otp_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "tm.ak_ulag.sms_otp_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningReady) {
                storeFile = File(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any {
        it.project == project && it.name.contains("Release") &&
            (it.name.startsWith("assemble") || it.name.startsWith("bundle") || it.name.startsWith("package"))
    }
    if (buildingRelease && !releaseSigningReady) {
        throw GradleException(
            "Release signing is not configured. Put the Ak Ulag key.properties in " +
                "~/ak-ulag-signing/ or set AK_ULAG_SIGNING_PROPS / the AK_ULAG_KEYSTORE_* env vars."
        )
    }
}
