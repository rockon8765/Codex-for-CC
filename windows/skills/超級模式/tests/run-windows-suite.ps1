# run-windows-suite.ps1 -- Windows 側測試的單一入口。
#
# 為什麼需要它（2026-08-19，Codex 反方審查指出）：在此之前，Windows 這邊沒有任何
# 「跑全部」的入口——`run-gate-tests.ps1` 只跑 gate 的 JS。新增的測試檔就算寫得再好，
# 沒有人叫它就不是回歸守衛，只是「可以手動跑的檔案」。
#
# 設計：**顯式 manifest**，不是掃目錄數檔案。
#   ⚠️ 用檔數當守衛擋不住「刪掉真 runner、補一個 dummy 進去」——數字不變、全綠。
#   所以每一列都要釘：檔名、參數、host、timeout、以及**成功時必須出現的 marker**。
#   marker 不出現就算 FAIL，即使該支自己回了 exit 0（空模組／被截斷的輸出都會自然 exit 0）。
#
# ⚠️ 涵蓋範圍：只跑 windows/ 底下的測試。POSIX 側有各自的入口
#    （tests/run-gate-tests.js、tests/exit-code-contract.smoke.sh）。
# ⚠️ codex-check.tests.ps1 內部把 SUT 的 host 寫死成 powershell.exe，
#    所以本聚合器對它的 -Shell 標示只反映 runner，不代表 SUT。見 docs/backlog.md
#    的 CODEX-CHECK-WARNING。

