# exit-code-contract.tests.ps1 -- Windows：codex-consult / codex-exec 的退出碼契約回歸測試。
#
# 契約：「哨兵訊息 ＋ 專屬退出碼」。42 = 疑似配額/認證失敗（呼叫端停止重試）；
#       46 = 逐字稿寫入失敗（不得回報成功、不得鑄證）；其餘 = 原樣傳回 codex 的退出碼。
#
# 這份測試守的是**三條**曾經讓契約塌成 rc 1 的路（全部實測過，見
# docs/exit-code-contract-plan-2026-08-19.md §2.1）：
#   (1) $WarningPreference='Stop' → Write-Warning 變終止性例外，走不到 exit。
#   (2) $ErrorActionPreference='Stop' ＋ $PSNativeCommandUseErrorActionPreference=$true
#       → native 非零退出直接丟例外，連 $LASTEXITCODE 都抓不到。
#   (3) pipeline 內用 -ErrorAction Stop 寫 log → log 壞掉時在擷取 rc 前中止（同型）。
# 另外守「哨兵必須在 stderr、不得污染 stdout」——warning stream 跨 process 會落到 OS stdout。
#
# ⚠️ 涵蓋範圍（別讀成「全部守住了」）：
#   - preference 矩陣在 pwsh 是 2³；WinPS 5.1 沒有 native preference，只跑 2² 並標 N/A。
#   - 分類**精度**的案例（§2）目前**刻意有一條是紅的**，見該節註解。
#   - 假 codex 只模擬 stdout/stderr/rc，不模擬逾時、部分輸出、串流中斷。
#
# ⚠️ 兩支受測腳本都**必須**透過測試接縫換掉 codex 本體，否則會打到真的 codex
#    （2026-08-19 我就誤打過 4 次）。每個 child 另有硬性 timeout 當第二道保險。

param([ValidateSet('pwsh', 'powershell')][string]$Shell = 'pwsh')

$ErrorActionPreference = 'Stop'
$script:pass = 0
$script:fail = 0
$script:failed = @()
$script:xfail = 0            # 已知會紅、且**刻意**保留的案例（見 §2）
$CHILD_TIMEOUT_MS = 30000

