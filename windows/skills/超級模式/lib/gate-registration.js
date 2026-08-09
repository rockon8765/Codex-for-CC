#!/usr/bin/env node
/*
 * gate-registration —— 「哪個 handler 是本 gate、它會不會真的攔得住」的**單一真相**。
 *
 * 這個檔在三平台 payload 底下各有一份，**三份逐位元相同**（一份邏輯版本、三份配送鏡像）。
 * 消費者兩個：
 *   ・`tools/probe-gate-registration.js`（repo 根，唯讀診斷）—— 讀三份鏡像、比 bytes、
 *     全等才 require；不等或缺檔一律 TOOL_INTEGRITY_ERROR。
 *   ・`<platform>/skills/超級模式/tests/matcher-contract.test.js`（會被安裝到 live）——
 *     單一相對路徑 `../lib/gate-registration.js`，repo 與 live 兩種佈局都成立。
 *
 * 為什麼要有這個檔（2026-08-09）：同一個判斷先前住在上面那兩個地方，**規則不一致**，
 * 而且在欄位層面**一致地錯**。實測（對 `main` = 5da2624）兩邊都說「正常／PASS」但 gate
 * 根本不會 gate 的輸入至少五種：`command:"echo <needle>"`、`if`、`once`、`async`、
 * `asyncRewake`。詳見 docs/backlog.md。
 *
 * ── 設計約束（每一條都是被實測或審查逼出來的，改動前先讀）─────────────────
 *
 * 1. **本模組不碰 fs、不碰 process。** 輸入是 caller 讀好的 SettingsSource（tagged union），
 *    輸出是結構化 verdict。理由：`read-error`（EISDIR／EACCES）必須表達得出來 ——
 *    先前設計把輸入寫成 `rawOrNull`，於是「讀取失敗」這個狀態根本不可達。
 *    附帶好處：單元測試不需要假 HOME 或 mock。
 *
 * 2. **open-world schema。** 只驗本模組宣告負責的形狀，未宣告的 top-level／entry／handler
 *    欄位一律放行。三份 `settings.snippet.json` 都帶頂層 `_comment`，closed-world 會讓
 *    三份一起誤紅。
 *
 * 3. **「命中 needle」≠「已註冊本 gate」。** 本模組一律稱 needle **candidate**。
 *    `{"type":"command","command":"echo super-mode-consult-gate"}` 會被算成 candidate，
 *    但它根本不執行 gate —— 要排除這種假陽性得剖析 shell token，本模組刻意不做，
 *    所以**不要**把 candidate 當成「gate 一定會被叫起」的證據。記在 docs/backlog.md。
 *
 * 4. **中文句子只住在 renderer。** scanner／assess 只產結構化 code＋參數；
 *    `renderProbe` 與 `renderMatcher` 是兩個 adapter，不是同一個 render()：
 *    probe 要雙檔盤點＋範圍 epilogue，matcher 要 target attestation＋contract diff。
 *    兩者都印 `RESULT_CODE=`，**文件請按 code 分派，不要按中文句子**。
 *
 * 5. **共用 parser，不共用停手條件。** `siblings > 0`（gate 與別的 handler 同一個 entry）
 *    對 probe 是停手（整筆搬移會動到不相干的 hook），對 matcher-contract **無害**
 *    （matcher 照樣適用）。這不是規則漂移，是兩個不同的問題 —— 所以
 *    `assessProbe` 與 `assessMatcher` 各有自己的具名 verdict。
 *    `tests/gate-registration.test.js` 有一組成對契約案釘住這件事。
 */
"use strict";

// ── 常數 ────────────────────────────────────────────────────────────────
const NEEDLE = "super-mode-consult-gate";

// Claude Code 的 hook handler `type` 合法值（官方 hooks reference）。
// 本 gate 必須是 `command` —— 其餘四種都不會執行 `command` 欄位。
const LEGAL_TYPES = ["command", "http", "mcp_tool", "prompt", "agent"];

