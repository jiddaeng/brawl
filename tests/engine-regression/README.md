# 추천 엔진 회귀 테스트

웹(`index.html`)과 iOS 앱이 함께 쓰는 `engine/draft-engine.js`가 운영 중인 웹 결과와 같은 값을 내는지 확인합니다.
입력은 녹화해 둔 실제 API 응답(`fixtures/`)이라 네트워크 상태나 데이터 갱신과 무관하게 같은 결과가 나옵니다.

| 단계 | 명령 | 확인 내용 |
|---|---|---|
| 녹화 | `node tests/engine-regression/record.mjs` | Brawlify·BrawlTime 응답과 맵 이미지 18개를 `fixtures/`에 저장 |
| 웹 정답 | `node tests/engine-regression/web-golden.cjs` | 엔진 분리 전 웹(기본 `4b9f7f5`)과 현재 웹의 결과 화면이 같은지 비교하고, 결과 카드 DOM에서 `golden.json` 생성 |
| 엔진 비교 | `node tests/engine-regression/compare.cjs` | JavaScriptCore(`jsc --useJIT=false`, iOS 앱과 같은 조건)로 `DraftEngine.recommend`를 돌려 `golden.json`과 비교 |
| | `... compare.cjs --node` | Node(V8)로 같은 비교 |
| | `... compare.cjs --results <파일>` | iOS 테스트가 저장한 결과 파일과 비교 |

시나리오: 맵 18개(랭크 6개 모드 × 2, 5v5 2개, 쇼다운 3개, 듀얼) × 기본 / 고정 픽 1·2명 / 상대 픽 2명 / 밴 2명 + 상대 1명.
각 시나리오에서 1위 조합과, 대안 조합을 눌러 메인으로 올린 화면까지 모두 비교합니다.

필요한 도구: Node 18+, Playwright(Chromium), `jsc`(Ubuntu: `apt install libjavascriptcoregtk-bin`, macOS: `/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc`).
