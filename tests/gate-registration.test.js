#!/usr/bin/env node
/*
 * `<platform>/skills/超級模式/lib/gate-registration.js` 的回歸案。
 *
 * 用法：
 *   node tests/gate-registration.test.js
 *   node tests/gate-registration.test.js --strict   # SKIP 也算失敗（CI 用）
 *
 * 三平台共用（純 Node，不依賴 shell、不碰檔案系統、不需要假 HOME）——
 * 這是把 I/O 推到 caller 的直接好處：`SettingsSource` 是 tagged union，
 * 連「settings.json 是個目錄（EISDIR）」都能當成一筆純資料 fixture 餵進去。
 *
 * 三段：
 *   §A 模組單元案 —— assessProbe / assessMatcher 的 code、exit、render 出來的字串
 *   §B 成對契約案 —— 同一份 fixture，probe 停手但 matcher 照樣驗（刻意的規則差異）
 *   §C 鏡像同一性 —— 宣告哪些 payload 檔必須三平台逐位元相同，以及**為什麼**
 *
 * ⚠️ 斷言刻意不只看 code。2026-08-08 的教訓：只核對總數或退出碼時，
 * 無從得知失敗的是不是「該失敗的那幾條」——修正前的 matcher-contract 對
 * 「頂層 null」「PreToolUse 是物件」都是 exit 1，只有字串斷言抓得到差別。
 */
"use strict";

const fs = require("fs");
const path = require("path");

// ── 參數 ────────────────────────────────────────────────────────────────
let strict = false;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--strict") strict = true;
  else {
    console.error("未知參數：" + process.argv[i]);
    process.exitCode = 2;
    return;
  }
}

// ── 鏡像清單（§C 的宣告，同時決定 §A 用哪一份跑）────────────────────────
const PLATFORMS = ["windows", "macos", "linux"];
const MIRRORED = [
  {
    rel: "skills/超級模式/lib/gate-registration.js",
    why: "gate 辨識的單一邏輯版本。三份是配送鏡像：probe 從 repo 根讀並比對 bytes，" +
      "matcher-contract 安裝到 live 之後從相鄰的 lib/ 讀。",
  },
  {
    rel: "skills/超級模式/tests/matcher-contract.test.js",
    why: "同一支測試在三平台 payload 各一份；安裝時只有對應平台那一份會進 live。",
  },
];
// ⚠️ **刻意不鎖** `skills/超級模式/tests/run-gate-tests.js` 與
// `skills/超級模式/references/review-output.schema.json`：它們今天剛好三平台同 blob，
// 但那是巧合，不是宣告過的契約。byte invariant 要有明確理由才鎖，
// 否則日後某平台合理地分歧時，這支測試會變成阻礙而不是保護。

const modPath = (plat) =>
  path.join(__dirname, "..", plat, "skills", "超級模式", "lib", "gate-registration.js");
const G = require(modPath(PLATFORMS[0]));

// ── 測試框架 ────────────────────────────────────────────────────────────
let pass = 0, fail = 0, skip = 0;
const failures = [];

function check(name, cond, detail) {
  if (cond) { pass++; return true; }
  fail++;
  failures.push(name);
  console.log("  FAIL  " + name);
  if (detail) console.log("        " + String(detail).split("\n").join("\n        "));
  return false;
}
function skipCase(name, why) {
  skip++;
  console.log("  SKIP  " + name + "（" + why + "）");
}

// 一個案子：斷言 code、exit，以及 render 出來的必含／禁含字串。
function expect(name, got, want) {
  const bad = [];
  if (got.code !== want.code) bad.push("code=" + got.code + "，期望 " + want.code);
  if (got.exit !== want.exit) bad.push("exit=" + got.exit + "，期望 " + want.exit);
  for (const s of want.has || []) if (!got.text.includes(s)) bad.push("缺少字串：" + s);
  for (const s of want.hasnt || []) if (got.text.includes(s)) bad.push("不該出現字串：" + s);
  check(name, bad.length === 0, bad.length ? bad.join("\n") + "\n---- 實際輸出 ----\n" + got.text : "");
}

