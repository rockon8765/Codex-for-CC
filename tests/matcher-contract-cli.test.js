#!/usr/bin/env node
/*
 * `<platform>/skills/超級模式/tests/matcher-contract.test.js` 的 **CLI 層**回歸案。
 *
 * 用法：
 *   node tests/matcher-contract-cli.test.js
 *   node tests/matcher-contract-cli.test.js --target <某版 matcher-contract.test.js>
 *
 * 為什麼與 `tests/gate-registration.test.js` 分開：那一支驗**模組**（純資料 fixture、
 * 不 spawn、不碰檔案系統）；這一支驗**命令列行為**（旗標、attestation、退出碼、
 * 有沒有噴 stack trace），必須真的把整棵樹擺好再開子程序。兩種機具塞進同一個檔案
 * 只會長出一堆模式旗標。
 *
 * ── `--target` 必須是「完整 staged bundle」，不是裸 .js ────────────────────
 *
 * 每個案子都會重建一棵最小樹，並把受測檔放到它由 `__dirname` 推導得出的位置：
 *
 *   <case>/repo/<plat>/skills/超級模式/tests/matcher-contract.test.js   ← 受測檔
 *   <case>/repo/<plat>/skills/超級模式/lib/gate-registration.js         ← 新版才需要
 *   <case>/repo/<plat>/hooks/super-mode-consult-gate.js
 *   <case>/repo/<plat>/settings.snippet.json
 *   <case>/home/.claude/settings.json                                   ← 假 HOME
 *   <case>/home/.claude/hooks/super-mode-consult-gate.js
 *
 * 少了這一步，反向驗證量到的只會是 `MODULE_NOT_FOUND`：舊版靠 `__dirname` 找 snippet
 * 與 hook，新版還要找相鄰的 lib/。（另外，舊版**會忽略** `--settings`／`--hook`，
 * 所以 fixture 一定要真的擺到它自己推導的位置，不能靠旗標餵。）
 *
 * ── 反向驗證怎麼設計 ──────────────────────────────────────────────────────
 *
 * 每個案子都宣告 `oldExit`（舊版的退出碼），少數關鍵案另外宣告 `oldWant`／`oldDeny`。
 * 所以 `--target <舊版>` 不只是「會失敗」，而是對舊版行為的**正面刻畫**——
 * 這比核對失敗總數強得多。attestation 是新版才有的輸出，若只比字串會讓每一案都因為
 * 同一個瑣碎理由失敗，反向驗證就失去區辨力。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

// ── 參數 ────────────────────────────────────────────────────────────────
const CANON_PLAT = "windows"; // 三平台受測檔逐位元相同，由 gate-registration.test.js §C 保證
let target = path.join(__dirname, "..", CANON_PLAT, "skills", "超級模式", "tests", "matcher-contract.test.js");
let reverse = false;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--target") {
    if (!process.argv[i + 1]) { console.error("--target 後面要接路徑"); process.exitCode = 2; return; }
    target = path.resolve(process.argv[++i]);
    reverse = true;
  } else {
    console.error("未知參數：" + process.argv[i]);
    process.exitCode = 2;
    return;
  }
}
if (!fs.existsSync(target)) { console.error("找不到受測檔：" + target); process.exitCode = 2; return; }
console.log("受測 matcher-contract：" + target);
console.log("模式：" + (reverse ? "反向驗證（斷言 oldExit／oldWant／oldDeny）" : "正向"));

const MODULE_SRC = path.join(__dirname, "..", CANON_PLAT, "skills", "超級模式", "lib", "gate-registration.js");
const HOOK_SRC = path.join(__dirname, "..", CANON_PLAT, "hooks", "super-mode-consult-gate.js");
const SNIPPET_SRC = path.join(__dirname, "..", CANON_PLAT, "settings.snippet.json");
const CANON_SNIPPET = JSON.parse(fs.readFileSync(SNIPPET_SRC, "utf8"));
const CANON_MATCHER = CANON_SNIPPET.hooks.PreToolUse[0].matcher;
const CANON_CMD = CANON_SNIPPET.hooks.PreToolUse[0].hooks[0].command;

// ── fixture 素材 ────────────────────────────────────────────────────────
const g = (o) => Object.assign({ type: "command", command: CANON_CMD }, o || {});
const ent = (hooks, m) => ({ matcher: m === undefined ? CANON_MATCHER : m, hooks });
const S = (...xs) => ({ hooks: { PreToolUse: xs } });
const CANON_LIVE = S(ent([g()]));

// ── staging ─────────────────────────────────────────────────────────────
const work = fs.mkdtempSync(path.join(os.tmpdir(), "mc-cli-"));

/*
 * `layout`：
 *   "repo"      受測檔放 <case>/repo/<plat>/skills/超級模式/tests（相鄰有 snippet）
 *   "installed" 受測檔放 <case>/home/.claude/skills/超級模式/tests（相鄰**沒有** snippet）
 * `withModule: false` 用來驗 loader guard。
 */
