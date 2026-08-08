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
 * 退出碼（文件的判斷分支一律以這個為準，不要另外摘要規則）：
 *   0 = 判定可執行，照印出來的「判定：」那行做
 *   1 = 讀不到或形狀不合 —— 先修好再重跑，不要往下做（fail-closed）
 *   3 = 停手：需要人工判斷，本 repo 的文件涵蓋不了
 *
 * **範圍（刻意很窄，不要把它當成別的東西）**——每次執行都會把這段印在最後：
 *   ・它數的是「gate 註冊了幾筆」，不是完整的 settings schema 驗證器。
 *   ・只判斷 shell form；**看到 exec form（handler 帶 `args`）一律 exit 3**。
 *   ・不驗 command 指到的檔案存不存在，也不驗 hook 真的會被叫起。
 *   ・needle 比對大小寫敏感 —— Windows 上兩筆只差路徑大小寫的重複註冊看不見。
 *   ・**不是 settings 的 schema 驗證器。** 實際會驗、驗不過就非 0 的只有：
 *     `PreToolUse` 是陣列／每個 entry 是物件／`entry.hooks` 若存在是陣列／每個 handler 是物件／
 *     `handler.command` 若存在是字串／`handler.args` 若存在是字串陣列。
 *     命中 needle 之後才另外驗 `handler.type === "command"` 與該 entry 的 `matcher` 型別。
 *     **不驗**：沒有 `hooks` 鍵的 entry 直接略過；非 gate 的 handler 不驗 `type` 的型別，
 *     也不驗 `type:"command"` 是否真的帶了 `command`。
 *     （這段的歷史：先寫成「無關的畸形條目會被略過」——與實作相反；再改成「唯二例外」
 *     ——漏了上面那第三類。所以現在改成正面列出「驗什麼」，不再用「例外」描述。）
 *
 * 為什麼形狀不合一定要 fail-closed：舊版寫
 * `for (const entry of (j.hooks && j.hooks.PreToolUse) || [])`，當 `hooks.PreToolUse`
 * 是**字串**時會逐字元迭代、靜默數成 0，於是判定成「兩邊都沒有 gate……照 AI-INSTALL
 * 步驟 2 重做」——假陰性，而且重裝正是可能造成重複註冊的動作。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

const NEEDLE = "super-mode-consult-gate";

const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const typeName = (v) => (v === null ? "null" : Array.isArray(v) ? "陣列" : typeof v);

// **每一條退出路徑都要印範圍。** 先前只在「有找到 gate」時才印，於是最需要看到它的
// 那條路徑——找到 0 筆、接著 `AI-INSTALL` 步驟 2 會叫人新增一筆——反而看不到
// 「needle 大小寫敏感」這個警告，而那正是 Windows 上製造重複註冊的入口。
//
// 五個受控的判定分支各自 `return` 一個退出碼，由檔尾**單一 epilogue** 印範圍並設
// `process.exitCode`，讓程序**自然結束**。
//
// ⚠️ **刻意不呼叫 `process.exit()`**：Node 官方文件明講它會強制結束、
// **截斷尚未完成的 `process.stdout` 寫入**；而 stdout 對 pipe／socket 的同步性隨平台不同
// （Windows 同步、Linux／macOS 非同步），所以「先印再 exit」在小輸出時剛好通過、
// 大輸出時遺失——典型的靠運氣綠燈。
//
// ⚠️ 這只涵蓋**受控的判定分支**。未捕捉例外、stdout `EPIPE`、signal、OOM 都不在保證內
// ——所以不要把它宣稱成「每一條退出路徑」。
function printScope() {
  console.log("");
  console.log("⚠️ 本工具只數「gate 註冊了幾筆」，範圍刻意很窄：");
  console.log("   ・只判斷 shell form；看到 exec form（handler 帶 args）一律停手，不做判斷");
  console.log("   ・不驗 command 指到的檔案是否存在，也不驗 hook 真的會被叫起");
  console.log("   ・needle 比對**大小寫敏感** —— Windows 上兩筆只差路徑大小寫、卻指向同一個檔的");
  console.log("     重複註冊，本工具看不見。判「0 筆」時請先確認不是這種情況再新增。");
  console.log("   ・它**不是 settings 的 schema 驗證器**。實際會驗、驗不過就非 0 的只有這些欄位：");
  console.log("       PreToolUse 是陣列／每個 entry 是物件／entry.hooks 若存在是陣列／");
  console.log("       每個 handler 是物件／handler.command 若存在是字串／handler.args 若存在是字串陣列。");
  console.log("     命中 needle 之後才另外驗 handler.type === \"command\" 與該 entry 的 matcher 型別。");
  console.log("     **不驗**的例子：沒有 hooks 鍵的 entry 直接略過；非 gate 的 handler 不驗 type 的型別，");
  console.log("     也不驗 type:\"command\" 是否真的帶了 command —— 這些都會 exit 0 放行。");
}

