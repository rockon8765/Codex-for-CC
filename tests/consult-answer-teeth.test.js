#!/usr/bin/env node
/**
 * consult-answer-teeth.test.js —— 證明 tests/consult-answer.test.js 真的有牙齒。
 *
 * 為什麼需要這支：本 repo 實測過「刪掉測試的 stimulus、保留 assertion → 案數不變、全綠、
 * exit 0、mutant 存活」。所以「有測試」「案數對」都不是牙齒的證據。
 *
 * ⚠️ 本檔**刻意不比對失敗總數**。F2 那批的教訓：只比總數時，「該紅的變綠 ＋ 不相關的變紅」
 *    這種等量交換會假綠。這裡釘的是**具名失敗集合的雙向差集**——
 *    少紅了哪一條、多紅了哪一條，兩邊都要印出來並判 FAIL。
 *
 * 做法：把 validator 複製到暫存目錄、套一個字面替換（mutation）、用**同一份** fixtures 跑，
 * 然後比對「實際具名失敗集合」與「預期具名失敗集合」。
 */

"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const REPO = path.join(__dirname, "..");
const LIB_REL = path.join("windows", "skills", "超級模式", "lib", "consult-answer.js");
const LIB = path.join(REPO, LIB_REL);
const FIXTURES = path.join(__dirname, "consult-answer.test.js");

/**
 * 每個 mutant：把 validator 的某個判準改壞，宣告**恰好**哪些具名案例必須因此變紅。
 * 宣告寫窄一點：多紅或少紅都會被抓出來。
 */
const MUTANTS = [
  {
    id: "m1-case-insensitive-verdict",
    why: "把裁決比對改成不分大小寫（PowerShell -match 的預設，正是封存版特地避開的坑）",
    from: 'const VERDICT_RE = /^(ALLOW|BLOCK)\\s*:/;',
    to: 'const VERDICT_RE = /^(ALLOW|BLOCK)\\s*:/i;',
    expect: ["A7 小寫 allow: 不算（大小寫敏感）", "A8 混合大小寫 Allow: 不算"],
  },
  {
    id: "m7-verdict-no-optional-space",
    why: "把裁決 regex 的 \s* 拿掉 → `ALLOW :` 這種合法回覆會被誤判成 BLOCK（cry-wolf）",
    from: 'const VERDICT_RE = /^(ALLOW|BLOCK)\\s*:/;',
    to: "const VERDICT_RE = /^(ALLOW|BLOCK):/;",
    expect: ["C10 動詞與冒號之間允許空白", "C10b TAB 也算"],
  },
  {
    id: "m2-length-counts-characters",
    why: "長度改數字元而非字母數字 → 零寬/變體選擇符/空行都能湊過門檻",
    from: 'const m = String(text).match(/[\\p{L}\\p{N}]/gu);\n  return m ? m.length : 0;',
    to: 'return String(text).length;',
    // ⚠️ A9（零寬湊字數）**不在**預期內，這不是漏寫：零寬是 \p{Cf}，cleanedText 早就剝掉了，
    //    所以它有兩道防線，只弄壞長度計數那道並不會讓它變紅。
    //    （2026-08-18 我第一版把 A9 列進來，被本 harness 抓出「該紅卻沒紅」——留著這行免得再犯。）
    expect: [
      "A11 空行湊長度 → 拒（換行不計）",
      "A12 variation selector 湊字數 → 拒",
      "D2 補充平面字母計入長度（node 語義，刻意）",
    ],
  },
  {
    id: "m3-firstline-no-control-strip",
    why: "firstLine 改用裸 trim() → node 的 trim() 語義洩漏成規格，合法回覆被誤判 BLOCK",
    from: "    const c = trimEdgeInvisible(l);",
    to: "    const c = String(l).trim();",
    // ⚠️ D1e（尾端控制字元）**不在**預期內，這不是漏寫：裁決 regex 是 `^(ALLOW|BLOCK)\s*:`，
    //    只比前綴，所以行尾有什麼都不影響判定 ⇒ D1e 對「兩端 trim 怎麼寫」本來就不敏感。
    //    它的價值是文件性的（記錄尾端控制字元可接受），不是這個 mutant 的牙齒。
    //    （2026-08-18 我第一版把它列進來，被本 harness 抓出「該紅卻沒紅」。）
    expect: ["D1 控制字元開頭的裁決仍接受（維持封存版行為）"],
  },
  {
    // 2026-08-18 設計審查抓到的真缺陷：整行剝除會把 AL<TAB>LOW: 洗成 ALLOW: 而放行。
    // 這個 mutant 就是把它還原回去，確認 fixtures 抓得到。
    id: "m3b-firstline-strips-whole-line",
    why: "firstLine 改回「整行剝除」→ 行中間的控制字元被洗掉，AL<TAB>LOW: 會被當成合法裁決",
    from: '    .replace(/^[\\p{Cc}\\p{Cf}\\s]+/u, "")\n    .replace(/[\\p{Cc}\\p{Cf}\\s]+$/u, "");',
    to: '    .replace(/[\\p{Cc}\\p{Cf}]/gu, "").trim();',
    expect: [
      "D1b 行中間的 TAB 不得被洗掉",
      "D1c 行中間的 NUL 不得被洗掉",
      "D1d 行中間的 U+0085 不得被洗掉",
    ],
  },
  {
    id: "m4-length-before-nocredential",
    why: "把長度門檻搬回 noCredential 之前（＝封存版的順序）→ 日常討論諮詢開始 cry-wolf",
    from: "  if (noCredential) {\n    // 討論模式不鑄造憑證 → 只要不是空的就放行，不套長度與裁決門檻（見上方 ③ 的說明）。\n    return { ok: true, code: 0, mode: MODES.DISCUSSION, verdict: \"\", reason: \"\" };\n  }\n\n  const meaningful = meaningfulLength(text);",
    to: "  const meaningful = meaningfulLength(text);",
    // 這個 mutation 把整個 discussion 分支拿掉（不只是換順序），所以三條都該紅：
    // 短回覆、無裁決的討論回覆，以及檢查 mode 列舉的那條。
    expect: [
      "D3 討論模式：短回覆也放行（刻意改自封存版）",
      "D3b 討論模式：無裁決首行也放行",
      "C8 mode 是列舉且 verdict 只在 verdict 模式有值",
    ],
  },
  {
    id: "m5-schema-validates-cleaned",
    why: "schema 改驗 cleaned 而非 raw → 等於幫非法輸出把不可見字元清掉再放行",
    from: "      JSON.parse(raw);",
    to: "      JSON.parse(text);",
    expect: ["A16 schema 驗 raw 不驗 cleaned（清理後再 parse 等於幫非法輸出修好）"],
  },
  {
    id: "m6-flags-accept-truthiness",
    why: "旗標改吃 JS truthiness → 呼叫端把 \"false\" 之類的字串傳進來會被默默當成 true",
    from: '  if (typeof v !== "boolean") throw new TypeError(name + " 必須是 boolean，收到 " + typeof v);',
    to: "  if (typeof v !== \"boolean\") return Boolean(v);",
    expect: ["C6 非 boolean 旗標會 throw"],
  },
];

