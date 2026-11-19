// Brawl Assistant Live Activity 중계: 방송 확장이 보낸 '푸시 토큰 + 표시 값'을 APNs ActivityKit 푸시로 전달한다.
// 외부 의존성 없음 (Node 20+ 의 http2, crypto 만 사용). 상태(DB)를 저장하지 않는다.
import http2 from 'node:http2';
import crypto from 'node:crypto';

/** ActivityKit ContentState(ActivityDisplayState) 의 키. iOS RelayRequest.contentStateKeys 와 같아야 한다 */
export const CONTENT_STATE_KEYS = ['status', 'mapName', 'modeName', 'members', 'score', 'winRate', 'message', 'updatedAt'];
const STATUSES = ['idle', 'waiting', 'broadcasting', 'mapRecognized', 'computing', 'ready', 'mapFailed', 'modeFailed', 'noRecommendation', 'ended'];

export class RelayError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

const isStr = (v, max) => typeof v === 'string' && v.length <= max;
const isNum = v => typeof v === 'number' && Number.isFinite(v);

/** 요청 검증: 필요한 최소 정보만 통과시킨다 (모르는 키, 큰 값, 이미지·URL 거부) */
export function validateRequest(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new RelayError(400, 'body must be an object');
  const allowed = new Set(['token', 'environment', 'event', 'contentState', 'alert']);
  for (const k of Object.keys(body)) if (!allowed.has(k)) throw new RelayError(400, `unknown field: ${k}`);
  const { token, environment, event, contentState: cs, alert } = body;
  if (typeof token !== 'string' || !/^[0-9a-f]{32,400}$/.test(token)) throw new RelayError(400, 'token must be hex');
  if (!['development', 'production'].includes(environment)) throw new RelayError(400, 'environment must be development or production');
  if (!['update', 'end'].includes(event)) throw new RelayError(400, 'event must be update or end');
  if (!cs || typeof cs !== 'object' || Array.isArray(cs)) throw new RelayError(400, 'contentState must be an object');
  for (const k of Object.keys(cs)) if (!CONTENT_STATE_KEYS.includes(k)) throw new RelayError(400, `unknown contentState field: ${k}`);
  if (!STATUSES.includes(cs.status)) throw new RelayError(400, 'contentState.status invalid');
  if (!isNum(cs.updatedAt)) throw new RelayError(400, 'contentState.updatedAt must be a number (seconds since 2001-01-01)');
  for (const k of ['mapName', 'modeName']) if (cs[k] !== undefined && !isStr(cs[k], 80)) throw new RelayError(400, `contentState.${k} invalid`);
  if (cs.message !== undefined && !isStr(cs.message, 300)) throw new RelayError(400, 'contentState.message invalid');
  if (cs.winRate !== undefined && !(isStr(cs.winRate, 8) && /^[0-9.]+$/.test(cs.winRate))) throw new RelayError(400, 'contentState.winRate invalid');
  if (cs.score !== undefined && !(Number.isInteger(cs.score) && cs.score >= 0 && cs.score <= 100)) throw new RelayError(400, 'contentState.score invalid');
  if (!Array.isArray(cs.members) || cs.members.length > 5) throw new RelayError(400, 'contentState.members must be an array of up to 5');
  for (const m of cs.members) {
    if (!m || typeof m !== 'object' || Object.keys(m).some(k => k !== 'id' && k !== 'name') || !Number.isInteger(m.id) || !isStr(m.name, 40))
      throw new RelayError(400, 'contentState.members entries must be {id, name}');
  }
  for (const v of [cs.mapName, cs.modeName, cs.message, ...cs.members.map(m => m.name)])
    if (typeof v === 'string' && /https?:|data:/i.test(v)) throw new RelayError(400, 'URLs are not allowed');
  if (alert !== undefined && alert !== null) {
    if (typeof alert !== 'object' || !isStr(alert.title, 60) || !isStr(alert.body, 160) || Object.keys(alert).some(k => k !== 'title' && k !== 'body'))
      throw new RelayError(400, 'alert must be {title, body}');
  }
  return { token, environment, event, contentState: cs, alert: alert || null };
}

/** APNs ActivityKit 페이로드. aps 의 시각은 Unix 초, content-state 는 받은 그대로(Date 는 2001 기준 초) */
export function buildPayload(req, nowSec) {
  const aps = { timestamp: nowSec, event: req.event, 'content-state': req.contentState };
  if (req.event === 'update') aps['stale-date'] = nowSec + 30 * 60;
  else aps['dismissal-date'] = nowSec + 15 * 60;   // HIG: 종료 후 15~30분
  if (req.alert && req.event === 'update') aps.alert = { title: req.alert.title, body: req.alert.body };
  const json = JSON.stringify({ aps });
  if (Buffer.byteLength(json) > 4096) throw new RelayError(413, 'payload exceeds APNs 4KB limit');
  return json;
}

