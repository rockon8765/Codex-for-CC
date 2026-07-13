# codex-check.ps1 合成測試臺（Windows / PowerShell 5.1）。
# 用法: powershell.exe -NoProfile -ExecutionPolicy Bypass -File codex-check.tests.ps1 [測試名…]；無參數跑全部。
# ⚠️ 本 host（mac）無 powershell.exe / cmd.exe → 無法在此執行；權威執行留給 Windows 原生 session（promote gate）。
# 原理: USERPROFILE 指到暫存 fakeHome（隔離快取）；seam env（CODEX_CHECK_*_CMD）注入 stub、不靠 PATH；
#       每案以獨立子行程 powershell.exe -File 跑真 SUT（SUT 內含 exit，同行程會殺 runner）。
# 反打 live: 每案斷言 stub trace 與 SUT 輸出都不含 C:\npm。
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:sut       = Join-Path $here '..\scripts\codex-check.ps1'
$script:testsFile = $MyInvocation.MyCommand.Path

$script:total = 0
$script:fails = 0
$script:out = ''
$script:rc = 0
$script:fakeHome = ''
$script:tracePath = ''
$script:currentTest = ''
$script:fakeHomes = @()
$script:origUserProfile = $env:USERPROFILE

# 測試控制的 env 名單（每案先清、再套 override，避免跨案汙染）
$stubVars = @('CODEX_STUB_VERSION','CODEX_STUB_VERSION_PREFIX','CODEX_STUB_SUPPORTS_LASTMSG',
              'CODEX_STUB_MODE','CODEX_STUB_LASTMSG','CODEX_STUB_TRACE','CODEX_STUB_HELP_PAD',
              'CODEX_STUB_EXEC_STDERR','NPM_STUB_MODE','NPM_STUB_VERSION')

