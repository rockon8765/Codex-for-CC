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
 * 已知範圍：symlink／reparse point 一律拒絕備份（複製會把它實體化，回滾時就用那個
 * 普通版本蓋回去，等於在你不知情下改掉佈局）。Windows 上 junction 也帶 reparse 屬性，
 * `lstat().isSymbolicLink()` 認得。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");

const die = (msg) => {
  console.error(msg + "，中止（未產生任何備份）");
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
for (const item of plan) {
  try {
    fs.copyFileSync(item.src, item.bak, fs.constants.COPYFILE_EXCL);
  } catch (e) {
    die("複製 " + item.src + " 失敗：" + e.code);
  }
  if (sha(item.src) !== sha(item.bak)) die(item.bak + " 備份不完整（雜湊不符）");
  console.log(item.bak + "  OK");
}

console.log("backup ts=" + ts);
