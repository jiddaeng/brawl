// HTTP 서버
//  POST /v1/live-activity          방송 확장 → APNs Live Activity 푸시 (APNS_* 설정 시)
//  GET  /v1/brawlstars/rotation    지금 열린 이벤트 맵 (BRAWLSTARS_API_KEY 설정 시)
//  GET  /v1/brawlstars/player/:tag 보유 브롤러·최근 경기 (BRAWLSTARS_API_KEY 설정 시)
//  GET  /healthz
// 환경 변수: APNS_KEY(.p8 내용) 또는 APNS_KEY_FILE, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID,
//           BRAWLSTARS_API_KEY (developer.brawlstars.com, 이 서버의 공인 IP 를 허용 목록에 등록), PORT(기본 8080)
// 두 기능은 각각 따로 켤 수 있다. 설정하지 않은 기능은 503 을 돌려준다.
import http from 'node:http';
import fs from 'node:fs';
import { ApnsAuth, ApnsClient, RateLimiter, RelayError, handle } from './relay.mjs';
import { BrawlStarsClient, TTLCache, handleBrawlStars } from './brawlstars.mjs';

const env = process.env;

function makeApns() {
  const keyPem = env.APNS_KEY || (env.APNS_KEY_FILE && fs.readFileSync(env.APNS_KEY_FILE, 'utf8'));
  if (!keyPem) return null;
  return new ApnsClient({
    auth: new ApnsAuth({ keyPem, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID }),
    bundleId: env.APNS_BUNDLE_ID,
    origins: { production: env.APNS_ORIGIN_PRODUCTION || 'https://api.push.apple.com', development: env.APNS_ORIGIN_DEVELOPMENT || 'https://api.sandbox.push.apple.com' },
  });
}

export function createServer({ apns = null, brawlStars = null } = {}) {
  const limiter = new RateLimiter();
  // 공식 API 호출: 접속 주소마다 2초 간격, 시간당 120번 (캐시에 있으면 세지 않음)
  const bsLimiter = new RateLimiter({ minIntervalMs: 2000, perHour: 120 });
  const cache = new TTLCache();
  return http.createServer(async (req, res) => {
    const send = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(JSON.stringify(obj)); };
    try {
      if (req.method === 'GET' && req.url === '/healthz') return send(200, { ok: true, liveActivity: !!apns, brawlStars: !!brawlStars });
      const bs = await handleBrawlStars(req.method, req.url, { client: brawlStars, cache, limiter: bsLimiter, clientKey: req.socket.remoteAddress });
      if (bs) {
        // 로그에는 플레이어 태그를 남기지 않는다
        console.log(new Date().toISOString(), 'brawlstars', req.url.startsWith('/v1/brawlstars/player/') ? 'player' : 'rotation', bs.status);
        return send(bs.status, bs.body);
      }
      if (req.method !== 'POST' || req.url !== '/v1/live-activity') return send(404, { ok: false });
      if (!apns) throw new RelayError(503, 'Live Activity push is not configured on this server');
      let size = 0; const chunks = [];
      for await (const c of req) { size += c.length; if (size > 8192) return send(413, { ok: false, reason: 'too large' }); chunks.push(c); }
      const out = await handle(JSON.parse(Buffer.concat(chunks).toString('utf8')), { apns, limiter });
      // 로그에는 토큰·내용을 남기지 않는다
      console.log(new Date().toISOString(), 'apns', out.apnsStatus, out.reason || '');
      send(out.ok ? 200 : (out.apnsStatus === 410 ? 410 : 502), out);
    } catch (e) {
      const code = e instanceof RelayError ? e.status : (e instanceof SyntaxError ? 400 : 500);
      send(code, { ok: false, reason: e.message });
    }
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const apns = makeApns();
  const brawlStars = env.BRAWLSTARS_API_KEY ? new BrawlStarsClient({ apiKey: env.BRAWLSTARS_API_KEY }) : null;
  const port = Number(env.PORT || 8080);
  createServer({ apns, brawlStars }).listen(port, () =>
    console.log(`brawl-assistant server listening on ${port} (live activity: ${apns ? 'on' : 'off'}, brawl stars api: ${brawlStars ? 'on' : 'off'})`));
}
