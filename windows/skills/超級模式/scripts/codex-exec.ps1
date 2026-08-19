<#
.SYNOPSIS
  超級模式 §3 派工：把任務簡報交給 Codex 執行（workspace-write 沙箱）。
  交回後 Claude 必須 review diff，不合格退回重做。
.PARAMETER Dir
  Codex 的工作目錄（專案根，Windows 路徑）。Codex 沙箱進不到 WSL UNC 路徑。
.PARAMETER PromptFile
  從檔案讀任務簡報 — **傳簡報就用這個**。簡報寫進 scratchpad（gate 豁免路徑）再傳路徑。
.PARAMETER Prompt
  DEPRECATED（stage 1：仍可用但出警告，未來版本改為錯誤）。含 ; | & 標點的 inline 簡報
  會被 consult-gate 的指令解析誤判成串接指令而擋下。同時給 -Prompt 與 -PromptFile 現在
  直接報錯，不再靜默採用 -PromptFile。
.PARAMETER OutFile
  Codex 最終回覆落地路徑（--output-last-message）。不給就自動放 ~/.claude/super-mode-logs/。
.EXAMPLE
  .\codex-exec.ps1 -Dir C:\proj -PromptFile <scratchpad>\task.txt
.NOTES
  派工一律用 run_in_background:true 跑本腳本（重任務常超過工具 10 分鐘上限）。
  全程輸出自動存 ~/.claude/super-mode-logs/codex_exec_<ts>.txt。
  STDIN 佈線(v3)：簡報正規化成 UTF-8(無 BOM)暫存檔，用 cmd /s /c 的 `<` 重導向
  位元組直達 codex。不要用 PowerShell pipe — PS 5.1 在 script 內設 $OutputEncoding
  對 native pipe 不生效(作用域坑)，中文會全變 '?'；positional 傳 prompt 會被
  codex.ps1 shim word-split。
#>
param(
  [Parameter(Mandatory = $true)][string]$Dir,
  [string]$Prompt,
  [string]$PromptFile,
  [string]$OutFile,
  [switch]$Quiet,   # 背景派工建議帶：stdout 只印摘要，逐字稿仍寫 log；收工後只讀 _last.txt + git diff
  [string]$SchemaFile   # 可選：JSON schema 檔路徑；給了就讓 Codex 最終回覆符合此結構(--output-schema)，好機器驗收
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

# codex-exec 的接縫**刻意與 consult 分開命名**：exec 跑的是 --sandbox workspace-write，
# 不該讓一個變數同時改動唯讀諮詢與可寫派工兩條路徑。
$execOverride = Resolve-CodexOverride 'SUPER_MODE_CODEX_CMD_EXEC' $env:SUPER_MODE_CODEX_CMD_EXEC
if ($execOverride) { $codexCmd = $execOverride }


# codex 輸出是 UTF-8：讓 PowerShell 正確解碼進 transcript
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

function Read-TextSmart([string]$path) {
  # BOM 嗅探：UTF-16LE / UTF-8 BOM / 其餘一律當 UTF-8(Claude Write 工具與 bash 的產物)
  $b = [System.IO.File]::ReadAllBytes($path)
  if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2) }
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) }
  return [System.Text.Encoding]::UTF8.GetString($b)
}

# C5 stage 1：舊行為是兩個都給就靜默採用 -PromptFile(呼叫端不會發現 inline 被丟掉) → fail-fast。
if ($PromptFile -and $Prompt) {
  throw "同時給了 -Prompt 與 -PromptFile：語意不明確(舊行為靜默採用 -PromptFile)，拒絕執行。請只給 -PromptFile。"
}
if ($PromptFile) { $p = Read-TextSmart $PromptFile }
elseif ($Prompt) {
  $p = $Prompt
  # 用 [Console]::Error 而非 Write-Warning：實測 powershell.exe -File 跨 process 時 warning stream
  # 會落到 OS stdout —— 本腳本的 -Quiet 模式 stdout 就是給呼叫端讀的摘要，被污染會壞掉；
  # 且 $WarningPreference='Stop' 會讓它變終止性例外，違背 staged deprecation「仍可跑」的承諾。
  [Console]::Error.WriteLine("[DEPRECATED] -Prompt(inline) 將於未來版本改為錯誤。inline 簡報含 ; | & 等標點會被 consult-gate 的指令解析誤判成串接指令而擋下。請改用 -PromptFile：用 Write 工具把簡報寫進 scratchpad(gate 豁免路徑)再傳路徑。")
}
else { throw "需提供 -PromptFile（建議）或 -Prompt（已 deprecated）" }
if ([string]::IsNullOrWhiteSpace($p)) { throw "Prompt is empty." }

