// JavaScriptCore 셸용 드라이버: iOS 앱과 같은 방식(DraftEngine 호스트 API)으로 golden 시나리오를 계산해 JSON 으로 출력한다.
// 실행: jsc --useJIT=false tests/engine-regression/jsc-driver.js -- <레포 루트>
// (iOS 앱의 JSContext 는 JIT 없이 인터프리터로 돌기 때문에 --useJIT=false 로 같은 조건을 만든다)
const root = arguments[0];
const fx = root + '/tests/engine-regression/fixtures/';
load(root + '/engine/draft-engine.js');
const J = f => JSON.parse(readFile(f));
const golden = J(root + '/tests/engine-regression/golden.json');
const t0 = Date.now();
DraftEngine.load(J(fx + 'maps.json').list, J(fx + 'brawlers.json').list, J(fx + 'strength.json'));
const statsCache = {};
const out = [];
let maxMs = 0;
for (const c of golden.cases) {
  const stats = c.stats ? (statsCache[c.stats] = statsCache[c.stats] || DraftEngine.parseStats(J(fx + 'stats/' + c.stats.replace('/', '__') + '.json'))) : null;
  const s = Date.now();
  const r = DraftEngine.recommend(c.map, c.feat, { stats, lock: c.scenario.lock, enemy: c.scenario.enemy, ban: c.scenario.ban });
  maxMs = Math.max(maxMs, Date.now() - s);
  out.push(r);
}
print(JSON.stringify({ totalMs: Date.now() - t0, maxMs, results: out }));