/**
 * 掃一個 settings 檔。
 * 回傳 { ok: true, n, handlers: [{ matcher, command, others }] } 或 { ok: false }。
 * `others` = 同一個 outer entry 底下**不是 gate** 的 handler 數量。
 */
function scan(label, p) {
  const say = (msg) => console.log(label.padEnd(32) + msg);
  const bad = (why) => {
    say("形狀不合：" + why);
    return { ok: false };
  };
  const execForm = []; // 命中 needle 但屬 exec form —— 不計數，改走停手

  let raw;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch (e) {
    if (e.code === "ENOENT") {
      say("檔案不存在");
      return { ok: true, n: 0, handlers: [], execForm };
    }
    say("讀取失敗：" + e.code);
    return { ok: false };
  }

  let j;
  try {
    // 用 \uFEFF 而不是把 BOM 字元直接寫進 regex：後者在編輯器／diff 裡是隱形的，
    // 誰不小心刪掉都看不出來。語意完全相同。
    j = JSON.parse(raw.replace(/^\uFEFF/, ""));
  } catch (e) {
    say("JSON 解析失敗：" + e.message);
    return { ok: false };
  }

  if (!isObj(j)) return bad("頂層不是物件（是 " + typeName(j) + "）");
  if (!("hooks" in j)) {
    say("沒有 hooks 段 —— gate 條目：0 個");
    return { ok: true, n: 0, handlers: [], execForm };
  }
  if (!isObj(j.hooks)) return bad("hooks 不是物件（是 " + typeName(j.hooks) + "）");

  const pre = j.hooks.PreToolUse;
  if (pre === undefined) {
    say("沒有 hooks.PreToolUse —— gate 條目：0 個");
    return { ok: true, n: 0, handlers: [], execForm };
  }
  if (!Array.isArray(pre)) return bad("hooks.PreToolUse 不是陣列（是 " + typeName(pre) + "）");

  const handlers = [];
  for (let i = 0; i < pre.length; i++) {
    const entry = pre[i];
    const at = "PreToolUse[" + i + "]";
    if (!isObj(entry)) return bad(at + " 不是物件（是 " + typeName(entry) + "）");
    if (entry.hooks === undefined) continue;
    if (!Array.isArray(entry.hooks)) return bad(at + ".hooks 不是陣列（是 " + typeName(entry.hooks) + "）");

    const gateIdx = [];
    for (let k = 0; k < entry.hooks.length; k++) {
      const h = entry.hooks[k];
      const hat = at + ".hooks[" + k + "]";
      if (!isObj(h)) return bad(hat + " 不是物件（是 " + typeName(h) + "）");
      if (h.command !== undefined && typeof h.command !== "string") {
        return bad(hat + ".command 不是字串（是 " + typeName(h.command) + "）");
      }
      // Claude Code 的 command hook 有兩種形態：
      //   shell form  { "type":"command", "command":"node /x/super-mode-consult-gate.js" }
      //   exec form   { "type":"command", "command":"node", "args":["/x/super-mode-consult-gate.js"] }
      // **本工具只判斷 shell form；看到 exec form 一律停手。** 兩個理由：
      //   1. `matcher-contract.test.js`（安裝流程規定必跑）目前也只看 `command`，
      //      對 exec form 會回報「沒有註冊本 hook」。這裡若自作主張判「正常」，
      //      使用者會拿到兩個互相矛盾的結論，而且照樣過不了安裝驗收。
      //   2. `args` 存在與否會改變 runtime 語義（直接 exec vs 經 shell），
      //      光比字串無法安全判斷兩筆註冊是不是「同一筆」。
      // 停手至少讓人知道要找人；判「兩邊都沒有 gate」則會讓 AI-INSTALL 步驟 2 再加一筆，
      // 也就是這支診斷自己製造出它要防的重複註冊。
      if (h.args !== undefined && !Array.isArray(h.args)) {
        return bad(hat + ".args 不是陣列（是 " + typeName(h.args) + "）");
      }
      const argv = [];
      if (Array.isArray(h.args)) {
        for (let a = 0; a < h.args.length; a++) {
          if (typeof h.args[a] !== "string") {
            return bad(hat + ".args[" + a + "] 不是字串（是 " + typeName(h.args[a]) + "）");
          }
          argv.push(h.args[a]);
        }
      }
      if (h.command === undefined && h.args === undefined) continue;
      const haystack = [h.command === undefined ? "" : h.command].concat(argv).join(" ");
      if (!haystack.includes(NEEDLE)) continue;
      // 命中字串還不夠：canonical 註冊是 { "type": "command", "command": ... }。
      // 只比對 command 的 substring，會把「type 缺漏或不是 command」的條目也算成
      // 「gate 已接上」——那是這支診斷自己製造假綠。形狀不對就停，不要回報成已註冊。
      if (h.type !== "command") {
        return bad(
          hat + " 的 command 含 gate，但 type 是 " +
          (h.type === undefined ? "缺漏" : JSON.stringify(h.type)) +
          "（必須是 \"command\"）"
        );
      }
      // exec form：不計數、改記到停手清單。
      if (h.args !== undefined) {
        execForm.push({ where: hat, command: h.command === undefined ? null : h.command, args: argv });
        continue;
      }
      // 走到這裡一定是 shell form，`command` 必須是字串才算數得上一筆 gate。
      if (typeof h.command !== "string") {
        return bad(hat + " 命中 gate 但沒有可用的 command 字串");
      }
      gateIdx.push({ k, argv });
    }

    if (!gateIdx.length) continue;
    // matcher 只在「這個 entry 真的掛著 gate」時才驗型別：不相干的畸形 entry
    // 不該把使用者的 migration 擋死。
    if (entry.matcher !== undefined && typeof entry.matcher !== "string") {
      return bad(at + ".matcher 不是字串（是 " + typeName(entry.matcher) + "）");
    }
    // 只有 shell form 會走到這裡（exec form 已進 execForm 並會讓整支停手），
    // 所以 handlers 一律沒有 args，一致性比對只需要 (matcher, command)。
    const others = entry.hooks.length - gateIdx.length;
    for (const g of gateIdx) {
      handlers.push({
        matcher: entry.matcher === undefined ? "" : entry.matcher,
        command: entry.hooks[g.k].command,
        others,
        where: at + ".hooks[" + g.k + "]",
      });
    }
  }

  say("gate 條目：" + handlers.length + " 個" + (execForm.length ? "（另有 " + execForm.length + " 筆 exec form，見下）" : ""));
  return { ok: true, n: handlers.length, handlers, execForm };
}

