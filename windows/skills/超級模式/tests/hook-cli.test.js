#!/usr/bin/env node
// consult-gate 的 stdin → exit code 水管測試。run-gate-tests.js 與 class-b-8dot3 都只呼叫 decide()，
// 碰不到 hook 主區塊；這裡真的 spawn hook，守住「被擋時 exit 2、stderr 寫完整理由」與 fail-open。
//
// 隔離：每案用 mkdtemp 建假家目錄，USERPROFILE／HOME 都指過去，CLAUDE_PROJECT_DIR 從 child 環境移除。
// 開跑前先確認 child 看到的 os.homedir() 就是假家目錄，對不上就中止，不碰真實 ~/.claude。
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

// tests → 超級模式 → skills → base → hooks，repo 與部署布局皆成立。刻意不 fallback 到家目錄：
// 找不到就 FAIL，不靜默改驗安裝版。
const hookPath = path.join(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js");
if (!fs.existsSync(hookPath)) {
  console.error("hook not found: " + hookPath);
  process.exit(1);
}
console.log("HOOK_UNDER_TEST=" + hookPath);

const WRITE_INPUT = JSON.stringify({
  tool_name: "Write",
  tool_input: { file_path: "C:\\proj\\src\\app.js" },
  cwd: "C:\\proj",
});
const BOM = Buffer.from([0xef, 0xbb, 0xbf]);
// 理由的開頭與結尾都要看到：只比開頭的話，訊息被截斷也會過。
const DENY_HEAD = "[超級模式]";
const DENY_TAIL = "勿再重試。）";

const CASES = [
  { name: "無旗標 exit 0", flag: false, stdin: WRITE_INPUT, status: 0, stderr: "empty" },
  { name: "壞 JSON exit 0（fail-open）", flag: true, stdin: "{not json", status: 0, stderr: "empty" },
  { name: "空 stdin exit 0", flag: true, stdin: "", status: 0, stderr: "empty" },
  { name: "無憑證 exit 2，stderr 是完整理由", flag: true, stdin: WRITE_INPUT, status: 2, stderr: "deny" },
  { name: "帶 BOM 的 stdin 照常解析：無憑證 exit 2", flag: true, stdin: Buffer.concat([BOM, Buffer.from(WRITE_INPUT)]), status: 2, stderr: "deny" },
  { name: "新憑證 exit 0", flag: true, token: true, stdin: WRITE_INPUT, status: 0, stderr: "empty" },
];

function childEnv(home) {
  const env = { ...process.env, USERPROFILE: home, HOME: home };
  delete env.CLAUDE_PROJECT_DIR;
  return env;
}

function runCase(tc) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "hook-cli-"));
  try {
    const env = childEnv(home);
    const seen = spawnSync(process.execPath, ["-p", "require('os').homedir()"], { env, encoding: "utf8" });
    if (seen.status !== 0 || seen.stdout.trim().toLowerCase() !== home.toLowerCase()) {
      console.error("FATAL child homedir 不是假家目錄：" + JSON.stringify(seen.stdout) + "，期望 " + home);
      process.exit(1);
    }

    const claude = path.join(home, ".claude");
    fs.mkdirSync(claude);
    if (tc.flag) fs.writeFileSync(path.join(claude, ".super-mode-active"), "");
    if (tc.token) fs.writeFileSync(path.join(claude, ".super-mode-consult-ok"), new Date().toISOString());

    const res = spawnSync(process.execPath, [hookPath], { env, input: tc.stdin, timeout: 30000 });
    const stderr = (res.stderr || Buffer.alloc(0)).toString("utf8");
    const problems = [];
    if (res.status !== tc.status) problems.push("status=" + res.status + " 期望 " + tc.status);
    if (tc.stderr === "empty" && stderr !== "") problems.push("stderr 應為空：" + stderr.slice(0, 120));
    if (tc.stderr === "deny" && !(stderr.startsWith(DENY_HEAD) && stderr.includes(DENY_TAIL))) {
      problems.push("stderr 不是完整理由（" + Buffer.byteLength(stderr) + " bytes）：" + stderr.slice(0, 120));
    }
    return problems;
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
}

let passed = 0;
for (const tc of CASES) {
  const problems = runCase(tc);
  if (problems.length) {
    console.error("FAIL " + tc.name + "：" + problems.join("；"));
  } else {
    passed++;
    console.log("ok   " + tc.name);
  }
}
console.log("HOOK-CLI " + passed + "/" + CASES.length);
process.exit(passed === CASES.length ? 0 : 1);
