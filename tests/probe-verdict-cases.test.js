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
const crypto = require("crypto");
const { spawnSync, execFileSync } = require("child_process");
const { parseCliOutcome, legacyOutcome, compareCliOutcome } = require("./lib/cli-outcome.js");
const {
  PROBE_EXIT_BY_CODE, MODULE_EXIT_BY_CODE, assertMatchesSource, crossCheckCases,
} = require("./lib/verdict-manifest.js");

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
const sha = (b) => crypto.createHash("sha256").update(b).digest("hex");

/*
 * **已驗證過的 baseline**：`完整 SHA → 該 SHA 下 probe 的 blob`。
 *
 * ⚠️ 為什麼是 blob 白名單，而不是「bytes > 4000 ＋ node --check」：那兩道對
 * 「不小心抽到**現行版**」**全部會過**（實測），於是比對變成自己跟自己比、
 * 一片「相同」看起來像大成功。釘 blob 才擋得住抽錯版本。
 *
 * ⚠️ 也不要用 `origin/main`：合併之後它就是受測版本自己。
 */
const VALIDATED_BASELINES = {
  "5da2624e5f3f103f80ecca520f8ad272d2715ef5": "4ac2afb5ca1d99dab7840e0e66804e1a5eacb446",
};

let OLD = null;
let baselineInfo = null;
if (baseline) {
  // 1) 先解析成完整 commit SHA 並印出來 —— 短 ref／分支名會漂移
  let resolved;
  try {
    resolved = execFileSync("git", ["-C", REPO, "rev-parse", baseline + "^{commit}"], { encoding: "utf8" }).trim();
  } catch (e) {
    console.error("解析不了 baseline ref " + baseline + "：" + (e.message || e));
    process.exitCode = 2; return;
  }
  let blob;
  try {
    blob = execFileSync("git", ["-C", REPO, "rev-parse", baseline + ":tools/probe-gate-registration.js"], { encoding: "utf8" }).trim();
  } catch (e) {
    console.error("抽不出 " + baseline + " 的 probe blob：" + (e.message || e));
    process.exitCode = 2; return;
  }
  const sutBlob = execFileSync("git", ["-C", REPO, "hash-object", PROBE], { encoding: "utf8" }).trim();

  console.log("baseline ref：      " + baseline);
  console.log("resolved commit：   " + resolved);
  console.log("baseline probe blob：" + blob);
  console.log("SUT probe blob：     " + sutBlob);

  // 2) SUT 與 baseline 同 blob ＝ 在跟自己比，立刻停手
  if (sutBlob === blob) {
    console.error("⛔ SUT 與 baseline 是**同一個 blob** —— 這樣比不出任何東西，停手。");
    console.error("   （合併之後 origin/main 就是受測版本自己，正是這個情況。）");
    process.exitCode = 2; return;
  }
  // 3) blob 白名單
  const expected = VALIDATED_BASELINES[resolved];
  if (!expected) {
    console.error("⛔ " + resolved + " 不在已驗證的 baseline 清單內，停手。");
    console.error("   目前只有 " + Object.keys(VALIDATED_BASELINES).join(", ") + " 被驗證過。");
    console.error("   「任意歷史 ref」做不到：更早的 ref 沒有共用模組，topology 不同。");
    process.exitCode = 2; return;
  }
  if (blob !== expected) {
    console.error("⛔ blob 不符：預期 " + expected + "，實得 " + blob + " —— 抽錯版本，停手。");
    process.exitCode = 2; return;
  }

  OLD = path.join(work, "baseline-probe.js");
  fs.writeFileSync(OLD, execFileSync("git", ["-C", REPO, "show", baseline + ":tools/probe-gate-registration.js"], { maxBuffer: 1e8 }));

  // 4) 自我檢查：抽出來的檔要**自足**。
  //    現行版的 probe 會去 __dirname/../<plat>/... 讀三平台鏡像；從 mktemp 目錄跑
  //    那條路徑必然不存在 → 每一案都退化成 TOOL_INTEGRITY_ERROR，比對到的是垃圾。
  //    （`5da2624` 的 probe 實測**不含** loadShared／MIRROR_PLATFORMS，所以自足。）
  const oldSrc = fs.readFileSync(OLD, "utf8");
  if (/MIRROR_PLATFORMS|function loadShared/.test(oldSrc)) {
    console.error("⛔ 抽出的 baseline 依賴 payload 內的共用模組，從暫存目錄執行會全部退化成");
    console.error("   TOOL_INTEGRITY_ERROR —— 比對結果無意義，停手。");
    process.exitCode = 2; return;
  }
  const chk = spawnSync(process.execPath, ["--check", OLD], { encoding: "utf8" });
  if (chk.status !== 0) { console.error("抽出的 baseline 語法不通，停手"); process.exitCode = 2; return; }

  baselineInfo = { resolved, blob, sutBlob, selfContained: true, hasMarker: /RESULT_CODE/.test(oldSrc) };
  console.log("baseline 自足性：   OK（不依賴共用模組）");
  console.log("baseline 有 marker：" + (baselineInfo.hasMarker ? "有" : "**無** → 舊版 code 一律標 N/A"));
  console.log("");
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
  /*
   * ⚠️ **exec form 五案：probe 印的是 `HALT_EXEC_FORM`（exit 3），不是
   * `UNSUPPORTED_EXEC_FORM`。** 後者是 **matcher-contract** 對同一種輸入的 code、
   * 而且 exit 是 1。
   *
   * 這五案原本釘成 `UNSUPPORTED_EXEC_FORM` 卻仍然 PASS，是本批存在的直接原因：
   * 舊 oracle 用未錨定的 `/RESULT_CODE=([A-Z_]+)/` 取第一筆，抓到的是
   * `gate-registration.js` **散文**裡的字面 `RESULT_CODE=UNSUPPORTED_EXEC_FORM`。
   * 案子自己內部其實早就矛盾了 —— 期望 exit 寫 3，而 `UNSUPPORTED_EXEC_FORM` 是 exit 1；
   * 沒有 code→exit manifest 就看不出來。現在兩道都有了。
   */
  ["halt-exec", S(e([gx()])), undefined, "HALT_EXEC_FORM", 3],
  ["halt-exec-dup", S(e([gx()]), e([gx()])), undefined, "HALT_EXEC_FORM", 3],
  ["halt-exec-mixed-files", S(e([g()])), S(e([gx()])), "HALT_EXEC_FORM", 3],
  ["halt-echo-args", S(e([{ type: "command", command: "echo", args: ["super-mode-consult-gate"] }])), undefined, "HALT_EXEC_FORM", 3],
  ["halt-args-only", S(e([{ type: "command", args: ["/x/super-mode-consult-gate.js"] }])), undefined, "HALT_EXEC_FORM", 3],
  ["halt-shared", S(e([g(), { type: "command", command: "node /other/hook.js" }])), undefined, "HALT_SHARED_ENTRY", 3],
  ["halt-diff-command", S(e([g()]), e([g({ command: STALE })])), undefined, "HALT_INCONSISTENT", 3],
  ["halt-diff-matcher", S(e([g()]), e([g()], "Bash")), undefined, "HALT_INCONSISTENT", 3],
  ["halt-main-stale-local-good", S(e([g({ command: STALE })])), S(e([g()])), "HALT_INCONSISTENT", 3],
  ["halt-local2-diff", undefined, S(e([g()]), e([g({ command: STALE })])), "HALT_INCONSISTENT", 3],
];

