// 녹화된 API 응답으로 (1) 엔진 분리 전 웹 페이지 (2) 현재 웹 페이지를 띄워 결과 화면이 완전히 같은지 확인하고,
// 현재 웹 페이지의 결과 카드 DOM 에서 정답(golden.json)을 뽑는다. iOS·JavaScriptCore 비교는 이 정답을 기준으로 한다.
// 실행: node tests/engine-regression/web-golden.cjs [기준 커밋=4b9f7f5]
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');
const { chromium } = require('playwright');

const here = __dirname, root = path.resolve(here, '../..'), fx = path.join(here, 'fixtures');
const baseRef = process.argv[2] || '4b9f7f5';
const manifest = JSON.parse(fs.readFileSync(path.join(fx, 'manifest.json'), 'utf8'));

// 분리 전 페이지는 단일 파일이므로 임시 폴더에 꺼내 둔다
const oldDir = fs.mkdtempSync(path.join(os.tmpdir(), 'draftroom-old-'));
fs.writeFileSync(path.join(oldDir, 'index.html'), execSync(`git -C "${root}" show ${baseRef}:index.html`));

const CORS = { 'access-control-allow-origin': '*' };
async function serveFixtures(page) {
  await page.route('**/*', route => {
    const u = new URL(route.request().url());
    const send = (file, type) => fs.existsSync(file) ? route.fulfill({ status: 200, headers: { ...CORS, 'content-type': type }, body: fs.readFileSync(file) }) : route.fulfill({ status: 404, headers: CORS, body: '' });
    if (u.protocol === 'file:') return route.continue();
    if (u.host === 'api.brawlapi.com' && u.pathname === '/v1/maps') return send(path.join(fx, 'maps.json'), 'application/json');
    if (u.host === 'api.brawlapi.com' && u.pathname === '/v1/brawlers') return send(path.join(fx, 'brawlers.json'), 'application/json');
    if (u.host === 'brawltime.ninja' && u.pathname === '/media/brawler-strength.json') return send(path.join(fx, 'strength.json'), 'application/json');
    let m;
    if (u.host === 'brawltime.ninja' && (m = u.pathname.match(/^\/media\/brawler-strength\/([^/]+)\/([^/]+)\.json$/))) return send(path.join(fx, 'stats', m[1] + '__' + m[2] + '.json'), 'application/json');
    if ((m = u.pathname.match(/\/maps\/(?:regular\/)?(\d+)\.png$/))) return send(path.join(fx, 'maps', m[1] + '.png'), 'image/png');
    return route.abort(); // 폰트·브롤러 이미지 등 계산과 무관한 리소스
  });
}

// 웹 결과 카드(#res)에서 사용자에게 보이는 값만 읽는다
const READ_CARD = () => {
  const q = (s, r = document) => [...r.querySelectorAll(s)];
  const best = document.querySelector('#res .card.best');
  if (!best) return null;
  const boxes = q('.cols .box', best);
  return {
    archetype: best.querySelector('h3').textContent.replace(/^S-TIER최적 조합 · /, ''),
    members: q('.br', best).map(c => ({ name: c.querySelector('.en').textContent.split(' · ')[0], role: c.querySelector('.role').textContent, pick: c.querySelector('.pk')?.textContent || null, eff: c.querySelector('.eff')?.textContent || null })),
    score: +best.querySelector('.big').dataset.count,
    kpi: q('.kpi b', best).map(b => b.textContent),
    bars: q('.bar .t', best).map(t => [t.firstChild.textContent, +t.querySelector('b').textContent]),
    reasons: q('li', boxes[0]).map(li => li.textContent),
    order: boxes.length === 3 ? q('li', boxes[1]).map(li => li.textContent) : [],
    threats: q('.mini span', boxes[boxes.length - 1]).map(s => s.textContent),
    alts: q('#res .alt').map(a => ({ names: a.querySelector('.ps > span:not(.ar)').textContent, ar: a.querySelector('.ar').textContent, score: +a.querySelector('.sc').textContent })),
  };
};