function stage(c, dir) {
  const home = path.join(dir, "home");
  fs.mkdirSync(path.join(home, ".claude", "hooks"), { recursive: true });
  fs.copyFileSync(HOOK_SRC, path.join(home, ".claude", "hooks", "super-mode-consult-gate.js"));
  if (c.live !== undefined) {
    const p = path.join(home, ".claude", "settings.json");
    if (c.live === "<DIR>") fs.mkdirSync(p);
    else fs.writeFileSync(p, typeof c.live === "string" ? c.live : JSON.stringify(c.live, null, 2));
  }

  let base;
  if (c.layout === "installed") {
    base = path.join(home, ".claude", "skills", "超級模式");
  } else {
    base = path.join(dir, "repo", CANON_PLAT, "skills", "超級模式");
    const snip = c.snippet === undefined ? CANON_SNIPPET : c.snippet;
    const snipPath = path.join(dir, "repo", CANON_PLAT, "settings.snippet.json");
    fs.mkdirSync(path.dirname(snipPath), { recursive: true });
    fs.writeFileSync(snipPath, typeof snip === "string" ? snip : JSON.stringify(snip, null, 2));
    fs.mkdirSync(path.join(dir, "repo", CANON_PLAT, "hooks"), { recursive: true });
    fs.copyFileSync(HOOK_SRC, path.join(dir, "repo", CANON_PLAT, "hooks", "super-mode-consult-gate.js"));
  }
  fs.mkdirSync(path.join(base, "tests"), { recursive: true });
  fs.copyFileSync(target, path.join(base, "tests", "matcher-contract.test.js"));
  if (c.withModule !== false) {
    fs.mkdirSync(path.join(base, "lib"), { recursive: true });
    fs.copyFileSync(MODULE_SRC, path.join(base, "lib", "gate-registration.js"));
  }
  return { home, sut: path.join(base, "tests", "matcher-contract.test.js") };
}

function fingerprint(dir) {
  const out = [];
  const walk = (d, rel) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : 1)) {
      const p = path.join(d, e.name);
      const r = rel + "/" + e.name;
      if (e.isDirectory()) { out.push("D " + r); walk(p, r); }
      else out.push("F " + r + " " + fs.statSync(p).size);
    }
  };
  walk(dir, "");
  return out.join("\n");
}

