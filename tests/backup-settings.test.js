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
function run(home) {
  const r = spawnSync(process.execPath, [tool], {
    encoding: "utf8",
    env: Object.assign({}, process.env, { HOME: home, USERPROFILE: home }),
  });
  return { status: r.status, out: (r.stdout || "") + (r.stderr || "") };
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

check("collision-aborts-without-partial", (a) => {
  const h = newHome("collision");
  fs.writeFileSync(path.join(h, ".claude", "settings.json"), MAIN);
  fs.writeFileSync(path.join(h, ".claude", "settings.local.json"), LOCAL);
  // 先跑一次拿到 ts，再用同一個 ts 撞名
  const first = run(h);
  const ts = (first.out.match(/backup ts=(\d{8}-\d{6})/) || [])[1];
  a(!!ts, "第一次沒拿到 ts");
  if (!ts) return;
  const before = baks(h).length;
  // 直接改系統時間不可行，所以改成：刪掉其中一個備份，讓第二次在同一秒重跑時撞到另一個。
  // 若第二次的 ts 不同（跨秒）就視為無法觸發，標 SKIP 而不是假綠。
  fs.unlinkSync(path.join(h, ".claude", "settings.json.bak-" + ts));
  const second = run(h);
  const ts2 = (second.out.match(/backup ts=(\d{8}-\d{6})/) || [])[1];
  if (ts2 && ts2 !== ts) {
    skipped.push("collision-aborts-without-partial（跨秒，撞名條件未觸發）");
    pass--; // 這一輪不算過，改記到 skipped
    return;
  }
  a(second.status === 1, "退出碼 " + second.status + "（預期 1）");
  a(second.out.includes("已存在"), "沒有回報撞名");
  a(!second.out.includes("backup ts="), "中止了卻仍印出 backup ts=");
  // 關鍵：預檢階段就中止，不該補回剛剛刪掉的那個備份（＝沒有半完成狀態）
  a(baks(h).length === before - 1, "中止後備份數 " + baks(h).length + "（預期 " + (before - 1) + "，代表完全沒動手）");
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

fs.rmSync(work, { recursive: true, force: true });

const total = pass + failed.length + skipped.length;
console.log("");
console.log("TOTAL " + total + "  PASS " + pass + "  FAIL " + failed.length + "  SKIP " + skipped.length);
for (const s of skipped) console.log("SKIP: " + s);
if (failed.length) {
  console.log("失敗的案子：" + failed.join(", "));
  process.exit(1);
}
