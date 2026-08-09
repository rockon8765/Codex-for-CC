#!/usr/bin/env node
/*
 * probe-gate-registration —— 唯讀診斷：super-mode consult gate 現在註冊在哪、有幾筆、
 * 能不能照文件往下做。**不會修改任何檔案。**
 *
 * 三平台共用同一份（`node tools/probe-gate-registration.js`）。
 * 它先前是 `docs/MIGRATION-hook-settings-target.md` 第 1 節裡的 bash heredoc，
 * 2026-08-08 抽成本檔，原因有二：
 *   1. heredoc 在 Windows 的 PowerShell 跑不動，但「重複註冊」三平台都會發生，
 *      `AI-INSTALL` 步驟 2 與三份 snippet 都要叫使用者先數一次。
 *   2. 內嵌在 markdown 裡的邏輯沒有任何回歸案守著。現在有
 *      `tests/probe-gate-registration.test.js`。
 *
 * **2026-08-09：判斷邏輯全部搬去共用模組。** 本檔現在只做三件事 ——
 * 載入模組（並驗它的完整性）、讀兩個 settings 檔、把 verdict 印出來。
 * 「哪個 handler 是本 gate、它會不會真的攔得住」的**唯一實作**在
 * `<platform>/skills/超級模式/lib/gate-registration.js`（三平台逐位元相同）。
 * 為什麼要搬：同一個判斷先前也住在三份 `matcher-contract.test.js` 裡，兩邊規則不一致
 * （這裡驗 `type`、那邊不驗；這裡對 exec form 停手、那邊判成「沒註冊」），
 * 而且在欄位層面**一致地錯**（`if`／`once`／`async` 兩邊都放行）。詳見模組檔頭。
 *
 * 退出碼（文件的判斷分支一律以退出碼 ＋ `RESULT_CODE=` 為準，不要另外摘要規則）：
 *   0 = 判定可執行，照印出來的「判定：」那行做
 *   1 = 讀不到／形狀不合／設定不安全 —— 先修好再重跑，不要往下做（fail-closed）
 *   2 = 參數用錯
 *   3 = 停手：需要人工判斷，本 repo 的文件涵蓋不了
 *
 * **範圍**：刻意很窄，每次執行都會把範圍說明印在最後（由模組的 renderer 產生，
 * 所以文案與行為綁在同一處）。⚠️ **但「每條退出路徑都印範圍」只涵蓋受控的判定分支**——
 * `TOOL_INTEGRITY_ERROR`（模組載不進來，還沒開始判斷）、參數錯誤、未捕捉例外、
 * stdout `EPIPE`、signal、OOM 都不在保證內。
 *
 * 為什麼形狀不合一定要 fail-closed：舊版寫
 * `for (const entry of (j.hooks && j.hooks.PreToolUse) || [])`，當 `hooks.PreToolUse`
 * 是**字串**時會逐字元迭代、靜默數成 0，於是判定成「兩邊都沒有 gate……照 AI-INSTALL
 * 步驟 2 重做」——假陰性，而且重裝正是可能造成重複註冊的動作。
 *
 * ⚠️ **刻意不呼叫 `process.exit()`**：Node 官方文件明講它會強制結束、
 * **截斷尚未完成的 `process.stdout` 寫入**；而 stdout 對 pipe／socket 的同步性隨平台不同
 * （Windows 同步、Linux／macOS 非同步），所以「先印再 exit」在小輸出時剛好通過、
 * 大輸出時遺失——典型的靠運氣綠燈。全程用 `process.exitCode` ＋自然結束。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

// ── 共用模組的載入與完整性 ───────────────────────────────────────────────
/*
 * 三份鏡像**全部讀進來、逐位元比對、全等才 require**。
 *
 * 為什麼不用 `process.platform` 挑一份（這是 2026-08-09 對抗審查否決掉的原案）：
 *   ・三份既然必須逐位元相同，「挑哪一份」就沒有選擇語義，只是多長出錯誤分支。
 *   ・`process.platform` 是 **Node binary 的編譯平台**，不是使用者要檢查的安裝 target，
 *     而且可能值不只三種 —— 把「其餘」全折成 linux 會把 FreeBSD／AIX／OpenBSD／
 *     SunOS／Android 靜默歸錯。
 *   ・sparse checkout 只有一個平台樹時，會在受控 renderer 之前就噴 MODULE_NOT_FOUND。
 * 現在改成驗**本工具自身的完整性**：三份缺一份或內容分歧，一律 fail-closed 並明講
 * 「沒有做任何判斷」。完整 checkout 是本工具的正式前置條件，所以這個 fail-closed
 * 面是合理的 —— 它不是在擴大 settings 的 schema 驗證。
 *
 * ⚠️ 這**不能**解決跨 target 診斷（例如在 WSL 想檢查 Windows 那邊的安裝）：
 * 那件事的主因是 target home 而不是模組副本，要修得加明確的 `--home`／
 * `--settings` 旗標。記在 docs/backlog.md，本批不做。
 */
const MIRROR_PLATFORMS = ["windows", "macos", "linux"];
const MIRROR_REL = path.join("skills", "超級模式", "lib", "gate-registration.js");

