# consult-credential.tests.ps1 -- codex-consult.ps1 的憑證鑄造整合測試（假 codex）。
#
# 為什麼需要這支：consult-answer.test.js 測的是**判準本體**（純函式）。
# 這支測的是 **caller 的接線**——那是 2026-08-18 這批真正新增的風險面：
#   codex 的 stdout 有沒有正確餵給判準（而不是把 stderr 或 log 一起餵進去）、
#   43 有沒有真的不鑄造、哨兵檢查會不會被「exit 0 的空模組」騙過、
#   憑證寫入是不是原子的、失敗時舊憑證有沒有被動到。
#
# 做法：用 SUPER_MODE_CODEX_CMD 換掉 codex 本體，用 USERPROFILE 換掉家目錄，
#       所以完全不碰真的 codex、不碰真的 ~/.claude。
#
# ⚠️ 每個案例都釘**具名斷言**與**精確退出碼**，不比總數。

#
# 受測 host 用 -Shell 切換：codex-consult.ps1 必須在 pwsh 7.x 與 Windows PowerShell 5.1
# 兩邊都成立（使用者的 PowerShell 工具用哪一支不由我們決定）。
param([ValidateSet('pwsh', 'powershell')][string]$Shell = 'pwsh')

$ErrorActionPreference = 'Stop'
$script:pass = 0
$script:fail = 0
$script:failed = @()

function Read-Utf8([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return "" }
  return [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding $false))
}

