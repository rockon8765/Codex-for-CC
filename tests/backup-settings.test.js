#!/usr/bin/env node
/*
 * tools/backup-settings.js 的回歸案。三平台共用（純 Node）。
 *
 * 每個案子開一個假 HOME，跑子程序，斷言**退出碼 ＋ 輸出 ＋ 檔案系統實際狀態**。
 * 只看退出碼不夠：這支工具的價值在「失敗時不留半完成狀態」，那必須查檔案系統。
 *
 * ⚠️ symlink 案在**無法建立 symlink 的環境**（Windows 非管理員）會標成 SKIP 並計入
 * 摘要，**不會靜默跳過**——靜默跳過等於假綠。macOS／Linux 上它一定要真的跑到。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

// --strict：有任何 SKIP 就回非 0。CI 用它 —— 否則「SKIP 後照樣 exit 0」等於把
// 沒驗到的守衛包成綠燈，而 CI 只看退出碼。
const strict = process.argv.includes("--strict");
for (const arg of process.argv.slice(2)) {
  if (arg !== "--strict") {
    console.error("未知參數：" + arg);
    process.exit(2);
  }
}

const tool = path.join(__dirname, "..", "tools", "backup-settings.js");
if (!fs.existsSync(tool)) {
  console.error("找不到：" + tool);
  process.exit(2);
}
console.log("受測工具：" + tool);

const work = fs.mkdtempSync(path.join(os.tmpdir(), "backup-settings-"));
let pass = 0;
const failed = [];
const skipped = [];

function newHome(name) {
  const h = path.join(work, name);
  fs.mkdirSync(path.join(h, ".claude"), { recursive: true });
  return h;
}
// fixedMs：用 --require 預載固定時鐘，讓子程序的 `new Date()` 停在指定時刻。
// 這樣「同一秒撞名」可以確定性觸發，不必賭時鐘。
function run(home, fixedMs) {
  const args = fixedMs === undefined
    ? [tool]
    : ["--require", path.join(__dirname, "helpers", "fixed-clock.js"), tool];
  const env = Object.assign({}, process.env, { HOME: home, USERPROFILE: home });
  if (fixedMs !== undefined) env.FIXED_CLOCK_MS = String(fixedMs);
  const r = spawnSync(process.execPath, args, { encoding: "utf8", env });
  return { status: r.status, out: (r.stdout || "") + (r.stderr || "") };
}

// 與 tools/backup-settings.js 相同的時間戳格式（本地時區、到秒）
function tsOf(ms) {
  const two = (x) => String(x).padStart(2, "0");
  const d = new Date(ms);
  return (
    String(d.getFullYear()) + two(d.getMonth() + 1) + two(d.getDate()) + "-" +
    two(d.getHours()) + two(d.getMinutes()) + two(d.getSeconds())
  );
}
function baks(home) {
  return fs.readdirSync(path.join(home, ".claude")).filter((f) => f.includes(".bak-")).sort();
}
function check(id, fn) {
  const problems = [];
  try {
    fn((cond, msg) => { if (!cond) problems.push(msg); });
  } catch (e) {
    problems.push("測試本身拋出：" + e.message);
  }
  if (problems.length) {
    failed.push(id);
    console.log("FAIL: " + id + " — " + problems.join("；"));
  } else {
    pass++;
  }
}

const MAIN = '{"hooks":{"PreToolUse":[]}}';
const LOCAL = '{"permissions":{"allow":["Bash(ls:*)"]}}';

check("both-files", (a) => {
  const h = newHome("both");
  fs.writeFileSync(path.join(h, ".claude", "settings.json"), MAIN);
  fs.writeFileSync(path.join(h, ".claude", "settings.local.json"), LOCAL);
  const r = run(h);
  a(r.status === 0, "退出碼 " + r.status + "（預期 0）");
  a(/backup ts=\d{8}-\d{6}/.test(r.out), "沒印出 backup ts=");
  const b = baks(h);
  a(b.length === 2, "備份數 " + b.length + "（預期 2）");
  for (const f of b) {
    const src = path.join(h, ".claude", f.split(".bak-")[0]);
    a(fs.readFileSync(path.join(h, ".claude", f), "utf8") === fs.readFileSync(src, "utf8"), f + " 內容與來源不符");
  }
});

check("only-main", (a) => {
  const h = newHome("only-main");
  fs.writeFileSync(path.join(h, ".claude", "settings.json"), MAIN);
  const r = run(h);
  a(r.status === 0, "退出碼 " + r.status);
  a(r.out.includes("不存在，略過"), "沒有回報 local 不存在");
  a(baks(h).length === 1, "備份數 " + baks(h).length + "（預期 1）");
});

check("neither-file", (a) => {
  const h = newHome("neither");
  const r = run(h);
  a(r.status === 0, "退出碼 " + r.status);
  a(r.out.includes("沒有需要備份的 settings 檔"), "沒有回報無事可做");
  a(baks(h).length === 0, "不該產生備份");
});

check("unicode-and-bom-preserved", (a) => {
  const h = newHome("unicode");
  const body = "﻿" + JSON.stringify({ _comment: "中文與 emoji 🚀", hooks: {} });
  fs.writeFileSync(path.join(h, ".claude", "settings.json"), body);
  const r = run(h);
  a(r.status === 0, "退出碼 " + r.status);
  const b = baks(h);
  a(b.length === 1, "備份數 " + b.length);
  a(fs.readFileSync(path.join(h, ".claude", b[0])).equals(Buffer.from(body, "utf8")), "位元組不相同（BOM 或編碼掉了）");
});

// 撞名用**固定時鐘**確定性觸發：預載 tests/helpers/fixed-clock.js 把子程序的
// `new Date()` 釘死，測試就知道工具會用哪一個時間戳，只預建那唯一一個檔名。
// （先前是「預建未來 5 秒的候選」去賭時鐘，落出視窗就 SKIP —— 等於把沒驗到包成綠燈。
//  現在若工具沒有中止，那是**真的回歸**，直接 FAIL，不再有 SKIP 這條逃生口。）
const FIXED_MS = Date.parse("2026-08-09T03:04:05");

check("collision-aborts-without-partial", (a) => {
  const h = newHome("collision");
  fs.writeFileSync(path.join(h, ".claude", "settings.json"), MAIN);
  fs.writeFileSync(path.join(h, ".claude", "settings.local.json"), LOCAL);
  // 只擋**第二個**目標，用來證明「撞名在預檢階段就攔下，第一個檔也不會被備份」
  const collide = path.join(h, ".claude", "settings.local.json.bak-" + tsOf(FIXED_MS));
  fs.writeFileSync(collide, "佔位");
  const before = baks(h).length;

  const r = run(h, FIXED_MS);
  a(r.status === 1, "退出碼 " + r.status + "（預期 1；固定時鐘下撞名是必然的，沒中止＝回歸）");
  a(r.out.includes("已存在"), "沒有回報撞名");
  a(r.out.includes(tsOf(FIXED_MS)), "回報的時間戳不是固定時鐘的值，代表注入沒生效");
  a(!r.out.includes("backup ts="), "中止了卻仍印出 backup ts=");
  a(baks(h).length === before, "中止後備份數 " + baks(h).length + "（預期 " + before + "，代表完全沒動手）");
});

// 固定時鐘的**正向對照**：同一個 FIXED_MS、但沒有預先佔位時必須成功。
// 沒有這條的話，上面那案可能是因為「注入本身把工具弄壞了」而通過。
check("fixed-clock-control-group", (a) => {
  const h = newHome("fixed-clock-ok");
  fs.writeFileSync(path.join(h, ".claude", "settings.json"), MAIN);
  const r = run(h, FIXED_MS);
  a(r.status === 0, "退出碼 " + r.status + "（預期 0）");
  a(r.out.includes("backup ts=" + tsOf(FIXED_MS)), "沒有用固定時鐘的時間戳");
  a(baks(h).length === 1, "備份數 " + baks(h).length + "（預期 1）");
});

check("directory-instead-of-file", (a) => {
  const h = newHome("isdir");
  fs.mkdirSync(path.join(h, ".claude", "settings.json"));
  const r = run(h);
  a(r.status === 1, "退出碼 " + r.status + "（預期 1）");
  a(r.out.includes("不是一般檔案"), "沒有回報型別問題");
  a(!r.out.includes("backup ts="), "中止了卻仍印出 backup ts=");
});

check("symlink-refused-and-no-partial", (a) => {
  const h = newHome("symlink");
  const real = path.join(work, "real-local.json");
  fs.writeFileSync(real, LOCAL);
  fs.writeFileSync(path.join(h, ".claude", "settings.json"), MAIN);
  try {
    fs.symlinkSync(real, path.join(h, ".claude", "settings.local.json"));
  } catch (e) {
    skipped.push("symlink-refused-and-no-partial（本環境建不了 symlink：" + e.code + "）");
    pass--; // 不計入 PASS
    return;
  }
  const r = run(h);
  a(r.status === 1, "退出碼 " + r.status + "（預期 1）");
  a(r.out.includes("symlink"), "沒有回報 symlink");
  a(!r.out.includes("backup ts="), "中止了卻仍印出 backup ts=");
  // 最重要的一條：settings.json 是合法的，但預檢階段就中止 → 它也不該被備份
  a(baks(h).length === 0, "產生了 " + baks(h).length + " 個備份（預檢應在動手前就中止）");
});

// 複製階段失敗 → 必須回收本次已建立的備份（不變量：全部成功或什麼都沒留下）。
// 變異注入：把第二個來源檔 chmod 000，讓它通過 lstat 預檢、卻在 copyFileSync 失敗。
// ⚠️ 注入是否成功要自我檢查：以 root 執行時 chmod 擋不住讀取，那時 copy 會成功——
// 那是「沒驗到」，必須標 SKIP，不能當成通過。
check("copy-phase-failure-rolls-back", (a) => {
  const h = newHome("rollback");
  fs.writeFileSync(path.join(h, ".claude", "settings.json"), MAIN);
  const second = path.join(h, ".claude", "settings.local.json");
  fs.writeFileSync(second, LOCAL);
  try {
    fs.chmodSync(second, 0o000);
    fs.readFileSync(second); // 注入自我檢查：讀得到就代表沒注入成功
    skipped.push("copy-phase-failure-rolls-back（chmod 000 擋不住讀取，可能是 root 或 Windows）");
    pass--;
    return;
  } catch (e) {
    if (e.code !== "EACCES" && e.code !== "EPERM") {
      skipped.push("copy-phase-failure-rolls-back（注入未生效：" + e.code + "）");
      pass--;
      return;
    }
  }
  const r = run(h);
  a(r.status === 1, "退出碼 " + r.status + "（預期 1）");
  a(!r.out.includes("backup ts="), "中止了卻仍印出 backup ts=");
  a(!r.out.includes("未產生任何備份"), "複製階段失敗卻宣稱『未產生任何備份』——那正是要修掉的假宣稱");
  a(r.out.includes("已回收本次建立的備份"), "沒有回報回收動作");
  fs.chmodSync(second, 0o600); // 讓後續清理刪得掉
  a(baks(h).length === 0, "回收後仍留下 " + baks(h).length + " 個備份");
});

fs.rmSync(work, { recursive: true, force: true });

const total = pass + failed.length + skipped.length;
console.log("");
console.log("TOTAL " + total + "  PASS " + pass + "  FAIL " + failed.length + "  SKIP " + skipped.length);
for (const s of skipped) console.log("SKIP: " + s);
if (failed.length) {
  console.log("失敗的案子：" + failed.join(", "));
  process.exit(1);
}
if (strict && skipped.length) {
  console.log("--strict：有 " + skipped.length + " 個案子沒有實際驗到，視為失敗。");
  process.exit(1);
}