/*
 * 案例清單的**宣告數量**。刪掉一案卻仍印「55/55 PASS」是抓不到的假綠，
 * 所以數量本身要被釘住 —— 增刪案例必須同步改這個數字。
 */
const EXPECTED_CASE_COUNT = 56;

/*
 * manifest 裡**允許沒有案例涵蓋**的 code，每一筆都要有理由。
 * 沒列在這裡的 orphan 一律算失敗（逼人補案例，而不是默默少驗一塊）。
 */
const UNCOVERED_OK = [
  "CONFIG_DIR_OVERRIDE", // 需要設環境變數，不是 settings fixture 能造出來的；由 probe-gate-registration.test.js 覆蓋
  "TOOL_INTEGRITY_ERROR", // 需要破壞 payload 的三平台鏡像；由 oracle-teeth 與 probe-gate-registration.test.js 覆蓋
  "INTERNAL_ERROR",       // 只在未預期例外時出現，無法用合法 fixture 觸發
  "BAD_ARGS",             // 參數層，不經 settings fixture；由 probe-gate-registration.test.js 覆蓋
];

/*
 * §「已知的刻意差異」—— `--baseline` 比對時預期會不同的 fixture。
 * 清單以外的任何差異都算失敗；宣告了卻沒差異也算失敗（清單過期）。
 *
 * ⚠️ 每筆除了理由，還釘 `oldExit`（舊版退出碼）與 `regionHash`（舊版判定區的 sha256）。
 * 只驗「有差」是不夠的 —— 差異的**內容**變了也必須被看見，否則「刻意差異」會變成
 * 一個吸收任何新差異的黑洞。
 */
