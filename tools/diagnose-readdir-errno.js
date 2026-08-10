#!/usr/bin/env node
/*
 * **原生診斷**：`fs.readFileSync()` 對一個**目錄**實際丟出的 `e.code` 是什麼。
 *
 * ── 為什麼需要這一支（F8 證據鏈）──────────────────────────────────────────
 *
 * 兩支驗證工具在「settings.json 其實是個目錄」時都要走 `UNREADABLE`／`SHAPE_ERROR`
 * 路徑，而那條路徑依賴 `readFileSync(dir)` 會丟出 `EISDIR`。
 *
 * ⚠️ **既有測試證明不了這件事，先前 handoff 與 README 說「BSD 若不是 EISDIR 會被測試抓到」
 * 是假話。** 具體地說：
 *   ・`tests/gate-registration.test.js` 的 `A14` 是
 *     `probe(readErr(L_MAIN, "EISDIR"))` —— 把字串 `"EISDIR"` 當**資料**注入純函式，
 *     它在任何 OS 上都綠，根本沒碰過檔案系統。
 *   ・`matcher-contract-cli` 的 `live-is-directory` 只驗「讀取失敗：」**前綴**，
 *     錯誤碼是什麼都通得過。
 *
 * 所以要驗真的 errno，只能像這支一樣**真的去讀一個目錄**。
 *
 * 用法：
 *   node tools/diagnose-readdir-errno.js            # 不符預期就 exit 1
 *   node tools/diagnose-readdir-errno.js --report   # 只回報，一律 exit 0
 *
 * 輸出（機器可讀，最後一行）：
 *   READ_DIR_CODE=<code>
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

let reportOnly = false;
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--report") reportOnly = true;
  else { console.error("未知參數：" + process.argv[i]); process.exitCode = 2; return; }
}

/* 產品實際依賴的錯誤碼。三平台目前都預期 EISDIR（Linux 與 macOS 已各自實測）。 */
const EXPECTED = "EISDIR";

const work = fs.mkdtempSync(path.join(os.tmpdir(), "readdir-errno-"));
const target = path.join(work, "settings.json");
fs.mkdirSync(target); // 刻意把「該是檔案的路徑」做成目錄

let code = null;
let message = null;
try {
  fs.readFileSync(target, "utf8");
  code = "(沒有丟例外)";
} catch (e) {
  code = e && e.code ? e.code : "(例外沒有 code)";
  message = e && e.message ? e.message : String(e);
}
fs.rmSync(work, { recursive: true, force: true });

console.log("平台：      " + process.platform + " " + os.release() + "  Node " + process.version);
console.log("讀取目標：  <tmp>/settings.json（實際是目錄）");
console.log("錯誤訊息：  " + (message || "(無)"));
console.log("預期錯誤碼：" + EXPECTED);
console.log("");

if (code !== EXPECTED) {
  console.log("⚠️ 實測錯誤碼與預期**不同**。");
  console.log("   產品的 UNREADABLE／SHAPE_ERROR 路徑依賴這個錯誤碼，請照實回報，");
  console.log("   **不要改測試去迎合** —— 這代表該平台需要各自的處理。");
  if (!reportOnly) process.exitCode = 1;
}

console.log("READ_DIR_CODE=" + code);
