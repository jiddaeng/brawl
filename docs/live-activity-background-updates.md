# 게임 중 Dynamic Island 추천이 갱신되지 않는 문제: 조사와 수정

## 증상 (실기기 보고)
| 항목 | 값 |
|---|---|
| 테스트 커밋 | `0aab097` |
| 기기 | iPhone 14 Pro, iOS 26.6.1 |
| 스킴 | `BrawlAssistant` (Debug) |

- 실제 게임 화면의 맵 인식은 정상입니다. 녹아웃 '미리 준비(Think Ahead)'를 신뢰도 100%로 인식했습니다.
- 앱으로 돌아오면 BEST TEAM과 종합 점수 82가 표시됩니다.
- 게임 중(가로 로비 화면)에는 Dynamic Island에 추천이 표시되지 않았습니다.
- 앱 진단 문구: `Dynamic Island: 확장 갱신 불가 → 앱이 열릴 때 갱신 (확장 프로세스에서 Live Activity 가 보이지 않음)`

## 원인 구분
| 구분 | 결과 | 근거 |
|---|---|---|
| Live Activity 생성·유지 | 정상 | 앱에서 시작되고, 앱 복귀 시 갱신되며, 시뮬레이터 홈·잠금 화면에 표시됨 |
| 방송 확장의 인식·전달 | 인식·세션 기록은 정상, **Live Activity 갱신은 실패** | 진단 문구. 확장 프로세스의 `Activity<BrawlActivityAttributes>.activities`가 빈 목록 |
| 가로 전체 화면 표시 | 별도 확인 필요 | 아래 '가로 화면' 참고 |

**결론:** 방송 확장(별도 프로세스)은 앱이 만든 Live Activity에 접근하지 못합니다. 게임 중에는 앱이 일시 정지 상태라 앱도 갱신하지 못합니다. 그래서 앱이 화면에 다시 나올 때까지 Dynamic Island가 바뀌지 않았습니다.

