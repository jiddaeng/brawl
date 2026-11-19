# Brawl Assistant 서버

두 기능을 각각 따로 켤 수 있습니다.

| 기능 | 경로 | 필요한 설정 |
|---|---|---|
| **공식 Brawl Stars API 중계** (지금 열린 맵, 보유 브롤러, 최근 경기) | `GET /v1/brawlstars/rotation`, `GET /v1/brawlstars/player/:tag` | `BRAWLSTARS_API_KEY` |
| **Live Activity 푸시** (화면 인식을 쓸 때만) | `POST /v1/live-activity` | `APNS_*` |

## 공식 Brawl Stars API 중계 (`brawlstars.mjs`)
- **키 발급:** https://developer.brawlstars.com 에 Supercell ID로 로그인 → My Account → Create New Key. **이 서버의 공인 IP**를 허용 목록에 넣습니다. 키는 IP에 묶여 있어 앱이나 다른 서버에서는 쓸 수 없습니다(403).
- **실행:** `BRAWLSTARS_API_KEY=... node server.mjs`. 고정 IP가 있는 곳(작은 VPS, 고정 IP를 주는 호스팅)에 올립니다.
- **앱에 돌려주는 값(최소 정보):** 플레이어는 태그·이름·트로피·보유 브롤러(id, 파워)와 최근 경기 10개(시각, 모드, 맵 id·이름, 결과)입니다. 다른 플레이어 정보는 버립니다. 로테이션은 슬롯·시작·끝·모드·맵 id·이름입니다.
- **캐시와 제한:** 로테이션 5분, 플레이어 1분 메모리 캐시. 공식 API 호출은 접속 주소마다 2초 간격, 시간당 120번입니다. 로그에 플레이어 태그를 남기지 않습니다.
- **한계:** 공식 API에는 진행 중인 경기 정보가 없습니다. 전적은 경기가 끝난 뒤 늦게(수 분~30분) 올라옵니다. 그래서 앱은 '지금 열린 맵'과 '최근 경기 맵'으로 맵 고르기를 빠르게 할 뿐, 지금 들어갈 맵을 확정하지는 못합니다.
- **약관:** Supercell 팬 콘텐츠 정책에 따라 비공식 도구임을 밝히고(앱 하단 문구), 공식 API로만 데이터를 받습니다.

# Live Activity 푸시 중계

게임 중(Brawl Assistant가 백그라운드일 때) Dynamic Island와 잠금 화면 추천을 갱신하기 위한 작은 서버입니다.

## 왜 필요한가
- **방송 확장은 Live Activity에 접근할 수 없습니다.** 실기기(iPhone 14 Pro, iOS 26.6.1)에서 확장 프로세스의 `Activity<…>.activities`가 비어 있었습니다. 앱이 만든 Live Activity가 확장 쪽에서는 보이지 않습니다.
- **앱도 갱신할 수 없습니다.** 게임 중에는 앱이 일시 정지 상태라 직접 갱신하지 못합니다.
- **공식 방법은 APNs뿐입니다.** 앱이 백그라운드일 때 Live Activity를 갱신하는 공식 방법은 ActivityKit 푸시입니다. APNs 인증 키는 비밀이라 앱에 넣을 수 없으므로 서버가 보냅니다.

```
방송 확장 ──(HTTPS: 푸시 토큰 + 표시 값)──▶ 이 서버 ──(HTTP/2, JWT)──▶ APNs ──▶ iPhone Live Activity
```

## 보내는 데이터 (최소 정보)
| 필드 | 내용 |
|---|---|
| `token` | Live Activity 푸시 토큰. 그 Live Activity 하나에만 쓸 수 있고, 끝나면 무효 |
| `environment` | `development`(Xcode 개발 빌드) 또는 `production` |
| `event` | `update` 또는 `end` |
| `contentState` | 상태, 맵 이름, 모드 이름, 브롤러 최대 5명(id·한글 이름), 종합 점수, 추정 승률, 안내 문구, 시각 |
| `alert` | 맵이 바뀔 때만, 설정을 켠 경우. 제목과 한 줄 |

