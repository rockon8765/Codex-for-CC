#!/usr/bin/env node
/*
 * `cli-outcome.js` 的**合成輸出**單元測試：不 spawn 任何程序、不碰檔案系統。
 *
 * ⚠️ **這裡刻意全部用手寫 literal 字串**，不 require 受測模組的 `MARKER_RE`、
 * 也不共用任何 fixture 產生器。理由：共用 oracle 是單點靜默失效，如果連它的測試
 * 都靠同一個 regex 造資料，那 regex 錯的時候兩邊會一起錯、一起綠。
 *
 * 每一案都對應一個**真實發生過**的假綠，不是想像出來的邊角案例：
 *   prose-fake-code      → gate-registration.js 散文裡的字面 RESULT_CODE=UNSUPPORTED_EXEC_FORM
 *   prefix-collision     → "RESULT_CODE=OK_WITH_DUPLICATES".includes("RESULT_CODE=OK") === true
 *   cross-stream-splice  → 舊 oracle 的 (stdout + stderr) 無分隔串接
 */
"use strict";

const {
  parseCliOutcome,
  legacyOutcome,
  compareCliOutcome,
  includesInAnyStream,
} = require("./cli-outcome.js");

let pass = 0;
const failed = [];

function check(id, cond, detail) {
  if (cond) { pass++; return; }
  failed.push(id);
  console.log("FAIL: " + id + (detail ? " — " + detail : ""));
}
/** 斷言 problems 裡有一條含指定關鍵字——比對「失敗原因」而不是只比「有沒有失敗」。 */
function hasProblem(res, needle) {
  return res.problems.some((p) => p.indexOf(needle) >= 0);
}

// ── 1. 正常路徑：marker 在 stdout 最後一行 ────────────────────────────────
{
  const r = {
    stdout: "判定：正常，不用修。\n\nRESULT_CODE=OK_NORMAL\n",
    stderr: "",
    status: 0,
    signal: null,
  };
  const res = parseCliOutcome(r);
  check("ok-stdout/ok", res.ok, res.problems.join("；"));
  check("ok-stdout/code", res.code === "OK_NORMAL", "得到 " + res.code);
  check("ok-stdout/stream", res.markerStream === "stdout", "得到 " + res.markerStream);
  check("ok-stdout/status", res.status === 0);
}

// ── 2. marker 在 stderr（BAD_ARGS 的真實形狀）─────────────────────────────
{
  const r = {
    stdout: "",
    stderr: "FAIL: 未知參數：--bogus\n用法：--repo | --live\n\nRESULT_CODE=BAD_ARGS\n",
    status: 2,
    signal: null,
  };
  const res = parseCliOutcome(r);
  check("ok-stderr/ok", res.ok, res.problems.join("；"));
  check("ok-stderr/code", res.code === "BAD_ARGS", "得到 " + res.code);
  check("ok-stderr/stream", res.markerStream === "stderr", "得到 " + res.markerStream);
}

// ── 3. 散文裡的假 code（FG-1 的真實形狀）──────────────────────────────────
// 舊 oracle `/RESULT_CODE=([A-Z_]+)/` 取第一筆會得到 UNSUPPORTED_EXEC_FORM，
// 正解必須得到最後那行的 HALT_EXEC_FORM。
{
  const r = {
    stdout:
      "⛔ 停手：settings 用的是 exec form。\n" +
      "      matcher-contract 對同一份輸入會回報 RESULT_CODE=UNSUPPORTED_EXEC_FORM，兩邊一致。\n" +
      "\n" +
      "RESULT_CODE=HALT_EXEC_FORM\n",
    stderr: "",
    status: 3,
    signal: null,
  };
  const res = parseCliOutcome(r);
  check("prose-fake-code/ok", res.ok, res.problems.join("；"));
  check("prose-fake-code/code", res.code === "HALT_EXEC_FORM",
    "抓到 " + res.code + "（散文那個假標記不該被抓走）");
}