function run() {
  const home = os.homedir();
  const mainRes = scan("~/.claude/settings.json", path.join(home, ".claude", "settings.json"));
  const localRes = scan("~/.claude/settings.local.json", path.join(home, ".claude", "settings.local.json"));
  console.log("");

  if (!mainRes.ok || !localRes.ok) {
    console.log("判定：有檔案無法解析或形狀不合 —— 先修好再重跑，不要往下做。");
    return 1; // fail-closed：形狀不明時不可以讓人拿 exit 0 當成「已確認沒問題」
  }

  const tag = (file) => (h) => Object.assign({ file }, h);
  const all = mainRes.handlers.map(tag("settings.json")).concat(localRes.handlers.map(tag("settings.local.json")));

  // ── 停手條件（機械判定，文件不再自己摘要一份）────────────────────────────
  // 0. exec form：本工具的辨識能力到不了，而且必跑的 matcher-contract 也看不到它。
  const execAll = mainRes.execForm.map(tag("settings.json")).concat(localRes.execForm.map(tag("settings.local.json")));
  if (execAll.length) {
    for (const h of execAll) {
      console.log("  " + h.file + " " + h.where + "  command=" + JSON.stringify(h.command) + "  args=" + JSON.stringify(h.args));
    }
    console.log("判定：停手 —— 上面是 exec form（handler 帶 `args`）的 gate 註冊，本工具無法判斷。請人工確認。");
    console.log("      理由：安裝流程規定必跑的 matcher-contract 目前也只看 `command`，會對它回報");
    console.log("      「沒有註冊本 hook」；而 `args` 存在與否會改變 runtime 語義，光比字串無法");
    console.log("      安全判斷兩筆註冊是不是同一筆。這裡若判「正常」或「沒有 gate」都會誤導。");
    return 3;
  }
  // 1. 含 gate 的 outer entry 底下還掛著別的 handler：整筆搬移／刪除會動到不相干的 hook。
  const shared = all.filter((h) => h.others > 0);
  if (shared.length) {
    for (const h of shared) {
      console.log("  " + h.where + " 所在的 entry 底下還有 " + h.others + " 個非 gate 的 handler");
    }
    console.log("判定：停手 —— 含 gate 的條目底下還掛著其他 handler，動它會影響不相干的 hook。請人工判斷。");
    return 3;
  }
  // 2. 有兩筆以上 gate handler、但它們的 matcher 或 command 不一致：不知道該留哪一筆。
  //    ⚠️ 必須比**兩個檔的聯集**。只比 settings.json 的話，「main 一筆 stale ＋ local 一筆正確」
  //    會被判成 B（純減法），使用者刪光 local 只留下壞的那筆，重跑還會得到「正常」。
  const seen = [];
  for (const h of all) {
    const key = JSON.stringify([h.matcher, h.command]);
    if (!seen.includes(key)) seen.push(key);
  }
  if (all.length >= 2 && seen.length > 1) {
    console.log("  共 " + all.length + " 筆 gate handler，出現 " + seen.length + " 種不同的 (matcher, command)：");
    for (const k of seen) {
      const v = JSON.parse(k);
      console.log("    matcher=" + JSON.stringify(v[0]) + "  command=" + JSON.stringify(v[1]));
    }
    console.log("判定：停手 —— 多筆 gate handler 的 matcher／command 不一致，無法判斷該留哪一筆。請人工判斷。");
    return 3;
  }

  // ── 一般判定 ────────────────────────────────────────────────────────────
  const main = mainRes.n;
  const local = localRes.n;
  if (main === 1 && local === 0) console.log("判定：正常，不用修。");
  else if (main > 1) console.log("判定：settings.json 裡有 " + main + " 筆 gate —— 已經重複註冊。做第 2 節的『B. 已經有一筆』。");
  else if (main === 1 && local >= 1) console.log("判定：兩邊都有 —— **只要從 settings.local.json 移除**，不要搬。做第 2 節的『B. 已經有一筆』。");
  else if (main === 0 && local >= 1) console.log("判定：受影響 —— gate 只在 local，從非家目錄啟動完全不生效。做第 2 節的『A. 還沒有』。");
  else console.log("判定：兩邊都沒有 gate —— 可能還沒安裝，或註冊在別處。照 AI-INSTALL 步驟 2 重做。");

  // ⚠️ 明確劃出本 probe **不**負責的事。不寫出來的話，「判定：正常」會被當成
  // 「gate 一定會生效」，但 command 指到一個已經被刪掉的路徑時它照樣印「正常」。
  if (all.length) {
    console.log("");
    console.log("已註冊的 gate handler：");
    for (const h of all) {
      console.log("  " + h.file + " " + h.where + "  command=" + JSON.stringify(h.command));
    }
    console.log("（端到端沒被 deny 時，先核對上面印出來的路徑還在不在——見下方範圍說明。）");
  }

  return 0;
}

// ── 單一 epilogue ───────────────────────────────────────────────────────
// 不論走哪個判定分支，範圍說明都在這裡印一次；設 exitCode 後**自然結束**，
// 由 runtime 排空 stdout（不呼叫 process.exit()）。
process.exitCode = run();
printScope();