param(
  # repo = 驗 repo 樹（AI-INSTALL 步驟 1a）；live = 驗已安裝的副本（步驟 3）。
  # ⚠️ 這不是可選項：matcher-contract 在兩種情境要用不同旗標。寫死 --repo 會讓
  #    乾淨的 live 安裝必敗（live 端沒有相鄰的 settings.snippet.json →
  #    SETTINGS_UNREADABLE → 依 AI-INSTALL 要 rollback）。2026-08-19 Codex 抓到。
  [ValidateSet('repo', 'live')][string]$Mode = 'repo',
  # 只跑名稱含此字串的項目（除錯用）。正式驗收不要帶。
  [string]$Filter = ''
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── manifest ─────────────────────────────────────────────────────────────────
# Marker 一律用**錨定**的樣式：散文裡出現同樣的字不該讓它變綠。
$MANIFEST = @(
  @{ Name = 'gate-cases';            Exe = 'node';        Args = @('run-gate-tests.js');                       Marker = '(?m)^PASS \d+/\d+\r?$';                      TimeoutMs = 120000 }
  @{ Name = 'matcher-contract';      Exe = 'node';        Args = @('matcher-contract.test.js', "--$Mode");     Marker = '(?m)^RESULT_CODE=OK\r?$';                    TimeoutMs = 120000 }
  @{ Name = 'class-b-8dot3';         Exe = 'node';        Args = @('class-b-8dot3.test.js');                   Marker = '(?m)^PASS\r?$';                              TimeoutMs = 120000 }
  @{ Name = 'consult-schema';        Exe = 'pwsh';        Args = @('consult-schema.tests.ps1');                Marker = '(?m)^CONSULT-SCHEMA (\d+)/\1\r?$';           TimeoutMs = 300000 }
  @{ Name = 'consult-credential-7';  Exe = 'pwsh';        Args = @('consult-credential.tests.ps1', '-Shell', 'pwsh');       Marker = '(?m)^CONSULT-CREDENTIAL (\d+)/\1\r?$'; TimeoutMs = 600000 }
  @{ Name = 'exit-contract-7';       Exe = 'pwsh';        Args = @('exit-code-contract.tests.ps1', '-Shell', 'pwsh');       Marker = '(?m)^exit-code-contract \[pwsh\]: pass=\d+ fail=0 '; TimeoutMs = 900000 }
  @{ Name = 'exit-contract-51';      Exe = 'pwsh';        Args = @('exit-code-contract.tests.ps1', '-Shell', 'powershell'); Marker = '(?m)^exit-code-contract \[powershell\]: pass=\d+ fail=0 '; TimeoutMs = 900000 }
  @{ Name = 'codex-check';           Exe = 'powershell';  Args = @('codex-check.tests.ps1');                   Marker = '(?m)^TOTAL \d+ FAIL 0\r?$';                  TimeoutMs = 900000 }
  # ⚠️ repo 層級的規則：這支測試**不在 skill payload 內**，live 安裝時根本不存在
  #    （從 ~/.claude/skills/超級模式/tests 往上四層是 %USERPROFILE%，不是 repo 根）。
  #    2026-08-19 我上一輪才修掉「matcher 寫死 --repo 導致 live 必敗」，
  #    加這條時**用同一個模式再犯一次** —— repo-only 的東西塞進 repo/live 共用 runner。
  #    所以每一列都要宣告它適用哪些 mode，而被跳過的要**印出來**，不能靜靜消失。
  @{ Name = 'no-multibyte-varref';   Exe = 'node';        Args = @('..\..\..\..\tests\no-multibyte-varref.test.js'); Marker = '(?m)^RESULT_CODE=OK\r?$';        TimeoutMs = 120000; Modes = @('repo') }
)

# 這個數字是**刻意寫死**的：manifest 被人不小心刪掉一列時要看得出來。
# 改動 manifest 請一併改這裡（並在 commit 訊息說明改了什麼）。
$EXPECTED_ENTRIES = 9

$results = @()
$fail = 0

if ($MANIFEST.Count -ne $EXPECTED_ENTRIES) {
  Write-Output ("FAIL  manifest 條目數 = " + $MANIFEST.Count + "，期望 " + $EXPECTED_ENTRIES +
    "（有人動了 manifest 卻沒更新 EXPECTED_ENTRIES）")
  $fail++
}

$skipped = @()
foreach ($m in $MANIFEST) {
  if ($Filter -and ($m.Name -notlike "*$Filter*")) { continue }
  # 沒宣告 Modes = 兩種 mode 都跑。宣告了就只在列出的 mode 跑。
  $entryModes = if ($m.ContainsKey('Modes')) { $m.Modes } else { @('repo', 'live') }
  if ($entryModes -notcontains $Mode) {
    $skipped += ("{0}（只在 -Mode {1} 跑）" -f $m.Name, ($entryModes -join '/'))
    continue
  }
  $target = Join-Path $here $m.Args[0]
  if (-not (Test-Path -LiteralPath $target)) {
    Write-Output ("FAIL  " + $m.Name + " -- 找不到 " + $target)
    $fail++; continue
  }

  $argv = @()
  if ($m.Exe -in @('pwsh', 'powershell')) { $argv += @('-NoProfile', '-File', $target) + $m.Args[1..($m.Args.Count - 1)] }
  else { $argv = @($target) + $m.Args[1..($m.Args.Count - 1)] }
  # $m.Args[1..0] 在只有一個元素時會回空陣列以外的怪東西 → 明確處理。
  if ($m.Args.Count -eq 1) {
    if ($m.Exe -in @('pwsh', 'powershell')) { $argv = @('-NoProfile', '-File', $target) } else { $argv = @($target) }
  }

  # 受測 host 不存在時要講清楚是哪一支，不要變成看不懂的 FAIL。
  if (-not (Get-Command $m.Exe -ErrorAction SilentlyContinue)) {
    Write-Output ("FAIL  " + $m.Name + " -- 找不到受測 host '" + $m.Exe +
      "'。本 suite 需要 node、pwsh 與 powershell 三者皆可用。")
    $fail++; continue
  }

  $o = Join-Path ([System.IO.Path]::GetTempPath()) ("suite-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".out")
  $e = $o + ".err"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  # ⚠️ Start-Process 的 -ArgumentList **陣列**不保留 argv 邊界——它用空白串成單一
  #    command line，所以含空白的路徑（`C:\Users\First Last\...`）會被拆開，
  #    child 收到半截路徑 → 整個 suite 假紅。consult-credential.tests.ps1 §11 早就
  #    記載過這個坑，我還是踩了（2026-08-19 Codex 抓到）。這裡自己逐一加引號。
  $argString = ($argv | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
  # 逐支開**新 process**：共用 session 會讓某一支改動的 preference／環境變數污染下一支。
  $pr = Start-Process -FilePath $m.Exe -ArgumentList $argString -NoNewWindow -PassThru `
    -RedirectStandardOutput $o -RedirectStandardError $e
  $exited = $pr.WaitForExit($m.TimeoutMs)
  $sw.Stop()
  if (-not $exited) {
    try { $pr.Kill() } catch {}
    Write-Output ("FAIL  " + $m.Name + " -- TIMEOUT (" + $m.TimeoutMs + "ms)")
    $fail++
    Remove-Item -LiteralPath $o, $e -Force -ErrorAction SilentlyContinue
    continue
  }
  $out = ""
  if (Test-Path -LiteralPath $o) { $out = [System.IO.File]::ReadAllText($o, (New-Object System.Text.UTF8Encoding $false)) }
  $err = ""
  if (Test-Path -LiteralPath $e) { $err = [System.IO.File]::ReadAllText($e, (New-Object System.Text.UTF8Encoding $false)) }
  Remove-Item -LiteralPath $o, $e -Force -ErrorAction SilentlyContinue

  $rcOk = ($pr.ExitCode -eq 0)
  # marker 同時掃 stdout 與 stderr：有些受測檔把摘要寫在 stderr。
  $markOk = (($out + "`n" + $err) -match $m.Marker)
  $ok = $rcOk -and $markOk
  if (-not $ok) {
    $fail++
    $why = @()
    if (-not $rcOk) { $why += ("exit=" + $pr.ExitCode) }
    if (-not $markOk) { $why += "缺少成功 marker" }
    Write-Output ("FAIL  " + $m.Name + " -- " + ($why -join '，'))
    $tail = (($out + "`n" + $err) -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 6) -join "`n        "
    if ($tail) { Write-Output ("        " + $tail) }
  }
  $results += ("{0,-22} {1,-6} {2,6}s  {3}" -f $m.Name, $(if ($ok) { 'OK' } else { 'FAIL' }), [int]$sw.Elapsed.TotalSeconds, $m.Exe)
}

Write-Output ""
$results | ForEach-Object { Write-Output $_ }
if ($skipped.Count -gt 0) {
  Write-Output ""
  # 被跳過的要看得見：靜靜消失的話，「全綠」就分不出「跑完了」與「沒跑」。
  Write-Output ("因 mode 而未執行： " + ($skipped -join '； '))
}
Write-Output ""
Write-Output ("run-windows-suite [mode=" + $Mode + "]: entries=" + $MANIFEST.Count +
  " ran=" + $results.Count + " skipped=" + $skipped.Count + " fail=" + $fail)
if ($fail -gt 0) { exit 1 }
Write-Output "SUITE_RESULT=OK"
exit 0
