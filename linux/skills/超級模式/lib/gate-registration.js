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
 * 根本不會 gate 的輸入：頂層 `disableAllHooks: true`、`if`、`async`、`asyncRewake`、
 * `timeout: 0`（官方 settings JSON schema 對它是 `exclusiveMinimum: 0`，違反就整份被拒絕載入）、
 * 以及 `command:"echo <needle>"`（substring 假陽性，**刻意保留**，見範圍說明）。
 * 另有 `CLAUDE_CONFIG_DIR` 這個「驗錯目標」的路徑（見下方 CONFIG_DIR_ENV）。
 *
 * ⚠️ **`once` 不在這張清單上。** 我一度把它列為不安全並讓兩支工具 exit 1，那是**誤紅**
 * ——官方明訂它在 settings 檔會被忽略。理由與教訓見下方 `IGNORED_IN_SETTINGS`。
 * 詳見 docs/backlog.md。
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
 *   async        非阻塞背景執行 → PreToolUse deny gate 根本不能 deny
 *   asyncRewake  同上（只是多了 exit 2 喚醒）
 *
 * policy：
 *   "present"  只要欄位存在（值非 undefined）就算不安全 —— `if` 屬此類，
 *              任何規則字串都是一種限縮。
 *   "truthy"   只有真值才算 —— `async:false` 是明確關閉，無害。
 *
 * **刻意不列**：
 *   once                     官方明訂 settings 檔裡會被忽略 → 擋它是誤紅，見 IGNORED_IN_SETTINGS
 *   shell / statusMessage    不影響 gate 能否阻擋，放行並保留
 *   timeout                  **不在這裡判「多小算太小」**（官方沒記載），但 scanner 會驗它
 *                            必須是 > 0 的數字 —— 那是官方 JSON schema 的硬門檻，見 bad-timeout
 */
const UNSAFE_FIELDS = [
  { name: "if", policy: "present" },
  { name: "async", policy: "truthy" },
  { name: "asyncRewake", policy: "truthy" },
];

/*
 * **`once` 刻意不在上面那張表裡，而且不准再加回去。**
 *
 * 2026-08-09 的合併前審查抓到：本檔一度把 `once:true` 列為不安全並讓兩支工具 exit 1。
 * 那是**誤紅**——官方 hooks reference 明講 `once`
 * 「Only honored for hooks declared in skill frontmatter; **ignored in settings files**
 * and agent frontmatter」。settings 檔裡的 `once` 根本不生效，所以它既不會讓 gate 失效，
 * 也不該讓既有使用者的安裝驗收由綠變紅。
 *
 * 這個錯誤的來源值得記下來：第一次查官方文件時，摘要把 `once` 列成「所有 hook type 通用」
 * 而**漏掉了那句限定**。教訓＝欄位語義要看原文的限定子句，不要只看欄位表。
 *
 * `tests/gate-registration.test.js` 有一條斷言釘住「`once:true` 必須放行」。
 */
const IGNORED_IN_SETTINGS = ["once"];

/*
 * `disableAllHooks: true` —— settings 的**總開關**，把所有 hook 一起關掉。
 * 官方 settings 文件：「Disable all hooks and any custom status line」；
 * hooks 文件另註明它遵循 managed settings 階層（managed 層的 hook 只有 managed 層關得掉）。
 *
 * 這是 open-world schema 的一個**例外**，必須具名擋下：它是「JSON 完全合法、gate 註冊完全
 * 正確、但 gate 一定不會被叫起」的最乾淨案例。修正前兩支工具都印「正常／PASS」。
 *
 * ⚠️ 範圍誠實：本模組只看 caller 餵進來的檔案。專案層 `.claude/settings.json` 或
 * managed 層若設了這個旗標，這裡看不到。
 */
const KILL_SWITCH = "disableAllHooks";