function Check([string]$name, [bool]$cond, [string]$detail) {
  if ($cond) { $script:pass++; return }
  $script:fail++
  $script:failed += $name
  Write-Output ("  FAIL  " + $name + $(if ($detail) { "`n        " + $detail } else { "" }))
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here "..\scripts\codex-consult.ps1"
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("consult-cred-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$fakeHome = Join-Path $root "home"
New-Item -ItemType Directory -Path (Join-Path $fakeHome ".claude") -Force | Out-Null
$repo = Join-Path $root "repo"
New-Item -ItemType Directory -Path $repo -Force | Out-Null
$brief = Join-Path $root "brief.md"
Set-Content -LiteralPath $brief -Value "測試用簡報" -Encoding utf8
$token = Join-Path $fakeHome ".claude\.super-mode-consult-ok"

# 假 codex：把 STDOUT_FILE 的內容原樣吐到 stdout，退出碼取 EXIT_CODE。
$fakeCodex = Join-Path $root "fake-codex.cmd"
@'
@echo off
type "%STDOUT_FILE%"
exit /b %EXIT_CODE%
'@ | Set-Content -LiteralPath $fakeCodex -Encoding ascii

function Run-Consult([string]$answer, [int]$exitCode, [string[]]$extra, [string[]]$launchArgv) {
  $ansFile = Join-Path $root ("ans-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + ".txt")
  [System.IO.File]::WriteAllText($ansFile, $answer, (New-Object System.Text.UTF8Encoding $false))
  $outF = Join-Path $root "o.txt"; $errF = Join-Path $root "e.txt"
  # §14（2026-10-17）：給了 launchArgv 就改啟動那支 driver（它再以 & 執行整支 SUT）；假 codex／家目錄的準備完全相同。
  $argv = if ($launchArgv) { $launchArgv } else { @("-NoProfile", "-File", $script, "-Dir", $repo, "-PromptFile", $brief) + $extra }
  $env:SUPER_MODE_CODEX_CMD = $fakeCodex
  $env:STDOUT_FILE = $ansFile
  $env:EXIT_CODE = "$exitCode"
  $oldHome = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  try {
    $pr = Start-Process -FilePath $Shell -ArgumentList $argv -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput $outF -RedirectStandardError $errF
    return @{
      Code = $pr.ExitCode
      # ⚠️ 必須指定 UTF-8：受測腳本把中文寫到 stdout，而 WinPS 5.1 的 Get-Content 預設
      #    用 ANSI 解碼，會讀成亂碼，害「訊息內容」類斷言假性失敗（2026-08-18 實際踩到：
      #    5.1 下 out 是「BLOCK: 銝???」）。
      Out  = (Read-Utf8 $outF)
      Err  = (Read-Utf8 $errF)
    }
  } finally { $env:USERPROFILE = $oldHome }
}

$long = "x" * 60

try {
  Write-Output "§1 合格回覆 → 鑄造"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult ("ALLOW: 可以做`n" + $long) 0 @()
  Check "1a ALLOW 合格 → exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "1b ALLOW 合格 → 憑證存在" (Test-Path -LiteralPath $token) "憑證沒寫出來"
  Check "1c 憑證內容綁 repo" ((Get-Content -LiteralPath $token -Raw) -match [regex]::Escape($repo.Replace('\', '\\'))) `
    ("內容=" + (Get-Content -LiteralPath $token -Raw))

  Write-Output "`n§2 BLOCK 仍鑄造（憑證是收據不是授權），但訊息要講"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult ("BLOCK: 不要做`n" + $long) 0 @()
  Check "2a BLOCK → exit 0" ($r.Code -eq 0) ("exit=" + $r.Code)
  Check "2b BLOCK → 憑證仍存在" (Test-Path -LiteralPath $token) "BLOCK 應該仍鑄造"
  # ⚠️ 不可只 match 'BLOCK'：假 codex 的 stdout 本身就含 "BLOCK: 不要做" 並被 echo 出來，
  #    就算把 caller 的警告整段刪掉這條也還是綠的（2026-08-18 設計審查指出＝假綠）。
  Check "2c BLOCK → caller 明說「裁決為 BLOCK」" ($r.Out -match '裁決為 BLOCK') ("out=" + $r.Out)

  Write-Output "`n§3 不合格回覆 → 43 且不鑄造，且**不動既有憑證**"
  # 先放一個既有憑證，內容與 mtime 都記下來
  Set-Content -LiteralPath $token -Value '{"repo":"OLD","ts":"old"}' -Encoding utf8
  $beforeBytes = [System.IO.File]::ReadAllBytes($token)
  $beforeTime = (Get-Item -LiteralPath $token).LastWriteTimeUtc
  Start-Sleep -Milliseconds 1100   # 讓 mtime 有機會不同，否則「沒變」證明不了什麼
  $r = Run-Consult "hi" 0 @()
  Check "3a 過短 → exit 43" ($r.Code -eq 43) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "3b 過短 → stderr 有 UNUSABLE" ($r.Err -match 'CONSULT_UNUSABLE_ANSWER') ("err=" + $r.Err)
  Check "3c 既有憑證 bytes 未變" `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeBytes, [byte[]][System.IO.File]::ReadAllBytes($token))) "憑證內容被動過"
  Check "3d 既有憑證 mtime 未變" `
    ((Get-Item -LiteralPath $token).LastWriteTimeUtc -eq $beforeTime) "憑證 mtime 被動過（gate 只看 mtime，這等於偷偷續期）"

  Write-Output "`n§4 空回覆 / 無裁決"
  $r = Run-Consult "" 0 @()
  Check "4a 空回覆 → 43" ($r.Code -eq 43) ("exit=" + $r.Code)
  $r = Run-Consult ("這是一段夠長但沒有裁決首行的散文" + $long) 0 @()
  Check "4b 無裁決首行 → 43 且 NO_VERDICT" (($r.Code -eq 43) -and ($r.Err -match 'CONSULT_NO_VERDICT')) `
    ("exit=" + $r.Code + " err=" + $r.Err)

  Write-Output "`n§5 討論模式：短回覆放行、但不鑄造"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult "短" 0 @("-NoCredential")
  Check "5a 討論模式短回覆 → exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "5b 討論模式不鑄造" (-not (Test-Path -LiteralPath $token)) "討論模式竟然寫了憑證"
  $r = Run-Consult "" 0 @("-NoCredential")
  Check "5c 討論模式空回覆仍 43" ($r.Code -eq 43) ("exit=" + $r.Code)

  Write-Output "`n§6 codex 自己失敗時，判準不該被叫、也不該鑄造"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult ("ALLOW: 可以`n" + $long) 7 @()
  Check "6a codex exit 7 → 沿用退出碼" ($r.Code -eq 7) ("exit=" + $r.Code)
  Check "6b codex 失敗 → 不鑄造" (-not (Test-Path -LiteralPath $token)) "codex 失敗卻鑄了憑證"

  Write-Output "`n§8 覆蓋既有憑證（2026-08-18 補：先前每個成功案都先刪 token，這條路徑從沒被測到）"
  Set-Content -LiteralPath $token -Value '{"repo":"OLD","ts":"old"}' -Encoding utf8
  $oldBytes = [System.IO.File]::ReadAllBytes($token)
  $r = Run-Consult ("ALLOW: 可以做`n" + $long) 0 @()
  Check "8a 有舊憑證時仍 exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "8b 憑證仍存在（沒有被刪掉又補不回來）" (Test-Path -LiteralPath $token) "憑證不見了"
  Check "8c 憑證內容真的被換成新的" `
    (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$oldBytes, [byte[]][System.IO.File]::ReadAllBytes($token))) "內容還是舊的"
  Check "8d 新憑證綁新 repo" ((Get-Content -LiteralPath $token -Raw) -match [regex]::Escape($repo.Replace('\', '\\'))) `
    ("內容=" + (Get-Content -LiteralPath $token -Raw))
  Check "8e 沒有殘留 .tmp-* 垃圾" `
    (@(Get-ChildItem -LiteralPath (Split-Path $token) -Filter ".super-mode-consult-ok.tmp-*" -Force -ErrorAction SilentlyContinue).Count -eq 0) `
    "殘留了暫存憑證檔"

  Write-Output "`n§9 schema 模式（2026-08-18 補：先前完全沒測到這條路徑）"
  $schemaFile = Join-Path $root "s.json"
  [System.IO.File]::WriteAllText($schemaFile, '{"type":"object"}', (New-Object System.Text.UTF8Encoding $false))
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult '{"ok":true}' 0 @("-SchemaFile", $schemaFile)
  Check "9a 合法短 JSON → exit 0 並鑄造" (($r.Code -eq 0) -and (Test-Path -LiteralPath $token)) ("exit=" + $r.Code + " err=" + $r.Err)
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult "這不是 JSON，只是一段夠長的散文說明文字，用來確認 schema 模式不是免驗金牌。" 0 @("-SchemaFile", $schemaFile)
  Check "9b 非 JSON → 43 且不鑄造" (($r.Code -eq 43) -and (-not (Test-Path -LiteralPath $token))) ("exit=" + $r.Code + " err=" + $r.Err)

  Write-Output "`n§7 判準不可用 → 45（fail-closed，且不鑄造）"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $oldNode = $env:SUPER_MODE_NODE
  $env:SUPER_MODE_NODE = Join-Path $root "no-such-node.exe"
  try {
    $r = Run-Consult ("ALLOW: 可以`n" + $long) 0 @()
    # ⚠️ 原本斷言「非 0」＝假綠：實際 rc 是 1（未捕捉例外），契約卻是 45。
    #    契約是幾就要釘幾（2026-08-18 設計審查指出）。
    Check "7a SUPER_MODE_NODE 無效 → 精確 45" ($r.Code -eq 45) ("exit=" + $r.Code + " err=" + $r.Err)
    Check "7b 不鑄造" (-not (Test-Path -LiteralPath $token)) "判準不可用卻鑄了憑證"
    Check "7c 有 CONSULT_VALIDATOR_UNAVAILABLE 標記" ($r.Err -match 'CONSULT_VALIDATOR_UNAVAILABLE') ("err=" + $r.Err)
  } finally { $env:SUPER_MODE_NODE = $oldNode }

  Write-Output "`n§10 假哨兵不得被接受（2026-08-18 補：只比前綴會被 CONSULT-ANSWER-OK-FAKE 騙過）"
  $fakeNode = Join-Path $root "fake-node.cmd"
  @'
@echo off
echo CONSULT-ANSWER-OK-FAKE verdict ALLOW
exit /b 0
'@ | Set-Content -LiteralPath $fakeNode -Encoding ascii
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $oldNode = $env:SUPER_MODE_NODE
  $env:SUPER_MODE_NODE = $fakeNode
  try {
    $r = Run-Consult ("ALLOW: 可以`n" + $long) 0 @()
    Check "10a 假哨兵 → 45（不是 0）" ($r.Code -eq 45) ("exit=" + $r.Code + " out=" + $r.Out + " err=" + $r.Err)
    Check "10b 假哨兵 → 不鑄造" (-not (Test-Path -LiteralPath $token)) "假判準竟然鑄了憑證"
  } finally { $env:SUPER_MODE_NODE = $oldNode }

  Write-Output "`n§11 路徑含空白（2026-08-18 補：Start-Process -ArgumentList 會拆掉 argv 邊界）"
  $spaceHome = Join-Path $root "home with space"
  New-Item -ItemType Directory -Path (Join-Path $spaceHome ".claude") -Force | Out-Null
  $spaceToken = Join-Path $spaceHome ".claude\.super-mode-consult-ok"
  $ansFile = Join-Path $root "ans-space.txt"
  [System.IO.File]::WriteAllText($ansFile, ("ALLOW: 可以`n" + $long), (New-Object System.Text.UTF8Encoding $false))
  $outF = Join-Path $root "o2.txt"; $errF = Join-Path $root "e2.txt"
  $env:SUPER_MODE_CODEX_CMD = $fakeCodex
  $env:STDOUT_FILE = $ansFile
  $env:EXIT_CODE = "0"
  $oldHome2 = $env:USERPROFILE
  $env:USERPROFILE = $spaceHome
  try {
    $pr = Start-Process -FilePath $Shell -ArgumentList @("-NoProfile", "-File", $script, "-Dir", $repo, "-PromptFile", $brief) `
      -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outF -RedirectStandardError $errF
    Check "11a 家目錄含空白時仍能鑄造（不是 preflight 就 45）" ($pr.ExitCode -eq 0) `
      ("exit=" + $pr.ExitCode + " err=" + (Read-Utf8 $errF))
    Check "11b 憑證確實寫在含空白的路徑下" (Test-Path -LiteralPath $spaceToken) "憑證沒寫出來"
  } finally { $env:USERPROFILE = $oldHome2 }

  Write-Output "`n§12 憑證 commit 的有限重試（CONSULT-TOKEN-REPLACE-FLAKE，2026-10-17；確定性故障注入）"
  # 為什麼不用壓力重跑：那只能證明「機率變低」。這裡在受測 host 起一個 driver，從 SUT 的 AST 抽出
  # Test-TransientTokenCommitError／Move-ConsultTokenIntoPlace 兩個函式，並遮蔽 Start-Sleep：
  #   - 鎖＝driver 以不含 FileShare.Delete 的方式開著目標或暫存檔（Windows 原生「檔案被占用」，真的 Win32 錯誤 32）。
  #   - 遮蔽後的 Start-Sleep 是「第 1 次失敗之後、第 2 次嘗試之前」唯一的交接點，在那裡放鎖
  #     ＝確定性的「暫時失敗後成功」；不放鎖＝確定性的「持續失敗」。鎖的放與不放沒有計時競賽；
  #     唯一不受控的是環境（防毒／索引）在放手後可能再短暫占用一次，見下面 $backoffPrefix 的說明。
  #   - E／F 在同一個交接點刪掉目標檔，模擬 ReplaceFile 的部分完成（1176：舊檔已不在、暫存檔仍在原名）。
  #     E：下一次必須改走 Move 並成功（helper 若只在迴圈外判斷一次 Replace／Move，這裡會變成 FileNotFound）。
  #     F：暫存檔接著被持續占用 ⇒ 用盡後拋回，原位**沒有任何憑證**、暫存檔留給呼叫端清（呼叫端行為見 §14）。
  # ⚠️ 1175／1176／1177（backlog 記錄的原始錯誤是 1175）從 user mode 造不出來，只能在 12h 用合成例外驗判準。
  # ⚠️ driver 必須是純 ASCII：它在執行期才寫出來、不帶 BOM，5.1 會用 ANSI 解讀。
  $tokenCommitDriver = @'
param([Parameter(Mandatory = $true)][string]$Sut, [Parameter(Mandatory = $true)][string]$Work)
$ErrorActionPreference = 'Stop'
$perr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Sut, [ref]$null, [ref]$perr)
if ($perr -and $perr.Count -gt 0) { "TC-PARSE-ERRORS=" + $perr.Count; exit 3 }
$want = @('Test-TransientTokenCommitError', 'Move-ConsultTokenIntoPlace')
$defs = @($ast.FindAll({ param($n) ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($want -contains $n.Name) }, $true))
"TC-FUNCS=" + $defs.Count
if ($defs.Count -ne 2) { exit 3 }
foreach ($d in $defs) { . ([scriptblock]::Create($d.Extent.Text)) }
$script:sleeps = @(); $script:rx = @(); $script:lock = $null; $script:onFirstSleep = $null; $script:curTok = $null; $script:curTmp = $null
# rx = the exception each retry reacted to ($_ of the helper's catch is visible here); diagnostics only, never asserted.
function Start-Sleep { param([int]$Milliseconds) $script:sleeps += $Milliseconds; $script:rx += $(if ($_ -and $_.Exception) { Chain $_.Exception } else { '?' }); if (($script:sleeps.Count -eq 1) -and $script:onFirstSleep) { & $script:onFirstSleep } }
# The stimulus itself must not flake: AV/indexer may hold a fresh file for a moment, so deleting retries (bounded).
function Remove-Robust([string]$p) {
  for ($i = 0; ($i -lt 100) -and (Test-Path -LiteralPath $p); $i++) { try { [IO.File]::Delete($p) } catch { [System.Threading.Thread]::Sleep(20) } }
  if (Test-Path -LiteralPath $p) { throw ('stimulus failed: could not delete ' + $p) }
}
$release = { if ($script:lock) { $script:lock.Dispose(); $script:lock = $null } }
$vanish = { & $release; Remove-Robust $script:curTok }
$vanishLockTmp = { & $vanish; $script:lock = [IO.File]::Open($script:curTmp, 'Open', 'Read', [IO.FileShare]::ReadWrite) }
function Chain($e) { $o = @(); while ($e) { $o += ("{0}:0x{1:X8}" -f $e.GetType().Name, $e.HResult); $e = $e.InnerException }; $o -join '<-' }
function Invoke-Case([string]$id, [bool]$withOld, [string]$lockWhich, $onFirstSleep, [bool]$dropTmp) {
  $dir = Join-Path $Work $id; New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $tok = Join-Path $dir 'tok'; $tmp = Join-Path $dir 'tok.tmp-x'
  $script:curTok = $tok; $script:curTmp = $tmp
  if ($withOld) { [IO.File]::WriteAllText($tok, 'OLD') }
  [IO.File]::WriteAllText($tmp, 'NEW')
  if ($dropTmp) { Remove-Robust $tmp }
  $script:sleeps = @(); $script:rx = @(); $script:onFirstSleep = $onFirstSleep; $script:lock = $null
  if ($lockWhich -eq 'tok') { $script:lock = [IO.File]::Open($tok, 'Open', 'Read', [IO.FileShare]::ReadWrite) }
  if ($lockWhich -eq 'tmp') { $script:lock = [IO.File]::Open($tmp, 'Open', 'Read', [IO.FileShare]::ReadWrite) }
  $err = $null
  try { Move-ConsultTokenIntoPlace $tmp $tok } catch { $err = $_.Exception } finally { if ($script:lock) { $script:lock.Dispose(); $script:lock = $null } }
  $content = if (Test-Path -LiteralPath $tok) { [IO.File]::ReadAllText($tok) } else { '<none>' }
  "TC|{0}|threw={1}|sleeps={2}|tok={3}|tmp={4}|exc={5}|rx={6}" -f $id, [int]($null -ne $err), ($script:sleeps -join ','), $content, [int](Test-Path -LiteralPath $tmp), $(if ($err) { Chain $err } else { '' }), ($script:rx -join ';')
}
Invoke-Case 'A' $true  'tok' $release       $false
Invoke-Case 'B' $false 'tmp' $release       $false
Invoke-Case 'C' $true  'tok' $null          $false
Invoke-Case 'D' $true  ''    $null          $true
Invoke-Case 'E' $true  'tok' $vanish        $false
Invoke-Case 'F' $true  'tok' $vanishLockTmp $false
function Wrap($inner) { New-Object System.Management.Automation.MethodInvocationException('wrapped', $inner) }
$tbl = [ordered]@{
  'io1175' = (New-Object System.IO.IOException('Unable to remove the file to be replaced.', [int]0x80070497))
  'io1175wrap' = (Wrap (New-Object System.IO.IOException('Unable to remove the file to be replaced.', [int]0x80070497)))
  'io32wrap' = (Wrap (New-Object System.IO.IOException('sharing', [int]0x80070020)))
  'io33' = (New-Object System.IO.IOException('lock', [int]0x80070021))
  'io1176' = (New-Object System.IO.IOException('x', [int]0x80070498))
  'io1177' = (New-Object System.IO.IOException('x', [int]0x80070499))
  'uaWrap' = (Wrap (New-Object System.UnauthorizedAccessException('denied')))
  'fnfWrap' = (Wrap (New-Object System.IO.FileNotFoundException('nf')))
  'dnf' = (New-Object System.IO.DirectoryNotFoundException('dnf'))
  'ptl' = (New-Object System.IO.PathTooLongException('ptl'))
  'diskFull' = (New-Object System.IO.IOException('full', [int]0x80070070))
  'io32nonWin32' = (New-Object System.IO.IOException('odd', [int]0x80000020))
  'argument' = (New-Object System.ArgumentException('arg'))
}
foreach ($k in $tbl.Keys) { "TCE|{0}|{1}" -f $k, [int](Test-TransientTokenCommitError $tbl[$k]) }
"TC-DONE"
'@
  $drv = Join-Path $root "token-commit-driver.ps1"
  [System.IO.File]::WriteAllText($drv, $tokenCommitDriver, (New-Object System.Text.UTF8Encoding $false))
  $tcWork = Join-Path $root "tc"
  New-Item -ItemType Directory -Path $tcWork -Force | Out-Null
  $tcOutF = Join-Path $root "tc-o.txt"; $tcErrF = Join-Path $root "tc-e.txt"
  $pr = Start-Process -FilePath $Shell -ArgumentList @("-NoProfile", "-File", $drv, "-Sut", $script, "-Work", $tcWork) `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tcOutF -RedirectStandardError $tcErrF
  $tcOut = Read-Utf8 $tcOutF
  $tc = @{}
  foreach ($ln in ($tcOut -split "`r?`n")) {
    if ($ln -match '^TC\|([A-Z])\|(.*)$') {
      $kv = @{}
      foreach ($pair in ($Matches[2] -split '\|')) { $i = $pair.IndexOf('='); if ($i -gt 0) { $kv[$pair.Substring(0, $i)] = $pair.Substring($i + 1) } }
      $tc[$Matches[1]] = $kv
    } elseif ($ln -match '^TCE\|(\w+)\|([01])$') { $tc['E:' + $Matches[1]] = $Matches[2] }
  }
  $tcDetail = "exit=" + $pr.ExitCode + " out=" + $tcOut + " err=" + (Read-Utf8 $tcErrF)
  Check "12-0 driver 跑完（SUT 裡找得到兩個函式、無 parse error）" (($pr.ExitCode -eq 0) -and ($tcOut -match '(?m)^TC-DONE\r?$')) $tcDetail
  $A = $tc['A']; $B = $tc['B']; $C = $tc['C']; $D = $tc['D']; $E = $tc['E']; $F = $tc['F']
  # 「放手後成功」類的退避序列只要求是退避表的**非空前綴**、而且沒有拋回，不要求剛好 1 次：
  # 2026-10-17 在 repo 實跑時，12a 曾在 driver 放手之後又被環境（推論：防毒／索引服務）多擋一次，
  # 得到 sleeps=50,100——那正是本 ID 要修的真實 flake，重試把它吃掉了。第 1 次失敗是 driver 的鎖
  # 造成的，所以「非空」是確定的；退避值必須照表走，所以也不是放寬成「任何數字都行」。
  # 持續失敗類（12d／12k／14i）仍釘完整退避表：那幾條每一次嘗試都必然失敗，序列是確定的。
  $backoffPrefix = '^50(,100(,200(,400(,800)?)?)?)?$'
  Check "12a Replace 路徑：第 1 次被占用、放手後重試成功（退避照表、從 50ms 起）" `
    (($null -ne $A) -and ($A.threw -eq '0') -and ($A.sleeps -match $backoffPrefix)) $tcDetail
  Check "12b Replace 路徑成功後：憑證是新內容、暫存檔不留" (($null -ne $A) -and ($A.tok -eq 'NEW') -and ($A.tmp -eq '0')) $tcDetail
  Check "12c Move 路徑（無舊憑證）：暫存檔被占用、放手後重試成功" `
    (($null -ne $B) -and ($B.threw -eq '0') -and ($B.sleeps -match $backoffPrefix) -and ($B.tok -eq 'NEW') -and ($B.tmp -eq '0')) $tcDetail
  Check "12d 持續占用：6 次嘗試、退避 50,100,200,400,800 後拋回" `
    (($null -ne $C) -and ($C.threw -eq '1') -and ($C.sleeps -eq '50,100,200,400,800')) $tcDetail
  Check "12e 持續占用（目標檔一直在）：舊憑證內容不動、暫存檔留給呼叫端清" (($null -ne $C) -and ($C.tok -eq 'OLD') -and ($C.tmp -eq '1')) $tcDetail
  Check "12f 拋回的是原本的 Win32 錯誤（sharing violation 0x80070020），沒被改寫" `
    (($null -ne $C) -and ($C.exc -match 'IOException:0x80070020$')) $tcDetail
  Check "12g 不可重試的錯誤（暫存檔不見＝FileNotFound）不重試、舊憑證不動" `
    (($null -ne $D) -and ($D.threw -eq '1') -and ($D.sleeps -eq '') -and ($D.tok -eq 'OLD')) $tcDetail
  Check "12j 目標檔在兩次嘗試之間消失（模擬 1176）：下一次改走 Move 並成功" `
    (($null -ne $E) -and ($E.threw -eq '0') -and ($E.sleeps -match $backoffPrefix) -and ($E.tok -eq 'NEW') -and ($E.tmp -eq '0')) $tcDetail
  Check "12k 目標檔消失後暫存檔持續被占用：退避走完、拋回原本的 0x80070020" `
    (($null -ne $F) -and ($F.threw -eq '1') -and ($F.sleeps -eq '50,100,200,400,800') -and ($F.exc -match 'IOException:0x80070020$')) $tcDetail
  Check "12l 同上的狀態：原位沒有任何憑證（不是舊的、也不是新的）、暫存檔留給呼叫端清" `
    (($null -ne $F) -and ($F.tok -eq '<none>') -and ($F.tmp -eq '1')) $tcDetail
  foreach ($k in @('io1175', 'io1175wrap', 'io32wrap', 'io33', 'io1176', 'io1177', 'uaWrap')) {
    Check "12h 判為可重試：$k" ($tc['E:' + $k] -eq '1') $tcDetail
  }
  foreach ($k in @('fnfWrap', 'dnf', 'ptl', 'diskFull', 'io32nonWin32', 'argument')) {
    Check "12i 判為不可重試：$k" ($tc['E:' + $k] -eq '0') $tcDetail
  }

  Write-Output "`n§12s 靜態守衛：憑證 commit 只能經過重試 helper（防「helper 有測、呼叫端沒用」）"
  $perr = $null
  $sAst = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$perr)
  Check "12s-1 SUT 無 parse error" (($null -eq $perr) -or ($perr.Count -eq 0)) ("parse errors=" + $(if ($perr) { $perr.Count } else { 0 }))
  $inHelper = { param($n) $p = $n.Parent; while ($p) { if (($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($p.Name -eq 'Move-ConsultTokenIntoPlace')) { return $true }; $p = $p.Parent }; return $false }
  $commits = @($sAst.FindAll({ param($n) ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) -and $n.Static -and
      ($n.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) -and ($n.Expression.TypeName.FullName -match '^(System\.)?IO\.File$') -and
      (@('Replace', 'Move') -contains $n.Member.Value) }, $true))
  $outside = @($commits | Where-Object { -not (& $inHelper $_) })
  Check "12s-2 [IO.File]::Replace／Move 恰好 2 處，且都在 Move-ConsultTokenIntoPlace 內" (($commits.Count -eq 2) -and ($outside.Count -eq 0)) `
    ("總數=" + $commits.Count + " helper 外=" + (@($outside | ForEach-Object { "L" + $_.Extent.StartLineNumber }) -join ','))
  $helperCalls = @($sAst.FindAll({ param($n) ($n -is [System.Management.Automation.Language.CommandAst]) -and ($n.GetCommandName() -eq 'Move-ConsultTokenIntoPlace') }, $true))
  Check "12s-3 helper 在 SUT 裡恰好被呼叫 1 次" ($helperCalls.Count -eq 1) ("呼叫次數=" + $helperCalls.Count)
  $helperDef = @($sAst.FindAll({ param($n) ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($n.Name -eq 'Move-ConsultTokenIntoPlace') }, $true))
  $sleepCmds = @(); $threadSleep = @()
  if ($helperDef.Count -eq 1) {
    $sleepCmds = @($helperDef[0].FindAll({ param($n) ($n -is [System.Management.Automation.Language.CommandAst]) -and ($n.GetCommandName() -eq 'Start-Sleep') }, $true))
    $threadSleep = @($helperDef[0].FindAll({ param($n) ($n -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) -and ($n.Member.Value -eq 'Sleep') }, $true))
  }
  Check "12s-4 helper 的退避用 Start-Sleep（§12／§14 的遮蔽才咬得到），不用 Thread::Sleep" `
    (($helperDef.Count -eq 1) -and ($sleepCmds.Count -ge 1) -and ($threadSleep.Count -eq 0)) `
    ("定義數=" + $helperDef.Count + " Start-Sleep=" + $sleepCmds.Count + " ::Sleep=" + $threadSleep.Count)

  Write-Output "`n§13 憑證持續被占用 → 精確 44、舊憑證不動、不留暫存檔（fail-closed 邊界，端到端）"
  # 舊版同樣是 44：這一節守的是「重試用盡後仍正確拒絕」，不是本修的牙齒（牙齒在 §12 與 §14 的 14b–14f）。
  Set-Content -LiteralPath $token -Value '{"repo":"OLD","ts":"old"}' -Encoding utf8
  $heldBytes = [System.IO.File]::ReadAllBytes($token)
  $heldTime = (Get-Item -LiteralPath $token).LastWriteTimeUtc
  # 本行程以不含 FileShare.Delete 的方式握住舊憑證，直到 consult 結束才放 ⇒ 每一次 Replace 都必然失敗（確定性）。
  $hold = [System.IO.File]::Open($token, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try { $r = Run-Consult ("ALLOW: 可以做`n" + $long) 0 @() } finally { $hold.Dispose() }
  Check "13a 持續占用 → 精確 exit 44" ($r.Code -eq 44) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "13b stderr 有 CONSULT_TOKEN_WRITE_FAILED" ($r.Err -match 'CONSULT_TOKEN_WRITE_FAILED') ("err=" + $r.Err)
  Check "13c stdout 沒宣稱已寫入憑證" ($r.Out -notmatch 'credential written') ("out=" + $r.Out)
  Check "13d 舊憑證 bytes 未變" `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$heldBytes, [byte[]][System.IO.File]::ReadAllBytes($token))) "舊憑證被動過"
  Check "13e 舊憑證 mtime 未變" ((Get-Item -LiteralPath $token).LastWriteTimeUtc -eq $heldTime) "舊憑證 mtime 被動過（gate 只看 mtime，這等於偷偷續期）"
  Check "13f 沒有殘留 .tmp-*" `
    (@(Get-ChildItem -LiteralPath (Split-Path $token) -Filter ".super-mode-consult-ok.tmp-*" -Force -ErrorAction SilentlyContinue).Count -eq 0) "殘留了暫存憑證檔"

  Write-Output "`n§14 整支 consult 端到端：commit 暫時失敗後成功／舊憑證消失後持續失敗（child 以 & 執行整支 SUT）"
  # §12 只測 helper 本身；這一節證明「整支 consult 真的經過 helper」：child 先定義遮蔽用的 Start-Sleep
  # （第一次被呼叫時放鎖），以不含 FileShare.Delete 的方式鎖住既有憑證，再以 & 執行整支 SUT。
  # 假 codex、家目錄、判準都沿用 Run-Consult 的準備方式。舊版（單次 Replace）在 release 模式必然 exit 44。
  # vanish-persist：第一次退避時刪掉舊憑證、改鎖暫存憑證（模擬 ReplaceFile 部分完成後仍被占用）；
  # child 的 Remove-Item 遮蔽會在 SUT 自己的清理動作之前放開暫存檔（對方在重試用盡後、清理前放手）。
  # ⚠️ driver 必須是純 ASCII（理由同 §12）。
  $e2eDriver = @'
param([Parameter(Mandatory = $true)][string]$DrvSut, [Parameter(Mandatory = $true)][string]$DrvToken,
  [Parameter(Mandatory = $true)][ValidateSet('release', 'vanish-persist')][string]$DrvMode,
  [Parameter(Mandatory = $true)][string]$DrvDir, [Parameter(Mandatory = $true)][string]$DrvBrief)
# Globals only: inside functions called from the SUT, $script: would resolve to the SUT's own script scope.
$global:CCF = @{ Sleeps = @(); Rx = @(); TokLock = $null; TmpLock = $null; Mode = $DrvMode; Token = $DrvToken; Note = '' }
function Get-CcfChain($e) { $o = @(); while ($e) { $o += ("{0}:0x{1:X8}" -f $e.GetType().Name, $e.HResult); $e = $e.InnerException }; $o -join '<-' }
function Start-Sleep {
  param([int]$Milliseconds)
  $g = $global:CCF
  $g.Sleeps += $Milliseconds
  # Rx = the exception each retry reacted to ($_ of the SUT helper's catch is visible here); diagnostics only.
  $g.Rx += $(if ($_ -and $_.Exception) { Get-CcfChain $_.Exception } else { '?' })
  if ($g.Sleeps.Count -ne 1) { return }
  if ($g.TokLock) { $g.TokLock.Dispose(); $g.TokLock = $null }
  if ($g.Mode -eq 'vanish-persist') {
    # The stimulus itself must not flake: AV/indexer may hold the file for a moment, so deleting retries (bounded).
    for ($i = 0; ($i -lt 100) -and (Test-Path -LiteralPath $g.Token); $i++) {
      try { [System.IO.File]::Delete($g.Token) } catch { [System.Threading.Thread]::Sleep(20) }
    }
    if (Test-Path -LiteralPath $g.Token) { $g.Note += ' token-not-deleted' }
    $tmps = @(Get-ChildItem -LiteralPath (Split-Path -Parent $g.Token) -Filter '.super-mode-consult-ok.tmp-*' -Force)
    if ($tmps.Count -eq 1) {
      $g.TmpLock = [System.IO.File]::Open($tmps[0].FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    } else { $g.Note += ' tmp-count-' + $tmps.Count }
  }
}
function Remove-Item {
  if ($global:CCF.TmpLock) { $global:CCF.TmpLock.Dispose(); $global:CCF.TmpLock = $null }
  Microsoft.PowerShell.Management\Remove-Item @args
}
$code = 'none'
try {
  $global:CCF.TokLock = [System.IO.File]::Open($DrvToken, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  & $DrvSut -Dir $DrvDir -PromptFile $DrvBrief
  $code = $LASTEXITCODE
} catch {
  $global:CCF.Note += ' threw:' + $_.Exception.GetType().Name
} finally {
  if ($global:CCF.TokLock) { $global:CCF.TokLock.Dispose(); $global:CCF.TokLock = $null }
  if ($global:CCF.TmpLock) { $global:CCF.TmpLock.Dispose(); $global:CCF.TmpLock = $null }
}
'E2E|code={0}|sleeps={1}|rx={2}|note={3}' -f $code, ($global:CCF.Sleeps -join ','), ($global:CCF.Rx -join ';'), $global:CCF.Note
exit 0
'@
  $e2eDrv = Join-Path $root "consult-e2e-driver.ps1"
  [System.IO.File]::WriteAllText($e2eDrv, $e2eDriver, (New-Object System.Text.UTF8Encoding $false))
  $tmpGlob = ".super-mode-consult-ok.tmp-*"
  # 群組：1=code 2=sleeps 3=rx（每次重試所對應的例外，只供診斷）4=note（driver 自身的異常）
  $e2eRe = '(?m)^E2E\|code=([^|]*)\|sleeps=([^|]*)\|rx=([^|]*)\|note=([^\r\n]*)\r?$'

  # 14a–14f：release 模式（第 1 次 commit 被占用，第一次退避時放手）
  Set-Content -LiteralPath $token -Value '{"repo":"OLD","ts":"old"}' -Encoding utf8
  $e2eOld = [System.IO.File]::ReadAllBytes($token)
  $r = Run-Consult ("ALLOW: 可以做`n" + $long) 0 @() `
    @("-NoProfile", "-File", $e2eDrv, "-DrvSut", $script, "-DrvToken", $token, "-DrvMode", "release", "-DrvDir", $repo, "-DrvBrief", $brief)
  $m = [regex]::Match($r.Out, $e2eRe)
  $e2eDetail = "driver-exit=" + $r.Code + " out=" + $r.Out + " err=" + $r.Err
  Check "14a driver 跑完、沒有自身錯誤（E2E 標記行存在）" (($r.Code -eq 0) -and $m.Success -and ($m.Groups[4].Value.Trim() -eq '')) $e2eDetail
  Check "14b 舊憑證暫時被占用 → 整支 consult 仍 exit 0" ($m.Success -and ($m.Groups[1].Value -eq '0')) $e2eDetail
  Check "14c 確實走過重試（第 1 次 commit 被擋；退避照表、從 50ms 起）" ($m.Success -and ($m.Groups[2].Value -match $backoffPrefix)) $e2eDetail
  $e2eNow = if (Test-Path -LiteralPath $token) { [System.IO.File]::ReadAllBytes($token) } else { [byte[]]@() }
  Check "14d 憑證是新的（內容換掉、綁本次 repo）" `
    ((-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$e2eOld, [byte[]]$e2eNow)) -and
     ([System.Text.Encoding]::UTF8.GetString($e2eNow) -match [regex]::Escape($repo.Replace('\', '\\')))) `
    ("內容=" + [System.Text.Encoding]::UTF8.GetString($e2eNow))
  Check "14e 沒有殘留 .tmp-*" `
    (@(Get-ChildItem -LiteralPath (Split-Path $token) -Filter $tmpGlob -Force -ErrorAction SilentlyContinue).Count -eq 0) "殘留了暫存憑證檔"
  Check "14f 成功訊息正常（credential written）、沒有 CONSULT_TOKEN_WRITE_FAILED" `
    (($r.Out -match '(?m)^consult OK -- credential written; transcript: ') -and ($r.Err -notmatch 'CONSULT_TOKEN_WRITE_FAILED')) $e2eDetail

  # 14g–14l：vanish-persist 模式（第一次退避時舊憑證已不在、暫存憑證接著被持續占用）
  Set-Content -LiteralPath $token -Value '{"repo":"OLD","ts":"old"}' -Encoding utf8
  $r = Run-Consult ("ALLOW: 可以做`n" + $long) 0 @() `
    @("-NoProfile", "-File", $e2eDrv, "-DrvSut", $script, "-DrvToken", $token, "-DrvMode", "vanish-persist", "-DrvDir", $repo, "-DrvBrief", $brief)
  $m = [regex]::Match($r.Out, $e2eRe)
  $e2eDetail = "driver-exit=" + $r.Code + " out=" + $r.Out + " err=" + $r.Err
  Check "14g driver 跑完、沒有自身錯誤（E2E 標記行存在）" (($r.Code -eq 0) -and $m.Success -and ($m.Groups[4].Value.Trim() -eq '')) $e2eDetail
  Check "14h 舊憑證消失後暫存檔持續被占用 → 精確 exit 44" ($m.Success -and ($m.Groups[1].Value -eq '44')) $e2eDetail
  Check "14i 每次嘗試都重判 Replace／Move：退避表走完（50,100,200,400,800）" `
    ($m.Success -and ($m.Groups[2].Value -eq '50,100,200,400,800')) $e2eDetail
  Check "14j 原位沒有任何憑證（fail-closed：不是舊憑證被續期、也不是新憑證）" (-not (Test-Path -LiteralPath $token)) `
    ("憑證竟然存在：" + $(if (Test-Path -LiteralPath $token) { Get-Content -LiteralPath $token -Raw } else { "" }))
  Check "14k 暫存憑證被清掉、不殘留 .tmp-*" `
    (@(Get-ChildItem -LiteralPath (Split-Path $token) -Filter $tmpGlob -Force -ErrorAction SilentlyContinue).Count -eq 0) "殘留了暫存憑證檔"
  Check "14l stderr 有 CONSULT_TOKEN_WRITE_FAILED、stdout 沒宣稱已寫入" `
    (($r.Err -match 'CONSULT_TOKEN_WRITE_FAILED') -and ($r.Out -notmatch 'credential written')) $e2eDetail
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item Env:SUPER_MODE_CODEX_CMD -ErrorAction SilentlyContinue
  Remove-Item Env:STDOUT_FILE -ErrorAction SilentlyContinue
  Remove-Item Env:EXIT_CODE -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("CONSULT-CREDENTIAL " + $script:pass + "/" + ($script:pass + $script:fail))
if ($script:fail -gt 0) {
  Write-Output ("失敗清單：" + ($script:failed -join "、"))
  foreach ($n in $script:failed) { Write-Output ("FAILED-CASE: " + $n) }
  exit 1
}
exit 0
