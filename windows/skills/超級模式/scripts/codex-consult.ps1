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

# $Dir / $SchemaFile 會拼進 cmd /c 字串執行 → 進 cmd 前必須擋注入面(fail-closed)。
# cmd 即使在雙引號內也會展開 %VAR%(! 可能延遲展開；& | < > ^ 為運算子)；合法 repo/schema 路徑不含這些字元。
function Assert-CmdSafePath([string]$value, [string]$name) {
  if ($value -match '[%!"&|<>^]') { throw ($name + ' 含 cmd 不安全字元(% ! " & | < > ^ 之一)，拒絕以防注入: ' + $value) }
}

# 測試接縫的解析器。⚠️ 只換「執行哪支程式」，不改任何判準或鑄造規則；正式使用不需要設它。
# 為什麼要這麼嚴（2026-08-19 Codex 反方審查）：光用 Test-Path 會放行目錄、
# 非 FileSystem provider 的路徑，以及含 cmd 運算子的路徑（後者會直接變成注入面，
# 因為解析結果會被拼進 cmd /c 字串）。
function Resolve-CodexOverride([string]$envName, [string]$rawValue) {
  if ([string]::IsNullOrWhiteSpace($rawValue)) { return $null }
  $ri = $null
  try { $ri = Resolve-Path -LiteralPath $rawValue -ErrorAction Stop }
  catch { throw ($envName + ' 指向無法解析的路徑: ' + $rawValue) }
  if ($ri.Provider.Name -ne 'FileSystem') {
    throw ($envName + ' 必須是檔案系統路徑，實得 provider=' + $ri.Provider.Name + ': ' + $rawValue)
  }
  $resolved = $ri.ProviderPath
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw ($envName + ' 必須指向一個檔案(不是目錄): ' + $resolved)
  }
  Assert-CmdSafePath $resolved $envName   # 解析後的路徑會進 cmd /c 字串
  return $resolved
}

$consultOverride = Resolve-CodexOverride 'SUPER_MODE_CODEX_CMD' $env:SUPER_MODE_CODEX_CMD
if ($consultOverride) { $codexCmd = $consultOverride }


# codex 輸出是 UTF-8：讓 PowerShell 正確解碼進 transcript
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

function Read-TextSmart([string]$path) {
  # BOM 嗅探：UTF-16LE / UTF-8 BOM / 其餘一律當 UTF-8(Claude Write 工具與 bash 的產物)
  $b = [System.IO.File]::ReadAllBytes($path)
  if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2) }
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) }
  return [System.Text.Encoding]::UTF8.GetString($b)
}

# ── validator（憑證鑄造判準）─────────────────────────────────────────────────
# 判準是三平台共用的單一 node 模組 lib/consult-answer.js。這裡只負責「找到 node、
# 找到模組、確認它真的活著」——任何判準邏輯都不在這支裡（那正是要消除的副本）。
$validatorPath = Join-Path $PSScriptRoot "..\lib\consult-answer.js"