/*
 * `CLAUDE_CONFIG_DIR` —— 官方環境變數，**覆寫整個設定目錄**。
 * 官方 `.claude` 目錄頁：設定它之後「every `~/.claude` path on this page lives under
 * that directory instead」。
 *
 * 對本 repo 的實害：probe 與 `matcher-contract --live` 都用 `os.homedir()/.claude` 解路徑，
 * 所以變數一設，它們驗的是 Claude **不會讀**的那一份 —— 而且 attestation 會印出那條路徑，
 * 等於產出一份**假的**「我驗的是 live」證明。這正是本批要消滅的那一類缺陷。
 *
 * **處置：偵測到非空值就 fail-closed，不猜語義。** 刻意不做「有變數就改用它」的解析，
 * 理由是本 repo 對它的邊角語義（相對路徑、尾斜線、指向不存在的目錄）沒有實測依據，
 * 猜錯會製造出**另一個**錯誤目標 —— 而錯誤目標正是這條的問題本身。
 * 使用者的出路有兩條：unset 之後重跑，或用 `--settings <p> --hook <p>` 明確指定。
 * 記在 docs/backlog.md（正解是單一 config-root resolver，讓安裝流程也共用）。
 */
const CONFIG_DIR_ENV = "CLAUDE_CONFIG_DIR";

// 回傳被設定的值（trim 後非空）或 null。caller 傳 process.env 進來，模組自己不碰 process。
function configDirOverride(env) {
  const v = env && env[CONFIG_DIR_ENV];
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" ? null : t;
}