/*
 * **canonical safety profile** —— 這些欄位出現在 gate handler 上，gate 就不會如預期阻擋。
 * 每一條都對過官方 hooks reference 並在假 HOME 實測過（修正前兩支工具都放行）：
 *   if           把 gate 限縮到別的工具（例 "Bash(git push *)"）→ Edit/Write 完全不受攔
 *   once         首次叫用後就被移除 → 之後整個 session 不設防
 *   async        非阻塞背景執行 → PreToolUse deny gate 根本不能 deny
 *   asyncRewake  同上（只是多了 exit 2 喚醒）
 *
 * policy：
 *   "present"  只要欄位存在（值非 undefined）就算不安全 —— `if` 屬此類，
 *              任何規則字串都是一種限縮。
 *   "truthy"   只有真值才算 —— `once:false` / `async:false` 是明確關閉，無害。
 *
 * **刻意不列**（不影響 gate 能否阻擋，一律放行並保留）：
 *   timeout / shell / statusMessage
 */
const UNSAFE_FIELDS = [
  { name: "if", policy: "present" },
  { name: "once", policy: "truthy" },
  { name: "async", policy: "truthy" },
  { name: "asyncRewake", policy: "truthy" },
];

const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const typeName = (v) => (v === null ? "null" : Array.isArray(v) ? "陣列" : typeof v);
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

function unsafeFieldsOf(handler) {
  const out = [];
  for (const f of UNSAFE_FIELDS) {
    if (!has(handler, f.name)) continue;
    const v = handler[f.name];
    if (v === undefined) continue;
    if (f.policy === "truthy" && !v) continue;
    out.push({ name: f.name, value: v });
  }
  return out;
}

// ── SettingsSource 建構子（給 caller 用，避免各自拼 tagged union 拼錯）────────
//
// SettingsSource =
//   | { kind: "raw",        label, path, raw,  shortLabel? }
//   | { kind: "missing",    label, path,       shortLabel? }
//   | { kind: "read-error", label, path, code, shortLabel? }
//
// `label`      盤點行左欄用（probe 用 "~/.claude/settings.json"，補到 32 欄寬）
// `path`       真實檔案路徑，錯誤訊息用
// `shortLabel` 選填。逐筆列出 handler 時用的短名（probe 用 "settings.json"）。
//              缺省時退回 `label`。**存在的唯一理由**是讓 probe 的輸出與修正前
//              逐位元相同 —— 它的盤點行用長名、handler 清單用短名，兩者不同。
const sourceRaw = (label, p, raw, shortLabel) => ({ kind: "raw", label, path: p, raw, shortLabel });
const sourceMissing = (label, p, shortLabel) => ({ kind: "missing", label, path: p, shortLabel });
const sourceReadError = (label, p, code, shortLabel) => ({ kind: "read-error", label, path: p, code, shortLabel });

// ── scanner ─────────────────────────────────────────────────────────────
/*
 * 掃一份 settings。回傳（**不含任何人類文字**）：
 *
 * {
 *   label, path,
 *   status: "missing" | "read-error" | "parse-error" | "shape-error" | "ok",
 *   readCode?, parseMessage?,                     // 對應 status
 *   shapeError?: { kind, entryIndex?, handlerIndex?, argIndex?, typeName?, typeText? },
 *   emptyReason?: null | "no-hooks" | "no-pretooluse",   // status==="ok" 時
 *   candidates: [{
 *     entryIndex, handlerIndex, pointer,
 *     form: "shell" | "exec",
 *     type, command, args,        // 原樣保留，assess 才判定
 *     matcher,                    // entry.matcher，缺漏時為 ""
 *     unsafe: [{name, value}],
 *     siblings,                   // 同一 entry 底下**不是 shell-form candidate** 的 handler 數
 *   }],
 * }
 *
 * ⚠️ **形狀不合一律 fail-closed（不繼續掃）。** 舊版寫
 * `for (const entry of (j.hooks && j.hooks.PreToolUse) || [])`，`hooks.PreToolUse`
 * 是**字串**時會逐字元迭代、靜默數成 0，於是判定成「兩邊都沒有 gate……重做安裝」——
 * 假陰性，而且重裝正是可能造成重複註冊的動作。
 */
