# project-root-marker.tests.ps1 -- Windows：codex-exec.ps1／codex-consult.ps1 的專案指示根偵測（2026-10-20）。
#
# 守的規則（與 macos/skills/超級模式/tests/project-root-marker.tests.sh 同一組 A–F 案例）：
#   - 從 -Dir 往上找得到 .codex-project-root ⇒ codex argv 帶**一組** `-c project_root_markers=[".git",".codex-project-root"]`；
#     找不到 ⇒ 完全不帶。
#   - `-C` 一律是呼叫端給的 -Dir 原字串（cwd 與可寫範圍不變）。
#   - 成功摘要尾端印 cwd（Resolve-Path 後的絕對路徑）、預期的指示根、override yes/no。
#   - 指示根 = cwd 往上最近的標記目錄（.git 檔或目錄也算）；都沒有 ⇒ none (cwd only)。
#   - -Dir 不存在時偵測不得中止（行為交給 codex 自己報錯，與改動前相同）。
#
# Windows 另外守的：
#   - **`"` 要完整到達 codex**：stub 是 .cmd，以 %* 把參數交給 node（與 npm 的 codex.cmd shim 同一條路：
#     cmd /s /c → batch %* → MSVCRT 規則剖 argv），由 node 記下它實際收到的 argv。裸 `"` 在這條路上會被剝掉，
#     A2／A3 就會紅。
#   - 無標記時 codex argv 必須與加入前**逐元素相同**（B6／F5 比對整個 argv；A8 比對「舊 argv 插入兩個元素」）。
#   - 每案先驗 stub 恰跑一次（X0）：證明接縫生效，不是因為根本沒跑而讓斷言以錯誤理由通過。
#   - G 案（macOS 版沒有）：只有 .git **目錄**、沒有標記 ⇒ 不帶覆寫、指示根＝那一層。
#   - 「-C 是原 -Dir」指的是既有前處理（TrimEnd('\')、磁碟根補 \）之後的字串，與加入前相同；
#     本修法不再改動 -Dir。I 案：磁碟根的 -Dir 字串仍是 `C:\`，只有拼進 cmd 字串時才把結尾 \ 加倍。
#   - 不涵蓋：symlink／junction（偵測走 Resolve-Path 的邏輯路徑，macOS 走 pwd -P 實體路徑）、
#     呼叫端設 $PSNativeCommandArgumentPassing='Standard'（pwsh 7.3+；cmd.exe 只在預設的 Windows 模式走 Legacy）。
#   - A–G 的情境路徑含空白與 CJK；H 案（2026-10-31）另驗含 & 的目錄：-Dir／-SchemaFile／$PWD.ProviderPath 都逐字到達
#     argv、cmd 沒有斷句，cwd、-C 與憑證的 repo 三者一致。目錄名刻意含 `&echo INJECTED`：& 若被當成運算子，argv 會被截斷。
#
# ⚠️ 本檔只驗 wrapper 的 argv 與摘要，**不證明** codex 真的載入了 AGENTS.md。
#    那要用非 ephemeral 的真 codex 探測，看 ~/.codex/sessions 的 rollout 初始 user 訊息。
#
# 用法：pwsh -NoProfile -File project-root-marker.tests.ps1 [-Shell pwsh|powershell] [-ExecSut <codex-exec.ps1>] [-ConsultSut <codex-consult.ps1>]
#   -Shell = 受測 child 的 host（預設與 runner 相同）。-ExecSut／-ConsultSut 只給牙齒檢查用
#   （對舊版跑，應該要紅）；正式驗收不要帶。
# ⚠️ 隔離：受測腳本一律在**子行程**跑，USERPROFILE 指向本測試自建的暫存家目錄；兩個接縫變數
#    （SUPER_MODE_CODEX_CMD／SUPER_MODE_CODEX_CMD_EXEC）一律指向 stub，絕不打到真的 codex。
#    §0 先讓 child 回報它看到的 USERPROFILE，對不上就整支中止。

param(
  [ValidateSet('pwsh', 'powershell')]
  [string]$Shell = $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }),
  [string]$ExecSut = '',
  [string]$ConsultSut = ''
)

$ErrorActionPreference = 'Stop'
$script:pass = 0
$script:fail = 0
$script:failed = @()
$CHILD_TIMEOUT_MS = 60000

