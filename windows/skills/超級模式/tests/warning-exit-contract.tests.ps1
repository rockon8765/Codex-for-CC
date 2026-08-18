# warning-exit-contract.tests.ps1 -- Windows 專屬：Write-Warning 會吃掉退出碼契約的回歸測試。
#
# 守的是什麼（2026-08-19 修復）：
#   codex-consult.ps1 / codex-exec.ps1 對呼叫端的契約是「哨兵訊息 + 專屬退出碼」：
#     42 = 配額/認證失敗（呼叫端必須停止重試）、其餘 = 原樣傳回 codex 自己的退出碼。
#   舊寫法是 `Write-Warning "..."` 緊接 `exit 42`。在 $WarningPreference='Stop' 之下
#   Write-Warning 會變成**終止性例外**，程式根本走不到 exit 那行 → rc 塌成 1，契約消失。
#   同時 warning stream 跨 process 會落到 OS **stdout**，呼叫端在 stderr 看不到哨兵，
#   而 -Quiet 摘要 / --output-schema 的 stdout 解析反而被污染。
#   修法：改用 [Console]::Error.WriteLine（同檔 -Prompt deprecation 那段早就這樣做）。
#
# 為什麼要注入 $WarningPreference：呼叫端（Claude Code 的 PowerShell 工具）的 session
#   preference 不由本 repo 決定 —— 使用者 profile 設成 Stop 就會踩到。故兩種都要驗。
#
# ⚠️ 涵蓋範圍（別誤讀成「三支腳本都守住了」）：
#   - 動態案例只跑 codex-consult.ps1：只有它有 SUPER_MODE_CODEX_CMD 測試接縫。
#     codex-exec.ps1 把 codex 路徑硬寫死（無接縫），只能靠 §3 的靜態守衛。
#   - codex-check.ps1 **不在**守衛範圍。它仍在用 Write-Warning，而且其 test runner 用
#     `2>&1 | Out-String` 合流：改成真 stderr 會變成 NativeCommandError，在 EAP=Stop
#     之下會炸掉整個 runner。那是獨立一批工作，見 docs/backlog.md。
#
# 受測 host 用 -Shell 切換（使用者的 PowerShell 工具用哪一支不由我們決定）。

param([ValidateSet('pwsh', 'powershell')][string]$Shell = 'pwsh')

$ErrorActionPreference = 'Stop'
$script:pass = 0
$script:fail = 0
$script:failed = @()