function scanSource(source) {
  const base = {
    label: source.label,
    path: source.path,
    shortLabel: source.shortLabel === undefined ? source.label : source.shortLabel,
    candidates: [],
  };

  if (source.kind === "missing") return Object.assign(base, { status: "missing" });
  if (source.kind === "read-error") {
    return Object.assign(base, { status: "read-error", readCode: source.code });
  }

  let j;
  try {
    // 用 ﻿ 而不是把 BOM 字元直接寫進 regex：後者在編輯器／diff 裡是隱形的，
    // 誰不小心刪掉都看不出來。語意完全相同。
    j = JSON.parse(source.raw.replace(/^﻿/, ""));
  } catch (e) {
    return Object.assign(base, { status: "parse-error", parseMessage: e.message });
  }

  const shape = (shapeError) => Object.assign(base, { status: "shape-error", shapeError });

  if (!isObj(j)) return shape({ kind: "top-not-object", typeName: typeName(j) });
  if (!("hooks" in j)) return Object.assign(base, { status: "ok", emptyReason: "no-hooks" });
  if (!isObj(j.hooks)) return shape({ kind: "hooks-not-object", typeName: typeName(j.hooks) });

  const pre = j.hooks.PreToolUse;
  if (pre === undefined) return Object.assign(base, { status: "ok", emptyReason: "no-pretooluse" });
  if (!Array.isArray(pre)) return shape({ kind: "pretooluse-not-array", typeName: typeName(pre) });

  const candidates = [];
  for (let i = 0; i < pre.length; i++) {
    const entry = pre[i];
    if (!isObj(entry)) return shape({ kind: "entry-not-object", entryIndex: i, typeName: typeName(entry) });
    // 沒有 hooks 鍵的 entry 直接略過 —— 使用者可能有不相干的條目，不該把他們擋死。
    if (entry.hooks === undefined) continue;
    if (!Array.isArray(entry.hooks)) {
      return shape({ kind: "entry-hooks-not-array", entryIndex: i, typeName: typeName(entry.hooks) });
    }

    const hits = [];
    for (let k = 0; k < entry.hooks.length; k++) {
      const h = entry.hooks[k];
      if (!isObj(h)) return shape({ kind: "handler-not-object", entryIndex: i, handlerIndex: k, typeName: typeName(h) });
      if (h.command !== undefined && typeof h.command !== "string") {
        return shape({ kind: "command-not-string", entryIndex: i, handlerIndex: k, typeName: typeName(h.command) });
      }
      if (h.args !== undefined && !Array.isArray(h.args)) {
        return shape({ kind: "args-not-array", entryIndex: i, handlerIndex: k, typeName: typeName(h.args) });
      }
      const argv = [];
      if (Array.isArray(h.args)) {
        for (let a = 0; a < h.args.length; a++) {
          if (typeof h.args[a] !== "string") {
            return shape({
              kind: "args-element-not-string",
              entryIndex: i, handlerIndex: k, argIndex: a, typeName: typeName(h.args[a]),
            });
          }
          argv.push(h.args[a]);
        }
      }
      if (h.command === undefined && h.args === undefined) continue;

      // Claude Code 的 command hook 有兩種形態：
      //   shell form  { "type":"command", "command":"node /x/super-mode-consult-gate.js" }
      //   exec form   { "type":"command", "command":"node", "args":["/x/super-mode-consult-gate.js"] }
      // needle 兩邊都要看 —— 只看 `command` 的話，exec form 會被判成「沒有註冊」。
      const haystack = [h.command === undefined ? "" : h.command].concat(argv).join(" ");
      if (!haystack.includes(NEEDLE)) continue;

      // 命中字串還不夠：canonical 註冊是 `type:"command"`。只比 substring 會把
      // 「type 缺漏或不是 command」的條目也算成「gate 已接上」—— 那是自己製造假綠。
      if (h.type !== "command") {
        return shape({
          kind: "bad-type",
          entryIndex: i, handlerIndex: k,
          typeText: h.type === undefined ? "缺漏" : JSON.stringify(h.type),
        });
      }
      // shell form 走到這裡 `command` 必須是字串才算數得上一筆。
      // （command 非字串在上面就 fail 掉了，這條是防禦性的。）
      if (h.args === undefined && typeof h.command !== "string") {
        return shape({ kind: "no-usable-command", entryIndex: i, handlerIndex: k });
      }

      hits.push({
        entryIndex: i,
        handlerIndex: k,
        pointer: source.label + "#/hooks/PreToolUse/" + i + "/hooks/" + k,
        form: h.args === undefined ? "shell" : "exec",
        type: h.type,
        command: h.command === undefined ? null : h.command,
        args: h.args === undefined ? null : argv,
        unsafe: unsafeFieldsOf(h),
      });
    }

    if (!hits.length) continue;
    // matcher **只在這個 entry 真的掛著 gate 時**才驗型別：不相干的畸形 entry
    // 不該把使用者的 migration 擋死。
    if (entry.matcher !== undefined && typeof entry.matcher !== "string") {
      return shape({ kind: "matcher-not-string", entryIndex: i, typeName: typeName(entry.matcher) });
    }
    // siblings 只扣掉 shell-form candidate —— 與修正前的 `others` 定義一致
    // （exec form 存在時 probe 會先停手，所以這個差別觀察不到，但別悄悄改語意）。
    const shellHits = hits.filter((c) => c.form === "shell").length;
    const siblings = entry.hooks.length - shellHits;
    for (const c of hits) {
      candidates.push(Object.assign(c, {
        matcher: entry.matcher === undefined ? "" : entry.matcher,
        siblings,
      }));
    }
  }

  return Object.assign(base, { status: "ok", emptyReason: null, candidates });
}

