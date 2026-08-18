#!/usr/bin/env node
/**
 * consult-answer.test.js —— 憑證鑄造判準的行為 fixtures。
 *
 * 分工（重要，別把兩件事混為一談）：
 *   tests/gate-registration.test.js §C  只證明「三份 node 副本逐位元相同」。
 *   本檔                                 證明「這份邏輯的行為是我們要的」。
 *   byte 相同 ≠ 移植忠實 —— 沒有本檔，三份可以一起錯。
 *
 * 為什麼判準要抽成純函式：鑄造條件本來只能用「真的叫一次 Codex」來驗，等於沒有自動化
 * 測試（要額度、要網路、CI 跑不了）。抽成無副作用的純函式後就能直接餵假回覆做分支測試。
 *
 * 案例來源：
 *   [A*]  移植自封存的 consult-answer.tests.ps1（380462f）——行為必須相符。
 *   [D*]  對封存版的**刻意**行為裁決（見 lib 檔頭 D1／D2）。
 *   [C*]  2026-08-18 設計審查新增（strict JSON 子集、旗標型別、求值順序組合）。
 */

"use strict";

const path = require("path");
const assert = require("assert");

const LIB = path.join(__dirname, "..", "windows", "skills", "超級模式", "lib", "consult-answer.js");
const M = require(LIB);

let pass = 0, fail = 0;
const failed = [];

function check(name, cond, detail) {
  if (cond) { pass++; return true; }
  fail++; failed.push(name);
  console.log("  FAIL  " + name + (detail ? "\n        " + detail : ""));
  return false;
}

function t(name, opts, pred, describe) {
  let r;
  try { r = M.testConsultAnswer(opts); }
  catch (e) { r = { threw: e.message }; }
  check(name, pred(r), describe ? describe(r) : JSON.stringify(r));
}

const LONG = "x".repeat(60);
const ZW = "​";          // zero-width space      -> \p{Cf}
const VS = "️";          // variation selector    -> \p{Mn}（不在 Cf，剝除式做法漏得掉）
const NEL = "";         // next line             -> \p{Cc}（.NET Trim 視為空白，JS 不）
const SUP = "\u{1D400}";      // MATHEMATICAL BOLD A   -> \p{L}，但在 UTF-16 是代理對
const CJK = "本次變更的風險集中在憑證鑄造條件建議先在單機驗證後再考慮同步其他平台理由如下所述";

console.log("§A 移植自 380462f 的行為（必須相符）");
t("A1 ALLOW 首行 + 足量 → 鑄造", { lines: ["ALLOW: 可以做", LONG] },
  (r) => r.ok && r.verdict === "ALLOW" && r.mode === "verdict");
t("A2 BLOCK 首行也鑄造（憑證是收據不是授權）", { lines: ["BLOCK: 不要做", LONG] },
  (r) => r.ok && r.verdict === "BLOCK");
t("A3 首行 = 第一個非空行", { lines: ["", "   ", "ALLOW: 前面有空行", LONG] },
  (r) => r.ok && r.verdict === "ALLOW");
t("A4 空回覆 → 43", { lines: [] }, (r) => !r.ok && r.code === 43 && /UNUSABLE/.test(r.reason));
t("A5 過短 → 43", { lines: ["HELLO"] }, (r) => !r.ok && r.code === 43);
t("A6 夠長但無裁決 → NO_VERDICT", { lines: ["有限狀態機是一種模型，用來描述系統行為。" + LONG] },
  (r) => !r.ok && /NO_VERDICT/.test(r.reason));
t("A7 小寫 allow: 不算（大小寫敏感）", { lines: ["allow: 小寫不算", LONG] },
  (r) => !r.ok && /NO_VERDICT/.test(r.reason));
t("A8 混合大小寫 Allow: 不算", { lines: ["Allow: 混合", LONG] }, (r) => !r.ok);
t("A9 零寬字元湊字數 → 拒", { lines: ["ALLOW:" + ZW.repeat(60)] }, (r) => !r.ok && r.code === 43);
t("A10 有裁決但整體過短 → 仍拒（門檻不因裁決豁免）", { lines: ["ALLOW: ok"] }, (r) => !r.ok);
t("A11 空行湊長度 → 拒（換行不計）",
  { lines: ["ALLOW:"].concat(new Array(34).fill("")).concat(["x"]) }, (r) => !r.ok);
t("A12 variation selector 湊字數 → 拒", { lines: ["ALLOW:" + VS.repeat(60)] }, (r) => !r.ok);
t("A13 正常中文回覆不誤殺", { lines: ["ALLOW: 可以", CJK] },
  (r) => r.ok && r.verdict === "ALLOW");
