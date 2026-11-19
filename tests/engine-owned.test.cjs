// 보유 브롤러 옵션(opt.owned) 테스트: 우리 팀 후보만 보유 브롤러로 줄고, 없으면 결과가 그대로인지
// 실행: node --test tests/engine-owned.test.cjs
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const fx = path.join(root, 'tests/engine-regression/fixtures/');
const J = f => JSON.parse(fs.readFileSync(f, 'utf8'));
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'engine/draft-engine.js'), 'utf8') + '\nthis.DraftEngine=DraftEngine;', ctx);
const E = ctx.DraftEngine;
const cat = E.load(J(fx + 'maps.json').list, J(fx + 'brawlers.json').list, J(fx + 'strength.json'));
const golden = J(path.join(root, 'tests/engine-regression/golden.json'));
const c3 = golden.cases.find(c => c.scenario.lock.length === 0 && c.scenario.enemy.length === 0 && c.scenario.ban.length === 0 && /^(Gem Grab|Bounty|Knockout|Brawl Ball|Hot Zone|Heist)$/.test(cat.maps.find(m => m.id === c.map)?.mode || ''));
const run = opt => JSON.parse(JSON.stringify(E.recommend(c3.map, c3.feat, opt)));

test('owned 가 없으면(null·생략) 기존 결과와 같다', () => {
  assert.deepEqual(run({}), run({ owned: null }));
});

test('owned 를 주면 모든 추천 조합이 보유 브롤러로만 구성된다', () => {
  const all = run({});
  // 기본 1위 조합의 브롤러 하나를 빼고, 나머지 브롤러 절반 정도만 보유했다고 가정
  const removed = all.teams[0].ids[0];
  const owned = cat.brawlers.map(b => b.id).filter((id, i) => id !== removed && i % 2 === 0);
  const r = run({ owned });
  assert.ok(r.teams.length >= 1);
  for (const t of r.teams) for (const id of t.ids) assert.ok(owned.includes(id), `보유하지 않은 ${id}`);
  // 상대 위협(카운터)은 전체 풀 기준이라 보유하지 않은 브롤러도 나올 수 있다
  assert.equal(r.poolSize, all.poolSize);
});

test('고정 픽은 보유 목록에 없어도 유지된다', () => {
  const lock = [cat.brawlers[1].id];
  const owned = cat.brawlers.slice(10, 60).map(b => b.id);
  const r = run({ owned, lock });
  for (const t of r.teams) {
    assert.ok(t.ids.includes(lock[0]));
    for (const id of t.ids) if (id !== lock[0]) assert.ok(owned.includes(id));
  }
});

test('보유 브롤러가 팀 인원보다 적으면 조합이 없다', () => {
  const r = run({ owned: cat.brawlers.slice(0, 2).map(b => b.id) });
  assert.equal(r.teams.length, 0);
});