// ── 共用的小工具 ─────────────────────────────────────────────────────────
const isBroken = (s) => s.status === "read-error" || s.status === "parse-error" || s.status === "shape-error";
const shellOf = (s) => s.candidates.filter((c) => c.form === "shell");
const execOf = (s) => s.candidates.filter((c) => c.form === "exec");

function identityKeys(cands) {
  const seen = [];
  for (const c of cands) {
    const key = JSON.stringify([c.matcher, c.command]);
    if (!seen.includes(key)) seen.push(key);
  }
  return seen;
}

// ── assessProbe ─────────────────────────────────────────────────────────
/*
 * probe 問的是：「gate 註冊了幾筆、在哪個檔、照文件能不能往下做。」
 *
 * exit 語義（文件的判斷分支一律以退出碼＋RESULT_CODE 為準）：
 *   0 = 判定可執行   1 = 讀不到／形狀不合／設定不安全，先修好再重跑   3 = 停手，要人工判斷
 *
 * 判定順序（precedence）—— 順序本身是語義的一部分：
 *   1. 形狀不合（含 bad-type）        exit 1   不知道在看什麼，什麼都別做
 *   2. **不安全欄位**                  exit 1   確定壞了，而且有明確修法
 *   3. exec form                       exit 3   本工具的辨識能力到不了
 *   4. 與別的 handler 共用 entry       exit 3   動它會影響不相干的 hook
 *   5. 多筆但 (matcher, command) 不一致 exit 3   不知道該留哪一筆
 *   6. 一般判定                        exit 0
 * 2 排在 3 前面是刻意的：「確定壞了＋有修法」比「無法判斷、請找人」對使用者更有用。
 */
function assessProbe(sources) {
  const main = scanSource(sources.main);
  const local = scanSource(sources.local);
  const scans = [main, local];
  const tag = (s) => (c) => Object.assign({ file: s.shortLabel }, c);
  const allShell = shellOf(main).map(tag(main)).concat(shellOf(local).map(tag(local)));
  const allExec = execOf(main).map(tag(main)).concat(execOf(local).map(tag(local)));
  const out = (code, exit, extra) =>
    Object.assign({ code, exit, scans, main, local, allShell, allExec }, extra || {});

  if (scans.some(isBroken)) return out("SHAPE_ERROR", 1);

  const unsafe = allShell.concat(allExec).filter((c) => c.unsafe.length);
  if (unsafe.length) return out("UNSAFE_FIELD", 1, { unsafe });

  if (allExec.length) return out("HALT_EXEC_FORM", 3);

  const shared = allShell.filter((c) => c.siblings > 0);
  if (shared.length) return out("HALT_SHARED_ENTRY", 3, { shared });

  const keys = identityKeys(allShell);
  if (allShell.length >= 2 && keys.length > 1) return out("HALT_INCONSISTENT", 3, { keys });

  const m = shellOf(main).length;
  const l = shellOf(local).length;
  if (m === 1 && l === 0) return out("OK_NORMAL", 0);
  if (m > 1) return out("OK_DUPLICATE_MAIN", 0, { count: m });
  if (m === 1 && l >= 1) return out("OK_BOTH", 0);
  if (m === 0 && l >= 1) return out("OK_LOCAL_ONLY", 0);
  return out("OK_NONE", 0);
}

// ── assessMatcher ───────────────────────────────────────────────────────
/*
 * matcher-contract 問的是**另一個問題**：「這份 settings 裡有沒有一筆可信的 gate 註冊，
 * 它的 `matcher` 是什麼？」——所以它有自己的 verdict，不共用 probe 的停手條件。
 *
 * 與 probe 刻意不同的兩點：
 *   ・`siblings > 0` **不是問題**。gate 和別的 handler 同一個 entry 時，matcher 照樣適用。
 *   ・多筆 gate 但 `matcher` 相同（`command` 不同）→ **PASS ＋ duplicate 診斷**。
 *     matcher 本身沒有歧義；重複註冊是 probe 的職責。在這裡也 FAIL 等於
 *     matcher-contract 又接手了 probe 的工作，並且無故弄壞既有使用者的驗證。
 */
