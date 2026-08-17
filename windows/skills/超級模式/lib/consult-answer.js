#!/usr/bin/env node
/**
 * consult-answer.js —— 憑證鑄造條件的單一邏輯版本（三平台逐位元鏡像）。
 *
 * 為什麼是 node 而不是每平台各寫一份：
 *   判準裡有 \p{L}\p{N} 計數、首行定義、大小寫敏感 regex、JSON 可解析性四件事。
 *   在 PowerShell 與 bash 各實作一次 = 同一份規則寫三遍，本 repo 反覆吃虧的第一號失敗模式。
 *   而且 JSON 那條在各 host 的原生 parser 行為並不一致（pwsh 7.x 接受註解與 trailing comma、
 *   WinPS 5.1 拒絕；兩者都接受 NaN／01，Node 的 JSON.parse 全拒）——同一份 codex 回覆會在
 *   不同平台得到不同裁決。單一 node 實作用建構方式消滅這個分歧。
 *   node 不是新依賴：gate hook 本身就是 `node <home>/.claude/hooks/super-mode-consult-gate.js`，
 *   沒有 node 的機器上超級模式本來就不成立。
 *
 * ⚠️ 這支能證明什麼、不能證明什麼（措辭刻意收窄，不要放寬）：
 *   能：這次 codex 進程回了「足量且形式合格」的輸出。
 *   不能：不能證明諮詢真的發生過（真諮詢也可能只回短答；偽造的 40 字輸出照樣通過），
 *        更不能證明 Codex 批准了什麼——**BLOCK 也判 ok=true**（見下方 receipt 語義）。
 *
 * receipt 語義：憑證是「諮詢收據」不是「動作授權」。
 *   gate hook 只檢查 token 的 mtime 與 repo 綁定，**不讀裁決**，所以 BLOCK 一樣會解鎖 20 分鐘。
 *   §3.5 的「BLOCK 就不做」由 orchestrator 遵守，**不是這支或 hook 強制的**。
 *   要讓 hook 真的擋 BLOCK，需要 credential v2 ＋ hook 讀裁決 ＋ session／generation 綁定與
 *   舊授權撤銷 —— 那是另一批，見 docs/backlog.md 的「動作授權語義」列。
 *
 * ── 兩個對封存 PowerShell 版（380462f）的**刻意**行為裁決 ─────────────────────
 * 移植不是逐位元等價，下面兩處是明文決定，不是 /u 或 trim() 默默改掉的：
 *
 *   D1  U+0085 (NEL) 之類的控制字元開頭 → **維持封存版行為＝接受**。
 *       .NET 的 Trim() 視 U+0085 為 whitespace，JS 的 trim() 不視為。若照 JS 原樣，
 *       `<NEL>ALLOW: …` 會被判 NO_VERDICT。**這是錯誤方向的失敗**（合法回覆被誤判成 BLOCK
 *       → cry-wolf → 使用者白跑一次諮詢），所以 firstLine 明確剝除 \p{Cc}\p{Cf} 後再比對。
 *
 *   D2  補充平面（supplementary plane）的字母，例如 U+1D400 𝐀 → **改採 node 語義＝計入**。
 *       .NET regex 走 UTF-16 code unit，代理對的兩半是 \p{Cs} 不是 \p{L}，所以封存版**不計**；
 *       node 的 /u 走 code point，**計入**。這裡採 node 語義，因為門檻的本意是「有沒有實質內容」，
 *       而 𝐀 本來就是字母；封存版的不計是 UTF-16 的實作副作用，不是設計決定。
 *       ⚠️ 代價：理論上可用 40 個補充平面字母湊過門檻。本判準的威脅模型是「codex 沒真的跑」
 *       而不是「有人刻意構造 padding」，故接受此代價。兩案都有 fixture 釘住。
 */

"use strict";

const MIN_CHARS = 40;

/** 成功哨兵：caller 必須收到**恰好這一行**才算 validator 真的跑過。 */
const OK_SENTINEL = "CONSULT-ANSWER-OK";

/** mode：這次是用哪條規則放行的。verdict 只在 mode==="verdict" 時有值。 */
const MODES = { VERDICT: "verdict", DISCUSSION: "discussion", JSON: "json" };

/** 原始輸出：只做 join，不做任何清理。 */
function rawText(lines) {
  if (!Array.isArray(lines) || lines.length === 0) return "";
  return lines.join("\n");
}

/** 剝除格式字元與控制字元，但保留 \r \n \t（換行要留著，才數得出「34 個空行」不算長度）。 */
function stripInvisible(s, keepNewlines) {
  return String(s)
    .replace(/\p{Cf}/gu, "")
    .replace(/\p{Cc}/gu, (ch) =>
      keepNewlines && (ch === "\r" || ch === "\n" || ch === "\t") ? ch : "");
}