async function openPage(browser, file) {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await serveFixtures(page);
  await page.goto('file://' + file);
  await page.waitForSelector('.card.best', { timeout: 60000 });
  return { page, errors };
}

// 맵을 선택하고 이미지 분석·통계 로딩이 끝날 때까지 기다린다
async function select(page, id) {
  await page.evaluate(id => selectMap(id), id);
  await page.waitForFunction(id => {
    const m = STATE.map; if (!m || m.id !== id || !FEAT_CACHE[id]) return false;
    return !m.bt || ((m.bt.mode + '/' + m.bt.slug) in STATS);
  }, id, { timeout: 60000 });
  await page.waitForTimeout(50);
}

// 시나리오별 결과: 기본 + 대안 조합을 메인으로 올린 화면까지
async function runScenario(page, sc) {
  return page.evaluate(([sc, READ]) => {
    const read = eval('(' + READ + ')');
    STATE.lock = sc.lock.slice(); STATE.enemy = sc.enemy.slice(); STATE.ban = sc.ban.slice();
    runEngine(FEAT_CACHE[STATE.map.id], false);
    const html = document.querySelector('#res').innerHTML;
    const views = [read()];
    const n = document.querySelectorAll('#res .alt').length;
    for (let i = 1; i <= n; i++) { runEngine(FEAT_CACHE[STATE.map.id], false); document.querySelector(`#res [data-alt="${i}"]`).click(); views.push(read()); }
    return { html, views, feat: Object.fromEntries(Object.entries(FEAT_CACHE[STATE.map.id]).filter(([k]) => k !== 'tiles')) };
  }, [sc, READ_CARD.toString()]);
}

(async () => {
  const browser = await chromium.launch();
  const cur = await openPage(browser, path.join(root, 'index.html'));
  const old = await openPage(browser, path.join(oldDir, 'index.html'));
  const golden = { baseRef, recordedAt: manifest.recordedAt, cases: [] };
  let same = 0, diff = 0;
  for (const m of manifest.maps) {
    await select(cur.page, m.id); await select(old.page, m.id);
    // 시나리오의 브롤러는 기본 추천의 개인 적합도 순위에서 고른다 (두 페이지에 같은 id 를 쓴다)
    const P = await cur.page.evaluate(() => { STATE.lock = []; STATE.enemy = []; STATE.ban = []; runEngine(FEAT_CACHE[STATE.map.id], false); return { pool: DATA.pool.map(b => b.id), size: modeProfile(STATE.map.mode).size }; });
    const p = P.pool, scs = [
      { name: 'base', lock: [], enemy: [], ban: [] },
      { name: 'lock1', lock: [p[0]], enemy: [], ban: [] },
      ...(P.size >= 3 ? [{ name: 'lock2', lock: [p[0], p[1]], enemy: [], ban: [] }] : []),
      ...(P.size >= 2 ? [{ name: 'enemy2', lock: [], enemy: [p[2], p[5]], ban: [] }] : []),
      { name: 'ban2enemy1', lock: [], enemy: P.size >= 2 ? [p[6]] : [], ban: [p[0], p[3]] },
    ];
    for (const sc of scs) {
      const a = await runScenario(cur.page, sc), b = await runScenario(old.page, sc);
      const eq = a.html === b.html && JSON.stringify(a.views) === JSON.stringify(b.views);
      eq ? same++ : diff++;
      if (!eq) console.log(`DIFF  ${m.id} ${m.mode} ${sc.name}`);
      golden.cases.push({ map: m.id, mode: m.mode, scenario: sc, feat: a.feat, stats: m.stats, expected: a.views });
    }
  }
  console.log(`분리 전(${baseRef}) vs 현재 웹: 동일 ${same} / 다름 ${diff}`);
  console.log('페이지 에러:', cur.errors.concat(old.errors).length);
  fs.writeFileSync(path.join(here, 'golden.json'), JSON.stringify(golden));
  console.log(`golden.json: ${golden.cases.length}개 시나리오, 조합 ${golden.cases.reduce((s, c) => s + c.expected.length, 0)}개`);
  await browser.close();
  process.exit(diff || cur.errors.length || old.errors.length ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