# 5.1 output-schema：給了 -SchemaFile 就轉絕對路徑並在啟動 Codex 前先驗證可解析(fail-fast)
$schemaArg = ""
if ($SchemaFile) {
  if (-not (Test-Path -LiteralPath $SchemaFile)) { throw "SchemaFile not found: $SchemaFile" }
  $SchemaFile = (Resolve-Path -LiteralPath $SchemaFile).Path   # EXEC 有 -C 換工作根，必須絕對路徑
  Assert-CmdSafePath $SchemaFile 'SchemaFile'                  # 進 cmd /c 前擋注入字元
  try { [System.IO.File]::ReadAllText($SchemaFile, (New-Object System.Text.UTF8Encoding $false)) | ConvertFrom-Json | Out-Null }
  catch { throw "SchemaFile is not valid JSON: $SchemaFile -- $_" }
  $schemaArg = '--output-schema "{5}" '   # 附加成最高編號 {5}，不動 stdin{3}/stderr{4}
}

$logDir = Join-Path $env:USERPROFILE ".claude\super-mode-logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$stamp = "{0}_{1}" -f (Get-Date -Format "yyyyMMdd_HHmmss"), ([guid]::NewGuid().ToString('N').Substring(0, 6))  # 加去重後綴，防同秒並行派工檔名碰撞
$log = Join-Path $logDir ("codex_exec_{0}.txt" -f $stamp)
if (-not $OutFile) { $OutFile = Join-Path $logDir ("codex_exec_{0}_last.txt" -f $stamp) }

# ── 逐字稿前置：在呼叫 codex **之前**就強制把 log 建出來 ──────────────
# 此刻中止是安全的：還沒有 native 退出碼需要保住。呼叫 codex 之後就不能再這樣做了。
try {
  [System.IO.File]::WriteAllText($log, "", (New-Object System.Text.UTF8Encoding $false))
}
catch {
  [Console]::Error.WriteLine("EXEC_TRANSCRIPT_UNAVAILABLE: 無法建立逐字稿 $log -- $_ 。**尚未呼叫 codex**。")
  exit 46
}
# 逐行捕捉的 codex stdout；裁決一律只看這裡，不回頭讀 $log。
$stdoutLines = New-Object System.Collections.Generic.List[string]
# 逐字稿寫入錯誤只記**第一個**（後續多半是同一個原因刷屏），且絕不中止 pipeline。
$transcriptErrors = New-Object System.Collections.Generic.List[string]
$stderrText = ""
$code = $null

function Get-TranscriptNote {
  if ($transcriptErrors.Count -eq 0) { return "" }
  return " ⚠️ 逐字稿不完整（" + $transcriptErrors[0] + "）。"
}


