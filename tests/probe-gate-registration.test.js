#!/usr/bin/env node
/*
 * tools/probe-gate-registration.js 的回歸案。
 *
 * 用法：
 *   node tests/probe-gate-registration.test.js
 *   node tests/probe-gate-registration.test.js --probe <path>   # 反向驗證用：指向舊版 probe
 *
 * 三平台共用（純 Node，不依賴 shell）。每個案子開一個假 HOME，寫 fixture，
 * 用子程序跑 probe，斷言**退出碼 ＋ 應出現／不應出現的字串**。
 *
 * ⚠️ 斷言刻意不只看退出碼。2026-08-08 的教訓：反向驗證只核對總數時，
 * 無從得知失敗的是不是「該失敗的那幾條」——例如舊版對「頂層 null」會因
 * 未捕捉的 TypeError 湊巧也 exit 1，但它印的是 stack trace 而不是判定。
 *
 * 反向驗證（對 `5cc50e0` 那版 heredoc probe）預期失敗的案子，見
 * docs/MIGRATION-hook-settings-target.md 檔頭的修訂註記。
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

// ── 參數 ────────────────────────────────────────────────────────────────
let probe = path.join(__dirname, "..", "tools", "probe-gate-registration.js");
for (let i = 2; i < process.argv.length; i++) {
  if (process.argv[i] === "--probe") {
    if (!process.argv[i + 1]) {
      console.error("--probe 後面要接路徑");
      process.exit(2);
    }
    probe = process.argv[++i];
  } else {
    console.error("未知參數：" + process.argv[i]);
    process.exit(2);
  }
}
if (!fs.existsSync(probe)) {
  console.error("找不到 probe：" + probe);
  process.exit(2);
}
console.log("受測 probe：" + probe);

// ── fixture 素材 ────────────────────────────────────────────────────────
const MATCHER = "Write|Edit|NotebookEdit|Bash|PowerShell|Monitor|mcp__.*";
const CMD = "node /home/u/.claude/hooks/super-mode-consult-gate.js";
const CMD_STALE = "node /old/path/super-mode-consult-gate.js";

const gateHandler = (cmd) => ({ type: "command", command: cmd || CMD });
// exec form：args 存在時 command 只是可執行檔名，needle 在 args 裡
const gateExec = (p) => ({ type: "command", command: "node", args: [p || "/home/u/.claude/hooks/super-mode-consult-gate.js"] });
const execEntry = (p) => ({ matcher: MATCHER, hooks: [gateExec(p)] });
const gateEntry = (cmd, matcher) => ({
  matcher: matcher === undefined ? MATCHER : matcher,
  hooks: [gateHandler(cmd)],
});
const settings = (...entries) => ({ hooks: { PreToolUse: entries } });

// ── 案例矩陣 ────────────────────────────────────────────────────────────
// exit 1 = 讀不到／形狀不合（fail-closed）｜exit 3 = 停手｜exit 0 = 判定可執行
const CASES = [
  // ---- fail-closed：形狀不合，一律 exit 1 -------------------------------
  // fail-closed 這條路徑也要印範圍（先前 exit 1 時完全不印）
  { id: "invalid-json", main: { raw: "{ 這不是 JSON" }, exit: 1, want: ["JSON 解析失敗", "無法解析或形狀不合", "大小寫敏感"] },
  { id: "top-null", main: null, exit: 1, want: ["頂層不是物件（是 null）"] },
  { id: "top-array", main: [], exit: 1, want: ["頂層不是物件（是 陣列）"] },
  { id: "hooks-string", main: { hooks: "x" }, exit: 1, want: ["hooks 不是物件（是 string）"] },
  { id: "pretooluse-object", main: { hooks: { PreToolUse: {} } }, exit: 1, want: ["hooks.PreToolUse 不是陣列（是 object）"] },
  // ↓ 這就是舊版的假陰性：字串會被逐字元迭代、靜默數成 0
  { id: "pretooluse-string", main: { hooks: { PreToolUse: CMD } }, exit: 1, want: ["hooks.PreToolUse 不是陣列（是 string）"], deny: ["兩邊都沒有 gate"] },
  { id: "entry-not-object", main: settings("x"), exit: 1, want: ["PreToolUse[0] 不是物件（是 string）"] },
  { id: "entry-hooks-not-array", main: settings({ matcher: MATCHER, hooks: "x" }), exit: 1, want: ["PreToolUse[0].hooks 不是陣列（是 string）"] },
  { id: "handler-not-object", main: settings({ matcher: MATCHER, hooks: ["x"] }), exit: 1, want: ["PreToolUse[0].hooks[0] 不是物件（是 string）"] },
  { id: "command-not-string", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: [CMD] }] }), exit: 1, want: ["PreToolUse[0].hooks[0].command 不是字串（是 陣列）"] },
  { id: "type-missing", main: settings({ matcher: MATCHER, hooks: [{ command: CMD }] }), exit: 1, want: ["command 含 gate，但 type 是 缺漏"], deny: ["正常，不用修"] },
  { id: "type-prompt", main: settings({ matcher: MATCHER, hooks: [{ type: "prompt", command: CMD }] }), exit: 1, want: ['command 含 gate，但 type 是 "prompt"'], deny: ["正常，不用修"] },
  { id: "matcher-not-string", main: settings({ matcher: 5, hooks: [gateHandler()] }), exit: 1, want: ["PreToolUse[0].matcher 不是字串（是 number）"] },
  // 混合案：第一筆合法、第二筆 type 壞掉 —— existential 寫法會在這裡假綠
  { id: "mixed-good-then-bad", main: settings(gateEntry(), { matcher: MATCHER, hooks: [{ type: "prompt", command: CMD }] }), exit: 1, want: ["PreToolUse[1].hooks[0] 的 command 含 gate"], deny: ["正常，不用修"] },
  // local 壞掉、main 正常 —— 證明兩個檔都驗
  { id: "local-invalid-main-ok", main: settings(gateEntry()), local: { raw: "{" }, exit: 1, want: ["JSON 解析失敗"], deny: ["正常，不用修"] },

  // ---- 停手：需要人工判斷，exit 3 --------------------------------------
  { id: "halt-shared-entry", main: settings({ matcher: MATCHER, hooks: [gateHandler(), { type: "command", command: "node /other/hook.js" }] }), exit: 3, want: ["還有 1 個非 gate 的 handler", "判定：停手", "大小寫敏感"] },
  { id: "halt-main2-diff-command", main: settings(gateEntry(), gateEntry(CMD_STALE)), exit: 3, want: ["matcher／command 不一致", "判定：停手"] },
  { id: "halt-main2-diff-matcher", main: settings(gateEntry(), gateEntry(CMD, "Bash")), exit: 3, want: ["matcher／command 不一致", "判定：停手"] },
  // ↓ Codex 2026-08-08 指出的回歸路徑：main 一筆 stale ＋ local 一筆正確。
  //   只比 settings.json 的話會判成 B（純減法），使用者刪光 local 只留壞的那筆。
  { id: "halt-main-stale-local-good", main: settings(gateEntry(CMD_STALE)), local: settings(gateEntry()), exit: 3, want: ["判定：停手"], deny: ["『B. 已經有一筆』"] },
  { id: "halt-local2-diff", local: settings(gateEntry(), gateEntry(CMD_STALE)), exit: 3, want: ["判定：停手"] },

  // ---- 判定可執行：exit 0 ----------------------------------------------
  { id: "ok-normal", main: settings(gateEntry()), exit: 0, want: ["gate 條目：1 個", "檔案不存在", "正常，不用修"] },
  // 真機 census 樣本：local 存在但沒有 hooks 段
  { id: "ok-normal-local-no-hooks", main: settings(gateEntry()), local: { permissions: {} }, exit: 0, want: ["沒有 hooks 段 —— gate 條目：0 個", "正常，不用修"] },
  { id: "ok-duplicate-identical", main: settings(gateEntry(), gateEntry()), exit: 0, want: ["有 2 筆 gate", "已經重複註冊", "『B. 已經有一筆』"] },
  { id: "ok-both-identical", main: settings(gateEntry()), local: settings(gateEntry()), exit: 0, want: ["兩邊都有", "『B. 已經有一筆』"] },
  { id: "ok-local-only", main: { hooks: { PreToolUse: [] } }, local: settings(gateEntry()), exit: 0, want: ["受影響", "『A. 還沒有』"] },
  // 每條退出路徑都要印範圍。這條（0 筆 → AI-INSTALL 會叫人新增）最需要看到
  // 「needle 大小寫敏感」的警告，先前卻是唯一看不到的。
  { id: "ok-none-both-missing", exit: 0, want: ["檔案不存在", "兩邊都沒有 gate", "大小寫敏感"] },
  { id: "ok-none-no-pretooluse", main: { hooks: { PostToolUse: [] } }, exit: 0, want: ["沒有 hooks.PreToolUse —— gate 條目：0 個", "兩邊都沒有 gate"] },
  { id: "ok-none-nongate-handler", main: settings({ matcher: "Bash", hooks: [{ type: "command", command: "node /other/hook.js" }] }), exit: 0, want: ["gate 條目：0 個", "兩邊都沒有 gate"] },
  { id: "ok-bom", main: { raw: "\uFEFF" + JSON.stringify(settings(gateEntry())) }, exit: 0, want: ["正常，不用修"] },
  { id: "ok-entry-without-hooks-key", main: settings({ matcher: "Bash" }, gateEntry()), exit: 0, want: ["gate 條目：1 個", "正常，不用修"] },
  // 使用者本來就有的、與本 skill 無關的 PreToolUse 條目：不能被算進來，也不能觸發停手
  { id: "ok-gate-plus-unrelated-entry", main: settings({ matcher: "Bash", hooks: [{ type: "command", command: "node /other/hook.js" }] }, gateEntry()), exit: 0, want: ["gate 條目：1 個", "正常，不用修"] },
  // 同一個 entry 裡兩筆**相同**的 gate handler：others=0，不該判停手，該判重複註冊
  { id: "ok-two-gate-same-entry", main: settings({ matcher: MATCHER, hooks: [gateHandler(), gateHandler()] }), exit: 0, want: ["有 2 筆 gate", "已經重複註冊"], deny: ["判定：停手"] },
  // 讀取錯誤（非 ENOENT）：settings.json 是目錄。錯誤碼各平台可能不同，只斷言前綴。
  { id: "read-error-directory", main: { dir: true }, exit: 1, want: ["讀取失敗：", "無法解析或形狀不合"] },

  // ---- exec form（Claude Code 官方支援的第二種 command hook 形態）-------
  // 本工具**只判斷 shell form**：看到 exec form 一律 exit 3。
  // 理由見模組註解：`args` 存在與否會改變 runtime 語義，光比字串無法安全判斷兩筆註冊
  // 是不是同一筆；判「沒有 gate」則會叫人再加一筆（自己製造重複註冊）。
  // matcher-contract 對同一份輸入回報 UNSUPPORTED_EXEC_FORM，兩邊一致。
  // 「大小寫敏感」是範圍說明裡的字串——每個 exit 3 路徑也要印，所以在這裡釘住
  { id: "halt-exec-form", main: settings(execEntry()), exit: 3, want: ["exec form", "判定：停手", "大小寫敏感"], deny: ["正常，不用修", "兩邊都沒有 gate"] },
  { id: "halt-duplicate-exec-form", main: settings(execEntry(), execEntry()), exit: 3, want: ["exec form", "判定：停手"], deny: ["已經重複註冊"] },
  { id: "halt-mixed-forms", main: settings(gateEntry()), local: settings(execEntry()), exit: 3, want: ["exec form", "判定：停手"], deny: ["正常，不用修"] },
  // needle 出現在 args 但根本不是在跑 gate —— 舊寫法會判「正常，已裝好」，是假陽性
  { id: "halt-echo-args-needle", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: "echo", args: ["super-mode-consult-gate"] }] }), exit: 3, want: ["exec form", "判定：停手"], deny: ["正常，不用修"] },
  // 只有 args、沒有 command：官方 schema 要求 command，但這裡不當 schema 驗證器，一律停手
  { id: "halt-args-only-no-command", main: settings({ matcher: MATCHER, hooks: [{ type: "command", args: ["/x/super-mode-consult-gate.js"] }] }), exit: 3, want: ["exec form", "判定：停手"], deny: ["正常，不用修"] },
  { id: "exec-form-type-prompt", main: settings({ matcher: MATCHER, hooks: [{ type: "prompt", command: "node", args: ["/x/super-mode-consult-gate.js"] }] }), exit: 1, want: ['type 是 "prompt"'], deny: ["正常，不用修"] },
  { id: "args-not-array", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: "node", args: "/x/super-mode-consult-gate.js" }] }), exit: 1, want: ["PreToolUse[0].hooks[0].args 不是陣列（是 string）"] },
  { id: "args-element-not-string", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: "node", args: [7, "/x/super-mode-consult-gate.js"] }] }), exit: 1, want: ["PreToolUse[0].hooks[0].args[0] 不是字串（是 number）"] },
  // 不相干的 exec-form handler（args 裡沒有 needle）不能被算進來
  { id: "ok-unrelated-exec-form", main: settings({ matcher: "Bash", hooks: [{ type: "command", command: "node", args: ["/other/hook.js"] }] }), exit: 0, want: ["gate 條目：0 個", "兩邊都沒有 gate"] },

  // ---- 釘住「本工具**不驗**什麼」（範圍說明的正面對照）------------------
  // 這兩個形狀依官方 schema 是不合法的，但本工具**刻意放行**——它不是 schema 驗證器，
  // 對不相干的條目過度 fail-closed 會把使用者的 migration 擋死。
  // 之所以要用測試釘住：這一句先前寫錯過兩次（先寫成「無關的畸形會被略過」，
  // 與實作相反；再寫成「唯二例外」，漏了這一類）。文案與行為必須被同一組斷言綁住。
  { id: "scope-nongate-bad-type-passes", main: settings({ matcher: "Bash", hooks: [{ type: 7, command: "node /other/hook.js" }] }), exit: 0, want: ["gate 條目：0 個", "兩邊都沒有 gate", "非 gate 的 handler 不驗 type 的型別"] },
  { id: "scope-command-type-without-command-passes", main: settings({ matcher: "Bash", hooks: [{ type: "command" }] }), exit: 0, want: ["gate 條目：0 個", "兩邊都沒有 gate"] },

  // ---- type 的其餘合法值（官方共五種，只有 command 會執行 command 欄位）--------
  // 修正前只在案例裡釘了 prompt；http／mcp_tool／agent 同樣不會執行 gate。
  { id: "type-http", main: settings({ matcher: MATCHER, hooks: [{ type: "http", command: CMD }] }), exit: 1, want: ['command 含 gate，但 type 是 "http"'], deny: ["正常，不用修"] },
  { id: "type-mcp-tool", main: settings({ matcher: MATCHER, hooks: [{ type: "mcp_tool", command: CMD }] }), exit: 1, want: ['command 含 gate，但 type 是 "mcp_tool"'], deny: ["正常，不用修"] },
  { id: "type-agent", main: settings({ matcher: MATCHER, hooks: [{ type: "agent", command: CMD }] }), exit: 1, want: ['command 含 gate，但 type 是 "agent"'], deny: ["正常，不用修"] },

  // ---- 不安全欄位：JSON 合法、type 正確，但 gate 不會如預期阻擋 ---------------
  // 修正前這五種**兩支工具都印「正常／PASS」**（假 HOME 實測，見 docs/backlog.md）。
  // 官方 hooks reference 有這些欄位，所以它們不是畸形資料，是會生效的設定。
  { id: "unsafe-if", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, if: "Bash(git push *)" }] }), exit: 1, want: ["判定：設定不安全", "帶 if=", "其餘工具完全不受攔", "不要 append"], deny: ["判定：正常，不用修。"] },
  // ⚠️ once **不是**不安全欄位：官方明訂它只在 skill frontmatter 生效、settings 檔裡會被忽略。
  // 本批曾一度擋它（誤紅，會無故弄壞既有使用者的安裝驗收），合併前審查抓到並改回。
  { id: "once-must-pass", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, once: true }] }), exit: 0, want: ["判定：正常，不用修。"], deny: ["設定不安全"] },
  { id: "unsafe-async", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, async: true }] }), exit: 1, want: ["帶 async=true", "deny 來不及生效"], deny: ["判定：正常，不用修。"] },
  { id: "unsafe-async-rewake", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, asyncRewake: true }] }), exit: 1, want: ["帶 asyncRewake=true"], deny: ["判定：正常，不用修。"] },
  { id: "unsafe-in-local-too", main: { hooks: { PreToolUse: [] } }, local: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, async: true }] }), exit: 1, want: ["settings.local.json", "帶 async=true"] },

  // ---- disableAllHooks：settings 的總開關（合併前審查抓到的假綠）------------
  { id: "kill-switch-main", main: Object.assign({ disableAllHooks: true }, settings(gateEntry())), exit: 1, want: ["所有 hook 都被停用", "disableAllHooks: true", "註冊得完全正確也不會被叫起"], deny: ["判定：正常，不用修。"] },
  // local 的總開關**不能靜默忽略**：從家目錄啟動時它就是專案層 local，**且 local 覆蓋 user**。
  // 是否咬人取決於啟動目錄（本工具看不到），所以是停手而非機械修法。
  { id: "kill-switch-local-halts", main: settings(gateEntry()), local: { disableAllHooks: true }, exit: 3, want: ["判定：停手", "local 覆蓋 user"], deny: ["判定：正常，不用修。"] },
  { id: "kill-switch-false-passes", main: Object.assign({ disableAllHooks: false }, settings(gateEntry())), exit: 0, want: ["判定：正常，不用修。"] },
  // 不猜非官方形態，但也不當成「沒設」放行 —— 型別錯就報型別錯
  { id: "kill-switch-string-is-shape-error", main: Object.assign({ disableAllHooks: "true" }, settings(gateEntry())), exit: 1, want: ["不是布林"], deny: ["判定：正常，不用修。"] },
  // timeout <= 0：官方 schema exclusiveMinimum: 0 → 整份 settings 被拒絕載入
  { id: "timeout-zero-rejected", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, timeout: 0 }] }), exit: 1, want: ["必須是 > 0 的數字", "exclusiveMinimum"], deny: ["判定：正常，不用修。"] },
  { id: "timeout-positive-passes", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, timeout: 0.001 }] }), exit: 0, want: ["判定：正常，不用修。"] },
  { id: "kill-switch-beats-unsafe", main: Object.assign({ disableAllHooks: true }, settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, async: true }] })), exit: 1, want: ["所有 hook 都被停用"], deny: ["判定：設定不安全"] },
  // 明確關閉不算不安全 —— 否則會無故弄壞把欄位寫成 false 的使用者
  { id: "unsafe-async-false-passes", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, async: false, once: false }] }), exit: 0, want: ["判定：正常，不用修。"], deny: ["設定不安全"] },
  // 良性欄位一律放行（不影響 gate 能否阻擋）
  { id: "benign-fields-pass", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: CMD, timeout: 30, shell: "bash", statusMessage: "x" }] }), exit: 0, want: ["判定：正常，不用修。"], deny: ["設定不安全"] },
  // precedence：不安全欄位排在 exec form 之前（「確定壞了＋有修法」比「請找人」有用）
  { id: "unsafe-beats-exec-form", main: settings({ matcher: MATCHER, hooks: [{ type: "command", command: "node", args: ["/x/super-mode-consult-gate.js"], async: true }] }), exit: 1, want: ["判定：設定不安全"], deny: ["判定：停手"] },
  // precedence：形狀不合排在不安全之前
  { id: "shape-beats-unsafe", main: settings({ matcher: MATCHER, hooks: [{ type: "prompt", command: CMD, async: true }] }), exit: 1, want: ['type 是 "prompt"'], deny: ["判定：設定不安全"] },

  // ---- 參數：未知參數必須明確報錯，不可靜默忽略 -------------------------------
  // 踩過的實例：修正前的 matcher-contract 收到 `--live` 會靜默忽略並照樣 PASS，
  // 於是「我明明指定了驗 live」的人拿到一個驗別的東西的綠燈。同一個坑不再挖。
  { id: "bad-args-rejected", main: settings(gateEntry()), args: ["--live"], exit: 2, want: ["不吃參數", "RESULT_CODE=BAD_ARGS"], deny: ["判定：正常，不用修。"] },

  // ---- 共用模組的完整性（證明 loader guard 不是死碼）-------------------------
  // gate 辨識的邏輯只有一份，放在三平台 payload 的 lib/ 並要求逐位元相同。
  // 這三案分別驗：缺鏡像、鏡像分歧、以及**正向對照**（staging 機制本身有效）。
  // 少了正向對照，前兩案可能只是因為「temp 目錄下什麼都跑不起來」而通過。
  { id: "integrity-lonely-probe", main: settings(gateEntry()), lonely: true, exit: 1, want: ["TOOL_INTEGRITY_ERROR", "沒有做任何判斷", "讀不到"], deny: ["判定：正常，不用修。"] },
  { id: "integrity-staged-tree-ok", main: settings(gateEntry()), staged: {}, exit: 0, want: ["判定：正常，不用修。"], deny: ["TOOL_INTEGRITY_ERROR"] },
  { id: "integrity-mirror-divergence", main: settings(gateEntry()), staged: { mutate: "linux" }, exit: 1, want: ["TOOL_INTEGRITY_ERROR", "內容不一致"], deny: ["判定：正常，不用修。"] },
  { id: "integrity-mirror-absent", main: settings(gateEntry()), staged: { omit: "macos" }, exit: 1, want: ["TOOL_INTEGRITY_ERROR", "讀不到"], deny: ["判定：正常，不用修。"] },
];

// ── 執行 ────────────────────────────────────────────────────────────────
const work = fs.mkdtempSync(path.join(os.tmpdir(), "probe-gate-"));
let pass = 0;
const failed = [];

function writeFixture(dir, name, value) {
  if (value === undefined) return; // 檔案刻意不存在
  const isPlain = value !== null && typeof value === "object" && !Array.isArray(value);
  if (isPlain && value.dir === true) {
    fs.mkdirSync(path.join(dir, name), { recursive: true }); // 讓 readFileSync 撞非 ENOENT 的錯
    return;
  }
  const body = isPlain && typeof value.raw === "string" ? value.raw : JSON.stringify(value, null, 2);
  fs.writeFileSync(path.join(dir, name), body);
}

// ── 受測 probe 的擺放方式 ───────────────────────────────────────────────
/*
 * 預設直接跑 `probe`。兩種變體用來驗共用模組的 loader guard：
 *
 *   lonely: true   只把 probe 複製到一個空目錄 → 三份鏡像都讀不到
 *   staged: {...}  重建一棵最小樹（tools/ ＋ 三個平台的 lib/），可選擇
 *                  `omit`（省略某平台）或 `mutate`（改掉某平台那份 bytes）
 *
 * `staged: {}`（不動任何東西）是**正向對照**：它必須跑出正常判定。
 * 沒有它的話，另外兩案可能只是因為「這棵臨時樹本來就跑不起來」而通過 ——
 * 那樣 guard 是死碼也看不出來。
 */
