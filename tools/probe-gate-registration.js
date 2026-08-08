#!/usr/bin/env node
/*
 * probe-gate-registration —— 唯讀診斷：super-mode consult gate 現在註冊在哪、有幾筆、
 * 能不能照文件往下做。**不會修改任何檔案。**
 *
 * 三平台共用同一份（`node tools/probe-gate-registration.js`）。
 * 它先前是 `docs/MIGRATION-hook-settings-target.md` 第 1 節裡的 bash heredoc，
 * 2026-08-08 抽成本檔，原因有二：
 *   1. heredoc 在 Windows 的 PowerShell 跑不動，但「重複註冊」三平台都會發生，
 *      `AI-INSTALL` 步驟 2 與三份 snippet 都要叫使用者先數一次。
 *   2. 內嵌在 markdown 裡的邏輯沒有任何回歸案守著。現在有
 *      `tests/probe-gate-registration.test.js`。
 *
 * 退出碼（文件的判斷分支一律以這個為準，不要另外摘要規則）：
 *   0 = 判定可執行，照印出來的「判定：」那行做
 *   1 = 讀不到或形狀不合 —— 先修好再重跑，不要往下做（fail-closed）
 *   3 = 停手：需要人工判斷，本 repo 的文件涵蓋不了
 *
 * 為什麼形狀不合一定要 fail-closed：舊版寫
 * `for (const entry of (j.hooks && j.hooks.PreToolUse) || [])`，當 `hooks.PreToolUse`
 * 是**字串**時會逐字元迭代、靜默數成 0，於是判定成「兩邊都沒有 gate……照 AI-INSTALL
 * 步驟 2 重做」——假陰性，而且重裝正是可能造成重複註冊的動作。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

const NEEDLE = "super-mode-consult-gate";

const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const typeName = (v) => (v === null ? "null" : Array.isArray(v) ? "陣列" : typeof v);

/**
 * 掃一個 settings 檔。
 * 回傳 { ok: true, n, handlers: [{ matcher, command, others }] } 或 { ok: false }。
 * `others` = 同一個 outer entry 底下**不是 gate** 的 handler 數量。
 */
function scan(label, p) {
  const say = (msg) => console.log(label.padEnd(32) + msg);
  const bad = (why) => {
    say("形狀不合：" + why);
    return { ok: false };
  };

  let raw;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (e) {
    if (e.code === "ENOENT") {
      say("檔案不存在");
      return { ok: true, n: 0, handlers: [] };
    }
    say("讀取失敗：" + e.code);
    return { ok: false };
  }

  let j;
  try {
    // 用 \uFEFF 而不是把 BOM 字元直接寫進 regex：後者在編輯器／diff 裡是隱形的，
    // 誰不小心刪掉都看不出來。語意完全相同。
    j = JSON.parse(raw.replace(/^\uFEFF/, ""));
  } catch (e) {
    say("JSON 解析失敗：" + e.message);
    return { ok: false };
  }

  if (!isObj(j)) return bad("頂層不是物件（是 " + typeName(j) + "）");
  if (!("hooks" in j)) {
    say("沒有 hooks 段 —— gate 條目：0 個");
    return { ok: true, n: 0, handlers: [] };
  }
  if (!isObj(j.hooks)) return bad("hooks 不是物件（是 " + typeName(j.hooks) + "）");

  const pre = j.hooks.PreToolUse;
  if (pre === undefined) {
    say("沒有 hooks.PreToolUse —— gate 條目：0 個");
    return { ok: true, n: 0, handlers: [] };
  }
  if (!Array.isArray(pre)) return bad("hooks.PreToolUse 不是陣列（是 " + typeName(pre) + "）");

  const handlers = [];
  for (let i = 0; i < pre.length; i++) {
    const entry = pre[i];
    const at = "PreToolUse[" + i + "]";
    if (!isObj(entry)) return bad(at + " 不是物件（是 " + typeName(entry) + "）");
    if (entry.hooks === undefined) continue;
    if (!Array.isArray(entry.hooks)) return bad(at + ".hooks 不是陣列（是 " + typeName(entry.hooks) + "）");

    const gateIdx = [];
    for (let k = 0; k < entry.hooks.length; k++) {
      const h = entry.hooks[k];
      const hat = at + ".hooks[" + k + "]";
      if (!isObj(h)) return bad(hat + " 不是物件（是 " + typeName(h) + "）");
      if (h.command === undefined) continue;
      if (typeof h.command !== "string") return bad(hat + ".command 不是字串（是 " + typeName(h.command) + "）");
      if (!h.command.includes(NEEDLE)) continue;
      // 命中字串還不夠：canonical 註冊是 { "type": "command", "command": ... }。
      // 只比對 command 的 substring，會把「type 缺漏或不是 command」的條目也算成
      // 「gate 已接上」——那是這支診斷自己製造假綠。形狀不對就停，不要回報成已註冊。
      if (h.type !== "command") {
        return bad(
          hat + " 的 command 含 gate，但 type 是 " +
          (h.type === undefined ? "缺漏" : JSON.stringify(h.type)) +
          "（必須是 \"command\"）"
        );
      }
      gateIdx.push(k);
    }

    if (!gateIdx.length) continue;
    // matcher 只在「這個 entry 真的掛著 gate」時才驗型別：不相干的畸形 entry
    // 不該把使用者的 migration 擋死。
    if (entry.matcher !== undefined && typeof entry.matcher !== "string") {
      return bad(at + ".matcher 不是字串（是 " + typeName(entry.matcher) + "）");
    }
    const others = entry.hooks.length - gateIdx.length;
    for (const k of gateIdx) {
      handlers.push({
        matcher: entry.matcher === undefined ? "" : entry.matcher,
        command: entry.hooks[k].command,
        others,
        where: at + ".hooks[" + k + "]",
      });
    }
  }

  say("gate 條目：" + handlers.length + " 個");
  return { ok: true, n: handlers.length, handlers };
}

