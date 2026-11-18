plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.example.brawlassistant"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.brawlassistant"
        minSdk = 29          // MediaProjection 포그라운드 서비스 타입(Android 10+)
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    // assets 로 가져온 폴더(engine, tests/engine-regression)에서 스크립트·문서는 빼고 데이터만 넣는다
    androidResources { ignoreAssetsPattern = "!*.cjs:!*.mjs:!*.md:!*.py" }

    sourceSets {
        // 기존 Draft Room 추천 엔진: 웹과 같은 파일을 그대로 assets 에 넣는다 (복사본 없음)
        getByName("main").assets.srcDir("../../engine")
        // 기기 테스트용 정답·녹화본
        getByName("androidTest").assets.srcDirs("../../tests/engine-regression")
    }
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    implementation(project(":core"))
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.guava)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.service)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.javascriptengine)
    implementation(libs.mlkit.text.korean)

    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.junit)
}