function assessMatcher(input) {
  const scan = scanSource(input.settings);
  const out = (code, exit, extra) => Object.assign({ code, exit, scan }, extra || {});

  if (scan.status === "missing") return out("MISSING", 1);
  if (scan.status === "read-error") return out("UNREADABLE", 1);
  if (scan.status === "parse-error") return out("UNREADABLE", 1);
  if (scan.status === "shape-error") {
    // 同一個 scanner，兩種對映：bad-type 對 probe 是「形狀不合」，對 matcher-contract
    // 是它自己的具名 code —— 這正是先前設計裡 BAD_TYPE 不可達的那個洞。
    return out(scan.shapeError.kind === "bad-type" ? "BAD_TYPE" : "SHAPE_ERROR", 1);
  }

  const unsafe = scan.candidates.filter((c) => c.unsafe.length);
  if (unsafe.length) return out("UNSAFE_FIELD", 1, { unsafe });

  const exec = execOf(scan);
  const shell = shellOf(scan);
  // exec form 是官方支援的形態，不是畸形資料 —— 措辭是 UNSUPPORTED（本工具不支援），
  // 不是 INVALID。但只有 exec、沒有 shell 時才報它；混用時下面的歧義檢查更精確。
  if (exec.length && !shell.length) return out("UNSUPPORTED_EXEC_FORM", 1, { exec });
  if (!shell.length) return out("NO_GATE", 1);

  const keys = identityKeys(shell);
  const matchers = [];
  for (const c of shell) if (!matchers.includes(c.matcher)) matchers.push(c.matcher);
  if (matchers.length > 1) return out("AMBIGUOUS_MATCHER", 1, { matchers, shell });

  const chosen = shell[0];
  const dupes = shell.length > 1 || exec.length > 0;
  return out(dupes ? "OK_WITH_DUPLICATES" : "OK", 0, {
    matcher: chosen.matcher,
    where: chosen.pointer,
    duplicates: shell.length,
    exec,
    keys,
  });
}

// ── renderer ────────────────────────────────────────────────────────────
/*
 * **所有使用者看得到的中文句子都在這一段，而且只在這一段。**
 * 兩個 adapter 而不是一個 render()：probe 要雙檔盤點＋範圍 epilogue，
 * matcher 要 target attestation＋contract diff，硬塞成同一個函式只會長出旗標。
 *
 * 形狀不合的句子（`shapeSentence`）是**兩個 adapter 共用**的 —— 這正是重點：
 * 先前兩支工具各自造句，於是同一個畸形輸入在 probe 得到明確訊息、在 matcher-contract
 * 得到一段 uncaught TypeError 的 stack trace。
 */
const LABEL_PAD = 32;

const atOf = (e) => "PreToolUse[" + e.entryIndex + "]";
const hatOf = (e) => atOf(e) + ".hooks[" + e.handlerIndex + "]";

function shapeSentence(se) {
  switch (se.kind) {
    case "top-not-object": return "頂層不是物件（是 " + se.typeName + "）";
    case "hooks-not-object": return "hooks 不是物件（是 " + se.typeName + "）";
    case "pretooluse-not-array": return "hooks.PreToolUse 不是陣列（是 " + se.typeName + "）";
    case "entry-not-object": return atOf(se) + " 不是物件（是 " + se.typeName + "）";
    case "entry-hooks-not-array": return atOf(se) + ".hooks 不是陣列（是 " + se.typeName + "）";
    case "handler-not-object": return hatOf(se) + " 不是物件（是 " + se.typeName + "）";
    case "command-not-string": return hatOf(se) + ".command 不是字串（是 " + se.typeName + "）";
    case "args-not-array": return hatOf(se) + ".args 不是陣列（是 " + se.typeName + "）";
    case "args-element-not-string":
      return hatOf(se) + ".args[" + se.argIndex + "] 不是字串（是 " + se.typeName + "）";
    case "bad-type":
      return hatOf(se) + " 的 command 含 gate，但 type 是 " + se.typeText + "（必須是 \"command\"）";
    case "no-usable-command": return hatOf(se) + " 命中 gate 但沒有可用的 command 字串";
    case "matcher-not-string": return atOf(se) + ".matcher 不是字串（是 " + se.typeName + "）";
    default: return "未知的形狀問題：" + se.kind;
  }
}

