# codex-consult.ps1 -- super-mode section 3.5 advice gate (v3).
# Runs a read-only Codex second opinion. Codex writes nothing; it only reviews
# the evidence/plan you pass in. On success, writes a consult credential so the
# super-mode consult-gate allows change actions for ~20 minutes, and saves the
# full transcript to ~/.claude/super-mode-logs/codex_consult_<ts>.txt.
#
# Params:
#   -Dir         Codex working dir (project root, Windows path; WSL UNC not reachable -> feed evidence via the brief).
#   -PromptFile  Read the consult brief from a file. THE way to pass a brief --
#                write it to the session scratchpad (gate-exempt path), pass path.
#   -Prompt      DEPRECATED (stage 1: warns, still works; a later release errors).
#                Inline briefs containing ; | & trip the consult-gate's command
#                parsing and get blocked. Passing both -Prompt and -PromptFile is
#                now a hard error instead of silently preferring the file.
#   -NoCredential  Discussion-partner mode (outside super-mode): same read-only
#                consult, but do NOT mint the consult-gate credential.
#
# Exit codes: 0 = consult done (credential minted unless -NoCredential)
#             42 = CONSULT_UNAVAILABLE_QUOTA (quota/auth) -- stop, report to user
#             43 = consult ran but the answer is unusable (empty/too short, or no
#                  ^(ALLOW|BLOCK): verdict line) -> NO credential. Re-ask once with an
#                  explicit verdict-line request; never treat 43 as "already consulted".
#             other = codex's own exit code
#   -SchemaFile  Optional (T2b): JSON schema path; constrains Codex's final reply
#                shape via --output-schema. read-only + ephemeral unchanged. Fails
#                fast (before invoking codex) if the file is missing or invalid JSON.
# Note: set the calling tool timeout to 360000ms (6 min); Codex reasoning often exceeds the 2-min default.
#
# STDIN wiring (v3): the brief is normalized to a UTF-8(no BOM) temp file and fed to
# codex via `cmd /s /c "... < file"` so the bytes reach codex untouched. Do NOT pipe
# the prompt through PowerShell 5.1 -- in-script $OutputEncoding is not honored for
# native pipes (scope quirk) and non-ASCII turns into '?'; positional args get
# word-split in the codex.ps1 shim handoff.
param(
  [Parameter(Mandatory = $true)][string]$Dir,
  [string]$Prompt,
  [string]$PromptFile,
  [switch]$NoCredential,
  [string]$SchemaFile   # 可選(T2b)：JSON schema 檔路徑；給了就讓 Codex 回覆符合此結構(--output-schema)，好機器驗收。只約束輸出形狀，不改 read-only/ephemeral。
)

$codexCmd = "C:\npm\codex.cmd"

# 憑證鑄造判準（純函式，見該檔說明）。與本腳本同目錄。
. (Join-Path $PSScriptRoot 'consult-answer.lib.ps1')

# $Dir / $SchemaFile 會拼進 cmd /c 字串執行 → 進 cmd 前必須擋注入面(fail-closed)。
# cmd 即使在雙引號內也會展開 %VAR%(! 可能延遲展開；& | < > ^ 為運算子)；合法 repo/schema 路徑不含這些字元。
function Assert-CmdSafePath([string]$value, [string]$name) {
  if ($value -match '[%!"&|<>^]') { throw ($name + ' 含 cmd 不安全字元(% ! " & | < > ^ 之一)，拒絕以防注入: ' + $value) }
}

# codex 輸出是 UTF-8：讓 PowerShell 正確解碼進 transcript
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

function Read-TextSmart([string]$path) {
  # BOM 嗅探：UTF-16LE / UTF-8 BOM / 其餘一律當 UTF-8(Claude Write 工具與 bash 的產物)
  $b = [System.IO.File]::ReadAllBytes($path)
  if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2) }
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) }
  return [System.Text.Encoding]::UTF8.GetString($b)
}

