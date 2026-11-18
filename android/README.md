# Brawl Assistant (Android)

iOS 앱과 같은 기능의 Android 버전입니다. 추천 알고리즘은 새로 만들지 않았습니다. 웹과 같은 파일인 `../engine/draft-engine.js`를 assets로 넣고, androidx.javascriptengine(JavaScriptSandbox)으로 그대로 실행합니다.

| iOS | Android |
|---|---|
| JavaScriptCore | JavaScriptSandbox: WebView의 V8을 별도 샌드박스 프로세스에서 실행 |
| ReplayKit 방송 확장 | MediaProjection 포그라운드 서비스: 사용자가 매번 허락. Android 14+는 브롤스타즈 앱 하나만 공유 가능 |
| Vision OCR | ML Kit 한국어 텍스트 인식 (기기 안 처리, 라틴 문자 포함) |
| Dynamic Island (Live Activity) | 진행 중 상태 알림. Android 16+는 Live Updates(상태 표시줄 칩에 점수 표시)를 요청 |
| App Group 파일 공유 | 같은 프로세스 (서비스와 화면이 `AppGraph`를 공유) |

## 구조

```
android/
├── core/   순수 Kotlin (JVM 테스트) — iOS BrawlCore 와 같은 규칙
│   ├── EngineModels / AppModels      엔진 결과·세션 모델
│   ├── TextMatching                  OCR 줄 ↔ 맵·모드·브롤러 이름 사전
│   ├── RecognitionPipeline           프레임 샘플링, 인식 안정화, 알림 갱신 정책
│   ├── SessionLogic                  세션 상태 전이, 알림 표시 값, 메인 화면 규칙
│   ├── DataSources / Store           웹과 같은 API 규칙(저장본 폴백), 파일 저장소
│   ├── EngineProtocol                JS 실행기에 엔진 호출을 나눠 보내는 규약 (Binder 1MB 제한 대비)
│   └── RecommendationEngine          데이터 → 맵 이미지 분석 → 통계 → 추천 → 저장
└── app/    Android
    ├── engine/   SandboxRunner(JavaScriptSandbox), BitmapFactory 픽셀 디코더, HTTP
    ├── capture/  ScreenCaptureService(MediaProjection), ML Kit OCR, GameScreenRecognizer
    ├── live/     LiveNotifier (상태 알림 / Live Updates)
    └── ui/       Compose 메인 화면 (검은 배경 · 강조색 #FFCF1F)
```

Android는 서비스가 앱 프로세스 안에서 돌아갑니다. 그래서 미리 계산되지 않은 맵이나 드래프트 픽 반영 계산도 게임 중에 바로 할 수 있습니다. iOS에서는 확장 메모리 한도 때문에 앱이 화면에 올 때 계산합니다.

## 빌드

Android Studio 또는 JDK 17+와 Android SDK(플랫폼 36)가 필요합니다.

```bash
cd android && ./gradlew :core:test :app:assembleDebug
```

| 명령 | 내용 |
|---|---|
| `./gradlew :core:test` | JVM 테스트. Node가 있으면 엔진 일치 테스트도 실행 |
| `./gradlew :app:lintDebug` | lint |
| `./gradlew :app:connectedDebugAndroidTest` | 연결된 기기·에뮬레이터에서 JavaScriptSandbox·BitmapFactory로 웹 정답과 비교 |

- 최소 Android 10(API 29), 대상 API 36.
- JavaScriptSandbox를 쓰려면 최신 Android System WebView가 필요합니다. 지원하지 않으면 업데이트하라는 안내가 나옵니다.
- APK에는 ML Kit OCR 네이티브 라이브러리가 ABI별로 약 11MB씩 들어 있습니다. Play 스토어 App Bundle로 배포하면 기기에 맞는 ABI만 내려받습니다.

## 검증 현황

| 항목 | 결과 |
|---|---|
| `core` JVM 테스트 (공유 인식 벡터 포함) | 통과 |
| Android 호출 경로(조각 전송·base64 픽셀)로 웹 정답 비교, 실행기 Node | 517/517 조합 일치 |
| 데이터 받기 → 맵 이미지 분석 → 통계 → 추천 → 저장 (녹화본) | 18개 맵 기본 추천이 웹과 일치 |
| `assembleDebug`, `lintDebug` | 빌드 성공, lint 경고 0 |
| 에뮬레이터 계측 테스트 (실제 JavaScriptSandbox·BitmapFactory) | CI `Android / device-tests`에서 실행 |
| 실제 기기: 화면 공유, OCR 정확도, 게임 중 알림 표시, Live Updates 칩 | 미확인 |