/** 清理後的文字（保留換行）。 */
function cleanedText(lines) {
  return stripInvisible(rawText(lines), true).trim();
}

/**
 * 「有意義的長度」——只數字母與數字（\p{L}\p{N}）。
 *
 * 為什麼不是字元數：任何「先剝除某類不可見字元再數 .length」的做法都在跟人比誰列舉得完。
 *   U+200B 零寬空格 → \p{Cf}
 *   U+FE0F variation selector → \p{Mn}，不在 Cf
 *   34 個空行 → 換行是 \p{Cc} 但必須保留，trim 只清兩端，中間照樣計入長度
 * 改成正面表列可見內容，上面三種以及所有未來變體一次全部失效。
 */
function meaningfulLength(text) {
  if (!text) return 0;
  const m = String(text).match(/[\p{L}\p{N}]/gu);
  return m ? m.length : 0;
}

/** 首行 = 第一個非空行；剝除不可見字元（見 D1）後 trim。 */
function firstLine(lines) {
  if (!Array.isArray(lines)) return "";
  for (const l of lines) {
    const c = stripInvisible(l, false).trim();
    if (c) return c;
  }
  return "";
}

/** 大小寫敏感：只有大寫 ALLOW/BLOCK 算數（§3.5 宣告的契約）。 */
const VERDICT_RE = /^(ALLOW|BLOCK)\s*:/;

/**
 * 判斷這份回覆能不能鑄造憑證。**純函式：只回結果，不 exit、不寫檔。**
 * exit 與鑄造都是 caller 的事——把函式契約當成程序契約會移植錯。
 *
 * 求值順序本身就是規格的一部分：
 *   ① cleaned 為空        → code 43
 *   ② schemaMode          → 驗 raw 能否 JSON.parse，成功即通過（mode=json），不走 ③④⑤
 *   ③ noCredential        → **非空即可**通過（mode=discussion），不驗長度也不驗裁決
 *   ④ 長度門檻            → 只數 \p{L}\p{N}，不足則 code 43
 *   ⑤ 裁決格式            → 首行不合格則 code 43
 *
 * ⚠️ ③ 的位置是本批**對封存版的刻意修改**：封存版把長度門檻擺在 noCredential 之前，
 *   於是每一次日常討論諮詢都得湊滿 40 字。全域規則要求每個決策型輸出都跑一次討論諮詢，
 *   把硬門檻套上去等於製造高頻 cry-wolf，而且那條路徑**根本不鑄造憑證**——
 *   本批獲准的範圍只有「會鑄證的路徑」。封存版的檔頭註解自己也寫「討論模式只驗非空」，
 *   與它的函式本體矛盾，因此無法證明那是刻意設計。
 *
 * @param {{lines: string[], noCredential?: boolean, schemaMode?: boolean, minChars?: number}} opts
 * @returns {{ok: boolean, code: number, mode: string, verdict: string, reason: string}}
 */
function testConsultAnswer(opts) {
  const o = opts || {};
  const lines = Array.isArray(o.lines) ? o.lines : [];
  // ⚠️ 明確 boolean，不吃 JS truthiness：旗標語義由 caller adapter 決定並各自測，
  //   這裡收到非 boolean 就是呼叫端寫錯，要當場炸掉而不是猜。
  const noCredential = asBool(o.noCredential, "noCredential");
  const schemaMode = asBool(o.schemaMode, "schemaMode");
  const minChars = o.minChars === undefined ? MIN_CHARS : o.minChars;
  if (!Number.isInteger(minChars) || minChars < 1) {
    throw new TypeError("minChars 必須是 >=1 的整數（不提供繞過門檻的途徑）");
  }

  const raw = rawText(lines);
  const text = cleanedText(lines);

  if (!text) {
    return fail(43, "CONSULT_UNUSABLE_ANSWER: codex exit 0 但回覆是空的，未鑄造憑證。" +
      "這通常代表諮詢實際上沒發生(額度、認證、或 prompt 沒送到)。");
  }

  if (schemaMode) {
    // exit 0 不足以證明輸出真的符合 schema（上游有過 --output-schema 在某些路徑被忽略、
    // 仍產出 malformed 輸出的回報）。這裡只確認「是合法 JSON」——**不驗 schema conformance**。
    // ⚠ 驗 raw 而非 cleaned：清理後再 parse 等於把非法輸出修好再放行
    //   （`{"ok":tru<U+200B>e}` 會被修成合法 JSON）。
    try {
      JSON.parse(raw);
    } catch (e) {
      return fail(43, "CONSULT_SCHEMA_NOT_JSON: 指定了 schema 但 codex 的**原始**輸出不是" +
        "合法 JSON(strict：註解、trailing comma、NaN、01 一律拒)，未鑄造憑證。");
    }
    return { ok: true, code: 0, mode: MODES.JSON, verdict: "", reason: "" };
  }

  if (noCredential) {
    // 討論模式不鑄造憑證 → 只要不是空的就放行，不套長度與裁決門檻（見上方 ③ 的說明）。
    return { ok: true, code: 0, mode: MODES.DISCUSSION, verdict: "", reason: "" };
  }

  const meaningful = meaningfulLength(text);
  if (meaningful < minChars) {
    return fail(43, "CONSULT_UNUSABLE_ANSWER: codex exit 0 但回覆過短(" + meaningful +
      " 個字母/數字 < " + minChars + "；空白、換行、零寬與變體選擇符皆不計)，未鑄造憑證。" +
      "這通常代表諮詢實際上沒發生(額度、認證、或 prompt 沒送到)。");
  }

  const first = firstLine(lines);
  const m = first.match(VERDICT_RE);
  if (m) {
    // ⚠ BLOCK 也回 ok:true —— 憑證是諮詢收據，不是動作授權。見檔頭 receipt 語義。
    return { ok: true, code: 0, mode: MODES.VERDICT, verdict: m[1], reason: "" };
  }

  return fail(43, "CONSULT_NO_VERDICT: 首行不是 ^(ALLOW|BLOCK): 格式(大小寫敏感)，" +
    "依 SKILL §3.5 視為 BLOCK，未鑄造憑證。首行實際內容: '" + first.slice(0, 120) + "'。" +
    "請在簡報結尾明確要求首行裁決後重問一次。");
}