// ── 4. 前綴碰撞：OK 不得冒充 OK_WITH_DUPLICATES ───────────────────────────
{
  const r = { stdout: "RESULT_CODE=OK_WITH_DUPLICATES\n", stderr: "", status: 0, signal: null };
  const res = parseCliOutcome(r);
  check("prefix-collision/code", res.code === "OK_WITH_DUPLICATES", "得到 " + res.code);
  // 精確相等：期望 OK 時必須失敗
  const problems = compareCliOutcome(res, { code: "OK", exit: 0 }, null);
  check("prefix-collision/rejected", problems.length > 0,
    "期望 OK、實測 OK_WITH_DUPLICATES，必須判失敗");
  check("prefix-collision/reason", problems.some((p) => p.indexOf("code=OK_WITH_DUPLICATES") >= 0),
    "失敗原因要指出 code 不符：" + problems.join("；"));
  // 反向：substring 寫法會放行——這一行說明我們正在防的是什麼
  check("prefix-collision/substring-would-pass",
    "RESULT_CODE=OK_WITH_DUPLICATES".includes("RESULT_CODE=OK") === true,
    "前提變了：substring 不再碰撞的話，這道防線的理由要重寫");
}

// ── 5. 零個 marker ───────────────────────────────────────────────────────
{
  const res = parseCliOutcome({ stdout: "什麼都沒有\n", stderr: "", status: 0, signal: null });
  check("zero-marker/not-ok", !res.ok);
  check("zero-marker/reason", hasProblem(res, "找不到任何錨定"), res.problems.join("；"));
  check("zero-marker/code-null", res.code === null);
}

// ── 6. 兩個 marker（同一 stream）──────────────────────────────────────────
{
  const res = parseCliOutcome({
    stdout: "RESULT_CODE=OK\n中間\nRESULT_CODE=SHAPE_ERROR\n",
    stderr: "", status: 0, signal: null,
  });
  check("two-markers-same-stream/not-ok", !res.ok);
  check("two-markers-same-stream/reason", hasProblem(res, "出現 2 次"), res.problems.join("；"));
}

// ── 7. 兩個 marker（跨 stream）────────────────────────────────────────────
{
  const res = parseCliOutcome({
    stdout: "RESULT_CODE=OK\n",
    stderr: "RESULT_CODE=INTERNAL_ERROR\n",
    status: 0, signal: null,
  });
  check("two-markers-cross-stream/not-ok", !res.ok);
  check("two-markers-cross-stream/reason", hasProblem(res, "出現 2 次"), res.problems.join("；"));
}

// ── 8. 跨 stream 拼接：串接才湊得出 marker，逐 stream 掃必須看不到 ─────────
{
  const res = parseCliOutcome({
    stdout: "尾巴沒有換行 RESULT_CODE=",
    stderr: "OK\n",
    status: 0, signal: null,
  });
  check("cross-stream-splice/not-ok", !res.ok,
    "串接成 RESULT_CODE=OK 也不該被認可");
  check("cross-stream-splice/reason", hasProblem(res, "找不到任何錨定"), res.problems.join("；"));
}

// ── 9. marker 存在但不是所在 stream 的最後非空行 ──────────────────────────
{
  const res = parseCliOutcome({
    stdout: "RESULT_CODE=OK\n後面還有話\n",
    stderr: "", status: 0, signal: null,
  });
  check("marker-not-last/not-ok", !res.ok);
  check("marker-not-last/reason", hasProblem(res, "不是 stdout 的最後一個非空行"), res.problems.join("；"));
}

// ── 10. CRLF：Windows 子程序輸出帶 \r，錨定不能因此失效 ────────────────────
{
  const res = parseCliOutcome({ stdout: "判定\r\n\r\nRESULT_CODE=OK_NONE\r\n", stderr: "", status: 0, signal: null });
  check("crlf/ok", res.ok, res.problems.join("；"));
  check("crlf/code", res.code === "OK_NONE", "得到 " + res.code);
}

// ── 11. spawn 不健康的三種形態 ────────────────────────────────────────────
{
  const e = parseCliOutcome({ stdout: "", stderr: "", status: null, signal: null, error: new Error("ENOENT") });
  check("spawn-error/not-ok", !e.ok);
  check("spawn-error/reason", hasProblem(e, "spawn 失敗"), e.problems.join("；"));

  const s = parseCliOutcome({ stdout: "RESULT_CODE=OK\n", stderr: "", status: null, signal: "SIGKILL" });
  check("signal/not-ok", !s.ok, "被信號砍掉不能算量到 verdict");
  check("signal/reason", hasProblem(s, "信號中止"), s.problems.join("；"));

  const n = parseCliOutcome({ stdout: "RESULT_CODE=OK\n", stderr: "", status: null, signal: null });
  check("null-status/not-ok", !n.ok);
  check("null-status/reason", hasProblem(n, "退出碼是 null"), n.problems.join("；"));
}