// ── fixture 素材 ────────────────────────────────────────────────────────
const MATCHER = "Write|Edit|NotebookEdit|Bash|PowerShell|Monitor|mcp__.*";
const CMD = "node /home/u/.claude/hooks/super-mode-consult-gate.js";
const CMD_STALE = "node /old/path/super-mode-consult-gate.js";
const L_MAIN = "~/.claude/settings.json";
const L_LOCAL = "~/.claude/settings.local.json";

const gate = (over) => Object.assign({ type: "command", command: CMD }, over || {});
const gateExec = (p) => ({ type: "command", command: "node", args: [p || "/x/super-mode-consult-gate.js"] });
const entry = (hooks, m) => ({ matcher: m === undefined ? MATCHER : m, hooks });
const settings = (...entries) => ({ hooks: { PreToolUse: entries } });

// SettingsSource 便利建構
const raw = (label, obj) => G.sourceRaw(label, "/fake/" + label, typeof obj === "string" ? obj : JSON.stringify(obj));
const missing = (label) => G.sourceMissing(label, "/fake/" + label);
const readErr = (label, code) => G.sourceReadError(label, "/fake/" + label, code);

const probe = (main, local) => {
  const v = G.assessProbe({ main: main || missing(L_MAIN), local: local || missing(L_LOCAL) });
  return { code: v.code, exit: v.exit, text: G.renderProbe(v), v };
};
const matcher = (src) => {
  const v = G.assessMatcher({ settings: src });
  const ctx = { mode: "repo", settingsPath: src.path, hookPath: "/fake/hook.js" };
  return {
    code: v.code, exit: v.exit,
    text: G.matcherAttestation(ctx).join("\n") + "\n" + G.renderMatcher(v, ctx),
    v,
  };
};

// ════════════════════════════════════════════════════════════════════════
console.log("\n§A assessProbe");
// ════════════════════════════════════════════════════════════════════════

expect("A01 正常一筆", probe(raw(L_MAIN, settings(entry([gate()])))), {
  code: "OK_NORMAL", exit: 0,
  has: ["gate 條目：1 個", "檔案不存在", "判定：正常，不用修。", "已註冊的 gate handler：", "RESULT_CODE=OK_NORMAL"],
});

// 每一條退出路徑都要印範圍。這條（0 筆 → AI-INSTALL 會叫人新增）最需要看到
// 「needle 大小寫敏感」的警告，修正前卻是唯一看不到的。
expect("A02 兩邊都沒有", probe(), {
  code: "OK_NONE", exit: 0,
  has: ["檔案不存在", "兩邊都沒有 gate", "大小寫敏感"],
  hasnt: ["已註冊的 gate handler："],
});

expect("A03 main 兩筆相同", probe(raw(L_MAIN, settings(entry([gate()]), entry([gate()])))), {
  code: "OK_DUPLICATE_MAIN", exit: 0,
  has: ["有 2 筆 gate", "已經重複註冊", "『B. 已經有一筆』"],
  hasnt: ["判定：停手"],
});

expect("A04 兩邊都有", probe(raw(L_MAIN, settings(entry([gate()]))), raw(L_LOCAL, settings(entry([gate()])))), {
  code: "OK_BOTH", exit: 0, has: ["兩邊都有", "『B. 已經有一筆』"],
});

expect("A05 只在 local", probe(raw(L_MAIN, { hooks: { PreToolUse: [] } }), raw(L_LOCAL, settings(entry([gate()])))), {
  code: "OK_LOCAL_ONLY", exit: 0, has: ["受影響", "『A. 還沒有』"],
});

expect("A06 沒有 hooks 段", probe(raw(L_MAIN, { permissions: {} })), {
  code: "OK_NONE", exit: 0, has: ["沒有 hooks 段 —— gate 條目：0 個"],
});

expect("A07 沒有 PreToolUse", probe(raw(L_MAIN, { hooks: { PostToolUse: [] } })), {
  code: "OK_NONE", exit: 0, has: ["沒有 hooks.PreToolUse —— gate 條目：0 個"],
});