function renderConfigDirRefusal(value, what) {
  return [
    "⛔ CONFIG_DIR_OVERRIDE —— 偵測到 " + CONFIG_DIR_ENV + "，" + what + "**沒有做任何判斷**。",
    "   " + CONFIG_DIR_ENV + "=" + JSON.stringify(value),
    "   這個環境變數會**覆寫整個設定目錄**：Claude Code 讀的不是 ~/.claude，而是上面那個目錄。",
    "   本工具目前一律用 ~/.claude 解路徑，所以繼續下去會驗到一份 Claude 不會讀的檔案，",
    "   並且印出一條看起來像 live 卻不是的路徑 —— 假的驗證比沒有驗證更糟，所以這裡停手。",
    "   出路二選一：",
    "     1. unset " + CONFIG_DIR_ENV + " 之後重跑（要驗的就是預設的 ~/.claude 時）",
    "     2. 用 --settings <你的 settings.json> --hook <你的 hook.js> 明確指定那一對",
    "        （probe 目前沒有對應旗標，記在 docs/backlog.md）",
    "",
    "RESULT_CODE=CONFIG_DIR_OVERRIDE",
  ].join("\n");
}

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
    killSwitch: false,
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
  // 總開關要在任何「gate 註冊得好不好」的判斷**之前**記下來 —— 它一開，後面全部無意義。
  // 只認 `true`（`"true"`／1 之類不是官方形態，不替使用者猜）。
  // 型別要驗：`"true"`／`1` 這種**不是**官方形態，不替使用者猜成啟用；但也不能當成 false
  // 靜默忽略 —— 那等於「我看到一個我依賴的欄位型別錯了，卻假裝沒看到」。報型別錯。
  if (KILL_SWITCH in j && typeof j[KILL_SWITCH] !== "boolean") {
    return shape({ kind: "kill-switch-not-boolean", typeName: typeName(j[KILL_SWITCH]) });
  }
  base.killSwitch = j[KILL_SWITCH] === true;
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
      /*
       * `timeout` 必須是 finite number 且 **> 0**。
       * 這不是「極小值來不來得及」的 runtime 推測 —— 官方發布的 settings JSON schema
       * 對 hook 的 timeout 明定 `{"type":"number","exclusiveMinimum":0}`，
       * 而官方另說 user/project/local settings **驗證失敗會整份拒絕載入**。
       * 所以 `timeout: 0` 或負值或字串 ＝ 整份 settings 無效 ＝ gate 根本不存在，
       * 修正前這裡卻回 OK/exit 0（假綠）。
       * ⚠️ **任何正值都放行**：官方沒有記載「多小算來不及」，不自行發明門檻。
       */
      if (h.timeout !== undefined) {
        if (typeof h.timeout !== "number" || !isFinite(h.timeout) || h.timeout <= 0) {
          return shape({
            kind: "bad-timeout",
            entryIndex: i, handlerIndex: k,
            typeText: JSON.stringify(h.timeout),
          });
        }
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

  // 總開關排在所有「註冊得好不好」的判定之前 —— 它一開，gate 註冊得再完美也不會被叫起。
  if (main.killSwitch) return out("HOOKS_DISABLED", 1);
  /*
   * ⚠️ `settings.local.json` 裡的總開關**不能靜默忽略**。
   *
   * 「local 不是 user scope」是對的（2026-07-28 macOS 實測），但那句話的完整版是：
   * 家目錄那份**只有在從家目錄啟動時**生效 —— 而那時它就是專案層的 local settings，
   * **且 local 覆蓋 user**。所以「main 有正確的 gate ＋ local 設了 disableAllHooks:true」
   * 這個組合在從家目錄啟動時，gate 是被關掉的。
   * 修正前這裡回 OK_NORMAL（「正常，不用修」）—— 依啟動目錄而定的假綠。
   *
   * 判 exit 3（停手）而不是 1：它是否咬人取決於使用者的啟動目錄，本工具看不到那件事，
   * 所以這需要人工判斷，不是一條機械修法。
   */
  if (local.killSwitch) return out("HALT_LOCAL_HOOKS_DISABLED", 3);

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

  // 總開關：使用者明確指定要驗這一份，所以不論它是哪一份，看到就擋。
  if (scan.killSwitch) return out("HOOKS_DISABLED", 1);

  const unsafe = scan.candidates.filter((c) => c.unsafe.length);
  if (unsafe.length) return out("UNSAFE_FIELD", 1, { unsafe });

  const exec = execOf(scan);
  const shell = shellOf(scan);
  // exec form 是官方支援的形態，不是畸形資料 —— 措辭是 UNSUPPORTED（本工具不支援），
  // 不是 INVALID。但只有 exec、沒有 shell 時才報它；混用時下面的歧義檢查更精確。
  if (exec.length && !shell.length) return out("UNSUPPORTED_EXEC_FORM", 1, { exec });
  if (!shell.length) return out("NO_GATE", 1);

  const keys = identityKeys(shell);
  // ⚠️ matcher 集合要算**全部** candidate，不能只算 shell form。
  // 2026-08-09 合併前審查抓到的假綠：canonical shell 一筆 ＋ matcher 不同的 exec 一筆
  // → 只算 shell 會得到「只有一種 matcher」→ OK_WITH_DUPLICATES exit 0，
  // renderer 還會宣稱「matcher 相同」。那直接違反本模組自己宣告的規則
  //（多筆 gate 且 matcher 不一致 → AMBIGUOUS_MATCHER）。
  const matchers = [];
  for (const c of scan.candidates) if (!matchers.includes(c.matcher)) matchers.push(c.matcher);
  if (matchers.length > 1) return out("AMBIGUOUS_MATCHER", 1, { matchers, shell, exec });

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
    case "kill-switch-not-boolean":
      return KILL_SWITCH + " 不是布林（是 " + se.typeName + "）—— 官方形態只有 true／false，" +
        "這裡不替你猜；型別錯的設定不該被當成「沒設」放行";
    case "bad-timeout":
      return hatOf(se) + " 的 timeout 是 " + se.typeText +
        "（必須是 > 0 的數字）—— 官方 settings JSON schema 對 timeout 明定 exclusiveMinimum: 0，" +
        "而驗證失敗的 settings 會整份被拒絕載入，等於 gate 根本不存在";
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
    "     另外會驗頂層的 " + KILL_SWITCH + "（true ＝ 所有 hook 停用，具名擋下）；",
    "     命中 needle 之後才驗 handler.type === \"command\"（合法值有 command／http／",
    "     mcp_tool／prompt／agent，只有 command 會執行 command 欄位）、該 entry 的 matcher",
    "     型別，以及 if／async／asyncRewake 這幾個會讓 gate 不阻擋的欄位。",
    "     ⚠️ **不驗** once —— 官方明訂它在 settings 檔會被忽略（只對 skill frontmatter 生效），",
    "     所以在這裡擋它是誤紅。也不驗 timeout 的大小（極小值可能讓 gate 來不及回應，",
    "     但本 repo 尚未用真 runtime 證實，不憑推測擋人）。",
    "     **不驗**的例子：沒有 hooks 鍵的 entry 直接略過；非 gate 的 handler 不驗 type 的型別，",
    "     也不驗 type:\"command\" 是否真的帶了 command —— 這些都會 exit 0 放行。",
  ];
}

