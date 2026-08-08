#!/usr/bin/env node
/*
 * backup-settings —— 在手動編輯 settings 之前，備份 `~/.claude/settings.json` 與
 * `~/.claude/settings.local.json`。三平台共用（`node tools/backup-settings.js`）。
 *
 * 為什麼是一支 Node 而不是 bash ＋ PowerShell 兩份：
 *   `MIGRATION` 第 2 節的 **B 分支（重複註冊）三平台都會用到**，而 B 會**刪除**
 *   `settings.local.json` 裡的 gate handler。先前只有 bash 版備份，Windows 使用者
 *   被導去用 `AI-INSTALL` 步驟 1b —— 但 1b 是「安裝前的三件式備份」，它**只備
 *   `settings.json`**，正好漏掉 B 真正會刪的那個檔，而且會因為 skill 樹裡不相干的
 *   link 而中止。同一段備份邏輯寫成兩份 shell 版本則遲早演化到不一致，
 *   這個 repo 已經為此付過兩次代價。
 *
 * **fail-fast，而且是「先全部預檢、再全部複製」**：任何一步失敗就中止並回非 0，
 * **不會印出 `backup ts=`**。所以「有印出 ts」才等於「該備份的都完成且逐位元組比對過」。
 * 預檢與複製分兩段，是為了避免「第一個檔備份成功、第二個檔中止」的半完成狀態。
 *
 * 退出碼：0 = 全部完成（或本來就沒有檔案要備份）；1 = 中止，未產生任何備份。
 *
 * **已知範圍（不要當成比實際更強的保證）**：
 *   ・**不是交易式的。** 預檢到複製之間若有人把來源換成 symlink、或建立了預檢時
 *     還不存在的 settings 檔，本工具不會察覺。`copyFileSync` 本身也不保證原子性。
 *     它假設你在自己的機器上手動操作、沒有並行的安裝程序在動同一批檔案。
 *     唯一真的關掉的 race 是**目的檔撞名**（`COPYFILE_EXCL`，不會覆蓋既有備份）。
 *   ・symlink 一律拒絕備份（複製會把它實體化，還原時就用那個普通版本蓋回去，
 *     等於在你不知情下改掉佈局）。Windows 上**一般的 drive-letter junction** 帶
 *     reparse 屬性、`lstat().isSymbolicLink()` 認得；但 **Volume GUID 掛載點不會**
 *     被認成 link，會退回一般 stat —— 那種情況下最後一段若是掛載目錄，
 *     仍會被「不是一般檔案」擋下，但**不要宣稱所有 reparse 都攔得到**。
 *   ・只處理這兩個 settings 檔，不碰 hook 與 skill 目錄。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");

// 預檢階段的中止：此時什麼都還沒建立，所以「未產生任何備份」是真的。
const die = (msg) => {
  console.error(msg + "，中止（未產生任何備份）");
  process.exit(1);
};

// 複製階段的中止：前面的檔案可能已經備好了，所以**不能**照抄上面那句話。
// 這裡把本次已建立的備份刪掉再中止，讓「全部成功，或什麼都沒留下」成為固定不變量
// ——刪掉是安全的：來源檔完全沒被動過，這些備份是本次剛建的。
const dieAfterCopy = (msg, created) => {
  const removed = [];
  const stuck = [];
  for (const p of created) {
    try {
      fs.unlinkSync(p);
      removed.push(p);
    } catch (e) {
      stuck.push(p + "（" + e.code + "）");
    }
  }
  console.error(msg + "，中止");
  if (removed.length) console.error("  已回收本次建立的備份：" + removed.join("、"));
  if (stuck.length) console.error("  ⚠️ 這些備份刪不掉，請自行處理：" + stuck.join("、"));
  if (!removed.length && !stuck.length) console.error("  （未產生任何備份）");
  process.exit(1);
};

const two = (n) => String(n).padStart(2, "0");
const d = new Date();
const ts =
  String(d.getFullYear()) + two(d.getMonth() + 1) + two(d.getDate()) + "-" +
  two(d.getHours()) + two(d.getMinutes()) + two(d.getSeconds());

const home = os.homedir();
const targets = [
  path.join(home, ".claude", "settings.json"),
  path.join(home, ".claude", "settings.local.json"),
];

const sha = (p) => crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");

// ── 第一段：全部預檢，不動任何東西 ────────────────────────────────────
const plan = [];
for (const f of targets) {
  let st;
  try {
    st = fs.lstatSync(f); // lstat，不跟隨 link
  } catch (e) {
    if (e.code === "ENOENT") {
      console.log(f + "  不存在，略過");
      continue;
    }
    die(f + " 狀態讀取失敗：" + e.code);
  }
  if (st.isSymbolicLink()) die(f + " 是 symlink／reparse point，狀態不明");
  if (!st.isFile()) die(f + " 存在但不是一般檔案");

  const bak = f + ".bak-" + ts;
  let exists = true;
  try {
    fs.lstatSync(bak);
  } catch (e) {
    if (e.code === "ENOENT") exists = false;
    else die(bak + " 狀態讀取失敗：" + e.code);
  }
  // 撞名就停，不要覆蓋既有備份（同一秒重跑會撞到，等一秒再跑）
  if (exists) die("已存在 " + bak + "（同一秒重跑？等一秒再試）");

  plan.push({ src: f, bak });
}

if (!plan.length) {
  console.log("沒有需要備份的 settings 檔。");
  console.log("backup ts=" + ts);
  process.exit(0);
}

// ── 第二段：複製並逐位元組比對 ────────────────────────────────────────
// 不變量：**要嘛全部備份成功，要嘛什麼都沒留下。** 中途失敗會回收本次建立的備份。
const created = [];
for (const item of plan) {
  try {
    // COPYFILE_EXCL：預檢到這裡之間若有人搶先建了同名檔，這裡會 EEXIST 而不是覆蓋掉它。
    fs.copyFileSync(item.src, item.bak, fs.constants.COPYFILE_EXCL);
  } catch (e) {
    dieAfterCopy("複製 " + item.src + " 失敗：" + e.code, created);
  }
  created.push(item.bak);
  if (sha(item.src) !== sha(item.bak)) dieAfterCopy(item.bak + " 備份不完整（雜湊不符）", created);
  console.log(item.bak + "  OK");
}

console.log("backup ts=" + ts);
