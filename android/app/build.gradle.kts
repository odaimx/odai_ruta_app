import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de entrega: android/key.properties (no va al repositorio; en GitHub se arma con los secretos del
// repositorio). Sin ese archivo, el APK se firma con la llave de depuración: sirve para pruebas, no para entregar.
val firma = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}

android {
    namespace = "lat.odai.ruta"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "lat.odai.ruta"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (firma.containsKey("storeFile")) {
            create("entrega") {
                storeFile = file(firma.getProperty("storeFile"))
                storePassword = firma.getProperty("storePassword")
                keyAlias = firma.getProperty("keyAlias")
                keyPassword = firma.getProperty("keyPassword")
                firma.getProperty("storeType")?.let { storeType = it }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (firma.containsKey("storeFile")) signingConfigs.getByName("entrega")
                            else signingConfigs.getByName("debug")
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
    // FileProvider: pasar el APK descargado al instalador de Android.
    implementation("androidx.core:core:1.13.1")
}
