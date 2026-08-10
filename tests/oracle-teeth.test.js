#!/usr/bin/env node
/*
 * **牙齒檢查**：證明驗證資產本身會失敗。
 *
 * 為什麼需要這一支：2026-08-09 之前，`probe-verdict-cases` 印 56/56、
 * `matcher-contract-cli` 印 70/70，但兩者的 oracle 都不忠實 —— 綠燈完全不代表有在量。
 * 既有的 17/17 變異只證明**模組邏輯**的測試有牙齒，沒證明**CLI oracle** 有牙齒。
 *
 * 做法：對受測資產注入已知缺陷，斷言「對應的測試**必須**失敗，而且失敗原因正確」。
 *
 * ⚠️ **只檢查 exit code 非 0 是不夠的。** syntax error、抽錯檔、不相干案子爆掉
 * 都會讓 exit 非 0，於是變異看起來「被殺掉」其實根本沒測到。所以每個變異都要求：
 *   1. **注入自我檢查**：錨點存在、替換後 bytes 不同、磁碟內容真的變了（比對前後 hash）；
 *   2. 指定的案子**確實出現在失敗清單**；
 *   3. 失敗原因含指定的 **signature**（不是任何錯誤都算）；
 *   4. **對照組**案子仍然通過（證明不是整支垮掉）。
 *
 * ⚠️ 變異一律施加在 **temp 目錄的副本**上，永不改動工作目錄。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");
const { spawnSync } = require("child_process");

const REPO = path.join(__dirname, "..");
const sha = (buf) => crypto.createHash("sha256").update(buf).digest("hex");

const MIRROR_REL = ["windows", "macos", "linux"].map(
  (p) => p + "/skills/超級模式/lib/gate-registration.js"
);
/*
 * 跑 `probe-verdict-cases.test.js` 需要的完整 bundle。
 * ⚠️ 三平台鏡像**都要**帶上：probe 的 `loadShared()` 會逐位元比對三份，
 * 少一份或只改一份都會變成 `TOOL_INTEGRITY_ERROR` —— 那是「因為別的理由而失敗」，
 * 會讓變異看起來被殺掉，其實根本沒測到目標防線。
 */
const PROBE_BUNDLE = [
  "tests/probe-verdict-cases.test.js",
  "tests/lib/cli-outcome.js",
  "tests/lib/verdict-manifest.js",
  "tools/probe-gate-registration.js",
].concat(MIRROR_REL);

/*
 * 每個變異：
 *   id          識別碼
 *   describe    這個變異模擬的是哪一個真實假綠
 *   files       要複製到 temp 的檔案（相對 REPO）
 *   entry       要執行的測試（temp 內的相對路徑）
 *   mutate      { file, find, replace } —— find 必須**恰好出現一次**
 *   mustFail    失敗清單裡必須出現的案子 ID
 *   signature   失敗輸出中必須出現的字串（失敗**原因**，不是只看 exit）
 *   control     必須**仍然通過**的案子 ID（不得出現在失敗清單）
 */
