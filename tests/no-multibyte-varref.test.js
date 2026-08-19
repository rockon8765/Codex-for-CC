#!/usr/bin/env node
'use strict';
/*
 * no-multibyte-varref.test.js — 禁止 shell 腳本裡出現「$var 緊接非 ASCII 位元組」。
 *
 * 為什麼需要這條規則（2026-08-19，原生 macOS 驗證抓到）：
 *   macOS 的 /bin/bash 3.2.57 在某些 locale 下，會把緊鄰的多位元組字元**首位元組**
 *   當成變數名的可接受字元。於是
 *       echo "rc=$code）done"
 *   會被解析成變數 `code）` → `set -u` 之下是 unbound variable → 整支中止。
 *   修法就是加大括號界定名稱：`${code}）`。
 *
 * ⚠️ 觸發條件**不是**「UTF-8 locale」。macOS 端實測 en_US.ISO8859-1（charmap 不是
 *    UTF-8）同樣中招；C／US-ASCII 才安全。精確說法是「locale 讓 bash 把非 ASCII
 *    首位元組視為名稱可接受字元」。所以不要用 locale 名稱當判斷依據。
 *
 * ⚠️ 為什麼要靜態掃而不是靠測試：
 *    這個缺陷在 `bash -n` 下**完全看不出來**（語法合法），而且只在特定
 *    bash 版本 × locale 組合才發作 —— 開發機（Git Bash bash 5.3）**重現不出來**。
 *    也就是說「本機全綠」對這一類缺陷沒有證明力，只能靠原始碼層級的規則擋。
 *    本批先前已經吃過兩次同型的虧（PIPESTATUS 被賦值重設、`{ } >> file` 重導向
 *    失敗仍回 0），都是語法檢查看不出來、實跑才炸。
 *
 * 涵蓋範圍（刻意宣告，不要讀成「全 repo 都守住了」）：
 *   ✅ 所有 .sh
 *   ✅ docs/AI-INSTALL.md —— 它是**會被實際執行**的 canonical 安裝文件
 *   ❌ .ps1：PowerShell 實測不受影響（`$code）` 在 Set-StrictMode 下仍正常）
 *   ❌ .js：非 shell
 *   ❌ docs/ 底下的 plan／history 文件：純史料，不會被執行
 */

const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..');
// $ + 不加大括號的具名變數 + 緊接非 ASCII 位元組。
// ${var} 安全（大括號界定名稱）；$1 $? $@ 這類特殊參數也不在規則內。
const PAT = /\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]/g;
const EXTRA_FILES = ['docs/AI-INSTALL.md'];
const SKIP_DIRS = new Set(['.git', 'node_modules']);

function walk(dir, out) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.isDirectory()) {
      if (SKIP_DIRS.has(ent.name)) continue;
      walk(path.join(dir, ent.name), out);
    } else {
      out.push(path.join(dir, ent.name));
    }
  }
  return out;
}

const all = walk(REPO, []);
const targets = all.filter((p) => {
  const rel = path.relative(REPO, p).split(path.sep).join('/');
  return rel.endsWith('.sh') || EXTRA_FILES.includes(rel);
});

// 掃描面自我檢查：目標檔一個都沒有 → 一定是走錯目錄或 walk 壞了，
// 那時「0 個違規」是假綠。這條在 repo 結構被改動時會先叫。
const MIN_TARGETS = 10;
let violations = [];
for (const p of targets) {
  // 用 latin1 讀：一個 byte 一個 char，才對得上「非 ASCII 位元組」的判準。
  const buf = fs.readFileSync(p, 'latin1');
  const rel = path.relative(REPO, p).split(path.sep).join('/');
  let m;
  PAT.lastIndex = 0;
  while ((m = PAT.exec(buf)) !== null) {
    const line = buf.slice(0, m.index).split('\n').length;
    violations.push({ rel, line, frag: Buffer.from(m[0], 'latin1').toString('utf8') });
  }
}

console.log(`掃描 ${targets.length} 個檔（.sh 與 ${EXTRA_FILES.join(', ')}）`);

let failed = false;
if (targets.length < MIN_TARGETS) {
  console.log(`FAIL  掃描面異常：只找到 ${targets.length} 個目標檔（期望至少 ${MIN_TARGETS}）。` +
    `「0 個違規」在這種情況下是假綠。`);
  failed = true;
}
if (violations.length > 0) {
  failed = true;
  console.log(`FAIL  找到 ${violations.length} 處「$var 緊接非 ASCII」：`);
  for (const v of violations) {
    console.log(`  ${v.rel}:${v.line}  ${v.frag}   → 改成 \${${v.frag.replace(/^\$/, '').slice(0, -1)}}`);
  }
  console.log('');
  console.log('理由：macOS bash 3.2 在部分 locale 下會把多位元組字元的首位元組併進變數名，');
  console.log('      set -u 之下就是 unbound variable → 整支中止。加大括號即可。');
}

if (failed) {
  console.log('');
  console.log('RESULT_CODE=FAIL');
  process.exitCode = 1;
} else {
  console.log('PASS no-multibyte-varref');
  console.log('RESULT_CODE=OK');
}
