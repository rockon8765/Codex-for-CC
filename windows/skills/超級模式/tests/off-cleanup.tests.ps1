# off-cleanup.tests.ps1 -- Windows：super-mode.ps1 -Off 的逐字稿清理回歸（backlog OFF-CLEANUP-RECURSIVE）。
#
# 守的規則（與 macos/skills/超級模式/tests/off-cleanup.tests.sh 同一組案例）：
#   - 只刪 super-mode-logs **頂層**、檔名符合 consult／exec 逐字稿格式、且超過 14 天的檔。
#   - 不符檔名的舊檔、子目錄裡的舊檔（即使檔名符合）、近期逐字稿一律保留。
#   - 刪除失敗要在 stderr 回報（OFF_CLEANUP_ERROR），但 -Off 照常完成：
#     旗標與憑證清掉、印 super mode: OFF、exit 0。
#   - -Cleanup（§7–§14，2026-11-18）：同一組條件，但只清逐字稿——旗標與憑證不動；-DryRun 只報
#     檔數與位元組數；刪除／列舉失敗回 exit 1，stderr 前綴是 CLEANUP_ERROR；參數組合不合法回 exit 2。
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

# -Cleanup 用的兩個 wrapper（§10／§11／§12）：同 stop／enum，但要把受測腳本的退出碼傳出來
# （-Cleanup 清理失敗是 exit 1；-Off 的 wrapper 固定 exit 0，不能共用）。受測腳本沒呼叫 exit 時
# $LASTEXITCODE 是 $null，視為 0。OC_DRY=1 ⇒ 加 -DryRun。OC_PRESET=1 ⇒ 先把 $LASTEXITCODE 設成 7，
# 模擬呼叫端上一個指令失敗（§15：-Cleanup 成功時要自己 exit 0，不能讓呼叫端讀到殘留值）。
$cleanupCallSrc = @'
if ($env:OC_PRESET -eq '1') { $global:LASTEXITCODE = 7 }
if ($env:OC_DRY -eq '1') { & $env:OC_TARGET -Cleanup -DryRun } else { & $env:OC_TARGET -Cleanup }
$rc = 0
if ($null -ne $LASTEXITCODE) { $rc = $LASTEXITCODE }
exit $rc
'@
# §16：-Off -DryRun:$false。5.1 的 -File 不接受 `-Switch:$false` 這種寫法，只能在行程內用 & 呼叫。
$wrapperOffDry = Join-Path $root "wrapper-off-dryfalse.ps1"
$wrapperOffDrySrc = @'
& $env:OC_TARGET -Off -DryRun:$false
$rc = 0
if ($null -ne $LASTEXITCODE) { $rc = $LASTEXITCODE }
exit $rc
'@
[System.IO.File]::WriteAllText($wrapperOffDry, $wrapperOffDrySrc, (New-Object System.Text.UTF8Encoding $true))
$wrapperCleanup = Join-Path $root "wrapper-cleanup-stop.ps1"
$wrapperCleanupSrc = @'
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Stop'

'@ + $cleanupCallSrc
[System.IO.File]::WriteAllText($wrapperCleanup, $wrapperCleanupSrc, (New-Object System.Text.UTF8Encoding $true))
$wrapperCleanupEnum = Join-Path $root "wrapper-cleanup-enum.ps1"
$wrapperCleanupEnumSrc = @'
$ErrorActionPreference = 'Stop'
$WarningPreference = 'Stop'
function Get-ChildItem {
  [CmdletBinding()]
  param([string]$LiteralPath, [switch]$File)
  Write-Error "INJECTED enumeration failure for $LiteralPath"
}

'@ + $cleanupCallSrc
[System.IO.File]::WriteAllText($wrapperCleanupEnum, $wrapperCleanupEnumSrc, (New-Object System.Text.UTF8Encoding $true))

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