function Read-Utf8([string]$path) {
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
# 刻意保留的紅燈：印出來但不計入 fail，且**必須真的紅**——如果它變綠了，代表
# 被修好了（或案子被削弱了），此時反而要報 FAIL 逼人回來更新本檔。
function CheckXFail([string]$name, [bool]$condShouldBeFalse, [string]$why, [string]$detail) {
  if (-not $condShouldBeFalse) {
    $script:xfail++
    Write-Output ("  XFAIL " + $name + "  <- 已知未修：" + $why)
    return
  }
  $script:fail++
  $script:failed += ($name + "(XFAIL 變綠了，請更新本檔)")
  Write-Output ("  FAIL  " + $name + " —— 這個案子原本應該是紅的。若你剛修好它，請把 CheckXFail 改成 Check。" +
    $(if ($detail) { "`n        " + $detail } else { "" }))
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path $here "..\scripts"
$consult = Join-Path $scriptsDir "codex-consult.ps1"
$execSut = Join-Path $scriptsDir "codex-exec.ps1"

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("xcode-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$fakeHome = Join-Path $root "home"
New-Item -ItemType Directory -Path (Join-Path $fakeHome ".claude") -Force | Out-Null
$repo = Join-Path $root "repo"; New-Item -ItemType Directory -Path $repo -Force | Out-Null
$brief = Join-Path $root "brief.md"; Write-Utf8 $brief "test brief"
$outFixture = Join-Path $root "fake-stdout.txt"
$errFixture = Join-Path $root "fake-stderr.txt"
$trace = Join-Path $root "stub-trace.txt"

# 假 codex：stdout 與 stderr **分開**餵（2026-08-19 之前只能餵 stdout，
# 導致「分類器該看哪一段」這件事根本測不到）。每次執行寫一行 trace，用來證明
# 接縫真的生效、而且恰好執行一次（不是完全沒跑而讓斷言以錯誤理由通過）。
$fakeCodex = Join-Path $root "fake-codex.cmd"
@'
@echo off
>>"%FAKE_TRACE%" echo RAN
if "%FAKE_LOCK_LOG%"=="1" for %%f in ("%FAKE_LOGDIR%\*.txt") do attrib +r "%%f"
type "%FAKE_OUT_FILE%"
type "%FAKE_ERR_FILE%" 1>&2
exit /b %FAKE_EXIT%
'@ | Set-Content -LiteralPath $fakeCodex -Encoding ascii

# wrapper：注入三個 preference 的唯一辦法（-File 無法設 preference 變數）。
# 參數全走環境變數：實測 Start-Process -ArgumentList 傳空字串會整組位移，
# 而 **陣列 splat 會被當成位置參數**（-Dir 不被認成參數名）→ 兩者都會讓案子
# 以錯誤的理由「通過」。故一律 hashtable splat。
# ⚠️ 必須 UTF-8 **with BOM**：WinPS 5.1 讀無 BOM 的 .ps1 用 ANSI 解碼，
#    $env:XC_TARGET 裡的「超級模式」會變亂碼而找不到檔。
$wrapper = Join-Path $root "wrapper.ps1"
$wrapperSrc = @'
if ($env:XC_WARN) { $WarningPreference = $env:XC_WARN }
if ($env:XC_EAP)  { $ErrorActionPreference = $env:XC_EAP }
if ($env:XC_NATIVE -eq 'true')  { $PSNativeCommandUseErrorActionPreference = $true }
if ($env:XC_NATIVE -eq 'false') { $PSNativeCommandUseErrorActionPreference = $false }
$ht = @{}
foreach ($pair in ($env:XC_ARGS -split "`n")) {
  if (-not $pair) { continue }
  $k, $v = $pair -split '=', 2
  if ($v -eq '__SWITCH__') { $ht[$k] = $true } else { $ht[$k] = $v }
}
& $env:XC_TARGET @ht
exit $LASTEXITCODE
'@
[System.IO.File]::WriteAllText($wrapper, $wrapperSrc, (New-Object System.Text.UTF8Encoding $true))

# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Sut {
  param(
    [string]$Target, [hashtable]$Params,
    [string]$Warn = '', [string]$Eap = '', [string]$Native = '',
    [string]$StdoutText = '', [string]$StderrText = '', [int]$FakeExit = 0,
    [string]$SeamVar = 'SUPER_MODE_CODEX_CMD',
    [switch]$LockLog, [switch]$BreakLogDir
  )
  $o = Join-Path $root "o.txt"; $e = Join-Path $root "e.txt"
  Remove-Item -LiteralPath $o, $e, $trace -Force -ErrorAction SilentlyContinue
  # 每案重建乾淨的假家目錄：logdir 只能有一份 log，stub 的 glob 才會精準命中。
  $fakeLogDir = Join-Path $fakeHome ".claude\super-mode-logs"
  if (Test-Path -LiteralPath $fakeLogDir) {
    Get-ChildItem -LiteralPath $fakeLogDir -File -Force -ErrorAction SilentlyContinue |
      ForEach-Object { try { $_.IsReadOnly = $false } catch {}; Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $fakeLogDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($BreakLogDir) {
    # logdir 位置放一個**檔案**：Test-Path 會回 true 所以腳本不會嘗試建目錄，
    # 接著 preflight 的 WriteAllText 必定失敗 → 這是「還沒呼叫 codex 就壞」那條路。
    New-Item -ItemType Directory -Path (Split-Path -Parent $fakeLogDir) -Force | Out-Null
    Set-Content -LiteralPath $fakeLogDir -Value "not a directory" -Encoding ascii
  }
  $env:FAKE_LOGDIR = $fakeLogDir
  $env:FAKE_LOCK_LOG = $(if ($LockLog) { "1" } else { "0" })
  Write-Utf8 $outFixture $StdoutText
  Write-Utf8 $errFixture $StderrText

  # 兩個接縫變數都先清掉，再只設要用的那一個 —— 免得上一案的殘留讓本案「以錯誤理由通過」。
  Remove-Item -LiteralPath Env:SUPER_MODE_CODEX_CMD -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath Env:SUPER_MODE_CODEX_CMD_EXEC -ErrorAction SilentlyContinue
  Set-Item -LiteralPath ("Env:" + $SeamVar) -Value $fakeCodex

  $env:FAKE_OUT_FILE = $outFixture
  $env:FAKE_ERR_FILE = $errFixture
  $env:FAKE_EXIT = "$FakeExit"
  $env:FAKE_TRACE = $trace
  $env:XC_WARN = $Warn; $env:XC_EAP = $Eap; $env:XC_NATIVE = $Native
  $env:XC_TARGET = $Target
  $env:XC_ARGS = (($Params.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n")

  $oldHome = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  try {
    $pr = Start-Process -FilePath $Shell -ArgumentList @('-NoProfile', '-File', $wrapper) `
      -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
    if (-not $pr.WaitForExit($CHILD_TIMEOUT_MS)) {
      try { $pr.Kill() } catch {}
      return @{ Code = -999; Out = ""; Err = "TIMEOUT"; Ran = -1 }
    }
    $ranLines = @((Read-Utf8 $trace) -split "`r?`n" | Where-Object { $_ -match 'RAN' })
    return @{ Code = $pr.ExitCode; Out = (Read-Utf8 $o); Err = (Read-Utf8 $e); Ran = $ranLines.Count }
  }
  finally {
    $env:USERPROFILE = $oldHome
    if (Test-Path -LiteralPath $fakeLogDir -PathType Container) {
      Get-ChildItem -LiteralPath $fakeLogDir -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_.IsReadOnly = $false } catch {} }
    }
  }
}

$QUOTA = 'CONSULT_UNAVAILABLE_QUOTA'
$consultArgs = @{ Dir = $repo; PromptFile = $brief; NoCredential = '__SWITCH__' }
$execArgs = @{ Dir = $repo; PromptFile = $brief }

# preference profile 矩陣。WinPS 5.1 沒有 native preference → 只跑 2²，並標 N/A。
$profiles = @()
foreach ($w in @('Continue', 'Stop')) {
  foreach ($ea in @('Continue', 'Stop')) {
    if ($Shell -eq 'pwsh') {
      foreach ($nv in @('false', 'true')) {
        $profiles += @{ Warn = $w; Eap = $ea; Native = $nv; Tag = "W=$w/E=$ea/N=$nv" }
      }
    }
    else {
      $profiles += @{ Warn = $w; Eap = $ea; Native = ''; Tag = "W=$w/E=$ea/N=n-a" }
    }
  }
}

try {
  Write-Output ("§0 attestation：runner host = " + $PSVersionTable.PSVersion +
    " / 受測 child host = " + $Shell + " / profile 數 = " + $profiles.Count)
  # child 真正的 host 版本要由 child 自己回報，不能拿 runner 的版本充數。
  $hostProbe = Join-Path $root "hostprobe.ps1"
  [System.IO.File]::WriteAllText($hostProbe, '$PSVersionTable.PSVersion.ToString()', (New-Object System.Text.UTF8Encoding $true))
  $hp = & $Shell -NoProfile -File $hostProbe
  Write-Output ("   child 自報版本 = " + $hp)
  Check "0a child host 版本可取得" ([string]::IsNullOrWhiteSpace($hp) -eq $false) "child 沒回報版本"
  if ($Shell -eq 'powershell') {
    Check "0b -Shell powershell 必須真的是 5.x" ($hp -like '5.*') "child 自報 $hp"
  }
  else {
    Check "0b -Shell pwsh 必須真的是 7+" ($hp -like '7.*') "child 自報 $hp"
  }

  # ═══ §1 preference 矩陣 × 兩條 transport 路徑 ═══════════════════════════
  foreach ($pf in $profiles) {
    $t = $pf.Tag
    # (a) 疑似配額：訊息在 **stderr**（真 codex 的致命錯誤走 stderr，實測 2026-08-13 事故如此）
    $r = Invoke-Sut -Target $consult -Params $consultArgs -Warn $pf.Warn -Eap $pf.Eap -Native $pf.Native `
      -StdoutText "" -StderrText "ERROR: usage limit reached" -FakeExit 7
    Check "1a[$t] 接縫生效且 stub 恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran)
    Check "1b[$t] 配額路徑 → 精確 exit 42（不是 1）" ($r.Code -eq 42) ("exit=" + $r.Code + " err=" + $r.Err)
    Check "1c[$t] 哨兵在 stderr" ($r.Err -match $QUOTA) ("err=" + $r.Err)
    Check "1d[$t] 哨兵不得污染 stdout" (-not ($r.Out -match $QUOTA)) ("out=" + $r.Out)
    Check "1e[$t] 不得洩漏 native 例外文字" (-not ($r.Err -match 'NativeCommandExitException|NativeCommandError')) ("err=" + $r.Err)

    # (b) 一般失敗 → 原樣傳回 codex 的退出碼
    $r = Invoke-Sut -Target $consult -Params $consultArgs -Warn $pf.Warn -Eap $pf.Eap -Native $pf.Native `
      -StdoutText "some answer" -StderrText "plain failure, nothing special" -FakeExit 7
    Check "1f[$t] 一般失敗 → 原樣 exit 7" ($r.Code -eq 7) ("exit=" + $r.Code + " err=" + $r.Err)
    Check "1g[$t] 一般失敗不得產生配額哨兵" (-not (($r.Out + $r.Err) -match $QUOTA)) ("err=" + $r.Err)
  }

  # ═══ §2 分類精度（preference 無關，只跑預設 profile）══════════════════════
  Write-Output "§2 分類精度"
  # 第二個 rc：只用 7 的話，產品被改成寫死 `exit 7` 仍會全綠。
  $r = Invoke-Sut -Target $consult -Params $consultArgs -StdoutText "ans" -StderrText "plain failure" -FakeExit 23
  Check "2a 第二個 rc 也要原樣傳回（23）" ($r.Code -eq 23) ("exit=" + $r.Code)

  # codex 自己回 42、但沒有配額訊息 → rc 仍是 42，但**不得**有哨兵。
  # 這正是 exit 42 命名空間衝突：消費端必須要求「rc42 **且** 哨兵」，不能只看 rc。
  $r = Invoke-Sut -Target $consult -Params $consultArgs -StdoutText "ans" -StderrText "plain failure" -FakeExit 42
  Check "2b codex 原生 42 → rc 42" ($r.Code -eq 42) ("exit=" + $r.Code)
  Check "2c codex 原生 42 但無配額訊息 → 不得有哨兵" (-not (($r.Out + $r.Err) -match $QUOTA)) ("err=" + $r.Err)

  # 誤陽性負例 (i)：grep 行號前綴出現在 **stdout**（codex 的回答正文）。
  $r = Invoke-Sut -Target $consult -Params $consultArgs `
    -StdoutText "docs/history/FIX-PLAN.md:401:  see line 429 here" -StderrText "plain failure" -FakeExit 7
  Check "2d stdout 的 401:/429 前綴不得觸發配額" (-not (($r.Out + $r.Err) -match $QUOTA)) ("err=" + $r.Err)

  # 誤陽性負例 (ii)：**stderr** 中段是 codex 的推理/工具軌跡（grep 行號前綴、
  # 以及我們自己原始碼裡的 CONSULT_UNAVAILABLE_QUOTA 字串），尾端才是真正的失敗原因。
  # 這是 2026-08-13 事故的真實形狀（實測 88 份逐字稿，47 份只在 stderr 命中）。
  # 這四行就是 2026-08-13 事故逐字稿的真實形狀：前三行是 codex 的推理/工具軌跡
  # （grep 行號前綴、以及它讀到我們自己原始碼裡的 QUOTA 字串），最後一行才是真正的
  # 失敗原因，而那個原因**與配額無關**。判準必須只認最後那種形狀的行。
  $noisyErr = @(
    'docs/history/FIX-PLAN-macos-2026-07-03.md:401:  3. rerun tests',
    'grep hit: "CONSULT_UNAVAILABLE_QUOTA: codex quota/auth failure"',
    'web search: CLICOLOR_FORCE',
    'ERROR: This content was flagged for possible cybersecurity risk.'
  ) -join "`n"
  $r = Invoke-Sut -Target $consult -Params $consultArgs -StdoutText "" -StderrText $noisyErr -FakeExit 7
  Check "2e stderr 軌跡雜訊不得誤判成配額" (-not ($r.Err -match $QUOTA)) ("err=" + $r.Err)
  Check "2e2 但仍要原樣傳回退出碼" ($r.Code -eq 7) ("exit=" + $r.Code)
  Check "2e3 要附一句「有字樣但未據此判定」的提示" ($r.Err -match '未據此判定') ("err=" + $r.Err)

  # tier 1 的另一個關鍵字：確認判準不是只認得 'usage limit' 這一句。
  $r = Invoke-Sut -Target $consult -Params $consultArgs `
    -StdoutText "" -StderrText "ERROR: 429 Too Many Requests" -FakeExit 7
  Check "2f 錯誤行上的 429 → 42 + 哨兵" (($r.Code -eq 42) -and ($r.Err -match $QUOTA)) `
    ("exit=" + $r.Code + " err=" + $r.Err)

  # 尾端視窗：配額字樣出現在**很早**的地方、後面被大量軌跡蓋過 → 不得判定。
  # （真的額度用盡時，錯誤一定在最後才印出來。）
  $buried = (@('ERROR: usage limit reached') + (1..60 | ForEach-Object { "trace line $_" })) -join "`n"
  $r = Invoke-Sut -Target $consult -Params $consultArgs -StdoutText "" -StderrText $buried -FakeExit 7
  Check "2g 尾端視窗之外的配額字樣不得判定" (-not ($r.Err -match $QUOTA)) ("err=" + $r.Err)

  # ═══ §3 codex-exec：專屬接縫 ＋ 同一組 transport 保證 ══════════════════════
  Write-Output "§3 codex-exec"
  # 先證明**專屬**接縫是分開的：只設 consult 的變數時，exec 不該採用它。
  # （若 exec 誤用了 consult 的變數，stub 會被執行 → Ran 會 > 0。）
  $r = Invoke-Sut -Target $execSut -Params $execArgs -SeamVar 'SUPER_MODE_CODEX_CMD' `
    -StdoutText "" -StderrText "" -FakeExit 0
  Check "3a exec 不得採用 consult 的接縫變數" ($r.Ran -eq 0) `
    ("Ran=" + $r.Ran + " —— exec 竟然吃了 SUPER_MODE_CODEX_CMD")

  foreach ($pf in $profiles) {
    $t = $pf.Tag
    $r = Invoke-Sut -Target $execSut -Params $execArgs -SeamVar 'SUPER_MODE_CODEX_CMD_EXEC' `
      -Warn $pf.Warn -Eap $pf.Eap -Native $pf.Native `
      -StdoutText "worker output" -StderrText "worker failed" -FakeExit 7
    Check "3b[$t] exec 接縫生效且恰跑一次" ($r.Ran -eq 1) ("Ran=" + $r.Ran + " err=" + $r.Err)
    Check "3c[$t] exec 失敗 → 原樣 exit 7" ($r.Code -eq 7) ("exit=" + $r.Code + " err=" + $r.Err)
    Check "3d[$t] exec 不得洩漏 native 例外文字" (-not ($r.Err -match 'NativeCommandExitException|NativeCommandError')) ("err=" + $r.Err)
  }

  # ═══ §5 逐字稿故障注入（P0-7）════════════════════════════════════════════
  # 這一節存在的理由很具體：mutant C（pipeline 內把 log 寫入改回 -ErrorAction Stop）
  # 在沒有本節時 **94/0 全綠** —— 也就是「log 壞掉仍要 drain 完才抓 rc」這條規則
  # 原本沒有任何守衛。2026-08-19 實測確認。
  Write-Output "§5 逐字稿故障注入"
  $tokenPath = Join-Path $fakeHome ".claude\.super-mode-consult-ok"

  # 5a：codex 成功，但逐字稿跑到一半壞掉 → 不得回報成功、不得鑄證，精確 exit 46。
  Remove-Item -LiteralPath $tokenPath -Force -ErrorAction SilentlyContinue
  $okArgs = @{ Dir = $repo; PromptFile = $brief }      # 刻意**不帶** -NoCredential，才驗得到鑄證與否
  $r = Invoke-Sut -Target $consult -Params $okArgs -LockLog `
    -StdoutText ("ALLOW: 可以做`\n" + ("x" * 80)) -StderrText "" -FakeExit 0
  Check "5a-1 log 中途壞掉 → 精確 exit 46" ($r.Code -eq 46) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "5a-2 有 TRANSCRIPT_FAILED 哨兵" ($r.Err -match 'CONSULT_TRANSCRIPT_FAILED') ("err=" + $r.Err)
  Check "5a-3 不得鑄造憑證" (-not (Test-Path -LiteralPath $tokenPath)) "憑證竟然被寫出來了"
  Check "5a-4 不得印出成功訊息" (-not ($r.Out -match 'consult OK')) ("out=" + $r.Out)

  # 5b：codex 失敗 + log 壞掉 → **退出碼仍須原樣傳回**（這正是 mutant C 會破的那條）。
  $r = Invoke-Sut -Target $consult -Params $consultArgs -LockLog `
    -StdoutText "partial answer" -StderrText "plain failure" -FakeExit 7
  Check "5b-1 log 壞掉不得吃掉退出碼（仍是 7，不是 1）" ($r.Code -eq 7) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "5b-2 訊息要附上逐字稿不完整的診斷" ($r.Err -match '逐字稿不完整') ("err=" + $r.Err)

  # 5c：log 壞掉時**分類結果不得改變** —— 這是 P0-2 的驗收標準本身。
  #     判準吃的是記憶體裡的 stderr，不是磁碟上的 log。
  $r = Invoke-Sut -Target $consult -Params $consultArgs -LockLog `
    -StdoutText "" -StderrText "ERROR: usage limit reached" -FakeExit 7
  Check "5c-1 log 壞掉但配額分類不受影響 → 仍是 42" ($r.Code -eq 42) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "5c-2 哨兵仍在 stderr" ($r.Err -match $QUOTA) ("err=" + $r.Err)

  # 5d：連 log 都建不出來（logdir 位置是個檔案）→ 在呼叫 codex **之前**就停。
  $r = Invoke-Sut -Target $consult -Params $consultArgs -BreakLogDir `
    -StdoutText "x" -StderrText "" -FakeExit 0
  Check "5d-1 preflight 失敗 → 精確 exit 46" ($r.Code -eq 46) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "5d-2 有 TRANSCRIPT_UNAVAILABLE 哨兵" ($r.Err -match 'CONSULT_TRANSCRIPT_UNAVAILABLE') ("err=" + $r.Err)
  Check "5d-3 codex 根本不該被呼叫" ($r.Ran -eq 0) ("Ran=" + $r.Ran)

  # ═══ §4 靜態守衛（AST）══════════════════════════════════════════════════
  # 規則：這兩支 process wrapper **不得使用 PowerShell 的 warning stream**。
  # ⚠️ 名稱刻意叫「靜態可解析」：AST 抓不到 `& $cmd` 這種動態命令名，也抓不到
  #    $PSCmdlet.WriteWarning()。別把本節全綠讀成「完全不可能用到 warning stream」。
  Write-Output "§4 靜態守衛：禁止靜態可解析的 Write-Warning"
  foreach ($n in @('codex-consult.ps1', 'codex-exec.ps1')) {
    $p = Join-Path $scriptsDir $n
    Check "4-$n 檔案存在" (Test-Path -LiteralPath $p) "找不到 $p"
    $perr = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$perr)
    # parse error 一律視為失敗：解析不了就等於守衛沒有生效，不能當成通過。
    Check "4-$n 無 parse error" (($null -eq $perr) -or ($perr.Count -eq 0)) `
      ("parse errors=" + $(if ($perr) { $perr.Count } else { 0 }))
    $hits = @()
    if ($ast) {
      # $true = 遞迴掃 nested AST（scriptblock、function、pipeline 內都要掃到）
      $cmds = $ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true)
      foreach ($c in $cmds) {
        $nm = $c.GetCommandName()
        if (-not $nm) { continue }                       # 動態命令名 → AST 無能為力
        $leaf = ($nm -split '\\')[-1]                    # 模組限定名取最後一節
        if ($leaf -ieq 'Write-Warning') { $hits += ("L" + $c.Extent.StartLineNumber) }
      }
    }
    Check "4-$n 無 Write-Warning（0 處）" ($hits.Count -eq 0) `
      ("命中 " + $hits.Count + " 處 (" + ($hits -join ',') + ")；改用 [Console]::Error.WriteLine")
  }
  # 案數守衛：只證明「沒少跑案」，**不證明案子有牙齒**（刪 stimulus 留 assertion 的 mutant 案數不變）。
  # 公式：§2 固定 2 案 + §1 每 profile 7 案 + §2 4 案 + §3a 1 案 + §3 每 profile 3 案 + §4 6 案。
  $expected = 29 + 10 * $profiles.Count   # 13 原有 + §5 的 11 + §2 新增的 4（2e2/2e3/2f/2g）
  $ran = $script:pass + $script:fail
  Check "案數守衛：實跑 $expected 案" ($ran -eq $expected) ("實跑=" + $ran + " 期望=" + $expected)
}
finally {
  foreach ($v in @('SUPER_MODE_CODEX_CMD', 'SUPER_MODE_CODEX_CMD_EXEC', 'FAKE_OUT_FILE', 'FAKE_ERR_FILE',
      'FAKE_EXIT', 'FAKE_TRACE', 'FAKE_LOGDIR', 'FAKE_LOCK_LOG', 'XC_WARN', 'XC_EAP', 'XC_NATIVE', 'XC_TARGET', 'XC_ARGS')) {
    Remove-Item -LiteralPath ("Env:" + $v) -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("exit-code-contract [$Shell]: pass=" + $script:pass + " fail=" + $script:fail + " xfail=" + $script:xfail)
if ($script:fail -gt 0) {
  Write-Output ("failed: " + ($script:failed -join ', '))
  exit 1
}
exit 0