t("A14 schema：短 JSON 也接受（不套字數門檻）", { lines: ['{"ok":true}'], schemaMode: true },
  (r) => r.ok && r.mode === "json");
t("A15 schema：散文不是 JSON → 拒（不能拿 schema 當免驗金牌）",
  { lines: ["這不是 JSON，只是四十個字以上的散文說明文字，用來確認不能當免驗金牌。"], schemaMode: true },
  (r) => !r.ok && /NOT_JSON/.test(r.reason));
t("A16 schema 驗 raw 不驗 cleaned（清理後再 parse 等於幫非法輸出修好）",
  { lines: ['{"ok":tru' + ZW + 'e}'], schemaMode: true }, (r) => !r.ok && /NOT_JSON/.test(r.reason));

console.log("\n§D 對封存版的刻意行為裁決（不是意外分歧）");
// D1：.NET 的 Trim() 視 U+0085 為空白、JS 的不視為。若照 JS 原樣，合法回覆會被誤判 NO_VERDICT。
//     那是錯誤方向的失敗（cry-wolf），所以 firstLine 明確剝除 \p{Cc}\p{Cf} → 維持封存版的「接受」。
t("D1 控制字元開頭的裁決仍接受（維持封存版行為）", { lines: [NEL + "ALLOW: 可以", LONG] },
  (r) => r.ok && r.verdict === "ALLOW",
  (r) => "若這裡 FAIL，代表 firstLine 沒剝控制字元，node 的 trim() 語義洩漏成規格：" + JSON.stringify(r));
// D2：.NET regex 走 UTF-16 code unit，代理對兩半是 \p{Cs} 不是 \p{L} → 封存版不計；node /u 計。
//     採 node 語義（門檻本意是「有沒有實質內容」，𝐀 本來就是字母）。
check("D2 補充平面字母計入長度（node 語義，刻意）", M.meaningfulLength(SUP.repeat(50)) === 50,
  "實得 " + M.meaningfulLength(SUP.repeat(50)) + "，預期 50；若為 0 代表退回 .NET 的 UTF-16 語義");
t("D2b 補充平面字母可湊過門檻（已知代價，威脅模型不含刻意 padding）",
  { lines: ["ALLOW: x", SUP.repeat(50)] }, (r) => r.ok);
// D3：討論模式改成只驗非空。封存版把長度門檻擺在 noCredential 之前，於是每次日常討論諮詢
//     都得湊滿 40 字；那條路徑根本不鑄造憑證，套硬門檻只會製造高頻 cry-wolf。
t("D3 討論模式：短回覆也放行（刻意改自封存版）", { lines: ["短"], noCredential: true },
  (r) => r.ok && r.mode === "discussion");
t("D3b 討論模式：無裁決首行也放行", { lines: ["一段沒有裁決首行的正常討論回覆。" + LONG], noCredential: true },
  (r) => r.ok && r.mode === "discussion");
t("D3c 討論模式：空的仍然拒（唯一保留的門檻）", { lines: ["   ", ""], noCredential: true },
  (r) => !r.ok && r.code === 43);

// D1b：只剝**兩端**。整行剝除會把 AL<TAB>LOW: 洗成 ALLOW: 而放行——遠超 D1 宣稱的範圍，
//      且與封存版（.NET Trim() 也只清兩端）不同。2026-08-18 設計審查抓到我第一版寫成整行剝除。
t("D1b 行中間的 TAB 不得被洗掉", { lines: ["AL\tLOW: ok", LONG] }, (r) => !r.ok,
  (r) => "AL<TAB>LOW: 被當成 ALLOW 了：" + JSON.stringify(r));
t("D1c 行中間的 NUL 不得被洗掉", { lines: ["A\u0000LLOW: ok", LONG] }, (r) => !r.ok);
t("D1d 行中間的 U+0085 不得被洗掉", { lines: ["AL" + NEL + "LOW: ok", LONG] }, (r) => !r.ok);
t("D1e 尾端控制字元仍接受（兩端都剝）", { lines: ["ALLOW: 可以" + NEL, LONG] },
  (r) => r.ok && r.verdict === "ALLOW");
// 哨兵文法：caller 不可只比前綴（`CONSULT-ANSWER-OK-FAKE …` 會通過前綴檢查）。
check("C0 假哨兵不符文法", !M.OK_SENTINEL_RE.test("CONSULT-ANSWER-OK-FAKE verdict ALLOW"),
  "CONSULT-ANSWER-OK-FAKE 竟然符合文法");