// 每份 settings 一行盤點結果。
function scanLine(s) {
  const pad = s.label.padEnd(LABEL_PAD);
  if (s.status === "missing") return pad + "檔案不存在";
  if (s.status === "read-error") return pad + "讀取失敗：" + s.readCode;
  if (s.status === "parse-error") return pad + "JSON 解析失敗：" + s.parseMessage;
  if (s.status === "shape-error") return pad + "形狀不合：" + shapeSentence(s.shapeError);
  if (s.emptyReason === "no-hooks") return pad + "沒有 hooks 段 —— gate 條目：0 個";
  if (s.emptyReason === "no-pretooluse") return pad + "沒有 hooks.PreToolUse —— gate 條目：0 個";
  const ex = execOf(s).length;
  return pad + "gate 條目：" + shellOf(s).length + " 個" +
    (ex ? "（另有 " + ex + " 筆 exec form，見下）" : "");
}

// 不安全欄位的逐條說明。文案與 UNSAFE_FIELDS 表綁在一起，加欄位時這裡要一起加
// ——`tests/gate-registration.test.js` 有一條斷言會在漏掉時 FAIL。
const UNSAFE_WHY = {
  if: "把 gate 限縮到符合該規則的工具，其餘工具完全不受攔",
  once: "首次叫用後就被移除，之後整個 session 不設防",
  async: "非阻塞背景執行，PreToolUse 的 deny 來不及生效",
  asyncRewake: "非阻塞背景執行（多了 exit 2 喚醒），PreToolUse 的 deny 來不及生效",
};

/*
 * ⚠️ **範圍說明每一條退出路徑都要印。** 先前只在「有找到 gate」時才印，於是最需要看到它的
 * 那條路徑——找到 0 筆、接著 `AI-INSTALL` 步驟 2 會叫人新增一筆——反而看不到
 * 「needle 大小寫敏感」這個警告，而那正是 Windows 上製造重複註冊的入口。
 */
function scopeLines() {
  return [
    "",
    "⚠️ 本工具只數「gate 註冊了幾筆」，範圍刻意很窄：",
    "   ・只判斷 shell form；看到 exec form（handler 帶 args）一律停手，不做判斷",
    "   ・不驗 command 指到的檔案是否存在，也不驗 hook 真的會被叫起",
    "   ・needle 比對**大小寫敏感** —— Windows 上兩筆只差路徑大小寫、卻指向同一個檔的",
    "     重複註冊，本工具看不見。判「0 筆」時請先確認不是這種情況再新增。",
    "   ・**命中 needle 只代表「candidate」，不代表 gate 一定會被執行。**",
    "     例：command=\"echo super-mode-consult-gate\" 也含 needle，但它根本不跑 gate。",
    "     要排除這種假陽性得剖析 shell token，本工具刻意不做（記在 docs/backlog.md）。",
    "   ・它**不是 settings 的 schema 驗證器**。實際會驗、驗不過就非 0 的只有這些欄位：",
    "       PreToolUse 是陣列／每個 entry 是物件／entry.hooks 若存在是陣列／",
    "       每個 handler 是物件／handler.command 若存在是字串／handler.args 若存在是字串陣列。",
    "     命中 needle 之後才另外驗 handler.type === \"command\"（合法值有 command／http／",
    "     mcp_tool／prompt／agent，只有 command 會執行 command 欄位）、該 entry 的 matcher",
    "     型別，以及 if／once／async／asyncRewake 這幾個會讓 gate 不阻擋的欄位。",
    "     **不驗**的例子：沒有 hooks 鍵的 entry 直接略過；非 gate 的 handler 不驗 type 的型別，",
    "     也不驗 type:\"command\" 是否真的帶了 command —— 這些都會 exit 0 放行。",
  ];
}

