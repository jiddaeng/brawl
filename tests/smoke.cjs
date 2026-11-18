// DRAFT ROOM 스모크 테스트: 실제 API로 페이지를 띄워 주요 동작을 확인한다.
// 실행: node tests/smoke.cjs   (Playwright + Chromium 필요, 인터넷 연결 필요)
const path = require('path');
const assert = require('assert');
const { chromium } = require('playwright');

const PAGE = 'file://' + path.resolve(__dirname, '..', 'index.html');
const results = [];
async function check(name, fn) {
  try { await fn(); results.push(['PASS', name]); }
  catch (e) { results.push(['FAIL', name, e.message]); }
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 1000 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));

  await page.goto(PAGE);
  await page.waitForSelector('.card.best', { timeout: 60000 });

  // 3v3 랭크 맵 하나를 골라 엔진을 다시 돌리는 도우미
  const pickMap = kind => page.evaluate(async kind => {
    const m = DATA.maps.find(m => inPool(m) && RANKED.includes(m.mode) && modeProfile(m.mode).kind === kind && modeProfile(m.mode).size === 3);
    selectMap(m.id);
    for (let i = 0; i < 100 && !FEAT_CACHE[m.id]; i++) await new Promise(r => setTimeout(r, 100));
    await new Promise(r => setTimeout(r, 1500)); // 실전 통계 로딩 대기
    return m.mode;
  }, kind);
  const rerun = () => page.evaluate(() => runEngine(FEAT_CACHE[STATE.map.id], false));

  await check('페이지 로딩 중 에러 없음', async () => assert.deepStrictEqual(errors, []));

  await check('데이터 로딩: 브롤러·맵·현재 맵 풀', async () => {
    const d = await page.evaluate(() => ({ b: DATA.brawlers.length, m: DATA.maps.length, live: DATA.maps.filter(inPool).length }));
    assert(d.b > 50 && d.m > 100 && d.live > 20, JSON.stringify(d));
  });

  await pickMap('gem');
  for (const n of [0, 1, 2]) {
    await check(`3v3 고정 픽 ${n}명 → 대안 조합이 남아 있음`, async () => {
      await page.evaluate(n => { STATE.lock = DATA.pool.slice(0, n).map(b => b.id); STATE.enemy = []; STATE.ban = []; }, n);
      await rerun();
      const alts = await page.evaluate(() => document.querySelectorAll('.alt').length);
      assert(alts >= 1, `대안 ${alts}개`);
    });
  }

  await check('고정 픽 2명이면 대안 조합끼리 세 번째 브롤러가 모두 다름', async () => {
    await page.evaluate(() => { STATE.lock = DATA.pool.slice(0, 2).map(b => b.id); });
    await rerun();
    const ok = await page.evaluate(() => {
      const R = solve(modeProfile(STATE.map.mode), demands(FEAT_CACHE[STATE.map.id], modeProfile(STATE.map.mode)));
      const third = R.list.map(o => o.team.find(b => !STATE.lock.includes(b.id)).id);
      return new Set(third).size === third.length;
    });
    assert(ok);
  });

  for (const kind of ['gem', 'ball', 'heist', 'pick', 'zone']) {
    await check(`${kind}: 역할이 겹치지 않고 필수 역할이 배정됨, 포지션과 어긋난 역할 없음`, async () => {
      const mode = await pickMap(kind);
      const r = await page.evaluate(() => {
        const mp = modeProfile(STATE.map.mode);
        const out = [];
        for (const o of solve(mp, demands(FEAT_CACHE[STATE.map.id], mp)).list) {
          const roles = assignRoles(o.team, mp);
          out.push(roles.map(x => [x.b.name, x.b.prof.p, x.role]));
        }
        return { out, req: ROLE_POOL[mp.kind].filter(r => r.req).map(r => r.n) };
      });
      for (const team of r.out) {
        const names = team.map(x => x[2]);
        assert.strictEqual(new Set(names).size, names.length, `${mode} 역할 중복: ${JSON.stringify(team)}`);
        for (const req of r.req) assert(names.includes(req), `${mode} 필수 역할 ${req} 없음: ${JSON.stringify(team)}`);
        for (const [n, p, role] of team) {
          // 프론트라인 탱커가 '안전한 백업'·'저격 앵커'로, 저격수가 '전방 탱커'로 표시되면 안 됨
          if (p === 'F') assert(!['안전한 백업', '저격 앵커'].includes(role), `${n}(F) → ${role}`);
          if (p === 'B') assert(!['전방 탱커', '탱커 방어', '전방 압박'].includes(role), `${n}(B) → ${role}`);
        }
      }
    });
  }

  await pickMap('gem');
  await check('밴하면 상대 픽에서도 빠짐', async () => {
    const r = await page.evaluate(() => {
      const id = DATA.pool[5].id;
      STATE.lock = []; STATE.ban = []; STATE.enemy = [id];
      runEngine(FEAT_CACHE[STATE.map.id], false);
      const sel = document.querySelector('#selB'); sel.value = String(id); sel.onchange({ target: sel });
      return { enemy: STATE.enemy.includes(id), ban: STATE.ban.includes(id) };
    });
    assert(r.ban && !r.enemy, JSON.stringify(r));
  });

  await check('밴한 브롤러는 상대 픽 목록에 없고, 추가도 거부됨', async () => {
    const r = await page.evaluate(() => {
      const id = STATE.ban[0];
      const listed = [...document.querySelectorAll('#selE option')].some(o => +o.value === id);
      const sel = document.querySelector('#selE');
      const opt = document.createElement('option'); opt.value = String(id); sel.append(opt); sel.value = String(id);
      sel.onchange({ target: sel });
      return { listed, added: STATE.enemy.includes(id) };
    });
    assert(!r.listed && !r.added, JSON.stringify(r));
  });

  await check('API 장애 시 저장본으로 페이지가 뜸', async () => {
    const p2 = await ctx.newPage(); // 같은 컨텍스트 → 앞에서 저장된 localStorage 공유
    const errs2 = [];
    p2.on('pageerror', e => errs2.push(e.message));
    await p2.route(/brawlapi\.com|brawltime\.ninja\/media\/brawler-strength\.json/, r => r.abort());
    await p2.goto(PAGE);
    await p2.waitForSelector('.card.best', { timeout: 60000 });
    const live = await p2.textContent('#live');
    assert(/저장본/.test(live), live);
    assert.deepStrictEqual(errs2, []);
    await p2.close();
  });

  await browser.close();
  for (const [s, n, m] of results) console.log(`${s}  ${n}${m ? '\n      ' + m : ''}`);
  const failed = results.filter(r => r[0] === 'FAIL').length;
  console.log(`\n${results.length - failed}/${results.length} 통과`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