function Read-Text([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return "" }
  return [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding $false))
}
function Write-Utf8([string]$path, [string]$text) {
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}
function Check([string]$name, [bool]$cond, [string]$detail) {
  if ($cond) { $script:pass++; return }
  $script:fail++
  $script:failed += $name
  Write-Output ("  FAIL  " + $name + $(if ($detail) { "`n        " + $detail } else { "" }))
}
function New-Id { [guid]::NewGuid().ToString('N').Substring(0, 8) }
function Test-Marker([string]$d) {
  foreach ($n in @('.git', '.codex-project-root')) {
    $p = [System.IO.Path]::Combine($d, $n)
    if ([System.IO.File]::Exists($p) -or [System.IO.Directory]::Exists($p)) { return $true }
  }
  return $false
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ExecSut) { $ExecSut = Join-Path $here "..\scripts\codex-exec.ps1" }
if (-not $ConsultSut) { $ConsultSut = Join-Path $here "..\scripts\codex-consult.ps1" }
foreach ($s in @($ExecSut, $ConsultSut)) {
  if (-not (Test-Path -LiteralPath $s -PathType Leaf)) { Write-Output "找不到受測腳本：$s"; exit 2 }
}
$ExecSut = (Resolve-Path -LiteralPath $ExecSut).Path
$ConsultSut = (Resolve-Path -LiteralPath $ConsultSut).Path

# stub 與 codex-consult.ps1 的判準 preflight 都需要 node。缺了是 hard fail，不是 skip。
$nodeCmd = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $nodeCmd) { Write-Output "PREREQ-MISSING: PATH 上沒有 node（stub 與 consult 的判準都需要）。這是 hard fail，不是 skip。"; exit 3 }

# 與受測腳本同一套正規化（Resolve-Path），期望值才比得中（TEMP 可能是 8.3 短名，兩邊都不展開）。
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("prmark-" + (New-Id))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$root = (Resolve-Path -LiteralPath $root).ProviderPath

# 前置：暫存區往上不得已有標記，否則「無標記」案會以錯誤的理由變紅。
$d = $root
while ($d) {
  if (Test-Marker $d) {
    Write-Output ("PREREQ: 暫存區祖先 " + $d + " 已有 .git 或 .codex-project-root，本測試無法建立「無標記」情境。")
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    exit 3
  }
  $d = [System.IO.Path]::GetDirectoryName($d)
}

$fakeHome = Join-Path $root "home"
New-Item -ItemType Directory -Path (Join-Path $fakeHome ".claude") -Force | Out-Null
$stubDir = Join-Path $root "stub"
New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
$brief = Join-Path $root "brief.md"; Write-Utf8 $brief "測試用簡報`n"
$argvFile = Join-Path $root "argv.json"
$trace = Join-Path $root "stub-trace.txt"

# stub codex：.cmd 以 %* 交給 node（同 npm shim），node 把收到的 argv 寫成 JSON、每跑一次記一行 trace，
# stdout 給一段非空答案（consult -NoCredential 只要求非空）。
$dumpJs = Join-Path $stubDir "argv-dump.js"
Write-Utf8 $dumpJs @'
'use strict';
const fs = require('fs');
fs.appendFileSync(process.env.FAKE_TRACE, 'RAN\n');
fs.writeFileSync(process.env.FAKE_ARGV, JSON.stringify(process.argv.slice(2)), 'utf8');
try { fs.readFileSync(0); } catch (e) { /* stdin 已關閉也無妨 */ }
process.stdout.write(process.env.FAKE_ANSWER || 'stub answer: ready\n');
'@
$fakeCodex = Join-Path $stubDir "fake-codex.cmd"
@'
@echo off
"%PRM_NODE%" "%PRM_DUMP_JS%" %*
exit /b %ERRORLEVEL%
'@ | Set-Content -LiteralPath $fakeCodex -Encoding ascii