// ↓ 修正前的假陰性：字串會被逐字元迭代、靜默數成 0，於是判定成「重做安裝」
expect("A08 PreToolUse 是字串（fail-closed）", probe(raw(L_MAIN, { hooks: { PreToolUse: CMD } })), {
  code: "SHAPE_ERROR", exit: 1,
  has: ["hooks.PreToolUse 不是陣列（是 string）", "無法解析或形狀不合", "大小寫敏感"],
  hasnt: ["兩邊都沒有 gate"],
});

expect("A09 PreToolUse 是物件", probe(raw(L_MAIN, { hooks: { PreToolUse: {} } })), {
  code: "SHAPE_ERROR", exit: 1, has: ["hooks.PreToolUse 不是陣列（是 object）"],
});

expect("A10 頂層 null", probe(raw(L_MAIN, null)), {
  code: "SHAPE_ERROR", exit: 1, has: ["頂層不是物件（是 null）"],
});

expect("A11 頂層陣列", probe(raw(L_MAIN, [])), {
  code: "SHAPE_ERROR", exit: 1, has: ["頂層不是物件（是 陣列）"],
});

expect("A12 hooks 是字串", probe(raw(L_MAIN, { hooks: "x" })), {
  code: "SHAPE_ERROR", exit: 1, has: ["hooks 不是物件（是 string）"],
});

expect("A13 壞 JSON", probe(raw(L_MAIN, "{ 這不是 JSON")), {
  code: "SHAPE_ERROR", exit: 1, has: ["JSON 解析失敗", "無法解析或形狀不合"],
});

expect("A14 讀取失敗 EISDIR", probe(readErr(L_MAIN, "EISDIR")), {
  code: "SHAPE_ERROR", exit: 1, has: ["讀取失敗：EISDIR", "無法解析或形狀不合"],
});

expect("A15 entry 非物件", probe(raw(L_MAIN, settings("x"))), {
  code: "SHAPE_ERROR", exit: 1, has: ["PreToolUse[0] 不是物件（是 string）"],
});

expect("A16 entry.hooks 非陣列", probe(raw(L_MAIN, settings({ matcher: MATCHER, hooks: "x" }))), {
  code: "SHAPE_ERROR", exit: 1, has: ["PreToolUse[0].hooks 不是陣列（是 string）"],
});

expect("A17 handler 非物件", probe(raw(L_MAIN, settings(entry(["x"])))), {
  code: "SHAPE_ERROR", exit: 1, has: ["PreToolUse[0].hooks[0] 不是物件（是 string）"],
});

expect("A18 command 非字串", probe(raw(L_MAIN, settings(entry([{ type: "command", command: [CMD] }])))), {
  code: "SHAPE_ERROR", exit: 1, has: ["PreToolUse[0].hooks[0].command 不是字串（是 陣列）"],
});

expect("A19 args 非陣列", probe(raw(L_MAIN, settings(entry([{ type: "command", command: "node", args: "/x/super-mode-consult-gate.js" }])))), {
  code: "SHAPE_ERROR", exit: 1, has: ["PreToolUse[0].hooks[0].args 不是陣列（是 string）"],
});

expect("A20 args 元素非字串", probe(raw(L_MAIN, settings(entry([{ type: "command", command: "node", args: [7, "/x/super-mode-consult-gate.js"] }])))), {
  code: "SHAPE_ERROR", exit: 1, has: ["PreToolUse[0].hooks[0].args[0] 不是字串（是 number）"],
});

expect("A21 matcher 非字串", probe(raw(L_MAIN, settings(entry([gate()], 5)))), {
  code: "SHAPE_ERROR", exit: 1, has: ["PreToolUse[0].matcher 不是字串（是 number）"],
});

expect("A22 type 缺漏", probe(raw(L_MAIN, settings(entry([{ command: CMD }])))), {
  code: "SHAPE_ERROR", exit: 1,
  has: ["command 含 gate，但 type 是 缺漏"], hasnt: ["正常，不用修"],
});

expect("A23 type 是 prompt", probe(raw(L_MAIN, settings(entry([{ type: "prompt", command: CMD }])))), {
  code: "SHAPE_ERROR", exit: 1,
  has: ['command 含 gate，但 type 是 "prompt"'], hasnt: ["正常，不用修"],
});

