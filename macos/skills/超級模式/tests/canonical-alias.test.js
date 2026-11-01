#!/usr/bin/env node
// scope 比對的 canonical 路徑真實檔案系統測試。gate-cases 的 scope 都是不存在的固定路徑，比不出別名；
// 這裡在 temp 建真的 scope 與 symlink，守住 isSessionOutsideScope 與 mentionsGuardedPath 的 canonical 比對。
//
// 每案都傳 { baseDir, projectDir: "" }：不讀跑測試那個 session 的 CLAUDE_PROJECT_DIR。
//
// Windows 上這份 hook 停用 realpath，比不出 symlink → 印 SKIP、不印 CANONICAL-ALIAS 摘要行。
// 要驗就在 macOS 跑。
const fs = require("fs");
const os = require("os");
const path = require("path");

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

if (process.platform === "win32") {
  console.log("SKIP (win32: this hook only runs realpath on POSIX)");
  process.exit(0);
}

// 實體路徑與別名都從 canonical 的 temp 起算：$TMPDIR 本身常在 /var → /private/var 的 symlink 底下。
const root = fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(), "canon-alias-")));
const baseDir = path.join(root, "claude");
const real = path.join(root, "scope-real-directory");
const link = path.join(root, "scope-link");
const outside = path.join(root, "outside-directory");

let passed = 0;
let total = 0;
function check(name, { scope, cwd, cmd, expect, reason }) {
  total++;
  fs.writeFileSync(path.join(baseDir, ".super-mode-active"), scope);
  const res = decide(
    { tool_name: "Bash", tool_input: { command: cmd }, cwd },
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

let exitCode = 1;
try {
  fs.mkdirSync(baseDir);
  fs.mkdirSync(real);
  fs.mkdirSync(outside);
  fs.symlinkSync(real, link);

  const STASH = "git stash";
  const NOT_READONLY = "非唯讀指令";
  const SCOPE_HINT = "-d 請用該專案根";
  const removeIn = (dir) => "rm -rf " + dir + "/x";

  // 對照組：真的在 scope 外就放行。沒有這組，canonicalize 整個失敗（一律不吃捷徑）也會全綠。
  check("對照 scope=實體、cwd 在外 allows", { scope: real, cwd: outside, cmd: STASH, expect: "allow" });
  check("對照 scope=symlink、cwd 在外 allows", { scope: link, cwd: outside, cmd: STASH, expect: "allow" });
  check("對照 scope=symlink、指令只提到 scope 外 allows", { scope: link, cwd: outside, cmd: removeIn(outside), expect: "allow" });
  check("對照 scope=實體、cwd=實體 denies", { scope: real, cwd: real, cmd: STASH, expect: "deny", reason: NOT_READONLY });

  check("cwd=symlink 算 scope 內 denies", { scope: real, cwd: link, cmd: STASH, expect: "deny", reason: NOT_READONLY });
  check("scope=symlink、cwd=實體 denies", { scope: link, cwd: real, cmd: STASH, expect: "deny", reason: NOT_READONLY });
  check("scope=symlink、指令寫實體路徑走 scope 分支", { scope: link, cwd: outside, cmd: removeIn(real), expect: "deny", reason: SCOPE_HINT });
  check("scope=實體、指令寫實體路徑走 scope 分支", { scope: real, cwd: outside, cmd: removeIn(real), expect: "deny", reason: SCOPE_HINT });
  check("scope=symlink、指令寫 symlink 路徑走 scope 分支", { scope: link, cwd: outside, cmd: removeIn(link), expect: "deny", reason: SCOPE_HINT });

  console.log("CANONICAL-ALIAS " + passed + "/" + total);
  exitCode = passed === total ? 0 : 1;
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
process.exit(exitCode);
