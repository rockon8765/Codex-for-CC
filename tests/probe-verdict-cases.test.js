#!/usr/bin/env node
/*
 * probe 的**判定矩陣**回歸案：每個 fixture 釘死它應該產出的 `RESULT_CODE` 與退出碼。
 *
 * 用法：
 *   node tests/probe-verdict-cases.test.js
 *   node tests/probe-verdict-cases.test.js --baseline <git-ref>
 *       額外把**判定區**（範圍說明之前的全部內容）與該 ref 的 probe 逐位元比對。
 *       差異一律列出，不做白名單 —— 刻意改過的差異寫在 §「已知的刻意差異」。
 *
 * 為什麼要有這一支（而不是只有 `probe-gate-registration.test.js`）：
 * 那一支驗「這些輸入會不會得到正確判定」，用的是必含／禁含字串；**這一支驗判定矩陣的
 * 形狀**——47 個輸入各自落在哪個 code、涵蓋幾種 code。兩者抓的東西不同：
 * 前者抓「訊息對不對」，後者抓「有沒有整片坍縮到同一個 code」。
 *
 * ⚠️ **它存在的直接原因是我用壞掉的工具量過一次。** 2026-08-09 我報「probe 判定區
 * 47/47 逐位元相同」，那份比對工具的 fixture 把「local 檔不存在」寫成 `null`，
 * 於是寫出一個**內容為 `null`** 的檔，幾乎每個 fixture 都落在 `SHAPE_ERROR`——
 * 47/47 是真的，但涵蓋的分支遠少於我宣稱的。合併前審查另指出「至少 N 種 code」
 * 這種門檻仍可能讓大部分案子坍縮而通過。**所以這裡逐案釘死 code，不用門檻。**
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync, execFileSync } = require("child_process");

// ── 參數 ────────────────────────────────────────────────────────────────
let baseline = null;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--baseline") {
    baseline = process.argv[++i];
    if (!baseline) { console.error("--baseline 後面要接 git ref"); process.exitCode = 2; return; }
  } else {
    console.error("未知參數：" + process.argv[i]);
    process.exitCode = 2;
    return;
  }
}

const REPO = path.join(__dirname, "..");
const PROBE = path.join(REPO, "tools", "probe-gate-registration.js");
const SCOPE_HEAD = "⚠️ 本工具只數「gate 註冊了幾筆」，範圍刻意很窄：";
const work = fs.mkdtempSync(path.join(os.tmpdir(), "probe-verdict-"));

let OLD = null;
if (baseline) {
  OLD = path.join(work, "baseline-probe.js");
  try {
    fs.writeFileSync(OLD, execFileSync("git", ["-C", REPO, "show", baseline + ":tools/probe-gate-registration.js"], { maxBuffer: 1e8 }));
  } catch (e) {
    console.error("抽不出 " + baseline + " 的 probe：" + (e.message || e));
    process.exitCode = 2;
    return;
  }
  // 抽取自我檢查：空檔或語法不通的話，下面每一案都會「失敗」，看起來像大發現其實是量測壞了。
  const sz = fs.statSync(OLD).size;
  if (sz < 4000) { console.error("抽出的 baseline 只有 " + sz + " bytes，抽取失敗，停手"); process.exitCode = 2; return; }
  const chk = spawnSync(process.execPath, ["--check", OLD], { encoding: "utf8" });
  if (chk.status !== 0) { console.error("抽出的 baseline 語法不通，停手"); process.exitCode = 2; return; }
  console.log("baseline：" + baseline + "（" + sz + " bytes，語法 OK）");
}

// ── fixture 素材 ────────────────────────────────────────────────────────
const M = "Write|Edit|NotebookEdit|Bash|PowerShell|Monitor|mcp__.*";
const CMD = "node /home/u/.claude/hooks/super-mode-consult-gate.js";
const STALE = "node /old/path/super-mode-consult-gate.js";
const g = (o) => Object.assign({ type: "command", command: CMD }, o || {});
const gx = (p) => ({ type: "command", command: "node", args: [p || "/x/super-mode-consult-gate.js"] });
const e = (hooks, m) => ({ matcher: m === undefined ? M : m, hooks });
const S = (...xs) => ({ hooks: { PreToolUse: xs } });

/*
 * `[id, settings.json 的內容, settings.local.json 的內容, 期望 code, 期望 exit]`
 *
 * ⚠️ **`undefined` ＝ 檔案不存在；`null` ＝ 檔案內容是 JSON `null`。** 這個區別是刻意的，
 * 而且搞混它正是上面提到的那次錯誤量測的成因。
 */