function renderProbe(v) {
  const out = [scanLine(v.main), scanLine(v.local), ""];

  if (v.code === "SHAPE_ERROR") {
    // fail-closed：形狀不明時不可以讓人拿 exit 0 當成「已確認沒問題」
    out.push("判定：有檔案無法解析或形狀不合 —— 先修好再重跑，不要往下做。");
  } else if (v.code === "HOOKS_DISABLED") {
    out.push("判定：**所有 hook 都被停用** —— settings.json 設了 " + KILL_SWITCH + ": true。");
    out.push("      gate 就算註冊得完全正確也不會被叫起。把它移除或改成 false 再重跑。");
    out.push("      官方說明是「Disable all hooks and any custom status line」。");
    out.push("      ⚠️ 本工具只看家目錄那兩個檔：專案層 .claude/settings.json 或 managed 層");
    out.push("      若也設了這個旗標，這裡看不到。");
  } else if (v.code === "HALT_LOCAL_HOOKS_DISABLED") {
    out.push("判定：停手 —— settings.local.json 設了 " + KILL_SWITCH + ": true。");
    out.push("      家目錄那份**只在你從家目錄啟動 Claude Code 時**才生效，但那時它就是專案層的");
    out.push("      local settings，**而 local 覆蓋 user** —— 所以那種情況下你 settings.json 裡的");
    out.push("      gate 是被關掉的。是否咬到你取決於你的啟動目錄，本工具看不到，所以請人工判斷：");
    out.push("      ・平常從家目錄啟動 → 把 local 那個旗標移除（或改 false）");
    out.push("      ・平常從專案目錄啟動 → 這一筆對 gate 無影響，但留著遲早誤導人");
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
    out.push("      理由：`args` 存在與否會改變 runtime 語義（直接 exec vs 經 shell），");
    out.push("      光比字串無法安全判斷兩筆註冊是不是同一筆。這裡若判「正常」或「沒有 gate」都會誤導。");
    // ⚠️ 這裡**刻意不寫** `RESULT_CODE=<CODE>` 字面。那是機器介面的保留命名空間，
    // 整份輸出只准出現一次（最後那行真標記）。散文裡寫出來的話，會被未錨定的
    // oracle 抓成假標記 —— 2026-08-09 的靜默假綠就是這樣來的：
    // 五個 exec form 案子釘成 UNSUPPORTED_EXEC_FORM 仍然 PASS，因為 oracle 抓到了這一行。
    out.push("      matcher-contract 對同一份輸入也會停手，但它的 code 是 UNSUPPORTED_EXEC_FORM");
    out.push("      （exit 1）；本工具是 HALT_EXEC_FORM（exit 3）。結論一致，code 與退出碼刻意不同。");
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

// ── matcher 的 runtime 語義 ───────────────────────────────────────────────
/*
 * **這一段的存在理由是修正前的比對方式與 runtime 不一致。**
 *
 * 官方 hooks reference 的 matcher 判定規則：
 *   `"*"`／`""`／省略                                  → 全部匹配
 *   只含字母、數字、`_`、`-`、空白、`,`、`|`            → 精確字串，或以 `|`／`,` 分隔的精確清單
 *   **含其他任何字元 → JavaScript 正規表達式（unanchored）**
 *
 * 關鍵事實：本 repo 的 canonical matcher 含 `mcp__.*` 的 `.` 與 `*`，
 * 所以它**走的是 regex 路徑**，不是精確清單。修正前這支測試一律
 * `split("|").map(trim)` 當精確清單比，剛好得到相同答案（因為每個 alternative 都是純名字），
 * 但那是巧合而非等價。合併前審查給出的反例：把 canonical matcher 寫成
 * `Edit | Write | … | mcp__.*`（`|` 兩側加空白）——
 *   ・舊比法：trim 之後清單一致 → **PASS**
 *   ・runtime：仍是 regex，alternative 變成 `Edit `／` Write `，帶字面空白，
 *     所以 `Edit`、`Write`、`Bash`、`mcp__foo__bar` 全都不匹配 → **gate 從不執行**
 * 所以現在改成**依規則判定走哪條路，再用該條路的語義實際比對**。
 */
const LIST_SAFE_RE = /^[A-Za-z0-9_\-,| \t]*$/;
// 反向檢查用的代表性 MCP 工具名。用「明顯是範例」的名字，避免有人以為它是真工具。
const MCP_PROBE = "mcp__example__do_thing";

function evaluateMatcher(matcher) {
  const raw = matcher === undefined || matcher === null ? "" : String(matcher);
  if (raw === "*" || raw.trim() === "") return { kind: "all", raw, names: [] };
  if (LIST_SAFE_RE.test(raw)) {
    return { kind: "list", raw, names: raw.split(/[|,]/).map((s) => s.trim()).filter(Boolean) };
  }
  let regex = null;
  let regexError = null;
  try {
    regex = new RegExp(raw);
  } catch (e) {
    regexError = e.message;
  }
  // regex 路徑下仍抽出「看起來像字面工具名」的 alternative，供反向檢查用。
  // ⚠️ 這是**啟發式**：regex 的 alternative 不一定是字面名字。正向檢查用真的比對，
  // 反向檢查只能盡力而為 —— 文案要如實說。
  return { kind: "regex", raw, names: raw.split("|").map((s) => s.trim()).filter(Boolean), regex, regexError };
}

/*
 * 契約比對：hook 要攔的每個工具名，在**runtime 的語義下**都必須被 matcher 命中。
 * 回傳結構化 problems，由 renderMatcherContract 產生文案。
 */
function checkMatcherContract(matcher, required) {
  const ev = evaluateMatcher(matcher);
  const problems = [];
  if (ev.kind === "regex" && !ev.regex) {
    problems.push({ code: "REGEX_INVALID", params: { error: ev.regexError } });
    return { ok: false, ev, problems };
  }
  const hits = (name) =>
    ev.kind === "all" ? true : ev.kind === "list" ? ev.names.includes(name) : ev.regex.test(name);

  for (const name of required) if (!hits(name)) problems.push({ code: "MISSING_TOOL", params: { name } });
  if (!hits(MCP_PROBE)) problems.push({ code: "MISSING_MCP", params: { probe: MCP_PROBE } });

  /*
   * 反向檢查：matcher 不該出現 hook 不認識的**字面**工具名（避免只改 matcher 卻忘了改 hook）。
   *
   * ⚠️ **只有正向涵蓋是 hard gate；反向在 regex 路徑下只能盡力而為。**
   * 合併前審查給的反例是一個與 canonical **語義等價**的寫法：
   *     ^(?:Edit|Write|…|Monitor|mcp__.*)$
   * 正向 `RegExp.test()` 全數命中，但 `raw.split("|")` 會產出 `^(?:Edit` 與 `mcp__.*)$`
   * 這種**片段**，修正前把它們當成「不認識的工具名」→ `MATCHER_DRIFT`。
   * 那是正式安裝驗收的**誤紅**，不只是文案不精確。
   *
   * 現在的規則：只有「長得就是一個純工具名」的 alternative（`^[A-Za-z0-9_]+$`）
   * 才拿去比對 —— 所以 `…|NoSuchTool` 仍然抓得到。含 regex 元字元的片段一律歸為
   * **無法可靠反解析**，回一則 `UNVERIFIABLE_REGEX` **警告**（不影響 ok）。
   */
  const warnings = [];
  if (ev.kind !== "all") {
    const known = required.concat(["mcp__.*"]);
    const PLAIN = /^[A-Za-z0-9_]+$/;
    const unparsable = [];
    for (const alt of ev.names) {
      if (known.includes(alt)) continue;
      if (ev.kind === "list" || PLAIN.test(alt)) problems.push({ code: "UNKNOWN_ALT", params: { alt } });
      else unparsable.push(alt);
    }
    if (unparsable.length) warnings.push({ code: "UNVERIFIABLE_REGEX", params: { fragments: unparsable } });
  }
  return { ok: problems.length === 0, ev, problems, warnings };
}

// ── matcher-contract 的 renderer ─────────────────────────────────────────
/*
 * `ctx.kind` 是**機械值**（`"repo"` / `"live"` / `"explicit"`），`ctx.mode` 是給人看的字串。
 * 兩者分開的理由：**每一條修復建議都必須依受驗目標而不同。**
 * 重構時我一度只留 `mode`，於是 `--repo` 模式下「待出貨的 snippet 壞了」也會得到
 * 「hook 必須註冊在 ~/.claude/settings.json、注意 settings.local.json 不是 user scope、
 * 請確認你合併的是…」這一整段——全部不合語境，而且比修正前**更差**
 *（舊版對 repo 佈局本來有一句正確的「這是待出貨的檔案」）。
 * 合併前審查進一步指出：不只 `NO_GATE`，`BAD_TYPE`／`UNSAFE_FIELD`／exec／ambiguous
 * 也都固定叫人「重跑 probe 與 --live」，而那在 repo／explicit 模式下驗的是另一個目標。
 */
const KINDS = ["repo", "live", "explicit"];

function nextStep(kind) {
  if (kind === "repo") {
    return "  下一步：這是**待出貨的檔案**，不是你的個人設定。請回報維護者，先不要安裝。";
  }
  if (kind === "explicit") {
    return "  下一步：受驗路徑就印在上面。修那一份，再用**同一組** --settings/--hook 重跑。";
  }
  return "  下一步：先跑 node tools/probe-gate-registration.js（它會看兩個檔並數筆數），" +
    "\n        照它印的判定與 docs/AI-INSTALL.md 步驟 2 修，然後重跑本測試 --live。";
}

function fixNoAppend(kind) {
  if (kind !== "live") return nextStep(kind);
  return "  修法：**修改／替換現有那一筆**，不要 append 新的一筆 —— 只重做 AI-INSTALL 步驟 2 會" +
    "\n        多出第二筆註冊。\n" + nextStep(kind);
}

function renderMatcher(v, ctx) {
  const s = v.scan;
  const out = [];
  if (v.code === "OK" || v.code === "OK_WITH_DUPLICATES") {
    if (v.code === "OK_WITH_DUPLICATES") {
      out.push("⚠️ 這份 settings 有 " + v.duplicates + " 筆 shell-form gate handler" +
        (v.exec.length ? "（另有 " + v.exec.length + " 筆 exec form）" : "") +
        "。它們的 matcher 相同，所以本測試不擋。");
      out.push("   重複註冊是 probe 的職責：請跑 node tools/probe-gate-registration.js。");
    }
    return out.join("\n");
  }

  if (v.code === "HOOKS_DISABLED") {
    out.push("FAIL: " + s.path + " 設了 " + KILL_SWITCH + ": true —— **所有 hook 都被停用**。");
    out.push("  gate 就算註冊得完全正確也不會被叫起。這是 settings 的總開關，");
    out.push("  官方說明是「Disable all hooks and any custom status line」。");
    out.push("  把它移除或改成 false 之後再重跑。");
    out.push("  ⚠️ 本測試只看上面那一份檔案：專案層 .claude/settings.json 或 managed 層若也設了，這裡看不到。");
    out.push(nextStep(ctx.kind));
  } else if (v.code === "MISSING") {
    out.push("FAIL: 找不到 " + s.path);
    out.push(nextStep(ctx.kind));
  } else if (v.code === "UNREADABLE") {
    out.push("FAIL: " + s.path + " " +
      (s.status === "read-error" ? "讀取失敗：" + s.readCode : "JSON 解析失敗：" + s.parseMessage));
    out.push(nextStep(ctx.kind));
  } else if (v.code === "SHAPE_ERROR" || v.code === "BAD_TYPE") {
    out.push("FAIL: " + s.path + " 形狀不合：" + shapeSentence(s.shapeError));
    if (v.code === "BAD_TYPE") {
      out.push("  Claude Code 的 type 合法值有 command／http／mcp_tool／prompt／agent，");
      out.push("  **只有 command 會執行 command 欄位** —— 其餘四種都等於 gate 不會被叫起。");
      out.push(fixNoAppend(ctx.kind));
    } else {
      out.push(nextStep(ctx.kind));
    }
  } else if (v.code === "UNSAFE_FIELD") {
    out.push("FAIL: " + s.path + " 裡的 gate 註冊帶了會讓它不阻擋的欄位：");
    for (const c of v.unsafe) {
      for (const f of c.unsafe) {
        out.push("  " + hatOf(c) + "  " + f.name + "=" + JSON.stringify(f.value) + " —— " + UNSAFE_WHY[f.name]);
      }
    }
    out.push(fixNoAppend(ctx.kind));
  } else if (v.code === "UNSUPPORTED_EXEC_FORM") {
    out.push("FAIL: " + s.path + " 裡的 gate 是 exec form（handler 帶 args），本測試不支援。");
    out.push("  exec form 是 Claude Code 官方支援的形態，**不是**無效註冊 —— 但 args 存在與否");
    out.push("  會改變 runtime 語義，光比字串無法安全判斷。");
    out.push(nextStep(ctx.kind));
  } else if (v.code === "AMBIGUOUS_MATCHER") {
    const total = v.shell.length + v.exec.length;
    out.push("FAIL: " + s.path + " 有 " + total + " 筆 gate handler（shell " + v.shell.length +
      "、exec " + v.exec.length + "），但 matcher 不一致：");
    for (const m of v.matchers) out.push("  matcher=" + JSON.stringify(m));
    out.push("  本測試無法判斷該以哪一筆為準。");
    out.push(nextStep(ctx.kind));
  } else {
    out.push("FAIL: " + s.path + " 裡沒有註冊本 hook");
    out.push("");
    if (ctx.kind === "repo") {
      out.push("這是**待出貨的 settings.snippet.json**，不是你的個人設定 —— 它自己就該註冊本 hook。");
      out.push("**不要安裝**，也不要拿家目錄的 settings 來掩蓋它；請回報維護者。");
      out.push("（若你其實想驗的是已安裝的那一份，請改用 --live。）");
    } else if (ctx.kind === "live") {
      out.push("hook 必須註冊在 ~/.claude/settings.json（user scope）。");
      out.push("⚠️ ~/.claude/settings.local.json 不是 user scope —— 只有從家目錄啟動 Claude Code 時");
      out.push("   才會被當成專案層檔案讀到，從其他目錄啟動就完全不生效。");
      out.push(nextStep(ctx.kind));
    } else {
      out.push("你用 --settings 明確指定了這一份，但它裡面沒有 command 含本 hook 檔名的 handler。");
      out.push(nextStep(ctx.kind));
    }
  }
  return out.join("\n");
}

const CONTRACT_SENTENCE = {
  REGEX_INVALID: (p) => "matcher 含 regex 專用字元，但編不成正規表達式：" + p.error,
  MISSING_TOOL: (p) => "matcher 命中不了 " + p.name + " → hook 不會被叫起，該工具的攔截等於沒生效",
  MISSING_MCP: (p) => "matcher 命中不了 MCP 工具（測試名 " + p.probe + "）→ 所有 MCP 工具都不會進 hook",
  UNKNOWN_ALT: (p) => "matcher 多出 hook 不認識的項目 " + p.alt + " → 只改了 matcher 卻沒改 hook？",
};

/*
 * matcher 契約失敗的修法**不能導向 probe**。合併前審查抓到的具體誤導鏈：
 * matcher 缺 `Edit` → 這裡正確 FAIL → 舊文案叫人「跑 probe」→ probe 不驗 matcher 語義、
 * 回「判定：正常，不用修。」→ `AI-INSTALL` 的矩陣又規定看到那句就什麼都不做
 * → 使用者照著走一圈，回到原點而且以為沒事。
 * 所以這裡給的是「改 matcher 本身、用同一個目標重驗」，不提 probe。
 */
function contractFix(kind) {
  if (kind === "repo") {
    return "  修法：改**與受測檔相鄰**的 settings.snippet.json 的 matcher（它是待出貨的檔案）。" +
      "\n        改完重跑同一條 --repo。這一步不要碰你的 ~/.claude。";
  }
  if (kind === "explicit") {
    return "  修法：改上面印出的那一份 settings 的 matcher，再用**同一組** --settings/--hook 重驗。";
  }
  return "  修法：改 ~/.claude/settings.json 裡**現有那一筆** gate 的 matcher，" +
    "\n        **不要 append 新的一筆**（會變成重複註冊）。改完重跑同一條 --live。" +
    "\n        ⚠️ 這條**不要**去跑 probe —— probe 不驗 matcher 語義，它會回「正常，不用修」，" +
    "\n        那會讓你以為沒事。probe 管的是「註冊了幾筆、在哪」，不是 matcher 對不對。";
}

function renderMatcherContract(res, ctx, required) {
  const out = [];
  for (const p of res.problems) {
    out.push("FAIL: " + (CONTRACT_SENTENCE[p.code] ? CONTRACT_SENTENCE[p.code](p.params) : p.code));
  }
  for (const w of res.warnings || []) {
    if (w.code === "UNVERIFIABLE_REGEX") {
      out.push("⚠️ UNVERIFIABLE_REGEX：matcher 走 regex 路徑，下列片段無法可靠反解析成工具名，");
      out.push("   因此**只驗了正向涵蓋**（每個工具名都真的被命中），沒有驗「有沒有多出不認識的工具」：");
      for (const f of w.params.fragments) out.push("     " + JSON.stringify(f));
    }
  }
  if (!res.ok) {
    out.push("");
    out.push("matcher 現值:   " + JSON.stringify(res.ev.raw));
    // 印出「runtime 會怎麼解讀它」——這是修正前完全看不到、卻決定一切的資訊。
    out.push("runtime 解讀為: " + (
      res.ev.kind === "all" ? "全部匹配（\"*\" 或空字串）"
        : res.ev.kind === "list" ? "精確清單（只含字母／數字／_／-／空白／, ／| ）"
          : "**JavaScript 正規表達式（unanchored）** —— 因為它含上述以外的字元"
    ));
    if (res.ev.kind === "regex") {
      out.push("                ⚠️ regex 路徑下，`|` 兩側的空白會變成 regex 的字面內容。");
      out.push("                例：`Edit | Write` 的第一個 alternative 是 `Edit `（含尾空白），");
      out.push("                所以工具名 `Edit` **不會**被命中。");
    }
    out.push("hook 清單:      " + required.join("|") + "|mcp__.*");
    out.push(contractFix(ctx.kind));
  }
  return out.join("\n");
}

module.exports = {
  NEEDLE,
  LEGAL_TYPES,
  UNSAFE_FIELDS,
  UNSAFE_WHY,
  IGNORED_IN_SETTINGS,
  KILL_SWITCH,
  CONFIG_DIR_ENV,
  configDirOverride,
  renderConfigDirRefusal,
  KINDS,
  MCP_PROBE,
  sourceRaw,
  sourceMissing,
  sourceReadError,
  scanSource,
  assessProbe,
  assessMatcher,
  evaluateMatcher,
  checkMatcherContract,
  shapeSentence,
  scanLine,
  renderProbe,
  renderMatcher,
  renderMatcherContract,
  nextStep,
  contractFix,
};