# wrapper：參數全走環境變數（Start-Process -ArgumentList 不保留 argv 邊界；含空白／CJK 的 -Dir 會被拆開）。
# ⚠️ 必須 UTF-8 **with BOM**：WinPS 5.1 讀無 BOM 的 .ps1 用 ANSI 解碼。
$wrapper = Join-Path $root "wrapper.ps1"
$wrapperSrc = @'
$ht = @{ Dir = $(if ($env:PRM_USE_PWD) { $PWD.ProviderPath } else { $env:PRM_DIR }); PromptFile = $env:PRM_BRIEF }
if ($env:PRM_SCHEMA) { $ht['SchemaFile'] = $env:PRM_SCHEMA }
if ($env:PRM_MODE -eq 'exec') { $ht['Quiet'] = $true } elseif (-not $env:PRM_CRED) { $ht['NoCredential'] = $true }
& $env:PRM_TARGET @ht
exit $LASTEXITCODE
'@
[System.IO.File]::WriteAllText($wrapper, $wrapperSrc, (New-Object System.Text.UTF8Encoding $true))
$probe = Join-Path $root "probe.ps1"
# probe 先把 stdout 定成 UTF-8：Read-Text 以 UTF-8 讀，TEMP／USERPROFILE 含中文時（5.1 的 console code page
# 不是 UTF-8）0c 才不會因解碼錯誤假紅。受測腳本自己也設同一行，所以 SUT 的摘要不受影響。
[System.IO.File]::WriteAllText($probe, ('try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}' +
  "`r`n" + '$PSVersionTable.PSVersion.ToString(); $env:USERPROFILE'),
  (New-Object System.Text.UTF8Encoding $true))

# 情境目錄：名稱刻意含空白與 CJK。
$P = Join-Path $root "proj 專案"
foreach ($sub in @("sub\deep", "wt\x")) { New-Item -ItemType Directory -Path (Join-Path $P $sub) -Force | Out-Null }
New-Item -ItemType Directory -Path (Join-Path $root "plain\sub") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root "gitrepo\.git") -Force | Out-Null   # 只有 .git **目錄**、沒有標記
New-Item -ItemType Directory -Path (Join-Path $root "gitrepo\sub") -Force | Out-Null
$AMP = Join-Path $root "proj 專案&echo INJECTED"      # H 案：& 若被 cmd 當運算子，argv 會在這裡斷掉
New-Item -ItemType Directory -Path $AMP -Force | Out-Null
$ampSchema = Join-Path $AMP "schema&x.json"; Write-Utf8 $ampSchema "{}"
$ZW = Join-Path $root ([string][char]0x200D)         # I3：文化比較的 EndsWith('\') 會把它誤判成以 \ 結尾
New-Item -ItemType Directory -Path $ZW -Force | Out-Null
Write-Utf8 (Join-Path $P ".codex-project-root") ""
Write-Utf8 (Join-Path $P "wt\.git") "gitdir: C:\nonexistent\.git\worktrees\wt`n"   # 巢狀 .git 檔（gitdir 失效）

$MARKERS = 'project_root_markers=[".git",".codex-project-root"]'
$OUTFILE_RE = '\\codex_exec_\d{8}_\d{6}_[0-9a-f]{6}_last\.txt$'