const CASES = [
  ["ok-normal", S(e([g()])), undefined, "OK_NORMAL", 0],
  ["ok-none-both-missing", undefined, undefined, "OK_NONE", 0],
  ["ok-none-no-hooks", { permissions: {} }, undefined, "OK_NONE", 0],
  ["ok-none-no-pretooluse", { hooks: { PostToolUse: [] } }, undefined, "OK_NONE", 0],
  ["ok-none-nongate", S(e([{ type: "command", command: "node /other.js" }], "Bash")), undefined, "OK_NONE", 0],
  ["ok-dup-main", S(e([g()]), e([g()])), undefined, "OK_DUPLICATE_MAIN", 0],
  ["ok-dup-same-entry", S(e([g(), g()])), undefined, "OK_DUPLICATE_MAIN", 0],
  ["ok-both", S(e([g()])), S(e([g()])), "OK_BOTH", 0],
  ["ok-local-only", { hooks: { PreToolUse: [] } }, S(e([g()])), "OK_LOCAL_ONLY", 0],
  ["ok-local-no-hooks", S(e([g()])), { permissions: {} }, "OK_NORMAL", 0],
  ["ok-entry-without-hooks", S({ matcher: "Bash" }, e([g()])), undefined, "OK_NORMAL", 0],
  ["ok-gate-plus-unrelated", S(e([{ type: "command", command: "node /other.js" }], "Bash"), e([g()])), undefined, "OK_NORMAL", 0],
  ["ok-bom", "﻿" + JSON.stringify(S(e([g()]))), undefined, "OK_NORMAL", 0],
  ["ok-nongate-bad-type", S(e([{ type: 7, command: "node /other.js" }], "Bash")), undefined, "OK_NONE", 0],
  ["ok-type-command-no-command", S(e([{ type: "command" }], "Bash")), undefined, "OK_NONE", 0],
  ["ok-unrelated-exec", S(e([{ type: "command", command: "node", args: ["/other.js"] }], "Bash")), undefined, "OK_NONE", 0],
  // 已知假陽性（substring 命中但不跑 gate）—— 刻意判正常，見 probe 的範圍說明
  ["ok-echo-needle", S(e([{ type: "command", command: "echo super-mode-consult-gate" }])), undefined, "OK_NORMAL", 0],
  ["ok-timeout-positive", S(e([g({ timeout: 0.001 })])), undefined, "OK_NORMAL", 0],
  ["ok-once-ignored-in-settings", S(e([g({ once: true })])), undefined, "OK_NORMAL", 0],
  ["ok-kill-switch-false", Object.assign({ disableAllHooks: false }, S(e([g()]))), undefined, "OK_NORMAL", 0],
  ["shape-invalid-json", "{ 這不是 JSON", undefined, "SHAPE_ERROR", 1],
  ["shape-top-null", null, undefined, "SHAPE_ERROR", 1],
  ["shape-top-array", [], undefined, "SHAPE_ERROR", 1],
  ["shape-hooks-string", { hooks: "x" }, undefined, "SHAPE_ERROR", 1],
  ["shape-pre-object", { hooks: { PreToolUse: {} } }, undefined, "SHAPE_ERROR", 1],
  ["shape-pre-string", { hooks: { PreToolUse: CMD } }, undefined, "SHAPE_ERROR", 1],
  ["shape-entry-not-object", S("x"), undefined, "SHAPE_ERROR", 1],
  ["shape-entry-hooks-string", S({ matcher: M, hooks: "x" }), undefined, "SHAPE_ERROR", 1],
  ["shape-handler-not-object", S(e(["x"])), undefined, "SHAPE_ERROR", 1],
  ["shape-command-array", S(e([{ type: "command", command: [CMD] }])), undefined, "SHAPE_ERROR", 1],
  ["shape-args-string", S(e([{ type: "command", command: "node", args: "/x/super-mode-consult-gate.js" }])), undefined, "SHAPE_ERROR", 1],
  ["shape-args-el-number", S(e([{ type: "command", command: "node", args: [7, "/x/super-mode-consult-gate.js"] }])), undefined, "SHAPE_ERROR", 1],
  ["shape-type-missing", S(e([{ command: CMD }])), undefined, "SHAPE_ERROR", 1],
  ["shape-type-prompt", S(e([{ type: "prompt", command: CMD }])), undefined, "SHAPE_ERROR", 1],
  ["shape-type-http", S(e([{ type: "http", command: CMD }])), undefined, "SHAPE_ERROR", 1],
  ["shape-matcher-number", S(e([g()], 5)), undefined, "SHAPE_ERROR", 1],
  ["shape-mixed-good-then-bad", S(e([g()]), e([{ type: "prompt", command: CMD }])), undefined, "SHAPE_ERROR", 1],
  ["shape-local-invalid", S(e([g()])), "{", "SHAPE_ERROR", 1],
  ["shape-exec-type-prompt", S(e([{ type: "prompt", command: "node", args: ["/x/super-mode-consult-gate.js"] }])), undefined, "SHAPE_ERROR", 1],
  ["shape-timeout-zero", S(e([g({ timeout: 0 })])), undefined, "SHAPE_ERROR", 1],
  ["shape-kill-switch-string", Object.assign({ disableAllHooks: "true" }, S(e([g()]))), undefined, "SHAPE_ERROR", 1],
  ["read-error-dir", "<DIR>", undefined, "SHAPE_ERROR", 1],
  ["unsafe-if", S(e([g({ if: "Bash(git push *)" })])), undefined, "UNSAFE_FIELD", 1],
  ["unsafe-async", S(e([g({ async: true })])), undefined, "UNSAFE_FIELD", 1],
  ["kill-switch-main", Object.assign({ disableAllHooks: true }, S(e([g()]))), undefined, "HOOKS_DISABLED", 1],
  ["kill-switch-local", S(e([g()])), { disableAllHooks: true }, "HALT_LOCAL_HOOKS_DISABLED", 3],
  ["halt-exec", S(e([gx()])), undefined, "UNSUPPORTED_EXEC_FORM", 3],
  ["halt-exec-dup", S(e([gx()]), e([gx()])), undefined, "UNSUPPORTED_EXEC_FORM", 3],
  ["halt-exec-mixed-files", S(e([g()])), S(e([gx()])), "UNSUPPORTED_EXEC_FORM", 3],
  ["halt-echo-args", S(e([{ type: "command", command: "echo", args: ["super-mode-consult-gate"] }])), undefined, "UNSUPPORTED_EXEC_FORM", 3],
  ["halt-args-only", S(e([{ type: "command", args: ["/x/super-mode-consult-gate.js"] }])), undefined, "UNSUPPORTED_EXEC_FORM", 3],
  ["halt-shared", S(e([g(), { type: "command", command: "node /other/hook.js" }])), undefined, "HALT_SHARED_ENTRY", 3],
  ["halt-diff-command", S(e([g()]), e([g({ command: STALE })])), undefined, "HALT_INCONSISTENT", 3],
  ["halt-diff-matcher", S(e([g()]), e([g()], "Bash")), undefined, "HALT_INCONSISTENT", 3],
  ["halt-main-stale-local-good", S(e([g({ command: STALE })])), S(e([g()])), "HALT_INCONSISTENT", 3],
  ["halt-local2-diff", undefined, S(e([g()]), e([g({ command: STALE })])), "HALT_INCONSISTENT", 3],
];