// ── 案例 ────────────────────────────────────────────────────────────────
// want/deny 對**新版**；oldExit/oldWant/oldDeny 對舊版（反向驗證用）。
const CASES = [
  // ---- 參數（exit 2）。舊版沒有參數驗證，一律走自動判斷 → exit 0 ----------
  { id: "arg-bogus", args: ["--bogus"], exit: 2, want: ["未知參數", "RESULT_CODE=BAD_ARGS"], oldExit: 0 },
  { id: "arg-repo-and-live", args: ["--repo", "--live"], exit: 2, want: ["不能同時指定"], oldExit: 0 },
  { id: "arg-settings-alone", args: ["--settings", "x.json"], exit: 2, want: ["必須成對"], oldExit: 0 },
  { id: "arg-hook-alone", args: ["--hook", "x.js"], exit: 2, want: ["必須成對"], oldExit: 0 },
  { id: "arg-settings-with-repo", args: ["--settings", "x.json", "--hook", "y.js", "--repo"], exit: 2, want: ["不能與 --repo/--live 併用"], oldExit: 0 },
  { id: "arg-settings-no-value", args: ["--settings"], exit: 2, want: ["後面要接路徑"], oldExit: 0 },
  { id: "arg-repo-twice", args: ["--repo", "--repo"], exit: 2, want: ["不能同時指定"], oldExit: 0 },
  { id: "arg-settings-twice", args: ["--settings", "a", "--settings", "b", "--hook", "c"], exit: 2, want: ["指定了兩次"], oldExit: 0 },

  // ---- --repo ------------------------------------------------------------
  { id: "repo-canonical", args: ["--repo"], exit: 0, want: ["受驗模式：   repo", "settings.snippet.json", "PASS matcher-contract", "RESULT_CODE=OK"], oldExit: 0, oldDeny: ["受驗模式"] },
  { id: "repo-bad-type", args: ["--repo"], snippet: S(ent([{ type: "prompt", command: CANON_CMD }])), exit: 1, want: ["RESULT_CODE=BAD_TYPE", "只有 command 會執行"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "repo-matcher-missing-tool", args: ["--repo"], snippet: S(ent([g()], "Bash|mcp__.*")), exit: 1, want: ["RESULT_CODE=MATCHER_DRIFT", "matcher 命中不了 Edit"], oldExit: 1 },
  { id: "repo-matcher-extra-tool", args: ["--repo"], snippet: S(ent([g()], CANON_MATCHER + "|NoSuchTool")), exit: 1, want: ["RESULT_CODE=MATCHER_DRIFT", "matcher 多出 hook 不認識的項目 NoSuchTool"], oldExit: 1 },
  { id: "repo-snippet-broken-json", args: ["--repo"], snippet: "{ 壞掉", exit: 1, want: ["RESULT_CODE=UNREADABLE", "JSON 解析失敗"], oldExit: 1, oldDeny: ["RESULT_CODE"] },
  // 修復建議必須合語境：repo 模式講「待出貨的檔案、不要安裝」，**不能**講家目錄與 user scope。
  // 這條是重構時真的弄壞才補的（一度只留 mode 不留 kind，於是三種模式共用 live 的文案）。
  { id: "repo-no-gate-advice-is-repo-specific", args: ["--repo"], snippet: S(ent([{ type: "command", command: "node /somewhere/other-hook.js" }])), exit: 1, want: ["RESULT_CODE=NO_GATE", "待出貨的 settings.snippet.json", "不要安裝"], deny: ["settings.local.json 不是 user scope"], oldExit: 1, oldWant: ["這是待出貨的檔案"] },
  // attestation 一律印共用模組的路徑與內容摘要 —— 已安裝的 lib/ 是舊版時，
  // require() 會成功、規則卻是舊的，摘要是唯一能從輸出看出來的線索。
  { id: "prints-module-digest", args: ["--repo"], exit: 0, want: ["受驗 module:   ", "sha256="], oldExit: 0, oldDeny: ["受驗 module"] },

  // ---- --live（A1 的核心：從 checkout 也能驗 live）------------------------
  // 舊版**靜默忽略** --live 並照樣驗相鄰 snippet → 這批案子的 oldExit 幾乎都是 0，
  // 那正是「舊的 installed verifier 收到 --live 會假綠」這個發現的可執行形式。
  { id: "live-canonical", args: ["--live"], live: CANON_LIVE, exit: 0, want: ["受驗模式：   live", ".claude", "PASS matcher-contract"], deny: ["settings.snippet.json"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-missing", args: ["--live"], exit: 1, want: ["RESULT_CODE=MISSING", "找不到"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-bad-type-prompt", args: ["--live"], live: S(ent([{ type: "prompt", command: CANON_CMD }])), exit: 1, want: ["RESULT_CODE=BAD_TYPE"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-bad-type-http", args: ["--live"], live: S(ent([{ type: "http", command: CANON_CMD }])), exit: 1, want: ["RESULT_CODE=BAD_TYPE", '"http"'], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-type-missing", args: ["--live"], live: S(ent([{ command: CANON_CMD }])), exit: 1, want: ["RESULT_CODE=BAD_TYPE", "缺漏"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-unsafe-if", args: ["--live"], live: S(ent([g({ if: "Bash(git push *)" })])), exit: 1, want: ["RESULT_CODE=UNSAFE_FIELD", "其餘工具完全不受攔", "不要 append"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  // live-unsafe-once 已刪除：把 once 判成不安全是誤紅（官方明訂 settings 檔裡它被忽略）。
  // 正確行為由 live-once-must-pass 釘住。
  { id: "live-unsafe-async", args: ["--live"], live: S(ent([g({ async: true })])), exit: 1, want: ["RESULT_CODE=UNSAFE_FIELD", "來不及生效"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-unsafe-async-rewake", args: ["--live"], live: S(ent([g({ asyncRewake: true })])), exit: 1, want: ["RESULT_CODE=UNSAFE_FIELD"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-async-false-ok", args: ["--live"], live: S(ent([g({ async: false })])), exit: 0, want: ["PASS matcher-contract"], deny: ["UNSAFE_FIELD"], oldExit: 0 },
  { id: "live-benign-fields-ok", args: ["--live"], live: S(ent([g({ timeout: 30, shell: "powershell", statusMessage: "x" })])), exit: 0, want: ["PASS matcher-contract"], deny: ["UNSAFE_FIELD"], oldExit: 0 },
  { id: "live-exec-form", args: ["--live"], live: S(ent([{ type: "command", command: "node", args: ["/x/super-mode-consult-gate.js"] }])), exit: 1, want: ["RESULT_CODE=UNSUPPORTED_EXEC_FORM", "官方支援的形態"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-shape-pretooluse-string", args: ["--live"], live: { hooks: { PreToolUse: "x" } }, exit: 1, want: ["RESULT_CODE=SHAPE_ERROR", "hooks.PreToolUse 不是陣列（是 string）"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-shape-top-null", args: ["--live"], live: null, exit: 1, want: ["RESULT_CODE=SHAPE_ERROR", "頂層不是物件（是 null）"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-shape-pretooluse-object", args: ["--live"], live: { hooks: { PreToolUse: {} } }, exit: 1, want: ["RESULT_CODE=SHAPE_ERROR", "不是陣列（是 object）"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-no-gate", args: ["--live"], live: S(ent([{ type: "command", command: "node /other/hook.js" }], "Bash")), exit: 1, want: ["RESULT_CODE=NO_GATE", "裡沒有註冊本 hook"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-invalid-json", args: ["--live"], live: "{", exit: 1, want: ["RESULT_CODE=UNREADABLE", "JSON 解析失敗"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-is-directory", args: ["--live"], live: "<DIR>", exit: 1, want: ["RESULT_CODE=UNREADABLE", "讀取失敗："], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-dup-same-matcher", args: ["--live"], live: S(ent([g()]), ent([g({ command: "node /old/super-mode-consult-gate.js" })])), exit: 0, want: ["RESULT_CODE=OK_WITH_DUPLICATES", "重複註冊是 probe 的職責"], oldExit: 0 },
  { id: "live-dup-identical", args: ["--live"], live: S(ent([g(), g()])), exit: 0, want: ["RESULT_CODE=OK_WITH_DUPLICATES"], oldExit: 0 },
  { id: "live-shared-entry-ok", args: ["--live"], live: S(ent([g(), { type: "command", command: "node /other/hook.js" }])), exit: 0, want: ["PASS matcher-contract"], oldExit: 0 },

  // ---- 順序敏感（舊版短路成 PASS）----------------------------------------
  { id: "order-canonical-then-bash-matcher", args: ["--live"], live: S(ent([g()]), ent([g()], "Bash")), exit: 1, want: ["RESULT_CODE=AMBIGUOUS_MATCHER", "無法判斷該以哪一筆為準"], deny: ["matcher 缺少"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "order-good-then-bad-type", args: ["--live"], live: S(ent([g()]), ent([{ type: "prompt", command: CANON_CMD }])), exit: 1, want: ["RESULT_CODE=BAD_TYPE", "PreToolUse[1].hooks[0]"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "order-good-then-malformed-entry", args: ["--live"], live: S(ent([g()]), { matcher: "Bash", hooks: "x" }), exit: 1, want: ["RESULT_CODE=SHAPE_ERROR", "PreToolUse[1].hooks 不是陣列"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "order-bash-matcher-first", args: ["--live"], live: S(ent([g()], "Bash"), ent([g()])), exit: 1, want: ["RESULT_CODE=AMBIGUOUS_MATCHER"], deny: ["matcher 缺少"], oldExit: 0, oldWant: ["PASS matcher-contract"] },

  // ---- installed 佈局：舊版在這裡才真的會去讀 live ------------------------
  // ⚠️ 上面那批 repo 佈局的 live-* 案子，反向驗證只證明了「舊版靜默忽略 --live」——
  // 因為 repo 佈局有相鄰 snippet，舊版連 live 都不會打開。要刻畫「舊版對壞掉的 live
  // 會假綠」，必須用 installed 佈局（沒有相鄰 snippet，舊版才會落到 live）。
  // 這一組就是本次修的洞的可執行證據。
  { id: "installed-live-bad-type", args: ["--live"], layout: "installed", live: S(ent([{ type: "prompt", command: CANON_CMD }])), exit: 1, want: ["RESULT_CODE=BAD_TYPE"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "installed-live-unsafe-if", args: ["--live"], layout: "installed", live: S(ent([g({ if: "Bash(git push *)" })])), exit: 1, want: ["RESULT_CODE=UNSAFE_FIELD"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "installed-live-unsafe-async", args: ["--live"], layout: "installed", live: S(ent([g({ async: true })])), exit: 1, want: ["RESULT_CODE=UNSAFE_FIELD"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "installed-order-good-then-bad-type", args: ["--live"], layout: "installed", live: S(ent([g()]), ent([{ type: "prompt", command: CANON_CMD }])), exit: 1, want: ["RESULT_CODE=BAD_TYPE"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  // ↓ 這三個舊版**退出碼也是 1**，只有訊息抓得到差別 —— 只比總數或退出碼會完全看不見
  { id: "installed-live-exec-form", args: ["--live"], layout: "installed", live: S(ent([{ type: "command", command: "node", args: ["/x/super-mode-consult-gate.js"] }])), exit: 1, want: ["RESULT_CODE=UNSUPPORTED_EXEC_FORM", "官方支援的形態"], deny: ["裡沒有註冊本 hook"], oldExit: 1, oldWant: ["裡沒有註冊本 hook"] },
  { id: "installed-live-shape-string", args: ["--live"], layout: "installed", live: { hooks: { PreToolUse: "x" } }, exit: 1, want: ["RESULT_CODE=SHAPE_ERROR", "不是陣列（是 string）"], oldExit: 1, oldStack: true },
  { id: "installed-live-top-null", args: ["--live"], layout: "installed", live: null, exit: 1, want: ["RESULT_CODE=SHAPE_ERROR", "頂層不是物件（是 null）"], oldExit: 1, oldStack: true },
  { id: "installed-order-bash-first", args: ["--live"], layout: "installed", live: S(ent([g()], "Bash"), ent([g()])), exit: 1, want: ["RESULT_CODE=AMBIGUOUS_MATCHER"], deny: ["matcher 缺少"], oldExit: 1, oldWant: ["matcher 缺少 Edit"] },

  // ---- explicit pair ----------------------------------------------------
  { id: "explicit-pair-ok", args: ["--settings", "@LIVE", "--hook", "@HOOK"], live: CANON_LIVE, exit: 0, want: ["受驗模式：   explicit", "PASS matcher-contract"], oldExit: 0 },
  // 早退也必須先印**兩條**路徑
  { id: "explicit-both-missing-still-prints-both", args: ["--settings", "@NOPE_S", "--hook", "@NOPE_H"], exit: 1, want: ["受驗 settings: ", "受驗 hook:     ", "nope-settings.json", "nope-hook.js", "RESULT_CODE=HOOK_UNREADABLE"], oldExit: 0 },

  // ---- 無旗標＝淘汰第一階段 ---------------------------------------------
  { id: "noflag-repo-layout", args: [], exit: 0, want: ["deprecated", "相鄰 snippet", "PASS matcher-contract"], oldExit: 0, oldDeny: ["deprecated"] },
  { id: "noflag-installed-layout-uses-live", args: [], layout: "installed", live: CANON_LIVE, exit: 0, want: ["deprecated", "→ live", ".claude", "PASS matcher-contract"], oldExit: 0 },
  // 嚴格化在無旗標路徑同樣生效：這就是「行為與退出碼完全不變」不實的地方
  { id: "noflag-installed-bad-type-now-fails", args: [], layout: "installed", live: S(ent([{ type: "prompt", command: CANON_CMD }])), exit: 1, want: ["RESULT_CODE=BAD_TYPE"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "noflag-installed-unsafe-now-fails", args: [], layout: "installed", live: S(ent([g({ async: true })])), exit: 1, want: ["RESULT_CODE=UNSAFE_FIELD"], oldExit: 0, oldWant: ["PASS matcher-contract"] },

  // ---- installed 佈局不准偷偷回頭讀 repo --------------------------------
  // installed 佈局下相鄰 snippet 是 ~/.claude/settings.snippet.json（不存在），
  // 所以 --repo 必須失敗。若它「成功」了，代表它從真的 repo 撿了一份 —— 那就是假綠。
  { id: "installed-repo-mode-must-not-reach-back", args: ["--repo"], layout: "installed", live: CANON_LIVE, exit: 1, want: ["RESULT_CODE=MISSING"], deny: ["PASS matcher-contract"], oldExit: 0, oldWant: ["PASS matcher-contract"] },

  // ---- disableAllHooks：JSON 合法、gate 註冊完美，但所有 hook 都被關掉 --------
  // 合併前審查抓到的最乾淨假綠：修正前**兩支工具都印「正常／PASS」**。
  { id: "live-kill-switch", args: ["--live"], layout: "installed", live: Object.assign({ disableAllHooks: true }, S(ent([g()]))), exit: 1, want: ["RESULT_CODE=HOOKS_DISABLED", "所有 hook 都被停用", "Disable all hooks"], deny: ["PASS matcher-contract"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "repo-kill-switch", args: ["--repo"], snippet: Object.assign({ disableAllHooks: true }, S(ent([g()]))), exit: 1, want: ["RESULT_CODE=HOOKS_DISABLED", "待出貨的檔案"], deny: ["重跑本測試 --live"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-kill-switch-false-ok", args: ["--live"], layout: "installed", live: Object.assign({ disableAllHooks: false }, S(ent([g()]))), exit: 0, want: ["PASS matcher-contract"], deny: ["HOOKS_DISABLED"], oldExit: 0 },

  // ---- once：官方明訂 settings 檔裡會被忽略，擋它是誤紅 ----------------------
  // 我一度把它列為不安全並讓兩支工具 exit 1，那會無故弄壞既有使用者的安裝驗收。
  { id: "live-once-must-pass", args: ["--live"], layout: "installed", live: S(ent([g({ once: true })])), exit: 0, want: ["PASS matcher-contract"], deny: ["UNSAFE_FIELD"], oldExit: 0 },

  // ---- matcher 的 runtime 語義（regex vs 精確清單）--------------------------
  // canonical matcher 含 `mcp__.*` 的 `.`，所以 runtime 把**整串**當 regex。
  // 把 `|` 兩側加空白 → 每個 alternative 都帶字面空白 → 一個工具都命中不了、gate 從不執行。
  // 修正前一律 split("|").trim() 當精確清單比，這種寫法會**照樣 PASS**。
  { id: "matcher-spaces-around-pipe-is-regex-trap", args: ["--repo"], snippet: S(ent([g()], CANON_MATCHER.split("|").join(" | "))), exit: 1, want: ["RESULT_CODE=MATCHER_DRIFT", "正規表達式", "字面內容", "命中不了 Edit"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "matcher-pass-prints-runtime-interpretation", args: ["--repo"], exit: 0, want: ["PASS matcher-contract", "matcher 依 runtime 規則解讀為正規表達式"], oldExit: 0, oldDeny: ["runtime 規則解讀"] },

  // ---- shell ＋ exec 混用時 matcher 集合要算全部 candidate --------------------
  { id: "mixed-shell-exec-diff-matcher", args: ["--live"], layout: "installed", live: S(ent([g()]), ent([{ type: "command", command: "node", args: ["/x/super-mode-consult-gate.js"] }], "Bash")), exit: 1, want: ["RESULT_CODE=AMBIGUOUS_MATCHER", "shell 1", "exec 1"], deny: ["PASS matcher-contract"], oldExit: 0, oldWant: ["PASS matcher-contract"] },

  // ---- 合併前審查第二輪：CONFIG_DIR、timeout、anchored regex、attestation 順序 ----
  // CLAUDE_CONFIG_DIR 只影響「目標是 live」的模式；--repo 的路徑不是從設定目錄解出來的。
  { id: "config-dir-override-live-refused", args: ["--live"], layout: "installed", live: CANON_LIVE, env: { CLAUDE_CONFIG_DIR: "D:/alt-claude" }, exit: 1, want: ["受驗 settings: ", "RESULT_CODE=CONFIG_DIR_OVERRIDE", "覆寫整個設定目錄", "unset"], deny: ["PASS matcher-contract"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "config-dir-override-repo-unaffected", args: ["--repo"], env: { CLAUDE_CONFIG_DIR: "D:/alt-claude" }, exit: 0, want: ["PASS matcher-contract"], deny: ["CONFIG_DIR_OVERRIDE"], oldExit: 0 },
  { id: "config-dir-empty-is-not-set", args: ["--live"], layout: "installed", live: CANON_LIVE, env: { CLAUDE_CONFIG_DIR: "  " }, exit: 0, want: ["PASS matcher-contract"], deny: ["CONFIG_DIR_OVERRIDE"], oldExit: 0 },
  // timeout <= 0：官方 schema exclusiveMinimum: 0 → 整份 settings 被拒
  { id: "live-timeout-zero", args: ["--live"], layout: "installed", live: S(ent([g({ timeout: 0 })])), exit: 1, want: ["RESULT_CODE=SHAPE_ERROR", "必須是 > 0 的數字"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "live-timeout-positive-ok", args: ["--live"], layout: "installed", live: S(ent([g({ timeout: 0.001 })])), exit: 0, want: ["PASS matcher-contract"], oldExit: 0 },
  // 語義等價的 anchored regex 不得誤紅
  { id: "matcher-anchored-regex-not-drift", args: ["--repo"], snippet: S(ent([g()], "^(?:" + CANON_MATCHER.split("|").join("|") + ")$")), exit: 0, want: ["PASS matcher-contract", "UNVERIFIABLE_REGEX", "只驗了正向涵蓋"], deny: ["RESULT_CODE=MATCHER_DRIFT"], oldExit: 1 },
  // MATCHER_DRIFT 的修法不得導向 probe
  { id: "matcher-drift-fix-does-not-send-to-probe", args: ["--repo"], snippet: S(ent([g()], "Bash|mcp__.*")), exit: 1, want: ["RESULT_CODE=MATCHER_DRIFT", "settings.snippet.json"], deny: ["~/.claude/settings.json"], oldExit: 1 },

  // ---- loader guard（含正向對照）----------------------------------------
  // ⚠️ 模組缺失時**仍必須印出 attestation 的四行** —— 「一律先印實際受驗目標」這個承諾
  // 不能因為早退就跳過（合併前審查抓到的次級違約）。
  { id: "integrity-no-module", args: ["--repo"], withModule: false, exit: 1, want: ["受驗模式：", "受驗 settings: ", "受驗 hook:     ", "受驗 module:   ", "TOOL_INTEGRITY_ERROR", "沒有做任何比對", "重裝 skill"], deny: ["PASS matcher-contract"], oldExit: 0, oldWant: ["PASS matcher-contract"] },
  { id: "integrity-with-module-control", args: ["--repo"], exit: 0, want: ["PASS matcher-contract"], deny: ["TOOL_INTEGRITY_ERROR"], oldExit: 0 },
];

// ── 執行 ────────────────────────────────────────────────────────────────
let pass = 0;
const failed = [];
const STACK_RE = /\n\s+at\s+\S/; // uncaught exception 的特徵

for (const c of CASES) {
  const dir = path.join(work, c.id);
  fs.mkdirSync(dir, { recursive: true });
  const st = stage(c, dir);
  const before = fingerprint(dir);

  const args = (c.args || []).map((a) =>
    a === "@LIVE" ? path.join(st.home, ".claude", "settings.json")
      : a === "@HOOK" ? path.join(st.home, ".claude", "hooks", "super-mode-consult-gate.js")
        : a === "@NOPE_S" ? path.join(dir, "nope-settings.json")
          : a === "@NOPE_H" ? path.join(dir, "nope-hook.js")
            : a);

  // 每案可指定額外環境變數（CLAUDE_CONFIG_DIR 等）。基準環境刻意把它清空，
  // 否則驗證者自己設了這個變數時，整套 --live 案子會全部變成 CONFIG_DIR_OVERRIDE。
  const env = Object.assign({}, process.env, { HOME: st.home, USERPROFILE: st.home, CLAUDE_CONFIG_DIR: "" }, c.env || {});
  const r = spawnSync(process.execPath, [st.sut].concat(args), { encoding: "utf8", env });
  const out = (r.stdout || "") + (r.stderr || "");
  const problems = [];

  const wantExit = reverse ? c.oldExit : c.exit;
  const wantStrings = reverse ? (c.oldWant || []) : (c.want || []);
  const denyStrings = reverse ? (c.oldDeny || []) : (c.deny || []);
  if (wantExit === undefined) problems.push("案例沒宣告 " + (reverse ? "oldExit" : "exit"));
  else if (r.status !== wantExit) problems.push("退出碼 " + r.status + "（預期 " + wantExit + "）");
  for (const w of wantStrings) if (!out.includes(w)) problems.push("缺少字串「" + w + "」");
  for (const d of denyStrings) if (out.includes(d)) problems.push("不該出現字串「" + d + "」");
  // 新版任何路徑都不該噴 stack trace（修正前對形狀不合就是這樣）。
  // 反向驗證時，宣告 oldStack 的案子必須**真的**看到 stack trace —— 那是「同一個退出碼、
  // 只有訊息品質不同」的正面證據，不是靠退出碼推斷出來的。
  if (!reverse && STACK_RE.test(out)) problems.push("輸出含 stack trace");
  if (reverse && c.oldStack && !STACK_RE.test(out)) problems.push("預期舊版噴 stack trace，但沒有");
  // 受測檔是唯讀的：fixture 樹執行前後不得改變
  if (fingerprint(dir) !== before) problems.push("fixture 樹被改動了（本測試應為唯讀）");

  if (problems.length) {
    failed.push(c.id);
    console.log("FAIL: " + c.id + " — " + problems.join("；"));
  } else pass++;
}

fs.rmSync(work, { recursive: true, force: true });

console.log("");
console.log("TOTAL " + CASES.length + "  PASS " + pass + "  FAIL " + failed.length);
if (failed.length) {
  console.log("失敗的案子：" + failed.join(", "));
  // process.exitCode ＋自然結束：process.exit() 會截斷上面這段最需要被看到的清單
  process.exitCode = 1;
}
