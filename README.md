# DRAFT ROOM — 브롤스타즈 조합 연구소

맵을 고르면 그 맵에 맞는 브롤러 조합을 추천해 주는 비공식 팬메이드 도구입니다.
웹 사이트와, 같은 추천 엔진을 쓰는 iOS·Android 앱(Brawl Assistant)으로 구성됩니다.

| 경로 | 내용 |
|---|---|
| `index.html` | 웹 사이트 (https://jiddaeng.github.io/brawl/) |
| `engine/draft-engine.js` | **추천 엔진 단일 소스** — 웹·iOS(JavaScriptCore)·Android(JavaScriptSandbox)가 같은 파일을 실행 |
| `ios/` | Brawl Assistant iOS: SwiftUI, ReplayKit 화면 인식, Dynamic Island ([README](ios/README.md)) |
| `android/` | Brawl Assistant Android: Compose, MediaProjection 화면 인식, 상태 알림·Live Updates ([README](android/README.md)) |
| `docs/draft-room-engine.md` | 엔진 분석: 데이터 구조, 계산식, 데이터 연결 |
| `tests/` | 웹 스모크 테스트, 엔진 회귀 테스트(녹화한 API 응답 + 웹 정답), 앱 공용 테스트 입력 |
| `.github/workflows/` | CI: 엔진 회귀(Chromium·JavaScriptCore·V8), iOS 빌드·테스트(macOS), Android 빌드·테스트·에뮬레이터 |

## 웹 실행

`index.html`을 브라우저로 엽니다. 인터넷 연결이 필요합니다(맵·브롤러·통계 데이터를 실시간으로 불러옵니다).
`engine/draft-engine.js`를 함께 불러오므로, 레포를 통째로 두거나 웹 서버로 열어야 합니다.

한 번 정상적으로 불러온 데이터는 브라우저에 저장해 둡니다. 이후 API가 응답하지 않으면 저장본으로 페이지를 띄우고, 상단에 `API 응답 없음 · 저장본 사용`과 저장 시각을 표시합니다.

## 데이터

- 맵·브롤러 목록: [Brawlify](https://brawlify.com) 공개 API
- 현재 맵 풀(최근 4주 실전 기록이 있는 맵), 맵별 브롤러 승률 효과, 맵 이미지: [BrawlTime](https://brawltime.ninja)
- 한국어 맵·브롤러 이름: 게임 텍스트 추출본([psh1234567890/brawl_status_kr](https://github.com/psh1234567890/brawl_status_kr)) + BrawlTime
- Brawlify 목록에 아직 없는 신규 맵은 `NEW_MAPS`에 직접 넣어 두었습니다.

## 추천 방식

- 맵 이미지를 타일 단위로 분석해 벽·부쉬 비율, 시야선, 중앙 개방도 등을 계산합니다.
- 브롤러별 프로필(사거리, 체력, 딜, 기동, 군중 제어, 벽 파괴, 투척, 회복, 포지션), 모드별 가중치, 실전 승률 효과를 합쳐 개인 적합도를 냅니다.
- 상위 후보로 만들 수 있는 조합을 모두 계산합니다. 역할 밸런스, 시너지, 카운터 내성, 상대 픽 대응을 반영한 점수로 정렬합니다.

종합 점수와 추정 승률은 이 엔진이 계산한 값이며 공식 통계가 아닙니다. 자세한 계산식은 [docs/draft-room-engine.md](docs/draft-room-engine.md)에 있습니다.

## 테스트

| 테스트 | 명령 |
|---|---|
| 웹 스모크 (실제 API) | `node tests/smoke.cjs` |
| 엔진 회귀 (녹화본, 분리 전 웹 vs 현재 웹 vs JavaScriptCore) | [tests/engine-regression/README.md](tests/engine-regression/README.md) |
| iOS 코어 | `cd ios/Packages/BrawlCore && swift test` |
| Android 코어 | `cd android && ./gradlew :core:test` |

Playwright·Chromium이 필요한 테스트는 `npm install playwright && npx playwright install chromium`으로 준비합니다.

## 데이터 갱신

브롤러 프로필(`P`), 한국어 이름(`KO`, `MAP_KO`, `MAP_KO_ID`), 신규 맵(`NEW_MAPS`)은 `engine/draft-engine.js`에 직접 넣은 값입니다. 프로필이 없는 신규 브롤러는 클래스 기본값으로 계산되며, 화면에 `추정 프로필`로 표시되고 개인 적합도 카드 아래에 목록이 나옵니다. 그 목록에 브롤러가 보이면 `P`에 프로필을 추가하세요.
엔진을 바꾼 뒤에는 `tests/engine-regression`의 정답을 다시 만들고 차이를 확인하세요.
