#!/usr/bin/env node
/*
 * 超級模式 consult-gate (PreToolUse) v2-mac
 *
 * ⚠ 定位：這是「諮詢紀律提醒」，不是安全邊界。fail-open、可被 agent 自己 -Off 關掉、
 *   不攔子程序副作用（test runner／某些 shell·MCP 寫法會通過）。用途是讓合作的 Claude
 *   動手前先諮詢、少漏流程；圍堵蓄意繞過或被挾持的 agent 要靠 OS sandbox + Claude permission。
 *   細節見 repo docs/super-mode-hardening-plan-2026-07.md「✅ 定案 姿態 A」。
 *
 * 超級模式啟用時 (~/.claude/.super-mode-active 存在) 攔截「會改變狀態」的工具呼叫：
 *   - Edit / Write / MultiEdit / NotebookEdit（scratchpad 與 ~/.claude 路徑豁免；
 *     安全關鍵檔與 *.sh / conftest.py 等會被自動執行的檔名不豁免）
 *   - Bash / PowerShell：唯讀白名單自動放行；其餘一律需要 20 分鐘內的 Codex 諮詢
 *     憑證（default-deny，未知指令視同要憑證）
 *   - mcp__* 寫入/外發類工具（create/update/delete/submit/send/click/type/...）
 *
 * 憑證 = ~/.claude/.super-mode-consult-ok（codex-consult.sh 成功時寫入；JSON 含 repo
 * 則比對動作路徑要落在該 repo 下，舊格式純時間戳只驗時間）。
 * 收尾動作（git commit/push/merge、publish、deploy）放行後把憑證「降為只剩 3 分鐘」，
 * 讓同一條指令內的 commit+push 能走完，但下一個里程碑必須重新諮詢。
 *
 * 旗標第一行若是路徑（super-mode.sh on --scope <dir>）→ 只在該路徑底下強制；
 * 空內容 → 全域強制。旗標超過 8 小時視為上個 session 殘留 → 自動解除（自癒）。
 *
 * 部署位置：~/.claude/hooks/super-mode-consult-gate.js（I3 保護目錄，勿放 skill 內），
 * 由 ~/.claude/settings.local.json 的 PreToolUse 註冊。
 * FAIL-OPEN：沒旗標、或任何錯誤 → 一律放行 (exit 0)，確保一般模式絕不被卡。
 * 被擋時 exit 2，stderr 訊息會回饋給 Claude。
 * testOpts.mcpPolicy/MCP_PATHLESS_ALLOW 一旦有內容即等於開放對應 MCP 放行；生產呼叫端只傳一個參數，勿讓任何 runtime/使用者輸入流入第二參數。
 */
const fs = require("fs");
const os = require("os");
const path = require("path");

const WINDOW_MS = 20 * 60 * 1000; // 諮詢憑證有效視窗
const GRACE_MS = 3 * 60 * 1000; // 收尾動作後保留的餘裕
const FLAG_STALE_MS = 8 * 60 * 60 * 1000; // 旗標殘留自動解除門檻

// 暫存根：os.tmpdir()($TMPDIR=/var/folders/...) 與 /tmp。norm() 已把 /private/tmp
// 摺成 /tmp，因此同時涵蓋 Claude Code scratchpad(/private/tmp/claude-*) 與系統暫存。
const TMP_ROOTS = [norm(os.tmpdir()), "/tmp"];

const MUTATING_FILE_TOOLS = ["Edit", "Write", "MultiEdit", "NotebookEdit"];
// 會外發/排程/觸發遠端的內建工具（非 shell、非 MCP）→ 也要憑證。需同步 settings matcher。
const MUTATING_BUILTIN = ["RemoteTrigger", "PushNotification", "CronCreate", "CronDelete"];

