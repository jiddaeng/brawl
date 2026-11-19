# Brawl Assistant (iOS)

기존 **Draft Room 추천 엔진**으로 브롤스타즈 조합을 계산해 앱과 Dynamic Island에 보여 주는 iPhone 앱입니다.

## 사용 흐름 (화면 녹화 없음)
1. **플레이어 연결 (선택):** 게임 태그를 넣으면 서버가 Supercell 공식 API로 보유 브롤러와 파워를 받아 옵니다. 추천은 내가 가진 브롤러로만 합니다(최소 파워 설정 가능).
2. **지금 열린 맵:** 공식 이벤트 로테이션 맵이 앱 위쪽에 나옵니다. 한 번 누르면 추천이 나옵니다. 공식 전적의 최근 경기 맵이 45분 이내이면 그 맵을 표시하고 자동으로 고릅니다.
3. **Dynamic Island 켜기:** 게임 중에는 Dynamic Island를 길게 눌러 펼치거나 잠금 화면에서 ◀ ▶ 를 누르면 맵이 바뀝니다. 이 버튼은 `ChangeMapIntent`(LiveActivityIntent)입니다. 시스템이 앱을 백그라운드에서 깨워 실행하고, 앱이 직접 Live Activity를 갱신합니다. 서버나 푸시가 필요 없습니다.
4. **화면 인식 (선택):** 예전 방식(ReplayKit 방송 + Vision OCR)은 맵을 자동으로 찾고 싶을 때만 씁니다.

**게임 앱에서 직접 받지 않는 이유:** iOS는 다른 앱의 데이터를 읽을 수 없습니다. Supercell 공식 API에는 진행 중인 경기(지금 들어갈 맵, 드래프트 픽) 정보가 없고, 전적은 경기가 끝난 뒤 늦게 올라옵니다. 게임 통신을 가로채는 방식은 Supercell 약관 위반이라 쓰지 않습니다.

**서버:** 공식 API 키는 서버 IP에 묶인 비밀 값이라 앱에 넣을 수 없습니다. 그래서 `server/live-activity-relay`가 키를 들고 대신 부릅니다(`/v1/brawlstars/rotation`, `/v1/brawlstars/player/:tag`). 서버 주소는 `project.yml`의 `PUSH_RELAY_URL`에 넣습니다. 비워 두면 '지금 열린 맵'과 플레이어 연결이 꺼집니다. 그때는 맵 직접 선택과 ◀ ▶(랭크 맵 순서)만 동작합니다.
추천 알고리즘은 새로 만들지 않았습니다. 웹 사이트와 같은 파일인 `../engine/draft-engine.js`를 JavaScriptCore로 그대로 실행합니다.

