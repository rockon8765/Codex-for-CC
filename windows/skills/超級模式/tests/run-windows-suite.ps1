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

# ══ SUT root 驗證 ══════════════════════════════════════════════════════════
# ⚠️ `-Mode` 原本只是**使用者宣告**：它換 matcher 旗標與 skip 名單，但 `$here`
#    永遠是 runner 自己所在的樹 ⇒ 從 repo 樹跑 `-Mode live` 會把 repo 檔案標成 live。
#    （2026-08-19 Codex 抓到，我複驗屬實：先前那句「live ran=8」測的其實是 repo。）
#    與「harness 3.2 × SUT 5.3」同型：**標籤不等於實際受測的東西**。
#    所以這裡把宣告變成可驗證的事實，對不上就拒跑。
$liveRoot = Join-Path $env:USERPROFILE ".claude"
$underLive = $here.TrimEnd('\').ToLowerInvariant().StartsWith($liveRoot.TrimEnd('\').ToLowerInvariant() + [IO.Path]::DirectorySeparatorChar)
if ($Mode -eq 'live' -and -not $underLive) {
  Write-Output ("FAIL  -Mode live 但 runner 不在 live 樹底下：" + $here)
  Write-Output ("      live 應在 " + $liveRoot + " 之下。從 repo 樹跑 -Mode live 只會把 repo 檔案標成 live。")
  Write-Output "SUITE_RESULT=WRONG-ROOT"
  exit 1
}
if ($Mode -eq 'repo' -and $underLive) {
  Write-Output ("FAIL  -Mode repo 但 runner 在 live 樹底下：" + $here)
  Write-Output "SUITE_RESULT=WRONG-ROOT"
  exit 1
}

# ── manifest ─────────────────────────────────────────────────────────────────
# Marker 一律用**錨定**的樣式：散文裡出現同樣的字不該讓它變綠。
$MANIFEST = @(
  @{ Name = 'gate-cases';            Exe = 'node';        Args = @('run-gate-tests.js');                       Marker = '(?m)^PASS ([1-9]\d*)/\1\r?$';                      TimeoutMs = 120000 }
  @{ Name = 'matcher-contract';      Exe = 'node';        Args = @('matcher-contract.test.js', "--$Mode");     Marker = '(?m)^RESULT_CODE=OK\r?$';                    TimeoutMs = 120000 }
  @{ Name = 'class-b-8dot3';         Exe = 'node';        Args = @('class-b-8dot3.test.js');                   Marker = '(?m)^PASS\r?$';                              TimeoutMs = 120000 }
  @{ Name = 'consult-schema';        Exe = 'pwsh';        Args = @('consult-schema.tests.ps1');                Marker = '(?m)^CONSULT-SCHEMA ([1-9]\d*)/\1\r?$';           TimeoutMs = 300000 }
  @{ Name = 'consult-credential-7';  Exe = 'pwsh';        Args = @('consult-credential.tests.ps1', '-Shell', 'pwsh');       Marker = '(?m)^CONSULT-CREDENTIAL ([1-9]\d*)/\1\r?$'; TimeoutMs = 600000 }
  @{ Name = 'consult-credential-51'; Exe = 'pwsh';        Args = @('consult-credential.tests.ps1', '-Shell', 'powershell');  Marker = '(?m)^CONSULT-CREDENTIAL ([1-9]\d*)/\1\r?$'; TimeoutMs = 900000 }
  @{ Name = 'exit-contract-7';       Exe = 'pwsh';        Args = @('exit-code-contract.tests.ps1', '-Shell', 'pwsh');       Marker = '(?m)^exit-code-contract \[pwsh\]: pass=[1-9]\d* fail=0 '; TimeoutMs = 900000 }
  @{ Name = 'exit-contract-51';      Exe = 'pwsh';        Args = @('exit-code-contract.tests.ps1', '-Shell', 'powershell'); Marker = '(?m)^exit-code-contract \[powershell\]: pass=[1-9]\d* fail=0 '; TimeoutMs = 900000 }
  @{ Name = 'codex-check';           Exe = 'powershell';  Args = @('codex-check.tests.ps1');                   Marker = '(?m)^TOTAL [1-9]\d* FAIL 0\r?$';                  TimeoutMs = 900000 }
  # ⚠️ repo 層級的規則：這支測試**不在 skill payload 內**，live 安裝時根本不存在
  #    （從 ~/.claude/skills/超級模式/tests 往上四層是 %USERPROFILE%，不是 repo 根）。
  #    2026-08-19 我上一輪才修掉「matcher 寫死 --repo 導致 live 必敗」，
  #    加這條時**用同一個模式再犯一次** —— repo-only 的東西塞進 repo/live 共用 runner。
  #    所以每一列都要宣告它適用哪些 mode，而被跳過的要**印出來**，不能靜靜消失。
  @{ Name = 'no-multibyte-varref';   Exe = 'node';        Args = @('..\..\..\..\tests\no-multibyte-varref.test.js'); Marker = '(?m)^RESULT_CODE=OK\r?$';        TimeoutMs = 120000; Modes = @('repo') }
)

# 這個數字是**刻意寫死**的：manifest 被人不小心刪掉一列時要看得出來。
# 改動 manifest 請一併改這裡（並在 commit 訊息說明改了什麼）。
$EXPECTED_ENTRIES = 10

$results = @()
$fail = 0

if ($MANIFEST.Count -ne $EXPECTED_ENTRIES) {
  Write-Output ("FAIL  manifest 條目數 = " + $MANIFEST.Count + "，期望 " + $EXPECTED_ENTRIES +
    "（有人動了 manifest 卻沒更新 EXPECTED_ENTRIES）")
  $fail++
}

$skipped = @()
$resolvedTargets = @()
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

  $resolvedTargets += (Resolve-Path -LiteralPath $target).Path
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
  # ⚠️ 這一段外面要有 catch：runner 頂層是 EAP=Stop，Start-Process／WaitForExit／
  #    讀暫存檔任何一個丟例外都會在**印出總結之前**中止。那會紅（不是假綠），
  #    但仍是「報告機制在報告之前死掉」——本批已經栽在這個模式上好幾次。
  try {
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

  }
  catch {
    $fail++
    Write-Output ("FAIL  " + $m.Name + " -- 啟動或收集輸出時丟出例外：" + $_.Exception.Message)
    $results += ("{0,-22} {1,-6} {2,6}s  {3}" -f $m.Name, 'ERROR', [int]$sw.Elapsed.TotalSeconds, $m.Exe)
    continue
  }

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

# 受測 bytes 的指紋：把所有 resolved target 依路徑排序後串接內容取 SHA-256。
# ⚠️ 這是「證據信任根從 label 換成 bytes」的最小做法 —— `mode=live`、`22/0`、`@sha`
#    三者可以各自為真而組合起來不是你以為的那個測量（Codex 第六輪的核心指控）。
$digest = "?"
try {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $buf = New-Object System.IO.MemoryStream
  # ⚠️ 指紋必須同時涵蓋**產品腳本**，不能只有測試檔。
  #    第一版只雜湊 manifest 的 target（都是測試），結果我改了 codex-consult.ps1 與
  #    codex-exec.ps1 之後 digest 一模一樣 —— 那個指紋認不出「測的是哪一版產品」，
  #    等於又是一個看起來像證據、實際上不指向受測 bytes 的東西。
  $prodDir = Join-Path $here "..\scripts"
  $prodFiles = @()
  if (Test-Path -LiteralPath $prodDir) {
    $prodFiles = @(Get-ChildItem -LiteralPath $prodDir -File | ForEach-Object { $_.FullName })
  }
  foreach ($t in (($resolvedTargets + $prodFiles) | Sort-Object -Unique)) {
    $bytes = [System.IO.File]::ReadAllBytes($t)
    $buf.Write($bytes, 0, $bytes.Length)
  }
  $digest = ([BitConverter]::ToString($sha.ComputeHash($buf.ToArray())) -replace '-', '').Substring(0, 16).ToLowerInvariant()
}
catch { $digest = "digest-failed" }

Write-Output ""
$results | ForEach-Object { Write-Output $_ }
if ($skipped.Count -gt 0) {
  Write-Output ""
  # 被跳過的要看得見：靜靜消失的話，「全綠」就分不出「跑完了」與「沒跑」。
  Write-Output ("因 mode 而未執行： " + ($skipped -join '； '))
}
Write-Output ""
Write-Output ("runner-root = " + $here)
Write-Output ("sut-digest  = " + $digest + "   （所有受測檔內容的 SHA-256 前 16 碼）")
Write-Output ("run-windows-suite [mode=" + $Mode + "]: entries=" + $MANIFEST.Count +
  " ran=" + $results.Count + " skipped=" + $skipped.Count + " fail=" + $fail)

# ⚠️ -Filter 是除錯用的，**不得產生 attestation**：
#    `-Mode live -Filter no-multibyte-varref` 原本會得到 ran=0 fail=0 SUITE_RESULT=OK
#    —— 跑了零個測試卻回報成功，而本檔檔頭正好寫著「空模組不得綠」。
if ($Filter) {
  Write-Output "SUITE_RESULT=FILTERED（用了 -Filter，這不是完整驗收，不得引用為證據）"
  if ($fail -gt 0) { exit 1 }
  exit 0
}

# 正式模式：釘死每個 mode 該跑幾支、該跳過幾支。零案一律視為失敗。
$EXPECTED = @{ repo = @{ ran = 10; skipped = 0 }; live = @{ ran = 9; skipped = 1 } }
$want = $EXPECTED[$Mode]
if ($results.Count -eq 0) {
  Write-Output "FAIL  一支都沒跑到 —— 零案不算通過。"
  exit 1
}
if ($results.Count -ne $want.ran -or $skipped.Count -ne $want.skipped) {
  Write-Output ("FAIL  mode=" + $Mode + " 期望 ran=" + $want.ran + " skipped=" + $want.skipped +
    "，實得 ran=" + $results.Count + " skipped=" + $skipped.Count +
    "（manifest 被動過卻沒更新這裡，或有項目異常跳過）")
  exit 1
}
if ($fail -gt 0) { exit 1 }
Write-Output "SUITE_RESULT=OK"
exit 0