function renderProbe(v) {
  const out = [scanLine(v.main), scanLine(v.local), ""];

  if (v.code === "SHAPE_ERROR") {
    // fail-closed：形狀不明時不可以讓人拿 exit 0 當成「已確認沒問題」
    out.push("判定：有檔案無法解析或形狀不合 —— 先修好再重跑，不要往下做。");
  } else if (v.code === "UNSAFE_FIELD") {
    for (const c of v.unsafe) {
      for (const f of c.unsafe) {
        out.push("  " + c.file + " " + hatOf(c) + "  帶 " + f.name + "=" + JSON.stringify(f.value));
      }
    }
    out.push("判定：設定不安全 —— gate 有註冊，但上面這些欄位會讓它不如預期阻擋。先修好再重跑。");
    const named = [];
    for (const c of v.unsafe) for (const f of c.unsafe) if (!named.includes(f.name)) named.push(f.name);
    for (const n of named) out.push("      " + n + "：" + UNSAFE_WHY[n]);
    out.push("      修法：**修改現有那一筆**（移除該欄位），不要 append 新的一筆 —— 重做安裝");
    out.push("      步驟 2 會多出第二筆註冊。改完重跑本 probe 與 matcher-contract --live。");
  } else if (v.code === "HALT_EXEC_FORM") {
    for (const c of v.allExec) {
      out.push("  " + c.file + " " + hatOf(c) + "  command=" + JSON.stringify(c.command) +
        "  args=" + JSON.stringify(c.args));
    }
    out.push("判定：停手 —— 上面是 exec form（handler 帶 `args`）的 gate 註冊，本工具無法判斷。請人工確認。");
    out.push("      理由：安裝流程規定必跑的 matcher-contract 目前也只看 `command`，會對它回報");
    out.push("      「沒有註冊本 hook」；而 `args` 存在與否會改變 runtime 語義，光比字串無法");
    out.push("      安全判斷兩筆註冊是不是同一筆。這裡若判「正常」或「沒有 gate」都會誤導。");
  } else if (v.code === "HALT_SHARED_ENTRY") {
    for (const c of v.shared) {
      out.push("  " + hatOf(c) + " 所在的 entry 底下還有 " + c.siblings + " 個非 gate 的 handler");
    }
    out.push("判定：停手 —— 含 gate 的條目底下還掛著其他 handler，動它會影響不相干的 hook。請人工判斷。");
  } else if (v.code === "HALT_INCONSISTENT") {
    out.push("  共 " + v.allShell.length + " 筆 gate handler，出現 " + v.keys.length + " 種不同的 (matcher, command)：");
    for (const k of v.keys) {
      const t = JSON.parse(k);
      out.push("    matcher=" + JSON.stringify(t[0]) + "  command=" + JSON.stringify(t[1]));
    }
    out.push("判定：停手 —— 多筆 gate handler 的 matcher／command 不一致，無法判斷該留哪一筆。請人工判斷。");
  } else if (v.code === "OK_NORMAL") {
    out.push("判定：正常，不用修。");
  } else if (v.code === "OK_DUPLICATE_MAIN") {
    out.push("判定：settings.json 裡有 " + v.count + " 筆 gate —— 已經重複註冊。做第 2 節的『B. 已經有一筆』。");
  } else if (v.code === "OK_BOTH") {
    out.push("判定：兩邊都有 —— **只要從 settings.local.json 移除**，不要搬。做第 2 節的『B. 已經有一筆』。");
  } else if (v.code === "OK_LOCAL_ONLY") {
    out.push("判定：受影響 —— gate 只在 local，從非家目錄啟動完全不生效。做第 2 節的『A. 還沒有』。");
  } else {
    out.push("判定：兩邊都沒有 gate —— 可能還沒安裝，或註冊在別處。照 AI-INSTALL 步驟 2 重做。");
  }

  // ⚠️ 明確劃出本 probe **不**負責的事。不寫出來的話，「判定：正常」會被當成
  // 「gate 一定會生效」，但 command 指到一個已經被刪掉的路徑時它照樣印「正常」。
  if (v.exit === 0 && v.allShell.length) {
    out.push("");
    out.push("已註冊的 gate handler：");
    for (const c of v.allShell) {
      out.push("  " + c.file + " " + hatOf(c) + "  command=" + JSON.stringify(c.command));
    }
    out.push("（端到端沒被 deny 時，先核對上面印出來的路徑還在不在——見下方範圍說明。）");
  }

  return out.concat(scopeLines(), ["", "RESULT_CODE=" + v.code]).join("\n");
}

/*
 * matcher-contract 的 adapter。`ctx` = { mode, settingsPath, hookPath }。
 *
 * **一律先印兩條實際受驗的路徑**，含早退路徑 —— 這支測試的整個價值在於「比對的是哪一對」，
 * 只印 PASS/FAIL 會讓人以為驗到了 live，其實驗的是 repo snippet（修正前就是這樣）。
 */