/*
 * ⚠️ 下面五筆的 `regionHash` **刻意相同**（`11008b17…`）。那不是複製貼上失誤：
 * 這五個 fixture 在**舊版**都只有一筆 gate handler、command 與 matcher 完全一樣，
 * 而舊版判定區只印「條目數 ＋ handler command」，所以輸出逐位元相同 ——
 * 全部都是那句假綠的「判定：正常，不用修。」。這正是本批要修掉的東西。
 */
const INTENTIONAL_DIFFS = {
  // 文案變更（判定與退出碼不變）
  "halt-exec": { reason: "exec form 的理由文案：舊版說「matcher-contract 也只看 command，會回報沒有註冊本 hook」，本批之後那句變成假的", oldExit: 3, regionHash: "59e30af359ddde18c0bd929f8da2d9a4f316a94e744dfbf8a66e7c45bebf2977" },
  "halt-exec-dup": { reason: "同上", oldExit: 3, regionHash: "f1099b04aab3f328033b02ff46b0859d94d2100e39eef744db3bfeba28a4b739" },
  "halt-exec-mixed-files": { reason: "同上", oldExit: 3, regionHash: "fa05885228508cb5e6cc1af3ffd8f761716e9f98ea13ecf48160414805bfc097" },
  "halt-echo-args": { reason: "同上", oldExit: 3, regionHash: "2bda2da58e7b0dee23a1bb67f6882373dfab15babc3dcf95f49152701cdac746" },
  "halt-args-only": { reason: "同上", oldExit: 3, regionHash: "580ed95fd54e9b685c40e65d9873a0366f8b029ef55f8a6d6ded04eb46589f46" },
  // 行為變更（舊版假綠，本批修掉）—— 每一條都是本批存在的理由
  "unsafe-if": { reason: "舊版 exit 0「正常，不用修」：`if` 把 gate 限縮到別的工具，Edit/Write 完全不受攔", oldExit: 0, regionHash: "11008b17167e8e651382d7cf650af7905c213795a22a3eb5eafa8b5769014216" },
  "unsafe-async": { reason: "舊版 exit 0：`async` 非阻塞，PreToolUse 的 deny 來不及生效", oldExit: 0, regionHash: "11008b17167e8e651382d7cf650af7905c213795a22a3eb5eafa8b5769014216" },
  "kill-switch-main": { reason: "舊版 exit 0：`disableAllHooks:true` 把所有 hook 關掉，gate 註冊再完美也不會被叫起", oldExit: 0, regionHash: "11008b17167e8e651382d7cf650af7905c213795a22a3eb5eafa8b5769014216" },
  "kill-switch-local": { reason: "舊版 exit 0：local 的總開關在「從家目錄啟動」時生效且 local 覆蓋 user，不能靜默忽略", oldExit: 0, regionHash: "241351a37b0164822f593c8c83c210d175bd75660ee58f398f1a46c2d6c849d1" },
  "shape-timeout-zero": { reason: "舊版 exit 0：官方 settings JSON schema 對 timeout 是 exclusiveMinimum: 0，違反則整份 settings 被拒絕載入", oldExit: 0, regionHash: "11008b17167e8e651382d7cf650af7905c213795a22a3eb5eafa8b5769014216" },
  "shape-kill-switch-string": { reason: "舊版 exit 0：`disableAllHooks:\"true\"` 型別錯卻被當成「沒設」放行；不猜成啟用，但也不能靜默忽略", oldExit: 0, regionHash: "11008b17167e8e651382d7cf650af7905c213795a22a3eb5eafa8b5769014216" },
};

function place(home, name, val) {
  const p = path.join(home, ".claude", name);
  if (val === undefined) return; // 檔案刻意不存在
  if (val === "<DIR>") { fs.mkdirSync(p); return; }
  fs.writeFileSync(p, typeof val === "string" ? val : JSON.stringify(val, null, 2));
}
function run(probe, home) {
  // 回傳**原始 spawn 結果**：oracle 需要 stdout／stderr／status／signal／error 全部，
  // 只回傳 { status, out } 會讓 stderr 與 signal 靜默消失。
  return spawnSync(process.execPath, [probe], {
    encoding: "utf8",
    // CLAUDE_CONFIG_DIR 一定要清掉：驗證者自己設了它的話，probe 會全部 fail-closed，
    // 這一整套就變成量不到東西卻看起來「有跑」。
    env: Object.assign({}, process.env, { HOME: home, USERPROFILE: home, CLAUDE_CONFIG_DIR: "" }),
  });
}
const verdictRegion = (out) => {
  const i = out.indexOf(SCOPE_HEAD);
  return i < 0 ? out : out.slice(0, i);
};