// ── harness ────────────────────────────────────────────────────────────────
const original = fs.readFileSync(LIB, "utf8");
let pass = 0, fail = 0;
const failed = [];

function check(name, cond, detail) {
  if (cond) { pass++; return true; }
  fail++; failed.push(name);
  console.log("  FAIL  " + name + (detail ? "\n" + detail : ""));
  return false;
}

/** 跑一次 fixtures，回 { rc, failedNames }。 */
function runFixtures(libOverride) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "consult-teeth-"));
  const shim = path.join(tmp, "shim.js");
  // fixtures 用 require(LIB) 直接載入；改用 module cache 注入太脆弱，
  // 這裡改成實際覆寫檔案再還原（單執行緒、finally 一定還原）。
  fs.rmSync(tmp, { recursive: true, force: true });
  void shim;

  if (libOverride !== null) fs.writeFileSync(LIB, libOverride, "utf8");
  let out = "", rc = 0;
  try {
    out = execFileSync(process.execPath, [FIXTURES], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    out = (e.stdout || "") + (e.stderr || "");
    rc = e.status === undefined ? -1 : e.status;
  }
  // ⚠️ 解析機器可讀的 `FAILED-CASE:` 行，不解析人類版的「、」分隔清單——
  //    案例名稱本身可能含「、」，用它當分隔符會把一條切成兩條（2026-08-18 實際踩到，
  //    當時 m4 多報了兩條不存在的「不該紅卻紅了」）。
  const failedNames = out.split(/\r?\n/)
    .filter((l) => l.startsWith("FAILED-CASE: "))
    .map((l) => l.slice("FAILED-CASE: ".length).trim())
    .filter(Boolean);
  return { rc, failedNames, out };
}

function diffSets(actual, expected) {
  const missing = expected.filter((x) => !actual.includes(x)); // 該紅卻沒紅
  const extra = actual.filter((x) => !expected.includes(x));   // 不該紅卻紅了
  return { missing, extra };
}

try {
  console.log("§0 基準（未變異）必須全綠");
  const base = runFixtures(null);
  check("基準 rc=0", base.rc === 0, "        rc=" + base.rc);
  check("基準無具名失敗", base.failedNames.length === 0, "        " + base.failedNames.join("、"));

  console.log("\n§1 變異對照（比對具名失敗集合，不比總數）");
  for (const mut of MUTANTS) {
    const occurrences = original.split(mut.from).length - 1;
    // 注入自檢：錨點必須**恰好命中一次**。命中 0 次＝變異沒生效卻可能全綠（假牙齒）；
    // 命中多次＝改到不只一處，失敗集合就解釋不了。本 repo 兩種都踩過。
    if (!check(mut.id + " 錨點恰好命中一次", occurrences === 1,
      "        實際命中 " + occurrences + " 次 —— 變異未生效或改到多處，本案結果不可信")) continue;

    const mutated = original.split(mut.from).join(mut.to);
    const r = runFixtures(mutated);
    const { missing, extra } = diffSets(r.failedNames, mut.expect);
    const okSet = missing.length === 0 && extra.length === 0;
    const detail =
      "        why: " + mut.why + "\n" +
      "        rc=" + r.rc + " 具名失敗 " + r.failedNames.length + " 條（預期 " + mut.expect.length + "）\n" +
      missing.map((x) => "        ❌ 該紅卻沒紅：" + x).join("\n") +
      (missing.length && extra.length ? "\n" : "") +
      extra.map((x) => "        ❌ 不該紅卻紅了：" + x).join("\n");
    check(mut.id + " 具名失敗集合相符", okSet, detail);
    check(mut.id + " rc=1", r.rc === 1, "        rc=" + r.rc);
  }
} finally {
  fs.writeFileSync(LIB, original, "utf8");
}

// 還原自檢：跑完必須回到基準全綠，否則後面所有測試都建立在被污染的檔案上。
const after = runFixtures(null);
check("還原後仍全綠", after.rc === 0 && after.failedNames.length === 0,
  "        rc=" + after.rc + " " + after.failedNames.join("、"));

console.log("");
console.log("CONSULT-ANSWER-TEETH " + pass + "/" + (pass + fail));
if (fail > 0) {
  console.log("失敗清單：" + failed.join("、"));
  process.exitCode = 1;
}