## 지원 여부 확인
- **실기기:** 확장에서 `activities`가 비어 있음을 확인했습니다. 이것이 직접 갱신이 동작하지 않는다는 1차 근거입니다.
- **Apple 자료:**
  - Apple Developer Forums 답변은 앱이 백그라운드일 때 지원되는 갱신 방법을 푸시 알림뿐이라고 설명합니다. 예외는 앱이 백그라운드 위치나 PiP처럼 실제로 실행 중인 경우입니다. ([thread 776031](https://developer.apple.com/forums/thread/776031))
  - ActivityKit 푸시 방식은 [WWDC23 "Update Live Activities with push notifications"](https://developer.apple.com/videos/play/wwdc2023/10185/)에 나옵니다.
  - 앱 확장에서 ActivityKit 갱신이 된다는 공식 문서는 찾지 못했습니다.

## 검토한 대안
| 대안 | 판단 |
|---|---|
| 방송 확장에서 직접 갱신 | 실기기에서 동작하지 않음. 코드는 남겨 두었고, 이후 iOS에서 되면 그 경로가 먼저 쓰임 |
| 앱이 백그라운드에서 계속 실행되도록 오디오·위치 백그라운드 모드 사용 | 목적 외 사용이라 App Store 심사 거절 대상. 배터리 소모도 큼. 채택 안 함 |
| BGTaskScheduler | 실행 시점을 시스템이 정해 몇 초 단위 갱신에 쓸 수 없음 |
| 앱이 화면에 올 때만 갱신 (이전 동작) | 요구사항("앱 백그라운드에서 갱신")을 충족하지 못함 |
| **ActivityKit 푸시 (APNs) + 작은 중계 서버** | **채택.** 앱이 백그라운드여도 시스템이 갱신. APNs 키는 서버에만 둠 |

## 구현 (커밋은 이 문서와 함께)
1. **앱** (`LiveActivityController`)
   - `PUSH_RELAY_URL`이 설정돼 있으면 Live Activity를 `pushType: .token`으로 시작합니다.
   - `pushTokenUpdates`로 받은 토큰을 App Group(`live-activity-push.json`)에 저장합니다. Live Activity가 끝나면 지웁니다.
   - 권한: `aps-environment`(Debug는 development, Release는 production)와 `NSSupportsLiveActivitiesFrequentUpdates`를 추가했습니다.
2. **방송 확장** (`ExtensionActivityUpdater`)
   - 직접 갱신을 먼저 시도하고, 안 되면 중계 서버에 `{token, environment, event, contentState, alert?}`를 보냅니다.
   - 5초 안에 연속으로 바뀐 내용은 마지막 값을 모아 뒤에 보냅니다. 예전에는 버려졌습니다.
3. **중계 서버** (`server/live-activity-relay`)
   - 요청을 검증하고, ES256 JWT로 APNs에 `liveactivity` 푸시를 보냅니다.
   - 맵 변경 알림만 우선순위 10, 나머지는 5로 보냅니다.
   - 준비물, 비용, 전송 데이터, 보안은 [서버 README](../server/live-activity-relay/README.md)에 있습니다.
4. **진단 문구**
   - `Dynamic Island: 푸시 중계로 갱신 요청 성공`: 서버까지 갔고 APNs가 200을 반환함
   - `게임 중 갱신 실패 …`: 원인 문구를 함께 표시
   - 서버가 설정되지 않았으면 그 사실을 표시

**이 환경에서 검증한 것:**
- iOS 요청 형식 테스트: BrawlCore 40개 통과
- 중계 서버 테스트: 8개 통과(가짜 APNs 서버로 경로·헤더·JWT·응답 처리 확인)
- 실제 `server.mjs`를 띄워 HTTP 요청부터 가짜 APNs 전달까지 확인
- iOS가 실제로 만든 요청을 서버가 받아들이는지 확인

**아직 검증하지 못한 것:** 실제 APNs 전송과 실기기 표시입니다. Apple Developer 계정의 APNs 키와 배포된 서버가 있어야 합니다.

## 가로 화면 (브롤스타즈 로비)
- **보도:** iOS 27부터 Live Activity를 가로 모드에서도 표시한다는 보도가 있습니다. 가로를 지원하는 앱에 한한다고 합니다. ([Mac Observer](https://www.macobserver.com/news/ios-27-brings-dynamic-island-to-landscape-mode-heres-whats-new/), 기사 원문은 접근이 막혀 검색 요약으로만 확인)
- **추정:** 테스트 기기(iOS 26.6.1)에서는 가로 전체 화면 게임 중에 Dynamic Island 축소형이 보이지 않는 것이 시스템 동작일 가능성이 높습니다.
- **판단 방법:** 앱 문제와 구분하려면 같은 시점에 **홈 화면으로 나가 보거나 잠금 화면을 확인**합니다. 거기서 갱신돼 있으면 갱신은 된 것이고, 가로에서 안 보이는 것만 시스템 제한입니다.
- **우회:** 설정의 "추천이 바뀌면 Dynamic Island 펼치기"를 켜면 맵이 바뀔 때 알림으로 갱신합니다. 가로 화면에서 어떻게 보이는지(배너 여부)는 기기에서 기록이 필요합니다.

## 실기기 검증 절차
**준비**
1. 중계 서버를 배포합니다([서버 README](../server/live-activity-relay/README.md)).
2. `ios/project.yml`의 `PUSH_RELAY_URL`을 설정하고 `xcodegen generate`를 다시 실행합니다.
3. App ID에 Push Notifications 기능이 켜져 있는지 확인합니다.
4. 앱을 다시 설치합니다(Debug면 sandbox APNs를 씁니다).
5. 앱에서 Live Activity를 끈 뒤 다시 켭니다. 푸시 토큰을 새로 받기 위해서입니다.

**미러링·USB 영향 구분:** 방송을 폰에서 직접 시작한 뒤 USB와 미러링을 **끊은 상태에서 한 번**, 연결한 상태에서 한 번 확인합니다. 방송 확장과 APNs는 Mac 연결과 무관하지만, 미러링 중에는 Dynamic Island 표시 방식이 다를 수 있어 따로 기록합니다.

**기록표**
| 화면 | 기대 동작 | 결과 | 캡처 |
|---|---|---|---|
| 홈 화면 (방송 중, 앱 백그라운드) | 게임에서 맵을 바꾸면 수 초 안에 축소형의 팀·점수가 바뀜 | | |
| 잠금 화면 | 카드에 새 맵·팀·점수 | | |
| 브롤스타즈 가로 로비 | iOS 26: 축소형 미표시 가능(시스템). 알림 설정 시 배너·펼침 여부 기록 | | |
| 앱 복귀 후 진단 | `푸시 중계로 갱신 요청 성공` | | |

함께 남길 정보: 테스트한 커밋, 기기·iOS 버전, 앱 진단 문구 원문, 서버 로그(APNs 응답 코드).