const INTEGRITY_TAIL = [
  "   請從 Codex-for-CC 的 checkout **根目錄**執行：node tools/probe-gate-registration.js",
  "   不要把本檔單獨複製到別處跑 —— 它需要 payload 裡的共用模組。",
  "",
  "RESULT_CODE=TOOL_INTEGRITY_ERROR",
];

function loadShared() {
  const mirrors = MIRROR_PLATFORMS.map((plat) => {
    const p = path.join(__dirname, "..", plat, MIRROR_REL);
    let buf = null;
    try {
      buf = fs.readFileSync(p);
    } catch (e) {
      return { plat, path: p, buf: null, err: e.code };
    }
    return { plat, path: p, buf };
  });

  const head = "⛔ TOOL_INTEGRITY_ERROR —— 共用模組不可用，本工具**沒有做任何判斷**。";
  const bad = (lines) => ({ ok: false, text: [head].concat(lines, INTEGRITY_TAIL).join("\n") });

  const absent = mirrors.filter((m) => !m.buf);
  if (absent.length) {
    return bad(absent.map((m) => "   讀不到 " + m.path + "（" + m.err + "）"));
  }
  const differ = mirrors.filter((m) => !m.buf.equals(mirrors[0].buf));
  if (differ.length) {
    return bad([
      "   三平台鏡像**內容不一致** —— gate 辨識的邏輯只能有一份，這代表有人只改了其中幾份。",
    ].concat(mirrors.map((m) => "   " + m.plat + " " + m.buf.length + " bytes  " + m.path)));
  }
  try {
    return { ok: true, mod: require(mirrors[0].path), path: mirrors[0].path };
  } catch (e) {
    return bad(["   require 失敗：" + (e && e.message ? e.message : String(e)), "   " + mirrors[0].path]);
  }
}

// ── I/O ─────────────────────────────────────────────────────────────────
/*
 * 讀一份 settings 並包成 SettingsSource。**判斷全在模組裡**，這裡只分辨三種 I/O 結果。
 * `label` 是盤點行左欄（長名，補到固定欄寬）、`shortLabel` 是逐筆列 handler 時的短名。
 */
function readSource(G, label, shortLabel, p) {
  try {
    return G.sourceRaw(label, p, fs.readFileSync(p, "utf8"), shortLabel);
  } catch (e) {
    if (e.code === "ENOENT") return G.sourceMissing(label, p, shortLabel);
    return G.sourceReadError(label, p, e.code, shortLabel);
  }
}

// ── 參數 ────────────────────────────────────────────────────────────────
/*
 * 本工具**不吃任何參數**，但未知參數要明確報錯而不是靜默忽略。
 * 理由是踩過的實例：修正前的 `matcher-contract.test.js` 收到 `--live` 會**靜默忽略**
 * 並照樣 PASS，於是「我明明指定了驗 live」的人拿到一個驗別的東西的綠燈。
 * 同一個坑不要在這裡再挖一次。
 */
function parseArgs(argv) {
  if (!argv.length) return { ok: true };
  return {
    ok: false,
    text: [
      "FAIL: 本工具不吃參數，收到：" + argv.join(" "),
      "用法：node tools/probe-gate-registration.js（唯讀，三平台同一條指令）",
      "",
      "RESULT_CODE=BAD_ARGS",
    ].join("\n"),
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.ok) {
    console.log(args.text);
    return 2;
  }

  const loaded = loadShared();
  if (!loaded.ok) {
    console.log(loaded.text);
    return 1;
  }
  const G = loaded.mod;

  /*
   * `CLAUDE_CONFIG_DIR` 會覆寫整個設定目錄，而本工具一律用 `~/.claude` 解路徑 ——
   * 變數一設，下面數的就是 Claude **不會讀**的那一份。判「正常，不用修」會直接誤導。
   * 所以 fail-closed 並明講原因，不猜它的語義（理由見模組的 CONFIG_DIR_ENV 註解）。
   */
  const override = G.configDirOverride(process.env);
  if (override) {
    console.log(G.renderConfigDirRefusal(override, "本工具"));
    return 1;
  }

  const claude = path.join(os.homedir(), ".claude");
  const verdict = G.assessProbe({
    main: readSource(G, "~/.claude/settings.json", "settings.json", path.join(claude, "settings.json")),
    local: readSource(G, "~/.claude/settings.local.json", "settings.local.json", path.join(claude, "settings.local.json")),
  });
  console.log(G.renderProbe(verdict));
  return verdict.exit;
}

// 受控的整包 try/catch：本工具是 fail-closed 的診斷，任何意外都必須變成
// 「非 0 ＋ 說明」而不是一段 stack trace —— 使用者拿 stack trace 沒辦法判斷
// 「我可不可以往下做」，而修正前的 matcher-contract 正是這樣（見模組檔頭）。
try {
  process.exitCode = main();
} catch (e) {
  console.log("⛔ INTERNAL_ERROR —— 本工具自己出錯，沒有做出任何判斷，請回報。");
  console.log("   " + (e && e.stack ? String(e.stack).split("\n")[0] : String(e)));
  console.log("");
  console.log("RESULT_CODE=INTERNAL_ERROR");
  process.exitCode = 1;
}
