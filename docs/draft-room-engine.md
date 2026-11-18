# Draft Room 추천 엔진 분석 (PHASE 1)

운영 중인 https://jiddaeng.github.io/brawl/ 은 이 레포 `main`의 `index.html`과 같은 파일입니다 (2026-11-18 확인, 바이트 단위 동일).
iOS 앱이 같은 알고리즘을 쓰도록 계산 코드를 `engine/draft-engine.js`로 옮겼고, 옮기기 전과 후의 웹 결과가 같음을 회귀 테스트로 확인했습니다(`tests/engine-regression`).
아래 줄 번호는 `engine/draft-engine.js` 기준입니다.

## 1. 브롤러 데이터

| 항목 | 내용 |
|---|---|
| 원천 | Brawlify `GET https://api.brawlapi.com/v1/brawlers` → `list` (사용 필드: `id, name, imageUrl2, released, class.name, rarity.color`) |
| 프로필 `P` | 브롤러마다 11개 값: 사거리 `r`(1–5), 체력 `hp`, 지속딜 `d`, 순간딜 `b`, 기동 `m`, 군중제어 `c`(0–3), 벽파괴 `w`(0–2), 투척 `t`, 회복·버프 `h`, 메타 파워 `k`, 포지션 `p`(F 프론트 / A 암살 / M 미드 / B 저격 / T 투척 / S 서포트) |
| 프로필 없는 브롤러 | `CLASS_BASE[class]`로 대체하고 `auto:1` 표시 (현재 108명 전원 직접 입력 프로필 있음) |
| 태그 `TAGS` | `antiTank, antiHeal, bushCheck, zone, invis, pull` — 상성·시너지 계산에 사용 |
| 한국어 이름 | `KO` |
| 엔진 내부 형식 | `DATA.brawlers[] = {id, name, img, cls, rarity, prof}` (`released === false`는 제외) |

## 2. 맵 데이터

| 항목 | 내용 |
|---|---|
| 원천 | Brawlify `GET /v1/maps` → `list` (사용 필드: `id, name, imageUrl, disabled, new, gameMode{name,imageUrl,color}, environment.name`) |
| 수동 추가 | `NEW_MAPS` 24개: Brawlify에 아직 없는 신규 맵 `[id, 영문, 모드, 한글]` |
| BrawlTime 전용 맵 | Brawlify·NEW_MAPS에 없는데 BrawlTime 맵 풀에 있으면 `id = "bt-<모드>-<슬러그>"`로 생성 (이미지 없음 → 모드 기본 특성) |
| 한국어 이름 | `MAP_KO_ID[id]` → `m.ko` → `MAP_KO[영문]` → 정규화 이름 → 영문 (`mapKo`) |
| 정렬 | 현재 맵 풀 먼저, 그다음 id 내림차순 |
| 맵 이미지 | `mapImgs`: BrawlTime `/media/maps/<id>.png` → Brawlify `imageUrl` 순서로 시도 |

## 3. 게임 모드

`modeProfile(name)`이 모드 이름(정규식)으로 결정합니다.

| kind | 대상 모드 | size | 특징 |
|---|---|---|---|
| gem | Gem Grab | 3 | 체력·CC·회복·투척 가중 |
| ball | Brawl Ball, Hockey, Basket, Volley 등 | 3 (5v5는 5) | 벽파괴 1.3, 기동·CC 가중, shift −1 |
| heist | Heist | 3 | 지속딜 1.5 |
| pick | Bounty, Knockout, Wipeout | 3 (5v5는 5) | 순간딜·사거리, shift 1.2 |
| zone | Hot Zone | 3 | 체력·지속딜·CC·회복 |
| sd | Showdown | Solo 1 / Duo 2 / Trio 3 | |
| duel | Duels | 3 | 순서 역할 |
| pve | Boss, Mecha, Guard | 3 | |
| gen | 그 외 | 3 | 기본 가중치 |

