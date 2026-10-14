# off-cleanup.tests.ps1 -- Windows：super-mode.ps1 -Off 的逐字稿清理回歸（backlog OFF-CLEANUP-RECURSIVE）。
#
# 守的規則（與 macos/skills/超級模式/tests/off-cleanup.tests.sh 同一組案例）：
#   - 只刪 super-mode-logs **頂層**、檔名符合 consult／exec 逐字稿格式、且超過 14 天的檔。
#   - 不符檔名的舊檔、子目錄裡的舊檔（即使檔名符合）、近期逐字稿一律保留。
#   - 刪除失敗要在 stderr 回報（OFF_CLEANUP_ERROR），但 -Off 照常完成：
#     旗標與憑證清掉、印 super mode: OFF、exit 0。
#
# 用法：pwsh -NoProfile -File off-cleanup.tests.ps1 [-Shell pwsh|powershell] [-Sut <super-mode.ps1>]
#   -Shell = 受測 child 的 host（預設與 runner 相同）。-Sut 只給牙齒檢查用（對舊版／mutant 跑，
#   應該要紅）；正式驗收不要帶。
#
# ⚠️ 隔離：受測腳本一律在**子行程**跑，USERPROFILE 指向本測試自建的暫存家目錄，絕不碰真的
#    ~/.claude。§0 先讓 child 回報它看到的 USERPROFILE，對不上就整支中止、一個 -Off 都不跑。
# ⚠️ 鎖檔案例用本行程以 FileShare.None 開檔握住（Windows 原生的「檔案被占用」）。
#    不用唯讀屬性：受測腳本帶 -Force，唯讀擋不住刪除，那樣的案子會以錯誤的理由通過。
# ⚠️ 列舉（Get-ChildItem）本身失敗的路徑由 §6 涵蓋：不必改目錄 ACL —— wrapper 在同一行程內先定義
#    同名的 advanced function `Get-ChildItem`（只 Write-Error），再 `& <sut> -Off`，受測腳本的
#    `-ErrorVariable` 就會收到注入的錯誤（2026-10-14 合併前審查以 pwsh 與 powershell.exe 實測可行）。
#    macOS 版用 PATH shim 涵蓋 find 失敗。
# ⚠️ §5（super-mode-logs 是檔案）驗的是**結果**「該檔不會被刪」，不能拿來證明 super-mode.ps1 的
#    `-PathType Container` 檢查有效：檔名 super-mode-logs 本來就不符白名單，真正擋住刪除的是白名單
#    （審查實測：拿掉 -PathType Container 本測試仍全綠）。該檢查保留為縱深防禦。

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

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("offclean-" + (New-Id))
New-Item -ItemType Directory -Path $root -Force | Out-Null

# 呼叫端 preference = Stop 的情境：-File 無法設 preference，只能用 wrapper 在同一行程內 & 受測腳本。
# ⚠️ 必須 UTF-8 **with BOM**：WinPS 5.1 讀無 BOM 的 .ps1 用 ANSI 解碼。
$wrapper = Join-Path $root "wrapper-stop.ps1"
$wrapperSrc = @'
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Stop'
& $env:OC_TARGET -Off
exit 0
'@
[System.IO.File]::WriteAllText($wrapper, $wrapperSrc, (New-Object System.Text.UTF8Encoding $true))

# §6 列舉失敗注入：同 stop-wrapper（呼叫端 preference = Stop、同一行程內 &），另外先定義同名的
# advanced function 遮蔽 Get-ChildItem —— 它只 Write-Error，受測腳本的 -ErrorVariable 會收到這筆錯誤。
$wrapperEnum = Join-Path $root "wrapper-enum.ps1"
$wrapperEnumSrc = @'
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Stop'
function Get-ChildItem {
  [CmdletBinding()]
  param([string]$LiteralPath, [switch]$File)
  Write-Error "INJECTED enumeration failure for $LiteralPath"
}
& $env:OC_TARGET -Off
exit 0
'@
[System.IO.File]::WriteAllText($wrapperEnum, $wrapperEnumSrc, (New-Object System.Text.UTF8Encoding $true))

$probe = Join-Path $root "probe.ps1"
[System.IO.File]::WriteAllText($probe, '$PSVersionTable.PSVersion.ToString(); $env:USERPROFILE',
  (New-Object System.Text.UTF8Encoding $true))

