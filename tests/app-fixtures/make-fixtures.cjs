// iOS(BrawlCore)·Android(core) 공용 테스트 입력 생성: 녹화된 API 응답(tests/engine-regression/fixtures)으로 실제 엔진을 돌려
// catalog.json(현재 맵 풀·브롤러)과 result-*.json(추천 결과)을 만든다.  실행: node tests/app-fixtures/make-fixtures.cjs
// recognition-cases.json(화면 인식 공유 테스트 벡터)은 손으로 관리한다.
const fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.resolve(__dirname, '../..'), fx = path.join(root, 'tests/engine-regression/fixtures'), out = __dirname;
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'engine/draft-engine.js'), 'utf8'), ctx);
const E = vm.runInContext('DraftEngine', ctx);
const J = f => JSON.parse(fs.readFileSync(path.join(fx, f), 'utf8'));
const cat = E.load(J('maps.json').list, J('brawlers.json').list, J('strength.json'));
fs.writeFileSync(path.join(out, 'catalog.json'), JSON.stringify(cat));
const golden = JSON.parse(fs.readFileSync(path.join(root, 'tests/engine-regression/golden.json'), 'utf8'));
for (const [name, mapId] of [['result-bounty', 15001395], ['result-5v5', 15001315], ['result-solo', 15001307]]) {
  const c = golden.cases.find(c => c.map === mapId && c.scenario.name === 'base');
  const st = c.stats ? E.parseStats(J('stats/' + c.stats.replace('/', '__') + '.json')) : null;
  fs.writeFileSync(path.join(out, name + '.json'), JSON.stringify(E.recommend(mapId, c.feat, { stats: st })));
}
console.log('maps', cat.maps.length, 'brawlers', cat.brawlers.length);