// type 的其餘三種合法值同樣不會執行 command
for (const t of ["http", "mcp_tool", "agent"]) {
  expect("A23-" + t + " type 是 " + t, probe(raw(L_MAIN, settings(entry([{ type: t, command: CMD }])))), {
    code: "SHAPE_ERROR", exit: 1,
    has: ['command 含 gate，但 type 是 "' + t + '"'], hasnt: ["正常，不用修"],
  });
}

// 混合案：第一筆合法、第二筆 type 壞掉 —— existential 寫法會在這裡假綠
expect("A24 好 gate 在前、壞 type 在後", probe(raw(L_MAIN, settings(entry([gate()]), entry([{ type: "prompt", command: CMD }])))), {
  code: "SHAPE_ERROR", exit: 1,
  has: ["PreToolUse[1].hooks[0] 的 command 含 gate"], hasnt: ["正常，不用修"],
});

expect("A25 local 壞掉、main 正常（兩個檔都驗）", probe(raw(L_MAIN, settings(entry([gate()]))), raw(L_LOCAL, "{")), {
  code: "SHAPE_ERROR", exit: 1, has: ["JSON 解析失敗"], hasnt: ["正常，不用修"],
});

// ── 停手 ───────────────────────────────────────────────────────────────
expect("A26 exec form", probe(raw(L_MAIN, settings(entry([gateExec()])))), {
  code: "HALT_EXEC_FORM", exit: 3,
  has: ["exec form", "判定：停手", "大小寫敏感"],
  hasnt: ["正常，不用修", "兩邊都沒有 gate"],
});

// needle 出現在 args 但根本不是在跑 gate —— 只看 command 的寫法會判「沒有 gate」
expect("A27 echo + args needle", probe(raw(L_MAIN, settings(entry([{ type: "command", command: "echo", args: ["super-mode-consult-gate"] }])))), {
  code: "HALT_EXEC_FORM", exit: 3, has: ["exec form", "判定：停手"], hasnt: ["正常，不用修"],
});

expect("A28 只有 args 沒有 command", probe(raw(L_MAIN, settings(entry([{ type: "command", args: ["/x/super-mode-consult-gate.js"] }])))), {
  code: "HALT_EXEC_FORM", exit: 3, has: ["exec form", "判定：停手"],
});

expect("A29 exec + type prompt（形狀優先）", probe(raw(L_MAIN, settings(entry([{ type: "prompt", command: "node", args: ["/x/super-mode-consult-gate.js"] }])))), {
  code: "SHAPE_ERROR", exit: 1, has: ['type 是 "prompt"'], hasnt: ["正常，不用修"],
});

expect("A30 共用 entry", probe(raw(L_MAIN, settings(entry([gate(), { type: "command", command: "node /other/hook.js" }])))), {
  code: "HALT_SHARED_ENTRY", exit: 3,
  has: ["還有 1 個非 gate 的 handler", "判定：停手", "大小寫敏感"],
});

expect("A31 兩筆 command 不同", probe(raw(L_MAIN, settings(entry([gate()]), entry([gate({ command: CMD_STALE })])))), {
  code: "HALT_INCONSISTENT", exit: 3, has: ["matcher／command 不一致", "判定：停手"],
});

expect("A32 兩筆 matcher 不同", probe(raw(L_MAIN, settings(entry([gate()]), entry([gate()], "Bash")))), {
  code: "HALT_INCONSISTENT", exit: 3, has: ["matcher／command 不一致", "判定：停手"],
});

// main 一筆 stale ＋ local 一筆正確：只比 settings.json 會判成純減法，
// 使用者刪光 local 只留下壞的那筆，重跑還會得到「正常」
expect("A33 main stale + local good（必須比聯集）", probe(raw(L_MAIN, settings(entry([gate({ command: CMD_STALE })]))), raw(L_LOCAL, settings(entry([gate()])))), {
  code: "HALT_INCONSISTENT", exit: 3, has: ["判定：停手"], hasnt: ["『B. 已經有一筆』"],
});

// 同一個 entry 裡兩筆**相同**的 gate handler：siblings=0，該判重複註冊不是停手
expect("A34 同 entry 兩筆相同", probe(raw(L_MAIN, settings(entry([gate(), gate()])))), {
  code: "OK_DUPLICATE_MAIN", exit: 0, has: ["有 2 筆 gate", "已經重複註冊"], hasnt: ["判定：停手"],
});

