// 플랫폼 독립 로직 (iOS BrawlCore 와 같은 규칙). JVM 에서 테스트한다.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

// 설치된 JDK(17 이상)로 빌드하고 결과물은 Java 17 바이트코드
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}

tasks.test {
    // 공용 테스트 입력 (tests/app-fixtures, tests/engine-regression) 위치
    systemProperty("repoRoot", rootProject.projectDir.parentFile.absolutePath)
    testLogging { events("passed", "skipped", "failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL; showStandardStreams = true }
}