# C5 stage 1：介面收斂取代散文規則。舊行為是兩個都給就靜默採用 -PromptFile(呼叫端無從
# 察覺自己的 inline 被丟掉) → 改 fail-fast。inline 單獨使用仍可跑，但出 deprecation 警告。
if ($PromptFile -and $Prompt) {
  throw "同時給了 -Prompt 與 -PromptFile：語意不明確(舊行為靜默採用 -PromptFile)，拒絕執行。請只給 -PromptFile。"
}
if ($PromptFile)   { $p = Read-TextSmart $PromptFile }
elseif ($Prompt)   {
  $p = $Prompt
  # 用 [Console]::Error 而非 Write-Warning：實測 powershell.exe -File 跨 process 時 warning stream
  # 會落到 OS stdout(污染 -Quiet 摘要與 --output-schema 的 stdout 解析)，且 $WarningPreference='Stop'
  # 會把它變成 ActionPreferenceStopException —— staged deprecation 的「仍可跑」承諾就破功了。
  [Console]::Error.WriteLine("[DEPRECATED] -Prompt(inline) 將於未來版本改為錯誤。inline 簡報含 ; | & 等標點會被 consult-gate 的指令解析誤判成串接指令而擋下。請改用 -PromptFile：用 Write 工具把簡報寫進 scratchpad(gate 豁免路徑)再傳路徑。")
}
else               { throw "Provide -PromptFile (preferred) or -Prompt (deprecated)." }
if ([string]::IsNullOrWhiteSpace($p)) { throw "Prompt is empty." }

# T2b：給了 -SchemaFile 就轉絕對路徑並在啟動 Codex 前先驗證可解析(fail-fast)。只約束輸出形狀，不改沙箱(read-only/ephemeral 不變)。
$schemaArg = ""
if ($SchemaFile) {
  if (-not (Test-Path -LiteralPath $SchemaFile)) { throw "SchemaFile not found: $SchemaFile" }
  $SchemaFile = (Resolve-Path -LiteralPath $SchemaFile).Path   # consult 有 -C 換工作根，必須絕對路徑
  Assert-CmdSafePath $SchemaFile 'SchemaFile'                  # 進 cmd /c 前擋注入字元
  try { [System.IO.File]::ReadAllText($SchemaFile, (New-Object System.Text.UTF8Encoding $false)) | ConvertFrom-Json | Out-Null }
  catch { throw "SchemaFile is not valid JSON: $SchemaFile -- $_" }
  $schemaArg = '--output-schema "{4}" '   # 併入 $inner 最高編號 {4}(不動 codex{0}/dir{1}/brief{2}/stderr{3})
}

$logDir = Join-Path $env:USERPROFILE ".claude\super-mode-logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$log = Join-Path $logDir ("codex_consult_{0}_{1}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"), ([guid]::NewGuid().ToString('N').Substring(0, 6)))  # 去重後綴防同秒碰撞