# -Cleanup [-DryRun]。Mode 同 Invoke-Off：file＝獨立行程；stop／enum＝wrapper 內同行程 &。
function Invoke-Cleanup([string]$fakeHome, [switch]$DryRun, [string]$Mode = 'file', [switch]$PresetExit) {
  if ($Mode -eq 'stop' -or $Mode -eq 'enum') {
    $w = if ($Mode -eq 'enum') { $wrapperCleanupEnum } else { $wrapperCleanup }
    $env:OC_TARGET = $Sut
    $env:OC_DRY = $(if ($DryRun) { '1' } else { '0' })
    $env:OC_PRESET = $(if ($PresetExit) { '1' } else { '0' })
    try { return (Start-Child $fakeHome ('-NoProfile -File "' + $w + '"')) }
    finally {
      Remove-Item -LiteralPath Env:OC_TARGET -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath Env:OC_DRY -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath Env:OC_PRESET -ErrorAction SilentlyContinue
    }
  }
  return (Start-Child $fakeHome ('-NoProfile -File "' + $Sut + '" -Cleanup' + $(if ($DryRun) { ' -DryRun' } else { '' })))
}
# 參數檢查用：引數字串原樣接在 -File <sut> 後面。
function Invoke-Raw([string]$fakeHome, [string]$sutArgs) {
  return (Start-Child $fakeHome ('-NoProfile -File "' + $Sut + '" ' + $sutArgs))
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
# -Cleanup 不得動旗標與憑證，也不是 -Off。New-Home 寫的旗標是空檔、憑證內容是 token。
function Test-StateKept([string]$tag, $r, [string]$h) {
  $f = Join-Path $h ".claude\.super-mode-active"
  Check "$tag 旗標仍在且內容不變" ((Test-Path -LiteralPath $f) -and ((Read-Text $f) -ceq "")) ("flag=" + (Read-Text $f))
  Check "$tag 憑證仍在且內容不變" ((Read-Text (Join-Path $h ".claude\.super-mode-consult-ok")) -ceq "token") "憑證被動了"
  Check "$tag stdout 不得印 super mode: OFF" ($r.Out -notmatch 'super mode: OFF') ("out=" + $r.Out)
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

  # ═══ §7–§14 -Cleanup（2026-11-18）═════════════════════════════════════════
  # 與 -Off 同一組條件（頂層 × 白名單 × 14 天），但只清逐字稿：旗標與憑證不動，部分失敗回 exit 1。
  # ⚠️ stdout／stderr 的斷言只比 ASCII 片段：5.1 child 的重導向輸出走 console code page，中文不可靠。
  Write-Output "§7 -Cleanup -DryRun：只報檔數與位元組數，不刪"
  $h7 = New-Home "cleanup"
  $l7 = Get-LogDir $h7
  # 3 個該清的（1＋1＋1000＝1002 bytes）＋ 4 個該留的
  $cleanDel = @(
    'codex_consult_20200101_000000_abcdef.txt',
    'codex_exec_20200101_000000_abcdef_last.txt',
    'codex_exec_20200101_000001_abcdef.txt'
  )
  $cleanKeep = @(
    'notes.txt',                                           # 檔名不符
    'codex_exec_20200101_000000_cafe.txt',                 # 後綴長度不符
    'evidence\codex_consult_20200101_000000_abcdef.txt',   # 子目錄
    'codex_exec_20200101_000005_abcdef.txt'                # 未滿 14 天
  )
  New-LogFile (Join-Path $l7 $cleanDel[0]) $OLD
  New-LogFile (Join-Path $l7 $cleanDel[1]) $D16
  Write-Utf8 (Join-Path $l7 $cleanDel[2]) ("y" * 1000)
  [System.IO.File]::SetLastWriteTime((Join-Path $l7 $cleanDel[2]), $OLD)
  New-LogFile (Join-Path $l7 $cleanKeep[0]) $OLD
  New-LogFile (Join-Path $l7 $cleanKeep[1]) $OLD
  New-LogFile (Join-Path $l7 $cleanKeep[2]) $OLD
  New-LogFile (Join-Path $l7 $cleanKeep[3]) $D13

  $r = Invoke-Cleanup $h7 -DryRun
  Check "7 exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "7 stdout 報 matched=3 bytes=1002" ($r.Out -match 'matched=3 bytes=1002 ') ("out=" + $r.Out)
  Check "7 stdout 標明 dry-run" ($r.Out -match '\(dry-run\)') ("out=" + $r.Out)
  Check "7 stderr 不得有 CLEANUP_ERROR" (-not ($r.Err -match 'CLEANUP_ERROR')) ("err=" + $r.Err)
  foreach ($n in ($cleanDel + $cleanKeep)) {
    Check "7 預覽不刪：$n" (Test-Path -LiteralPath (Join-Path $l7 $n)) "-DryRun 卻刪了檔"
  }
  Test-StateKept "7" $r $h7

  Write-Output "§8 -Cleanup：真的刪，範圍與 -Off 相同"
  $r = Invoke-Cleanup $h7
  Check "8 exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "8 stdout 報 deleted=3 bytes=1002 failed=0" ($r.Out -match 'deleted=3 bytes=1002 failed=0') ("out=" + $r.Out)
  Check "8 stderr 不得有 CLEANUP_ERROR" (-not ($r.Err -match 'CLEANUP_ERROR')) ("err=" + $r.Err)
  foreach ($n in $cleanDel) {
    Check "8 刪：$n" (-not (Test-Path -LiteralPath (Join-Path $l7 $n))) "超過 14 天的逐字稿沒被刪"
  }
  foreach ($n in $cleanKeep) {
    Check "8 留：$n" (Test-Path -LiteralPath (Join-Path $l7 $n)) "不該清的檔被刪了"
  }
  Test-StateKept "8" $r $h7

  # §9／§10 刪除失敗：-Cleanup 要回非零（-Off 的 §2／§3 是 exit 0）
  foreach ($mode in @('file', 'stop')) {
    $sec = if ($mode -eq 'file') { "9" } else { "10" }
    Write-Output ("§$sec -Cleanup 遇到鎖住的逐字稿（" + $(if ($mode -eq 'file') { "-File" } else { "呼叫端 EAP／Warning=Stop、同行程 &" }) + "）")
    $h = New-Home ("cleanup-locked-" + $mode)
    $l = Get-LogDir $h
    $lockedName = 'codex_consult_20200101_000000_aaaaaa.txt'
    $otherName = 'codex_exec_20200101_000000_bbbbbb.txt'
    New-LogFile (Join-Path $l $lockedName) $OLD
    New-LogFile (Join-Path $l $otherName) $OLD
    $fs = [System.IO.File]::Open((Join-Path $l $lockedName), [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
    try { $r = Invoke-Cleanup $h -Mode $mode }
    finally { $fs.Dispose() }
    Check "$sec exit 1（部分失敗要回非零）" ($r.Code -eq 1) ("exit=" + $r.Code + " err=" + $r.Err)
    Check "$sec 鎖住的檔仍在（刪除確實失敗過）" (Test-Path -LiteralPath (Join-Path $l $lockedName)) "鎖沒有生效，本案沒刺激到失敗路徑"
    Check "$sec 其他舊逐字稿照清（不因單一失敗放棄）" (-not (Test-Path -LiteralPath (Join-Path $l $otherName))) "其餘檔沒被清"
    Check "$sec stderr 有 CLEANUP_ERROR（行首）" ($r.Err -match '(?m)^CLEANUP_ERROR: ') ("err=" + $r.Err)
    Check "$sec stderr 指名失敗的檔" ($r.Err -match [regex]::Escape($lockedName)) ("err=" + $r.Err)
    Check "$sec stderr 不得用 -Off 的前綴（那一行宣稱旗標與憑證已清除）" (-not ($r.Err -match 'OFF_CLEANUP_ERROR')) ("err=" + $r.Err)
    Check "$sec stdout 報 deleted=1 bytes=1 failed=1" ($r.Out -match 'deleted=1 bytes=1 failed=1') ("out=" + $r.Out)
    Test-StateKept $sec $r $h
  }

  Write-Output "§11 -Cleanup 列舉失敗（Get-ChildItem 被遮蔽）→ exit 1"
  $h11 = New-Home "cleanup-enumfail"
  $l11 = Get-LogDir $h11
  $enumOld11 = 'codex_consult_20200101_000000_dddddd.txt'
  New-LogFile (Join-Path $l11 $enumOld11) $OLD
  $r = Invoke-Cleanup $h11 -Mode 'enum'
  Check "11 exit 1" ($r.Code -eq 1) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "11 stderr 有 CLEANUP_ERROR（行首）" ($r.Err -match '(?m)^CLEANUP_ERROR: ') ("err=" + $r.Err)
  Check "11 stderr 帶出注入的列舉錯誤" ($r.Err -match 'INJECTED enumeration failure') ("err=" + $r.Err)
  Check "11 stderr 不得用 -Off 的前綴" (-not ($r.Err -match 'OFF_CLEANUP_ERROR')) ("err=" + $r.Err)
  Check "11 列舉失敗時不得誤刪" (Test-Path -LiteralPath (Join-Path $l11 $enumOld11)) "列舉失敗卻刪了檔"
  Test-StateKept "11" $r $h11

  Write-Output "§12 -Cleanup -DryRun 列舉失敗 → exit 1（數字不可信）"
  $r = Invoke-Cleanup $h11 -DryRun -Mode 'enum'
  Check "12 exit 1" ($r.Code -eq 1) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "12 stderr 有 CLEANUP_ERROR（行首）" ($r.Err -match '(?m)^CLEANUP_ERROR: ') ("err=" + $r.Err)
  Check "12 檔案仍在" (Test-Path -LiteralPath (Join-Path $l11 $enumOld11)) "-DryRun 卻刪了檔"

  Write-Output "§13 -Cleanup：沒有 super-mode-logs"
  $h13 = New-Home "cleanup-nolog"
  Remove-Item -LiteralPath (Get-LogDir $h13) -Recurse -Force
  $r = Invoke-Cleanup $h13
  Check "13 exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "13 stdout 報 deleted=0 bytes=0 failed=0" ($r.Out -match 'deleted=0 bytes=0 failed=0') ("out=" + $r.Out)
  Check "13 stderr 不得有 CLEANUP_ERROR" (-not ($r.Err -match 'CLEANUP_ERROR')) ("err=" + $r.Err)
  Test-StateKept "13" $r $h13

  Write-Output "§14 -Cleanup 的參數組合不合法 ⇒ exit 2、不刪逐字稿、不動旗標與憑證"
  $argSpecs = @(
    '-Cleanup -Off',                    # 不得照做 -Off
    '-Cleanup -On',                     # 不得照做 -On
    '-DryRun',                          # -DryRun 沒搭配 -Cleanup
    '-Off -DryRun',                     # 不得照做 -Off
    '-Cleanup stray',                   # 單一多餘引數依位置綁到 -Scope
    '-Cleanup -DryRun stray1 stray2'    # 第二個多餘引數落在 $args
  )
  $i = 0
  foreach ($spec in $argSpecs) {
    $i++
    $h = New-Home ("cleanup-args-" + $i)
    $oldLog = Join-Path (Get-LogDir $h) 'codex_consult_20200101_000000_eeeeee.txt'
    New-LogFile $oldLog $OLD
    $r = Invoke-Raw $h $spec
    $ctx = "exit=" + $r.Code + " out=" + $r.Out + " err=" + $r.Err
    Check "14.$i exit 2 [$spec]" ($r.Code -eq 2) $ctx
    Check "14.$i 舊逐字稿仍在 [$spec]" (Test-Path -LiteralPath $oldLog) $ctx
    Check "14.$i stdout 不得印清理結果 [$spec]" ($r.Out -notmatch 'transcript cleanup') $ctx
    Test-StateKept "14.$i [$spec]" $r $h
  }
  Check "14 usage 列出 -Cleanup [-DryRun]" ($r.Err -match '\[-Cleanup \[-DryRun\]\]') ("err=" + $r.Err)

  Write-Output '§15 -Cleanup 成功時明確 exit 0（同行程 & 呼叫，呼叫端原本的 $LASTEXITCODE 是 7）'
  $h15 = New-Home "cleanup-preset"
  New-LogFile (Join-Path (Get-LogDir $h15) 'codex_exec_20200101_000000_ffffff.txt') $OLD
  $r = Invoke-Cleanup $h15 -Mode 'stop' -PresetExit
  Check "15 exit 0（不得沿用呼叫端殘留的 7）" ($r.Code -eq 0) ("exit=" + $r.Code + " out=" + $r.Out + " err=" + $r.Err)
  Check "15 stdout 報 deleted=1 bytes=1 failed=0" ($r.Out -match 'deleted=1 bytes=1 failed=0') ("out=" + $r.Out)

  Write-Output '§16 -Off -DryRun:$false ⇒ exit 2，不得照做 -Off（看有沒有帶 -DryRun，不看值）'
  $h16 = New-Home "off-dryfalse"
  $oldLog16 = Join-Path (Get-LogDir $h16) 'codex_consult_20200101_000000_eeeeee.txt'
  New-LogFile $oldLog16 $OLD
  $env:OC_TARGET = $Sut
  try { $r = Start-Child $h16 ('-NoProfile -File "' + $wrapperOffDry + '"') }
  finally { Remove-Item -LiteralPath Env:OC_TARGET -ErrorAction SilentlyContinue }
  $ctx = "exit=" + $r.Code + " out=" + $r.Out + " err=" + $r.Err
  Check "16 exit 2" ($r.Code -eq 2) $ctx
  Check "16 舊逐字稿仍在" (Test-Path -LiteralPath $oldLog16) $ctx
  Test-StateKept "16" $r $h16

  # 案數守衛：只證明「沒少跑案」，不證明案子有牙齒（牙齒見檔頭 -Sut 用法）。
  # §0 3 + §1 (4+1+7+17+3+2+3=37) + §2 (4+4=8) + §3 (4+4=8) + §4 (4+1=5) + §5 (4+1=5) + §6 (4+3=7)
  # + §7 (4+7+3=14) + §8 (3+3+4+3=13) + §9 (7+3=10) + §10 (7+3=10) + §11 (5+3=8) + §12 3
  # + §13 (3+3=6) + §14 (6×6+1=37) + §15 2 + §16 (2+3=5)
  $expected = 181
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