// 只有唯讀的諮詢/查版/開關腳本可無條件放行（否則死鎖）。codex-exec 是 workspace-write
// 執行者，故意排除 → 派工也要先有憑證（落到 decide 的 default-deny）。錨定在指令開頭
// （bash/zsh 前綴與路徑段可有，但不得含分隔/替換字元），杜絕 v1 的誤放行。
const CODEX_SAFE_RE = /^\s*["']?[^;&|<>"'`]*(codex-(consult|check)|super-mode)\.sh\b/i;

// 破壞性/不可逆指令。default-deny 才是主網；這份清單的用途是
// (1) 判斷「收尾動作」要不要消耗憑證 (2) 檢查 codex 腳本呼叫的參數尾巴沒夾帶壞事。
// Windows-only 條目（reg/schtasks/wsl/PS cmdlets）故意保留：多擋無害、與參考版逐字可比。
const DESTRUCTIVE = [
  /\bgit\s+(commit|push|merge|rebase|reset|clean|restore|revert|cherry-pick|checkout|switch|rm|mv|am|apply|filter-branch|prune)\b/i,
  /(^|[;&|(]\s*)(rm|del|erase|rmdir|rd|mv|move|ren|rename|mklink)\b/i,
  /\b(Remove-Item|Move-Item|Rename-Item|Copy-Item|Set-Content|Add-Content|Clear-Content|Out-File|New-Item|Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|Stop-Process|Stop-Service|Restart-Service|Set-Service|Set-ExecutionPolicy|Install-Module|Uninstall-Module|Start-Process)\b/i,
  /\bsed\s+(-\w+\s+)*(-i|--in-place)\b/i,
  /\btee\b/i,
  /\b(npm|pnpm|yarn)\s+(publish|unpublish|deprecate|add|remove|uninstall|update|upgrade|link|ci|install|i)\b/i,
  /\bpip3?\s+(install|uninstall)\b/i,
  /\bconda\s+(install|remove|update|create)\b/i,
  /\bcargo\s+(publish|install)\b/i,
  /\bgo\s+install\b/i,
  /\bgh\s+(pr\s+(create|merge|close|edit)|issue\s+(create|edit|close)|release|repo\s+(create|delete|edit))\b/i,
  /\bgh\s+api\b[^;|&]*(-X|--method)\s+(POST|PUT|PATCH|DELETE)/i,
  /(^|[;&|]\s*)(deploy|netlify|vercel|gh-pages)\b|\bfirebase\s+deploy\b/i,
  /\bterraform\s+(apply|destroy)\b/i,
  /\bkubectl\s+(apply|delete|scale|rollout|drain)\b/i,
  /\bdocker\s+(rm|rmi|push|prune|build|run|compose)\b/i,
  /\b(schtasks|bcdedit|diskpart|netsh)\b|\breg\s+(add|delete)\b/i,
  /\bwsl(\.exe)?\s+--(unregister|import|shutdown|terminate)\b/i,
];

// 收尾/發佈型動作：放行後把憑證降為只剩 GRACE_MS
const CONSUMING = [
  /\bgit\s+(commit|merge|rebase|push)\b/i,
  /\b(npm|pnpm|yarn|cargo)\s+publish\b/i,
  /(^|[;&|]\s*)(deploy|netlify|vercel|gh-pages)\b|\bfirebase\s+deploy\b/i,
  /\bterraform\s+apply\b/i,
  /\bgh\s+pr\s+(create|merge)\b/i,
];

// 唯讀白名單（逐管線段比對，錨定段首）
const READONLY_SEG = [
  /^git\s+((-C\s+\S+|--no-pager|--git-dir=\S+|-c\s+\S+)\s+)*(status|log|diff|show|rev-parse|blame|shortlog|describe|grep|ls-files|ls-remote|ls-tree|cat-file|config\s+(--get|--list|-l)\b|stash\s+list|worktree\s+list|reflog|branch(\s+(-a|--all|-l|--list|-v|-vv|--show-current|-r))*\s*$|tag(\s+(-l|--list))?\s*$|remote(\s+(-v|--verbose))?\s*$)/i,
  /^(ls|ll|dir|cat|type|head|tail|wc|sort|uniq|cut|tr|nl|stat|du|df|tree|pwd|cd|pushd|popd|echo|printf|date|whoami|hostname|uname|env|printenv|which|where(\.exe)?|findstr|grep|egrep|fgrep|rg|jq|diff|comm|file|less|more|sleep|true)\b/i,
  /^find\b(?!.*(-delete|-exec|-execdir|-ok|-okdir|-fprintf?|-fls|-fprint0))/i,
  /^(node|python3?|ruby|php|perl)\s+(-v|--version)\s*$/i,
  /^npm\s+(view|ls|list|outdated|config\s+get|-v|--version|ping|root|prefix)\b/i,
  /^(pip3?\s+(list|show|freeze)|conda\s+(list|info)|cargo\s+(check|clippy|tree|metadata)|go\s+(vet|list|env|version)|dotnet\s+--(info|version))\b/i,
  /^(npm|pnpm|yarn)\s+(run\s+)?(test|lint|typecheck|check)\b/i,
  /^(python3?\s+-m\s+)?pytest\b/i,
  /^cargo\s+test\b/i,
  /^go\s+test\b/i,
  /^dotnet\s+test\b/i,
  /^(npx\s+)?tsc\b.*--noEmit/i,
  /^eslint\b(?!.*--fix)/i,
  /^prettier\b.*--check/i,
  /^ruff\s+check\b(?!.*--fix)/i,
  /^gh\s+(search|status)\b/i,
  /^gh\s+(pr|issue|run|release|repo|workflow)\s+(list|view|status|diff|checks)\b/i,
  /^gh\s+api\b(?!.*(-X|--method)\s*(POST|PUT|PATCH|DELETE))/i,
  /^sed\s+-n\b/i,
  /^\S*python3?(\.exe)?\s+-m\s+pytest\b/i,
  /^\S*pytest(\.exe)?\b/i,
  /^(select|sls|gc|gci|gcm|gm)\b/i,
  /^\$\w+\s*=\s*(Get-\w+|Select-\w+|Measure-\w+|Test-Path|Test-Connection|Resolve-Path|Compare-Object|ConvertFrom-\w+|Import-Csv|Split-Path|Join-Path)\b/i,
  /^(Get-\w+|Select-Object|Select-String|Select-Xml|Measure-\w+|Test-Path|Test-Connection|Resolve-Path|Compare-Object|Format-\w+|Out-String|Out-Host|Write-Output|Write-Host|Write-Verbose|ForEach-Object|Where-Object|Sort-Object|Group-Object|ConvertFrom-\w+|ConvertTo-Json|Split-Path|Join-Path|Start-Sleep|Set-Location)\b/i,
];

// MCP 工具名關鍵字：寫入/外發 → gate；唯讀 → 放行（寫入優先判定）
const MCP_READ_RE = /(read|get|list|search|fetch|query|download|view|describe|inspect|snapshot|screenshot|context|logs|console|network|find|cursor_position|resolve)/i;
const MCP_WRITE_RE = /(create|update|delete|remove|move|write|submit|publish|send|upload|archive|duplicate|add|insert|patch|post|execute|fill|click|type|press|key|drag|join|copy|trigger|run_now|scale|deploy)/i;
// 純標註/無副作用的 MCP 工具白名單（未知 MCP 一律 default-deny，這些例外放行）
const MCP_BENIGN_RE = /(mark_chapter|read_widget)/i;
// N5：名字含 read-y 字（get/read/resolve/view…）、實際有外發副作用的已知工具 → 精確封鎖(比對 action 尾段、
// 不看 server 名，避免 server 名含 read/get/context 污染)。這是「已證實清單」而非「封住整類」：姿態 A 下用最小改動
// 關掉誤放行(set_budget/resolve_comment/mark_as_read/reply_to_thread/request_copilot_review …)，未列舉的新
// 變體仍可能漏放行(gate 非邊界=已接受殘餘)。完整解法(action 分詞+寫入優先+exact 例外表+MCP 三態授權)見
// docs/super-mode-hardening-plan-2026-07.md 的 Z 案(backlog)。注意：被此表封鎖者走既有 MCP 寫入路徑=harddeny
// (無 repo path 綁定，即使有憑證仍拒)，要放行請加進 MCP_PATHLESS_ALLOW/policy。
const MCP_FORCE_GATE_ACTION = new Set([
  "set_budget",
  "resolve_comment",
  "mark_as_read",
  "mark_as_unread",
  "mark_all_as_read",
  "reply_to_thread",
  "slack_reply_to_thread",
  "request_copilot_review",
]);
const MCP_PATHLESS_ALLOW = [
  "mcp__sportspredict__join_lobby",
  "mcp__sportspredict__submit_prediction",
  "mcp__sportspredict__submit_predictions_batch",
  "mcp__sportspredict__update_prediction",
  /^mcp__[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}__notion-(create-pages|update-page|create-comment)$/,
];

if (require.main === module) {
  let raw = "";
  process.stdin.on("data", (c) => (raw += c));
  process.stdin.on("end", () => {
    let verdict;
    try {
      verdict = decide(JSON.parse(raw || "{}"));
    } catch (e) {
      verdict = { allow: true }; // FAIL-OPEN：任何錯誤都放行
    }
    if (verdict.allow) process.exit(0);
    process.stderr.write(verdict.reason);
    process.exit(2);
  });
}

function decide(input, testOpts) {
  try {
  testOpts = testOpts || {};
  input = input || {};
  const baseDir = typeof testOpts === "string"
    ? testOpts
    : (typeof testOpts.baseDir === "string" ? testOpts.baseDir : path.join(os.homedir(), ".claude"));
  const mcpPolicy = Array.isArray(testOpts.mcpPolicy) ? testOpts.mcpPolicy : [];
  const claude = baseDir;
  const flag = path.join(claude, ".super-mode-active");
  const token = path.join(claude, ".super-mode-consult-ok");

  if (!fs.existsSync(flag)) return { allow: true }; // 非超級模式

  // 殘留自癒：旗標太舊 → 上個 session 忘了跑 off，自動解除
  if (Date.now() - fs.statSync(flag).mtimeMs > FLAG_STALE_MS) {
    tryUnlink(flag);
    tryUnlink(token);
    return { allow: true };
  }

  // Scope：旗標第一行是路徑 → 只在該專案底下強制
  const scope = readScope(flag);
  const tool = String(input.tool_name || "");
  const ti = input.tool_input || {};

  let gated = false;
  let consuming = false;
  let category = "";
  let mcpAuth = null;
  let actionPath = ""; // 本動作綁定的路徑(檔案 file_path / shell cwd)，供憑證範圍比對

  if (MUTATING_FILE_TOOLS.includes(tool)) {
    const fp = String(ti.file_path || ti.notebook_path || "");
    // v2 決策順序(全部以 canonical 路徑判定；安全關鍵檔保護必須 BEAT scope 捷徑)：
    //   canonicalize 先做(詞法擋 `..` → 摺 `.`/重複分隔 → 對最近存在祖先 realpathSync.native 解
    //   symlink/大小寫 → 接回尾段)。
    //   (i) canonical 可疑 → gated，跳過所有捷徑。
    //   (ii) 安全關鍵檔 → 永遠 gated(在 scope 之前) → 殺 CLASS A(scope 捷徑蓋黑名單)/C(`/.` 單點段)。
    //   (iii) 豁免(scratchpad 或 ~/.claude 下非安全非自動執行檔) → 放行。
    //   (iv) 有 scope 且 canonical 不在 scope 下、且不在 ~/.claude 內 → 放行(gate 自己的地盤絕不因 scope 外快放行；只剩非關鍵、非 ~/.claude 檔會到這)。
    //   (v) 其餘 → gated。
    const canonRes = canonicalize(fp);
    const canon = canonRes.path;
    const claudeRes = canonicalize(claude);
    const claudeCanon = claudeRes.path || claude;
    actionPath = fp; // 憑證範圍比對維持用原始 fp(不動 credential 決策路徑，避免非對稱誤判)
    if (canonRes.dangerous || claudeRes.dangerous) {
      // fp 可疑，或連 ~/.claude base 都無法可靠正規化 → gated，不放行任何豁免/scope 捷徑(fail-closed)。
      gated = true;
      category = "檔案寫入(可疑路徑)";
    } else if (isSecurityCriticalPath(canon, claudeCanon)) {
      gated = true;
      category = "檔案寫入(安全關鍵檔)";
    } else if (isExemptPath(canon, claudeCanon)) {
      return { allow: true };
    } else if (scope && canon && isScopeOutside(canon, scope) && !isUnderClaudeRoot(canon, claudeCanon)) {
      return { allow: true }; // scope 外(非關鍵檔、且不在 ~/.claude 內)不管
    } else {
      gated = true;
      category = "檔案寫入";
    }
  } else if (tool === "Bash" || tool === "PowerShell") {
    const cwd = String(input.cwd || "");
    const cmd = String(ti.command || "");
    // CLASS A shell facet 修補：cwd 在 scope 外的捷徑放行「僅限唯讀指令」；會改狀態的指令一律
    // 落回下方 default-deny/破壞性判定(需憑證)。可疑 cwd(含 ..)不吃此捷徑。
    // (operand/git -C 綁定屬 P0.4，此處不解析 operand。)
    if (!isDangerousPath(cwd) && scope && !isUnder(cwd, scope) && isReadOnlyCommand(cmd)) return { allow: true };
    actionPath = cwd;

    // 唯讀諮詢/查版/開關腳本：錨定開頭 + 參數尾巴無串接/替換/破壞性字樣才放行
    const m = cmd.match(CODEX_SAFE_RE);
    if (m) {
      const rest = cmd.slice(cmd.indexOf(m[0]) + m[0].length);
      if (!/[;&|<>`]/.test(rest) && !/\$\(/.test(rest) && !DESTRUCTIVE.some((re) => re.test(rest))) {
        return { allow: true };
      }
    }

    if (DESTRUCTIVE.some((re) => re.test(cmd))) {
      gated = true;
      consuming = CONSUMING.some((re) => re.test(cmd));
      category = consuming ? "收尾動作(會消耗憑證)" : "破壞性指令";
    } else if (isReadOnlyCommand(cmd)) {
      // runner 否決：測試/lint runner 一旦指向暫存或 ~/.claude 路徑，可執行先前寫入
      // 豁免區的 conftest.py/package.json 等 → 任意程式碼執行繞過。故一律要憑證。
      // "/tmp" 子字串會誤含 /Users/x/proj/tmp/ —— 故意的保守誤擋（只多要一次憑證），勿優化掉。
      const RUNNER_RE = /(^|[;&|]\s*)\S*(pytest|npm|pnpm|yarn|cargo|go|dotnet|eslint|ruff|prettier|tsc|node|python3?)(\.exe)?\b/i;
      const low = cmd.toLowerCase().replace(/\\/g, "/").replace(/\/private\/(tmp|var|etc)\//g, "/$1/");
      const HITS = [norm(os.tmpdir()), norm(claude), "/tmp", "~/.claude"];
      if (RUNNER_RE.test(cmd) && HITS.some((h) => low.includes(h))) {
        gated = true; category = "runner 涉及暫存/設定路徑";
      } else {
        return { allow: true };
      }
    } else {
      gated = true; // default-deny：不在唯讀白名單的未知指令一律要憑證
      category = "非唯讀指令";
    }
  } else if (MUTATING_BUILTIN.includes(tool)) {
    gated = true;
    category = "外發/排程內建工具";
  } else if (tool.startsWith("mcp__")) {
    // 唯讀/良性 MCP 維持放行；寫入與未知工具必須走 repo-bound policy。
    const mcpIsWrite = MCP_WRITE_RE.test(tool);
    const mcpForceGate = MCP_FORCE_GATE_ACTION.has(mcpAction(tool)); // N5：讀名誤導的已知副作用工具
    // 寫入/已知副作用一律優先於良性白名單：mark_chapter_delete/read_widget_update 這種「良性名 +
    // 寫入動作」不得因命中 MCP_BENIGN_RE 而繞過 write 檢查(N5 regression 修補，恢復 main 的 write 優先)。
    const mcpIsReadOnly = !mcpIsWrite && !mcpForceGate && (MCP_BENIGN_RE.test(tool) || MCP_READ_RE.test(tool));
    if (mcpIsReadOnly) {
      return { allow: true };
    }

    let mcpPolicyEntry = null;
    try {
      mcpPolicyEntry =
        mcpPolicy.find(
          (entry) =>
            entry &&
            entry.tool === tool &&
            Array.isArray(entry.pathFields) &&
            entry.pathFields.length > 0 &&
            entry.pathFields.every((field) => typeof field === "string" && field)
        ) || null;
    } catch (e) {
      mcpPolicyEntry = null;
    }
    if (mcpPolicyEntry) {
      const values = {};
      try {
        for (const field of mcpPolicyEntry.pathFields) values[field] = ti[field];
      } catch (e) {}
      mcpAuth = { kind: "pathbound", entry: mcpPolicyEntry, values };
    } else if (isMcpPathlessAllowed(tool)) {
      mcpAuth = { kind: "pathless-allow" };
    } else {
      mcpAuth = { kind: "harddeny" };
    }
    gated = true;
    category = mcpIsWrite ? "MCP 寫入/外發" : (mcpForceGate ? "MCP 已知副作用(讀名誤導)" : "MCP 未知工具(default-deny)");
  }

  if (!gated) return { allow: true };

  if (fs.existsSync(token) && Date.now() - fs.statSync(token).mtimeMs < WINDOW_MS) {
    // 憑證決策範圍：諮詢時綁定的 repo。舊格式(純時間戳)→ credRepo 空 → 只驗時間(相容)。
    // 拿不到動作路徑(MCP/外發工具)→ 無從綁定 → 只驗時間。
    const credRepo = readCredRepo(token);
    if (mcpAuth) {
      const mcpDenyBase =
        "[超級模式] MCP 寫入/未知工具無 repo path 綁定，超級模式下不放行(即使有憑證)。" +
        "請關閉超級模式、或把此工具加入 hook 的 MCP_PATHLESS_ALLOW/policy 白名單後重試。";
      if (mcpAuth.kind === "harddeny") {
        // 被擋 tool 名來自不可信 input：移除非可列印 ASCII(含控制/零寬/雙向字元)、壓縮空白、截斷 160，再回饋。
        const safeTool = String(tool).replace(/[^ -~]/g, "").replace(/\s+/g, " ").slice(0, 160);
        return {
          allow: false,
          reason: mcpDenyBase + " 被擋工具: " + safeTool +
            "。白名單真值在 Codex-for-CC repo 三平台 hooks/super-mode-consult-gate.js(改完須重裝同步 ~/.claude/hooks/)。",
        };
      }
      if (mcpAuth.kind === "pathbound") {
        const mcpRepo = credRepo;
        const fields = mcpAuth.entry && Array.isArray(mcpAuth.entry.pathFields) ? mcpAuth.entry.pathFields : [];
        if (!mcpRepo || !fields.length) {
          return { allow: false, reason: mcpDenyBase + " 憑證缺少 repo 綁定或 pathFields 不可信，請重新諮詢產生綁 repo 的新憑證。" };
        }
        for (const field of fields) {
          const value = mcpAuth.values ? mcpAuth.values[field] : undefined;
          if (!isTrustedRepoPath(value, mcpRepo)) {
            return {
              allow: false,
              reason: mcpDenyBase + " 欄位 " + field + " 不在憑證 repo 內: " + String(value || "(空)"),
            };
          }
        }
      }
    }
    if (credRepo && actionPath && !isUnder(actionPath, credRepo)) {
      return {
        allow: false,
        reason:
          "[超級模式] 現有諮詢憑證的範圍是另一個專案(" + credRepo + ")，本動作在 " +
          (actionPath || "(未知路徑)") + "。請針對本專案重新諮詢：" +
          "codex-consult.sh -d <本專案根> -f <brief>。",
      };
    }
    if (consuming) demoteToken(token); // 收尾動作 → 憑證只剩 3 分鐘餘裕
    return { allow: true };
  }

  return {
    allow: false,
    reason:
      "[超級模式] 此動作(" + category + ": " + tool + ")需要 20 分鐘內的 Codex 諮詢憑證。步驟：" +
      "①用 Write 工具把諮詢簡報寫進 scratchpad(豁免路徑，別用 shell 寫) " +
      "②用 Bash 工具(timeout 設 360000ms)跑 " +
      "~/.claude/skills/超級模式/scripts/codex-consult.sh -d <repo> -f <brief>(一律 -f) " +
      "③成功後重試此動作。若超級模式其實已結束，跑 scripts/super-mode.sh off 解除。" +
      "（連續諮詢失敗 ≥2 次、或看到 CONSULT_UNAVAILABLE_QUOTA，請直接向使用者回報，勿再重試。）",
  };
  } catch (e) {
    return { allow: true };
  }
}

function readScope(flag) {
  try {
    const first = fs.readFileSync(flag, "utf8").split(/\r?\n/)[0].trim();
    if (first.startsWith("/") && !isDangerousPath(first)) return first; // 可疑 scope → 視為無 scope(全域強制,較嚴格)
  } catch (e) {}
  return ""; // 空 / 舊格式(時間戳) → 全域強制
}

// 讀憑證綁定的 repo。JSON {repo,ts} → 回 repo；純時間戳(舊格式)或任何錯誤 → ""(只驗時間)
function readCredRepo(token) {
  try {
    const c = fs.readFileSync(token, "utf8").trim();
    if (c[0] !== "{") return "";
    const o = JSON.parse(c);
    return typeof o.repo === "string" ? o.repo : "";
  } catch (e) {
    return "";
  }
}

function norm(p) {
  let s = String(p).replace(/\\/g, "/"); // 容錯：反斜線輸入一律轉正斜線
  s = s.replace(/\/{2,}/g, "/"); // 摺疊重複斜線(防過度跳脫的輸入)
  s = s.replace(/^\/private\/(tmp|var|etc)(\/|$)/, "/$1$2"); // macOS symlink 等價
  return s.replace(/\/+$/, "").toLowerCase(); // 去尾斜線 + APFS 大小寫不敏感
}

// 詞法可疑路徑偵測(在任何路徑比對前呼叫)：Claude Code 傳絕對 file_path，合法情況不含 `..`，
// 故「拒絕」而非「解析」即零誤判且確定性關閉提權。POSIX 無 Windows 的裝置路徑/ADS/尾端點空白
// 摺疊問題，故只擋 `..` 段。
function isDangerousPath(p) {
  try {
    const s = String(p == null ? "" : p);
    if (!s) return false;
    return s.replace(/\\/g, "/").split(/\/+/).includes(".."); // .. 段(反斜線輸入先轉正斜線,與 norm 對齊)
  } catch (e) {
    return true; // 解析失敗 → 保守視為可疑
  }
}

// 路徑必須是絕對路徑：POSIX 根(/)。測試臺在 Windows 上跑本 hook，__BASE__/__TMP__ 會是宿主磁碟路徑
// (C:\ / UNC)，故一併接受(僅測試臺會出現；真實 POSIX file_path 恆為 /...)。拒絕相對路徑(無法判 containment)。
function isAbsoluteEnough(p) {
  return /^\//.test(p) || /^[a-zA-Z]:[\\/]/.test(p) || /^[\\/]{2}/.test(p);
}

// v2 正規化：詞法擋 `..` → 摺 `.`/重複分隔 → 要求絕對路徑 → 對「最近的存在祖先」realpathSync.native(解
// symlink、APFS 大小寫、/private 等) → 接回不存在的尾段。回 { path, dangerous }。任何非預期錯誤/dangling
// link/權限 → fail-closed。POSIX 無 NTFS 8.3 短名，故無短名偵測。realpath 僅在目標平台(非 win32)執行；
// 在 Windows 測試臺上跑本 POSIX hook 時停用 realpath(避免把 POSIX 路徑的磁碟根偽造成 C:\)，只做詞法正規化。
const PP = path.posix; // 詞法路徑運算固定用 posix 語義(不隨宿主 OS 變)
const CAN_REALPATH = process.platform !== "win32"; // 僅目標平台做真實 realpath
function canonicalize(fp) {
  try {
    const raw = String(fp == null ? "" : fp);
    if (!raw) return { path: "", dangerous: false };
    if (isDangerousPath(raw)) return { path: raw, dangerous: true }; // (a) 詞法 reject(`..`)
    let n = PP.normalize(raw); // (b) 摺 `.` 與重複分隔；已在 `..` reject 之後
    if (isDangerousPath(n)) return { path: n, dangerous: true };
    if (!isAbsoluteEnough(n)) return { path: n, dangerous: true }; // (a') 非絕對路徑 → 可疑
    if (!CAN_REALPATH) return { path: n, dangerous: false }; // 非目標平台(Windows 測試臺)：只做詞法正規化
    // (c) 逐層上溯找「存在的」祖先(用 lstat：dangling symlink 本體也算存在，交給 realpath fail-closed) → realpath → 接回尾段
    let cur = n;
    const tail = [];
    let guard = 0;
    while (guard++ < 8192) {
      let present = true;
      try { fs.lstatSync(cur); }
      catch (e) {
        if (e && e.code === "ENOENT") present = false;
        else return { path: n, dangerous: true }; // (d) EACCES/ELOOP/其他 → fail-closed
      }
      if (present) {
        let real;
        try { real = fs.realpathSync.native(cur); } // 解 symlink/大小寫；dangling link 會 throw → fail-closed
        catch (e) { return { path: n, dangerous: true }; } // (d)
        const joined = tail.length ? real + PP.sep + tail.slice().reverse().join(PP.sep) : real;
        return { path: joined, dangerous: false };
      }
      const parent = PP.dirname(cur);
      if (parent === cur) return { path: n, dangerous: true }; // 連根都 ENOENT → fail-closed
      tail.push(PP.basename(cur));
      cur = parent;
    }
    return { path: n, dangerous: true }; // guard 觸頂 → fail-closed
  } catch (e) {
    return { path: String(fp == null ? "" : fp), dangerous: true }; // (d)
  }
}

// canonical 路徑是否為安全關鍵檔(在 scope 判定之前永遠 gated)。兩參數都須是已 canonicalize 的路徑。
function isSecurityCriticalPath(canonFp, canonClaude) {
  if (!canonFp) return false;
  const p = norm(canonFp);
  const c = norm(canonClaude);
  return (
    p === c + "/.super-mode-active" ||
    p === c + "/.super-mode-consult-ok" ||
    p === c + "/settings.json" ||
    p === c + "/settings.local.json" ||
    p === c + "/.codex-check-last" ||
    p === c + "/.codex-check-baseline" ||
    p.startsWith(c + "/hooks/")
  );
}

// step(iv) scope-outside 捷徑的 claude-root 守衛：~/.claude 是 gate 自己的地盤，永不因「不在 repo
// scope 下」而被 scope-outside 快放行。否則 scoped 旗標 + 無憑證下，可 zero-credential 覆寫非安全關鍵
// 清單、卻仍會被 gate 無條件執行的檔(codex-consult.sh/super-mode.sh/任意 .sh) → 提權。canonFp
// 落在 canonClaude(=~/.claude) 內 → true。合法 ~/.claude 下非關鍵檔已在 step(iii) isExemptPath 放行。
function isUnderClaudeRoot(canonFp, canonClaude) {
  if (!canonFp || !canonClaude) return false;
  const p = norm(canonFp);
  const c = norm(canonClaude);
  return p === c || p.startsWith(c + "/");
}

// scope 外判定：scope 也走 canonicalize(兩邊一致)；scope 無法正規化 → 回 false(視為全域強制，不放行捷徑)。
function isScopeOutside(canon, scope) {
  const s = canonicalize(scope);
  if (s.dangerous) return false;
  return !isUnder(canon, s.path || scope);
}

function isUnder(p, root) {
  if (!p) return true; // 拿不到路徑就當在 scope 內(保守：仍要憑證)
  if (isDangerousPath(p) || isDangerousPath(root)) return false; // .. 等可疑路徑不可判為「在範圍內」
  const a = norm(p);
  const b = norm(root);
  return a === b || a.startsWith(b + "/");
}

// 取 MCP 工具名的 action 尾段(最後一個 __ 之後)、lowercase；用於 N5 exact 副作用封鎖(不看 server 名)。
function mcpAction(tool) {
  const s = String(tool == null ? "" : tool);
  const i = s.lastIndexOf("__");
  return (i >= 0 ? s.slice(i + 2) : s).toLowerCase();
}

function isMcpPathlessAllowed(tool) {
  return MCP_PATHLESS_ALLOW.some((p) => {
    if (typeof p === "string") return p === tool;
    if (p instanceof RegExp) return p.test(tool);
    return false; // 非 string 非 RegExp 的髒條目 → fail-closed，不 throw 不放行
  });
}

function isTrustedRepoPath(p, repo) {
  try {
    if (typeof p !== "string" || !p.trim()) return false;
    if (typeof repo !== "string" || !repo.trim()) return false;
    // 字串級檢查：不處理 symlink/junction；未來若保護實體檔案 I/O，需另做 realpath。
    if (!/^\//.test(p)) return false;
    if (hasDotDotSegment(p)) return false;
    const a = norm(p);
    const b = norm(repo);
    if (!a || !b || hasDotDotSegment(a)) return false;
    const sep = "/";
    return a === b || a.startsWith(b + sep);
  } catch (e) {
    return false;
  }
}

function hasDotDotSegment(value) {
  try {
    return String(value).split(/[\\/]+/).includes("..");
  } catch (e) {
    return true;
  }
}

// 輸入(fp/claude)應已 canonicalize。安全關鍵檔委派給 isSecurityCriticalPath(單一真相源)。
function isExemptPath(fp, claude) {
  if (!fp) return false;
  const p = norm(fp);
  const c = norm(claude);
  // 安全關鍵檔絕不豁免（否則可 Write 偽造憑證 / 覆寫 settings / 抽換 hook 本體自我提權）。
  // 這些檔仍受一般 gating：真的要改就得先有諮詢憑證。(step (ii) 已先擋，這裡是防禦性重複。)
  if (isSecurityCriticalPath(fp, claude)) {
    return false;
  }
  const base = p.split("/").pop();
  // 會被 runner/shell 自動載入執行的檔名不豁免（I9：*.sh 為 Windows 版 *.ps1 的同義翻譯）
  if (
    /^(conftest\.py|pytest\.ini|tox\.ini|noxfile\.py|setup\.cfg|package\.json|makefile|\.pytestrc)$/i.test(base) ||
    /\.(sh|zsh|bash|command)$/i.test(base)
  ) {
    return false;
  }
  // tmp root 也走 canonicalize，讓 canon(fp) 與比對基準兩邊都是 realpath 大小寫/symlink(尤其 linux
  // case-sensitive norm 需兩邊一致才不誤判)。"/tmp" 保留為字面根(norm 會把 /private/tmp 摺回 /tmp)。
  // os.tmpdir() 正規化失敗 → 停用該 tmp 豁免(fail-closed)，"/tmp" 字面根仍保留。
  const tmpRes = canonicalize(os.tmpdir());
  const tmpRoots = tmpRes.dangerous ? ["/tmp"] : [norm(tmpRes.path || os.tmpdir()), "/tmp"];
  return p.startsWith(c + "/") || tmpRoots.some((r) => p.startsWith(r + "/"));
}

function isReadOnlyCommand(cmd) {
  // 命令/程序替換 = 可跑任意程式 → 一律不算唯讀（$(...)、反引號、<(...)、>(...)）
  if (/\$\(|`|<\(|>\(/.test(cmd)) return false;
  // 先剝掉無害的重導向，再檢查殘留的 > (寫檔) 就不算唯讀
  const c = cmd
    .replace(/2>&1/g, " ")
    .replace(/[\d*]?>+\s*\$null/gi, " ")
    .replace(/[\d*]?>+\s*nul\b/gi, " ")
    .replace(/[\d*]?>+\s*\/dev\/null/gi, " ");
  if (/>/.test(c)) return false;
  // 分隔：&& || ; | 換行，以及單一 & (背景作業)。2>&1 已在上面剝除，此處 & 只會是背景/串接。
  const segs = c.replace(/&&|\|\|/g, ";").split(/[;|&\r\n]+/);
  return segs.every((s) => {
    const t = s.trim().replace(/^[&('"\s]+/, "");
    if (!t) return true;
    return READONLY_SEG.some((re) => re.test(t));
  });
}

function demoteToken(token) {
  try {
    const st = fs.statSync(token);
    const target = Date.now() - (WINDOW_MS - GRACE_MS);
    if (st.mtimeMs > target) fs.utimesSync(token, new Date(), new Date(target));
  } catch (e) {}
}

function tryUnlink(p) {
  try {
    fs.unlinkSync(p);
  } catch (e) {}
}

module.exports = { decide, canonicalize };
