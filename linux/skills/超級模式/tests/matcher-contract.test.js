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
 * 用法：node tests/matcher-contract.test.js   （exit 0 = 通過、非 0 = 失敗）
 */
const fs = require("fs");
const os = require("os");
const path = require("path");

const hookPath = path.join(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js");

// repo 佈局用 settings.snippet.json；安裝後(live)佈局沒有那個檔，改查真正生效的 settings —
// live 的 settings 才是決定 hook 會不會被叫起的真值，所以裝到 ~/.claude 之後這支測試更有意義。
// 優先挑「真的註冊了本 hook」的那一份，避免撿到不相干的 settings。
const settingsCandidates = [
  path.join(__dirname, "..", "..", "..", "settings.snippet.json"),
  path.join(os.homedir(), ".claude", "settings.json"),
  path.join(os.homedir(), ".claude", "settings.local.json"),
].filter((p) => fs.existsSync(p));

function hasOurHook(p) {
  try {
    const j = JSON.parse(fs.readFileSync(p, "utf8").replace(/^﻿/, ""));
    const list = (j.hooks && j.hooks.PreToolUse) || [];
    return list.some(
      (e) =>
        Array.isArray(e.hooks) &&
        e.hooks.some((h) => String((h && h.command) || "").includes("super-mode-consult-gate"))
    );
  } catch (e) {
    return false;
  }
}
const snippetPath = settingsCandidates.find(hasOurHook) || settingsCandidates[0];

const fail = (msg) => {
  console.error("FAIL: " + msg);
  process.exitCode = 1;
};

if (!fs.existsSync(hookPath)) {
  console.error("hook not found: " + hookPath);
  process.exit(1);
}
if (!snippetPath) {
  console.error("找不到任何 settings（repo settings.snippet.json 或 ~/.claude/settings*.json）");
  process.exit(1);
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
const alternatives = matcher.split("|").map((s) => s.trim()).filter(Boolean);

// --- 正向：hook 要攔的，matcher 必須列到 ---
const required = [...mutatingFileTools, ...mutatingBuiltin, ...SHELL_TOOLS];
for (const name of required) {
  if (!alternatives.includes(name)) {
    fail("matcher 缺少 " + name + " → hook 不會被叫起，該工具的攔截等於沒生效");
  }
}
if (!alternatives.includes("mcp__.*")) {
  fail("matcher 缺少 mcp__.* → 所有 MCP 工具都不會進 hook");
}

// --- 反向：matcher 不該出現 hook 不認識的字面工具名 ---
const known = new Set([...required, "mcp__.*"]);
for (const alt of alternatives) {
  if (!known.has(alt)) {
    fail("matcher 多出 hook 不認識的項目 " + alt + " → 只改了 matcher 卻沒改 hook？");
  }
}

if (process.exitCode) {
  console.error(
    "\nmatcher 現值: " + matcher +
    "\nhook 清單:   " + required.join("|") + "|mcp__.*"
  );
} else {
  console.log("PASS matcher-contract (" + required.length + " 個工具名 + mcp__.* 兩邊一致)");
}