// ── 不安全欄位（本批新增，修正前兩支工具都放行）──────────────────────────
expect("A35 if 限縮", probe(raw(L_MAIN, settings(entry([gate({ if: "Bash(git push *)" })])))), {
  code: "UNSAFE_FIELD", exit: 1,
  has: ["帶 if=", "判定：設定不安全", "其餘工具完全不受攔", "不要 append"],
  hasnt: ["判定：正常，不用修。"],
});

expect("A36 once", probe(raw(L_MAIN, settings(entry([gate({ once: true })])))), {
  code: "UNSAFE_FIELD", exit: 1, has: ["帶 once=true", "整個 session 不設防"],
});

expect("A37 async", probe(raw(L_MAIN, settings(entry([gate({ async: true })])))), {
  code: "UNSAFE_FIELD", exit: 1, has: ["帶 async=true", "deny 來不及生效"],
});

expect("A38 asyncRewake", probe(raw(L_MAIN, settings(entry([gate({ asyncRewake: true })])))), {
  code: "UNSAFE_FIELD", exit: 1, has: ["帶 asyncRewake=true"],
});

// 明確關閉不算不安全 —— 否則會無故弄壞把欄位寫成 false 的使用者
expect("A39 async:false 放行", probe(raw(L_MAIN, settings(entry([gate({ async: false, once: false })])))), {
  code: "OK_NORMAL", exit: 0, has: ["判定：正常，不用修。"], hasnt: ["設定不安全"],
});

// 良性欄位一律放行（不影響 gate 能否阻擋）
expect("A40 timeout/shell/statusMessage 放行", probe(raw(L_MAIN, settings(entry([gate({ timeout: 30, shell: "bash", statusMessage: "x" })])))), {
  code: "OK_NORMAL", exit: 0, has: ["判定：正常，不用修。"], hasnt: ["設定不安全"],
});

// precedence：不安全欄位排在 exec form 之前（「確定壞了＋有修法」比「請找人」有用）
expect("A41 exec + async → 不安全優先", probe(raw(L_MAIN, settings(entry([{ type: "command", command: "node", args: ["/x/super-mode-consult-gate.js"], async: true }])))), {
  code: "UNSAFE_FIELD", exit: 1, has: ["判定：設定不安全"], hasnt: ["判定：停手"],
});

// precedence：形狀不合排在不安全之前
expect("A42 bad type + async → 形狀優先", probe(raw(L_MAIN, settings(entry([{ type: "prompt", command: CMD, async: true }])))), {
  code: "SHAPE_ERROR", exit: 1, has: ['type 是 "prompt"'], hasnt: ["判定：設定不安全"],
});

expect("A43 local 帶不安全欄位也要抓到", probe(raw(L_MAIN, { hooks: { PreToolUse: [] } }), raw(L_LOCAL, settings(entry([gate({ once: true })])))), {
  code: "UNSAFE_FIELD", exit: 1, has: [L_LOCAL, "帶 once=true"],
});

// ── open-world：不相干的畸形／未知欄位一律放行 ──────────────────────────
// 這幾條釘住「本工具**不**驗什麼」。文案與行為必須被同一組斷言綁住 ——
// 這句話先前寫錯過兩次（先寫成「無關的畸形會被略過」，與實作相反；再寫成「唯二例外」，漏了一類）。
expect("A44 非 gate handler 的 type 不驗", probe(raw(L_MAIN, settings({ matcher: "Bash", hooks: [{ type: 7, command: "node /other/hook.js" }] }))), {
  code: "OK_NONE", exit: 0,
  has: ["gate 條目：0 個", "兩邊都沒有 gate", "非 gate 的 handler 不驗 type 的型別"],
});

expect("A45 type:command 沒帶 command 不驗", probe(raw(L_MAIN, settings({ matcher: "Bash", hooks: [{ type: "command" }] }))), {
  code: "OK_NONE", exit: 0, has: ["gate 條目：0 個"],
});

