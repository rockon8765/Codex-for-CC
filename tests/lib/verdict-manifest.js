#!/usr/bin/env node
/*
 * **獨立**的 code→exit manifest。
 *
 * ⚠️ 這份表是**手寫**的，刻意不從案例清單、也不從產品原始碼推導出來。理由：
 *
 *   ・若從**案例**推導 → 案例期望寫錯時（例如 exec form 五案釘成 `UNSUPPORTED_EXEC_FORM`
 *     卻配 exit 3），manifest 會跟著錯，交叉比對就變成自己跟自己比。
 *   ・若從**產品**推導 → 產品把配對改掉時 manifest 會靜默跟著改，抓不到漂移。
 *
 * 所以：手寫一份，然後**雙向**核對
 *   (a) 案例 ↔ manifest：案例用到的 code 都要在表內；表內的 code 都要有案例涵蓋（orphan 檢查）
 *   (b) manifest ↔ 產品：`assertMatchesSource()` 直接讀產品原始碼的 `out("CODE", exit)`
 *       宣告，逐筆核對，對不上就失敗
 *
 * exit 語義（三支工具共用）：
 *   0  判定正常
 *   1  判定有問題，要修
 *   2  呼叫方式錯誤（參數）
 *   3  停手：本工具無法判斷，需要人介入
 */
"use strict";

const fs = require("fs");
const path = require("path");

/**
 * probe（`tools/probe-gate-registration.js`）會印的所有 code。
 * 來源：`lib/gate-registration.js` 的 probe 判定函式 ＋ probe 自己的參數/環境守衛。
 */
const PROBE_EXIT_BY_CODE = {
  // ── 正常（exit 0）──
  OK_NORMAL: 0,
  OK_NONE: 0,
  OK_BOTH: 0,
  OK_LOCAL_ONLY: 0,
  OK_DUPLICATE_MAIN: 0,
  // ── 要修（exit 1）──
  SHAPE_ERROR: 1,
  HOOKS_DISABLED: 1,
  UNSAFE_FIELD: 1,
  CONFIG_DIR_OVERRIDE: 1,
  TOOL_INTEGRITY_ERROR: 1,
  INTERNAL_ERROR: 1,
  // ── 參數錯（exit 2）──
  BAD_ARGS: 2,
  // ── 停手（exit 3）──
  HALT_LOCAL_HOOKS_DISABLED: 3,
  HALT_EXEC_FORM: 3,
  HALT_SHARED_ENTRY: 3,
  HALT_INCONSISTENT: 3,
};

/**
 * matcher-contract（`<plat>/skills/超級模式/tests/matcher-contract.test.js`）的 code。
 *
 * ⚠️ `UNSUPPORTED_EXEC_FORM` 是 **matcher 的** code、exit 1；
 * probe 對同一種輸入印的是 `HALT_EXEC_FORM`、exit 3。**兩者不是同一個東西** ——
 * 把它們搞混正是 2026-08-09 那個靜默假綠的核心。
 */
const MATCHER_EXIT_BY_CODE = {
  OK: 0,
  OK_WITH_DUPLICATES: 0,
  MISSING: 1,
  UNREADABLE: 1,
  SHAPE_ERROR: 1,
  BAD_TYPE: 1,
  HOOKS_DISABLED: 1,
  UNSAFE_FIELD: 1,
  UNSUPPORTED_EXEC_FORM: 1,
  NO_GATE: 1,
  AMBIGUOUS_MATCHER: 1,
  MATCHER_DRIFT: 1,
  HOOK_UNREADABLE: 1,
  HOOK_UNPARSEABLE: 1,
  CONFIG_DIR_OVERRIDE: 1,
  TOOL_INTEGRITY_ERROR: 1,
  INTERNAL_ERROR: 1,
  BAD_ARGS: 2,
};

