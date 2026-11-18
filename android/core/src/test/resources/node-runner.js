// JVM 테스트용 JS 실행기: 표준입력으로 {"code": "..."} 한 줄씩 받아 같은 컨텍스트에서 실행하고
// {"ok": true, "value": "<마지막 값의 문자열>"} 한 줄로 답한다 (JavaScriptSandbox.evaluateJavaScriptAsync 와 같은 의미)
const vm = require('vm');
const readline = require('readline');
const ctx = vm.createContext({});
const rl = readline.createInterface({ input: process.stdin, terminal: false, crlfDelay: Infinity });
rl.on('line', line => {
  let out;
  try { const v = vm.runInContext(JSON.parse(line).code, ctx); out = { ok: true, value: String(v) }; }
  catch (e) { out = { ok: false, error: String(e && e.stack || e) }; }
  process.stdout.write(JSON.stringify(out) + '\n');
});
