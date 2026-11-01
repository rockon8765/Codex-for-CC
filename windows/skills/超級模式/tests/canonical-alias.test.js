#!/usr/bin/env node
// scope 比對的 canonical 路徑真實檔案系統測試。gate-cases 的 scope 都是不存在的固定路徑，比不出別名；
// 這裡在 temp 建真的 scope 與 junction（可取得 8.3 短名時一併測），守住
// isSessionOutsideScope 與 mentionsGuardedPath 的 canonical 比對。
//
// 每案都傳 { baseDir, projectDir: "" }：不讀跑測試那個 session 的 CLAUDE_PROJECT_DIR。
//
// 非 win32 或建不出 junction → 印 SKIP、不印 CANONICAL-ALIAS 摘要行（suite 的 marker 只認摘要行）。
// 8.3 短名停用時只略過 8.3 那幾案，並印出來。
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execSync } = require("child_process");

const hookCandidates = [
  path.join(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js"),
  path.join(os.homedir(), ".claude", "hooks", "super-mode-consult-gate.js"),
];
const hookPath = hookCandidates.find((p) => fs.existsSync(p));
if (!hookPath) {
  console.error("hook not found in: " + hookCandidates.join(" | "));
  process.exit(1);
}
const { decide } = require(hookPath);

if (process.platform !== "win32") {
  console.log("SKIP (not win32)");
  process.exit(0);
}

// 實體路徑與別名都從 canonical 的 temp 起算：os.tmpdir() 自己可能就含 8.3 段。
const root = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "canon-alias-")));
const baseDir = path.join(root, "claude");
const real = path.join(root, "scope-real-directory");
const link = path.join(root, "scope-link");
const outside = path.join(root, "outside-directory");

function shortNameOf(longName) {
  const out = execSync('cmd /c dir /x /ad "' + root + '"', { encoding: "utf8", windowsHide: true });
  for (const line of out.split(/\r?\n/)) {
    const m = line.match(new RegExp("\\s(\\S+)\\s+" + longName + "\\s*$", "i"));
    if (m && /~/.test(m[1])) return m[1];
  }
  return "";
}

let passed = 0;
let total = 0;
function check(name, { scope, cwd, cmd, expect, reason }) {
  total++;
  fs.writeFileSync(path.join(baseDir, ".super-mode-active"), scope);
  const res = decide(
    { tool_name: "PowerShell", tool_input: { command: cmd }, cwd },
    { baseDir, projectDir: "" }
  );
  const got = res && res.allow ? "allow" : "deny";
  const text = (res && res.reason) || "";
  if (got !== expect || (reason && !text.includes(reason))) {
    console.error("FAIL " + name + "：" + got + "，期望 " + expect + (reason ? "（理由含 " + reason + "）" : "") + " " + text.slice(0, 120));
  } else {
    passed++;
    console.log("ok   " + name);
  }
}

function main() {
  fs.mkdirSync(baseDir);
  fs.mkdirSync(real);
  fs.mkdirSync(outside);
  try {
    fs.symlinkSync(real, link, "junction");
  } catch (e) {
    console.log("SKIP (junction unavailable: " + (e && e.code) + ")");
    return 0;
  }

  const STASH = "git stash";
  const NOT_READONLY = "非唯讀指令";
  const SCOPE_HINT = "-Dir 請用該專案根";
  const removeIn = (dir) => "Remove-Item -Recurse " + dir + "\\x";

  // 對照組：真的在 scope 外就放行。沒有這組，canonicalize 整個失敗（一律不吃捷徑）也會全綠。
  check("對照 scope=實體、cwd 在外 allows", { scope: real, cwd: outside, cmd: STASH, expect: "allow" });
  check("對照 scope=junction、cwd 在外 allows", { scope: link, cwd: outside, cmd: STASH, expect: "allow" });
  check("對照 scope=junction、指令只提到 scope 外 allows", { scope: link, cwd: outside, cmd: removeIn(outside), expect: "allow" });
  check("對照 scope=實體、cwd=實體 denies", { scope: real, cwd: real, cmd: STASH, expect: "deny", reason: NOT_READONLY });

  check("cwd=junction 算 scope 內 denies", { scope: real, cwd: link, cmd: STASH, expect: "deny", reason: NOT_READONLY });
  check("scope=junction、cwd=實體 denies", { scope: link, cwd: real, cmd: STASH, expect: "deny", reason: NOT_READONLY });
  check("scope=junction、指令寫實體路徑走 scope 分支", { scope: link, cwd: outside, cmd: removeIn(real), expect: "deny", reason: SCOPE_HINT });

  let short = "";
  try {
    const name = shortNameOf(path.basename(real));
    if (name) {
      const candidate = path.join(root, name);
      if (fs.realpathSync.native(candidate).toLowerCase() === real.toLowerCase()) short = candidate;
    }
  } catch (e) {}
  if (short) {
    check("cwd=8.3 算 scope 內 denies", { scope: real, cwd: short, cmd: STASH, expect: "deny", reason: NOT_READONLY });
    check("scope=8.3、cwd=實體 denies", { scope: short, cwd: real, cmd: STASH, expect: "deny", reason: NOT_READONLY });
    check("scope=8.3、指令寫實體路徑走 scope 分支", { scope: short, cwd: outside, cmd: removeIn(real), expect: "deny", reason: SCOPE_HINT });
  } else {
    console.log("8.3 cases skipped (no 8.3 short name on this volume)");
  }

  console.log("CANONICAL-ALIAS " + passed + "/" + total);
  return passed === total ? 0 : 1;
}

let exitCode = 1;
try {
  exitCode = main();
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
process.exit(exitCode);