const MIRROR_PLATFORMS = ["windows", "macos", "linux"];
const MIRROR_REL = path.join("skills", "超級模式", "lib", "gate-registration.js");

function stageProbe(c, home) {
  if (c.lonely) {
    const p = path.join(home, "lonely-probe.js");
    fs.copyFileSync(probe, p);
    return p;
  }
  if (!c.staged) return probe;
  const root = path.join(home, "staged");
  fs.mkdirSync(path.join(root, "tools"), { recursive: true });
  const staged = path.join(root, "tools", "probe-gate-registration.js");
  fs.copyFileSync(probe, staged);
  for (const plat of MIRROR_PLATFORMS) {
    if (c.staged.omit === plat) continue;
    const src = path.join(__dirname, "..", plat, MIRROR_REL);
    const dst = path.join(root, plat, MIRROR_REL);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    let buf = fs.readFileSync(src);
    if (c.staged.mutate === plat) buf = Buffer.concat([buf, Buffer.from("\n// mirror divergence\n")]);
    fs.writeFileSync(dst, buf);
  }
  return staged;
}

for (const c of CASES) {
  const home = path.join(work, c.id);
  fs.mkdirSync(path.join(home, ".claude"), { recursive: true });
  writeFixture(path.join(home, ".claude"), "settings.json", c.main);
  writeFixture(path.join(home, ".claude"), "settings.local.json", c.local);

  const r = spawnSync(process.execPath, [stageProbe(c, home)].concat(c.args || []), {
    encoding: "utf8",
    env: Object.assign({}, process.env, { HOME: home, USERPROFILE: home }),
  });
  const out = (r.stdout || "") + (r.stderr || "");
  const problems = [];
  if (r.status !== c.exit) problems.push("退出碼 " + r.status + "（預期 " + c.exit + "）");
  for (const w of c.want || []) if (!out.includes(w)) problems.push("缺少字串「" + w + "」");
  for (const d of c.deny || []) if (out.includes(d)) problems.push("不該出現字串「" + d + "」");

  if (problems.length) {
    failed.push(c.id);
    console.log("FAIL: " + c.id + " — " + problems.join("；"));
  } else {
    pass++;
  }
}

fs.rmSync(work, { recursive: true, force: true });

console.log("");
console.log("TOTAL " + CASES.length + "  PASS " + pass + "  FAIL " + failed.length);
if (failed.length) {
  console.log("失敗的案子：" + failed.join(", "));
  // ⚠️ 刻意用 process.exitCode ＋自然結束，不用 process.exit()：後者依 Node 官方文件
  // 會截斷尚未完成的 stdout 寫入，而失敗清單正好是最長、最需要被看到的那一段。
  process.exitCode = 1;
}
