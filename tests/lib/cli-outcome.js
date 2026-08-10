#!/usr/bin/env node
/*
 * 從一個子程序結果萃取 verdict —— **兩支驗證工具共用的唯一 oracle**。
 *
 * 為什麼存在：2026-08-09 macOS 驗證後發現兩支測試的 oracle 各自不忠實，
 * 而且是**同一個病的兩種長法**：
 *
 *   1. `probe-verdict-cases.test.js` 用 `/RESULT_CODE=([A-Z_]+)/`（未錨定、非 global）
 *      取第一筆 → 抓到 `gate-registration.js` **散文裡**的字面
 *      `RESULT_CODE=UNSUPPORTED_EXEC_FORM`，而不是最後那行真標記
 *      `RESULT_CODE=HALT_EXEC_FORM`。五個 exec form 案子因此靜默假綠。
 *   2. `matcher-contract-cli.test.js` 用 `out.includes("RESULT_CODE=OK")` 當 oracle，
 *      而 `"RESULT_CODE=OK_WITH_DUPLICATES".includes("RESULT_CODE=OK")` 為 **true**
 *      → 前綴碰撞放行；且 `stdout + stderr` 是**無分隔串接**，跨 stream 拼接
 *      也可能湊出一個假標記。
 *
 * 所以萃取邏輯只能有一份。⚠️ 但共用 oracle 是**單點靜默失效**：它錯的話兩支測試會
 * 一起假綠。獨立性靠三層，不是靠複製兩份 parser：
 *   (a) 本檔用**完全合成**的字串釘死（`cli-outcome.test.js`，不 spawn、不共用 fixture 產生器）；
 *   (b) 每個 caller 各自的端對端變異注入；
 *   (c) 案例期望 ↔ 獨立 code→exit manifest 的**雙向** orphan 檢查。
 *
 * ── 契約 ──────────────────────────────────────────────────────────────
 * `parseCliOutcome` 只做**解析**，不做語意判斷；「code 對但 exit 錯」由
 * `compareCliOutcome` 負責。硬把兩者塞進同一個函式，就會變成無法單獨驗證配對。
 *
 * ⚠️ **不要宣稱「marker 是整個程序的最後一行」。** `spawnSync` 拿到的是兩個獨立
 * pipe 的內容，無法可靠重建它們的全域先後順序。能斷言的只有
 * 「marker 是**它所在那個 stream** 的最後一個非空行」。
 */
"use strict";

/** 錨定的標記樣式：整行只能是 `RESULT_CODE=<CODE>`。 */
const MARKER_RE = /^RESULT_CODE=([A-Z_]+)$/;

/** 把 CRLF 正規化掉——Windows 的子程序輸出會帶 \r，否則錨定 `$` 會對不上。 */
function normalize(s) {
  return String(s == null ? "" : s).replace(/\r\n/g, "\n");
}

function nonEmptyLines(text) {
  return text.split("\n").filter((l) => l.trim() !== "");
}

/**
 * 掃單一 stream，回傳所有錨定 marker 及其是否為該 stream 的最後非空行。
 */
function scanStream(name, raw) {
  const text = normalize(raw);
  const lines = text.split("\n");
  const markers = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(MARKER_RE);
    if (m) markers.push({ stream: name, code: m[1], line: i + 1 });
  }
  const ne = nonEmptyLines(text);
  const last = ne.length ? ne[ne.length - 1] : null;
  return { name, text, markers, lastNonEmpty: last, isEmpty: ne.length === 0 };
}

/**
 * `parseCliOutcome(spawnResult)` —— 收 `spawnSync` 的結果物件本身，
 * 不收五個位置參數（那種簽章一次漏傳 `stderr`／`error`／`signal` 就靜默降級）。
 *
 * 回傳：
 *   { ok, code, status, markerStream, streams, problems }
 * `ok:false` 時 `code` 為 null，`problems` 說明為什麼不能信這次量測。
 */