// ── 12. comparator：code 對但 exit 錯 ─────────────────────────────────────
{
  const res = parseCliOutcome({ stdout: "RESULT_CODE=HALT_EXEC_FORM\n", stderr: "", status: 1, signal: null });
  const problems = compareCliOutcome(res, { code: "HALT_EXEC_FORM", exit: 3 }, null);
  check("code-ok-exit-wrong/rejected", problems.length > 0);
  check("code-ok-exit-wrong/reason", problems.some((p) => p.indexOf("exit=1") >= 0), problems.join("；"));
}

// ── 13. comparator：manifest 契約 ─────────────────────────────────────────
{
  const MANIFEST = { OK: 0, HALT_EXEC_FORM: 3, SHAPE_ERROR: 1 };
  // 案例期望與實測一致，但兩者都違反 manifest → 仍要抓出來
  const res = parseCliOutcome({ stdout: "RESULT_CODE=HALT_EXEC_FORM\n", stderr: "", status: 1, signal: null });
  const problems = compareCliOutcome(res, { code: "HALT_EXEC_FORM", exit: 1 }, MANIFEST);
  check("manifest/catches-drift", problems.some((p) => p.indexOf("違反 code→exit 契約") >= 0),
    "案例與實測一致但違反全域契約時必須抓到：" + problems.join("；"));

  // 未登記的 code
  const res2 = parseCliOutcome({ stdout: "RESULT_CODE=BRAND_NEW\n", stderr: "", status: 0, signal: null });
  const p2 = compareCliOutcome(res2, { code: "BRAND_NEW", exit: 0 }, MANIFEST);
  check("manifest/catches-unregistered", p2.some((p) => p.indexOf("不在 manifest 裡") >= 0), p2.join("；"));

  // 完全合規
  const res3 = parseCliOutcome({ stdout: "RESULT_CODE=OK\n", stderr: "", status: 0, signal: null });
  check("manifest/clean", compareCliOutcome(res3, { code: "OK", exit: 0 }, MANIFEST).length === 0);
}

// ── 14. 量測不可信時，comparator 不得再往下推論 ───────────────────────────
{
  const res = parseCliOutcome({ stdout: "沒有標記\n", stderr: "", status: 0, signal: null });
  const problems = compareCliOutcome(res, { code: "OK", exit: 0 }, { OK: 0 });
  check("unreliable/stops", problems.length === res.problems.length,
    "解析失敗時不該再疊加 code/exit 的比對結論");
}

// ── 15. legacyOutcome：舊版沒有 marker 也不算失敗 ─────────────────────────
{
  const res = legacyOutcome({ stdout: "判定：正常，不用修。\n", stderr: "", status: 0, signal: null });
  check("legacy/ok", res.ok, res.problems.join("；"));
  check("legacy/code-na", res.code === "N/A", "得到 " + res.code);
  // 但 spawn 不健康仍要抓
  const bad = legacyOutcome({ stdout: "", stderr: "", status: null, signal: "SIGSEGV" });
  check("legacy/still-checks-health", !bad.ok);
}

// ── 16. includesInAnyStream：逐 stream，不串接 ────────────────────────────
{
  const res = parseCliOutcome({ stdout: "前段 ABC", stderr: "DEF 後段\n\nRESULT_CODE=OK\n", status: 0, signal: null });
  check("includes/finds-in-stderr", includesInAnyStream(res, "DEF 後段"));
  check("includes/finds-in-stdout", includesInAnyStream(res, "前段 ABC"));
  check("includes/no-splice", !includesInAnyStream(res, "ABCDEF"),
    "跨 stream 串接出來的字串不該被視為存在");
}

console.log("");
console.log("TOTAL " + (pass + failed.length) + "  PASS " + pass + "  FAIL " + failed.length);
if (failed.length) {
  console.log("失敗的案子：" + failed.join(", "));
  process.exitCode = 1;
}