# --- stub 生成（寫進 $env:TEMP\codex-check-test-<GUID>\，UTF-8 無 BOM；cmd batch 有 BOM 會壞）---
# 讀同名 CODEX_STUB_* / NPM_STUB_* env（語義同 bash stub，含 SUPPORTS / TRACE / help / print-then-hang）。
$esc = [char]27
$stubRoot = Join-Path $env:TEMP ('codex-check-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stubRoot -Force | Out-Null
$script:codexStub = Join-Path $stubRoot 'codex-stub.cmd'
$script:npmStub   = Join-Path $stubRoot 'npm-stub.cmd'

$codexStubLines = @(
  '@echo off',
  'if defined CODEX_STUB_TRACE (echo %*>>"%CODEX_STUB_TRACE%")',
  'if not defined CODEX_STUB_VERSION set "CODEX_STUB_VERSION=0.144.1"',
  'if not defined CODEX_STUB_SUPPORTS_LASTMSG set "CODEX_STUB_SUPPORTS_LASTMSG=1"',
  'if "%~1"=="--version" goto :version',
  'if "%~1"=="plugin" exit /b 0',
  'if "%~1"=="mcp" exit /b 0',
  'if "%~1"=="features" exit /b 0',
  'if "%~1"=="exec" goto :exec',
  'exit /b 0',
  '',
  ':version',
  'if defined CODEX_STUB_VERSION_PREFIX echo %CODEX_STUB_VERSION_PREFIX%',
  'if /I not "%CODEX_STUB_VERSION%"=="NONE" echo codex-cli %CODEX_STUB_VERSION%',
  'exit /b 0',
  '',
  ':exec',
  'if "%~2"=="--help" goto :exechelp',
  'if defined CODEX_STUB_EXEC_STDERR echo Reading additional input from stdin... 1>&2',
  'set "lastmsg_file="',
  'shift',
  ':scan',
  'if "%~1"=="" goto :run',
  'if "%~1"=="-o" goto :wantfile',
  'if "%~1"=="--output-last-message" goto :wantfile',
  'shift',
  'goto :scan',
  ':wantfile',
  'if not "%CODEX_STUB_SUPPORTS_LASTMSG%"=="1" goto :badflag',
  'shift',
  'set "lastmsg_file=%~1"',
  'shift',
  'goto :scan',
  ':badflag',
  'echo error: unexpected argument 1>&2',
  'exit /b 2',
  ':run',
  'if not defined lastmsg_file goto :emit',
  'if not defined CODEX_STUB_LASTMSG goto :emit',
  '>"%lastmsg_file%" echo %CODEX_STUB_LASTMSG%',
  ':emit',
  'if not defined CODEX_STUB_MODE set "CODEX_STUB_MODE=ok"',
  'if /I "%CODEX_STUB_MODE%"=="echo-only" goto :emit_echo',
  'if /I "%CODEX_STUB_MODE%"=="ansi" goto :emit_ansi',
  ':emit_ok',
  'echo user',
  'echo Reply with exactly: CODEX_OK',
  'echo codex',
  'echo CODEX_OK',
  'echo tokens used',
  'echo 123',
  'exit /b 0',
  ':emit_ansi',
  'echo user',
  'echo Reply with exactly: CODEX_OK',
  ('echo ' + $esc + '[1;32mcodex' + $esc + '[0m'),
  ('echo ' + $esc + '[32mCODEX_OK' + $esc + '[0m'),
  'echo tokens used',
  'echo 123',
  'exit /b 0',
  ':emit_echo',
  'echo user',
  'echo Reply with exactly: CODEX_OK',
  'echo tokens used',
  'echo 123',
  'exit /b 0',
  '',
  ':exechelp',
  'echo Usage: codex exec [OPTIONS] [PROMPT]',
  'if "%CODEX_STUB_SUPPORTS_LASTMSG%"=="1" echo   -o, --output-last-message ^<FILE^>  Write last agent message to file',
  'if defined CODEX_STUB_HELP_PAD call :helppad',
  'exit /b 0',
  '',
  ':helppad',
  'rem H2 regression filler: CODEX_STUB_HELP_PAD (bytes) appends filler lines after the flag line',
  'set /a n=CODEX_STUB_HELP_PAD/40+1',
  'for /l %%i in (1,1,%n%) do echo wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww',
  'goto :eof'
)

$npmStubLines = @(
  '@echo off',
  'if not defined NPM_STUB_MODE set "NPM_STUB_MODE=ok"',
  'if /I "%NPM_STUB_MODE%"=="fail" goto :fail',
  'if /I "%NPM_STUB_MODE%"=="sleep" goto :sleep',
  'if /I "%NPM_STUB_MODE%"=="print-then-hang" goto :pth',
  'if /I "%NPM_STUB_MODE%"=="print-then-fail" goto :ptf',
  'if /I "%NPM_STUB_MODE%"=="multiline" goto :multiline',
  'if /I "%NPM_STUB_MODE%"=="blank2" goto :blank2',
  'if /I "%NPM_STUB_MODE%"=="junk" goto :junk',
  ':ok',
  'if not defined NPM_STUB_VERSION set "NPM_STUB_VERSION=0.144.1"',
  'echo %NPM_STUB_VERSION%',
  'exit /b 0',
  ':fail',
  'echo npm error network request failed 1>&2',
  'exit /b 1',
  ':sleep',
  'ping -n 61 127.0.0.1 >NUL',
  'exit /b 0',
  ':pth',
  'echo 0.145.0',
  'ping -n 61 127.0.0.1 >NUL',
  'exit /b 0',
  ':ptf',
  'echo 0.145.0',
  'exit /b 1',
  ':multiline',
  'echo 0.145.0',
  'echo NOTICE something',
  'exit /b 0',
  ':blank2',
  'echo 0.145.0',
  'echo.',
  'echo NOTICE',
  'exit /b 0',
  ':junk',
  'echo 0.145.0garbage',
  'exit /b 0'
)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($script:codexStub, (($codexStubLines -join "`r`n") + "`r`n"), $utf8NoBom)
[System.IO.File]::WriteAllText($script:npmStub,   (($npmStubLines   -join "`r`n") + "`r`n"), $utf8NoBom)

# --- runner infra ------------------------------------------------------------
function Assert {
  param([string]$name, [string]$desc, [int]$code)
  $script:total++
  if ($code -eq 0) { Write-Output "PASS: $name — $desc" }
  else { Write-Output "FAIL: $name — $desc"; $script:fails++ }
}
function AssertMatch { param([string]$name, [string]$desc, [string]$pattern)
  if ($script:out -match $pattern) { Assert $name $desc 0 } else { Assert $name $desc 1 } }
function AssertNoMatch { param([string]$name, [string]$desc, [string]$pattern)
  if ($script:out -match $pattern) { Assert $name $desc 1 } else { Assert $name $desc 0 } }

function Assert-Bom {
  param([string]$path, [string]$label)
  $ok = $false
  try {
    $fs = [System.IO.File]::OpenRead($path)
    try {
      $b = New-Object byte[] 3
      $n = $fs.Read($b, 0, 3)
      if ($n -eq 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $ok = $true }
    } finally { $fs.Close() }
  } catch { $ok = $false }
  if ($ok) { Assert 'bom' "$label 檔頭 EF BB BF" 0 } else { Assert 'bom' "$label 檔頭非 EF BB BF" 1 }
}

function Setup {
  $script:fakeHome = Join-Path $env:TEMP ('codex-check-home-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path (Join-Path $script:fakeHome '.claude') -Force | Out-Null
  # 實測（PS 5.1.26100，2026-07-13 Windows 原生 gate）：USERPROFILE 重導到缺 AppData\Local 的目錄時，
  # SUT 內 Receive-Job 丟 terminating「The Persistence Path does not exist」（-EA SilentlyContinue 擋不住），
  # 被 SUT 的 catch 折成 $latest=$null → npm 查詢永遠 UNKNOWN（假 offline），五個正向 verdict 案全紅。
  # bisect：fake home 補建空的 AppData\Local 即恢復。此為 fake profile 保真度修補，不改 SUT 行為。
  New-Item -ItemType Directory -Path (Join-Path $script:fakeHome 'AppData\Local') -Force | Out-Null
  $script:fakeHomes += $script:fakeHome
}
function CacheFile { return (Join-Path $script:fakeHome '.claude\.codex-check-last') }

# 唯一進入點；stub 預設在此統一注入（後傳 hashtable 可覆寫；空字串=移除該 env=bash「定義但空」的 no-write 語義）。
function Invoke-Check {
  param([string]$Mode, [hashtable]$Overrides = @{})
  foreach ($n in $stubVars) { if (Test-Path "Env:$n") { Remove-Item "Env:$n" } }
  $env:CODEX_CHECK_CODEX_CMD = $script:codexStub   # seam → stub（永遠注入，絕不打 live）
  $env:CODEX_CHECK_NPM_CMD   = $script:npmStub
  $env:USERPROFILE = $script:fakeHome
  $env:CODEX_STUB_LASTMSG = 'CODEX_OK'             # 預設 lastmsg（同 bash invoke_check）
  $script:tracePath = Join-Path $script:fakeHome ('codex.trace.' + [guid]::NewGuid().ToString('N'))
  $env:CODEX_STUB_TRACE = $script:tracePath
  foreach ($k in $Overrides.Keys) {
    $v = $Overrides[$k]
    if ($null -eq $v -or $v -eq '') { if (Test-Path "Env:$k") { Remove-Item "Env:$k" } }
    else { Set-Item "Env:$k" -Value $v }
  }
  $sutArgs = @()
  if ($Mode -eq 'force') { $sutArgs = @('-Force') }
  # 捕 SUT 輸出時暫降 EAP=Continue：runner 頂層是 Stop，SUT 子行程若寫 stderr（如回歸的
  # NativeCommandError 文字），2>&1 會把它包成 ErrorRecord、Stop 之下直接炸死整個 runner——
  # 那應該呈現為該案 FAIL 斷言，不是測試臺崩潰。
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $raw = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:sut @sutArgs 2>&1 | Out-String
  $script:rc = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  $script:out = $raw
  # anti-live：stub trace 與 SUT 輸出都不得出現 C:\npm（防繞過 seam 打真 Codex）
  $antiHit = $false
  if (Test-Path -LiteralPath $script:tracePath) {
    $tc = Get-Content -LiteralPath $script:tracePath -Raw -ErrorAction SilentlyContinue
    if ($tc -and ($tc -match [regex]::Escape('C:\npm'))) { $antiHit = $true }
  }
  if ($script:out -match [regex]::Escape('C:\npm')) { $antiHit = $true }
  if ($antiHit) { Assert $script:currentTest 'anti-live: 無 C:\npm 痕跡' 1 } else { Assert $script:currentTest 'anti-live: 無 C:\npm 痕跡' 0 }
}
function Run-Check { param([hashtable]$Overrides = @{}); Invoke-Check -Mode force -Overrides $Overrides }

# --- 28 測試案例（27 案鏡像 bash runner；含 H4 全欄位/H2 大 help/H1 巨型 banner 反方檢核同步案；
#     +1 Windows 專屬 smoke stderr 噪音回歸案——bash 無此失敗模式故無對應案）--------
function t_happy_path {
  $script:currentTest = 'happy_path'
  Setup; Run-Check
  Assert 'happy_path' 'exit 0' $script:rc
  AssertMatch 'happy_path' 'verdict UP-TO-DATE' 'UP-TO-DATE'
  $cf = CacheFile
  if ((Test-Path -LiteralPath $cf) -and ((Get-Content -LiteralPath $cf -Raw) -match 'smoke=OK')) { Assert 'happy_path' '快取寫入' 0 } else { Assert 'happy_path' '快取寫入' 1 }
}
function t_offline_unknown {   # C3 回歸：離線 → UNKNOWN、絕無 OUTDATED
  $script:currentTest = 'offline_unknown'
  Setup; Run-Check @{ NPM_STUB_MODE = 'fail' }
  AssertMatch 'offline_unknown' 'verdict UNKNOWN' '(?m)^UNKNOWN'
  AssertNoMatch 'offline_unknown' '無 OUTDATED' 'OUTDATED'
}
function t_fake_pass_rejected {  # C2 回歸：只有 prompt echo、無回覆、exit 0 → 判失敗（SUPPORTS=0 走 legacy 路徑）
  $script:currentTest = 'fake_pass_rejected'
  Setup; Set-Content -LiteralPath (CacheFile) -Value 'stale'
  Run-Check @{ CODEX_STUB_MODE = 'echo-only'; CODEX_STUB_SUPPORTS_LASTMSG = '0'; CODEX_STUB_LASTMSG = '' }
  if ($script:rc -eq 1) { Assert 'fake_pass_rejected' 'exit 1' 0 } else { Assert 'fake_pass_rejected' "exit 1（實際 $($script:rc)）" 1 }
  if (-not (Test-Path -LiteralPath (CacheFile))) { Assert 'fake_pass_rejected' '快取已刪' 0 } else { Assert 'fake_pass_rejected' '快取已刪' 1 }
}
function t_ansi_stripped {       # C2 回歸：marker/回覆包 ANSI 仍認得（legacy 路徑）
  $script:currentTest = 'ansi_stripped'
  Setup; Run-Check @{ CODEX_STUB_MODE = 'ansi'; CODEX_STUB_SUPPORTS_LASTMSG = '0'; CODEX_STUB_LASTMSG = '' }
  Assert 'ansi_stripped' 'exit 0' $script:rc
}
function t_h1_leading_warning {  # 版本行前有 warning → 仍抽到版本 → UP-TO-DATE
  $script:currentTest = 'h1_leading_warning'
  Setup; Run-Check @{ CODEX_STUB_VERSION_PREFIX = 'warning: something enabled' }
  AssertMatch 'h1_leading_warning' 'warning 前置仍 UP-TO-DATE' 'UP-TO-DATE'
}
function t_h1_warning_has_version {  # warning 內含別的版本號 → 錨定行優先、不誤抓
  $script:currentTest = 'h1_warning_has_version'
  Setup; Run-Check @{ CODEX_STUB_VERSION_PREFIX = 'warning: node 22.1.0 is deprecated' }
  AssertMatch 'h1_warning_has_version' '錨定 codex-cli 行、不吃 22.1.0' 'UP-TO-DATE'
}
function t_h1_no_version {       # 完全抽不到版本 → UNKNOWN(installed) 且 smoke 照跑、exit 0
  $script:currentTest = 'h1_no_version'
  Setup; Run-Check @{ CODEX_STUB_VERSION = 'NONE'; CODEX_STUB_VERSION_PREFIX = 'some banner text' }
  AssertMatch 'h1_no_version' 'verdict UNKNOWN(installed)' 'UNKNOWN \(installed'
  Assert 'h1_no_version' 'smoke 照跑 exit 0' $script:rc
}
function t_h5_multiline {   # 多行 → UNKNOWN、不可死在 smoke 前
  $script:currentTest = 'h5_multiline'
  Setup; Run-Check @{ NPM_STUB_MODE = 'multiline' }
  AssertMatch 'h5_multiline' 'UNKNOWN' 'UNKNOWN \(latest'
  Assert 'h5_multiline' 'smoke 照跑 exit 0' $script:rc
}
function t_h5_blank_second_line {  # 第二行空白、第三行垃圾 → 仍 UNKNOWN（不可只驗第二行）
  $script:currentTest = 'h5_blank2'
  Setup; Run-Check @{ NPM_STUB_MODE = 'blank2' }
  AssertMatch 'h5_blank2' 'UNKNOWN' 'UNKNOWN \(latest'
}
function t_h5_junk {        # 尾部垃圾 0.145.0garbage → UNKNOWN
  $script:currentTest = 'h5_junk'
  Setup; Run-Check @{ NPM_STUB_MODE = 'junk' }
  AssertMatch 'h5_junk' 'UNKNOWN' 'UNKNOWN \(latest'
}
function t_h5_prerelease_current {  # 合法 prerelease 尾綴照走狀態機（CURRENT 回歸）
  $script:currentTest = 'h5_prerelease_current'
  Setup; Run-Check @{ CODEX_STUB_VERSION = '0.144.0-alpha.4'; NPM_STUB_VERSION = '0.144.0' }
  AssertMatch 'h5_prerelease_current' 'CURRENT' '(?m)^CURRENT'
}
function t_h3_npm_hang {   # npm 卡（ping 60s）→ 20s watchdog 放行 → UNKNOWN、全程 < 40s
  $script:currentTest = 'h3_npm_hang'
  Setup; $start = Get-Date
  Run-Check @{ NPM_STUB_MODE = 'sleep' }
  $dur = ((Get-Date) - $start).TotalSeconds
  AssertMatch 'h3_npm_hang' 'UNKNOWN' 'UNKNOWN \(latest'
  if ($dur -lt 40) { Assert 'h3_npm_hang' ("40s 內完成（實際 {0:N0}s）" -f $dur) 0 } else { Assert 'h3_npm_hang' ("40s 內完成（實際 {0:N0}s）" -f $dur) 1 }
}
function t_h3_partial_stdout_discarded {  # 先印完整版本再 hang → 逾時 → stdout 必須丟棄 → UNKNOWN（不可 BEHIND/AHEAD）
  $script:currentTest = 'h3_partial'
  Setup; Run-Check @{ NPM_STUB_MODE = 'print-then-hang' }
  AssertMatch 'h3_partial' 'timeout 部分輸出不進狀態機' 'UNKNOWN \(latest'
  Assert 'h3_partial' 'smoke 照跑 exit 0' $script:rc
}
function t_h3_print_then_fail {  # npm 印完版本後 exit 1（State=Completed 但 native rc!=0）→ stdout 必須丟棄 → UNKNOWN
  $script:currentTest = 'h3_print_then_fail'
  Setup; Run-Check @{ NPM_STUB_MODE = 'print-then-fail' }
  AssertMatch 'h3_print_then_fail' 'rc!=0 丟棄輸出' 'UNKNOWN \(latest'
  Assert 'h3_print_then_fail' 'smoke 照跑 exit 0' $script:rc
}
function t_h4_empty_cache_miss {   # <24h 空快取檔 → miss（照跑全檢且成功）
  $script:currentTest = 'h4_empty_cache'
  Setup; New-Item -ItemType File -Path (CacheFile) -Force | Out-Null
  Invoke-Check -Mode noforce
  AssertMatch 'h4_empty_cache' '空檔當 miss、跑了全檢' 'read-only smoke test'
  Assert 'h4_empty_cache' '全檢成功 exit 0' $script:rc
}
function t_h4_oldformat_cache_miss {  # 舊格式（無 format=2）→ miss
  $script:currentTest = 'h4_oldformat_cache'
  Setup; Set-Content -LiteralPath (CacheFile) -Value 'installed=0.1.0 latest=0.1.0 verdict=UP-TO-DATE smoke=OK at x' -Encoding utf8
  Invoke-Check -Mode noforce
  AssertMatch 'h4_oldformat_cache' '舊格式當 miss' 'read-only smoke test'
  Assert 'h4_oldformat_cache' '全檢成功 exit 0' $script:rc
}
function t_h4_truncated_line_miss {   # 截斷行（只剩前綴）→ miss（全行格式驗證）
  $script:currentTest = 'h4_truncated'
  Setup; Set-Content -LiteralPath (CacheFile) -Value 'format=2 installed=' -Encoding utf8
  Invoke-Check -Mode noforce
  AssertMatch 'h4_truncated' '截斷行當 miss' 'read-only smoke test'
}
function t_h4_future_mtime_miss {     # 合法格式但 mtime 在未來 → miss
  $script:currentTest = 'h4_future_mtime'
  Setup; Invoke-Check -Mode force     # 先產生合法快取
  $fi = Get-Item -LiteralPath (CacheFile); $fi.LastWriteTime = [datetime]'2030-01-01T00:00:00'
  Invoke-Check -Mode noforce
  AssertMatch 'h4_future_mtime' 'future-mtime 當 miss' 'read-only smoke test'
}
function t_h4_newformat_cache_hit {   # 新格式且 <24h → hit、跳過、exit 0
  $script:currentTest = 'h4_newformat_cache'
  Setup; Invoke-Check -Mode force
  Invoke-Check -Mode noforce
  AssertMatch 'h4_newformat_cache' '快取命中跳過' '跳過'
  Assert 'h4_newformat_cache' 'exit 0' $script:rc
}
function t_h2_exact_ok {    # 支援 -o：lastmsg 檔 == CODEX_OK → OK（transcript 無 marker 也行）
  $script:currentTest = 'h2_exact_ok'
  Setup; Run-Check @{ CODEX_STUB_MODE = 'echo-only' }
  Assert 'h2_exact_ok' 'exit 0（憑 lastmsg 檔）' $script:rc
}
function t_h2_not_ok_rejected {  # lastmsg 為 NOT_CODEX_OK → substring 假通過要擋
  $script:currentTest = 'h2_not_ok'
  Setup; Run-Check @{ CODEX_STUB_LASTMSG = 'NOT_CODEX_OK' }
  if ($script:rc -eq 1) { Assert 'h2_not_ok' 'exit 1' 0 } else { Assert 'h2_not_ok' "exit 1（實際 $($script:rc)）" 1 }
}
function t_h2_refusal_rejected { # lastmsg 是含 CODEX_OK 的句子 → 非精確 → 擋
  $script:currentTest = 'h2_refusal'
  Setup; Run-Check @{ CODEX_STUB_LASTMSG = 'I cannot reply CODEX_OK' }
  if ($script:rc -eq 1) { Assert 'h2_refusal' 'exit 1' 0 } else { Assert 'h2_refusal' "exit 1（實際 $($script:rc)）" 1 }
}
function t_h2_no_flag_when_unsupported {  # help 無旗標 → 絕不傳 -o（trace 佐證）、走 marker 路徑成功
  $script:currentTest = 'h2_no_flag'
  Setup; Run-Check @{ CODEX_STUB_SUPPORTS_LASTMSG = '0'; CODEX_STUB_LASTMSG = '' }
  Assert 'h2_no_flag' 'exit 0（marker 路徑）' $script:rc
  $traceHasFlag = $false
  if (Test-Path -LiteralPath $script:tracePath) {
    $tc = Get-Content -LiteralPath $script:tracePath -Raw -ErrorAction SilentlyContinue
    if ($tc -and ($tc -match 'output-last-message')) { $traceHasFlag = $true }
  }
  if ($traceHasFlag) { Assert 'h2_no_flag' '未傳 -o（trace 無旗標）' 1 } else { Assert 'h2_no_flag' '未傳 -o（trace 無旗標）' 0 }
}
function t_h4_missing_latest_field {  # 缺 latest=/verdict= 的 format=2 行 → miss（全欄位驗證，鏡像 POSIX H4 修正）
  $script:currentTest = 'h4_missing_latest'
  Setup; Set-Content -LiteralPath (CacheFile) -Value 'format=2 installed=0.144.1 smoke=OK at 2026-07-13T00:00:00+0800' -Encoding utf8
  Invoke-Check -Mode noforce
  AssertMatch 'h4_missing_latest' '缺 latest 欄位當 miss' 'read-only smoke test'
}
function t_h4_missing_verdict_field {  # 缺 verdict= 的 format=2 行 → miss（全欄位驗證）
  $script:currentTest = 'h4_missing_verdict'
  Setup; Set-Content -LiteralPath (CacheFile) -Value 'format=2 installed=0.144.1 latest=0.144.1 smoke=OK at 2026-07-13T00:00:00+0800' -Encoding utf8
  Invoke-Check -Mode noforce
  AssertMatch 'h4_missing_verdict' '缺 verdict 欄位當 miss' 'read-only smoke test'
}
function t_h2_large_help_keeps_lastmsg {  # help 旗標行後接大量填充 → Windows 無 SIGPIPE，此案為 parity/regression tripwire（非重現臭蟲）：探測不得因大量 help 輸出誤降 legacy
  $script:currentTest = 'h2_large_help'
  Setup; Run-Check @{ CODEX_STUB_MODE = 'echo-only'; CODEX_STUB_HELP_PAD = '200000' }
  Assert 'h2_large_help' 'exit 0（lastmsg 路徑不因大 help 降級）' $script:rc
}
function t_h1_huge_banner_no_crash {  # 巨大 banner（cmd 環境變數/命令列長度風險，見任務筆記，改用 30000 字元）→ 顯示管線不得崩潰
  $script:currentTest = 'h1_huge_banner'
  Setup
  $big = [string]::new([char]'w', 30000)
  Run-Check @{ CODEX_STUB_VERSION_PREFIX = $big }
  AssertMatch 'h1_huge_banner' '巨型 banner 仍 UP-TO-DATE' 'UP-TO-DATE'
  Assert 'h1_huge_banner' 'exit 0' $script:rc
}
function t_smoke_stderr_noise_no_crash {  # 2026-07-13 真 codex 回歸：exec 在 stderr 印噪音（如
  # "Reading additional input from stdin..."）→ EAP=Stop 下 PS 層 2>&1 會把 NativeCommandError 變
  # terminating、smoke 中途死掉 exit 1。修法=stderr 合流下沉到 cmd 層（鏡像 bash 2>&1）。
  $script:currentTest = 'smoke_stderr_noise'
  Setup; Run-Check @{ CODEX_STUB_EXEC_STDERR = '1' }
  Assert 'smoke_stderr_noise' 'stderr 噪音不炸 smoke（exit 0）' $script:rc
  AssertMatch 'smoke_stderr_noise' 'verdict 照常產出' 'UP-TO-DATE'
}

$allTests = @(
  't_happy_path','t_offline_unknown','t_fake_pass_rejected','t_ansi_stripped',
  't_h1_leading_warning','t_h1_warning_has_version','t_h1_no_version',
  't_h5_multiline','t_h5_blank_second_line','t_h5_junk','t_h5_prerelease_current',
  't_h3_npm_hang','t_h3_partial_stdout_discarded','t_h3_print_then_fail',
  't_h4_empty_cache_miss','t_h4_oldformat_cache_miss','t_h4_truncated_line_miss','t_h4_future_mtime_miss','t_h4_newformat_cache_hit',
  't_h2_exact_ok','t_h2_not_ok_rejected','t_h2_refusal_rejected','t_h2_no_flag_when_unsupported',
  't_h4_missing_latest_field','t_h4_missing_verdict_field','t_h2_large_help_keeps_lastmsg','t_h1_huge_banner_no_crash',
  't_smoke_stderr_noise_no_crash'
)

try {
  Assert-Bom $script:sut 'SUT'           # 檔頭 BOM 斷言（SUT 與 tests）
  Assert-Bom $script:testsFile 'tests'
  $sel = if ($args.Count -gt 0) { $args } else { $allTests }
  foreach ($t in $sel) {
    if ($allTests -contains $t) { & $t }
    else { [Console]::Error.WriteLine("unknown test: $t"); exit 2 }
  }
  Write-Output "TOTAL $($script:total) FAIL $($script:fails)"
} finally {
  # 清殘留 job 與 temp 目錄、還原 USERPROFILE
  Get-Job -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
  Get-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
  foreach ($h in $script:fakeHomes) { if ($h -and (Test-Path -LiteralPath $h)) { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue } }
  if ($stubRoot -and (Test-Path -LiteralPath $stubRoot)) { Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue }
  $env:USERPROFILE = $script:origUserProfile
}
if ($script:fails -gt 0) { exit 1 } else { exit 0 }