function Start-Child([string]$argString, [string]$cwd) {
  $o = Join-Path $root ("o-" + (New-Id) + ".txt")
  $e = Join-Path $root ("e-" + (New-Id) + ".txt")
  $oldHome = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  try {
    $pr = Start-Process -FilePath $Shell -ArgumentList $argString -WorkingDirectory $cwd -NoNewWindow -PassThru `
      -RedirectStandardOutput $o -RedirectStandardError $e
    $null = $pr.Handle   # 先取 handle，ExitCode 才可靠（5.1 的 Start-Process -PassThru 坑，見 run-windows-suite.ps1）
    if (-not $pr.WaitForExit($CHILD_TIMEOUT_MS)) {
      try { $pr.Kill() } catch {}
      return @{ Code = -999; Out = ""; Err = "TIMEOUT" }
    }
    return @{ Code = $pr.ExitCode; Out = (Read-Text $o); Err = (Read-Text $e) }
  }
  finally {
    $env:USERPROFILE = $oldHome
    Remove-Item -LiteralPath $o, $e -Force -ErrorAction SilentlyContinue
  }
}

# Invoke-Sut exec|consult <dir> [cwd]：回傳 rc、stdout、stderr、stub 執行次數、codex 實收的 argv。
# -Schema 帶 -SchemaFile；-UsePwd 以 $PWD.ProviderPath 當 -Dir；-Credential 讓 consult 走鑄證模式；-Answer 換 stub 的回覆。
function Invoke-Sut([string]$Mode, [string]$Dir, [string]$Cwd = '', [string]$Schema = '', [switch]$UsePwd, [switch]$Credential, [string]$Answer = '') {
  if (-not $Cwd) { $Cwd = $root }
  Remove-Item -LiteralPath $argvFile, $trace -Force -ErrorAction SilentlyContinue
  $env:PRM_MODE = $Mode
  $env:PRM_TARGET = $(if ($Mode -eq 'exec') { $ExecSut } else { $ConsultSut })
  $env:PRM_DIR = $Dir
  $env:PRM_BRIEF = $brief
  $env:PRM_SCHEMA = $Schema
  $env:PRM_USE_PWD = $(if ($UsePwd) { '1' } else { '' })
  $env:PRM_CRED = $(if ($Credential) { '1' } else { '' })
  $env:FAKE_ANSWER = $Answer
  $r = Start-Child ('-NoProfile -File "' + $wrapper + '"') $Cwd
  $ran = @((Read-Text $trace) -split "`r?`n" | Where-Object { $_ -eq 'RAN' }).Count
  $argv = @()
  $json = Read-Text $argvFile
  if ($json) { $parsed = ConvertFrom-Json -InputObject $json; $argv = @($parsed | ForEach-Object { [string]$_ }) }
  $r['Ran'] = $ran
  $r['Argv'] = $argv
  return $r
}

# argv 中「a 緊接 b」出現幾次（大小寫敏感）
function Get-PairCount([string[]]$argv, [string]$a, [string]$b) {
  $n = 0
  for ($i = 0; $i -lt ($argv.Count - 1); $i++) { if (($argv[$i] -ceq $a) -and ($argv[$i + 1] -ceq $b)) { $n++ } }
  return $n
}
function Get-ElemCount([string[]]$argv, [string]$v) { return @($argv | Where-Object { $_ -ceq $v }).Count }

# 加入前的 codex argv（逐元素），withMarker 時在 memories 兩個 -c 之後、-C 之前插入兩個元素。
# exec 的 --output-last-message 值是隨機逐字稿檔名 → 以 <OUTFILE> 佔位、改用 regex 比。
function Get-ExpectedArgv([string]$Mode, [string]$Dir, [bool]$WithMarker) {
  $head = if ($Mode -eq 'exec') { @('exec', '--sandbox', 'workspace-write', '--skip-git-repo-check') }
          else { @('exec', '--sandbox', 'read-only', '--ephemeral', '--skip-git-repo-check') }
  $mid = @('-c', 'memories.use_memories=false', '-c', 'memories.generate_memories=false')
  if ($WithMarker) { $mid += @('-c', $MARKERS) }
  $tail = if ($Mode -eq 'exec') { @('-C', $Dir, '--output-last-message', '<OUTFILE>') } else { @('-C', $Dir) }
  return @($head + $mid + $tail)
}
function Test-ArgvExact([string[]]$got, [string[]]$exp) {
  if ($got.Count -ne $exp.Count) { return $false }
  for ($i = 0; $i -lt $exp.Count; $i++) {
    if ($exp[$i] -ceq '<OUTFILE>') { if ($got[$i] -notmatch $OUTFILE_RE) { return $false } }
    elseif (-not ($got[$i] -ceq $exp[$i])) { return $false }
  }
  return $true
}
function Format-Argv([string[]]$argv) { return ('[' + (($argv | ForEach-Object { '<' + $_ + '>' }) -join ' ') + ']') }
function Test-Has([string]$hay, [string]$needle) { return $hay.Contains($needle) }
# 成功摘要那一行（exec OK -- …／consult OK -- …）必須以 suffix 結尾：鎖住「附在同一行的尾端」。
function Test-SummaryTail([string]$out, [string]$suffix) {
  $hit = @(($out -split "`r?`n") | Where-Object { ($_ -like 'exec OK -- *' -or $_ -like 'consult OK -- *') -and $_.EndsWith($suffix) })
  return ($hit.Count -eq 1)
}

try {
  # ═══ §0 attestation ════════════════════════════════════════════════════════
  $p0 = Start-Child ('-NoProfile -File "' + $probe + '"') $root
  $lines = @(($p0.Out -split "`r?`n") | Where-Object { $_ })
  $childVer = if ($lines.Count -ge 1) { $lines[0] } else { "" }
  $childHome = if ($lines.Count -ge 2) { $lines[1] } else { "" }
  Write-Output ("§0 runner host = " + $PSVersionTable.PSVersion + " / child host = " + $Shell +
    " (自報 " + $childVer + ") / node = " + $nodeCmd.Source)
  Write-Output ("   SUT exec    = " + $ExecSut)
  Write-Output ("   SUT consult = " + $ConsultSut)
  Check "0a child host 版本可取得" (-not [string]::IsNullOrWhiteSpace($childVer)) ("out=" + $p0.Out + " err=" + $p0.Err)
  if ($Shell -eq 'powershell') { Check "0b -Shell powershell 必須真的是 5.x" ($childVer -like '5.*') "child 自報 $childVer" }
  else { Check "0b -Shell pwsh 必須真的是 7+" ($(try { ([version]$childVer).Major -ge 7 } catch { $false })) "child 自報 $childVer" }
  $homeOk = ($childHome -eq $fakeHome)
  Check "0c child 看到的 USERPROFILE 是暫存家目錄" $homeOk ("child=" + $childHome + " 期望=" + $fakeHome)
  if (-not $homeOk) {
    Write-Output "ABORT  USERPROFILE 隔離沒生效，為了不碰真的 ~/.claude，以下案例一律不跑。"
    throw "isolation-failed"
  }

  # 兩個接縫一律指向 stub（留空會 fallback 到真的 C:\npm\codex.cmd）。
  $env:SUPER_MODE_CODEX_CMD = $fakeCodex
  $env:SUPER_MODE_CODEX_CMD_EXEC = $fakeCodex
  $env:PRM_NODE = $nodeCmd.Source
  $env:PRM_DUMP_JS = $dumpJs
  $env:FAKE_ARGV = $argvFile
  $env:FAKE_TRACE = $trace

  foreach ($mode in @('exec', 'consult')) {
    Write-Output ("§" + $mode + " A 子目錄、祖先有標記 ⇒ 帶覆寫，-C 不變，指示根＝標記目錄")
    $dA = Join-Path $P "sub\deep"
    $r = Invoke-Sut $mode $dA
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode A0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode A1 rc=0" ($r.Code -eq 0) $ctx
    Check "$mode A2 -c 覆寫恰一組（含 `" 完整到達）" ((Get-PairCount $r.Argv '-c' $MARKERS) -eq 1) $ctx
    Check "$mode A3 覆寫值只出現一次" ((Get-ElemCount $r.Argv $MARKERS) -eq 1) $ctx
    Check "$mode A4 -C 仍是原 -Dir" ((Get-PairCount $r.Argv '-C' $dA) -eq 1) $ctx
    Check "$mode A5 摘要 cwd" (Test-Has $r.Out ("cwd: " + $dA + " ;")) $ctx
    Check "$mode A6 摘要指示根" (Test-Has $r.Out ("instructions root: " + $P + " ;")) $ctx
    Check "$mode A7 摘要行尾 override yes" (Test-SummaryTail $r.Out " ; project_root_markers override: yes") $ctx
    Check "$mode A8 argv＝舊 argv 在 -C 前插入兩個元素" (Test-ArgvExact $r.Argv (Get-ExpectedArgv $mode $dA $true)) $ctx

    Write-Output ("§" + $mode + " B 無標記 ⇒ 不帶覆寫，指示根 none，argv 與加入前逐元素相同")
    $dB = Join-Path $root "plain\sub"
    $r = Invoke-Sut $mode $dB
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode B0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode B1 rc=0" ($r.Code -eq 0) $ctx
    Check "$mode B2 不得帶覆寫" ((Get-ElemCount $r.Argv $MARKERS) -eq 0) $ctx
    Check "$mode B3 -C 仍是原 -Dir" ((Get-PairCount $r.Argv '-C' $dB) -eq 1) $ctx
    Check "$mode B4 摘要指示根 none" (Test-Has $r.Out "instructions root: none (cwd only) ;") $ctx
    Check "$mode B5 摘要行尾 override no" (Test-SummaryTail $r.Out " ; project_root_markers override: no") $ctx
    Check "$mode B6 argv 與加入前逐元素相同" (Test-ArgvExact $r.Argv (Get-ExpectedArgv $mode $dB $false)) $ctx

    Write-Output ("§" + $mode + " C 標記之下有較近的巢狀 .git 檔 ⇒ 仍帶覆寫，指示根＝.git 那層")
    $r = Invoke-Sut $mode (Join-Path $P "wt\x")
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode C0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode C1 rc=0" ($r.Code -eq 0) $ctx
    Check "$mode C2 帶覆寫" ((Get-PairCount $r.Argv '-c' $MARKERS) -eq 1) $ctx
    Check "$mode C3 指示根＝巢狀 .git 目錄" (Test-Has $r.Out ("instructions root: " + (Join-Path $P "wt") + " ;")) $ctx

    Write-Output ("§" + $mode + " D 標記就在 -Dir ⇒ 指示根＝-Dir")
    $r = Invoke-Sut $mode $P
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode D0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode D1 帶覆寫" ((Get-PairCount $r.Argv '-c' $MARKERS) -eq 1) $ctx
    Check "$mode D2 指示根＝-Dir" (Test-Has $r.Out ("instructions root: " + $P + " ;")) $ctx

    Write-Output ("§" + $mode + " E 相對 -Dir ⇒ -C 保留相對字串，摘要 cwd 為絕對路徑")
    $r = Invoke-Sut $mode "sub\deep" $P
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode E0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode E1 rc=0" ($r.Code -eq 0) $ctx
    Check "$mode E2 -C 保留相對字串" ((Get-PairCount $r.Argv '-C' "sub\deep") -eq 1) $ctx
    Check "$mode E3 帶覆寫" ((Get-PairCount $r.Argv '-c' $MARKERS) -eq 1) $ctx
    Check "$mode E4 摘要 cwd 絕對" (Test-Has $r.Out ("cwd: " + (Join-Path $P "sub\deep") + " ;")) $ctx

    Write-Output ("§" + $mode + " F -Dir 不存在 ⇒ 偵測不得中止，不帶覆寫，交給 codex")
    $dF = Join-Path $root "no-such-dir"
    $r = Invoke-Sut $mode $dF
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode F0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode F1 rc=0（stub 不驗 -C）" ($r.Code -eq 0) $ctx
    Check "$mode F2 codex 仍被呼叫且 -C 原樣" ((Get-PairCount $r.Argv '-C' $dF) -eq 1) $ctx
    Check "$mode F3 不帶覆寫" ((Get-ElemCount $r.Argv $MARKERS) -eq 0) $ctx
    Check "$mode F4 摘要指示根 unknown" (Test-Has $r.Out "instructions root: unknown ;") $ctx
    Check "$mode F5 argv 與加入前逐元素相同" (Test-ArgvExact $r.Argv (Get-ExpectedArgv $mode $dF $false)) $ctx

    # G 是 Windows 版多加的（macOS 版沒有）：A–F 裡的 .git 都是**檔案**、且都有標記，
    # 拿掉 Directory.Exists 或「只有 .git」那條指示根分支，A–F 仍會全綠（2026-10-20 Codex 反方審查）。
    Write-Output ("§" + $mode + " G 只有 .git 目錄、沒有標記 ⇒ 不帶覆寫，指示根＝.git 那層")
    $dG = Join-Path $root "gitrepo\sub"
    $r = Invoke-Sut $mode $dG
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode G0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode G1 不帶覆寫" ((Get-ElemCount $r.Argv $MARKERS) -eq 0) $ctx
    Check "$mode G2 指示根＝.git 目錄那層" (Test-Has $r.Out ("instructions root: " + (Join-Path $root "gitrepo") + " ;")) $ctx
    Check "$mode G3 argv 與加入前逐元素相同" (Test-ArgvExact $r.Argv (Get-ExpectedArgv $mode $dG $false)) $ctx

    Write-Output ("§" + $mode + " H -Dir／-SchemaFile 含 & ⇒ 逐字到達 argv，cmd 沒有斷句")
    $r = Invoke-Sut $mode $AMP
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode H0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode H1 rc=0" ($r.Code -eq 0) $ctx
    Check "$mode H2 argv 與不含 & 的路徑同形" (Test-ArgvExact $r.Argv (Get-ExpectedArgv $mode $AMP $false)) $ctx
    Check "$mode H3 摘要 cwd" (Test-Has $r.Out ("cwd: " + $AMP + " ;")) $ctx
    $r = Invoke-Sut $mode $AMP -Schema $ampSchema -Answer '{"ok":true}'
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode H4 schema rc=0" ($r.Code -eq 0) $ctx
    Check "$mode H5 --output-schema 逐字到達" ((Get-PairCount $r.Argv '--output-schema' $ampSchema) -eq 1) $ctx
    $r = Invoke-Sut $mode "unused" $AMP -UsePwd
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode H6 PWD.ProviderPath rc=0" ($r.Code -eq 0) $ctx
    Check "$mode H7 PWD.ProviderPath 到達 -C" ((Get-PairCount $r.Argv '-C' $AMP) -eq 1) $ctx

    Write-Output ("§" + $mode + " I 磁碟根 ⇒ 結尾 \ 不吃掉收尾引號，後面的參數不併進路徑")
    $dI = [System.IO.Path]::GetPathRoot($root)
    $r = Invoke-Sut $mode $dI
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode I0 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " " + $ctx)
    Check "$mode I1 rc=0" ($r.Code -eq 0) $ctx
    Check "$mode I2 argv 與一般路徑同形" (Test-ArgvExact $r.Argv (Get-ExpectedArgv $mode $dI $false)) $ctx
    $r = Invoke-Sut $mode $ZW
    $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
    Check "$mode I3 零寬目錄名不被當成結尾 \" (Test-ArgvExact $r.Argv (Get-ExpectedArgv $mode $ZW $false)) $ctx
  }

  # H 的憑證案只有 consult 有：cwd、-C、憑證的 repo 三者要一致，hook 才比對得上後續動作。
  Write-Output "§consult H 鑄證模式 ⇒ 憑證的 repo 是含 & 的絕對路徑"
  $r = Invoke-Sut consult "unused" $AMP -UsePwd -Credential -Answer ('ALLOW: stub ' + ('x' * 60))
  $ctx = "rc=" + $r.Code + " argv=" + (Format-Argv $r.Argv) + " out=" + $r.Out + " err=" + $r.Err
  Check "consult H8 鑄證 rc=0、-C＝cwd" (($r.Code -eq 0) -and ((Get-PairCount $r.Argv '-C' $AMP) -eq 1)) $ctx
  $credText = Read-Text (Join-Path $fakeHome ".claude\.super-mode-consult-ok")
  $credRepo = $(if ($credText) { (ConvertFrom-Json -InputObject $credText).repo } else { '' })
  Check "consult H9 credential.repo＝cwd" ($credRepo -ceq $AMP) ("repo=" + $credRepo + " " + $ctx)

  # 案數守衛：只證明「沒少跑案」，不證明案子有牙齒（牙齒見檔頭 -ExecSut／-ConsultSut 用法）。
  # §0 3 + 每個 mode (A 9 + B 7 + C 4 + D 3 + E 5 + F 6 + G 4 + H 8 + I 4 = 50) × 2 + consult 鑄證 2；全綠時摘要為 pass=106（含本守衛）
  $expected = 105
  $ran = $script:pass + $script:fail
  Check "案數守衛：實跑 $expected 案" ($ran -eq $expected) ("實跑=" + $ran + " 期望=" + $expected)
}
catch {
  if ("$($_.Exception.Message)" -ne 'isolation-failed') {
    $script:fail++
    $script:failed += "runner 例外"
    Write-Output ("  FAIL  runner 丟出例外：" + $_.Exception.Message)
  }
}
finally {
  foreach ($v in @('SUPER_MODE_CODEX_CMD', 'SUPER_MODE_CODEX_CMD_EXEC', 'PRM_NODE', 'PRM_DUMP_JS', 'PRM_MODE',
      'PRM_TARGET', 'PRM_DIR', 'PRM_BRIEF', 'PRM_SCHEMA', 'PRM_USE_PWD', 'PRM_CRED', 'FAKE_ARGV', 'FAKE_TRACE', 'FAKE_ANSWER')) {
    Remove-Item -LiteralPath ("Env:" + $v) -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("project-root-marker [" + $Shell + "]: pass=" + $script:pass + " fail=" + $script:fail)
if ($script:fail -gt 0) {
  Write-Output ("failed: " + ($script:failed -join ', '))
  exit 1
}
exit 0