function Resolve-NodeExe {
  # 1) SUPER_MODE_NODE 若有設就必須有效——**不靜默退回 PATH**。設了卻壞掉是設定錯誤，
  #    默默改用別的 node 會讓使用者以為自己指定的那支在跑。
  if ($env:SUPER_MODE_NODE) {
    if (-not (Test-Path -LiteralPath $env:SUPER_MODE_NODE)) {
      throw "SUPER_MODE_NODE 指向不存在的檔案: $($env:SUPER_MODE_NODE)"
    }
    return (Resolve-Path -LiteralPath $env:SUPER_MODE_NODE).Path
  }
  # 2) PATH 上的 node。⚠️ gate hook 走的是 settings.json 裡的**絕對路徑**，所以
  #    「hook 正常但 caller 找不到 node」是真的會發生的組合 → 訊息要講清楚怎麼修。
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Invoke-Validator([string]$nodeExe, [string]$answerFile, [string[]]$extraArgs) {
  $outFile = Join-Path $env:TEMP ("consult_v_out_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  $errFile2 = Join-Path $env:TEMP ("consult_v_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  $prevEap = $ErrorActionPreference
  try {
    # ⚠️ 2026-08-18：原本用 `Start-Process -ArgumentList $argv`。那個 API **不保留 argv 邊界**
    #    ——它把陣列用空白串成單一 command line，含空白的路徑會被拆開。實測 `%TEMP%` 或使用者名稱
    #    含空白時，validator 收到 `未知參數: space\answer.txt` → exit 2 → preflight 判 45
    #    ⇒ **那台機器上每一次諮詢都會失敗**。改用呼叫運算子 `&`，它會正確逐一引用參數。
    # ⚠️ 5.1 會把 native command 的 stderr 包成 NativeCommandError 的 ErrorRecord；
    #    若外層是 $ErrorActionPreference='Stop' 就會變成終止性例外。這裡本地降成 Continue。
    $ErrorActionPreference = 'Continue'
    & $nodeExe $validatorPath --answer-file $answerFile @extraArgs 1> $outFile 2> $errFile2
    $code = $LASTEXITCODE
    $so = if (Test-Path $outFile) { [System.IO.File]::ReadAllText($outFile) } else { "" }
    $se = if (Test-Path $errFile2) { [System.IO.File]::ReadAllText($errFile2) } else { "" }
    return @{ Code = $code; Out = $so; Err = $se }
  } finally {
    $ErrorActionPreference = $prevEap
    Remove-Item -LiteralPath $outFile, $errFile2 -Force -ErrorAction SilentlyContinue
  }
}

function Test-ValidatorSentinel($r) {
  # ⚠️ 不可只看 exit 0：空模組、被截斷的檔、被 shim 掉的 node 都會自然 exit 0。
  # ⚠️ 也**不可只比前綴**：`CONSULT-ANSWER-OK-FAKE verdict ALLOW` 會通過前綴檢查
  #    （2026-08-18 設計審查實測）。成功的定義是「stdout 恰好一行、且完全符合哨兵文法」。
  $lines = @($r.Out -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
  if ($lines.Count -ne 1) { return $false }
  return ($lines[0] -cmatch '^CONSULT-ANSWER-OK (?:discussion|json|verdict (?:ALLOW|BLOCK))$')
}

function Assert-ValidatorUsable([string]$nodeExe) {
  # preflight：在燒掉一次諮詢**之前**就確認判準跑得動，而且不是「永遠放行」或「永遠拒絕」。
  # 兩個探針缺一不可——只驗好樣本會放過 always-OK 的空模組，只驗壞樣本會放過 always-43。
  $good = Join-Path $env:TEMP ("consult_pf_g_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  $bad = Join-Path $env:TEMP ("consult_pf_b_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  try {
    [System.IO.File]::WriteAllText($good, ("ALLOW: preflight" + "`n" + ("x" * 60)), (New-Object System.Text.UTF8Encoding $false))
    [System.IO.File]::WriteAllText($bad, "hi", (New-Object System.Text.UTF8Encoding $false))
    $rg = Invoke-Validator $nodeExe $good @()
    $rb = Invoke-Validator $nodeExe $bad @()
    if ($rg.Code -ne 0 -or -not (Test-ValidatorSentinel $rg)) {
      throw "好樣本沒通過（exit=$($rg.Code) stdout=$($rg.Out.Trim())）"
    }
    if ($rb.Code -ne 43) { throw "壞樣本沒被擋（exit=$($rb.Code)）—— 判準可能是空的或被替換" }
  } finally {
    Remove-Item -LiteralPath $good, $bad -Force -ErrorAction SilentlyContinue
  }
}

# ⚠️ Resolve-NodeExe 在 SUPER_MODE_NODE 無效時 `throw`。原本這行沒有 try/catch，
#    於是那條路徑會以未捕捉例外結束、rc=1 且沒有 CONSULT_VALIDATOR_UNAVAILABLE 標記
#    （2026-08-18 設計審查實測 pwsh 7.6.3 與 5.1 皆為 rc=1）。而我的整合測試當時只斷言
#    「非 0」，所以那是**假綠**。契約是 45，就要真的回 45。
$nodeExe = $null
try { $nodeExe = Resolve-NodeExe }
catch {
  [Console]::Error.WriteLine("CONSULT_VALIDATOR_UNAVAILABLE: $_ 未鑄造憑證，**既有憑證未變**。")
  exit 45
}
if (-not $nodeExe -or -not (Test-Path -LiteralPath $validatorPath)) {
  [Console]::Error.WriteLine("CONSULT_VALIDATOR_UNAVAILABLE: " +
    $(if (-not $nodeExe) { "找不到 node（PATH 上沒有，且未設 SUPER_MODE_NODE）。" }
      else { "找不到判準模組: $validatorPath。" }) +
    "未鑄造憑證，**既有憑證未變**。修法：把 node 加進 PATH，或設 SUPER_MODE_NODE 指向 node 執行檔" +
    "（gate hook 用的是 settings.json 裡的絕對路徑，所以 hook 正常不代表 caller 找得到 node）。")
  exit 45
}
try { Assert-ValidatorUsable $nodeExe }
catch {
  [Console]::Error.WriteLine("CONSULT_VALIDATOR_UNAVAILABLE: 判準模組 preflight 失敗 -- $_ 。" +
    "未鑄造憑證，**既有憑證未變**。")
  exit 45
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
  # ⚠️ 2026-08-18：這裡原本用 ConvertFrom-Json，而 POSIX 兩支用的是 node 的 JSON.parse。
  #    那不是同一個 JSON 方言（pwsh 7.x 接受註解與 trailing comma、WinPS 5.1 拒；兩者都接受
  #    NaN 與 01，node 全拒）⇒ 同一份 schema 檔會在不同平台一邊過一邊不過。改成三平台
  #    都走 node，JSON 的判準才只有一個。
  # ⚠️ 走 validator 的 --check-json，**不要**用 `& node -e '<inline script>'`：
  #    WinPS 5.1 的原生參數傳遞會弄壞內嵌腳本的引號，實測 node 丟 ERR_INVALID_ARG_TYPE
  #    （pwsh 7 沒事）——那會讓 5.1 使用者的每一次 -SchemaFile 諮詢都失敗。
  $prevEap2 = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $schemaCheck = & $nodeExe $validatorPath --check-json $SchemaFile 2>&1
  $schemaRc = $LASTEXITCODE
  $ErrorActionPreference = $prevEap2
  if ($schemaRc -ne 0) { throw "SchemaFile is not valid JSON (strict, node): $SchemaFile -- $schemaCheck" }
  $schemaArg = '--output-schema "{4}" '   # 併入 $inner 最高編號 {4}(不動 codex{0}/dir{1}/brief{2}/stderr{3})
}

$logDir = Join-Path $env:USERPROFILE ".claude\super-mode-logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$log = Join-Path $logDir ("codex_consult_{0}_{1}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"), ([guid]::NewGuid().ToString('N').Substring(0, 6)))  # 去重後綴防同秒碰撞

# ── 逐字稿前置：在呼叫 codex **之前**就強制把 log 建出來 ──────────────
# 此刻中止是安全的：還沒有 native 退出碼需要保住。呼叫 codex 之後就不能再這樣做了
# （見下方 capture scope）。順序本身就是設計的一部分。
try {
  [System.IO.File]::WriteAllText($log, "", (New-Object System.Text.UTF8Encoding $false))
}
catch {
  [Console]::Error.WriteLine("CONSULT_TRANSCRIPT_UNAVAILABLE: 無法建立逐字稿 $log -- $_ 。**尚未呼叫 codex**，未鑄造憑證。")
  exit 46
}

$Dir = $Dir.TrimEnd('\')
if ($Dir -match '^[A-Za-z]:$') { $Dir += '\' }
Assert-CmdSafePath $Dir 'Dir'   # $Dir 也進 cmd /c 字串(既有注入面)，一併 fail-closed

# 正規化落地 UTF-8(無 BOM)暫存簡報，cmd `<` 重導向 → 位元組直達 codex
$brief = Join-Path $env:TEMP ("codex_brief_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
$errFile = Join-Path $env:TEMP ("codex_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
# codex 的 **stdout 專用**副本，餵給判準用。⚠️ 不能拿 $log 代替：log 事後會被接上
# "===== STDERR =====" 區段，把 stderr 一起送進判準會改變裁決（例如 schema 模式的 JSON 解析）。
$answerFile = Join-Path $env:TEMP ("codex_answer_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
[System.IO.File]::WriteAllText($brief, $p, (New-Object System.Text.UTF8Encoding $false))
# 逐行捕捉的 codex stdout；裁決一律只看這裡，不回頭讀 $log。
$stdoutLines = New-Object System.Collections.Generic.List[string]
# 逐字稿寫入錯誤只記**第一個**（後續多半是同一個原因刷屏），且絕不中止 pipeline。
$transcriptErrors = New-Object System.Collections.Generic.List[string]
$stderrText = ""
$code = $null

function Get-TranscriptNote {
  if ($transcriptErrors.Count -eq 0) { return "" }
  return " ⚠️ 逐字稿不完整（" + $transcriptErrors[0] + "），上面的判斷是以記憶體捕捉的輸出做的。"
}

try {
  # stderr 導到獨立檔(編號佔位符 {3})；不可用 2>&1(會回灌 stdout)。$LASTEXITCODE 仍是 codex 退出碼。
  # 5.2：--ephemeral 讓短命唯讀諮詢不落地 Codex session 檔(下游不 resume 此 session，留著純浪費)
  # memories 隔離(2026-07-10)：Codex 全域 config 開了 [memories]，會把過往記憶注入 session。
  # consult 必須是「獨立第二意見」→ use_memories=false 斷讀入(否則反方審查被過往記憶污染)、
  # generate_memories=false 斷寫出(否則簡報進全域 memories，下次 consult 又讀到，形成自我強化閉環)。
  # 0.144.1 實測：加這兩個 -c 後 MEMORIES: NO_MEMORIES_VISIBLE、exit 0、MCP 工具面/沙箱邊界皆不受影響。
  $inner = ('"{0}" exec --sandbox read-only --ephemeral --skip-git-repo-check -c memories.use_memories=false -c memories.generate_memories=false -C "{1}" ' + $schemaArg + '< "{2}" 2> "{3}"') -f $codexCmd, $Dir, $brief, $errFile, $SchemaFile

  # ══ native capture scope ══════════════════════════════════════════════════
  # 這一段的唯一任務是「把 codex 跑完、把退出碼與兩條 stream 完整帶出來」。
  # 在拿到退出碼之前，**任何**理由的提前中止都會讓 rc 契約塌成 1。
  #
  # 為什麼要動 preference（2026-08-19 兩 host 實測）：
  #   (1) pwsh 7：`$PSNativeCommandUseErrorActionPreference = $true` 且 `$ErrorActionPreference='Stop'`
  #       時，native 非零退出會丟 NativeCommandExitException —— 連下一行的 `$LASTEXITCODE` 都到不了。
  #       實測 EAP=Stop × native=true → rc 塌成 1、哨兵消失；其餘三組 → rc=42。
  #   (2) WinPS 5.1 沒有 (1) 那個 preference，但會把 native 的 stderr 包成 NativeCommandError；
  #       本處 stderr 已在 cmd 層重導到檔案、正常不經 PowerShell，但 cmd.exe 自己仍可能寫 stderr。
  # ⇒ 兩個都在本 scope 內降級，離開時還原。
  # ⚠️ 這正是 POSIX 版 `set +e` … `code=${PIPESTATUS[0]}` … `set -e` 的平台翻譯，不是新機制。
  $prevEap = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    # -Scope 0 = 只在本 scope 建立遮蔽變數；finally 移除後，呼叫端原本的值自然重新可見。
    Set-Variable -Name 'PSNativeCommandUseErrorActionPreference' -Value $false -Scope 0

    & cmd.exe /d /s /c $inner | ForEach-Object {
      $line = [string]$_
      $line                       # 即時回顯（呼叫端要看得到進度）
      $stdoutLines.Add($line)
      # ⚠️ 這裡**不可以**用 -ErrorAction Stop。log 寫入失敗若中止 pipeline，下面的
      #    $LASTEXITCODE 就抓不到 → 又是一次 rc 塌成 1。（2026-08-19 我第一版的折衷
      #    方案正是犯這個錯，被 Codex 反方審查抓到。）只記第一個錯，繼續 drain。
      if ($transcriptErrors.Count -eq 0) {
        try { Add-Content -LiteralPath $log -Value $line -Encoding utf8 -ErrorAction Stop }
        catch { $transcriptErrors.Add("$_") }
      }
    }
    $code = $LASTEXITCODE       # pipeline 完整結束後**立刻**擷取
  }
  finally {
    $ErrorActionPreference = $prevEap
    Remove-Variable -Name 'PSNativeCommandUseErrorActionPreference' -Scope 0 -ErrorAction SilentlyContinue
  }
  # ══ capture scope 結束 ════════════════════════════════════════════════════

  # ⚠️ 先把 raw stderr 讀進記憶體，**之後**才准清 temp。裁決只吃這份副本。
  if (Test-Path -LiteralPath $errFile) {
    try { $stderrText = [System.IO.File]::ReadAllText($errFile, (New-Object System.Text.UTF8Encoding $false)) }
    catch { if ($transcriptErrors.Count -eq 0) { $transcriptErrors.Add("讀取 stderr 暫存檔失敗: $_") } }
  }

  # codex 的 **stdout 專用**副本，餵給判準用。⚠️ 不能拿 $log 代替：log 事後會被接上
  # "===== STDERR =====" 區段，把 stderr 一起送進判準會改變裁決（例如 schema 模式的 JSON 解析）。
  try { [System.IO.File]::WriteAllText($answerFile, ($stdoutLines -join "`n"), (New-Object System.Text.UTF8Encoding $false)) }
  catch { if ($transcriptErrors.Count -eq 0) { $transcriptErrors.Add("寫入判準用 answer 暫存檔失敗: $_") } }

  # 逐字稿的 stderr 區段：best-effort，失敗只記錄。
  try {
    Add-Content -LiteralPath $log -Value "===== STDERR =====" -Encoding utf8 -ErrorAction Stop
    Add-Content -LiteralPath $log -Value $stderrText -Encoding utf8 -ErrorAction Stop
  }
  catch { if ($transcriptErrors.Count -eq 0) { $transcriptErrors.Add("逐字稿 stderr 區段寫入失敗: $_") } }
}
finally {
  Remove-Item -LiteralPath $brief -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
}

if ($code -eq 0) {
  # ⚠️ 2026-08-19：codex 成功但逐字稿寫壞 → **不得**鑄證。憑證是「這次諮詢真的發生過」的收據，
  #    而逐字稿是它唯一的稽核痕跡；沒有痕跡就不該發收據。專屬 exit 46（雙重失敗優先序見規畫書 §4.3）。
  if ($transcriptErrors.Count -gt 0) {
    [Console]::Error.WriteLine("CONSULT_TRANSCRIPT_FAILED: codex 成功 (exit 0)，但逐字稿寫入失敗 -- " +
      $transcriptErrors[0] + " 。未鑄造憑證，**既有憑證（若有）未被移除**。transcript(可能不完整): $log")
    exit 46
  }
  # ⚠️ 2026-08-18：codex exit 0 **不再等於**可以鑄證。舊行為讓 codex 回空字串或幾個字
  #    也照樣解鎖 gate 20 分鐘，而那種情況通常正代表諮詢其實沒送到。
  #    判準本體在三平台共用的 lib/consult-answer.js，這裡只負責叫它並看結果。
  $vArgs = @()
  if ($NoCredential) { $vArgs += "--no-credential" }
  if ($SchemaFile) { $vArgs += "--schema" }
  $v = Invoke-Validator $nodeExe $answerFile $vArgs
  Remove-Item -LiteralPath $answerFile -Force -ErrorAction SilentlyContinue

  if ($v.Code -ne 0 -or -not (Test-ValidatorSentinel $v)) {
    if ($v.Code -eq 43) {
      [Console]::Error.WriteLine($v.Err.Trim() + " transcript: $log")
      [Console]::Error.WriteLine("（未鑄造新憑證；**既有憑證（若有）未被移除**，其原本的有效期不受本次影響。）")
      exit 43
    }
    # exit 0 但沒有哨兵 = 判準沒真的跑（空模組／被截斷／被 shim 掉的 node 都會自然 exit 0）。
    [Console]::Error.WriteLine("CONSULT_VALIDATOR_UNAVAILABLE: 判準回了 exit $($v.Code) 但沒有預期的成功哨兵" +
      "（stdout='$($v.Out.Trim())'）。未鑄造憑證，**既有憑證未變**。transcript: $log")
    exit 45
  }

  if ($NoCredential) {
    # Discussion-partner mode: no credential, so a casual consult can never
    # unlock super-mode gated actions in a concurrent session on this repo.
    Write-Output "consult OK -- no credential (discussion mode); transcript: $log"
  } else {
    $token = Join-Path $env:USERPROFILE ".claude\.super-mode-consult-ok"
    # 憑證決策範圍：綁定本次諮詢的 repo(-Dir)。hook 會比對後續動作路徑是否在此 repo 下。
    $cred = @{ repo = $Dir; ts = (Get-Date -Format o) } | ConvertTo-Json -Compress
    # 原子寫入：同目錄暫存檔 → 寫入 → 讀回驗證 → rename 才是 commit point。
    # ⚠️ 封存版(380462f)是「直接寫目標檔、寫完才讀回」，讀回失敗時 exit 44 但**舊憑證原封不動**，
    #    訊息卻說「未取得憑證」——它自己的註解點名了這個風險卻沒處理。這裡改掉。
    # ⚠️ 失敗時**刻意不刪除舊憑證**：那是另一個 session 可能還在用的合法收據，
    #    刪它等於引進撤銷語義（那是「動作授權」那批的事）。改成訊息誠實交代。
    $tokenTmp = $token + ".tmp-" + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
      [System.IO.File]::WriteAllText($tokenTmp, $cred, (New-Object System.Text.UTF8Encoding $false))
      $readBack = [System.IO.File]::ReadAllText($tokenTmp)
      if ($readBack -ne $cred) { throw "暫存檔讀回內容與寫入不符" }
      # ⚠️ 2026-08-18 訂正：原本用 `Move-Item -Force`，並在註解宣稱那是
      #    「MoveFileEx + REPLACE_EXISTING 單一 rename」。**那是錯的**——PowerShell 的
      #    FileSystemProvider 實作是 `destination.Delete()` 後才 `source.MoveTo(destination)`，
      #    中間有一段舊憑證不存在的視窗，而且第二步失敗時舊憑證**已經被刪掉了**
      #    ⇒ 本檔到處寫的「失敗時既有憑證未被移除」根本不成立。
      #    改用 .NET 的單次取代：目標存在 → File::Replace()；不存在 → File::Move()。
      # ⚠️ Replace 的第三參數要用 [NullString]::Value 不能用 $null——PowerShell 會把 $null
      #    轉成空字串，實測會丟 ArgumentException（我第一版就是被這個絆倒）。
      if (Test-Path -LiteralPath $token) {
        [System.IO.File]::Replace($tokenTmp, $token, [NullString]::Value)
      } else {
        [System.IO.File]::Move($tokenTmp, $token)
      }
    } catch {
      Remove-Item -LiteralPath $tokenTmp -Force -ErrorAction SilentlyContinue
      [Console]::Error.WriteLine("CONSULT_TOKEN_WRITE_FAILED: 諮詢完成且回覆合格，但憑證寫入失敗: $_ 。" +
        "**既有憑證（若有）未被移除**。請檢查 $token 的權限後重跑。transcript: $log")
      exit 44
    }
    $verdictNote = ($v.Out.Trim() -split '\s+')[-1]
    if ($verdictNote -ceq 'BLOCK') {
      Write-Output "consult OK -- credential written, but Codex 裁決為 BLOCK：依 §3.5 不得執行原動作，先向使用者回報。transcript: $log"
    } else {
      Write-Output "consult OK -- credential written; transcript: $log"
    }
  }
} else {
  Remove-Item -LiteralPath $answerFile -Force -ErrorAction SilentlyContinue
  # 配額/認證類失敗 → 明確標記 + 專屬 exit 42，讓上層 fail-fast、別在額度最稀缺時空轉重試。
  # ══ 配額/認證分類器（兩層）══════════════════════════════════════════════
  # 判準來源是**記憶體裡捕捉的 stderr**，不回頭重讀 $log —— 舊寫法把「分類正確性」
  # 綁在磁碟寫入是否成功上，而 log 寫壞正是最需要正確分類的時候。
  #
  # ⚠️ 為什麼不能在整段 stderr 找子字串（2026-08-19 實證，88 份真實逐字稿）：
  #    codex 把**推理軌跡與工具輸出**寫進 stderr，裡面充滿 grep 行號前綴（`…md:401:`）
  #    與本 repo 原始碼裡的 `CONSULT_UNAVAILABLE_QUOTA` 字串。47 份「只在 stderr 命中」
  #    的逐字稿幾乎全是**成功**的諮詢 ⇒ stderr 是最吵的輸入，不是最乾淨的。
  #    真正的致命錯誤長成「行首 ERROR:、出現在尾端」（2026-08-13 事故即如此）。
  #
  # ⚠️ 我們**沒有**任何「真的配額耗盡」的逐字稿樣本 ⇒ 寫不出有證據支撐的精確正例。
  #    故 Tier 1 只在「錯誤行 ∧ 配額字樣」時才 fail-fast；其餘只提示、不下判斷。
  #    哨兵文案一律是「疑似…（未確證）」——不要再寫成斷言。
  $quotaRe = '(?i)usage limit|rate limit|\b429\b|quota|not logged in|unauthorized|\b401\b'
  $errLineRe = '^\s*(ERROR|error)\b'
  $tailLines = @()
  if ($stderrText) { $tailLines = @(($stderrText -split "`r?`n") | Select-Object -Last 40) }
  $quotaErrLines = @($tailLines | Where-Object { $_ -match $errLineRe -and $_ -match $quotaRe })
  $quotaHintLines = @($tailLines | Where-Object { $_ -match $quotaRe })

  if ($quotaErrLines.Count -gt 0) {
    # 用 [Console]::Error 而非 Write-Warning：$WarningPreference='Stop' 下 Write-Warning 會變成
    # 終止性例外，程式走不到下一行的 exit → 退出碼契約塌成 1（兩 host 實測）。另外 warning stream
    # 跨 process 會落到 OS stdout，呼叫端在 stderr 根本看不到這個哨兵。
    [Console]::Error.WriteLine("CONSULT_UNAVAILABLE_QUOTA: 疑似 codex 配額/認證失敗（未確證，exit $code）。" +
      "判準：逐字稿尾端的 codex 錯誤行命中配額/認證字樣 -- " + $quotaErrLines[0].Trim() +
      " 。停止重試諮詢，向使用者回報；經同意可跑 super-mode.ps1 -Off 降級為一般模式。transcript: $log" + (Get-TranscriptNote))
    exit 42
  }
  $hint = ""
  if ($quotaHintLines.Count -gt 0) {
    # 有字樣但不在 codex 的錯誤行上 —— 依 2026-08-13 的教訓，這種情況**不得**判成配額失敗。
    $hint = " （附註：逐字稿尾端出現配額/認證相關字樣，但不在 codex 的錯誤行上，故未據此判定；" +
      "若你懷疑真的是額度問題，請自行檢視逐字稿。）"
  }
  [Console]::Error.WriteLine("codex-consult: codex exited [$code] -- no credential written. transcript: $log" + (Get-TranscriptNote) + $hint)
}
exit $code