$Dir = $Dir.TrimEnd('\')
if ($Dir -match '^[A-Za-z]:$') { $Dir += '\' }
Assert-CmdSafePath $Dir 'Dir'   # $Dir 也進 cmd /c 字串(既有注入面)，一併 fail-closed

# 正規化落地 UTF-8(無 BOM)暫存簡報，cmd `<` 重導向 → 位元組直達 codex
$brief = Join-Path $env:TEMP ("codex_brief_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
$errFile = Join-Path $env:TEMP ("codex_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
[System.IO.File]::WriteAllText($brief, $p, (New-Object System.Text.UTF8Encoding $false))
$answerLines = New-Object System.Collections.Generic.List[string]
try {
  # stderr 導到獨立檔(編號佔位符 {3})；不可用 2>&1(會回灌 stdout)。$LASTEXITCODE 仍是 codex 退出碼。
  # 5.2：--ephemeral 讓短命唯讀諮詢不落地 Codex session 檔(下游不 resume 此 session，留著純浪費)
  # memories 隔離(2026-07-10)：Codex 全域 config 開了 [memories]，會把過往記憶注入 session。
  # consult 必須是「獨立第二意見」→ use_memories=false 斷讀入(否則反方審查被過往記憶污染)、
  # generate_memories=false 斷寫出(否則簡報進全域 memories，下次 consult 又讀到，形成自我強化閉環)。
  # 0.144.1 實測：加這兩個 -c 後 MEMORIES: NO_MEMORIES_VISIBLE、exit 0、MCP 工具面/沙箱邊界皆不受影響。
  $inner = ('"{0}" exec --sandbox read-only --ephemeral --skip-git-repo-check -c memories.use_memories=false -c memories.generate_memories=false -C "{1}" ' + $schemaArg + '< "{2}" 2> "{3}"') -f $codexCmd, $Dir, $brief, $errFile, $SchemaFile
  # 逐行留一份在記憶體：憑證不能只憑 exit code 就發(見下方「憑證鑄造條件」)。
  & cmd.exe /d /s /c $inner | ForEach-Object {
    $_
    $answerLines.Add([string]$_)
    Add-Content -LiteralPath $log -Value $_ -Encoding utf8
  }
  $code = $LASTEXITCODE
  if (Test-Path $errFile) {
    Add-Content -LiteralPath $log -Value "===== STDERR =====" -Encoding utf8
    [System.IO.File]::ReadAllText($errFile, (New-Object System.Text.UTF8Encoding $false)) | Add-Content -LiteralPath $log -Encoding utf8
  }
}
finally {
  Remove-Item -LiteralPath $brief -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
}

# --- 憑證鑄造條件（2026-08）---------------------------------------------------
# 舊版只看 `exit 0` 就發憑證：codex 回空字串、回拒絕、答非所問，一樣解鎖後續 20 分鐘的
# 所有動作。exit code 只證明「進程沒掛」，不證明「諮詢真的發生過」——而 codex 的事件迴圈
# 在沒有 fatal error 時本來就會正常返回。判準抽在 consult-answer.lib.ps1（純函式、可單元測試）。
# BLOCK 仍然鑄造憑證：憑證證明的是「諮詢發生過」，不是「Codex 批准了」；裁決本身由 Claude
# 依 §3.5 遵守（BLOCK 就不做）。若 BLOCK 不鑄造，連「照 Codex 意見改做別的」都會被自己擋死。
if ($code -eq 0) {
  $check = Test-ConsultAnswer -Lines $answerLines -NoCredential:$NoCredential -SchemaFile $SchemaFile
  if (-not $check.Ok) {
    Write-Warning ($check.Reason + " transcript: $log")
    exit $check.Code
  }
  if ($NoCredential) {
    # Discussion-partner mode: no credential, so a casual consult can never
    # unlock super-mode gated actions in a concurrent session on this repo.
    Write-Output "consult OK -- no credential (discussion mode); transcript: $log"
  } else {
    $token = Join-Path $env:USERPROFILE ".claude\.super-mode-consult-ok"
    # 憑證決策範圍：綁定本次諮詢的 repo(-Dir)。hook 會比對後續動作路徑是否在此 repo 下。
    $cred = @{ repo = $Dir; ts = (Get-Date -Format o) } | ConvertTo-Json -Compress
    # 寫入必須 fail-closed 並讀回驗證：Set-Content 的 non-terminating error(唯讀/權限/磁碟滿)
    # 會被預設 EAP 吞掉，於是印出 "credential written" 卻其實沒有憑證(或留著上一次的舊憑證)。
    try {
      Set-Content -LiteralPath $token -Value $cred -Encoding utf8 -ErrorAction Stop
      $readBack = [System.IO.File]::ReadAllText($token)
      if ($readBack -notmatch '"ts"') { throw "讀回內容不含 ts 欄位" }
    } catch {
      Write-Warning ("CONSULT_TOKEN_WRITE_FAILED: 諮詢完成但憑證寫入/讀回失敗，未取得憑證: " +
        $_.Exception.Message + "。請檢查 $token 的權限後重跑。transcript: $log")
      exit 44
    }
    if ($check.Verdict -ceq 'BLOCK') {
      Write-Output "consult OK -- credential written, but Codex 裁決為 BLOCK：依 §3.5 不得執行原動作，先向使用者回報。transcript: $log"
    } else {
      Write-Output "consult OK -- credential written; transcript: $log"
    }
  }
} else {
  # 配額/認證類失敗 → 明確標記 + 專屬 exit 42，讓上層 fail-fast、別在額度最稀缺時空轉重試
  $tail = ""
  try { $tail = (Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue) } catch {}
  if ($tail -match '(?i)usage limit|rate limit|\b429\b|quota|not logged in|unauthorized|\b401\b') {
    Write-Warning "CONSULT_UNAVAILABLE_QUOTA: codex 配額/認證失敗 (exit $code)。停止重試諮詢，向使用者回報；經同意可跑 super-mode.ps1 -Off 降級為一般模式。transcript: $log"
    exit 42
  }
  Write-Warning "codex-consult: codex exited [$code] -- no credential written. transcript: $log"
}
exit $code
