#!/usr/bin/env node
/*
 * matcher-contract 測試（matcher ↔ hook 覆蓋面契約）
 *
 * 為什麼需要這支：hook 的判定**只有在 settings.json 的 PreToolUse matcher 匹配該工具名時
 * 才會生效**——matcher 不匹配，hook 根本不會被叫起，hook 裡寫什麼都是白寫。
 * 這兩處分屬不同檔案、沒有任何機制把它們綁在一起，歷史上就漂移過（Artifact / ScheduleWakeup /
 * Monitor / Enter·ExitWorktree 一度只存在於工具面、matcher 與 hook 兩邊都沒有）。
 *
 * ⚠️ 這支測試舊版（列舉式 matcher 時代）保證的只是「**兩份手寫清單彼此一致**」，
 *    不是「治理覆蓋完整」——兩份清單一起漏列同一個新工具時，它照樣 PASS。
 *    2026-08 起 matcher 改為「catch-all 減去高頻唯讀工具」，本測試的主要不變量隨之改成：
 *    **任意未知工具名都必須進得了 hook**（見 UNKNOWN_SAMPLES），
 *    以及「被 matcher 排除的工具必須是 hook 已分類為唯讀的」。
 *    覆蓋面是否完整，最終仍取決於 hook 的 default-deny，而不是這份 matcher。
 *
 * 用法：node tests/matcher-contract.test.js   （exit 0 = 通過、非 0 = 失敗）
 */
const fs = require("fs");
const os = require("os");
const path = require("path");

