#!/usr/bin/env node
/*
 * matcher-contract 測試
 *
 * 為什麼需要這支：hook 裡的 MUTATING_BUILTIN 清單**只有在 settings.json 的 PreToolUse
 * matcher 也列到該工具名時才會生效**——matcher 不匹配，hook 根本不會被叫起，清單加了也是白加。
 * 這兩處分屬不同檔案、沒有任何機制把它們綁在一起，歷史上就漂移過（Artifact / ScheduleWakeup /
 * Monitor / Enter·ExitWorktree 一度只存在於工具面、兩邊都沒有）。
 *
 * 本測試把兩邊釘死：hook 認為要攔的每個工具名，都必須出現在 settings 的 matcher 裡；
 * 反向也檢查 matcher 沒有多出 hook 不認識的字面工具名（避免只改 matcher 卻忘了改 hook）。
 *
 * ── 用法（exit 0 = 通過、1 = 不通過、2 = 參數用錯）────────────────────────
 *
 *   node .../tests/matcher-contract.test.js --repo
 *       驗**與本檔相鄰**的 settings.snippet.json ＋ hook。CI 與安裝前檢查（步驟 1a）用。
 *
 *   node .../tests/matcher-contract.test.js --live
 *       驗 ~/.claude/settings.json ＋ ~/.claude/hooks/super-mode-consult-gate.js
 *       ——「真正會被 Claude Code 載入的那一對」。安裝後驗收與診斷用。
 *       **從 checkout 執行也可以**，這正是它存在的理由：修正前沒有這個模式，
 *       「repo 佈局排他」會讓你在 checkout 裡永遠只驗到 repo snippet，
 *       於是 MIGRATION §3.1 宣稱的「驗 live」其實做不到。
 *
 *   node .../tests/matcher-contract.test.js --settings <path> --hook <path>
 *       明確指定一對。兩個旗標**必須成對**——只給 settings 會變成拿別處的 hook
 *       去對它，比對結果沒有意義，而且會安靜地誤導。
 *
 *   node .../tests/matcher-contract.test.js            （**已淘汰，仍可執行**）
 *       沿用舊的自動判斷並印 deprecation 到 stderr。
 *
 * ⚠️ **不要寫「無旗標的行為與退出碼完全不變」**——那是不實的。無旗標路徑同樣套用下面
 * 那些嚴格化：`type` 不是 `command`、或 handler 帶 `if`／`once`／`async`／`asyncRewake` 時，
 * 退出碼會由 **0 變 1**。那正是本次要修的洞，不是回歸。
 *
 * ── 2026-08-09：gate 辨識改用共用模組 ─────────────────────────────────────
 *
 * 「哪個 handler 是本 gate、它會不會真的攔得住」的唯一實作在相鄰的
 * `../lib/gate-registration.js`（三平台逐位元相同，安裝時隨 skill 樹一起進 live）。
 * 修正前這個判斷同時住在這裡與 `tools/probe-gate-registration.js`，兩邊規則不一致，
 * 而且在欄位層面**一致地錯**。對 `main` = 5da2624 實測到的假綠（本檔全部 exit 0 PASS）：
 *
 *   {"type":"prompt"|"http"|"mcp_tool"|"agent", "command":"…gate…"}   gate 不會被執行
 *   {"command":"…gate…"}（type 缺漏）                                  同上
 *   {…, "if":"Bash(git push *)"}                                       Edit/Write 完全不受攔
 *   {…, "once":true}                                                   首次叫用後就被移除
 *   {…, "async":true} / {…, "asyncRewake":true}                        非阻塞，deny 來不及生效
 *
 * 另外兩種修正前是「exit 1 但訊息誤導」：exec form 被報成「沒有註冊本 hook」；
 * 形狀不合（例如 `PreToolUse` 是字串）直接噴 uncaught TypeError 的 stack trace。
 *
 * ⚠️ **重複註冊不是本測試的職責。** 多筆 gate 但 matcher 相同 → 照樣 PASS 並印警告，
 * 由 `tools/probe-gate-registration.js` 負責停手。在這裡也 FAIL 等於接手 probe 的工作，
 * 並且無故弄壞既有使用者的安裝驗收。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

// ── 共用模組 ────────────────────────────────────────────────────────────
// 單一相對路徑，repo 與 live 兩種佈局都成立（1c 是整棵 cp -R，lib/ 會跟著進 live）。
const MODULE_PATH = path.join(__dirname, "..", "lib", "gate-registration.js");

function loadShared() {
  try {
    return { ok: true, mod: require(MODULE_PATH) };
  } catch (e) {
    return {
      ok: false,
      text: [
        "⛔ TOOL_INTEGRITY_ERROR —— 共用模組不可用，本測試**沒有做任何比對**。",
        "   " + MODULE_PATH,
        "   " + (e && e.message ? String(e.message).split("\n")[0] : String(e)),
        "   gate 辨識的邏輯只有一份，放在 skills/超級模式/lib/ 底下並隨 skill 一起安裝。",
        "   若這是已安裝的 live 副本：你的安裝是舊版或不完整，請照 docs/AI-INSTALL.md 重裝 skill。",
        "",
        "RESULT_CODE=TOOL_INTEGRITY_ERROR",
      ].join("\n"),
    };
  }
}

// ── 路徑 ────────────────────────────────────────────────────────────────
// **與本檔相鄰**的一對。這個相對式在兩種佈局下都對：
//   repo      <repo>/<platform>/skills/超級模式/tests → 上三層 = <repo>/<platform>
//   installed ~/.claude/skills/超級模式/tests         → 上三層 = ~/.claude
const adjacentSnippet = path.resolve(__dirname, "..", "..", "..", "settings.snippet.json");
const adjacentHook = path.resolve(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js");
// live 那一對一律由家目錄解出來，不靠 __dirname。
// ⚠️ 刻意**不列** `~/.claude/settings.local.json`。2026-07-28 在 macOS 實測確認它
// **不是** user scope 的 hook 來源：Claude Code 2.1.148 與 2.1.220 的來源列舉字串同為
// 「User-defined hooks from ~/.claude/settings.json, .claude/settings.json, and
// .claude/settings.local.json」——`~/` 只出現在 `settings.json`，另兩者是**專案相對**。
// 把它列為候選，等於讓這支專門防假綠的測試自己變成假綠的來源。
const liveSettings = path.resolve(os.homedir(), ".claude", "settings.json");
const liveHook = path.resolve(os.homedir(), ".claude", "hooks", "super-mode-consult-gate.js");

const USAGE = [
  "用法：--repo | --live | --settings <path> --hook <path>（成對）",
  "      不給旗標＝已淘汰的自動判斷，仍可執行但會印提醒。",
].join("\n");

function parseArgs(argv) {
  const bad = (msg) => ({ ok: false, text: "FAIL: " + msg + "\n" + USAGE + "\n\nRESULT_CODE=BAD_ARGS" });
  let mode = null;
  let settings = null;
  let hook = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--repo" || a === "--live") {
      if (mode) return bad("不能同時指定 " + (mode === "repo" ? "--repo" : "--live") + " 與 " + a);
      mode = a.slice(2);
    } else if (a === "--settings" || a === "--hook") {
      const v = argv[++i];
      if (v === undefined || v.startsWith("--")) return bad(a + " 後面要接路徑");
      if (a === "--settings") {
        if (settings !== null) return bad("--settings 指定了兩次");
        settings = v;
      } else {
        if (hook !== null) return bad("--hook 指定了兩次");
        hook = v;
      }
    } else {
      return bad("未知參數：" + a);
    }
  }
  // 只給一半＝拿別處的 hook 去對這份 settings，比對結果沒有意義。
  if ((settings === null) !== (hook === null)) return bad("--settings 與 --hook 必須成對出現");
  if (settings !== null && mode) return bad("--settings/--hook 不能與 --repo/--live 併用");
  return { ok: true, mode, settings, hook };
}

/*
 * 決定受驗的兩條路徑。**一律回傳兩條 lexical absolute path**，即使檔案不存在——
 * 呼叫端會先把它們印出來再做任何檢查。這條規則有具體理由：這支測試的整個價值在於
 * 「比對的是哪一對」，早退時只印先檢查到的那一條，等於讓人以為驗到了另一個目標。
 */