const MUTATIONS = [
  {
    id: "unanchored-regex",
    describe: "把錨定 regex 改回未錨定 —— 這正是 probe-verdict-cases 假綠的成因",
    files: ["tests/lib/cli-outcome.js", "tests/lib/cli-outcome.test.js"],
    entry: "tests/lib/cli-outcome.test.js",
    mutate: {
      file: "tests/lib/cli-outcome.js",
      find: 'const MARKER_RE = /^RESULT_CODE=([A-Z_]+)$/;',
      replace: 'const MARKER_RE = /RESULT_CODE=([A-Z_]+)/;',
    },
    mustFail: ["prose-fake-code/code"],
    signature: "散文那個假標記不該被抓走",
    control: ["ok-stdout/code"],
  },
  {
    id: "drop-cardinality",
    describe: "拿掉「恰一個 marker」的檢查",
    files: ["tests/lib/cli-outcome.js", "tests/lib/cli-outcome.test.js"],
    entry: "tests/lib/cli-outcome.test.js",
    mutate: {
      file: "tests/lib/cli-outcome.js",
      find: "  } else if (all.length > 1) {",
      replace: "  } else if (false) {",
    },
    mustFail: ["two-markers-same-stream/not-ok", "two-markers-cross-stream/not-ok"],
    signature: "two-markers",
    control: ["ok-stdout/code"],
  },
  {
    id: "substring-compare",
    describe: "把 code 精確相等改回 substring —— OK 就能冒充 OK_WITH_DUPLICATES",
    files: ["tests/lib/cli-outcome.js", "tests/lib/cli-outcome.test.js"],
    entry: "tests/lib/cli-outcome.test.js",
    mutate: {
      file: "tests/lib/cli-outcome.js",
      find: "  if (actual.code !== expected.code) {",
      replace: "  if (actual.code !== expected.code && actual.code.indexOf(expected.code) !== 0) {",
    },
    mustFail: ["prefix-collision/rejected"],
    signature: "期望 OK、實測 OK_WITH_DUPLICATES",
    control: ["ok-stdout/code"],
  },
  {
    id: "drop-last-line-rule",
    describe: "拿掉「marker 必須是所在 stream 最後非空行」",
    files: ["tests/lib/cli-outcome.js", "tests/lib/cli-outcome.test.js"],
    entry: "tests/lib/cli-outcome.test.js",
    mutate: {
      file: "tests/lib/cli-outcome.js",
      find: '    if (owner.lastNonEmpty !== "RESULT_CODE=" + m.code) {',
      replace: "    if (false) {",
    },
    mustFail: ["marker-not-last/not-ok"],
    signature: "marker-not-last",
    control: ["ok-stdout/code"],
  },
  {
    id: "concat-streams",
    describe: "把逐 stream 搜尋改回無分隔串接",
    files: ["tests/lib/cli-outcome.js", "tests/lib/cli-outcome.test.js"],
    entry: "tests/lib/cli-outcome.test.js",
    mutate: {
      file: "tests/lib/cli-outcome.js",
      find: "  return actual.streams.out.text.includes(needle) || actual.streams.err.text.includes(needle);",
      replace: "  return (actual.streams.out.text + actual.streams.err.text).includes(needle);",
    },
    mustFail: ["includes/no-splice"],
    signature: "跨 stream 串接出來的字串不該被視為存在",
    control: ["includes/finds-in-stderr"],
  },
  {
    id: "ignore-signal",
    describe: "不再拒絕被信號中止的子程序",
    files: ["tests/lib/cli-outcome.js", "tests/lib/cli-outcome.test.js"],
    entry: "tests/lib/cli-outcome.test.js",
    mutate: {
      file: "tests/lib/cli-outcome.js",
      find: '  if (r.signal != null) problems.push("子程序被信號中止：" + r.signal);\n  if (r.status === null || r.status === undefined) {\n    if (!r.error && r.signal == null) problems.push("退出碼是 null（子程序未正常結束，且未回報 error／signal）");\n  }',
      replace: '  if (r.status === null || r.status === undefined) {\n    if (!r.error && r.signal == null) problems.push("退出碼是 null（子程序未正常結束，且未回報 error／signal）");\n  }',
    },
    mustFail: ["signal/not-ok"],
    signature: "被信號砍掉不能算量到 verdict",
    control: ["ok-stdout/code"],
  },
  // ── 端對端：probe-verdict-cases 這道防線本身有沒有牙齒 ────────────────────
  {
    id: "e2e-prose-fake-marker",
    describe: "把散文裡的假標記種回產品（三鏡像同步）—— 重現 2026-08-09 的靜默假綠",
    files: PROBE_BUNDLE,
    entry: "tests/probe-verdict-cases.test.js",
    mutate: {
      files: MIRROR_REL,
      find: 'out.push("      matcher-contract 對同一份輸入也會停手，但它的 code 是 UNSUPPORTED_EXEC_FORM");',
      replace: 'out.push("      matcher-contract 會回報 RESULT_CODE=UNSUPPORTED_EXEC_FORM。");',
    },
    mustFail: ["halt-exec", "halt-exec-dup", "halt-exec-mixed-files", "halt-echo-args", "halt-args-only"],
    signature: "字面出現 2 次",
    control: ["ok-normal"],
  },
  {
    id: "e2e-wrong-expected-code",
    describe: "把某案的期望 code 改成另一支工具的 code —— manifest 的 exit 配對必須抓到",
    files: PROBE_BUNDLE,
    entry: "tests/probe-verdict-cases.test.js",
    mutate: {
      files: ["tests/probe-verdict-cases.test.js"],
      find: '["halt-exec", S(e([gx()])), undefined, "HALT_EXEC_FORM", 3],',
      replace: '["halt-exec", S(e([gx()])), undefined, "UNSUPPORTED_EXEC_FORM", 3],',
    },
    /*
     * ⚠️ 實測擋下它的是**案例 ↔ manifest 的 orphan 檢查**，不是我原本預期的
     * exit 配對檢查：`UNSUPPORTED_EXEC_FORM` 根本不在 probe 的 manifest 裡
     * （它屬於 matcher），所以更早的那道就先紅了。
     * 這比 exit 配對更精準 —— 它直接指出「你用了另一支工具的 code」。
     * 預估錯的是我，不是測試；所以改預估，不改防線。
     */
    mustFail: [],
    signature: "但 manifest 沒登記（拼錯，或用了另一支工具的 code）",
    control: [],
  },
  {
    id: "e2e-case-deleted",
    describe: "偷偷刪掉一個案子 —— 只看 n/n 的話會印 55/55 全綠",
    files: PROBE_BUNDLE,
    entry: "tests/probe-verdict-cases.test.js",
    mutate: {
      files: ["tests/probe-verdict-cases.test.js"],
      find: '  ["ok-both", S(e([g()])), S(e([g()])), "OK_BOTH", 0],\n',
      replace: "",
    },
    mustFail: [],
    signature: "≠ 宣告的 56",
    control: [],
  },
  {
    id: "e2e-manifest-drift",
    describe: "把 manifest 的 code→exit 配對改掉 —— 必須與產品原始碼對不上",
    files: PROBE_BUNDLE,
    entry: "tests/probe-verdict-cases.test.js",
    mutate: {
      files: ["tests/lib/verdict-manifest.js"],
      find: "  HALT_EXEC_FORM: 3,",
      replace: "  HALT_EXEC_FORM: 1,",
    },
    mustFail: [],
    signature: "配對漂移",
    control: [],
  },
  {
    id: "manifest-not-checked",
    describe: "拿掉 code→exit manifest 的全域契約檢查",
    files: ["tests/lib/cli-outcome.js", "tests/lib/cli-outcome.test.js"],
    entry: "tests/lib/cli-outcome.test.js",
    mutate: {
      file: "tests/lib/cli-outcome.js",
      find: "  if (exitByCode) {",
      replace: "  if (false) {",
    },
    mustFail: ["manifest/catches-drift", "manifest/catches-unregistered"],
    signature: "違反全域契約時必須抓到",
    control: ["ok-stdout/code"],
  },
];