function Start-Child([string]$fakeHome, [string]$argString) {
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

# Mode file  = <Shell> -NoProfile -File <sut> -Off（獨立行程，預設 preference）
# Mode stop  = wrapper 先把 EAP／Warning preference 設成 Stop，再在同一行程內 & <sut> -Off
# Mode enum  = 同 stop，另以同名 function 遮蔽 Get-ChildItem、注入列舉錯誤（§6）
function Invoke-Off([string]$fakeHome, [string]$Mode = 'file') {
  if ($Mode -eq 'stop' -or $Mode -eq 'enum') {
    $w = if ($Mode -eq 'enum') { $wrapperEnum } else { $wrapper }
    $env:OC_TARGET = $Sut
    try { return (Start-Child $fakeHome ('-NoProfile -File "' + $w + '"')) }
    finally { Remove-Item -LiteralPath Env:OC_TARGET -ErrorAction SilentlyContinue }
  }
  return (Start-Child $fakeHome ('-NoProfile -File "' + $Sut + '" -Off'))
}

function New-Home([string]$name) {
  $h = Join-Path $root $name
  $c = Join-Path $h ".claude"
  New-Item -ItemType Directory -Path (Join-Path $c "super-mode-logs") -Force | Out-Null
  Write-Utf8 (Join-Path $c ".super-mode-active") ""
  Write-Utf8 (Join-Path $c ".super-mode-consult-ok") "token"
  return $h
}
function Get-LogDir([string]$h) { Join-Path $h ".claude\super-mode-logs" }
function New-LogFile([string]$path, $mtime) {
  $d = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  Write-Utf8 $path "x"
  if ($null -ne $mtime) { [System.IO.File]::SetLastWriteTime($path, $mtime) }
}
function Test-OffBasics([string]$tag, $r, [string]$h) {
  Check "$tag exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "$tag stdout 印 super mode: OFF" ($r.Out -match '(?m)^super mode: OFF\r?$') ("out=" + $r.Out)
  Check "$tag 旗標已清" (-not (Test-Path -LiteralPath (Join-Path $h ".claude\.super-mode-active"))) "旗標還在"
  Check "$tag 憑證已清" (-not (Test-Path -LiteralPath (Join-Path $h ".claude\.super-mode-consult-ok"))) "憑證還在"
}

$OLD = (Get-Date).AddDays(-30)
# 16 天（不是 15）：與 macOS 版同一組案例。GNU find 的 -mtime 捨去取整，春季跳時後 15 天內，
# 牆鐘「15 天前」實際只過了 14 天 23 小時 ⇒ GNU 上會假紅；16 天兩邊都有 ≥ 1 天餘裕。
$D16 = (Get-Date).AddDays(-16)
$D13 = (Get-Date).AddDays(-13)
$TODAY = Get-Date -Format 'yyyyMMdd'

try {
  # ═══ §0 attestation ════════════════════════════════════════════════════════
  $h0 = New-Home "probe"
  $p = Start-Child $h0 ('-NoProfile -File "' + $probe + '"')
  $lines = @(($p.Out -split "`r?`n") | Where-Object { $_ })
  $childVer = if ($lines.Count -ge 1) { $lines[0] } else { "" }
  $childHome = if ($lines.Count -ge 2) { $lines[1] } else { "" }
  Write-Output ("§0 runner host = " + $PSVersionTable.PSVersion + " / child host = " + $Shell +
    " (自報 " + $childVer + ") / SUT = " + $Sut)
  Check "0a child host 版本可取得" (-not [string]::IsNullOrWhiteSpace($childVer)) ("out=" + $p.Out + " err=" + $p.Err)
  if ($Shell -eq 'powershell') { Check "0b -Shell powershell 必須真的是 5.x" ($childVer -like '5.*') "child 自報 $childVer" }
  else { Check "0b -Shell pwsh 必須真的是 7+" ($(try { ([version]$childVer).Major -ge 7 } catch { $false })) "child 自報 $childVer" }
  $homeOk = ($childHome -eq $h0)
  Check "0c child 看到的 USERPROFILE 是暫存家目錄" $homeOk ("child=" + $childHome + " 期望=" + $h0)
  if (-not $homeOk) {
    # 隔離沒生效就不能跑 -Off：那會清掉真的旗標、憑證與逐字稿。
    Write-Output "ABORT  USERPROFILE 隔離沒生效，為了不碰真的 ~/.claude，以下案例一律不跑。"
    throw "isolation-failed"
  }

  # ═══ §1 主情境：白名單 × 頂層 × 14 天 ══════════════════════════════════════
  Write-Output "§1 主情境"
  $h1 = New-Home "main"
  $l1 = Get-LogDir $h1
  $shouldDelete = @(
    'codex_consult_20200101_000000_abcdef.txt',        # consult（6 位 hex 後綴）
    'codex_exec_20200101_000000_abcdef.txt',           # exec 逐字稿
    'codex_exec_20200101_000000_abcdef_last.txt',      # exec 的 _last.txt
    'codex_consult_20200101_000001_12345.txt',         # macOS consult 的 PID 後綴 fallback
    'codex_consult_20200101_000002.txt',               # 2026-07-02 初版：無後綴
    'codex_exec_20200101_000003_last.txt'              # 初版 exec 的 _last.txt
  )
  foreach ($n in $shouldDelete) { New-LogFile (Join-Path $l1 $n) $OLD }
  New-LogFile (Join-Path $l1 'codex_exec_20200101_000004_abcdef.txt') $D16   # 16 天前 → 刪
  $keepOld = @(
    'notes.txt',
    'acceptance-evidence.json',
    'codex_consult_keep.txt',
    'codex_consult_20200101_000000_abcdef.md',
    'codex_consult_20200101_000000_abcdef.txt.bak',
    'codex_review_20200101_000000_abcdef.txt',
    'xcodex_consult_20200101_000000_abcdef.txt',
    'codex_consult_20200102_000000_ABCDEF.txt',        # 大寫後綴：產品不會產生
    'Codex_Consult_20200103_000000_abcdef.txt',        # 前綴大小寫不同
    'codex_consult_2020010_000000_abcdef.txt',         # 日期只有 7 碼
    'codex_consult_20200101_000000_abcdef_last.txt',   # consult 不產生 _last
    # 2026-10-15 收緊：後綴只認恰好 6 位 hex（consult 另認純數字 PID），短／長後綴都留
    'codex_exec_20200101_000000_cafe.txt',             # exec 4 位 hex
    'codex_exec_20200101_000000_abcdef0.txt',          # exec 7 位 hex
    'codex_exec_20200101_000000_cafe_last.txt',        # exec 4 位 hex 的 _last
    'codex_exec_20200101_000000_12345.txt',            # exec 沒有 PID fallback
    'codex_consult_20200101_000000_abcde.txt',         # consult 5 位 hex（非純數字）
    'codex_consult_20200101_000000_abcdef01.txt'       # consult 8 位 hex（非純數字）
  )
  foreach ($n in $keepOld) { New-LogFile (Join-Path $l1 $n) $OLD }
  $keepSub = @(
    'evidence\codex_consult_20200101_000000_abcdef.txt',
    'evidence\deeper\codex_exec_20200101_000000_abcdef_last.txt',
    'evidence\notes.txt'
  )
  foreach ($n in $keepSub) { New-LogFile (Join-Path $l1 $n) $OLD }
  # 名字像逐字稿的**目錄**：不是檔案 → 不碰
  $dirLike = Join-Path $l1 'codex_consult_20200104_000000_abcdef.txt'
  New-LogFile (Join-Path $dirLike 'inner.txt') $OLD
  [System.IO.Directory]::SetLastWriteTime($dirLike, $OLD)
  $keepRecent = @("codex_consult_${TODAY}_000000_abcdef.txt", "codex_exec_${TODAY}_000000_abcdef_last.txt")
  foreach ($n in $keepRecent) { New-LogFile (Join-Path $l1 $n) $null }
  New-LogFile (Join-Path $l1 'codex_exec_20200101_000005_abcdef.txt') $D13   # 13 天前 → 留

  $r = Invoke-Off $h1
  Test-OffBasics "1" $r $h1
  Check "1 乾淨情境 stderr 不得有 OFF_CLEANUP_ERROR" (-not ($r.Err -match 'OFF_CLEANUP_ERROR')) ("err=" + $r.Err)
  foreach ($n in ($shouldDelete + @('codex_exec_20200101_000004_abcdef.txt'))) {
    Check "1 刪：$n" (-not (Test-Path -LiteralPath (Join-Path $l1 $n))) "超過 14 天的逐字稿沒被刪"
  }
  foreach ($n in $keepOld) {
    Check "1 留（檔名不符）：$n" (Test-Path -LiteralPath (Join-Path $l1 $n)) "不在白名單的檔被刪了"
  }
  foreach ($n in $keepSub) {
    Check "1 留（子目錄）：$n" (Test-Path -LiteralPath (Join-Path $l1 $n)) "子目錄被遞迴清理了"
  }
  Check "1 留（目錄）：像逐字稿的目錄本身" (Test-Path -LiteralPath $dirLike -PathType Container) "目錄被刪了"
  Check "1 留（目錄）：該目錄內的檔" (Test-Path -LiteralPath (Join-Path $dirLike 'inner.txt')) "目錄內的檔被刪了"
  foreach ($n in ($keepRecent + @('codex_exec_20200101_000005_abcdef.txt'))) {
    Check "1 留（未滿 14 天）：$n" (Test-Path -LiteralPath (Join-Path $l1 $n)) "近期逐字稿被刪了"
  }

  # ═══ §2／§3 刪除失敗：回報但不讓 -Off 失敗 ══════════════════════════════════
  foreach ($mode in @('file', 'stop')) {
    $sec = if ($mode -eq 'file') { "2" } else { "3" }
    Write-Output ("§$sec 鎖住的逐字稿（" + $(if ($mode -eq 'file') { "-File" } else { "呼叫端 EAP／Warning=Stop、同行程 &" }) + "）")
    $h = New-Home ("locked-" + $mode)
    $l = Get-LogDir $h
    $lockedName = 'codex_consult_20200101_000000_aaaaaa.txt'
    $otherName = 'codex_exec_20200101_000000_bbbbbb.txt'
    New-LogFile (Join-Path $l $lockedName) $OLD
    New-LogFile (Join-Path $l $otherName) $OLD
    $fs = [System.IO.File]::Open((Join-Path $l $lockedName), [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
    try { $r = Invoke-Off $h $mode }
    finally { $fs.Dispose() }
    Test-OffBasics $sec $r $h
    Check "$sec 鎖住的檔仍在（刪除確實失敗過）" (Test-Path -LiteralPath (Join-Path $l $lockedName)) "鎖沒有生效，本案沒刺激到失敗路徑"
    Check "$sec 其他舊逐字稿照清（不因單一失敗放棄）" (-not (Test-Path -LiteralPath (Join-Path $l $otherName))) "其餘檔沒被清"
    Check "$sec stderr 有 OFF_CLEANUP_ERROR" ($r.Err -match 'OFF_CLEANUP_ERROR') ("err=" + $r.Err)
    # §3 也要驗：只靠 §2 的話，「呼叫端 preference=Stop 時逐檔錯誤改走 stdout」的 mutant 抓不到（審查實測）。
    Check "$sec stderr 指名失敗的檔" ($r.Err -match [regex]::Escape($lockedName)) ("err=" + $r.Err)
  }

  # ═══ §4 沒有 logdir ══════════════════════════════════════════════════════
  Write-Output "§4 沒有 super-mode-logs"
  $h4 = New-Home "nolog"
  Remove-Item -LiteralPath (Get-LogDir $h4) -Recurse -Force
  $r = Invoke-Off $h4
  Test-OffBasics "4" $r $h4
  Check "4 stderr 不得有 OFF_CLEANUP_ERROR" (-not ($r.Err -match 'OFF_CLEANUP_ERROR')) ("err=" + $r.Err)

  # ═══ §5 super-mode-logs 是檔案不是目錄 ═══════════════════════════════════
  # 驗的是結果（該檔不被刪），不證明 -PathType Container 有效：擋住刪除的是白名單（見檔頭）。
  Write-Output "§5 super-mode-logs 是檔案"
  $h5 = New-Home "logfile"
  $l5 = Get-LogDir $h5
  Remove-Item -LiteralPath $l5 -Recurse -Force
  New-LogFile $l5 $OLD
  $r = Invoke-Off $h5
  Test-OffBasics "5" $r $h5
  Check "5 該檔不得被刪" (Test-Path -LiteralPath $l5 -PathType Leaf) "super-mode-logs 檔案被刪了"

  # ═══ §6 列舉失敗（遮蔽 Get-ChildItem 注入錯誤）════════════════════════════
  Write-Output "§6 列舉失敗（呼叫端 EAP／Warning=Stop、同行程 &、Get-ChildItem 被遮蔽）"
  $h6 = New-Home "enumfail"
  $l6 = Get-LogDir $h6
  $enumOld = 'codex_consult_20200101_000000_cccccc.txt'
  New-LogFile (Join-Path $l6 $enumOld) $OLD
  $r = Invoke-Off $h6 'enum'
  Test-OffBasics "6" $r $h6
  Check "6 stderr 有 OFF_CLEANUP_ERROR" ($r.Err -match 'OFF_CLEANUP_ERROR') ("err=" + $r.Err)
  Check "6 stderr 帶出注入的列舉錯誤" ($r.Err -match 'INJECTED enumeration failure') ("err=" + $r.Err)
  Check "6 列舉失敗時不得誤刪" (Test-Path -LiteralPath (Join-Path $l6 $enumOld)) "列舉失敗卻刪了檔（注入沒生效，或受測腳本繞過了 Get-ChildItem）"

  # 案數守衛：只證明「沒少跑案」，不證明案子有牙齒（牙齒見檔頭 -Sut 用法）。
  # §0 3 + §1 (4+1+7+17+3+2+3=37) + §2 (4+4=8) + §3 (4+4=8) + §4 (4+1=5) + §5 (4+1=5) + §6 (4+3=7)
  $expected = 73
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
  Remove-Item -LiteralPath Env:OC_TARGET -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("off-cleanup [" + $Shell + "]: pass=" + $script:pass + " fail=" + $script:fail)
if ($script:fail -gt 0) {
  Write-Output ("failed: " + ($script:failed -join ', '))
  exit 1
}
exit 0