# 案數守衛：只證明「沒少跑案」，**不證明案子有牙齒**。牙齒靠變異注入手動驗（見 §3 註解）。
$EXPECTED_CHECKS = 16

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
$scriptsDir = Join-Path $here "..\scripts"
$consult = Join-Path $scriptsDir "codex-consult.ps1"

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("warnrc-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$fakeHome = Join-Path $root "home"
New-Item -ItemType Directory -Path (Join-Path $fakeHome ".claude") -Force | Out-Null
$repo = Join-Path $root "repo"
New-Item -ItemType Directory -Path $repo -Force | Out-Null
$brief = Join-Path $root "brief.md"
Set-Content -LiteralPath $brief -Value "test brief" -Encoding utf8

# 假 codex：把 FAKE_TEXT 印到 stdout，用 FAKE_EXIT 當退出碼。完全不碰真 codex。
$fakeCodex = Join-Path $root "fake-codex.cmd"
@'
@echo off
echo %FAKE_TEXT%
exit /b %FAKE_EXIT%
'@ | Set-Content -LiteralPath $fakeCodex -Encoding ascii

# wrapper：注入 $WarningPreference 的唯一辦法（-File 沒有辦法設 preference 變數）。
# 參數一律走環境變數，不走 -ArgumentList：實測 Start-Process 傳空字串會整組位移，
# 而 **陣列 splat 會被當成位置參數**（`-Dir` 不會被認成參數名）→ 兩種都會讓案子
# 以錯誤的理由「通過」。故用 hashtable splat（2026-08-19 踩過這兩個坑）。
# ⚠️ 必須 UTF-8 **with BOM**：WinPS 5.1 讀無 BOM 的 .ps1 會用 ANSI 解碼，
#    $env:WRC_TARGET 指向的「超級模式」路徑會變亂碼而找不到檔。
$wrapper = Join-Path $root "wrapper.ps1"
$wrapperSrc = @'
if ($env:WRC_PREF) { $WarningPreference = $env:WRC_PREF }
$ht = @{}
foreach ($pair in ($env:WRC_ARGS -split "`n")) {
  if (-not $pair) { continue }
  $k, $v = $pair -split '=', 2
  if ($v -eq '__SWITCH__') { $ht[$k] = $true } else { $ht[$k] = $v }
}
& $env:WRC_TARGET @ht
exit $LASTEXITCODE
'@
[System.IO.File]::WriteAllText($wrapper, $wrapperSrc, (New-Object System.Text.UTF8Encoding $true))

function Run-Consult([string]$pref, [string]$fakeText, [int]$fakeExit) {
  $o = Join-Path $root "o.txt"; $e = Join-Path $root "e.txt"
  Remove-Item -LiteralPath $o, $e -Force -ErrorAction SilentlyContinue
  $env:SUPER_MODE_CODEX_CMD = $fakeCodex
  $env:FAKE_TEXT = $fakeText
  $env:FAKE_EXIT = "$fakeExit"
  $env:WRC_PREF = $pref
  $env:WRC_TARGET = $consult
  $env:WRC_ARGS = (@("Dir=$repo", "PromptFile=$brief", "NoCredential=__SWITCH__") -join "`n")
  $oldHome = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  try {
    $pr = Start-Process -FilePath $Shell -ArgumentList @('-NoProfile', '-File', $wrapper) `
      -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
    return @{ Code = $pr.ExitCode; Out = (Read-Utf8 $o); Err = (Read-Utf8 $e) }
  }
  finally { $env:USERPROFILE = $oldHome }
}

try {
  # Continue = 一般 session 的預設；Stop = 使用者 profile 可能設的值，也就是會踩雷的那個。
  foreach ($pref in @('Continue', 'Stop')) {
    Write-Output "§1 配額/認證失敗路徑（pref=$pref）"
    $r = Run-Consult $pref 'usage limit reached' 7
    Check "1a[$pref] 配額路徑 → 精確 exit 42（不是 1）" ($r.Code -eq 42) `
      ("exit=" + $r.Code + " err=" + $r.Err)
    Check "1b[$pref] 哨兵出現在 stderr" ($r.Err -match 'CONSULT_UNAVAILABLE_QUOTA') `
      ("err=" + $r.Err)
    Check "1c[$pref] 哨兵不得污染 stdout" (-not ($r.Out -match 'CONSULT_UNAVAILABLE_QUOTA')) `
      ("out=" + $r.Out)

    Write-Output "§2 一般失敗路徑（pref=$pref）"
    $r = Run-Consult $pref 'ordinary failure' 7
    Check "2a[$pref] 一般失敗 → 原樣傳回 codex 的 exit 7" ($r.Code -eq 7) `
      ("exit=" + $r.Code + " err=" + $r.Err)
    Check "2b[$pref] 失敗訊息出現在 stderr" ($r.Err -match 'no credential written') `
      ("err=" + $r.Err)
    Check "2c[$pref] 失敗訊息不得污染 stdout" (-not ($r.Out -match 'no credential written')) `
      ("out=" + $r.Out)
  }

  # §3 靜態守衛：codex-exec.ps1 沒有測試接縫，只能用原始碼層級的規則守。
  # 規則刻意訂得比「Write-Warning 後面不能接 exit」更寬：只要這兩支還有 Write-Warning
  # 就算違規。理由是「後面幾行內有沒有 exit」要靠讀程式碼反推，改版時很容易漏判。
  # 牙齒驗證（手動變異注入，2026-08-19 做過）：把任一行改回 Write-Warning → 本節必紅。
  Write-Output "§3 靜態守衛：consult/exec 不得再出現 Write-Warning"
  foreach ($n in @('codex-consult.ps1', 'codex-exec.ps1')) {
    $p = Join-Path $scriptsDir $n
    Check "3-$n 檔案存在" (Test-Path -LiteralPath $p) "找不到 $p"
    $txt = Read-Utf8 $p
    $hits = @([regex]::Matches($txt, '(?m)^\s*Write-Warning\b'))
    Check "3-$n 無 Write-Warning（0 處）" ($hits.Count -eq 0) `
      ("命中 " + $hits.Count + " 處；改用 [Console]::Error.WriteLine")
  }

  # 本身是第 17 個 Check，所以拿它之前的累計數去比。
  $ran = $script:pass + $script:fail
  Check "案數守衛：實跑 $EXPECTED_CHECKS 案" ($ran -eq $EXPECTED_CHECKS) `
    ("實跑=" + $ran + " 期望=" + $EXPECTED_CHECKS)
}
finally {
  foreach ($v in @('SUPER_MODE_CODEX_CMD', 'FAKE_TEXT', 'FAKE_EXIT', 'WRC_PREF', 'WRC_TARGET', 'WRC_ARGS')) {
    Remove-Item -LiteralPath ("Env:" + $v) -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("warning-exit-contract [$Shell]: pass=" + $script:pass + " fail=" + $script:fail)
if ($script:fail -gt 0) {
  Write-Output ("failed: " + ($script:failed -join ', '))
  exit 1
}
exit 0