$Dir = $Dir.TrimEnd('\')
if ($Dir -match '^[A-Za-z]:$') { $Dir += '\' }
Assert-CmdSafePath $Dir 'Dir'   # $Dir 也進 cmd /c 字串(既有注入面)，一併 fail-closed

# 正規化落地 UTF-8(無 BOM)暫存簡報，cmd `<` 重導向 → 位元組直達 codex
$brief = Join-Path $env:TEMP ("codex_brief_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
$errFile = Join-Path $env:TEMP ("codex_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
[System.IO.File]::WriteAllText($brief, $p, (New-Object System.Text.UTF8Encoding $false))
try {
  # stderr 導到獨立檔(編號佔位符 {4})；不可用 2>&1(會回灌 stdout)。$LASTEXITCODE 仍是 codex 退出碼。
  # $schemaArg 為空時 {5} 不出現、多帶的 -f 參數無害；有值時併入 --output-schema "{5}"
  # memories 隔離(2026-07-10)：Codex 全域 config 開了 [memories]。派工關掉 memories 讀寫是為
  # (a)可重現：worker 只依本簡報行事，不受過往記憶漂移影響；(b)斷閉環：不把本專案實作細節寫進
  # 全域 memories，否則下次同專案 consult 讀到→反方獨立性被污染。與 consult 對稱處理。
  $inner = ('"{0}" exec --sandbox workspace-write --skip-git-repo-check -c memories.use_memories=false -c memories.generate_memories=false -C "{1}" ' + $schemaArg + '--output-last-message "{2}" < "{3}" 2> "{4}"') -f $codexCmd, $Dir, $OutFile, $brief, $errFile, $SchemaFile

  # ══ native capture scope ══════════════════════════════════════════════════
  # 唯一任務：把 codex 跑完、把退出碼與兩條 stream 完整帶出來。
  # 在拿到退出碼之前，**任何**理由的提前中止都會讓 rc 契約塌成 1。
  # 與 codex-consult.ps1 的同名段落逐字對應；理由與實測見那裡的註解與
  # docs/exit-code-contract-plan-2026-08-19.md §2.1／§4.2。
  # ⚠️ 這是 POSIX 版 `set +e` … `code=${PIPESTATUS[0]}` … `set -e` 的平台翻譯。
  $prevEap = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    Set-Variable -Name 'PSNativeCommandUseErrorActionPreference' -Value $false -Scope 0

    # -Quiet：只寫 log 不回灌 stdout(省 Claude context)；非 Quiet 維持逐行 echo
    & cmd.exe /d /s /c $inner | ForEach-Object {
      $line = [string]$_
      if (-not $Quiet) { $line }
      $stdoutLines.Add($line)
      # ⚠️ 不可用 -ErrorAction Stop：中止 pipeline 就抓不到 $LASTEXITCODE，rc 又會塌成 1。
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

  # ⚠️ 拿不到整數退出碼＝native 根本沒被啟動（典型原因：PATH 缺 System32，cmd.exe 找不到）。
  #    此時 $LASTEXITCODE 維持未設定，`exit $code` 會變成 **exit 0** —— 假成功。
  #    映射成 127（POSIX 的 command not found），與 POSIX 版天然行為一致。
  if ($null -eq $code -or -not ($code -is [int])) {
    [Console]::Error.WriteLine("EXEC_NATIVE_UNAVAILABLE: 無法取得 codex 的退出碼（native 很可能根本沒啟動，" +
      "例如 PATH 缺 System32 導致找不到 cmd.exe）。**不得視為成功**。transcript: $log")
    $code = 127
  }
  if (Test-Path -LiteralPath $errFile) {
    try { $stderrText = [System.IO.File]::ReadAllText($errFile, (New-Object System.Text.UTF8Encoding $false)) }
    catch { if ($transcriptErrors.Count -eq 0) { $transcriptErrors.Add("讀取 stderr 暫存檔失敗: $_") } }
  }
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
  # codex 成功但逐字稿寫壞 → 不得回報成功。派工的逐字稿是後續驗收的唯一依據。
  if ($transcriptErrors.Count -gt 0) {
    [Console]::Error.WriteLine("EXEC_TRANSCRIPT_FAILED: codex 成功 (exit 0)，但逐字稿寫入失敗 -- " +
      $transcriptErrors[0] + " 。transcript(可能不完整): $log ; last message: $OutFile")
    exit 46
  }
  Write-Output "exec OK -- transcript: $log ; last message: $OutFile"
} else {
  [Console]::Error.WriteLine("codex-exec: codex exited [$code]. transcript: $log" + (Get-TranscriptNote))
}
exit $code
