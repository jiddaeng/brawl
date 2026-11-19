// 실행: node --test server/live-activity-relay/brawlstars.test.mjs
// 가짜 공식 API(fetch)로 확인한다. 실제 api.brawlstars.com 호출은 키(서버 IP 등록)가 있어야 해서 배포 후 확인한다.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { normalizeTag, parseBsTime, slimPlayer, slimBattles, slimRotation, TTLCache, BrawlStarsClient, handleBrawlStars } from './brawlstars.mjs';
import { RateLimiter } from './relay.mjs';
import { createServer } from './server.mjs';

// 공식 API 응답 모양 (developer.brawlstars.com 문서의 필드). 값은 예시
const PLAYER = {
  tag: '#2PP', name: 'Tester', nameColor: '0xffffffff', trophies: 31000, expLevel: 200, club: { tag: '#ABC', name: 'Club' },
  brawlers: [
    { id: 16000015, name: 'PIPER', power: 11, rank: 30, trophies: 900, gadgets: [], starPowers: [], gears: [] },
    { id: 16000106, name: 'BOLT', power: 7, rank: 12, trophies: 400, gadgets: [], starPowers: [], gears: [] },
  ],
};
const BATTLELOG = { items: [
  { battleTime: '20261119T020000.000Z', event: { id: 15000132, mode: 'bounty', map: 'Shooting Star' },
    battle: { mode: 'bounty', type: 'ranked', result: 'victory', duration: 120, starPlayer: { tag: '#OTHER', name: 'X' },
      teams: [[{ tag: '#2PP', name: 'Tester', brawler: { id: 16000015, name: 'PIPER', power: 11, trophies: 900 } }], [{ tag: '#OTHER', name: 'Other', brawler: { id: 1, name: 'A' } }]] } },
] };
const ROTATION = [
  { startTime: '20261119T000000.000Z', endTime: '20261120T000000.000Z', slotId: 1, event: { id: 15000132, mode: 'bounty', map: 'Shooting Star' } },
  { startTime: '20261119T000000.000Z', endTime: '20261120T000000.000Z', slotId: 2, event: { id: 15000005, mode: 'gemGrab', map: 'Hard Rock Mine' } },
];

function fakeFetch(calls) {
  return async (url, init) => {
    calls.push({ url, auth: init.headers.authorization });
    const path = url.replace('https://api.brawlstars.com/v1', '');
    const json = path === '/events/rotation' ? ROTATION : path === '/players/%232PP' ? PLAYER : path === '/players/%232PP/battlelog' ? BATTLELOG : null;
    return { ok: !!json, status: json ? 200 : 404, json: async () => json };
  };
}

test('태그 정리: # 생략·소문자·O→0 허용, 잘못된 글자 거부', () => {
  assert.equal(normalizeTag('2pp'), '#2PP');
  assert.equal(normalizeTag('%232PP'), '#2PP');
  assert.equal(normalizeTag(' #Y0 LQ '), '#Y0LQ');
  assert.equal(normalizeTag('#yolq'), '#Y0LQ');
  for (const bad of ['', '#A1', '../x', '#2PP?x=1', 'x'.repeat(20)]) assert.throws(() => normalizeTag(bad));
});

test('시각 형식 변환', () => {
  assert.equal(parseBsTime('20261119T020000.000Z'), '2026-11-19T02:00:00.000Z');
  assert.equal(parseBsTime('nope'), null);
});

test('최소 정보만: 보유 브롤러는 id·파워, 전적은 다른 플레이어 정보 없이', () => {
  const p = slimPlayer(PLAYER);
  assert.deepEqual(p, { tag: '#2PP', name: 'Tester', trophies: 31000, brawlers: [{ id: 16000015, power: 11 }, { id: 16000106, power: 7 }] });
  const b = slimBattles(BATTLELOG);
  assert.deepEqual(b, [{ at: '2026-11-19T02:00:00.000Z', mode: 'bounty', mapId: 15000132, map: 'Shooting Star', result: 'victory' }]);
  assert.ok(!JSON.stringify(b).includes('OTHER'));
  assert.equal(slimRotation(ROTATION).length, 2);
  assert.deepEqual(slimRotation(ROTATION)[1], { slot: 2, start: '2026-11-19T00:00:00.000Z', end: '2026-11-20T00:00:00.000Z', mode: 'gemGrab', mapId: 15000005, map: 'Hard Rock Mine' });
});

test('플레이어 요청: 공식 API 를 키와 함께 부르고, 1분 캐시', async () => {
  const calls = [];
  const deps = { client: new BrawlStarsClient({ apiKey: 'k', fetchImpl: fakeFetch(calls) }), cache: new TTLCache(), limiter: new RateLimiter({ minIntervalMs: 0 }), clientKey: '1.2.3.4' };
  const r = await handleBrawlStars('GET', '/v1/brawlstars/player/%232pp', deps);
  assert.equal(r.status, 200);
  assert.equal(r.body.player.brawlers.length, 2);
  assert.equal(r.body.player.recent[0].mapId, 15000132);
  assert.equal(calls.length, 2);
  assert.ok(calls.every(c => c.auth === 'Bearer k'));
  await handleBrawlStars('GET', '/v1/brawlstars/player/2PP', deps);
  assert.equal(calls.length, 2, '캐시');
});

test('없는 플레이어 404, 키 없는 서버 503, 모르는 경로 404', async () => {
  const deps = { client: new BrawlStarsClient({ apiKey: 'k', fetchImpl: fakeFetch([]) }), cache: new TTLCache(), limiter: new RateLimiter({ minIntervalMs: 0 }) };
  await assert.rejects(handleBrawlStars('GET', '/v1/brawlstars/player/2PPP', deps), e => e.status === 404);
  await assert.rejects(handleBrawlStars('GET', '/v1/brawlstars/rotation', { ...deps, client: null }), e => e.status === 503);
  await assert.rejects(handleBrawlStars('GET', '/v1/brawlstars/clubs/x', deps), e => e.status === 404);
  assert.equal(await handleBrawlStars('GET', '/v1/live-activity', deps), null);
});

test('HTTP 서버: 로테이션 응답, APNs 미설정이면 live-activity 503', async () => {
  const srv = createServer({ brawlStars: new BrawlStarsClient({ apiKey: 'k', fetchImpl: fakeFetch([]) }) });
  await new Promise(r => srv.listen(0, r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  try {
    const rot = await (await fetch(base + '/v1/brawlstars/rotation')).json();
    assert.equal(rot.rotation[0].map, 'Shooting Star');
    const la = await fetch(base + '/v1/live-activity', { method: 'POST', body: '{}' });
    assert.equal(la.status, 503);
    const h = await (await fetch(base + '/healthz')).json();
    assert.deepEqual(h, { ok: true, liveActivity: false, brawlStars: true });
  } finally { srv.close(); }
});

test('iOS 가 읽는 응답 예시(tests/app-fixtures)가 서버 출력 형식과 같다', () => {
  const p = JSON.parse(fs.readFileSync(new URL('../../tests/app-fixtures/player.json', import.meta.url)));
  const r = JSON.parse(fs.readFileSync(new URL('../../tests/app-fixtures/rotation.json', import.meta.url)));
  assert.deepEqual(Object.keys(p.player).sort(), ['brawlers', 'name', 'recent', 'tag', 'trophies']);
  for (const e of r.rotation) assert.deepEqual(Object.keys(e).sort(), ['end', 'map', 'mapId', 'mode', 'slot', 'start']);
});
