// Supercell 공식 Brawl Stars API 중계 (api.brawlstars.com).
// 공식 API 키는 서버 IP 에 묶여 있고 비밀이라 앱에 넣을 수 없다 → 이 서버가 키를 들고 대신 부른다.
// 앱에는 추천에 필요한 최소 정보만 돌려준다: 보유 브롤러(id·파워), 최근 경기의 모드·맵, 현재 이벤트 맵.
// 실시간 경기 정보는 공식 API 에 없다 (전적은 경기가 끝난 뒤, 늦게 올라온다).
import { RelayError } from './relay.mjs';

export const BS_API = 'https://api.brawlstars.com/v1';
const TAG_CHARS = /^[0289PYLQGRJCUV]{3,14}$/;

/** "#abc 0" 같은 입력 → "#ABC0". 게임 태그에 쓰이는 글자(0289PYLQGRJCUV)만 허용, O 는 0 으로 */
export function normalizeTag(input) {
  if (typeof input !== 'string') throw new RelayError(400, 'tag must be a string');
  const t = decodeURIComponent(input).toUpperCase().replace(/[\s#]/g, '').replace(/O/g, '0');
  if (!TAG_CHARS.test(t)) throw new RelayError(400, 'invalid player tag');
  return '#' + t;
}

/** 공식 API 시각 "20260119T101530.000Z" → ISO 문자열 */
export function parseBsTime(s) {
  const m = typeof s === 'string' && /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(\.\d+)?Z$/.exec(s);
  return m ? `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}${m[7] || '.000'}Z` : null;
}

const int = v => (Number.isInteger(v) ? v : null);
const str = (v, max = 60) => (typeof v === 'string' ? v.slice(0, max) : null);

/** /players/{tag} → 이름·트로피·보유 브롤러(id, 파워) */
export function slimPlayer(p) {
  return {
    tag: str(p?.tag, 16), name: str(p?.name, 40), trophies: int(p?.trophies),
    brawlers: (Array.isArray(p?.brawlers) ? p.brawlers : [])
      .filter(b => Number.isInteger(b?.id))
      .map(b => ({ id: b.id, power: int(b.power) ?? 1 })),
  };
}

/** /players/{tag}/battlelog → 최근 경기 최대 10개 (시각, 모드, 맵 id·이름, 결과). 다른 플레이어 정보는 버린다 */
export function slimBattles(j) {
  return (Array.isArray(j?.items) ? j.items : []).slice(0, 10).map(it => ({
    at: parseBsTime(it?.battleTime),
    mode: str(it?.event?.mode ?? it?.battle?.mode, 40),
    mapId: int(it?.event?.id),
    map: str(it?.event?.map, 60),
    result: str(it?.battle?.result, 10),
  })).filter(b => b.at);
}

/** /events/rotation → 지금 열린 이벤트 맵 (슬롯, 시작·끝, 모드, 맵 id·이름) */
export function slimRotation(j) {
  return (Array.isArray(j) ? j : []).map(e => ({
    slot: int(e?.slotId),
    start: parseBsTime(e?.startTime), end: parseBsTime(e?.endTime),
    mode: str(e?.event?.mode, 40), mapId: int(e?.event?.id), map: str(e?.event?.map, 60),
  })).filter(e => e.mapId !== null);
}

/** 짧은 메모리 캐시 (같은 플레이어를 여러 번 불러도 공식 API 는 한 번) */
export class TTLCache {
  constructor({ now = () => Date.now(), max = 5000 } = {}) { this.now = now; this.max = max; this.map = new Map(); }
  get(k) { const e = this.map.get(k); if (!e) return undefined; if (e.until < this.now()) { this.map.delete(k); return undefined; } return e.v; }
  set(k, v, ttlMs) { if (this.map.size >= this.max) this.map.clear(); this.map.set(k, { v, until: this.now() + ttlMs }); }
}

export class BrawlStarsClient {
  constructor({ apiKey, base = BS_API, fetchImpl = globalThis.fetch }) {
    if (!apiKey) throw new Error('BRAWLSTARS_API_KEY is required');
    this.apiKey = apiKey; this.base = base; this.fetch = fetchImpl;
  }
  async get(path) {
    const r = await this.fetch(this.base + path, { headers: { authorization: `Bearer ${this.apiKey}`, accept: 'application/json' }, signal: AbortSignal.timeout(10_000) });
    if (r.status === 404) throw new RelayError(404, 'player not found');
    if (r.status === 403) throw new RelayError(502, 'Brawl Stars API key rejected (check the IP allow-list of the key)');
    if (r.status === 429) throw new RelayError(503, 'Brawl Stars API rate limited');
    if (!r.ok) throw new RelayError(502, `Brawl Stars API ${r.status}`);
    return r.json();
  }
}

/**
 * GET /v1/brawlstars/rotation, GET /v1/brawlstars/player/{tag} 처리.
 * 반환: {status, body}. 요청 경로가 아니면 null
 */
export async function handleBrawlStars(method, url, { client, cache, limiter, clientKey, now = () => Date.now() }) {
  if (!url.startsWith('/v1/brawlstars/')) return null;
  if (method !== 'GET') throw new RelayError(405, 'GET only');
  if (!client) throw new RelayError(503, 'Brawl Stars API is not configured on this server');
  const path = url.split('?')[0];
  if (path === '/v1/brawlstars/rotation') {
    let rot = cache.get('rotation');
    if (!rot) { rot = slimRotation(await client.get('/events/rotation')); cache.set('rotation', rot, 5 * 60_000); }
    return { status: 200, body: { ok: true, fetchedAt: new Date(now()).toISOString(), rotation: rot } };
  }
  const m = /^\/v1\/brawlstars\/player\/([^/]+)$/.exec(path);
  if (!m) throw new RelayError(404, 'unknown path');
  const tag = normalizeTag(m[1]);
  let player = cache.get('p' + tag);
  if (!player) {
    limiter.check('bs:' + (clientKey || 'unknown'));   // 캐시에 없을 때만 공식 API 호출 횟수를 센다
    const enc = encodeURIComponent(tag);
    const [p, b] = await Promise.all([client.get(`/players/${enc}`), client.get(`/players/${enc}/battlelog`).catch(() => ({ items: [] }))]);
    player = { ...slimPlayer(p), recent: slimBattles(b) };
    cache.set('p' + tag, player, 60_000);
  }
  return { status: 200, body: { ok: true, fetchedAt: new Date(now()).toISOString(), player } };
}