/*
 * §「已知的刻意差異」—— `--baseline` 比對時預期會不同的 fixture，附理由。
 * 清單以外的任何差異都算失敗。
 */
const INTENTIONAL_DIFFS = {
  // 文案變更（判定與退出碼不變）
  "halt-exec": "exec form 的理由文案：舊版說「matcher-contract 也只看 command，會回報沒有註冊本 hook」，本批之後那句變成假的（改回報 UNSUPPORTED_EXEC_FORM）",
  "halt-exec-dup": "同上",
  "halt-exec-mixed-files": "同上",
  "halt-echo-args": "同上",
  "halt-args-only": "同上",
  // 行為變更（舊版假綠，本批修掉）—— 每一條都是本批存在的理由
  "unsafe-if": "舊版 exit 0「正常，不用修」：`if` 把 gate 限縮到別的工具，Edit/Write 完全不受攔",
  "unsafe-async": "舊版 exit 0：`async` 非阻塞，PreToolUse 的 deny 來不及生效",
  "kill-switch-main": "舊版 exit 0：`disableAllHooks:true` 把所有 hook 關掉，gate 註冊再完美也不會被叫起",
  "kill-switch-local": "舊版 exit 0：local 的總開關在「從家目錄啟動」時生效且 local 覆蓋 user，不能靜默忽略",
  "shape-timeout-zero": "舊版 exit 0：官方 settings JSON schema 對 timeout 是 exclusiveMinimum: 0，違反則整份 settings 被拒絕載入",
  "shape-kill-switch-string": "舊版 exit 0：`disableAllHooks:\"true\"` 型別錯卻被當成「沒設」放行；不猜成啟用，但也不能靜默忽略",
};