const home = os.homedir();
const mainRes = scan("~/.claude/settings.json", path.join(home, ".claude", "settings.json"));
const localRes = scan("~/.claude/settings.local.json", path.join(home, ".claude", "settings.local.json"));
console.log("");

if (!mainRes.ok || !localRes.ok) {
  console.log("判定：有檔案無法解析或形狀不合 —— 先修好再重跑，不要往下做。");
  process.exit(1); // fail-closed：形狀不明時不可以讓人拿 exit 0 當成「已確認沒問題」
}

const all = mainRes.handlers.concat(localRes.handlers);

// ── 停手條件（機械判定，文件不再自己摘要一份）────────────────────────────
// 1. 含 gate 的 outer entry 底下還掛著別的 handler：整筆搬移／刪除會動到不相干的 hook。
const shared = all.filter((h) => h.others > 0);
if (shared.length) {
  for (const h of shared) {
    console.log("  " + h.where + " 所在的 entry 底下還有 " + h.others + " 個非 gate 的 handler");
  }
  console.log("判定：停手 —— 含 gate 的條目底下還掛著其他 handler，動它會影響不相干的 hook。請人工判斷。");
  process.exit(3);
}
// 2. 有兩筆以上 gate handler、但它們的 matcher 或 command 不一致：不知道該留哪一筆。
//    ⚠️ 必須比**兩個檔的聯集**。只比 settings.json 的話，「main 一筆 stale ＋ local 一筆正確」
//    會被判成 B（純減法），使用者刪光 local 只留下壞的那筆，重跑還會得到「正常」。
const seen = [];
for (const h of all) {
  const key = JSON.stringify([h.matcher, h.command]);
  if (!seen.includes(key)) seen.push(key);
}
if (all.length >= 2 && seen.length > 1) {
  console.log("  共 " + all.length + " 筆 gate handler，出現 " + seen.length + " 種不同的 (matcher, command)：");
  for (const k of seen) {
    const v = JSON.parse(k);
    console.log("    matcher=" + JSON.stringify(v[0]) + "  command=" + JSON.stringify(v[1]));
  }
  console.log("判定：停手 —— 多筆 gate handler 的 matcher／command 不一致，無法判斷該留哪一筆。請人工判斷。");
  process.exit(3);
}

// ── 一般判定 ────────────────────────────────────────────────────────────
const main = mainRes.n;
const local = localRes.n;
if (main === 1 && local === 0) console.log("判定：正常，不用修。");
else if (main > 1) console.log("判定：settings.json 裡有 " + main + " 筆 gate —— 已經重複註冊。做第 2 節的『B. 已經有一筆』。");
else if (main === 1 && local >= 1) console.log("判定：兩邊都有 —— **只要從 settings.local.json 移除**，不要搬。做第 2 節的『B. 已經有一筆』。");
else if (main === 0 && local >= 1) console.log("判定：受影響 —— gate 只在 local，從非家目錄啟動完全不生效。做第 2 節的『A. 還沒有』。");
else console.log("判定：兩邊都沒有 gate —— 可能還沒安裝，或註冊在別處。照 AI-INSTALL 步驟 2 重做。");