`RANKED` = 젬 그랩, 브롤 볼, 하이스트, 바운티, 핫 존, 녹아웃 / `MODE_KO` 한국어 이름 / `BT_MODE` BrawlTime 모드 키 → 영문 모드.

## 4. 조합 추천 알고리즘

1. **맵 이미지 분석** `analyzePixels(rgba, W, H)`
   - 세로 맵(H > 1.3W)은 23×35칸, 나머지는 30px 칸으로 나눕니다.
   - 가장 흔한 색 2개를 바닥으로 보고, 바닥색에서 먼 칸을 엄폐물로, 그중 초록 계열(hue 85–215, 채도 > 0.35)을 부쉬로 분류합니다.
   - 결과: `cover, bush, wall, open, sight`(열별 최장 시야선), `midOpen`(중앙 개방), `laneSplit`(레인 분리).
   - 이미지가 없거나 분석에 실패하면 `fallbackFeat(mode)`(모드별 기본값)을 씁니다.
2. **맵 요구 점수** `demands(feat, mp)`: 사거리, 투척, 벽파괴, 부쉬, 탱커, 다이브, 미드 장악 7개 값(0–1).
3. **개인 적합도** `indivFit`: 이상 사거리와의 차이 + 프로필 × 모드 가중치 × 요구 점수 + 포지션 보너스 + 태그 보너스 + 실전 승률 효과 `clamp(eff×30, −3, 4)`.
4. **상성** `beats(a, b, dm)`: 포지션 상성, anti 태그, 사거리 차이, 부쉬 체크.
5. **조합 탐색** `solve`
   - 밴·상대 픽을 뺀 풀을 개인 적합도 순으로 정렬합니다.
   - 상위 N명(5인 18, 3인 28, 2인 40, 솔로 전체)에서 고정 픽을 포함한 모든 조합을 평가합니다.
   - 점수순 정렬 후 고정 픽을 뺀 자리끼리 겹침을 비교해 비슷한 조합을 거르고, 상위 6개를 남깁니다.
6. **역할·드래프트**
   - `assignRoles`: 모드별 역할 후보 중 팀 합이 최대인 배치를 고릅니다. 필수 역할(젬 캐리어 등)은 반드시 배정됩니다.
   - `draftOrder`: 메타 파워와 카운터당하는 정도로 블라인드 픽 안전도를 매겨 픽 순서를 정합니다.
   - `banThreats`: 이 조합을 가장 강하게 카운터하는 3명을 밴 추천으로 냅니다.

## 5. 브롤러별 맵 승률 데이터

- **원천:** BrawlTime `GET /media/brawler-strength/<mode>/<slug>.json`
- **프리셋 우선순위** (`parseStats`): `presets.ranked` → `legendary` → `trophies` 중 처음 있는 것을 씁니다.
- **값:** `best[].effect`를 `eff[브롤러 대문자 이름]`으로 저장하고, 판수와 기간도 함께 기록합니다.
- **쓰이는 곳:** 개인 적합도(4번 항목), 팀 평가의 `stats` 항목(`clamp(0.5 + 평균eff×5)`, 가중치 2), 추천 근거 문구.
- **실패하면:** 통계 없이 프로필만으로 계산합니다.

## 6. 종합 점수 `teamEval`

평가 항목은 0–1 범위입니다: `map`(평균 적합도 정규화), `range`, `balance`, `cc`, `sustain`, `wall`, `bush`, `counter`(상위 30명 위협 내성), `synergy`, `meta`, `enemy`(상대 픽 대응), `stats`.

가중치 `W = {map 2.2, range .8, balance 1.4, cc .7, sustain .8, wall .7, bush .5, counter 1, synergy .8, meta .9, enemy 1.8(상대 픽 있을 때), stats 2(통계 있을 때)}`

모드별로 일부 가중치를 바꿉니다.