expect("A46 沒有 hooks 鍵的 entry 略過", probe(raw(L_MAIN, settings({ matcher: "Bash" }, entry([gate()])))), {
  code: "OK_NORMAL", exit: 0, has: ["gate 條目：1 個", "判定：正常，不用修。"],
});

expect("A47 不相干的 exec-form handler 不算", probe(raw(L_MAIN, settings({ matcher: "Bash", hooks: [{ type: "command", command: "node", args: ["/other/hook.js"] }] }))), {
  code: "OK_NONE", exit: 0, has: ["gate 條目：0 個", "兩邊都沒有 gate"],
});

// snippet 帶頂層 _comment；closed-world schema 會讓三份 snippet 一起誤紅
expect("A48 未知頂層欄位（_comment）放行", probe(raw(L_MAIN, Object.assign({ _comment: "說明" }, settings(entry([gate()]))))), {
  code: "OK_NORMAL", exit: 0, has: ["判定：正常，不用修。"],
});

expect("A49 未知 handler 欄位放行", probe(raw(L_MAIN, settings(entry([gate({ someFutureField: 1 })])))), {
  code: "OK_NORMAL", exit: 0, has: ["判定：正常，不用修。"],
});

expect("A50 BOM", probe(G.sourceRaw(L_MAIN, "/fake/m", "﻿" + JSON.stringify(settings(entry([gate()]))))), {
  code: "OK_NORMAL", exit: 0, has: ["判定：正常，不用修。"],
});

// shortLabel：盤點行用長名、handler 清單用短名。probe 的輸出要與修正前逐位元相同，
// 就靠這一個欄位；缺省時退回 label。
expect("A52 shortLabel 用在 handler 清單、label 用在盤點行",
  probe(G.sourceRaw(L_MAIN, "/fake/m", JSON.stringify(settings(entry([gate()]))), "settings.json")), {
    code: "OK_NORMAL", exit: 0,
    has: [L_MAIN.padEnd(32) + "gate 條目：1 個", "  settings.json PreToolUse[0].hooks[0]  command="],
    hasnt: ["  " + L_MAIN + " PreToolUse[0]"],
  });

expect("A53 沒給 shortLabel 就退回 label", probe(raw(L_MAIN, settings(entry([gate()])))), {
  code: "OK_NORMAL", exit: 0, has: ["  " + L_MAIN + " PreToolUse[0].hooks[0]  command="],
});

// 已知假陽性：substring 命中但根本不執行 gate。**刻意**判成正常 ——
// 排除它需要剖析 shell token，本模組不做。範圍說明必須明講這件事。
expect("A51 echo needle（已知假陽性，範圍說明要提到）", probe(raw(L_MAIN, settings(entry([{ type: "command", command: "echo super-mode-consult-gate" }])))), {
  code: "OK_NORMAL", exit: 0,
  has: ["判定：正常，不用修。", "只代表「candidate」", "echo super-mode-consult-gate"],
});

// ════════════════════════════════════════════════════════════════════════
console.log("\n§A assessMatcher");
// ════════════════════════════════════════════════════════════════════════

expect("A60 正常一筆", matcher(raw("snippet", settings(entry([gate()])))), {
  code: "OK", exit: 0, has: ["受驗模式：", "受驗 settings: ", "受驗 hook:     "],
});

expect("A61 檔案不存在", matcher(missing("live")), {
  code: "MISSING", exit: 1, has: ["找不到 /fake/live"],
});

expect("A62 壞 JSON", matcher(raw("live", "{")), {
  code: "UNREADABLE", exit: 1, has: ["JSON 解析失敗"],
});

expect("A63 讀取失敗", matcher(readErr("live", "EACCES")), {
  code: "UNREADABLE", exit: 1, has: ["讀取失敗：EACCES"],
});

expect("A64 形狀不合（訊息與 probe 同一份句子）", matcher(raw("live", { hooks: { PreToolUse: CMD } })), {
  code: "SHAPE_ERROR", exit: 1, has: ["形狀不合：hooks.PreToolUse 不是陣列（是 string）"],
});

// ↓ 修正前 exit 0 假綠；也是先前設計裡「不可達」的那個 code
expect("A65 type 是 prompt → BAD_TYPE", matcher(raw("live", settings(entry([{ type: "prompt", command: CMD }])))), {
  code: "BAD_TYPE", exit: 1,
  has: ['type 是 "prompt"', "command／http／mcp_tool／prompt／agent", "只有 command 會執行", "不要 append"],
});