// ── 前置：案例清單自身的完整性（抓「案子被刪掉還是 55/55」這類假綠）──────────
const preflight = [];
{
  const ids = CASES.map((c) => c[0]);
  const dupes = ids.filter((id, i) => ids.indexOf(id) !== i);
  if (dupes.length) preflight.push("案例 ID 重複：" + Array.from(new Set(dupes)).join(", "));
  if (CASES.length !== EXPECTED_CASE_COUNT) {
    preflight.push("案例數 " + CASES.length + " ≠ 宣告的 " + EXPECTED_CASE_COUNT +
      " —— 有人增刪案例卻沒更新宣告（刪掉一案仍印 n/n 是抓不到的假綠）");
  }
  // 案例 ↔ manifest 雙向 orphan
  const used = new Set(CASES.map((c) => c[3]));
  preflight.push(...crossCheckCases(used, PROBE_EXIT_BY_CODE, { uncoveredOk: UNCOVERED_OK }));
  // manifest ↔ 產品原始碼。⚠️ 用**聯集**：這個模組同時含 probe 與 matcher 兩支判定函式，
  // 只拿 probe 的表去比，會把 matcher 的 code 誤報成「產品會印但沒登記」。
  preflight.push(...assertMatchesSource(
    path.join(REPO, "windows", "skills", "超級模式", "lib", "gate-registration.js"),
    MODULE_EXIT_BY_CODE,
    // 釘住這批：`HALT_EXEC_FORM` 與 `UNSUPPORTED_EXEC_FORM` **必須同時存在且分屬不同 exit**，
    // 這正是本批修掉的混淆點；哪天有人把它們合併，這裡要立刻紅。
    { expectInSource: ["HALT_EXEC_FORM", "UNSUPPORTED_EXEC_FORM", "OK_NORMAL", "SHAPE_ERROR"] }
  ));
  // 案例宣告的 exit 必須符合 manifest（抓「期望值自己就寫錯」）
  for (const [id, , , wantCode, wantExit] of CASES) {
    if (Object.prototype.hasOwnProperty.call(PROBE_EXIT_BY_CODE, wantCode) &&
        PROBE_EXIT_BY_CODE[wantCode] !== wantExit) {
      preflight.push("案例 " + id + " 宣告 " + wantCode + " 配 exit " + wantExit +
        "，但 manifest 說應為 " + PROBE_EXIT_BY_CODE[wantCode]);
    }
  }
  // INTENTIONAL_DIFFS 的 orphan key
  for (const k of Object.keys(INTENTIONAL_DIFFS)) {
    if (!ids.includes(k)) preflight.push("INTENTIONAL_DIFFS 有 " + k + " 但案例清單裡沒有這個 ID");
  }
}
if (preflight.length) {
  console.log("⛔ 前置檢查失敗，不進行量測（量測結果會不可信）：");
  for (const p of preflight) console.log("   ・" + p);
  fs.rmSync(work, { recursive: true, force: true });
  process.exitCode = 1;
  return;
}

let pass = 0;
let executed = 0;
const failed = [];
const seen = {};       // **實測** code 的直方圖
const seenWanted = {}; // 期望 code 的直方圖（只用來對照，不當涵蓋率report）
const diffIds = [];
const unpinned = []; // 宣告了刻意差異但尚未釘 regionHash 的案子