const b64url = b => Buffer.from(b).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

/** APNs 토큰 인증 (ES256 JWT). 20~60분 사이에 갱신해야 하므로 50분 동안 재사용 */
export class ApnsAuth {
  constructor({ keyPem, keyId, teamId, now = () => Date.now() }) {
    if (!keyPem || !keyId || !teamId) throw new Error('APNS key, key id and team id are required');
    this.key = crypto.createPrivateKey(keyPem); this.keyId = keyId; this.teamId = teamId; this.now = now; this.cached = null;
  }
  token() {
    const nowSec = Math.floor(this.now() / 1000);
    if (this.cached && nowSec - this.cached.iat < 50 * 60) return this.cached.jwt;
    const head = b64url(JSON.stringify({ alg: 'ES256', kid: this.keyId }));
    const claims = b64url(JSON.stringify({ iss: this.teamId, iat: nowSec }));
    const sig = crypto.sign('sha256', Buffer.from(`${head}.${claims}`), { key: this.key, dsaEncoding: 'ieee-p1363' });
    this.cached = { iat: nowSec, jwt: `${head}.${claims}.${b64url(sig)}` };
    return this.cached.jwt;
  }
}

/** 토큰별 전송 제한 (메모리, 서버 한 대 기준) */
export class RateLimiter {
  constructor({ minIntervalMs = 1000, perHour = 240, now = () => Date.now() } = {}) {
    this.min = minIntervalMs; this.perHour = perHour; this.now = now; this.map = new Map();
  }
  check(key) {
    const t = this.now(); const e = this.map.get(key) || { last: -Infinity, hour: t, count: 0 };
    if (t - e.hour >= 3600_000) { e.hour = t; e.count = 0; }
    if (t - e.last < this.min) throw new RelayError(429, 'too frequent');
    if (e.count >= this.perHour) throw new RelayError(429, 'hourly limit reached');
    e.last = t; e.count++; this.map.set(key, e);
    if (this.map.size > 50_000) this.map.clear();   // 상한 (상태를 오래 들고 있지 않는다)
  }
}

export const APNS_ORIGINS = { production: 'https://api.push.apple.com', development: 'https://api.sandbox.push.apple.com' };

/** APNs 로 전송 (HTTP/2). 연결은 환경별로 재사용 */
export class ApnsClient {
  constructor({ auth, bundleId, origins = APNS_ORIGINS }) {
    if (!bundleId) throw new Error('bundle id is required');
    this.auth = auth; this.topic = `${bundleId}.push-type.liveactivity`; this.origins = origins; this.sessions = {};
  }
  session(env) {
    const s = this.sessions[env];
    if (s && !s.closed && !s.destroyed) return s;
    const n = http2.connect(this.origins[env]);
    n.on('error', () => {}); n.on('goaway', () => n.close());
    this.sessions[env] = n;
    return n;
  }
  send(req, payload) {
    return new Promise((resolve, reject) => {
      const s = this.session(req.environment);
      const r = s.request({
        ':method': 'POST', ':path': `/3/device/${req.token}`,
        authorization: `bearer ${this.auth.token()}`,
        'apns-push-type': 'liveactivity', 'apns-topic': this.topic,
        // 맵 변경 알림만 즉시(10), 나머지는 전력 절약(5). 10 은 시간당 예산을 쓴다
        'apns-priority': req.alert ? '10' : '5',
        'content-type': 'application/json',
      });
      let status = 0, apnsId = null, data = '';
      r.setEncoding('utf8');
      r.on('response', h => { status = h[':status']; apnsId = h['apns-id'] || null; });
      r.on('data', c => { data += c; });
      r.on('end', () => {
        let reason = null; try { reason = data ? JSON.parse(data).reason : null; } catch { reason = data.slice(0, 100); }
        resolve({ status, apnsId, reason });
      });
      r.on('error', reject);
      r.setTimeout(10_000, () => { r.close(); reject(new Error('APNs timeout')); });
      r.end(payload);
    });
  }
  close() { for (const s of Object.values(this.sessions)) s.close(); }
}

/** 요청 하나 처리: 검증 → 제한 → 페이로드 → APNs */
export async function handle(body, { apns, limiter, now = () => Date.now() }) {
  const req = validateRequest(body);
  limiter.check(req.token);
  const res = await apns.send(req, buildPayload(req, Math.floor(now() / 1000)));
  return { ok: res.status === 200, apnsStatus: res.status, apnsId: res.apnsId, reason: res.reason };
}
