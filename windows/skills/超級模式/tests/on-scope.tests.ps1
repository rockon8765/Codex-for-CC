# on-scope.tests.ps1 -- Windows：super-mode.ps1 -On 的寫入端回歸（2026-11-01）。
#
# 守的規則：
#   - -On -Scope <存在的磁碟機目錄> ⇒ 旗標第一行是該路徑，hook 的 decide() 認得：scope 內擋、scope 外放行。
#   - -On 不帶 -Scope ⇒ 全域強制（旗標空白、scope 外也擋）。
#   - 帶了 -Scope 但值是空字串、空白、檔案、不存在、UNC、非 FileSystem provider、session 專屬的 PSDrive，
#     或路徑段以點／空白結尾
#     ⇒ rc≠0、不留旗標；已有的旗標不被改掉。hook 的 readScope 只認路徑形狀的值，其他值都會靜默變成全域。
#
# ⚠️ 兩個 host 各跑一次：pwsh 寫的旗標沒有 BOM，WinPS 5.1 有。decide() 兩種都要認得。
# ⚠️ scope 用 %SystemRoot%：要是暫存區以外的路徑，否則會吃到 hook 的暫存豁免；本測試只讀不寫。
# ⚠️ UNC 案靠 \\localhost\c$，機器沒開管理分享時 Test-Path 會是 false：一樣要拒收，只是拒收理由不同，
#    所以「訊息指向省略 -Scope」只在路徑真的存在時才斷言。
#
# 用法：pwsh -NoProfile -File on-scope.tests.ps1 [-Shell pwsh|powershell] [-Sut <super-mode.ps1>]
#   -Sut 只給牙齒檢查用（對舊版跑，應該要紅）；正式驗收不要帶。
# ⚠️ 隔離：受測腳本一律在子行程跑，USERPROFILE 指向暫存家目錄；§0 先驗 child 看到的家目錄，
#    對不上就整支中止，一個 -On 都不跑（-On 會寫旗標，寫到真的家目錄會擋住所有 session）。

param(
  [ValidateSet('pwsh', 'powershell')]
  [string]$Shell = $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }),
  [string]$Sut = ''
)

$ErrorActionPreference = 'Stop'
$script:pass = 0
$script:fail = 0
$script:failed = @()
$CHILD_TIMEOUT_MS = 60000

function Read-Text([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return "" }
  return [System.IO.File]::ReadAllText($path)
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

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Sut) { $Sut = Join-Path $here "..\scripts\super-mode.ps1" }
if (-not (Test-Path -LiteralPath $Sut)) { Write-Output "找不到受測腳本：$Sut"; exit 2 }
$Sut = (Resolve-Path -LiteralPath $Sut).Path
# repo 與 live 的相對位置相同：windows\hooks 對 windows\skills\超級模式\tests、~\.claude\hooks 對 ~\.claude\skills\超級模式\tests。
$hook = Join-Path $here "..\..\..\hooks\super-mode-consult-gate.js"
if (-not (Test-Path -LiteralPath $hook)) { Write-Output "找不到 hook：$hook"; exit 2 }
$hook = (Resolve-Path -LiteralPath $hook).Path
$nodeCmd = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $nodeCmd) { Write-Output "PREREQ-MISSING: PATH 上沒有 node（decide() 需要）。這是 hard fail，不是 skip。"; exit 3 }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("onscope-" + (New-Id))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$fakeHome = Join-Path $root "home"
$claude = Join-Path $fakeHome ".claude"
New-Item -ItemType Directory -Path $claude -Force | Out-Null
$flag = Join-Path $claude ".super-mode-active"
$aFile = Join-Path $root "a-file.txt"; Write-Utf8 $aFile "x"