function place(home, name, val) {
  const p = path.join(home, ".claude", name);
  if (val === undefined) return; // 檔案刻意不存在
  if (val === "<DIR>") { fs.mkdirSync(p); return; }
  fs.writeFileSync(p, typeof val === "string" ? val : JSON.stringify(val, null, 2));
}
function run(probe, home) {
  const r = spawnSync(process.execPath, [probe], {
    encoding: "utf8",
    // CLAUDE_CONFIG_DIR 一定要清掉：驗證者自己設了它的話，probe 會全部 fail-closed，
    // 這一整套就變成量不到東西卻看起來「有跑」。
    env: Object.assign({}, process.env, { HOME: home, USERPROFILE: home, CLAUDE_CONFIG_DIR: "" }),
  });
  return { status: r.status, out: (r.stdout || "").replace(/\r\n/g, "\n") };
}
const verdictRegion = (out) => {
  const i = out.indexOf(SCOPE_HEAD);
  return i < 0 ? out : out.slice(0, i);
};

let pass = 0;
const failed = [];
const seen = {};
let diffs = 0;

for (const [id, mainVal, localVal, wantCode, wantExit] of CASES) {
  const home = path.join(work, "new-" + id);
  fs.mkdirSync(path.join(home, ".claude"), { recursive: true });
  place(home, "settings.json", mainVal);
  place(home, "settings.local.json", localVal);
  const now = run(PROBE, home);

  const problems = [];
  const m = now.out.match(/RESULT_CODE=([A-Z_]+)/);
  const code = m ? m[1] : "(缺 RESULT_CODE)";
  if (code !== wantCode) problems.push("code=" + code + "（預期 " + wantCode + "）");
  if (now.status !== wantExit) problems.push("exit=" + now.status + "（預期 " + wantExit + "）");
  seen[wantCode] = (seen[wantCode] || 0) + 1;

  if (baseline) {
    const oh = path.join(work, "old-" + id);
    fs.mkdirSync(path.join(oh, ".claude"), { recursive: true });
    place(oh, "settings.json", mainVal);
    place(oh, "settings.local.json", localVal);
    const then = run(OLD, oh);
    const differs = verdictRegion(then.out) !== verdictRegion(now.out);
    if (differs) {
      diffs++;
      if (!INTENTIONAL_DIFFS[id]) problems.push("判定區與 baseline 不同，且不在「已知的刻意差異」清單裡");
    } else if (INTENTIONAL_DIFFS[id]) {
      problems.push("宣告了刻意差異，但實際與 baseline 相同 —— 清單過期了");
    }
  }

  if (problems.length) {
    failed.push(id);
    console.log("FAIL: " + id + " — " + problems.join("；"));
  } else pass++;
}

fs.rmSync(work, { recursive: true, force: true });

console.log("");
console.log("涵蓋的 RESULT_CODE（" + Object.keys(seen).length + " 種）：");
for (const k of Object.keys(seen).sort()) console.log("   " + k + "  ×" + seen[k]);
if (baseline) {
  console.log("");
  console.log("判定區與 " + baseline + " 相同：" + (CASES.length - diffs) + "/" + CASES.length +
    "（不同 " + diffs + "，全部應在「已知的刻意差異」清單內，共宣告 " + Object.keys(INTENTIONAL_DIFFS).length + " 筆）");
}
console.log("");
console.log("TOTAL " + CASES.length + "  PASS " + pass + "  FAIL " + failed.length);
if (failed.length) {
  console.log("失敗的案子：" + failed.join(", "));
  process.exitCode = 1;
}
