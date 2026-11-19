# Brawl Assistant 디자인 기준

**웹 Draft Room(`index.html`)과 같은 모습**을 기준으로 합니다. 예전의 무채색 미니멀 방향은 "너무 기본적이고 AI가 만든 티가 난다"는 피드백을 받아 바꿨습니다.
`.claude/skills/apple-hig`는 크기·여백·Live Activity 규칙에만 씁니다. 색과 글꼴은 웹 Draft Room을 따릅니다. 이 결정은 unslop의 차분한 화면 규칙보다 우선합니다.
디자인을 바꾼 뒤에는 CI `iOS / design-snapshots`가 iPhone Pro 시뮬레이터에서 메인 화면, Dynamic Island, 잠금 화면 스크린샷을 찍습니다. 그 스크린샷으로 확인합니다.

## 방향
- **세계:** e스포츠 방송 화면의 드래프트 방입니다. 바탕은 남보라색이고, 금색 로고와 바이올렛 빛을 씁니다. 브롤러 카드는 희귀도 색으로 칠합니다.
- **순간:** S-TIER 카드에서 희귀도 색으로 빛나는 브롤러 카드 세 장과, 갈색 그림자가 진 금색 큰 점수가 눈에 들어오는 순간입니다.

## 토큰 (`Design/Theme.swift` = 웹 `:root`)
| 이름 | 값 | 웹 |
|---|---|---|
| background / background2 / panel | `#0B0A1F` / `#141235` / `#1B1846` | `--bg` `--bg2` `--panel` |
| deep / track / line | `#0D0B26` / `#0A0920` / `#2E2A6B` | 카드·박스 바탕, 막대 바탕, `--line` |
| text / secondaryText | `#F3F1FF` / `#9C97D6` | `--fg` `--dim` |
| accent(금) / gold2 / goldInk / goldShadow | `#FFCF1F` / `#FF9F1C` / `#2A1600` / `#6B2F00` | `--gold` `--gold2`, 태그 글자, 로고 그림자 |
| blue / violet / error / positive | `#2EA8FF` / `#9B5CFF` / `#FF3D6E` / `#36E39B` | `--blue` `--violet` `--red` `--green` |
| 희귀도 | 엔진 `rarity` (Brawlify 색) | `.br --rc` |

## 글꼴 (`Resources/Fonts`, SIL OFL)
- **Lilita One:** 로고, 순위, 점수, 승률 같은 영문과 숫자에 씁니다. 한글 글리프가 없습니다.
- **Black Han Sans:** 맵 이름, 제목, 브롤러 이름, 버튼 같은 한글 제목에 씁니다.
- **JetBrains Mono:** 칩, 눈썹(MAP INTEL), 영문 이름, 픽 태그, 실전 효과 같은 보조 정보에 씁니다.
- 본문(근거 문장)은 시스템 글꼴을 씁니다. 앱은 `relativeTo:`로 Dynamic Type을 따르고, Live Activity는 고정 크기(최소 11pt)를 씁니다.

## 구성
- **머리:** 금색 그라데이션 "DRAFT ROOM" 로고(갈색 그림자, -6° 기울임)와 "브롤스타즈 조합 연구소"를 둡니다. 그 아래에 LIVE(빨간 점)·맵 풀·브롤러 칩을 둡니다. 배경은 남보라 바탕에 바이올렛 빛과 고정된 금·보라 입자입니다.
- **MAP INTEL:** 금색 모노 눈썹 아래에 큰 맵 이름(검은 그림자), 영문 이름, 모드 칩을 둡니다.
- **추천 조합 리스트(웹 `.alt`):** 순위(Lilita, 1위 금색), 희귀도 테두리 초상화와 이름, 오른쪽에 추정 승률(Lilita)과 종합 점수(모노)를 둡니다. 선택한 줄은 금색 테두리와 빛으로 표시합니다.
- **선택 조합 카드(웹 `.card.best`):** S-TIER 태그와 BEST TEAM 아래에 브롤러 카드(희귀도 빛·테두리, 픽 태그, 역할 알약, 실전 효과)를 둡니다. 이어서 큰 점수와 KPI(추정 승률·시뮬레이션·카운터 내성), 평가 막대(높으면 금, 낮으면 빨강, 보통은 바이올렛→블루), 박스(왜 이 조합인가·드래프트 순서·밴 추천)를 둡니다.
- **주 동작:** 하단에 고정한 금색 그라데이션 버튼입니다. 글자는 진한 갈색, 그림자는 갈색입니다. 종료 버튼은 빨간 테두리를 씁니다.
- **Dynamic Island·잠금 화면:** 상위 3개 조합을 웹 `.alt` 축소판으로 한 줄씩 보여 줍니다. 진한 바탕에 선 색 테두리를 두르고, 1위는 금색 테두리입니다. 각 줄은 순위(Lilita), 희귀도 초상화와 이름(Black Han Sans), 추정 승률(Lilita)입니다. 잠금 화면 바탕은 `background2`이고 금색 "DRAFT ROOM" 작은 로고를 둡니다. 축소형은 1위 초상화와 1위 승률, 최소형은 1위 승률입니다. 키라인은 금색입니다.
- **HIG에서 지키는 것:** 탭 영역 44pt 이상, Live Activity 높이 160pt 이하와 잠금 화면 여백 14pt를 지킵니다. LIVE 점 깜빡임은 동작 줄이기 설정을 따릅니다. 종료된 Live Activity는 15분 뒤 사라집니다.