# 參數走環境變數（Start-Process -ArgumentList 傳不了空字串）。⚠️ 必須 UTF-8 **with BOM**：WinPS 5.1 讀無 BOM 的 .ps1 用 ANSI 解碼。
$wrapper = Join-Path $root "wrapper.ps1"
[System.IO.File]::WriteAllText($wrapper, @'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}   # 3h 比對中文訊息，不受 console code page 影響
if ($env:OS_DRIVE_ROOT) { $null = New-PSDrive -Name $env:OS_DRIVE_NAME -PSProvider $env:OS_DRIVE_PROV -Root $env:OS_DRIVE_ROOT }
if ($env:OS_MODE -eq 'status') { & $env:OS_TARGET }
elseif ($env:OS_MODE -eq 'noscope') { & $env:OS_TARGET -On }
elseif ($env:OS_MODE -eq 'empty') { & $env:OS_TARGET -On -Scope '' }
else { & $env:OS_TARGET -On -Scope $env:OS_SCOPE }
exit $LASTEXITCODE
'@, (New-Object System.Text.UTF8Encoding $true))
$probe = Join-Path $root "probe.ps1"
[System.IO.File]::WriteAllText($probe, '$PSVersionTable.PSVersion.ToString(); $env:USERPROFILE', (New-Object System.Text.UTF8Encoding $true))

$decideJs = Join-Path $root "decide.js"
Write-Utf8 $decideJs @'
const { decide } = require(process.argv[2]);
// projectDir 要明寫：不給的話 hook 會讀 CLAUDE_PROJECT_DIR，1f 就受跑測試的環境影響。
const r = decide({ tool_name: "Bash", tool_input: { command: "git stash" }, cwd: process.argv[4] }, { baseDir: process.argv[3], projectDir: "" });
process.stdout.write(r.allow ? "allow" : "deny");
'@
function Get-Decision([string]$cwd) { return (& $nodeCmd.Source $decideJs $hook $claude $cwd) }

function Start-Child([string]$argString) {
  $o = Join-Path $root ("o-" + (New-Id) + ".txt")
  $e = Join-Path $root ("e-" + (New-Id) + ".txt")
  $oldHome = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  try {
    $pr = Start-Process -FilePath $Shell -ArgumentList $argString -NoNewWindow -PassThru `
      -RedirectStandardOutput $o -RedirectStandardError $e
    $null = $pr.Handle   # 先取 handle，ExitCode 才可靠（WaitForExit(int) 的已知坑）
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
function Invoke-Sut([string]$Mode, [string]$Scope = '', [string]$DriveRoot = '', [string]$DriveName = 'OnScopeDrv', [string]$DriveProv = 'FileSystem') {
  $env:OS_TARGET = $Sut; $env:OS_MODE = $Mode; $env:OS_SCOPE = $Scope
  $env:OS_DRIVE_ROOT = $DriveRoot; $env:OS_DRIVE_NAME = $DriveName; $env:OS_DRIVE_PROV = $DriveProv
  return (Start-Child ('-NoProfile -File "' + $wrapper + '"'))
}
function Clear-Flag { Remove-Item -LiteralPath $flag -Force -ErrorAction SilentlyContinue }
function Get-FlagFirstLine {
  if (-not (Test-Path -LiteralPath $flag)) { return $null }
  $t = (Read-Text $flag).TrimStart([char]0xFEFF)
  return (($t -split "`r?`n")[0])
}
# 拒收案：恰好 rc=1（不用 rc≠0：逾時哨兵 -999 也會算過）、不留旗標。
function Test-Rejected([string]$tag, $r) {
  $ctx = "rc=" + $r.Code + " out=" + $r.Out + " err=" + $r.Err
  Check "$tag rc=1" ($r.Code -eq 1) $ctx
  Check "$tag 不留旗標" (-not (Test-Path -LiteralPath $flag)) ("flag=" + (Read-Text $flag) + " " + $ctx)
  Check "$tag 不印 ON" ($r.Out -notmatch 'super mode: ON') $ctx
}

try {
  # ═══ §0 attestation ════════════════════════════════════════════════════════
  $p0 = Start-Child ('-NoProfile -File "' + $probe + '"')
  $lines = @(($p0.Out -split "`r?`n") | Where-Object { $_ })
  $childVer = if ($lines.Count -ge 1) { $lines[0] } else { "" }
  $childHome = if ($lines.Count -ge 2) { $lines[1] } else { "" }
  Write-Output ("§0 runner host = " + $PSVersionTable.PSVersion + " / child host = " + $Shell + " (自報 " + $childVer + ")")
  Write-Output ("   SUT = " + $Sut)
  Write-Output ("   hook = " + $hook)
  if ($Shell -eq 'powershell') { Check "0a -Shell powershell 必須真的是 5.x" ($childVer -like '5.*') "child 自報 $childVer" }
  else { Check "0a -Shell pwsh 必須真的是 7+" ($(try { ([version]$childVer).Major -ge 7 } catch { $false })) "child 自報 $childVer" }
  $homeOk = ($childHome -eq $fakeHome)
  Check "0b child 看到的 USERPROFILE 是暫存家目錄" $homeOk ("child=" + $childHome + " 期望=" + $fakeHome)
  if (-not $homeOk) {
    Write-Output "ABORT  USERPROFILE 隔離沒生效，為了不碰真的 ~/.claude，以下案例一律不跑。"
    throw "isolation-failed"
  }

  $scopeDir = $env:SystemRoot
  $inside = Join-Path $scopeDir "System32"
  $outside = "C:\on-scope-outside"

  Write-Output "§1 -On -Scope <目錄> ⇒ 旗標、status 與 decide() 一致"
  Clear-Flag
  $r = Invoke-Sut 'scope' $scopeDir
  $ctx = "rc=" + $r.Code + " out=" + $r.Out + " err=" + $r.Err
  Check "1a rc=0" ($r.Code -eq 0) $ctx
  Check "1b 旗標第一行＝scope" ((Get-FlagFirstLine) -ceq $scopeDir) ("flag=" + (Read-Text $flag))
  Check "1c 輸出 scope" ($r.Out -match ('scope=' + [regex]::Escape($scopeDir))) $ctx
  $s = Invoke-Sut 'status'
  Check "1d status 與 -On 一致" ($s.Out -match ('scope=' + [regex]::Escape($scopeDir))) ("out=" + $s.Out)
  Check "1e decide：scope 內擋" ((Get-Decision $inside) -eq 'deny') ""
  Check "1f decide：scope 外放行" ((Get-Decision $outside) -eq 'allow') ""

  Write-Output "§2 -On 不帶 -Scope ⇒ 全域強制"
  Clear-Flag
  $r = Invoke-Sut 'noscope'
  Check "2a rc=0" ($r.Code -eq 0) ("rc=" + $r.Code + " err=" + $r.Err)
  Check "2b 輸出 GLOBAL" ($r.Out -match 'scope=GLOBAL') ("out=" + $r.Out)
  Check "2c decide：任何地方都擋" ((Get-Decision $outside) -eq 'deny') ""

  Write-Output "§3 帶了 -Scope 但值不合 ⇒ 拒收、不留旗標"
  Clear-Flag; Test-Rejected "3a 空字串" (Invoke-Sut 'empty')
  Clear-Flag; Test-Rejected "3b 空白" (Invoke-Sut 'scope' '   ')
  Clear-Flag; Test-Rejected "3c 檔案" (Invoke-Sut 'scope' $aFile)
  Clear-Flag; Test-Rejected "3d 不存在" (Invoke-Sut 'scope' (Join-Path $root "no-such-dir"))
  Clear-Flag; Test-Rejected "3e registry provider" (Invoke-Sut 'scope' 'HKCU:\Software')
  Clear-Flag; Test-Rejected "3f 自訂名稱的 PSDrive" (Invoke-Sut 'scope' 'OnScopeDrv:\' $scopeDir)

  # 單字母的 PSDrive 形狀和真磁碟機一樣，但 node 看不到。挑 OS 上沒有的字母，否則 New-PSDrive 會失敗。
  $used = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name })
  $free = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z' | Where-Object { ($used -notcontains $_) -and -not [System.IO.Directory]::Exists($_ + ':\') })
  Clear-Flag; Test-Rejected "3i 單字母 FileSystem PSDrive" (Invoke-Sut 'scope' ($free[0] + ':\') $scopeDir $free[0])
  Clear-Flag; Test-Rejected "3j 單字母 Registry PSDrive" (Invoke-Sut 'scope' ($free[1] + ':\') 'HKCU:\Software' $free[1] 'Registry')
  Clear-Flag; Test-Rejected "3k 段尾的點" (Invoke-Sut 'scope' ($scopeDir + '.'))
  Clear-Flag; Test-Rejected "3l 段尾空白" (Invoke-Sut 'scope' ($scopeDir + '   '))

  $unc = '\\localhost\c$\Windows'
  $uncExists = Test-Path -LiteralPath $unc -PathType Container
  Clear-Flag
  $r = Invoke-Sut 'scope' $unc
  Test-Rejected "3g UNC" $r
  # 去掉空白再比：5.1 的 Write-Error 會依 console 寬度換行，字串可能被切開。
  if ($uncExists) { Check "3h UNC 訊息指向省略 -Scope" (($r.Err -replace '\s', '') -match '省略-Scope') ("err=" + $r.Err) }
  else { Check "3h UNC 不可達（機器沒開管理分享），只驗拒收" $true "" }

  Write-Output "§4 拒收時不改掉既有旗標"
  Clear-Flag
  $null = Invoke-Sut 'scope' $scopeDir
  $before = Read-Text $flag
  $r = Invoke-Sut 'scope' $aFile
  Check "4a rc=1" ($r.Code -eq 1) ("rc=" + $r.Code)
  Check "4b 旗標內容不變" ((Read-Text $flag) -ceq $before) ("flag=" + (Read-Text $flag))

  # 案數守衛：只證明「沒少跑案」，不證明案子有牙齒（牙齒見檔頭 -Sut 用法）。
  # §0 2 + §1 6 + §2 3 + §3 (3×11 + 1) + §4 2 = 47；全綠時摘要為 pass=48（含本守衛）
  $expected = 47
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
  foreach ($v in @('OS_TARGET', 'OS_MODE', 'OS_SCOPE', 'OS_DRIVE_ROOT', 'OS_DRIVE_NAME', 'OS_DRIVE_PROV')) {
    Remove-Item -LiteralPath ("Env:" + $v) -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("on-scope [" + $Shell + "]: pass=" + $script:pass + " fail=" + $script:fail)
if ($script:fail -gt 0) {
  Write-Output ("failed: " + ($script:failed -join ', '))
  exit 1
}
exit 0