function resolveTargets(args) {
  if (args.mode === "live") return { mode: "live", settingsPath: liveSettings, hookPath: liveHook, deprecated: false };
  if (args.mode === "repo") return { mode: "repo（與本檔相鄰）", settingsPath: adjacentSnippet, hookPath: adjacentHook, deprecated: false };
  if (args.settings !== null) {
    return { mode: "explicit", settingsPath: path.resolve(args.settings), hookPath: path.resolve(args.hook), deprecated: false };
  }
  // ---- 已淘汰的自動判斷：相鄰 snippet 存在就驗它，否則驗 live ----
  const adjacentExists = fs.existsSync(adjacentSnippet);
  return {
    mode: "deprecated-auto → " + (adjacentExists ? "相鄰 snippet" : "live"),
    settingsPath: adjacentExists ? adjacentSnippet : liveSettings,
    hookPath: adjacentHook,
    deprecated: true,
  };
}

// ── hook 原始碼的工具清單 ────────────────────────────────────────────────
// 讀原始碼而非 require，避免依賴 hook 的匯出面。
function extractArray(hookSrc, name, problems) {
  const m = hookSrc.match(new RegExp("const\\s+" + name + "\\s*=\\s*\\[([\\s\\S]*?)\\]"));
  if (!m) {
    problems.push("在 hook 原始碼裡找不到 " + name + " 陣列");
    return [];
  }
  return (m[1].match(/"([^"]+)"/g) || []).map((s) => s.slice(1, -1));
}

