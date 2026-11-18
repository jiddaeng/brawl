// 실제 API 응답을 녹화해 회귀 테스트 입력(fixtures)으로 저장한다.
// 실행: node tests/engine-regression/record.mjs   (인터넷 필요. 녹화본을 바꾸면 golden 도 다시 만들어야 한다)
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const out = path.join(here, 'fixtures');
fs.mkdirSync(path.join(out, 'stats'), { recursive: true });
fs.mkdirSync(path.join(out, 'maps'), { recursive: true });

const getJSON = async u => { const r = await fetch(u); if (!r.ok) throw new Error(r.status + ' ' + u); return r.json(); };
const getBin = async u => { const r = await fetch(u); if (!r.ok) return null; return Buffer.from(await r.arrayBuffer()); };

// 웹 페이지(loadSources)와 같은 slim 형식으로 저장
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(root, 'engine/draft-engine.js'), 'utf8'), ctx);
const slimMap = m => ({ id: m.id, name: m.name, imageUrl: m.imageUrl, disabled: m.disabled, new: m.new, gameMode: { name: m.gameMode.name, imageUrl: m.gameMode.imageUrl, color: m.gameMode.color }, environment: m.environment ? { name: m.environment.name } : null });
const slimBrawler = b => ({ id: b.id, name: b.name, imageUrl2: b.imageUrl2, released: b.released, class: b.class ? { name: b.class.name } : null, rarity: b.rarity ? { color: b.rarity.color } : null });

const maps = (await getJSON('https://api.brawlapi.com/v1/maps')).list.map(slimMap);
const brawlers = (await getJSON('https://api.brawlapi.com/v1/brawlers')).list.map(slimBrawler);
const strength = await getJSON('https://brawltime.ninja/media/brawler-strength.json');
fs.writeFileSync(path.join(out, 'maps.json'), JSON.stringify({ list: maps }));
fs.writeFileSync(path.join(out, 'brawlers.json'), JSON.stringify({ list: brawlers }));
fs.writeFileSync(path.join(out, 'strength.json'), JSON.stringify(strength));

// 테스트 대상 맵: 랭크 6개 모드 × 2개 + 5v5·쇼다운·듀얼 등 모드별 1개
const cat = vm.runInContext('DraftEngine', ctx).load(maps, brawlers, strength);
const chosen = [];
for (const mode of ['Gem Grab', 'Brawl Ball', 'Heist', 'Bounty', 'Hot Zone', 'Knockout']) chosen.push(...cat.maps.filter(m => m.mode === mode && typeof m.id === 'number').slice(0, 2));
for (const mode of ['Brawl Ball 5v5', 'Knockout 5v5', 'Duo Showdown', 'Trio Showdown', 'Solo Showdown', 'Duels']) { const m = cat.maps.find(m => m.mode === mode && typeof m.id === 'number'); if (m) chosen.push(m); }

const recorded = [];
for (const m of chosen) {
  const rec = { id: m.id, name: m.name, mode: m.mode, stats: null, image: null };
  if (m.bt) {
    const k = m.bt.mode + '/' + m.bt.slug;
    try { fs.writeFileSync(path.join(out, 'stats', k.replace('/', '__') + '.json'), JSON.stringify(await getJSON(`https://brawltime.ninja/media/brawler-strength/${k}.json`))); rec.stats = k; } catch (e) { /* 웹과 같이 통계 없음으로 처리 */ }
  }
  for (const u of m.images) { const b = await getBin(u); if (b) { fs.writeFileSync(path.join(out, 'maps', m.id + '.png'), b); rec.image = u; break; } }
  recorded.push(rec);
  console.log(m.id, m.mode, m.name, rec.stats ? 'stats' : '-', rec.image ? 'img' : '-');
}
fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify({ recordedAt: new Date().toISOString(), maps: recorded }, null, 1));