expect("A66 type 缺漏 → BAD_TYPE", matcher(raw("live", settings(entry([{ command: CMD }])))), {
  code: "BAD_TYPE", exit: 1, has: ["type 是 缺漏"],
});

expect("A67 if → UNSAFE_FIELD", matcher(raw("live", settings(entry([gate({ if: "Bash(git *)" })])))), {
  code: "UNSAFE_FIELD", exit: 1, has: ["if=", "其餘工具完全不受攔", "不要 append"],
});

expect("A68 async → UNSAFE_FIELD", matcher(raw("live", settings(entry([gate({ async: true })])))), {
  code: "UNSAFE_FIELD", exit: 1, has: ["async=true"],
});

// exec form 是官方支援的形態，措辭不能寫成「無效註冊」
expect("A69 exec form", matcher(raw("live", settings(entry([gateExec()])))), {
  code: "UNSUPPORTED_EXEC_FORM", exit: 1,
  has: ["exec form", "官方支援的形態", "**不是**無效註冊", "probe-gate-registration.js"],
});

expect("A70 沒有 gate", matcher(raw("live", settings({ matcher: "Bash", hooks: [{ type: "command", command: "node /other.js" }] }))), {
  code: "NO_GATE", exit: 1, has: ["裡沒有註冊本 hook", "settings.local.json 不是 user scope"],
});

expect("A71 兩筆 matcher 不同 → 歧義", matcher(raw("live", settings(entry([gate()], "Bash"), entry([gate()])))), {
  code: "AMBIGUOUS_MATCHER", exit: 1,
  has: ["matcher 不一致", "無法判斷該以哪一筆為準"],
  // 修正前會挑第一筆（matcher="Bash"）然後亂報「matcher 缺少 Edit」
  hasnt: ["matcher 缺少"],
});

// matcher 相同、command 不同 → matcher 本身沒有歧義，重複註冊交給 probe
expect("A72 matcher 同 command 不同 → PASS＋警告", matcher(raw("live", settings(entry([gate()]), entry([gate({ command: CMD_STALE })])))), {
  code: "OK_WITH_DUPLICATES", exit: 0,
  has: ["2 筆 shell-form gate handler", "重複註冊是 probe 的職責"],
});

expect("A73 兩筆完全相同 → PASS＋警告", matcher(raw("live", settings(entry([gate(), gate()])))), {
  code: "OK_WITH_DUPLICATES", exit: 0, has: ["重複註冊是 probe 的職責"],
});

expect("A74 shell + exec 混用", matcher(raw("live", settings(entry([gate()]), entry([gateExec()])))), {
  code: "OK_WITH_DUPLICATES", exit: 0, has: ["1 筆 exec form"],
});

// ════════════════════════════════════════════════════════════════════════
console.log("\n§B 成對契約（刻意的規則差異）");
// ════════════════════════════════════════════════════════════════════════
// 共用 parser、**不共用停手條件**。這一段就是那句話的可執行版本：
// 同一份 fixture，probe 停手、matcher 照樣往下驗。少了這組案子，
// 日後有人「順手統一」兩邊的行為時不會有任何 gate 攔下來。
{
  const shared = settings(entry([gate(), { type: "command", command: "node /other/hook.js" }]));
  const p = probe(raw(L_MAIN, shared));
  const m = matcher(raw("live", shared));
  check("B01 共用 entry：probe 停手",
    p.code === "HALT_SHARED_ENTRY" && p.exit === 3, "得到 " + p.code + "/" + p.exit);
  check("B02 共用 entry：matcher 照樣驗（siblings 對它無害）",
    m.code === "OK" && m.exit === 0, "得到 " + m.code + "/" + m.exit);

  const dup = settings(entry([gate()]), entry([gate({ command: CMD_STALE })]));
  const p2 = probe(raw(L_MAIN, dup));
  const m2 = matcher(raw("live", dup));
  check("B03 matcher 同 command 不同：probe 停手",
    p2.code === "HALT_INCONSISTENT" && p2.exit === 3, "得到 " + p2.code + "/" + p2.exit);
  check("B04 同一份 fixture：matcher PASS 並指回 probe",
    m2.code === "OK_WITH_DUPLICATES" && m2.exit === 0 && m2.text.includes("probe"),
    "得到 " + m2.code + "/" + m2.exit);
}