- 화면 이미지, 추천 근거, 기기 정보, 사용자 정보는 보내지 않습니다. 서버는 모르는 필드, URL, 큰 값을 거부합니다(`validateRequest`).
- 서버는 아무것도 저장하지 않습니다. 로그에는 APNs 응답 코드만 남기고 토큰과 내용은 남기지 않습니다.

## 준비 (Apple Developer)
1. **App ID 기능:** App ID(`APP_BUNDLE_ID`)에서 **Push Notifications**를 켭니다. Xcode 자동 서명이면 앱의 `aps-environment` 권한을 보고 자동으로 켜 줍니다.
2. **APNs 인증 키(.p8) 발급:** Certificates, Identifiers & Profiles → Keys → **+** → *Apple Push Notifications service (APNs)*. 내려받은 `.p8` 파일과 **Key ID**를 보관합니다(파일은 한 번만 받을 수 있음).
3. **Team ID:** 계정 Membership 화면에서 확인합니다.

## 실행
```bash
cd server/live-activity-relay
APNS_KEY_FILE=./AuthKey_XXXXXXXXXX.p8 APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY \
APNS_BUNDLE_ID=com.example.brawlassistant node server.mjs
```

| 환경 변수 | 설명 |
|---|---|
| `APNS_KEY` 또는 `APNS_KEY_FILE` | .p8 내용 또는 경로. 레포에 커밋하지 않습니다 (`.dockerignore`에 `*.p8`) |
| `APNS_KEY_ID`, `APNS_TEAM_ID` | 위 2·3단계에서 확인한 값 |
| `APNS_BUNDLE_ID` | 앱 번들 id. topic은 `<번들 id>.push-type.liveactivity` |
| `PORT` | 기본 8080 |

**배포:** 컨테이너로 올립니다(`Dockerfile`). Fly.io, Render, Railway, Google Cloud Run 같은 곳이나 작은 VPS면 됩니다. HTTPS 주소가 필요합니다.

**앱 연결:** `ios/project.yml`의 `PUSH_RELAY_URL`에 `https://<서버 주소>`를 넣고 `xcodegen generate`를 다시 실행합니다.

## 비용과 운영
| 항목 | 내용 |
|---|---|
| **APNs** | 무료 |
| **서버** | 요청이 적습니다(맵이 바뀔 때만, 시간당 수십 건). 무료 등급이나 월 몇 달러 수준의 작은 인스턴스로 충분합니다. 응답 시간을 위해 잠들지 않는(always-on) 인스턴스를 권장합니다 |
| **푸시 예산** | iOS는 Live Activity 푸시에 시간당 예산을 둡니다. 이 서버는 맵 변경 알림만 우선순위 10으로, 나머지는 5로 보냅니다. 앱에는 `NSSupportsLiveActivitiesFrequentUpdates`를 켜 두었습니다 |
| **전송 제한** | 토큰마다 1초 간격, 시간당 240건 (`RateLimiter`, 메모리 기준) |

**남은 보안 과제:** 지금은 푸시 토큰을 아는 사람만 그 Live Activity를 갱신할 수 있습니다. 토큰은 추측할 수 없는 값입니다. 공개 배포 전에는 App Attest로 우리 앱이 보낸 요청인지 확인하는 단계를 추가하는 것이 좋습니다.

## 테스트
```bash
node --test server/live-activity-relay/relay.test.mjs server/live-activity-relay/brawlstars.test.mjs
```
`brawlstars.test.mjs`는 가짜 공식 API(fetch)로 태그 검증, 최소 정보 변환, 캐시, 오류 코드, HTTP 서버를 확인합니다. 실제 api.brawlstars.com 호출은 IP가 등록된 키가 있어야 해서 배포한 뒤 확인합니다.
가짜 APNs(HTTP/2) 서버로 다음을 확인합니다. 실제 APNs 전송은 키가 있어야 해서 기기 검증 단계에서 확인합니다.
- 요청 검증
- 페이로드: aps 시각은 Unix 초, content-state는 그대로 전달
- ES256 JWT 서명
- 헤더: topic, push-type, priority
- 410 응답 처리
- iOS가 실제로 만든 요청(`tests/app-fixtures/relay-request-ios.json`) 수용
