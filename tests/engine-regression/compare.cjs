// golden.json(웹 결과 카드) 과 DraftEngine.recommend 결과(JavaScriptCore 또는 Node)를 비교한다.
// 실행: node tests/engine-regression/compare.cjs            → jsc(JIT 끔)로 실행해 비교
//       node tests/engine-regression/compare.cjs --node     → Node(V8)로 실행해 비교
//       node tests/engine-regression/compare.cjs --results <file>  → 다른 호스트(iOS 등)가 저장한 결과 파일과 비교
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { execFileSync } = require('child_process');
const root = path.resolve(__dirname, '../..');
const golden = JSON.parse(fs.readFileSync(path.join(__dirname, 'golden.json'), 'utf8'));

let results, label, timing = '';
const ri = process.argv.indexOf('--results');
if (ri > 0) { results = JSON.parse(fs.readFileSync(process.argv[ri + 1], 'utf8')).results; label = process.argv[ri + 1]; }
else if (process.argv.includes('--node')) {
  const ctx = vm.createContext({ arguments: [root], load: f => vm.runInContext(fs.readFileSync(f, 'utf8'), ctx), readFile: f => fs.readFileSync(f, 'utf8'), print: s => { ctx.__out = s; } });
  vm.runInContext(fs.readFileSync(path.join(__dirname, 'jsc-driver.js'), 'utf8'), ctx);
  const o = JSON.parse(ctx.__out); results = o.results; label = 'Node (V8)'; timing = ` · 전체 ${o.totalMs}ms, 시나리오 최대 ${o.maxMs}ms`;
} else {
  const o = JSON.parse(execFileSync('jsc', ['--useJIT=false', path.join(__dirname, 'jsc-driver.js'), '--', root], { maxBuffer: 1 << 28 }).toString());
  results = o.results; label = 'JavaScriptCore (JIT 끔)'; timing = ` · 전체 ${o.totalMs}ms, 시나리오 최대 ${o.maxMs}ms`;
}

// 웹 결과 카드와 같은 모양으로 변환 (표시 문구는 index.html renderResult 와 같다)
const pct = v => Math.round(v * 100);
const unesc = s => s.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
function view(R, k) {
  const L = R.teams.slice(); [L[0], L[k]] = [L[k], L[0]];
  const T = L[0], size = R.map.size;
  const koById = {}; R.teams.forEach(t => t.members.forEach(m => koById[m.id] = m.ko));
  const ordered = T.members.filter(m => m.pick).sort((a, b) => a.pick - b.pick);
  return {
    archetype: T.archetype,
    members: T.members.map(m => ({ name: m.name, role: m.role, pick: m.pick ? m.pick + '픽' : null, eff: m.eff == null ? null : `실전 ${m.eff >= 0 ? '+' : ''}${(m.eff * 100).toFixed(1)}%p` })),
    score: T.score,
    kpi: [T.estimatedWinRate + '%', R.count.toLocaleString(), String(pct(T.f.counter))],
    bars: T.factors.map(f => [f.label, pct(f.value)]),
    reasons: T.reasons.map(unesc),
    order: size > 1 ? ordered.map((m, i) => `${i + 1}픽 ${m.ko} — ${i === 0 ? '카운터가 적어 블라인드 픽으로 안전' : i === ordered.length - 1 ? '카운터당하기 쉬워 마지막에 상대를 보고 확정' : '중간 픽, 상대 첫 픽에 맞춰 교체 가능'}`) : [],
    threats: T.threats.map(t => t.ko),
    alts: L.slice(1).map(o => ({ names: o.ids.map(id => koById[id]).join(' · '), ar: `${o.archetype} · 맵 ${pct(o.f.mapN)} · 밸런스 ${pct(o.f.balance)} · 내성 ${pct(o.f.counter)}`, score: o.score })),
  };
}

let ok = 0, bad = 0;
golden.cases.forEach((c, i) => {
  const R = results[i];
  const got = R.teams.map((_, k) => view(R, k));
  const a = JSON.stringify(got), b = JSON.stringify(c.expected);
  if (a === b) ok += c.expected.length;
  else {
    bad++;
    console.log(`DIFF  map ${c.map} ${c.mode} ${c.scenario.name}`);
    c.expected.forEach((e, k) => { const g = got[k]; for (const key of Object.keys(e)) if (JSON.stringify(e[key]) !== JSON.stringify(g && g[key])) console.log(`   #${k + 1} ${key}\n     web: ${JSON.stringify(e[key])}\n     got: ${JSON.stringify(g && g[key])}`); });
  }
});
console.log(`${label}: 조합 ${ok}개 일치, 시나리오 ${bad}개 불일치 (전체 ${golden.cases.length} 시나리오)${timing}`);
process.exit(bad ? 1 : 0);