function matcherAttestation(ctx) {
  return [
    "受驗模式：   " + ctx.mode,
    "受驗 settings: " + ctx.settingsPath,
    "受驗 hook:     " + ctx.hookPath,
  ];
}

const FIX_NO_APPEND =
  "  修法：**修改／替換現有那一筆**，不要 append 新的一筆 —— 只重做 AI-INSTALL 步驟 2 會" +
  "\n        多出第二筆註冊。改完先跑 node tools/probe-gate-registration.js，再跑本測試 --live。";

function renderMatcher(v, ctx) {
  const s = v.scan;
  const out = [];
  if (v.code === "OK" || v.code === "OK_WITH_DUPLICATES") {
    if (v.code === "OK_WITH_DUPLICATES") {
      out.push("⚠️ 這份 settings 有 " + v.duplicates + " 筆 shell-form gate handler" +
        (v.exec.length ? "（另有 " + v.exec.length + " 筆 exec form）" : "") +
        "，matcher 相同所以本測試不擋。");
      out.push("   重複註冊是 probe 的職責：請跑 node tools/probe-gate-registration.js。");
    }
    return out.join("\n");
  }

  if (v.code === "MISSING") {
    out.push("FAIL: 找不到 " + s.path);
  } else if (v.code === "UNREADABLE") {
    out.push("FAIL: " + s.path + " " +
      (s.status === "read-error" ? "讀取失敗：" + s.readCode : "JSON 解析失敗：" + s.parseMessage));
  } else if (v.code === "SHAPE_ERROR" || v.code === "BAD_TYPE") {
    out.push("FAIL: " + s.path + " 形狀不合：" + shapeSentence(s.shapeError));
    if (v.code === "BAD_TYPE") {
      out.push("  Claude Code 的 type 合法值有 command／http／mcp_tool／prompt／agent，");
      out.push("  **只有 command 會執行 command 欄位** —— 其餘四種都等於 gate 不會被叫起。");
      out.push(FIX_NO_APPEND);
    }
  } else if (v.code === "UNSAFE_FIELD") {
    out.push("FAIL: " + s.path + " 裡的 gate 註冊帶了會讓它不阻擋的欄位：");
    for (const c of v.unsafe) {
      for (const f of c.unsafe) {
        out.push("  " + hatOf(c) + "  " + f.name + "=" + JSON.stringify(f.value) + " —— " + UNSAFE_WHY[f.name]);
      }
    }
    out.push(FIX_NO_APPEND);
  } else if (v.code === "UNSUPPORTED_EXEC_FORM") {
    out.push("FAIL: " + s.path + " 裡的 gate 是 exec form（handler 帶 args），本測試不支援。");
    out.push("  exec form 是 Claude Code 官方支援的形態，**不是**無效註冊 —— 但 args 存在與否");
    out.push("  會改變 runtime 語義，光比字串無法安全判斷。請跑 node tools/probe-gate-registration.js");
    out.push("  （它對 exec form 會 exit 3 並要求人工確認）。");
  } else if (v.code === "AMBIGUOUS_MATCHER") {
    out.push("FAIL: " + s.path + " 有 " + v.shell.length + " 筆 gate handler，但 matcher 不一致：");
    for (const m of v.matchers) out.push("  matcher=" + JSON.stringify(m));
    out.push("  本測試無法判斷該以哪一筆為準。請跑 node tools/probe-gate-registration.js");
    out.push("  （它會 exit 3 並列出衝突的註冊）。");
  } else {
    out.push("FAIL: " + s.path + " 裡沒有註冊本 hook");
    out.push("");
    out.push("hook 必須註冊在 ~/.claude/settings.json（user scope）。");
    out.push("⚠️ ~/.claude/settings.local.json 不是 user scope —— 只有從家目錄啟動 Claude Code 時");
    out.push("   才會被當成專案層檔案讀到，從其他目錄啟動就完全不生效。");
    out.push("若你剛照 AI-INSTALL 步驟 2 合併過，請確認合併的是 ~/.claude/settings.json。");
  }
  return out.join("\n");
}

module.exports = {
  NEEDLE,
  LEGAL_TYPES,
  UNSAFE_FIELDS,
  UNSAFE_WHY,
  sourceRaw,
  sourceMissing,
  sourceReadError,
  scanSource,
  assessProbe,
  assessMatcher,
  shapeSentence,
  scanLine,
  renderProbe,
  matcherAttestation,
  renderMatcher,
};