> 상태: GitHub Actions(macOS, Xcode 16.4)에서 앱·위젯 확장·방송 확장이 시뮬레이터용과 기기용 모두 빌드되고, 엔진 일치 테스트가 통과합니다. 실제 iPhone 동작은 아직 확인하지 않았습니다. 아래 [검증 현황](#검증-현황)을 보세요.

## 구조

```
engine/draft-engine.js              ← 웹·앱 공용 추천 엔진 (단일 소스)
ios/
├── project.yml                     XcodeGen 정의 (앱 + 위젯 확장 + 방송 확장)
├── BrawlAssistant/
│   ├── App/                        BrawlAssistantApp, AppState
│   ├── Features/
│   │   ├── Home/                   HomeView, HomeViewModel, MapPickerView, GameDataViews (플레이어·지금 열린 맵)
│   │   ├── Recommendation/         RecommendationView, RecommendationService
│   │   └── ScreenRecognition/      BroadcastPicker (RPSystemBroadcastPickerView)
│   ├── LiveActivity/
│   │   ├── BrawlActivityAttributes.swift   (앱·위젯·확장 공용)
│   │   ├── LiveActivityController.swift    (앱: 시작·갱신·종료)
│   │   ├── ChangeMapIntent.swift           (앱·위젯 공용: ◀ ▶ 맵 전환, 앱 프로세스에서 실행)
│   │   └── Widget/                         BrawlLiveActivity, BrawlLiveActivityView (위젯 확장)
│   ├── Extensions/BrawlBroadcastExtension/ SampleHandler, ScreenCaptureManager, FrameAnalyzer, GameScreenRecognizer
│   ├── Shared/                     App Group · Darwin 알림
│   └── Design/                     Theme (웹 Draft Room 토큰·글꼴, DESIGN.md)
└── Packages/BrawlCore/             Swift 패키지 (요청 구조의 Core/ 에 해당)
    ├── BrawlCore    (Foundation만)  Models · Networking(DataSources) · Data(SharedStore) · 인식 매칭 · 상태 규칙
    └── BrawlEngine  (Apple 전용)    Algorithm: JavaScriptCore 브리지, PNG 원본 픽셀 디코더, 계산·캐시 오케스트레이션
```

### 데이터 흐름

```
[앱, 화면에 있을 때]
  데이터 새로고침 → Brawlify·BrawlTime (웹 loadSources 와 같은 규칙, 저장본 폴백)
  → DraftEngine.load → 현재 맵 풀 카탈로그 (App Group)
  → 맵 풀 전체 기본 추천 미리 계산 (맵 이미지 분석 + BrawlTime 맵별 통계 + DraftEngine.recommend)
  → recommendations/<맵id>.json, 브롤러 초상화 96px (App Group)

[방송 확장, 게임 중]
  ReplayKit 프레임 → 샘플링(1초 이상 간격, 화면 변화 없으면 건너뜀, 메모리 부족 시 건너뜀)
  → Vision OCR (ko-KR, en-US, accurate) → 맵·모드 이름 사전 매칭
  → 2프레임 연속 일치해야 확정 → 미리 계산된 추천 조회
  → session.json + Darwin 알림 → Live Activity 갱신 (보이는 내용이 바뀔 때만, 최소 5초 간격)

[앱이 다시 화면에 오면]
  세션을 읽어 Live Activity를 맞추고, 미리 계산되지 않은 맵이면 바로 계산해 확장에 넘김
```

확장은 추천 엔진을 직접 돌리지 않습니다. 방송 확장 메모리 상한(약 50MB) 안에서 Vision OCR을 돌려야 하기 때문입니다.

## 빌드 (Mac 필요)

1. Xcode(iOS 26 SDK, iPhone 17 대상)와 XcodeGen을 설치합니다: `brew install xcodegen`
2. `ios/project.yml`의 `DEVELOPMENT_TEAM`, `APP_BUNDLE_ID`, `APP_GROUP_ID`를 본인 값으로 바꿉니다.
   - App Group은 Apple Developer에서 만들고, 앱·위젯·방송 확장 세 타깃 모두에 켜야 합니다.
3. 프로젝트를 생성하고 엽니다.
   ```bash
   cd ios && xcodegen generate && open BrawlAssistant.xcodeproj
   ```
4. 엔진 일치 테스트(Mac에서 JIT 없이):
   ```bash
   cd ios/Packages/BrawlCore && JSC_useJIT=false swift test
   ```
   Xcode에서는 BrawlAssistant 스킴의 Test(시뮬레이터)로 실행합니다.

방송 확장에서 Live Activity를 갱신하는 코드가 빌드되지 않으면, `project.yml`의 `BROADCAST_UPDATES_ACTIVITY`를 지웁니다. 그러면 앱이 화면에 올 때 앱이 갱신합니다.

## 검증 현황

### 이 환경(Linux)에서 실행해 통과한 것

| 항목 | 결과 |
|---|---|
| 엔진 분리 전 웹 vs 분리 후 웹 (녹화한 실제 API 응답, 18개 맵 × 최대 5개 시나리오) | 87개 시나리오, 결과 화면 HTML 완전 동일 |
| 웹 결과 카드 vs `DraftEngine.recommend` (JavaScriptCore, JIT 끔) | 대안 조합 포함 517개 조합 전부 일치 |
| 같은 비교를 Node(V8)로 | 517개 일치 |
| 가중치를 2.2→2.25로 일부러 바꿨을 때 | 28개 시나리오 불일치로 검출 (테스트가 차이를 잡는지 확인) |
| 맵 PNG 원본 픽셀로 분석 vs 브라우저 canvas | 18개 맵 전부 동일 (PNG에 색 프로필 없음 → 색 변환 없이 읽으면 같음) |
| `BrawlCore` 단위 테스트 (Swift 6.4.2 Linux) | 35개 통과: OCR 매칭, 인식 안정화, 프레임 샘플링, Live Activity 갱신 정책, 세션 상태 전이, 화면 표시 규칙, 저장소, API 폴백, 모델, Android와 공용인 인식 벡터 |
| 웹 스모크 테스트 | 14개 통과 |

JIT 없는 JavaScriptCore 속도(이 서버 기준): 시나리오당 평균 0.42초, 최대 2.1초.

### GitHub Actions (macOS 15, Xcode 16.4)에서 통과한 것

| 항목 | 결과 |
|---|---|
| `xcodegen generate` → `xcodebuild` 시뮬레이터 빌드 / 기기용 빌드 (서명 없이) | 앱, 위젯 확장, 방송 확장 모두 성공 |
| `swift test` (`JSC_useJIT=false`) | 38개 통과 |
| Apple JavaScriptCore로 웹 정답 비교 | 517/517 조합 일치 |
| CoreGraphics `PixelDecoder`(원본 바이트)로 맵 분석 | 18개 맵 브라우저와 일치 |

CI 실행 중 찾아서 고친 문제:
- **반올림 차이:** Swift `String(format:"%.1f")`와 JS `toFixed(1)`이 1.25를 다르게 반올림해, 앱 화면 숫자가 웹과 달라질 수 있었습니다. 이제 표시 문자열을 엔진이 만듭니다.
- **언어 설정 차이:** `toLocaleString()`이 실행 환경 언어에 따라 달라졌습니다. `ko-KR`로 고정했습니다.

### 아직 확인하지 않은 것

- 시뮬레이터에서 화면 확인, 맵 직접 선택 → 추천, Live Activity·Dynamic Island 표시와 갱신 (CI는 빌드만 함)

### 실제 iPhone 17에서만 확인할 수 있는 것

| 항목 | 위험도 | 안 될 때 대안 |
|---|---|---|
| 방송 확장에서 `Activity.update` 동작 (Apple 문서로 확인되지 않음) | 높음 | 앱이 화면에 올 때 갱신 (지금도 구현됨). 게임 중 실시간 갱신은 ActivityKit 푸시 서버가 필요 |
| 가로 전체 화면 게임 중 Dynamic Island compact 표시 | 높음 | "추천이 바뀌면 Dynamic Island 펼치기" 알림 옵션, 잠금 화면 표시 |
| 방송 확장 50MB 안에서 Vision `.accurate` 한국어 OCR | 중간 | 분석 간격 늘리기, 관심 영역 자르기, 메모리 부족 시 건너뛰기(구현됨) |
| 실제 게임 화면에서 맵 이름이 보이는 화면과 OCR 정확도 | 중간 | 맵 직접 선택(구현됨) |
| `RPSystemBroadcastPickerView` 내부 버튼으로 시트 열기 | 낮음 | 피커 버튼을 그대로 화면에 노출 |
| 맵 풀 전체(약 193개) 미리 계산 시간과 맵 이미지 다운로드(약 40MB) | 중간 | 랭크 맵만 먼저 계산(순서 반영됨) |

## 알려진 한계

- **드래프트 픽 인식은 실험 기능입니다.** 브롤러 이름 글자만 읽고 화면 좌우로 팀을 추정합니다. 초상화 인식은 없고, 기본값은 꺼짐입니다.
  - 켜면 앱이 화면에 있을 때만 픽을 반영해 다시 계산합니다(웹 드래프트 시뮬레이터와 같은 입력).
- **팀 인원은 엔진 결과를 따릅니다.** 3v3은 3명, 5v5는 5명, 듀오는 2명, 솔로는 1명입니다. Dynamic Island compact에는 최대 3명까지 표시됩니다.
- **종합 점수와 추정 승률은 Draft Room 엔진의 계산값**이며 공식 통계가 아닙니다. 화면에도 그렇게 표시합니다.
- **Live Activity는 시스템 제한을 받습니다.** 최대 8시간 지속되고, 사용자가 설정에서 끌 수 있으며, 갱신 빈도도 시스템이 조절할 수 있습니다.
- **배포 전 확인할 것:** App Store 심사 기준(다른 앱 화면을 기기 내에서 분석하는 용도)과 Supercell 팬 콘텐츠 정책을 확인해야 합니다. 입력 자동화나 게임 메모리 접근은 하지 않습니다.