// hook 以 `tool === "X"` 形式直接判定的 shell 類工具（不在上面兩個陣列裡）
const SHELL_TOOLS = ["Bash", "PowerShell", "Monitor"];

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.ok) {
    console.error(args.text);
    return 2;
  }

  const loaded = loadShared();
  if (!loaded.ok) {
    console.error(loaded.text);
    return 1;
  }
  const G = loaded.mod;

  const t = resolveTargets(args);
  if (t.deprecated) {
    console.error(
      "⚠️ deprecated: 沒有指定 --repo / --live，正在使用舊的自動判斷。\n" +
      "   自動判斷在 repo 佈局下**一定**驗相鄰的 snippet，無法驗 live；請改用明確旗標。\n" +
      "   " + USAGE
    );
  }
  // **先印兩條路徑，再做任何檢查。** 早退路徑也一樣。
  console.log(G.matcherAttestation(t).join("\n"));

  // ---- hook ----
  let hookSrc;
  try {
    hookSrc = fs.readFileSync(t.hookPath, "utf8").replace(/^﻿/, "");
  } catch (e) {
    console.error("FAIL: 讀不到 hook（" + e.code + "）：" + t.hookPath);
    console.log("RESULT_CODE=HOOK_UNREADABLE");
    return 1;
  }

  // ---- settings：辨識與判定全交給共用模組 ----
  let source;
  try {
    source = G.sourceRaw(t.settingsPath, t.settingsPath, fs.readFileSync(t.settingsPath, "utf8"));
  } catch (e) {
    source = e.code === "ENOENT"
      ? G.sourceMissing(t.settingsPath, t.settingsPath)
      : G.sourceReadError(t.settingsPath, t.settingsPath, e.code);
  }
  const verdict = G.assessMatcher({ settings: source });
  const rendered = G.renderMatcher(verdict, t);
  if (verdict.exit !== 0) {
    console.error(rendered);
    if (t.settingsPath === liveSettings || t.mode === "live") {
      console.error("（受驗目標是 live。若你剛照 AI-INSTALL 步驟 2 合併過，請確認合併的是 " + liveSettings + "。）");
    }
    console.log("RESULT_CODE=" + verdict.code);
    return verdict.exit;
  }
  if (rendered) console.log(rendered); // OK_WITH_DUPLICATES 的警告

  // ---- 契約比對 ----
  const problems = [];
  const mutatingFileTools = extractArray(hookSrc, "MUTATING_FILE_TOOLS", problems);
  const mutatingBuiltin = extractArray(hookSrc, "MUTATING_BUILTIN", problems);
  for (const tool of SHELL_TOOLS) {
    if (!new RegExp('tool\\s*===\\s*"' + tool + '"').test(hookSrc)) {
      problems.push('hook 原始碼沒有 tool === "' + tool + '" 的分支，但本測試預期它存在');
    }
  }
  if (problems.length) {
    for (const p of problems) console.error("FAIL: " + p);
    console.log("RESULT_CODE=HOOK_UNPARSEABLE");
    return 1;
  }

  const matcher = verdict.matcher;
  const alternatives = matcher.split("|").map((s) => s.trim()).filter(Boolean);
  const required = mutatingFileTools.concat(mutatingBuiltin, SHELL_TOOLS);

  // 正向：hook 要攔的，matcher 必須列到
  for (const name of required) {
    if (!alternatives.includes(name)) {
      problems.push("matcher 缺少 " + name + " → hook 不會被叫起，該工具的攔截等於沒生效");
    }
  }
  if (!alternatives.includes("mcp__.*")) {
    problems.push("matcher 缺少 mcp__.* → 所有 MCP 工具都不會進 hook");
  }
  // 反向：matcher 不該出現 hook 不認識的字面工具名
  const known = required.concat(["mcp__.*"]);
  for (const alt of alternatives) {
    if (!known.includes(alt)) {
      problems.push("matcher 多出 hook 不認識的項目 " + alt + " → 只改了 matcher 卻沒改 hook？");
    }
  }

  if (problems.length) {
    for (const p of problems) console.error("FAIL: " + p);
    console.error("\nmatcher 現值: " + matcher + "\nhook 清單:   " + required.join("|") + "|mcp__.*");
    console.log("RESULT_CODE=MATCHER_DRIFT");
    return 1;
  }

  console.log("PASS matcher-contract (" + required.length + " 個工具名 + mcp__.* 兩邊一致)");
  console.log("RESULT_CODE=" + verdict.code);
  return 0;
}

// 受控的整包 try/catch：修正前這支對「形狀不合」會噴 uncaught TypeError 的 stack trace，
// 而使用者拿 stack trace 沒辦法判斷「我的安裝到底有沒有問題」。
// ⚠️ 全程 process.exitCode ＋自然結束，不用 process.exit()——後者依 Node 官方文件
// 會截斷尚未完成的 stdout 寫入。
try {
  process.exitCode = main();
} catch (e) {
  console.error("⛔ INTERNAL_ERROR —— 本測試自己出錯，沒有完成比對，請回報。");
  console.error("   " + (e && e.stack ? String(e.stack).split("\n")[0] : String(e)));
  console.log("RESULT_CODE=INTERNAL_ERROR");
  process.exitCode = 1;
}