check("C0b 三種合法哨兵都符合文法",
  M.OK_SENTINEL_RE.test("CONSULT-ANSWER-OK verdict ALLOW") &&
  M.OK_SENTINEL_RE.test("CONSULT-ANSWER-OK verdict BLOCK") &&
  M.OK_SENTINEL_RE.test("CONSULT-ANSWER-OK discussion") &&
  M.OK_SENTINEL_RE.test("CONSULT-ANSWER-OK json"), "合法哨兵被文法拒絕");
check("C0c 帶尾隨空白的哨兵不符文法", !M.OK_SENTINEL_RE.test("CONSULT-ANSWER-OK discussion "),
  "尾隨空白被接受");

console.log("\n§C 2026-08-18 設計審查新增");
// 裁決文法：實作是 `^(ALLOW|BLOCK)\s*:`，三份 SKILL.md 原本寫成 `^(ALLOW|BLOCK):`。
// 2026-08-18 設計審查指出這個不一致會直接改變是否鑄證。
// 裁決：**改文件不改實作**——拒絕 `ALLOW :` 屬錯誤方向的失敗（cry-wolf），
// 且改 regex 會讓 macOS 對 validator 的原生驗證失效。這幾條把實際文法釘住。
t("C10 動詞與冒號之間允許空白", { lines: ["ALLOW   : ok", LONG] },
  (r) => r.ok && r.verdict === "ALLOW");
t("C10b TAB 也算", { lines: ["ALLOW	: ok", LONG] },
  (r) => r.ok && r.verdict === "ALLOW");
t("C10c 動詞後接其他字母不算", { lines: ["ALLOWX: ok", LONG] }, (r) => !r.ok);
t("C10d 沒有冒號不算", { lines: ["ALLOW ok", LONG] }, (r) => !r.ok);

t("C1 schema 優先於 noCredential（求值順序）",
  { lines: ['{"ok":true}'], schemaMode: true, noCredential: true }, (r) => r.ok && r.mode === "json");
t("C2 strict JSON：trailing comma 拒", { lines: ['{"a":1,}'], schemaMode: true }, (r) => !r.ok);
t("C3 strict JSON：NaN 拒", { lines: ['{"a":NaN}'], schemaMode: true }, (r) => !r.ok);
t("C4 strict JSON：leading zero 拒", { lines: ['{"a":01}'], schemaMode: true }, (r) => !r.ok);
t("C5 strict JSON：註解拒", { lines: ['{"a":1} // hi'], schemaMode: true }, (r) => !r.ok);
// 旗標不吃 JS truthiness：呼叫端寫錯要當場炸，不是猜。
check("C6 非 boolean 旗標會 throw", (() => {
  try { M.testConsultAnswer({ lines: ["x"], noCredential: 1 }); return false; }
  catch (e) { return /boolean/.test(e.message); }
})(), "truthiness 被默默接受了");
// 不提供任何繞過門檻的途徑。
check("C7 minChars 不可設為 0/負數", (() => {
  try { M.testConsultAnswer({ lines: ["x"], minChars: 0 }); return false; }
  catch (e) { return true; }
})(), "門檻可被繞過");
check("C8 mode 是列舉且 verdict 只在 verdict 模式有值", (() => {
  const a = M.testConsultAnswer({ lines: ["ALLOW: x", LONG] });
  const b = M.testConsultAnswer({ lines: ['{"ok":1}'], schemaMode: true });
  const c = M.testConsultAnswer({ lines: ["hi"], noCredential: true });
  return a.mode === "verdict" && a.verdict === "ALLOW" &&
         b.mode === "json" && b.verdict === "" &&
         c.mode === "discussion" && c.verdict === "";
})(), "SCHEMA/DISCUSSION 又被塞進 verdict 了");
// 函式契約 ≠ 程序契約：它回 code，不 exit。
check("C9 函式回傳 code、不自己 exit", (() => {
  const r = M.testConsultAnswer({ lines: [] });
  return r.code === 43 && typeof r.ok === "boolean" && !("exitCode" in r);
})(), "函式開始有程序語義了");

console.log("");
console.log("CONSULT-ANSWER " + pass + "/" + (pass + fail));
if (fail > 0) {
  console.log("失敗清單：" + failed.join("、"));
  // 機器可讀的具名失敗清單：一行一條，供 consult-answer-teeth.test.js 做集合比對。
  // ⚠️ 刻意不重用上面那行「、」分隔的人類版——案例名稱本身就可能含「、」，
  //    用它當分隔符會把一條切成兩條（2026-08-18 實際踩到）。
  for (const name of failed) console.log("FAILED-CASE: " + name);
  process.exitCode = 1;
}