// ── 執行 ────────────────────────────────────────────────────────────────
const work = fs.mkdtempSync(path.join(os.tmpdir(), "oracle-teeth-"));
let pass = 0;
const failed = [];

// 先確認**未變異**時整套是綠的 —— 否則後面每個變異都會「成功」但毫無意義。
{
  const base = path.join(work, "__baseline");
  for (const rel of ["tests/lib/cli-outcome.js", "tests/lib/cli-outcome.test.js"]) {
    const dst = path.join(base, rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(path.join(REPO, rel), dst);
  }
  const r = spawnSync(process.execPath, [path.join(base, "tests/lib/cli-outcome.test.js")], { encoding: "utf8" });
  if (r.status !== 0) {
    console.log("FAIL: __baseline — 未變異時測試就不是綠的，後面的變異結果一律不可信");
    console.log((r.stdout || "") + (r.stderr || ""));
    process.exitCode = 1;
    fs.rmSync(work, { recursive: true, force: true });
    return;
  }
  console.log("baseline（未變異）：PASS —— 變異結果可信");
  console.log("");
}

for (const mut of MUTATIONS) {
  const dir = path.join(work, mut.id);
  const problems = [];

  // 1) 複製
  for (const rel of mut.files) {
    const dst = path.join(dir, rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(path.join(REPO, rel), dst);
  }

  // 2) 注入 ＋ 自我檢查（錨點唯一、bytes 變了、磁碟內容真的變了）
  //    `mutate.files` 為多檔時，同一組 find/replace 會**逐檔**施加 —— 三平台鏡像
  //    必須保持逐位元相同，只改其中一份會退化成 TOOL_INTEGRITY_ERROR。
  const targets = mut.mutate.files || [mut.mutate.file];
  for (const rel of targets) {
    const targetPath = path.join(dir, rel);
    const before = fs.readFileSync(targetPath);
    const beforeHash = sha(before);
    const src = before.toString("utf8");
    const occurrences = src.split(mut.mutate.find).length - 1;
    if (occurrences !== 1) {
      problems.push(rel + "：注入錨點出現 " + occurrences + " 次（必須恰一次）—— 變異沒有施加，結果不可信");
      continue;
    }
    fs.writeFileSync(targetPath, src.replace(mut.mutate.find, mut.mutate.replace));
    const after = fs.readFileSync(targetPath);
    if (sha(after) === beforeHash) problems.push(rel + "：替換後檔案 hash 未變 —— 注入失敗");
    if (after.equals(before)) problems.push(rel + "：磁碟內容未改變 —— 注入失敗");
  }

  // 3) 跑受測測試，要求它失敗
  let out = "";
  if (!problems.length) {
    const r = spawnSync(process.execPath, [path.join(dir, mut.entry)], { encoding: "utf8" });
    out = (r.stdout || "") + (r.stderr || "");
    if (r.status === 0) {
      problems.push("變異後測試仍然通過 —— 這道防線沒有牙齒");
    }
    // 4) 指定案子必須失敗
    for (const id of mut.mustFail) {
      if (out.indexOf("FAIL: " + id) < 0) problems.push("預期失敗的案子「" + id + "」沒有失敗");
    }
    // 5) 失敗原因要對
    if (mut.signature && out.indexOf(mut.signature) < 0) {
      problems.push("失敗原因不含指定 signature「" + mut.signature + "」—— 可能是因為別的錯誤而失敗");
    }
    // 6) 對照組必須仍然通過
    for (const id of mut.control || []) {
      if (out.indexOf("FAIL: " + id) >= 0) {
        problems.push("對照組「" + id + "」也失敗了 —— 變異範圍過寬，不是精準命中");
      }
    }
  }

  if (problems.length) {
    failed.push(mut.id);
    console.log("FAIL: " + mut.id + " — " + problems.join("；"));
    if (out) console.log("      受測輸出：" + out.split("\n").slice(0, 6).join(" | "));
  } else {
    pass++;
    console.log("  殺掉  " + mut.id + " — " + mut.describe);
  }
}

fs.rmSync(work, { recursive: true, force: true });

console.log("");
console.log("TOTAL " + MUTATIONS.length + "  殺掉 " + pass + "  漏掉 " + failed.length);
if (failed.length) {
  console.log("沒被殺掉的變異：" + failed.join(", "));
  process.exitCode = 1;
}