/*
 * `lib/gate-registration.js` 這**一個檔案**同時含 probe 與 matcher 兩支判定函式，
 * 所以掃它的 `out("CODE", exit)` 會同時得到兩邊的 code。
 * 對「原始碼 ↔ manifest」的核對必須用**聯集**，否則會把對方的 code 誤報成未登記。
 *
 * ⚠️ 兩邊共有的 code（`SHAPE_ERROR`／`HOOKS_DISABLED`／`UNSAFE_FIELD`）exit 必須一致，
 * 否則聯集本身就是矛盾的 —— 下面的建構程序會直接擋下來。
 */
const MODULE_EXIT_BY_CODE = (() => {
  const union = {};
  for (const [src, table] of [["probe", PROBE_EXIT_BY_CODE], ["matcher", MATCHER_EXIT_BY_CODE]]) {
    for (const [code, exit] of Object.entries(table)) {
      if (Object.prototype.hasOwnProperty.call(union, code) && union[code] !== exit) {
        throw new Error("manifest 聯集矛盾：" + code + " 在兩表分別是 exit " + union[code] + " 與 " + exit + "（來源 " + src + "）");
      }
      union[code] = exit;
    }
  }
  return union;
})();

/**
 * 從產品原始碼抽出 `out("CODE", exit)` 的宣告，與手寫 manifest 核對。
 * 抓的是「產品改了配對，manifest 沒跟上」以及反過來。
 *
 * 回傳 problems 陣列（空＝相符）。
 */
function assertMatchesSource(modulePath, manifest, opts) {
  const problems = [];
  const src = fs.readFileSync(modulePath, "utf8");
  const declared = {};
  const re = /\bout\(\s*"([A-Z_]+)"\s*,\s*(\d+)/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const code = m[1];
    const exit = Number(m[2]);
    if (Object.prototype.hasOwnProperty.call(declared, code) && declared[code] !== exit) {
      problems.push("產品原始碼對 " + code + " 宣告了兩種 exit：" + declared[code] + " 與 " + exit);
    }
    declared[code] = exit;
  }
  if (Object.keys(declared).length === 0) {
    problems.push("從 " + modulePath + " 抽不到任何 out(\"CODE\", exit) 宣告 —— 抽取方式已失效，不是「沒有漂移」");
    return problems;
  }
  // 產品宣告的每一筆都要在 manifest 內且相符
  for (const code of Object.keys(declared)) {
    if (!Object.prototype.hasOwnProperty.call(manifest, code)) {
      problems.push("產品會印 " + code + "，但 manifest 沒登記");
    } else if (manifest[code] !== declared[code]) {
      problems.push("配對漂移：產品 " + code + " → exit " + declared[code] + "，manifest 說 " + manifest[code]);
    }
  }
  // manifest 裡宣告「應由本模組產生」的 code，反向也要在產品裡找得到
  for (const code of (opts && opts.expectInSource) || []) {
    if (!Object.prototype.hasOwnProperty.call(declared, code)) {
      problems.push("manifest 宣告 " + code + " 由本模組產生，但原始碼裡找不到 —— 表過期了");
    }
  }
  return problems;
}

/**
 * 案例 ↔ manifest 的**雙向** orphan 檢查。
 *   usedCodes  案例實際用到的 code 集合
 * 回傳 problems（空＝雙向都對得上）。
 */
function crossCheckCases(usedCodes, manifest, opts) {
  const problems = [];
  const exempt = new Set((opts && opts.uncoveredOk) || []);
  for (const code of usedCodes) {
    if (!Object.prototype.hasOwnProperty.call(manifest, code)) {
      problems.push("案例用了 " + code + "，但 manifest 沒登記（拼錯，或用了另一支工具的 code）");
    }
  }
  for (const code of Object.keys(manifest)) {
    if (!usedCodes.has(code) && !exempt.has(code)) {
      problems.push("manifest 有 " + code + " 但沒有任何案例涵蓋（orphan —— 補案例，或在 uncoveredOk 明確豁免）");
    }
  }
  return problems;
}

module.exports = {
  PROBE_EXIT_BY_CODE,
  MATCHER_EXIT_BY_CODE,
  MODULE_EXIT_BY_CODE,
  assertMatchesSource,
  crossCheckCases,
};