for (const [id, mainVal, localVal, wantCode, wantExit] of CASES) {
  executed++;
  const home = path.join(work, "new-" + id);
  fs.mkdirSync(path.join(home, ".claude"), { recursive: true });
  place(home, "settings.json", mainVal);
  place(home, "settings.local.json", localVal);
  const now = run(PROBE, home);

  const actual = parseCliOutcome(now);
  const problems = compareCliOutcome(actual, { code: wantCode, exit: wantExit }, PROBE_EXIT_BY_CODE);

  // ⚠️ 直方圖統計**實測**值。舊版統計期望值，於是 exec form 五案的錯誤期望
  // 讓報表印出 probe 根本不會產生的 `UNSUPPORTED_EXEC_FORM ×5`。
  const measured = actual.code || "(缺 RESULT_CODE)";
  seen[measured] = (seen[measured] || 0) + 1;
  seenWanted[wantCode] = (seenWanted[wantCode] || 0) + 1;

  // probe 的所有輸出都應在 stdout；stderr 有東西代表有未預期的例外或雜訊。
  if (actual.streams.err.text.trim() !== "") {
    problems.push("stderr 非空：" + JSON.stringify(actual.streams.err.text.slice(0, 120)));
  }

  /*
   * **保留字串唯一性**：`RESULT_CODE=` 是機器介面的命名空間，整份輸出裡
   * 只准出現一次（就是最後那個真標記）。散文不得寫出 `RESULT_CODE=<CODE>` 字面。
   *
   * ⚠️ 這是**與錨定 oracle 互相獨立的第二道防線**，兩者防的是不同方向：
   *   ・錨定 oracle    → 防 consumer 誤讀（抓錯行）
   *   ・保留字串唯一性 → 防 producer 污染命名空間（散文長出假標記）
   * 只有前者的話，產品仍可繼續在散文裡埋假標記，下一個寫 oracle 的人會再踩一次。
   */
  const loose = (actual.streams.out.text.match(/RESULT_CODE=/g) || []).length +
                (actual.streams.err.text.match(/RESULT_CODE=/g) || []).length;
  if (loose !== 1) {
    problems.push("輸出裡 `RESULT_CODE=` 字面出現 " + loose + " 次（必須恰一次）—— " +
      "散文不得寫出保留字串，否則會被未錨定的 oracle 抓成假標記");
  }

  if (baseline) {
    const oh = path.join(work, "old-" + id);
    fs.mkdirSync(path.join(oh, ".claude"), { recursive: true });
    place(oh, "settings.json", mainVal);
    place(oh, "settings.local.json", localVal);
    const then = run(OLD, oh);
    // 舊版沒有 marker → 走 legacy 分支，code 標 N/A，只驗 spawn 健康＋exit＋判定區。
    const old = legacyOutcome(then);
    problems.push(...old.problems);

    const nowRegion = verdictRegion(parseCliOutcome(now).streams.out.text);
    const thenRegion = verdictRegion(old.streams.out.text);
    const differs = thenRegion !== nowRegion;
    const decl = INTENTIONAL_DIFFS[id];

    if (differs) {
      diffIds.push(id);
      if (!decl) {
        problems.push("判定區與 baseline 不同，且不在「已知的刻意差異」清單裡");
      } else if (!decl.regionHash) {
        // 還沒釘 hash 的，把實測值印出來供維護者貼回清單（不算失敗，但會提醒）
        unpinned.push('  "' + id + '": regionHash: "' + sha(thenRegion) + '"');
      } else if (decl.regionHash !== sha(thenRegion)) {
        // ⚠️ 只驗「有差」不夠：差異的**內容**改了也該被看見。
        problems.push("baseline 判定區 hash 與宣告不符（宣告 " + decl.regionHash +
          "，實得 " + sha(thenRegion) + "）—— 差異內容變了，請重新確認理由是否仍成立");
      }
      // baseline 端的**退出碼**也要比對（舊版本連 exit 都沒比）
      if (decl && typeof decl.oldExit === "number" && then.status !== decl.oldExit) {
        problems.push("baseline 退出碼 " + then.status + "（宣告 " + decl.oldExit + "）");
      }
    } else if (decl) {
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
console.log("涵蓋的 RESULT_CODE（**實測**，" + Object.keys(seen).length + " 種）：");
for (const k of Object.keys(seen).sort()) console.log("   " + k + "  ×" + seen[k]);
if (baseline) {
  console.log("");
  console.log("判定區與 " + baselineInfo.resolved.slice(0, 7) + " 相同：" +
    (CASES.length - diffIds.length) + "/" + CASES.length +
    "（不同 " + diffIds.length + "，共宣告 " + Object.keys(INTENTIONAL_DIFFS).length + " 筆刻意差異）");
  if (diffIds.length) console.log("   不同的案子：" + diffIds.join(", "));
  if (unpinned.length) {
    console.log("");
    console.log("⚠️ 下列刻意差異尚未釘 regionHash（只驗「有差」，抓不到差異內容被改掉）：");
    for (const u of unpinned) console.log(u);
  }
}
console.log("");
if (executed !== CASES.length) {
  console.log("⛔ 實際執行 " + executed + " 案 ≠ 清單 " + CASES.length + " 案");
  process.exitCode = 1;
}
console.log("TOTAL " + CASES.length + "  執行 " + executed + "  PASS " + pass + "  FAIL " + failed.length);
if (failed.length) {
  console.log("失敗的案子：" + failed.join(", "));
  process.exitCode = 1;
}
