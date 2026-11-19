// HTTP 서버: POST /v1/live-activity, GET /healthz
// 환경 변수: APNS_KEY(.p8 내용) 또는 APNS_KEY_FILE, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, PORT(기본 8080)
import http from 'node:http';
import fs from 'node:fs';
import { ApnsAuth, ApnsClient, RateLimiter, RelayError, handle } from './relay.mjs';

const env = process.env;
const keyPem = env.APNS_KEY || (env.APNS_KEY_FILE && fs.readFileSync(env.APNS_KEY_FILE, 'utf8'));
const apns = new ApnsClient({
  auth: new ApnsAuth({ keyPem, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID }),
  bundleId: env.APNS_BUNDLE_ID,
  origins: { production: env.APNS_ORIGIN_PRODUCTION || 'https://api.push.apple.com', development: env.APNS_ORIGIN_DEVELOPMENT || 'https://api.sandbox.push.apple.com' },
});
const limiter = new RateLimiter();

export const server = http.createServer(async (req, res) => {
  const send = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj)); };
  if (req.method === 'GET' && req.url === '/healthz') return send(200, { ok: true });
  if (req.method !== 'POST' || req.url !== '/v1/live-activity') return send(404, { ok: false });
  let size = 0; const chunks = [];
  for await (const c of req) { size += c.length; if (size > 8192) return send(413, { ok: false, reason: 'too large' }); chunks.push(c); }
  try {
    const out = await handle(JSON.parse(Buffer.concat(chunks).toString('utf8')), { apns, limiter });
    // 로그에는 토큰·내용을 남기지 않는다
    console.log(new Date().toISOString(), 'apns', out.apnsStatus, out.reason || '');
    send(out.ok ? 200 : (out.apnsStatus === 410 ? 410 : 502), out);
  } catch (e) {
    const code = e instanceof RelayError ? e.status : (e instanceof SyntaxError ? 400 : 500);
    send(code, { ok: false, reason: e.message });
  }
});

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(env.PORT || 8080);
  server.listen(port, () => console.log(`live-activity-relay listening on ${port}`));
}
