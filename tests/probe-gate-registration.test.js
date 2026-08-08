#!/usr/bin/env node
/*
 * tools/probe-gate-registration.js 的回歸案。
 *
 * 用法：
 *   node tests/probe-gate-registration.test.js
 *   node tests/probe-gate-registration.test.js --probe <path>   # 反向驗證用：指向舊版 probe
 *
 * 三平台共用（純 Node，不依賴 shell）。每個案子開一個假 HOME，寫 fixture，
 * 用子程序跑 probe，斷言**退出碼 ＋ 應出現／不應出現的字串**。
 *
 * ⚠️ 斷言刻意不只看退出碼。2026-08-08 的教訓：反向驗證只核對總數時，
 * 無從得知失敗的是不是「該失敗的那幾條」——例如舊版對「頂層 null」會因
 * 未捕捉的 TypeError 湊巧也 exit 1，但它印的是 stack trace 而不是判定。
 *
 * 反向驗證（對 `5cc50e0` 那版 heredoc probe）預期失敗的案子，見
 * docs/MIGRATION-hook-settings-target.md 檔頭的修訂註記。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

// ── 參數 ────────────────────────────────────────────────────────────────
let probe = path.join(__dirname, "..", "tools", "probe-gate-registration.js");
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--probe") {
    if (!process.argv[i + 1]) {
      console.error("--probe 後面要接路徑");
      process.exit(2);
    }
    probe = process.argv[++i];
  } else {
    console.error("未知參數：" + process.argv[i]);
    process.exit(2);
  }
}
if (!fs.existsSync(probe)) {
  console.error("找不到 probe：" + probe);
  process.exit(2);
}
console.log("受測 probe：" + probe);

// ── fixture 素材 ────────────────────────────────────────────────────────
const MATCHER = "Write|Edit|NotebookEdit|Bash|PowerShell|Monitor|mcp__.*";
const CMD = "node /home/u/.claude/hooks/super-mode-consult-gate.js";
const CMD_STALE = "node /old/path/super-mode-consult-gate.js";

const gateHandler = (cmd) => ({ type: "command", command: cmd || CMD });
// exec form：args 存在時 command 只是可執行檔名，needle 在 args 裡
const gateExec = (p) => ({ type: "command", command: "node", args: [p || "/home/u/.claude/hooks/super-mode-consult-gate.js"] });
const execEntry = (p) => ({ matcher: MATCHER, hooks: [gateExec(p)] });
const gateEntry = (cmd, matcher) => ({
  matcher: matcher === undefined ? MATCHER : matcher,
  hooks: [gateHandler(cmd)],
});
const settings = (...entries) => ({ hooks: { PreToolUse: entries } });

// ── 案例矩陣 ────────────────────────────────────────────────────────────
// exit 1 = 讀不到／形狀不合（fail-closed）｜exit 3 = 停手｜exit 0 = 判定可執行
const CASES = [
  // ---- fail-closed：形狀不合，一律 exit 1 -------------------------------
  { id: "invalid-json", main: { raw: "{ 這不是 JSON" }, exit: 1, want: ["JSON 解析失敗", "無法解析或形狀不合"] },
  { id: "top-null", main: null, exit: 1, want: ["頂層不是物件（是 null）"] },
  { id: "top-array", main: [], exit: 1, want: ["頂層不是物件（是 陣列）"] },
  { id: "hooks-string", main: { hooks: "x" }, exit: 1, want: ["hooks 不是物件（是 string）"] },
  { id: "pretooluse-object", main: { hooks: { PreToolUse: {} } }, exit: 1, want: ["hooks.PreToolUse 不是陣列（是 object）"] },
  // ↓ 這就是舊版的假陰性：字串會被逐字元迭代、靜默數成 0
  { id: "pretooluse-string", main: { hooks: { PreToolUse: CMD } }, exit: 1, want: ["hooks.PreToolUse 不是陣列（是 string）"], deny: ["兩邊都沒有 gate"] },
  { id: "entry-not-object", main: settings("x"), exit: 1, want: ["PreToolUse[0] 不是物件（是 string）"] },
  { id: "entry-hooks-not-array", main: settings({ matcher: MATCHER, hooks: "x" }), exit: 1, want: ["PreToolUse[0].hooks 不是陣列（是 string）"] },
  { id: "handler-not-object", main: settings({ matcher: MATCHER, hooks: ["x"] }), exit: 1, want: ["PreToolUse[0].hooks[0] 不是物件（是 string）"] },
  { id: "command-not-string", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: [CMD] }] }), exit: 1, want: ["PreToolUse[0].hooks[0].command 不是字串（是 陣列）"] },
  { id: "type-missing", main: settings({ matcher: MATCHER, hooks: [{ command: CMD }] }), exit: 1, want: ["command 含 gate，但 type 是 缺漏"], deny: ["正常，不用修"] },
  { id: "type-prompt", main: settings({ matcher: MATCHER, hooks: [{ type: "prompt", command: CMD }] }), exit: 1, want: ['command 含 gate，但 type 是 "prompt"'], deny: ["正常，不用修"] },
  { id: "matcher-not-string", main: settings({ matcher: 5, hooks: [gateHandler()] }), exit: 1, want: ["PreToolUse[0].matcher 不是字串（是 number）"] },
  // 混合案：第一筆合法、第二筆 type 壞掉 —— existential 寫法會在這裡假綠
  { id: "mixed-good-then-bad", main: settings(gateEntry(), { matcher: MATCHER, hooks: [{ type: "prompt", command: CMD }] }), exit: 1, want: ["PreToolUse[1].hooks[0] 的 command 含 gate"], deny: ["正常，不用修"] },
  // local 壞掉、main 正常 —— 證明兩個檔都驗
  { id: "local-invalid-main-ok", main: settings(gateEntry()), local: { raw: "{" }, exit: 1, want: ["JSON 解析失敗"], deny: ["正常，不用修"] },

  // ---- 停手：需要人工判斷，exit 3 --------------------------------------
  { id: "halt-shared-entry", main: settings({ matcher: MATCHER, hooks: [gateHandler(), { type: "command", command: "node /other/hook.js" }] }), exit: 3, want: ["還有 1 個非 gate 的 handler", "停手"] },
  { id: "halt-main2-diff-command", main: settings(gateEntry(), gateEntry(CMD_STALE)), exit: 3, want: ["matcher／command 不一致", "停手"] },
  { id: "halt-main2-diff-matcher", main: settings(gateEntry(), gateEntry(CMD, "Bash")), exit: 3, want: ["matcher／command 不一致", "停手"] },
  // ↓ Codex 2026-08-08 指出的回歸路徑：main 一筆 stale ＋ local 一筆正確。
  //   只比 settings.json 的話會判成 B（純減法），使用者刪光 local 只留壞的那筆。
  { id: "halt-main-stale-local-good", main: settings(gateEntry(CMD_STALE)), local: settings(gateEntry()), exit: 3, want: ["停手"], deny: ["『B. 已經有一筆』"] },
  { id: "halt-local2-diff", local: settings(gateEntry(), gateEntry(CMD_STALE)), exit: 3, want: ["停手"] },

  // ---- 判定可執行：exit 0 ----------------------------------------------
  { id: "ok-normal", main: settings(gateEntry()), exit: 0, want: ["gate 條目：1 個", "檔案不存在", "正常，不用修"] },
  // 真機 census 樣本：local 存在但沒有 hooks 段
  { id: "ok-normal-local-no-hooks", main: settings(gateEntry()), local: { permissions: {} }, exit: 0, want: ["沒有 hooks 段 —— gate 條目：0 個", "正常，不用修"] },
  { id: "ok-duplicate-identical", main: settings(gateEntry(), gateEntry()), exit: 0, want: ["有 2 筆 gate", "已經重複註冊", "『B. 已經有一筆』"] },
  { id: "ok-both-identical", main: settings(gateEntry()), local: settings(gateEntry()), exit: 0, want: ["兩邊都有", "『B. 已經有一筆』"] },
  { id: "ok-local-only", main: { hooks: { PreToolUse: [] } }, local: settings(gateEntry()), exit: 0, want: ["受影響", "『A. 還沒有』"] },
  { id: "ok-none-both-missing", exit: 0, want: ["檔案不存在", "兩邊都沒有 gate"] },
  { id: "ok-none-no-pretooluse", main: { hooks: { PostToolUse: [] } }, exit: 0, want: ["沒有 hooks.PreToolUse —— gate 條目：0 個", "兩邊都沒有 gate"] },
  { id: "ok-none-nongate-handler", main: settings({ matcher: "Bash", hooks: [{ type: "command", command: "node /other/hook.js" }] }), exit: 0, want: ["gate 條目：0 個", "兩邊都沒有 gate"] },
  { id: "ok-bom", main: { raw: "\uFEFF" + JSON.stringify(settings(gateEntry())) }, exit: 0, want: ["正常，不用修"] },
  { id: "ok-entry-without-hooks-key", main: settings({ matcher: "Bash" }, gateEntry()), exit: 0, want: ["gate 條目：1 個", "正常，不用修"] },
  // 使用者本來就有的、與本 skill 無關的 PreToolUse 條目：不能被算進來，也不能觸發停手
  { id: "ok-gate-plus-unrelated-entry", main: settings({ matcher: "Bash", hooks: [{ type: "command", command: "node /other/hook.js" }] }, gateEntry()), exit: 0, want: ["gate 條目：1 個", "正常，不用修"] },
  // 同一個 entry 裡兩筆**相同**的 gate handler：others=0，不該判停手，該判重複註冊
  { id: "ok-two-gate-same-entry", main: settings({ matcher: MATCHER, hooks: [gateHandler(), gateHandler()] }), exit: 0, want: ["有 2 筆 gate", "已經重複註冊"], deny: ["停手"] },
  // 讀取錯誤（非 ENOENT）：settings.json 是目錄。錯誤碼各平台可能不同，只斷言前綴。
  { id: "read-error-directory", main: { dir: true }, exit: 1, want: ["讀取失敗：", "無法解析或形狀不合"] },

  // ---- exec form（Claude Code 官方支援的第二種 command hook 形態）-------
  // needle 在 args 裡、command 只是 "node"。只找 command 會數成 0，
  // 於是 AI-INSTALL 步驟 2 判「兩邊都沒有 gate」並叫人再加一筆 = 自己製造重複註冊。
  { id: "ok-exec-form", main: settings(execEntry()), exit: 0, want: ["gate 條目：1 個", "正常，不用修"], deny: ["兩邊都沒有 gate"] },
  { id: "ok-duplicate-exec-form", main: settings(execEntry(), execEntry()), exit: 0, want: ["有 2 筆 gate", "已經重複註冊"] },
  // shell form ＋ exec form 混用：文字上不同，保守停手
  { id: "halt-mixed-forms", main: settings(gateEntry()), local: settings(execEntry()), exit: 3, want: ["停手"] },
  { id: "exec-form-type-prompt", main: settings({ matcher: MATCHER, hooks: [{ type: "prompt", command: "node", args: ["/x/super-mode-consult-gate.js"] }] }), exit: 1, want: ['type 是 "prompt"'], deny: ["正常，不用修"] },
  { id: "args-not-array", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: "node", args: "/x/super-mode-consult-gate.js" }] }), exit: 1, want: ["PreToolUse[0].hooks[0].args 不是陣列（是 string）"] },
  { id: "args-element-not-string", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: "node", args: [7, "/x/super-mode-consult-gate.js"] }] }), exit: 1, want: ["PreToolUse[0].hooks[0].args[0] 不是字串（是 number）"] },
  // 不相干的 exec-form handler（args 裡沒有 needle）不能被算進來
  { id: "ok-unrelated-exec-form", main: settings({ matcher: "Bash", hooks: [{ type: "command", command: "node", args: ["/other/hook.js"] }] }), exit: 0, want: ["gate 條目：0 個", "兩邊都沒有 gate"] },
];

// ── 執行 ────────────────────────────────────────────────────────────────
const work = fs.mkdtempSync(path.join(os.tmpdir(), "probe-gate-"));
let pass = 0;
const failed = [];

function writeFixture(dir, name, value) {
  if (value === undefined) return; // 檔案刻意不存在
  const isPlain = value !== null && typeof value === "object" && !Array.isArray(value);
  if (isPlain && value.dir === true) {
    fs.mkdirSync(path.join(dir, name), { recursive: true }); // 讓 readFileSync 撞非 ENOENT 的錯
    return;
  }
  const body = isPlain && typeof value.raw === "string" ? value.raw : JSON.stringify(value, null, 2);
  fs.writeFileSync(path.join(dir, name), body);
}

for (const c of CASES) {
  const home = path.join(work, c.id);
  fs.mkdirSync(path.join(home, ".claude"), { recursive: true });
  writeFixture(path.join(home, ".claude"), "settings.json", c.main);
  writeFixture(path.join(home, ".claude"), "settings.local.json", c.local);

  const r = spawnSync(process.execPath, [probe], {
    encoding: "utf8",
    env: Object.assign({}, process.env, { HOME: home, USERPROFILE: home }),
  });
  const out = (r.stdout || "") + (r.stderr || "");
  const problems = [];
  if (r.status !== c.exit) problems.push("退出碼 " + r.status + "（預期 " + c.exit + "）");
  for (const w of c.want || []) if (!out.includes(w)) problems.push("缺少字串「" + w + "」");
  for (const d of c.deny || []) if (out.includes(d)) problems.push("不該出現字串「" + d + "」");

  if (problems.length) {
    failed.push(c.id);
    console.log("FAIL: " + c.id + " — " + problems.join("；"));
  } else {
    pass++;
  }
}

fs.rmSync(work, { recursive: true, force: true });

console.log("");
console.log("TOTAL " + CASES.length + "  PASS " + pass + "  FAIL " + failed.length);
if (failed.length) {
  console.log("失敗的案子：" + failed.join(", "));
  process.exit(1);
}