// ════════════════════════════════════════════════════════════════════════
console.log("\n§B 自我一致性");
// ════════════════════════════════════════════════════════════════════════
// 文案表與行為表必須同時更新 —— 加了不安全欄位卻忘了寫說明，這條會 FAIL。
for (const f of G.UNSAFE_FIELDS) {
  check("B10 UNSAFE_WHY 有 " + f.name + " 的說明",
    typeof G.UNSAFE_WHY[f.name] === "string" && G.UNSAFE_WHY[f.name].length > 0,
    "UNSAFE_WHY[" + f.name + "] 缺漏");
}
// scanner 產得出來的每一種 shapeError kind 都必須有句子，不能落到 default
const SHAPE_KINDS = [
  "top-not-object", "hooks-not-object", "pretooluse-not-array", "entry-not-object",
  "entry-hooks-not-array", "handler-not-object", "command-not-string", "args-not-array",
  "args-element-not-string", "bad-type", "no-usable-command", "matcher-not-string",
];
for (const k of SHAPE_KINDS) {
  const s = G.shapeSentence({ kind: k, entryIndex: 0, handlerIndex: 0, argIndex: 0, typeName: "string", typeText: '"x"' });
  check("B11 shapeSentence 有 " + k, !s.includes("未知的形狀問題"), s);
}
// 反向：確認守衛不是死碼
check("B12 未知 kind 會落到 default（守衛非死碼）",
  G.shapeSentence({ kind: "totally-made-up" }).includes("未知的形狀問題"), "default 分支不見了");
check("B13 LEGAL_TYPES 是官方那五種",
  G.LEGAL_TYPES.join(",") === "command,http,mcp_tool,prompt,agent", G.LEGAL_TYPES.join(","));

// ════════════════════════════════════════════════════════════════════════
console.log("\n§C 鏡像逐位元同一性");
// ════════════════════════════════════════════════════════════════════════
for (const m of MIRRORED) {
  const bufs = [];
  let allPresent = true;
  for (const plat of PLATFORMS) {
    const p = path.join(__dirname, "..", plat, m.rel.split("/").join(path.sep));
    if (!fs.existsSync(p)) { allPresent = false; bufs.push(null); continue; }
    bufs.push(fs.readFileSync(p));
  }
  if (!check("C 三平台都有 " + m.rel, allPresent, "缺少：" +
    PLATFORMS.filter((_, i) => bufs[i] === null).join("／"))) continue;
  check("C 非空 " + m.rel, bufs.every((b) => b.length > 0), "有空檔");
  const same = bufs.every((b) => b.equals(bufs[0]));
  check("C 逐位元相同 " + m.rel, same,
    same ? "" : "sizes=" + bufs.map((b) => b.length).join("／") + "\n理由：" + m.why);
}
// 三份都要 require 得起來，且匯出面一致（identity 過了理應如此，但這是廉價的正向對照）
{
  const keys = PLATFORMS.map((plat) => {
    try { return Object.keys(require(modPath(plat))).sort().join(","); }
    catch (e) { return "REQUIRE_FAILED: " + e.code; }
  });
  check("C 三份 require 成功且匯出面一致", keys.every((k) => k === keys[0] && !k.startsWith("REQUIRE")),
    keys.join("\n"));
}

// ── 摘要 ────────────────────────────────────────────────────────────────
console.log("");
console.log("TOTAL " + (pass + fail + skip) + "  PASS " + pass + "  FAIL " + fail + "  SKIP " + skip);
if (failures.length) console.log("失敗清單：" + failures.join("、"));
if (fail) process.exitCode = 1;
else if (skip && strict) {
  // CI 只看退出碼，所以 SKIP 必須也算失敗，否則守衛沒跑到卻是綠燈
  console.log("--strict：有 " + skip + " 個 SKIP，視為失敗");
  process.exitCode = 1;
}
