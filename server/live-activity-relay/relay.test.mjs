// 실행: node --test server/live-activity-relay/relay.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import http2 from 'node:http2';
import crypto from 'node:crypto';
import { validateRequest, buildPayload, ApnsAuth, ApnsClient, RateLimiter, handle, CONTENT_STATE_KEYS } from './relay.mjs';

// iOS RelayRequest.body() 가 만드는 모양 (BrawlCore RelayTests 와 같은 값)
const iosRequest = () => ({
  token: 'a1b2c3d4' + '0'.repeat(56), environment: 'development', event: 'update',
  contentState: { status: 'ready', mapName: '기습적 움직임', modeName: '바운티', members: [{ id: 16000015, name: '파이퍼' }, { id: 16000109, name: '코스모' }, { id: 16000106, name: '볼트' }],
    score: 84, winRate: '57.5', updatedAt: 3_000_000.5 },
});

test('content-state 키 목록이 iOS 와 같다', () => {
  assert.deepEqual([...CONTENT_STATE_KEYS].sort(), ['mapName', 'members', 'message', 'modeName', 'score', 'status', 'updatedAt', 'winRate']);
});

test('정상 요청 통과', () => { assert.equal(validateRequest(iosRequest()).token.length, 64); });

test('최소 정보만 허용: 모르는 키·URL·큰 값 거부', () => {
  const bad = [
    r => { r.image = 'x'; }, r => { r.contentState.reasons = []; }, r => { r.contentState.members[0].img = 'https://x'; },
    r => { r.contentState.mapName = 'https://evil'; }, r => { r.contentState.message = 'x'.repeat(301); },
    r => { r.contentState.members = Array(6).fill({ id: 1, name: 'a' }); }, r => { r.token = 'not-hex'; },
    r => { r.environment = 'staging'; }, r => { r.contentState.score = 101; }, r => { r.contentState.updatedAt = '2026'; },
    r => { r.contentState.status = 'hacked'; }, r => { r.alert = { title: 'x', body: 'y', sound: 'z' }; },
  ];
  for (const f of bad) { const r = iosRequest(); f(r); assert.throws(() => validateRequest(r), /./); }
});

test('APNs 페이로드: aps 시각은 Unix 초, content-state 는 그대로', () => {
  const r = validateRequest(iosRequest());
  const p = JSON.parse(buildPayload(r, 1_800_000_000));
  assert.equal(p.aps.timestamp, 1_800_000_000);
  assert.equal(p.aps.event, 'update');
  assert.equal(p.aps['stale-date'], 1_800_000_000 + 1800);
  assert.deepEqual(p.aps['content-state'], iosRequest().contentState);
  assert.equal(p.aps.alert, undefined);
  const end = JSON.parse(buildPayload({ ...r, event: 'end' }, 100));
  assert.equal(end.aps['dismissal-date'], 100 + 900);
});

test('JWT: ES256, kid·iss, 서명 검증, 50분 재사용', () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  let t = 1_000_000_000_000;
  const auth = new ApnsAuth({ keyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }), keyId: 'KEY123', teamId: 'TEAM45', now: () => t });
  const jwt = auth.token();
  const [h, c, s] = jwt.split('.');
  assert.deepEqual(JSON.parse(Buffer.from(h, 'base64url')), { alg: 'ES256', kid: 'KEY123' });
  assert.equal(JSON.parse(Buffer.from(c, 'base64url')).iss, 'TEAM45');
  assert.ok(crypto.verify('sha256', Buffer.from(`${h}.${c}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url')));
  t += 49 * 60_000; assert.equal(auth.token(), jwt);
  t += 2 * 60_000; assert.notEqual(auth.token(), jwt);
});

test('전송 제한', () => {
  let t = 0; const l = new RateLimiter({ minIntervalMs: 1000, perHour: 3, now: () => t });
  l.check('a'); assert.throws(() => l.check('a'), /too frequent/);
  t = 1000; l.check('a'); t = 2000; l.check('a'); t = 3000; assert.throws(() => l.check('a'), /hourly/);
  t = 3_602_000; l.check('a');
});

test('가짜 APNs 서버로 끝까지: 경로·헤더·우선순위·환경', async () => {
  const seen = [];
  const fake = http2.createServer();
  fake.on('stream', (stream, headers) => {
    let body = ''; stream.setEncoding('utf8');
    stream.on('data', c => { body += c; });
    stream.on('end', () => {
      seen.push({ headers, body: JSON.parse(body) });
      const bad = headers[':path'].endsWith('dead');
      stream.respond({ ':status': bad ? 410 : 200, 'apns-id': 'ID-1' });
      stream.end(bad ? JSON.stringify({ reason: 'Unregistered' }) : '');
    });
  });
  await new Promise(r => fake.listen(0, r));
  const origin = `http://localhost:${fake.address().port}`;
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const apns = new ApnsClient({ auth: new ApnsAuth({ keyPem: privateKey.export({ type: 'pkcs8', format: 'pem' }), keyId: 'K', teamId: 'T' }),
    bundleId: 'com.example.brawlassistant', origins: { development: origin, production: origin } });
  try {
    let t = 1_800_000_000_000;
    const out = await handle(iosRequest(), { apns, limiter: new RateLimiter({ now: () => t }), now: () => t });
    assert.deepEqual(out, { ok: true, apnsStatus: 200, apnsId: 'ID-1', reason: null });
    const h = seen[0].headers;
    assert.equal(h[':path'], '/3/device/' + iosRequest().token);
    assert.equal(h['apns-push-type'], 'liveactivity');
    assert.equal(h['apns-topic'], 'com.example.brawlassistant.push-type.liveactivity');
    assert.equal(h['apns-priority'], '5');
    assert.match(h.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    assert.equal(seen[0].body.aps['content-state'].mapName, '기습적 움직임');

    const withAlert = { ...iosRequest(), alert: { title: 'BEST TEAM', body: '기습적 움직임 · 파이퍼 코스모 볼트' } };
    t += 2000;
    await handle(withAlert, { apns, limiter: new RateLimiter(), now: () => t });
    assert.equal(seen[1].headers['apns-priority'], '10');
    assert.deepEqual(seen[1].body.aps.alert, withAlert.alert);

    const dead = { ...iosRequest(), token: 'dead'.repeat(16) };
    const out2 = await handle(dead, { apns, limiter: new RateLimiter(), now: () => t });
    assert.deepEqual(out2, { ok: false, apnsStatus: 410, apnsId: 'ID-1', reason: 'Unregistered' });
  } finally { apns.close(); fake.close(); }
});

test('iOS(BrawlCore RelayRequest)가 실제로 만든 요청을 받아들인다', async () => {
  const fs = await import('node:fs');
  const url = new URL('../../tests/app-fixtures/relay-request-ios.json', import.meta.url);
  const body = JSON.parse(fs.readFileSync(url, 'utf8'));
  const r = validateRequest(body);
  assert.equal(r.event, 'update');
  assert.ok(r.alert, '맵 변경 알림 포함');
  const p = JSON.parse(buildPayload(r, 1_800_000_000));
  assert.deepEqual(p.aps['content-state'], body.contentState, 'content-state 는 바꾸지 않고 전달');
});