function parseCliOutcome(r) {
  const problems = [];
  const out = scanStream("stdout", r && r.stdout);
  const err = scanStream("stderr", r && r.stderr);

  // ── 先確認這次 spawn 本身是健康的；不健康就不要假裝量到了東西 ──
  if (!r || typeof r !== "object") {
    return { ok: false, code: null, status: null, markerStream: null, streams: { out, err }, problems: ["spawn 結果不是物件"] };
  }
  if (r.error) problems.push("spawn 失敗：" + (r.error.message || String(r.error)));
  if (r.signal != null) problems.push("子程序被信號中止：" + r.signal);
  if (r.status === null || r.status === undefined) {
    if (!r.error && r.signal == null) problems.push("退出碼是 null（子程序未正常結束，且未回報 error／signal）");
  }

  // ── 標記唯一性：跨兩個 stream 合計恰一筆 ──
  const all = out.markers.concat(err.markers);
  if (all.length === 0) {
    problems.push("找不到任何錨定的 RESULT_CODE 行（整行必須恰為 RESULT_CODE=<CODE>）");
  } else if (all.length > 1) {
    problems.push(
      "錨定 RESULT_CODE 出現 " + all.length + " 次（必須恰一次）：" +
      all.map((m) => m.stream + ":" + m.line + "=" + m.code).join(", ")
    );
  }

  let code = null;
  let markerStream = null;
  if (all.length === 1) {
    const m = all[0];
    code = m.code;
    markerStream = m.stream;
    // marker 必須是**它所在 stream** 的最後一個非空行。
    const owner = m.stream === "stdout" ? out : err;
    if (owner.lastNonEmpty !== "RESULT_CODE=" + m.code) {
      problems.push(
        "RESULT_CODE 不是 " + m.stream + " 的最後一個非空行（實際最後一行：" +
        JSON.stringify(owner.lastNonEmpty) + "）"
      );
    }
  }

  return {
    ok: problems.length === 0,
    code,
    status: r.status,
    markerStream,
    streams: { out, err },
    problems,
  };
}

/**
 * `legacyOutcome(spawnResult)` —— 反向驗證專用。
 *
 * ⚠️ **刻意不是 `parseCliOutcome` 的寬鬆旗標。** 用
 * `parseCliOutcome(r, { allowMissingMarker: true })` 那種寫法，一次誤傳就會把
 * 現行契約整個降級成「marker 可有可無」。所以走**獨立函式**：
 * 舊版 probe 根本沒有 `RESULT_CODE`（`5da2624` 的 probe 實測不含該字串），
 * 這裡只驗 spawn 健康與退出碼，code 一律標 `N/A`。
 */
function legacyOutcome(r) {
  const problems = [];
  const out = scanStream("stdout", r && r.stdout);
  const err = scanStream("stderr", r && r.stderr);
  if (!r || typeof r !== "object") {
    return { ok: false, code: "N/A", status: null, streams: { out, err }, problems: ["spawn 結果不是物件"] };
  }
  if (r.error) problems.push("spawn 失敗：" + (r.error.message || String(r.error)));
  if (r.signal != null) problems.push("子程序被信號中止：" + r.signal);
  if (r.status === null || r.status === undefined) {
    if (!r.error && r.signal == null) problems.push("退出碼是 null");
  }
  return { ok: problems.length === 0, code: "N/A", status: r.status, streams: { out, err }, problems };
}

/**
 * `compareCliOutcome(actual, expected, exitByCode)` —— 語意層。
 *
 *   actual      parseCliOutcome() 的結果
 *   expected    { code, exit }（逐案宣告）
 *   exitByCode  獨立的 code→exit manifest（**不是**從案例推導出來的）
 *
 * 三件事分開驗，任何一件不合都要能單獨指出來：
 *   1. code 精確相等（`===`，不是 substring —— OK 不得冒充 OK_WITH_DUPLICATES）
 *   2. exit 精確相等
 *   3. 全域契約：實測 code 對應的 exit 必須符合 manifest
 *      （抓「案例期望寫錯」與「產品把 code/exit 配對改掉」兩種漂移）
 */
function compareCliOutcome(actual, expected, exitByCode) {
  const problems = actual.problems.slice();
  if (!actual.ok) return problems; // 量測本身不可信，不要再往下推論

  if (actual.code !== expected.code) {
    problems.push("code=" + actual.code + "（預期 " + expected.code + "）");
  }
  if (actual.status !== expected.exit) {
    problems.push("exit=" + actual.status + "（預期 " + expected.exit + "）");
  }
  if (exitByCode) {
    if (!Object.prototype.hasOwnProperty.call(exitByCode, actual.code)) {
      problems.push("實測 code " + actual.code + " 不在 manifest 裡（manifest 過期，或產品新增了未登記的 code）");
    } else if (exitByCode[actual.code] !== actual.status) {
      problems.push(
        "違反 code→exit 契約：manifest 說 " + actual.code + " 應為 exit " +
        exitByCode[actual.code] + "，實測 " + actual.status
      );
    }
  }
  return problems;
}

/** 逐 stream 搜尋字串——取代 `(stdout + stderr).includes(...)` 的無分隔串接。 */
function includesInAnyStream(actual, needle) {
  return actual.streams.out.text.includes(needle) || actual.streams.err.text.includes(needle);
}

module.exports = {
  MARKER_RE,
  normalize,
  scanStream,
  parseCliOutcome,
  legacyOutcome,
  compareCliOutcome,
  includesInAnyStream,
};