const hookPath = path.join(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js");

// repo 佈局用 settings.snippet.json；安裝後(live)佈局沒有那個檔，改查真正生效的 settings —
// live 的 settings 才是決定 hook 會不會被叫起的真值，所以裝到 ~/.claude 之後這支測試更有意義。
// 只挑「真的註冊了本 hook」的那一份，避免撿到不相干的 settings。
// ⚠️ 刻意**不列** `~/.claude/settings.local.json`。2026-07-28 在 macOS 實測確認它
// **不是** user scope 的 hook 來源：Claude Code 2.1.148 與 2.1.220 的來源列舉字串同為
// 「User-defined hooks from ~/.claude/settings.json, .claude/settings.json, and
// .claude/settings.local.json」——`~/` 只出現在 `settings.json`，另兩者是**專案相對**。
// 家目錄那份只有在「從家目錄啟動 Claude Code」時才生效（那時它剛好就是專案層的檔案）。
// 把它列為候選，等於讓這支專門防假綠的測試自己變成假綠的來源。
const repoSnippet = path.join(__dirname, "..", "..", "..", "settings.snippet.json");
const liveSettings = path.join(os.homedir(), ".claude", "settings.json");

// 四態分類，不用布林 —— 「檔案不存在」與「檔案壞掉／沒註冊 hook」必須分得開。
// 舊寫法把 parse error 一律 catch 成 false，等於把「待出貨的 snippet 壞了」
// 和「這裡沒有 snippet」混為一談。
function classify(p) {
  if (!fs.existsSync(p)) return { state: "missing" };
  let raw;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (e) {
    return { state: "invalid", why: "讀取失敗：" + e.code };
  }
  let j;
  try {
    j = JSON.parse(raw.replace(/^﻿/, ""));
  } catch (e) {
    return { state: "invalid", why: "JSON 解析失敗：" + e.message };
  }
  const list = (j.hooks && j.hooks.PreToolUse) || [];
  const registered = list.some(
    (e) =>
      e &&
      Array.isArray(e.hooks) &&
      e.hooks.some((h) => String((h && h.command) || "").includes("super-mode-consult-gate"))
  );
  return registered ? { state: "ok" } : { state: "noHook" };
}

const fail = (msg) => {
  console.error("FAIL: " + msg);
  process.exitCode = 1;
};

if (!fs.existsSync(hookPath)) {
  console.error("hook not found: " + hookPath);
  process.exit(1);
}

// repo 佈局**排他**：只要 settings.snippet.json 存在，就一定驗它，
// 不准因為它壞掉／沒註冊 hook 就退去讀家目錄的 settings ——
// 那會讓「待出貨的 snippet 是壞的」被開發者自己機器上的舊設定掩蓋而 PASS。
// 只有在 repo snippet **真的不存在**（= live 佈局）時，才改驗使用者的 settings.json。
let snippetPath;
const repo = classify(repoSnippet);
if (repo.state !== "missing") {
  if (repo.state !== "ok") {
    console.error(
      "FAIL: repo 的 settings.snippet.json " +
        (repo.state === "invalid" ? repo.why : "沒有註冊本 hook") +
        "\n  " + repoSnippet +
        "\n這是待出貨的檔案，不能用家目錄的 settings 掩蓋它。"
    );
    process.exit(1);
  }
  snippetPath = repoSnippet;
} else {
  const live = classify(liveSettings);
  if (live.state !== "ok") {
    console.error(
      "FAIL: " +
        (live.state === "missing"
          ? "找不到 " + liveSettings
          : live.state === "invalid"
            ? liveSettings + " " + live.why
            : liveSettings + " 裡沒有註冊本 hook") +
        "\n\nhook 必須註冊在 ~/.claude/settings.json（user scope）。" +
        "\n⚠️ ~/.claude/settings.local.json 不是 user scope —— 只有從家目錄啟動 Claude Code 時" +
        "\n   才會被當成專案層檔案讀到，從其他目錄啟動就完全不生效。" +
        "\n若你剛照 AI-INSTALL 步驟 2 合併過，請確認合併的是 ~/.claude/settings.json。"
    );
    process.exit(1);
  }
  snippetPath = liveSettings;
}

const hookSrc = fs.readFileSync(hookPath, "utf8").replace(/^﻿/, "");
const snippet = JSON.parse(fs.readFileSync(snippetPath, "utf8").replace(/^﻿/, ""));

// --- 從 hook 原始碼抽出兩份工具名清單（讀原始碼而非 require，避免依賴匯出面） ---
function extractArray(name) {
  const m = hookSrc.match(new RegExp("const\\s+" + name + "\\s*=\\s*\\[([\\s\\S]*?)\\]"));
  if (!m) {
    fail("在 hook 原始碼裡找不到 " + name + " 陣列");
    return [];
  }
  return (m[1].match(/"([^"]+)"/g) || []).map((s) => s.slice(1, -1));
}

function extractSet(name) {
  const m = hookSrc.match(new RegExp("const\\s+" + name + "\\s*=\\s*new Set\\(\\[([\\s\\S]*?)\\]\\)"));
  if (!m) {
    fail("在 hook 原始碼裡找不到 " + name + " 集合");
    return [];
  }
  return (m[1].match(/"([^"]+)"/g) || []).map((s) => s.slice(1, -1));
}

const mutatingFileTools = extractArray("MUTATING_FILE_TOOLS");
const mutatingBuiltin = extractArray("MUTATING_BUILTIN");

// hook 以 `tool === "X"` 形式直接判定的 shell 類工具（不在上面兩個陣列裡）
const SHELL_TOOLS = ["Bash", "PowerShell", "Monitor"];
for (const t of SHELL_TOOLS) {
  if (!new RegExp('tool\\s*===\\s*"' + t + '"').test(hookSrc)) {
    fail('hook 原始碼沒有 tool === "' + t + '" 的分支，但本測試預期它存在');
  }
}

// --- 取 matcher ---
const entries = (snippet.hooks && snippet.hooks.PreToolUse) || [];
if (!entries.length) {
  console.error(snippetPath + " 沒有 hooks.PreToolUse 條目");
  process.exit(1);
}
const entry =
  entries.find(
    (e) =>
      Array.isArray(e.hooks) &&
      e.hooks.some((h) => String((h && h.command) || "").includes("super-mode-consult-gate"))
  ) || entries[0];
const matcher = String(entry.matcher || "");

// matcher 已從「工具名列舉」改為「catch-all 減去高頻唯讀工具」的負向前瞻，
// 所以不能再用 split("|") 拆項比對——改成**語義**比對：拿真正的 RegExp 去 test 工具名。
// 官方語義：matcher 含字母/數字/_/-/空白/,/| 以外的字元 → 當成 unanchored 的 JS 正則。
let matcherRe;
try {
  matcherRe = new RegExp(matcher);
} catch (e) {
  console.error("FAIL: matcher 不是合法正則：" + matcher + "（" + e.message + "）");
  process.exit(1);
}
const matches = (name) => matcherRe.test(name);

// --- 正向：hook 要攔的，matcher 必須放進來 ---
const required = [...mutatingFileTools, ...mutatingBuiltin, ...SHELL_TOOLS];
for (const name of required) {
  if (!matches(name)) {
    fail("matcher 不匹配 " + name + " → hook 不會被叫起，該工具的攔截等於沒生效");
  }
}
for (const name of ["mcp__whatever__do_thing", "mcp__github__create_pull_request"]) {
  if (!matches(name)) fail("matcher 不匹配 MCP 工具 " + name + " → 該 MCP 工具不會進 hook");
}

// --- 核心不變量：**未知**工具名必須進得了 hook ---
// 這條才是這支測試現在的主要價值。舊版只驗「兩份手寫清單一致」，
// 兩份清單一起漏列新工具時照樣 PASS（Artifact/ScheduleWakeup/Monitor/Enter·ExitWorktree 就這樣漏過）。
// 名字刻意取成「未來可能長這樣」但今天不存在的，確保判準不是靠硬編清單。
const UNKNOWN_SAMPLES = [
  "SendUserFile",
  "Workflow",
  "Agent",
  "PublishSomething",
  "ZzzFutureToolThatDoesNotExistYet",
  "TaskCreate",
];
for (const name of UNKNOWN_SAMPLES) {
  if (!matches(name)) {
    fail(
      "matcher 不匹配未知工具 " + name +
      " → 它永遠進不了 hook，等於無聲放行（這正是舊列舉式 matcher 的漏洞）"
    );
  }
}

// --- 反向：matcher 必須「剛好」等於由 MATCHER_EXCLUDED 生成的形式（exact equality）---
// ⚠️ 為什麼是 exact equality 而不是抽樣比對：
//    抽樣（拿幾個未知工具名去 test）擋不住「在 matcher 的排除組多塞一個名字」——
//    只要那個名字不在 required、不在 KNOWN_BENIGN_BUILTIN、也不在樣本清單裡，
//    抽樣式測試就會 PASS，而該工具實際上**永遠進不了 hook**。
//    唯一能證明「任意未知工具都進得了 hook」的方法，是讓排除集只有一個真相來源
//    （hook 的 MATCHER_EXCLUDED），並要求 matcher 字面上就是它生成出來的那一個。
const matcherExcluded = extractArray("MATCHER_EXCLUDED");
const knownBenign = new Set(extractSet("KNOWN_BENIGN_BUILTIN"));
if (!matcherExcluded.length) fail("hook 原始碼裡的 MATCHER_EXCLUDED 是空的");

const expectedMatcher = "^(?!(?:" + matcherExcluded.join("|") + ")$)";
if (matcher !== expectedMatcher) {
  fail(
    "matcher 不等於由 hook 的 MATCHER_EXCLUDED 生成的形式 → 有人只改了一邊。\n" +
      "  expected: " + expectedMatcher + "\n" +
      "  actual:   " + matcher
  );
}

// 排除者必須是 hook 已分類為良性的（被排除 = 永久盲區，不能是未分類或會改狀態的工具）
for (const name of matcherExcluded) {
  if (!knownBenign.has(name)) {
    fail(name + " 在 MATCHER_EXCLUDED 卻不在 KNOWN_BENIGN_BUILTIN → 被排除的工具必須先分類為良性");
  }
  if (matches(name)) fail("宣告排除的 " + name + " 實際仍被 matcher 匹配 → 生成式與語義不一致");
}
// 會改狀態的工具絕不可出現在排除集（即使有人同時改了兩邊）
for (const name of [...mutatingFileTools, ...mutatingBuiltin, ...SHELL_TOOLS]) {
  if (matcherExcluded.includes(name)) {
    fail(name + " 是會改狀態的工具，卻被列進 MATCHER_EXCLUDED → 會被永久排除在 hook 之外");
  }
}

// 上面那條只認得「hook 目前已列為 mutating」的工具，所以擋不住這條路徑：
// 把某個 stateful 工具**同時**加進 KNOWN_BENIGN_BUILTIN + MATCHER_EXCLUDED + settings matcher
// → 三邊一致、測試全綠，但該工具從此永久看不見。這裡用一份獨立的「絕不可排除」清單，
// 讓「重新分類成良性」這個動作本身也要過一關。清單漏列只是少一層保護，
// 主要防線仍是「未知工具 default-deny」。
const NEVER_EXCLUDE = [
  "TodoWrite", "TaskCreate", "TaskUpdate", "TaskStop",
  "Agent", "Workflow", "SendUserFile", "SendMessage",
  "Artifact", "ScheduleWakeup", "CronCreate", "CronDelete",
  "RemoteTrigger", "PushNotification", "EnterWorktree", "ExitWorktree",
  "Edit", "Write", "MultiEdit", "NotebookEdit", "Bash", "PowerShell", "Monitor",
];
for (const name of NEVER_EXCLUDE) {
  if (matcherExcluded.includes(name)) {
    fail(
      name + " 出現在 MATCHER_EXCLUDED，但它在 NEVER_EXCLUDE 清單上（會改變狀態或會扇出）→ " +
      "把它排除等於讓它永久進不了 hook。若真要重新分類，必須先改 NEVER_EXCLUDE 並說明理由。"
    );
  }
  if (!matches(name)) {
    fail(name + " 不被 matcher 匹配 → 進不了 hook（NEVER_EXCLUDE 的工具必須看得見）");
  }
}

if (process.exitCode) {
  console.error(
    "\nmatcher 現值: " + matcher +
    "\nhook 要攔:   " + required.join(", ") +
    "\nmatcher 排除: " + matcherExcluded.join(", ")
  );
} else {
  console.log(
    "PASS matcher-contract (" + required.length + " 個要攔的工具進得了 hook、" +
    UNKNOWN_SAMPLES.length + " 個未知工具進得了 hook、" +
    matcherExcluded.length + " 個排除項與 hook 宣告一致)"
  );
}