| 모드 | 바뀌는 가중치 |
|---|---|
| pick | range 1.4, sustain .4 |
| ball | wall 1.2, cc 1 |
| zone | sustain 1.2, cc 1 |
| 솔로 | balance 0, synergy 0, range .3 |

```
score = round(40 + 60 × (Σ v·W / Σ W) ^ 1.3)
```

## 7. 추정 승률 `estWinRate`

이 페이지가 자체적으로 계산하는 값이며 공식 통계가 아닙니다.

```
통계 있음: clamp(50 + 평균eff×100 + (score − 70)×0.15, 40, 70)
통계 없음: min(71, 46 + (score − 60)×0.55)
```
결과는 소수 첫째 자리 문자열입니다.

## 8. Brawlify 연결 (`index.html` `loadSources`)

- `/v1/maps`와 `/v1/brawlers`를 동시에 요청합니다.
- **둘 다 성공하면** 필요한 필드만 남겨 저장본(localStorage `draftroom.cache.v1`)을 갱신합니다.
- **하나라도 실패하면** 저장본을 씁니다. 상단에 "API 응답 없음 · 저장본 사용"이 표시됩니다.
- **저장본도 없으면** 오류 화면을 띄웁니다.

## 9. BrawlTime 연결

- **현재 맵 풀:** `brawler-strength.json`을 씁니다.
  - `from` / `until`: 최근 4주 기간
  - `files.maps[모드키]`: 그 모드에서 실전 기록이 있는 맵 슬러그 목록
- **맵 매칭:** 슬러그를 정규화한 맵 이름과 비교합니다. 모드까지 같은 맵을 우선하고, 같은 이름이 여러 개면 id가 가장 큰 맵에 `live` 표시를 합니다.
- **맵별 통계와 맵 이미지**는 5번 항목과 2번 항목을 참고하세요.

## 10. 현재 맵 자동 갱신 방식

- 별도 타이머나 서버가 없습니다. **페이지를 열 때마다** 8·9번의 요청을 새로 보냅니다.
- **현재 맵 풀** = BrawlTime 최근 4주 기록이 있는 맵입니다(`inPool`: `hasLive ? live : !disabled`). BrawlTime이 응답하지 않으면 Brawlify의 활성 맵(`!disabled`)으로 대체합니다.
- **맵별 통계**는 맵을 고를 때 받아서 세션 동안 캐시합니다(`STATS`).

## 외부 호스트 API (`DraftEngine`, iOS가 사용)

| 함수 | 하는 일 |
|---|---|
| `load(maps, brawlers, strength)` | `buildData` 후 `catalog()` 반환 |
| `catalog()` | 현재 맵 풀(이름·한글·모드·이미지 후보·BrawlTime 키)과 브롤러 목록 |
| `analyzePixels(rgba, W, H)` | 맵 특성 |
| `fallbackFeat(mode)`, `parseStats(json)` | 웹과 같음 |
| `recommend(mapId, feat, {stats, lock, enemy, ban})` | 웹 결과 카드에 그려지는 값 전부: 순위별 팀, 역할, 픽 순서, 점수, 추정 승률, 평가 항목, 근거, 밴 추천, 시뮬레이션 수 |

화면에 보일 숫자 문자열(`effPct`, `percent`, `counterPercent`, `summary`, `countText`)도 엔진이 웹과 같은 식으로 만들어 줍니다. 호스트가 다시 반올림하면 웹과 달라질 수 있기 때문입니다. 예를 들어 1.25를 JS `toFixed(1)`은 "1.3"으로, Swift `String(format:"%.1f")`는 "1.2"로 반올림합니다.
천 단위 구분 기호는 실행 환경 언어와 관계없이 `ko-KR`로 고정했습니다. 한국어 브라우저에서 보이는 결과는 바뀌지 않습니다.

여기서는 새로 계산하지 않습니다. 웹의 `runEngine` → `renderResult`가 호출하는 함수를 같은 순서로 부를 뿐입니다.