function fail(code, reason) {
  return { ok: false, code, mode: "", verdict: "", reason };
}

function asBool(v, name) {
  if (v === undefined) return false;
  if (typeof v !== "boolean") throw new TypeError(name + " 必須是 boolean，收到 " + typeof v);
  return v;
}

module.exports = {
  testConsultAnswer, meaningfulLength, firstLine, cleanedText, rawText, stripInvisible,
  MIN_CHARS, OK_SENTINEL, MODES,
};

// ────────────────────────────────────────────────────────────────────────────
// CLI —— 三個 caller（codex-consult.ps1／.sh）用這個入口。
//   node consult-answer.js --answer-file <path> [--no-credential] [--schema]
//   stdout: 恰一行 `CONSULT-ANSWER-OK <mode> <verdict>`（僅在 ok 時；verdict 可為空）
//   stderr: 不合格時的理由（caller 原樣轉給使用者）
//   exit  : 0 = 可鑄造；43 = 不可鑄造；2 = 用法/讀檔錯誤
//
// ⚠ 沒有 --min-chars：不提供任何繞過 validity gate 的旗標。
// ⚠ caller **不可只看 exit 0**——空模組、被截斷的檔、被 shim 掉的 node 都會自然 exit 0。
//   一律再確認 stdout 是恰一行且以 OK_SENTINEL 開頭（見三個 caller 的 sentinel 檢查）。
// ⚠ 一律 process.exitCode ＋自然結束，不用 process.exit()——後者會截斷未完成的 stdout。
// ⚠ 讀檔失敗 → exit 2 而不是 43：那是 caller 自己的問題，不該偽裝成「codex 答得不好」。
// ────────────────────────────────────────────────────────────────────────────
if (require.main === module) {
  const fs = require("fs");
  const argv = process.argv.slice(2);
  let answerFile = "";
  let noCredential = false;
  let schemaMode = false;
  let usageError = "";

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--answer-file") { answerFile = argv[++i] || ""; }
    else if (a === "--no-credential") { noCredential = true; }
    else if (a === "--schema") { schemaMode = true; }
    else { usageError = "未知參數: " + a; break; }
  }
  if (!usageError && !answerFile) usageError = "需要 --answer-file <path>";

  if (usageError) {
    process.stderr.write("consult-answer: " + usageError + "\n");
    process.exitCode = 2;
  } else {
    let content = null;
    let readFailed = false;
    try {
      content = fs.readFileSync(answerFile, "utf8");
    } catch (e) {
      process.stderr.write("consult-answer: 讀不到 --answer-file: " + answerFile +
        " (" + e.code + ")\n");
      process.exitCode = 2;
      readFailed = true;
    }
    if (!readFailed) {
      const lines = content.split(/\r?\n/);
      const r = testConsultAnswer({ lines, noCredential, schemaMode });
      if (r.ok) process.stdout.write(OK_SENTINEL + " " + r.mode + " " + r.verdict + "\n");
      else process.stderr.write(r.reason + "\n");
      process.exitCode = r.code;
    }
  }
}
