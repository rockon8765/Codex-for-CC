# codex-check.ps1 合成測試臺（Windows；受測 host 可選 Windows PowerShell 5.1 或 pwsh 7）。
# 用法: powershell.exe -NoProfile -ExecutionPolicy Bypass -File codex-check.tests.ps1 [-Shell powershell|pwsh] [測試名…]
#       無測試名＝跑全部；不給 -Shell ＝ powershell（與 2026-10-14 之前寫死 powershell.exe 的行為相同）。
# ⚠️ 本 host（mac）無 powershell.exe / cmd.exe → 無法在此執行；權威執行留給 Windows 原生 session（promote gate）。
# 原理: USERPROFILE 指到暫存 fakeHome（隔離快取）；seam env（CODEX_CHECK_*_CMD）注入 stub、不靠 PATH；
#       每案以獨立子行程 <受測 host> -File 跑真 SUT（SUT 內含 exit，同行程會殺 runner）。
# 反打 live: 每案斷言 stub trace 與 SUT 輸出都不含 C:\npm。
#
# ── 受測 host（-Shell，2026-10-14 LTS C3）──────────────────────────────────────
# 先前 SUT 一律以 powershell.exe 啟動 ⇒ 從 pwsh 啟動本 runner **不代表** SUT 在 pwsh 跑過
# （docs/backlog.md 的 CODEX-CHECK-WARNING、DECISION-MEMO-lts-2026-09-30 §「LTS 建置線」）。
# 所以 SUT host 改由 -Shell 決定，並在跑任何案例之前做**自檢**：真的啟動一次受測 host、
# 讓它自報 PSEdition／PSVersion，對不上就 FAIL 並不跑案例。自報結果印成
#   CODEX-CHECK-SUT-HOST=<-Shell> <PSEdition> <PSVersion> path=<實際執行檔>
# run-windows-suite.ps1 的 marker 會同時要求這一行與 `TOTAL n FAIL 0` ——
# 標籤（-Shell）不等於實際受測的東西，要用 child 自報的事實當證據。
# ⚠️ 自檢與案例**共用同一個啟動點**（Invoke-SutProcess），並有 AST 守衛（Test-SutLaunchSite，
#    斷言名 sut_launch_site）擋「把案例的啟動行換成寫死 host」。⚠️ 範圍只到這裡：另外新增的啟動路徑
#    （Start-Process、[Diagnostics.Process]::Start、iex、cmd /c、絕對路徑、-f 縮寫）它擋不住，
#    2026-10-15 審查以變異實測確認。2026-10-14 合併前審查實測：第一版的自檢走
#    另一條探針路徑，把案例的啟動行改回寫死 powershell.exe 之後，pwsh 腿照樣全綠 —— 自檢量到的
#    不是案例真正走的路，就不算證據。
#
# ⚠️ PositionalBinding=$false：測試名是位置參數（舊用法 `codex-check.tests.ps1 t_happy_path`），
#    若讓 -Shell 吃位置參數，第一個測試名會被拿去當 -Shell 而撞 ValidateSet。
[CmdletBinding(PositionalBinding = $false)]
param(
  [ValidateSet('powershell', 'pwsh')][string]$Shell = 'powershell',
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Tests = @()
)
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
# CODEX-CHECK-CP437：console code page 狀態。實際的記錄、設定與還原都在檔尾的主 try／finally 內（見那裡的註解）；
# 這裡只先宣告，好讓 finally 在 try 一開頭就失敗時也能判斷「有沒有東西要還原」。
$script:origOutEnc = $null
$script:origInEnc = $null
$script:envConsoleCp = $null   # runner 啟動時共用 console 的 output code page（＝環境值）
$script:sutConsoleCp = $null   # 下一次 Invoke-SutProcess 讓 child 以哪個 code page 起跑；$null ＝ 不切
$script:sutCpOk = $false       # 上一次 Invoke-SutProcess 啟動 child 前，實量的 output code page 是否等於 sutConsoleCp

# 受測 host 先解析成絕對路徑（同 tests/ai-install/run-windows.ps1 的理由：executable 不存在時
# `& $exe` 不會設定 $LASTEXITCODE，會沿用上一次的值 → 「找不到 host 卻判定成功」）。
$script:sutExeName = if ($Shell -eq 'pwsh') { 'pwsh' } else { 'powershell' }
$script:sutExe = $null
try { $script:sutExe = (Get-Command $script:sutExeName -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
catch {
  Write-Output ("FAIL: 找不到受測 host '" + $script:sutExeName + "'（-Shell " + $Shell + "）：" + $_.Exception.Message)
  exit 2
}

# 測試控制的 env 名單（每案先清、再套 override，避免跨案汙染）
$stubVars = @('CODEX_STUB_VERSION','CODEX_STUB_VERSION_PREFIX','CODEX_STUB_SUPPORTS_LASTMSG',
              'CODEX_STUB_MODE','CODEX_STUB_LASTMSG','CODEX_STUB_TRACE','CODEX_STUB_HELP_PAD',
              'CODEX_STUB_EXEC_STDERR','NPM_STUB_MODE','NPM_STUB_VERSION',
              'CODEX_STUB_PLUGINS','CODEX_STUB_MCP','CODEX_STUB_FEATURES','CODEX_STUB_CAP_FAIL','CODEX_STUB_HELP_DROP_FLAG',
              'CODEX_STUB_PLUGINS_GARBAGE','CODEX_STUB_HELP_NEARFLAG',
              'CODEX_STUB_LIST_STDERR','CODEX_STUB_HELP_STDERR','CODEX_STUB_LIST_BOILERPLATE',
              'CODEX_STUB_EXEC_RC','CCHK_WARN','CCHK_NATIVE','CCHK_ERR_BROKEN','CCHK_TARGET')

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
  'if "%~1"=="plugin" goto :plugin',
  'if "%~1"=="mcp" goto :mcp',
  'if "%~1"=="features" goto :features',
  'if "%~1"=="exec" goto :exec',
  'exit /b 0',
  '',
  'rem 能力面盤點 stub：CODEX_STUB_PLUGINS=a,b / CODEX_STUB_MCP=srv:enabled,srv2:disabled /',
  'rem CODEX_STUB_FEATURES=f1:true,f2:false；CODEX_STUB_CAP_FAIL=<plugin|mcp|features> 令該段 exit 1（查詢失敗）。',
  ':plugin',
  'rem CODEX_STUB_LIST_STDERR=1 模擬升級後子命令印 stderr 噪音（SUT 須在 cmd 層丟棄、不得炸成 FAILED）',
  'if defined CODEX_STUB_LIST_STDERR echo plugin list stderr noise 1>&2',
  'if /I "%CODEX_STUB_CAP_FAIL%"=="plugin" exit /b 1',
  'if defined CODEX_STUB_LIST_BOILERPLATE goto :plugboiler',
  'if defined CODEX_STUB_PLUGINS_GARBAGE goto :pluggarbage',
  'if not defined CODEX_STUB_PLUGINS exit /b 0',
  'rem 值本身可帶 marketplace 限定詞（alpha@m1）；SUT 保留完整識別、不剝 @ 尾綴',
  'for %%p in (%CODEX_STUB_PLUGINS%) do echo %%p    enabled',
  'exit /b 0',
  ':plugboiler',
  'rem 鏡像真 codex 0.144.3 乾淨機器輸出（零外掛=EMPTY、非 UNPARSEABLE）',
  'echo No marketplace plugins found.',
  'exit /b 0',
  ':pluggarbage',
  'rem 單一空白分隔=SUT 的 \s{2,} 切不出兩欄 → 解析 0 筆但有輸出（UNPARSEABLE 路徑）',
  'echo weird new plugin format v2',
  'exit /b 0',
  '',
  ':mcp',
  'if defined CODEX_STUB_LIST_STDERR echo mcp list stderr noise 1>&2',
  'if /I "%CODEX_STUB_CAP_FAIL%"=="mcp" exit /b 1',
  'if defined CODEX_STUB_LIST_BOILERPLATE goto :mcpboiler',
  'if not defined CODEX_STUB_MCP exit /b 0',
  'for %%m in (%CODEX_STUB_MCP%) do call :mcpline %%m',
  'exit /b 0',
  ':mcpboiler',
  'echo No MCP servers configured yet. Try codex mcp add my-tool.',
  'exit /b 0',
  ':mcpline',
  'for /f "tokens=1,2 delims=:" %%a in ("%~1") do echo %%a    %%b',
  'goto :eof',
  '',
  ':features',
  'if defined CODEX_STUB_LIST_STDERR echo features list stderr noise 1>&2',
  'if /I "%CODEX_STUB_CAP_FAIL%"=="features" exit /b 1',
  'if not defined CODEX_STUB_FEATURES exit /b 0',
  'for %%f in (%CODEX_STUB_FEATURES%) do call :featline %%f',
  'exit /b 0',
  ':featline',
  'for /f "tokens=1,2 delims=:" %%a in ("%~1") do echo %%a    stable    %%b',
  'goto :eof',
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
  'rem CODEX_STUB_EXEC_RC=n: print the smoke transcript, then exit n (smoke-failure fault injection, CODEX-CHECK-WARNING)',
  'if defined CODEX_STUB_EXEC_RC goto :emit_fail',
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
  ':emit_fail',
  'echo user',
  'echo Reply with exactly: CODEX_OK',
  'echo SIMULATED_SMOKE_FAILURE',
  'exit /b %CODEX_STUB_EXEC_RC%',
  '',
  ':exechelp',
  'rem 預設 help 含 skill 依賴旗標（鏡像真 codex）；CODEX_STUB_HELP_DROP_FLAG=<flag> 讓單一旗標消失；',
  'rem CODEX_STUB_HELP_NEARFLAG=1 以近似旗標 --sandbox-policy 取代 --sandbox（測旗標邊界比對不得誤中）；',
  'rem CODEX_STUB_HELP_STDERR=1 在 help 印一行 stderr（SUT 須在 cmd 層合流、不得整段 FAILED）。',
  'if defined CODEX_STUB_HELP_STDERR echo exec help stderr noise 1>&2',
  'echo Usage: codex exec [OPTIONS] [PROMPT]',
  'if defined CODEX_STUB_HELP_NEARFLAG echo       --sandbox-policy ^<MODE^>  near flag decoy',
  'if defined CODEX_STUB_HELP_NEARFLAG goto :helprest',
  'if not "%CODEX_STUB_HELP_DROP_FLAG%"=="--sandbox" echo       --sandbox ^<MODE^>  sandbox policy',
  ':helprest',
  'if not "%CODEX_STUB_HELP_DROP_FLAG%"=="--ephemeral" echo       --ephemeral  run without persistent session state',
  'if not "%CODEX_STUB_HELP_DROP_FLAG%"=="--output-schema" echo       --output-schema ^<FILE^>  JSON schema for final message',
  'if not "%CODEX_STUB_HELP_DROP_FLAG%"=="--skip-git-repo-check" echo       --skip-git-repo-check  do not error when outside a git repo',
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

# preference wrapper（CODEX-CHECK-WARNING）：-File 啟動的 child 拿不到呼叫端的 preference，而 AI-INSTALL 步驟 4
# 是在呼叫端 session 內以 & 同行程呼叫 SUT ⇒ 要重現就得「wrapper 先設 preference、再 & SUT」。
# CCHK_ERR_BROKEN=1 另把 [Console]::Error 換成一寫就丟例外的 writer（底層 stream 已關閉），模擬 stderr 壞掉。
# 只轉送 SUT 自己的兩個 switch（不用 @args：陣列 splat 不保證保留參數名）。內容純 ASCII、仍寫 BOM（同 exit-code-contract）。
$script:prefWrapper = Join-Path $stubRoot 'pref-wrapper.ps1'
$prefWrapperLines = @(
  'param([switch]$Force, [switch]$UpdateBaseline)',
  'if ($env:CCHK_WARN) { $WarningPreference = $env:CCHK_WARN }',
  "if (`$env:CCHK_NATIVE -eq 'true') { `$PSNativeCommandUseErrorActionPreference = `$true }",
  "`$errState = 'normal'",
  "if (`$env:CCHK_ERR_BROKEN -eq '1') {",
  '  $ms = New-Object System.IO.MemoryStream',
  '  $bw = New-Object System.IO.StreamWriter($ms)',
  '  $bw.AutoFlush = $true',
  '  $ms.Dispose()',
  '  [Console]::SetError($bw)',
  "  try { [Console]::Error.WriteLine('stderr probe'); `$errState = 'writable' } catch { `$errState = 'throws' }",
  '}',
  '# self-attest: Invoke-Check asserts this line, so a broken wrapper cannot make P cases pass vacuously',
  "[Console]::Out.WriteLine('PREF-WRAPPER-ATTEST W=' + [string]`$WarningPreference + ' N=' + [string]`$PSNativeCommandUseErrorActionPreference + ' E=' + `$errState)",
  '& $env:CCHK_TARGET -Force:$Force -UpdateBaseline:$UpdateBaseline',
  'exit $LASTEXITCODE'
)
[System.IO.File]::WriteAllText($script:prefWrapper, (($prefWrapperLines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))

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
function BaselineFile { return (Join-Path $script:fakeHome '.claude\.codex-check-baseline') }

# 唯一的 SUT 啟動點：案例（Invoke-Check）與 host 自檢（Test-SutHost）共用，
# 自檢量到的才是案例真正走的那條路；Test-SutLaunchSite 以 AST 擋「繞過本函式直接啟動 SUT」。
function Invoke-SutProcess([string]$File, [string[]]$SutArgv = @()) {
  # CODEX-CHECK-CP437：child 起跑時繼承共用 console 的 output code page，而 runner 的 UTF-8 解碼設定與每一次
  # 新版 SUT 都會把共用 console 切到 65001 ⇒ 每次啟動前明確切回 ${script:sutConsoleCp}（預設＝環境值）。
  # chcp 同時設 input／output；成功與否用 GetConsoleOutputCP 實量（chcp 印的是 input code page，不能拿來量）。
  $script:sutCpOk = $false
  if ($null -ne $script:sutConsoleCp) {
    $null = & cmd.exe /d /c ('chcp ' + $script:sutConsoleCp) 2>&1 | Out-String
    $chcpRc = $LASTEXITCODE
    $measured = Get-ConsoleOutputCp
    $script:sutCpOk = ($chcpRc -eq 0) -and ($measured -eq $script:sutConsoleCp)
  }
  & $script:sutExe -NoProfile -ExecutionPolicy Bypass -File $File @SutArgv 2>&1
}
function Get-ConsoleOutputCp {
  # 直接量共用 console 的 output code page（kernel32!GetConsoleOutputCP；沒有 console 時是 0）。量不到回 ${null}。
  try { return [int][CodexCheckTests.ConsoleCp]::GetConsoleOutputCP() } catch { return $null }
}
# 唯一進入點；stub 預設在此統一注入（後傳 hashtable 可覆寫；空字串=移除該 env=bash「定義但空」的 no-write 語義）。
function Invoke-Check {
  # -Prefs @{ Warn='Stop'; Native='true'; ErrBroken='1' }：經 pref-wrapper 同行程呼叫 SUT（重現呼叫端 preference
  # 外洩與 stderr 壞掉，CODEX-CHECK-WARNING）。沒給 -Prefs ＝ 舊行為（直接 -File 跑 SUT）。
  param([string]$Mode, [hashtable]$Overrides = @{}, [hashtable]$Prefs = @{})
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
  $sutFile = $script:sut
  if ($Prefs.Count -gt 0) {
    $sutFile = $script:prefWrapper
    $env:CCHK_TARGET = [System.IO.Path]::GetFullPath($script:sut)
    if ($Prefs.ContainsKey('Warn'))      { $env:CCHK_WARN       = [string]$Prefs['Warn'] }
    if ($Prefs.ContainsKey('Native'))    { $env:CCHK_NATIVE     = [string]$Prefs['Native'] }
    if ($Prefs.ContainsKey('ErrBroken')) { $env:CCHK_ERR_BROKEN = [string]$Prefs['ErrBroken'] }
  }
  $sutArgs = @()
  if ($Mode -eq 'force') { $sutArgs = @('-Force') }
  elseif ($Mode -eq 'update') { $sutArgs = @('-Force','-UpdateBaseline') }
  # 捕 SUT 輸出時暫降 EAP=Continue：runner 頂層是 Stop，SUT 子行程若寫 stderr（如回歸的
  # NativeCommandError 文字），2>&1 會把它包成 ErrorRecord、Stop 之下直接炸死整個 runner——
  # 那應該呈現為該案 FAIL 斷言，不是測試臺崩潰。
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  # SUT host 由 -Shell 決定（見檔頭）；預設 powershell ＝ 舊行為（原本這裡寫死 powershell.exe）。
  # child 的 stderr 行經 2>&1 會變成 ErrorRecord。還原成 child 實際寫出的那一行（Exception.Message）再串接：
  # 5.1 runner 的 Out-String 會替第一行加「powershell.exe : 」標頭與位置資訊，並依 console 寬度折行
  # （2026-10-17 實測：寬 120 時中文長行被拆成兩行）。CODEX-CHECK-WARNING 之後 SUT 的診斷全走 stderr，
  # 不還原的話，斷言能不能命中就取決於跑測試的主控台寬度。
  $raw = Invoke-SutProcess $sutFile $sutArgs | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ }
  } | Out-String
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
  # 注入前置檢查：wrapper 自報的 preference／stderr 狀態必須是要求的值（否則 P 案可能以錯誤的理由變綠）
  if ($Prefs.Count -gt 0) {
    $wantW = if ($Prefs.ContainsKey('Warn')) { [regex]::Escape([string]$Prefs['Warn']) } else { '\S+' }
    $wantN = if ([string]$Prefs['Native'] -eq 'true') { 'True' } else { '\S*' }
    $wantE = if ([string]$Prefs['ErrBroken'] -eq '1') { 'throws' } else { 'normal' }
    if ($script:out -match ('(?m)^PREF-WRAPPER-ATTEST W=' + $wantW + ' N=' + $wantN + ' E=' + $wantE + '\r?$')) { Assert $script:currentTest 'preference／stderr 注入已生效（wrapper 自報）' 0 }
    else { Assert $script:currentTest 'preference／stderr 注入已生效（wrapper 自報）' 1 }
  }
}
function Run-Check { param([hashtable]$Overrides = @{}); Invoke-Check -Mode force -Overrides $Overrides }

# --- 59 測試案例（27 案鏡像 bash runner；含 H4 全欄位/H2 大 help/H1 巨型 banner 反方檢核同步案；
#     +1 Windows 專屬 smoke stderr 噪音回歸案——bash 無此失敗模式故無對應案；
#     +19 B 系列能力面 baseline diff 案（2026-07-16，Windows 先行、bash 移植待 handoff；
#        含 Workflow 對抗審查後補的 stderr 免疫/boilerplate/mcp/marketplace 識別/hooks 失真/快取對稱守衛案）；
#     +2 Windows 專屬 console code page 案（CODEX-CHECK-CP437，2026-10-17）——POSIX 沒有 code page 概念，bash runner 無對應案；
#     +10 Windows 專屬 P 系列（CODEX-CHECK-WARNING，2026-10-17）——呼叫端 preference 外洩是 PowerShell 機制，
#        POSIX 沒有對應物；stderr 壞掉的那一案在 macOS 的對應缺陷另列殘留，bash runner 目前無對應案）---
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
function t_h4_newformat_cache_hit {   # 新格式且 <24h → hit、跳過、exit 0；盤點/baseline 警示必須在 hit 前照印
  $script:currentTest = 'h4_newformat_cache'
  Setup; Invoke-Check -Mode force
  Invoke-Check -Mode noforce
  AssertMatch 'h4_newformat_cache' '快取命中跳過' '跳過'
  Assert 'h4_newformat_cache' 'exit 0' $script:rc
  # 釘死「每次呼叫都盤點」的核心保證：mutation 測試證明少了這兩條斷言，把盤點搬到 exit 0 之後仍全綠
  AssertMatch 'h4_newformat_cache' 'hit run 仍印能力面' '=== Codex worker 能力面'
  AssertMatch 'h4_newformat_cache' 'hit run 仍印 baseline 狀態' 'NO_BASELINE'
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

# --- B 系列：能力面 baseline diff（2026-07-16，Codex 諮詢兩輪定形：不自動建立/四態/被拒 exit 2）---
function t_b_no_autocreate_then_update {  # 無 baseline → NO_BASELINE 警示、絕不自動建立；-UpdateBaseline 是唯一建立途徑
  $script:currentTest = 'b_create'
  Setup; Run-Check @{ CODEX_STUB_PLUGINS = 'alpha' }
  Assert 'b_create' 'exit 0' $script:rc
  AssertMatch 'b_create' '警示 NO_BASELINE' 'NO_BASELINE'
  if (-not (Test-Path -LiteralPath (BaselineFile))) { Assert 'b_create' '未自動建立 baseline' 0 } else { Assert 'b_create' '未自動建立 baseline' 1 }
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha' }
  AssertMatch 'b_create' '-UpdateBaseline 建立成功' 'baseline 已更新'
  $raw = if (Test-Path -LiteralPath (BaselineFile)) { Get-Content -LiteralPath (BaselineFile) -Raw } else { '' }
  if ($raw -match '(?m)^plugins=alpha\s*$' -and $raw -match '(?m)^codex_version=0\.144\.1\s*$' -and $raw -match '(?m)^format=1\s*$') {
    Assert 'b_create' 'baseline 檔含 format/plugins/version' 0 } else { Assert 'b_create' 'baseline 檔含 format/plugins/version' 1 }
}
function t_b_no_drift {           # 同能力面 → 報無漂移
  $script:currentTest = 'b_no_drift'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha'; CODEX_STUB_FEATURES = 'hooks:true' }
  Run-Check @{ CODEX_STUB_PLUGINS = 'alpha'; CODEX_STUB_FEATURES = 'hooks:true' }
  AssertMatch 'b_no_drift' '報無漂移' '無漂移'
  AssertNoMatch 'b_no_drift' '不報漂移' '能力面漂移'
  Assert 'b_no_drift' 'exit 0' $script:rc
}
function t_b_drift_warns_no_rewrite {  # 漂移 → 醒目警示＋exit 0（姿態 A）＋絕不自動改寫 baseline
  $script:currentTest = 'b_drift'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha' }
  Run-Check @{ CODEX_STUB_PLUGINS = 'alpha,beta' }
  AssertMatch 'b_drift' '報漂移' '能力面漂移'
  AssertMatch 'b_drift' '列出新增 plugin' 'plugins \+: beta'
  Assert 'b_drift' '漂移仍 exit 0（提醒非閘門）' $script:rc
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^plugins=alpha\s*$') { Assert 'b_drift' 'baseline 未被自動改寫' 0 } else { Assert 'b_drift' 'baseline 未被自動改寫' 1 }
  Run-Check @{ CODEX_STUB_PLUGINS = 'alpha,beta' }   # 第三跑仍報漂移（證明沒有靜默接受）
  AssertMatch 'b_drift' '第三跑仍報漂移' '能力面漂移'
}
function t_b_update_baseline {    # -UpdateBaseline 更新後不再報漂移
  $script:currentTest = 'b_update'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha' }
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha,beta' }
  AssertMatch 'b_update' '印出已更新' 'baseline 已更新'
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^plugins=alpha,beta\s*$') { Assert 'b_update' 'baseline 已含 beta' 0 } else { Assert 'b_update' 'baseline 已含 beta' 1 }
  Run-Check @{ CODEX_STUB_PLUGINS = 'alpha,beta' }
  AssertMatch 'b_update' '更新後無漂移' '無漂移'
}
function t_b_empty_ambiguous_unknown {  # 盤點真空（rc=0 無輸出）但 baseline 非空 → UNKNOWN 歧義、不當 removed-all、不改 baseline
  $script:currentTest = 'b_empty_unknown'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha' }
  Run-Check @{}
  AssertMatch 'b_empty_unknown' '報空盤點歧義' '盤點為空但 baseline 有'
  AssertNoMatch 'b_empty_unknown' '不當 removed 漂移' 'plugins -: alpha'
  Assert 'b_empty_unknown' 'exit 0' $script:rc
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^plugins=alpha\s*$') { Assert 'b_empty_unknown' 'baseline 未變' 0 } else { Assert 'b_empty_unknown' 'baseline 未變' 1 }
}
function t_b_query_fail_unknown_update_refused {  # 查詢失敗段 → UNKNOWN；-UpdateBaseline 拒絕且 exit 2；失敗段不產 baseline
  $script:currentTest = 'b_fail_refused'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha' }
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_CAP_FAIL = 'features'; CODEX_STUB_PLUGINS = 'alpha,beta' }
  AssertMatch 'b_fail_refused' '報查詢失敗' '查詢失敗'
  AssertMatch 'b_fail_refused' '拒絕更新' '拒絕更新 baseline'
  if ($script:rc -eq 2) { Assert 'b_fail_refused' 'mutation 被拒 exit 2' 0 } else { Assert 'b_fail_refused' "mutation 被拒 exit 2（實際 $($script:rc)）" 1 }
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^plugins=alpha\s*$') { Assert 'b_fail_refused' 'baseline 未被失敗盤點蓋掉' 0 } else { Assert 'b_fail_refused' 'baseline 未被失敗盤點蓋掉' 1 }
  Setup; Run-Check @{ CODEX_STUB_CAP_FAIL = 'plugin' }   # 全新 home：查詢失敗＋無 baseline → 不產檔
  AssertMatch 'b_fail_refused' '報查詢失敗(首跑)' '查詢失敗'
  if (-not (Test-Path -LiteralPath (BaselineFile))) { Assert 'b_fail_refused' '首跑失敗不產 baseline' 0 } else { Assert 'b_fail_refused' '首跑失敗不產 baseline' 1 }
}
function t_b_unparseable_blocks_update {  # rc=0 有輸出但解析 0 筆 → UNPARSEABLE：不當漂移、-UpdateBaseline 拒絕 exit 2
  $script:currentTest = 'b_unparseable'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha' }
  Run-Check @{ CODEX_STUB_PLUGINS_GARBAGE = '1' }
  AssertMatch 'b_unparseable' '報 UNPARSEABLE' 'UNPARSEABLE'
  AssertNoMatch 'b_unparseable' '不當 removed 漂移' 'plugins -: alpha'
  Assert 'b_unparseable' 'exit 0（警示非閘門）' $script:rc
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS_GARBAGE = '1' }
  if ($script:rc -eq 2) { Assert 'b_unparseable' '解析失真拒更新 exit 2' 0 } else { Assert 'b_unparseable' "解析失真拒更新 exit 2（實際 $($script:rc)）" 1 }
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^plugins=alpha\s*$') { Assert 'b_unparseable' 'baseline 未被失真盤點洗白' 0 } else { Assert 'b_unparseable' 'baseline 未被失真盤點洗白' 1 }
}
function t_b_corrupt_baseline {   # baseline 檔格式壞 → 警示、不自動覆寫；-UpdateBaseline 才能重建
  $script:currentTest = 'b_corrupt'
  Setup; Set-Content -LiteralPath (BaselineFile) -Value 'this is junk not a baseline' -Encoding utf8
  Run-Check @{ CODEX_STUB_PLUGINS = 'alpha' }
  AssertMatch 'b_corrupt' '報格式不符' '格式不符'
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match 'this is junk') { Assert 'b_corrupt' '壞檔未被自動覆寫' 0 } else { Assert 'b_corrupt' '壞檔未被自動覆寫' 1 }
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha' }
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^format=1\s*$') { Assert 'b_corrupt' '-UpdateBaseline 重建成功' 0 } else { Assert 'b_corrupt' '-UpdateBaseline 重建成功' 1 }
}
function t_b_flag_missing_no_cache {  # skill 依賴旗標消失 → 醒目警示＋不寫 smoke 快取（不讓 24h 快取蓋掉不相容訊號）
  $script:currentTest = 'b_flag_missing'
  Setup; Run-Check @{ CODEX_STUB_HELP_DROP_FLAG = '--ephemeral' }
  AssertMatch 'b_flag_missing' '警示缺 --ephemeral' '依賴旗標不在 exec --help.*--ephemeral'
  AssertMatch 'b_flag_missing' '印出不寫快取' '不寫 24h 快取'
  if (-not (Test-Path -LiteralPath (CacheFile))) { Assert 'b_flag_missing' '快取未寫' 0 } else { Assert 'b_flag_missing' '快取未寫' 1 }
  Assert 'b_flag_missing' 'exit 0（警示非閘門）' $script:rc
}
function t_b_near_flag_not_matched {  # help 只有 --sandbox-policy（近似旗標）→ --sandbox 必須判缺（邊界比對不得誤中）
  $script:currentTest = 'b_near_flag'
  Setup; Run-Check @{ CODEX_STUB_HELP_NEARFLAG = '1' }
  AssertMatch 'b_near_flag' '--sandbox 判缺' '依賴旗標不在 exec --help: --sandbox($|[\s,])'
  Assert 'b_near_flag' 'exit 0' $script:rc
}
function t_b_version_empty_no_cache_hit {  # 版本解析不到 → 空==空也不許快取命中（身分未知不可背書）
  $script:currentTest = 'b_ver_empty'
  Setup; Invoke-Check -Mode force -Overrides @{ CODEX_STUB_VERSION = 'NONE' }
  Assert 'b_ver_empty' '首跑 exit 0' $script:rc
  Invoke-Check -Mode noforce -Overrides @{ CODEX_STUB_VERSION = 'NONE' }
  AssertMatch 'b_ver_empty' '不採信快取' '不採信快取'
  AssertMatch 'b_ver_empty' '跑了全檢' 'read-only smoke test'
}
function t_b_cache_version_mismatch_miss {  # 快取 <24h 但版本已變 → 當 miss 全檢；同版本回歸命中＋help 恰抓一次
  $script:currentTest = 'b_cache_vermiss'
  Setup; Invoke-Check -Mode force
  Invoke-Check -Mode noforce -Overrides @{ CODEX_STUB_VERSION = '0.145.0' }
  AssertMatch 'b_cache_vermiss' '報版本不符' '快取版本 0\.144\.1 與當前 0\.145\.0 不符'
  AssertMatch 'b_cache_vermiss' '跑了全檢' 'read-only smoke test'
  Assert 'b_cache_vermiss' '全檢成功 exit 0' $script:rc
  Invoke-Check -Mode noforce -Overrides @{ CODEX_STUB_VERSION = '0.145.0' }   # 新快取已寫 0.145.0 → 同版本命中
  AssertMatch 'b_cache_vermiss' '同版本回歸命中' '跳過'
  $helpCalls = @((Get-Content -LiteralPath $script:tracePath -ErrorAction SilentlyContinue) | Where-Object { $_ -match '^exec --help' }).Count
  if ($helpCalls -eq 1) { Assert 'b_cache_vermiss' 'exec --help 恰呼叫一次(hit)' 0 } else { Assert 'b_cache_vermiss' "exec --help 恰呼叫一次(hit)（實際 $helpCalls）" 1 }
  Invoke-Check -Mode force   # 全檢路徑也要恰一次（防 merge 復活 smoke 段的第二次抓取）
  $helpCalls = @((Get-Content -LiteralPath $script:tracePath -ErrorAction SilentlyContinue) | Where-Object { $_ -match '^exec --help' }).Count
  if ($helpCalls -eq 1) { Assert 'b_cache_vermiss' 'exec --help 恰呼叫一次(full)' 0 } else { Assert 'b_cache_vermiss' "exec --help 恰呼叫一次(full)（實際 $helpCalls）" 1 }
}
function t_b_probe_stderr_immune {  # 升級後子命令印 stderr 噪音 → 盤點不得炸成 FAILED（4c3d477 同型地雷回歸案）
  $script:currentTest = 'b_stderr_immune'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha'; CODEX_STUB_LIST_STDERR = '1'; CODEX_STUB_HELP_STDERR = '1' }
  Assert 'b_stderr_immune' 'stderr 噪音下 -UpdateBaseline 成功 exit 0' $script:rc
  AssertNoMatch 'b_stderr_immune' '無查詢失敗' '查詢失敗'
  AssertMatch 'b_stderr_immune' 'baseline 已寫' 'UPDATE_BASELINE=OK'
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^plugins=alpha\s*$') { Assert 'b_stderr_immune' 'baseline 內容正確' 0 } else { Assert 'b_stderr_immune' 'baseline 內容正確' 1 }
}
function t_b_boilerplate_zero_is_empty {  # 乾淨機器（零外掛/零 MCP boilerplate 訊息）→ EMPTY 而非 UNPARSEABLE，baseline 建得起來
  $script:currentTest = 'b_boilerplate'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_LIST_BOILERPLATE = '1' }
  Assert 'b_boilerplate' '乾淨機器可建 baseline exit 0' $script:rc
  AssertNoMatch 'b_boilerplate' '無 UNPARSEABLE 誤判' 'UNPARSEABLE'
  AssertMatch 'b_boilerplate' 'baseline 已寫' 'UPDATE_BASELINE=OK'
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^plugins=\s*$' -and $raw -match '(?m)^mcp=\s*$') { Assert 'b_boilerplate' '空段落如實寫入' 0 } else { Assert 'b_boilerplate' '空段落如實寫入' 1 }
}
function t_b_mcp_drift_and_fail {  # mcp 段：正常解析、漂移偵測、查詢失敗三態
  $script:currentTest = 'b_mcp'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_MCP = 'srv1:enabled' }
  Run-Check @{ CODEX_STUB_MCP = 'srv1:enabled,srv2:disabled' }
  AssertMatch 'b_mcp' '偵測到新 server' 'mcp \+: srv2\[disabled\]'
  Run-Check @{ CODEX_STUB_CAP_FAIL = 'mcp'; CODEX_STUB_MCP = 'srv1:enabled' }
  AssertMatch 'b_mcp' 'mcp 查詢失敗' 'MCP servers: \(查詢失敗\)'
  Assert 'b_mcp' 'exit 0（警示非閘門）' $script:rc
}
function t_b_mcp_all_unknown_unparseable {  # mcp state 全 '?' ＝格式失真 → UNPARSEABLE、拒更新 exit 2
  $script:currentTest = 'b_mcp_unk'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_MCP = 'srv1:enabled' }
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_MCP = 'srv1:weird,srv2:strange' }
  if ($script:rc -eq 2) { Assert 'b_mcp_unk' '全 ? 拒更新 exit 2' 0 } else { Assert 'b_mcp_unk' "全 ? 拒更新 exit 2（實際 $($script:rc)）" 1 }
  AssertMatch 'b_mcp_unk' '報 REFUSED' 'UPDATE_BASELINE=REFUSED'
  $raw = Get-Content -LiteralPath (BaselineFile) -Raw
  if ($raw -match '(?m)^mcp=srv1\[enabled\]\s*$') { Assert 'b_mcp_unk' 'baseline 未被失真盤點洗白' 0 } else { Assert 'b_mcp_unk' 'baseline 未被失真盤點洗白' 1 }
}
function t_b_marketplace_identity_drift {  # 同名外掛換 marketplace（供應鏈識別變更）→ 必須呈現為漂移
  $script:currentTest = 'b_mkt_identity'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha@m1' }
  Run-Check @{ CODEX_STUB_PLUGINS = 'alpha@m2' }
  AssertMatch 'b_mkt_identity' '新識別 +' 'plugins \+: alpha@m2'
  AssertMatch 'b_mkt_identity' '舊識別 -' 'plugins -: alpha@m1'
}
function t_b_hooks_unparseable {  # config 有 hooks.state 但序列化格式變（單引號鍵）→ UNPARSEABLE、拒更新（hooks 洗白代價最高）
  $script:currentTest = 'b_hooks_unp'
  Setup
  $codexDir = Join-Path $script:fakeHome '.codex'
  New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $codexDir 'config.toml') -Value "[hooks.state.'myhook:abc123']`r`ntrusted = true" -Encoding utf8
  Run-Check @{ CODEX_STUB_PLUGINS = 'alpha' }
  AssertMatch 'b_hooks_unp' 'hooks 報 UNPARSEABLE' '受信任 hooks: \(UNPARSEABLE'
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_PLUGINS = 'alpha' }
  if ($script:rc -eq 2) { Assert 'b_hooks_unp' 'hooks 失真拒更新 exit 2' 0 } else { Assert 'b_hooks_unp' "hooks 失真拒更新 exit 2（實際 $($script:rc)）" 1 }
}
function t_b_flag_incompat_cache_not_trusted {  # 命中側對稱守衛：本次盤點旗標不相容 → 舊綠快取不採信
  $script:currentTest = 'b_flag_nohit'
  Setup; Invoke-Check -Mode force
  Invoke-Check -Mode noforce -Overrides @{ CODEX_STUB_HELP_DROP_FLAG = '--ephemeral' }
  AssertMatch 'b_flag_nohit' '不採信快取' '依賴旗標相容性未確立 → 不採信快取'
  AssertMatch 'b_flag_nohit' '跑了全檢' 'read-only smoke test'
  Assert 'b_flag_nohit' 'exit 0' $script:rc
}

# --- CODEX-CHECK-CP437（2026-10-17）：child 以 code page 437（en-US 主控台）起跑，中文經 pipe 仍須完整 ---
# 舊版 SUT 沒有設輸出編碼 ⇒ 依 437 編碼，'能力面（唯讀盤點）' 變成 '???(????)'。這兩案在案內自行切 437，
# 與環境 code page 無關，所以在 65001 的 CI 上也能確定性地抓到舊版。只挑兩條有代表性的路徑（全檢、快取命中），
# 不把整套翻倍；在非 UTF-8 主控台本機跑時，其餘各案本來就以環境 code page 起跑（見檔尾主 try 的註解）。
function Assert-Cp437Premise([string]$name, [bool]$ok, [string]$label) {
  # 前提沒成立（chcp 失敗、實量不是 437、沒有 console）時本案量不到東西 —— 必須紅，不可空轉成綠。
  if ($ok) { Assert $name ('前提：' + $label + ' 啟動前共用 console 的 output code page 實量為 437') 0 }
  else { Assert $name ('前提：' + $label + ' 切不到 code page 437（chcp 失敗或實量不符；沒有 console？）—— 本案量不到東西') 1 }
}
function t_console_cp437_utf8 {  # 全檢路徑：SUT 最早的兩個輸出點（stdout 的能力面標題、NO_BASELINE 診斷）
  $script:currentTest = 'cp437_utf8'
  Setup
  $prevCp = $script:sutConsoleCp; $script:sutConsoleCp = 437
  try { Run-Check @{} } finally { $script:sutConsoleCp = $prevCp }
  Assert-Cp437Premise 'cp437_utf8' $script:sutCpOk '全檢'
  Assert 'cp437_utf8' 'exit 0' $script:rc
  AssertMatch 'cp437_utf8' '中文完整：能力面標題（stdout）' '(?m)^=== Codex worker 能力面（唯讀盤點）===\r?$'
  # 不綁 WARNING:／警告: 前綴（pwsh 會依 UI 語系翻譯；CODEX-CHECK-WARNING 之後也不再走 warning stream）
  AssertMatch 'cp437_utf8' '中文完整：NO_BASELINE 診斷' 'NO_BASELINE -- 尚無能力面 baseline'
}
function t_console_cp437_cache_hit {  # 快取命中路徑（另一個 exit 0 出口）＋快取內容回顯的中文 verdict
  $script:currentTest = 'cp437_cache_hit'
  Setup
  $prevCp = $script:sutConsoleCp; $script:sutConsoleCp = 437
  $firstOk = $false; $firstRc = -1
  try {
    Run-Check @{ NPM_STUB_MODE = 'fail' }   # 離線 → verdict 是含中文的 UNKNOWN，連同 smoke=OK 寫進快取
    $firstOk = $script:sutCpOk; $firstRc = $script:rc
    Invoke-Check -Mode noforce -Overrides @{ NPM_STUB_MODE = 'fail' }
  } finally { $script:sutConsoleCp = $prevCp }
  Assert-Cp437Premise 'cp437_cache_hit' $firstOk '建快取的全檢'
  Assert-Cp437Premise 'cp437_cache_hit' $script:sutCpOk '快取命中的那一跑'
  Assert 'cp437_cache_hit' '建快取 exit 0' $firstRc
  Assert 'cp437_cache_hit' '快取命中 exit 0' $script:rc
  AssertMatch 'cp437_cache_hit' '中文完整：快取命中行' '(?m)^codex-check: \d+h 前查過，跳過（-f 強制重查）。上次結果：\r?$'
  AssertMatch 'cp437_cache_hit' '中文完整：快取回顯的 verdict' 'verdict=UNKNOWN \(latest 查不到，可能離線\) -- 無法判定新舊，改看下方 smoke test 認定可用性 smoke=OK at '
}

# --- P 系列：呼叫端 preference 外洩與診斷 best-effort（CODEX-CHECK-WARNING，2026-10-17）---
# 舊版：Write-Warning 在 $WarningPreference='Stop' 下變終止性例外（:275／:296／:300／:520／:522，HEAD 040b344 行號）；
# smoke 的 native 非零退出在 ${PSNativeCommandUseErrorActionPreference}=${true}（pwsh 7.3+）＋本 SUT 檔頭 EAP=Stop 下，
# 於擷取 rc 之前丟 NativeCommandExitException（:475）。
# ⚠️ Native 案的牙齒只在 -Shell pwsh 腿（5.1 沒有這個 preference，新舊版都綠）；Warn 案兩條腿都有牙齒。
# ⚠️ 等價變異（2026-10-17 實測，寫明以免被讀成「每一行都有牙齒」）：SUT capture scope 裡的
#    `$ErrorActionPreference = 'Continue'` 拿掉之後，本檔全部照樣綠 —— smoke 的 stderr 已在 cmd 層合流，
#    5.1 的 NativeCommandError 路徑目前碰不到。保留它只是為了與 consult／exec 的模式一致，額外防禦未被證明。
#    同理，「診斷排在刪快取／哨兵之後」這個**順序**在 t_p_broken_stderr_failure_state 的注入下也是等價變異
#    （best-effort 的 try/catch 已經吞掉例外）；順序是為 writer 卡住或行程被殺的情況保底，同樣未被證明。
function Test-NoPrefLeak([string]$name) {
  # Invoke-Check 已把 child 的 stderr ErrorRecord 還原成原始行，所以 runner 端不會再冒出 NativeCommandError 標記；
  # 這裡出現的 NativeCommandError 只可能來自 SUT 自己（5.1 把 native stderr 包成 ErrorRecord 的那條路）。
  AssertNoMatch $name '不得洩漏 preference／native 例外文字' 'WarningPreference|ActionPreferenceStopException|NativeCommandExitException|NativeCommandError'
}
function Seed-GreenCache([string]$name) {
  Invoke-Check -Mode force
  if (($script:rc -eq 0) -and (Test-Path -LiteralPath (CacheFile))) { Assert $name '前置：綠快取已建立' 0 } else { Assert $name "前置：綠快取已建立（rc=$($script:rc)）" 1 }
}
function Assert-NoStaleCacheHit([string]$name) {
  # 壞快取若沒刪，下一次非 -Force 會命中舊綠快取、把剛壞掉的 codex 報成可用
  Invoke-Check -Mode noforce
  AssertMatch $name '下一次非 -Force 走全檢（壞快取已刪）' 'read-only smoke test'
  AssertNoMatch $name '下一次非 -Force 不得命中舊綠快取' '跳過（-f 強制重查）'
}
function t_p_warn_refused_marker {   # :275 → REFUSED 哨兵與 exit 2 必須都在
  $script:currentTest = 'p_warn_refused'
  Setup; Invoke-Check -Mode update -Overrides @{ CODEX_STUB_CAP_FAIL = 'features' } -Prefs @{ Warn = 'Stop' }
  if ($script:rc -eq 2) { Assert 'p_warn_refused' 'W=Stop 下被拒仍 exit 2' 0 } else { Assert 'p_warn_refused' "W=Stop 下被拒仍 exit 2（實際 $($script:rc)）" 1 }
  AssertMatch 'p_warn_refused' 'REFUSED 哨兵仍在' '(?m)^UPDATE_BASELINE=REFUSED\r?$'
  AssertMatch 'p_warn_refused' '拒絕理由仍印出' '拒絕更新 baseline'
  if (-not (Test-Path -LiteralPath (BaselineFile))) { Assert 'p_warn_refused' '未產 baseline' 0 } else { Assert 'p_warn_refused' '未產 baseline' 1 }
  Test-NoPrefLeak 'p_warn_refused'
}
function t_p_warn_no_baseline_smoke_runs {   # :296 → 首次安裝（無 baseline）smoke 仍要跑
  $script:currentTest = 'p_warn_nobl'
  Setup; Invoke-Check -Mode force -Prefs @{ Warn = 'Stop' }
  Assert 'p_warn_nobl' 'W=Stop 下無 baseline 仍 exit 0' $script:rc
  AssertMatch 'p_warn_nobl' 'NO_BASELINE 仍印出' 'NO_BASELINE'
  AssertMatch 'p_warn_nobl' 'smoke 有跑' 'read-only smoke test'
  if (Test-Path -LiteralPath (CacheFile)) { Assert 'p_warn_nobl' '快取寫入' 0 } else { Assert 'p_warn_nobl' '快取寫入' 1 }
  Test-NoPrefLeak 'p_warn_nobl'
}
function t_p_warn_corrupt_baseline_smoke_runs {   # :300 → 壞 baseline 時 smoke 仍要跑、壞檔不覆寫
  $script:currentTest = 'p_warn_corrupt'
  Setup; Set-Content -LiteralPath (BaselineFile) -Value 'this is junk not a baseline' -Encoding utf8
  Invoke-Check -Mode force -Prefs @{ Warn = 'Stop' }
  Assert 'p_warn_corrupt' 'W=Stop 下壞 baseline 仍 exit 0' $script:rc
  AssertMatch 'p_warn_corrupt' '格式不符仍印出' '格式不符'
  AssertMatch 'p_warn_corrupt' 'smoke 有跑' 'read-only smoke test'
  if ((Get-Content -LiteralPath (BaselineFile) -Raw) -match 'this is junk') { Assert 'p_warn_corrupt' '壞檔未被覆寫' 0 } else { Assert 'p_warn_corrupt' '壞檔未被覆寫' 1 }
  Test-NoPrefLeak 'p_warn_corrupt'
}
function t_p_warn_smoke_fail_deletes_cache {   # :522 → smoke 失敗：rc 原樣、刪快取、NOT_APPLIED
  $script:currentTest = 'p_warn_smokefail'
  Setup; Seed-GreenCache 'p_warn_smokefail'
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_EXEC_RC = '7' } -Prefs @{ Warn = 'Stop' }
  if ($script:rc -eq 7) { Assert 'p_warn_smokefail' 'smoke rc 原樣傳回 7（不是 1）' 0 } else { Assert 'p_warn_smokefail' "smoke rc 原樣傳回 7（實際 $($script:rc)）" 1 }
  AssertMatch 'p_warn_smokefail' '失敗診斷仍印出' 'smoke test failed \(exit 7\)'
  AssertMatch 'p_warn_smokefail' 'NOT_APPLIED 哨兵仍在' '(?m)^UPDATE_BASELINE=NOT_APPLIED'
  if (-not (Test-Path -LiteralPath (CacheFile))) { Assert 'p_warn_smokefail' '壞快取已刪' 0 } else { Assert 'p_warn_smokefail' '壞快取已刪' 1 }
  if (-not (Test-Path -LiteralPath (BaselineFile))) { Assert 'p_warn_smokefail' 'baseline 未落檔' 0 } else { Assert 'p_warn_smokefail' 'baseline 未落檔' 1 }
  Test-NoPrefLeak 'p_warn_smokefail'
  Assert-NoStaleCacheHit 'p_warn_smokefail'
}
function t_p_warn_nosentinel_deletes_cache {   # :520 → exit 0 無 sentinel：rc 1、刪快取（rc 新舊都是 1，牙齒在快取與診斷）
  $script:currentTest = 'p_warn_nosentinel'
  Setup; Seed-GreenCache 'p_warn_nosentinel'
  Invoke-Check -Mode force -Overrides @{ CODEX_STUB_LASTMSG = 'NOT_CODEX_OK' } -Prefs @{ Warn = 'Stop' }
  if ($script:rc -eq 1) { Assert 'p_warn_nosentinel' 'exit 1' 0 } else { Assert 'p_warn_nosentinel' "exit 1（實際 $($script:rc)）" 1 }
  AssertMatch 'p_warn_nosentinel' '無 sentinel 診斷仍印出' '無精確 CODEX_OK sentinel'
  if (-not (Test-Path -LiteralPath (CacheFile))) { Assert 'p_warn_nosentinel' '壞快取已刪' 0 } else { Assert 'p_warn_nosentinel' '壞快取已刪' 1 }
  Test-NoPrefLeak 'p_warn_nosentinel'
  Assert-NoStaleCacheHit 'p_warn_nosentinel'
}
function t_p_native_smoke_fail_keeps_rc {   # :475 → native=true：rc 原樣（23，非 1）、刪快取、NOT_APPLIED
  $script:currentTest = 'p_native_smokefail'
  Setup; Seed-GreenCache 'p_native_smokefail'
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_EXEC_RC = '23' } -Prefs @{ Native = 'true' }
  if ($script:rc -eq 23) { Assert 'p_native_smokefail' 'smoke rc 原樣傳回 23（不是 1）' 0 } else { Assert 'p_native_smokefail' "smoke rc 原樣傳回 23（實際 $($script:rc)）" 1 }
  AssertMatch 'p_native_smokefail' 'smoke transcript 有回顯' 'SIMULATED_SMOKE_FAILURE'
  AssertMatch 'p_native_smokefail' '失敗診斷仍印出' 'smoke test failed \(exit 23\)'
  AssertMatch 'p_native_smokefail' 'NOT_APPLIED 哨兵仍在' '(?m)^UPDATE_BASELINE=NOT_APPLIED'
  if (-not (Test-Path -LiteralPath (CacheFile))) { Assert 'p_native_smokefail' '壞快取已刪' 0 } else { Assert 'p_native_smokefail' '壞快取已刪' 1 }
  Test-NoPrefLeak 'p_native_smokefail'
  Assert-NoStaleCacheHit 'p_native_smokefail'
}
function t_p_all_stop_smoke_fail {   # 兩個都開（最壞呼叫端）：兩條腿對舊版都有牙齒
  $script:currentTest = 'p_allstop_smokefail'
  Setup; Seed-GreenCache 'p_allstop_smokefail'
  Invoke-Check -Mode force -Overrides @{ CODEX_STUB_EXEC_RC = '7' } -Prefs @{ Warn = 'Stop'; Native = 'true' }
  if ($script:rc -eq 7) { Assert 'p_allstop_smokefail' 'smoke rc 原樣傳回 7' 0 } else { Assert 'p_allstop_smokefail' "smoke rc 原樣傳回 7（實際 $($script:rc)）" 1 }
  if (-not (Test-Path -LiteralPath (CacheFile))) { Assert 'p_allstop_smokefail' '壞快取已刪' 0 } else { Assert 'p_allstop_smokefail' '壞快取已刪' 1 }
  Test-NoPrefLeak 'p_allstop_smokefail'
}
function t_p_native_success_unaffected {   # native=true 但 smoke 成功：行為不變（回歸）
  $script:currentTest = 'p_native_ok'
  Setup; Invoke-Check -Mode force -Prefs @{ Warn = 'Stop'; Native = 'true' }
  Assert 'p_native_ok' 'exit 0' $script:rc
  AssertMatch 'p_native_ok' 'verdict UP-TO-DATE' 'UP-TO-DATE'
  if (Test-Path -LiteralPath (CacheFile)) { Assert 'p_native_ok' '快取寫入' 0 } else { Assert 'p_native_ok' '快取寫入' 1 }
  Test-NoPrefLeak 'p_native_ok'
}
function t_p_broken_stderr_failure_state {   # 診斷 writer 本身丟例外（stderr 壞掉）：失敗狀態與哨兵仍須完成
  # 牙齒對象是「改走 [Console]::Error 但寫入沒有 best-effort」的版本（10/17 設計原型即如此：診斷排在刪快取之前、
  # 沒有 try/catch）。舊版 SUT（Write-Warning）不經 [Console]::Error，本案對它是綠的 —— 舊版的缺陷由上面各 P 案抓。
  $script:currentTest = 'p_broken_stderr'
  Setup; Seed-GreenCache 'p_broken_stderr'
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_EXEC_RC = '7' } -Prefs @{ ErrBroken = '1' }
  if ($script:rc -eq 7) { Assert 'p_broken_stderr' 'smoke 失敗：rc 原樣傳回 7' 0 } else { Assert 'p_broken_stderr' "smoke 失敗：rc 原樣傳回 7（實際 $($script:rc)）" 1 }
  AssertMatch 'p_broken_stderr' 'smoke 失敗：NOT_APPLIED 哨兵仍在' '(?m)^UPDATE_BASELINE=NOT_APPLIED'
  if (-not (Test-Path -LiteralPath (CacheFile))) { Assert 'p_broken_stderr' 'smoke 失敗：壞快取已刪' 0 } else { Assert 'p_broken_stderr' 'smoke 失敗：壞快取已刪' 1 }
  if (-not (Test-Path -LiteralPath (BaselineFile))) { Assert 'p_broken_stderr' 'smoke 失敗：baseline 未落檔' 0 } else { Assert 'p_broken_stderr' 'smoke 失敗：baseline 未落檔' 1 }
  Invoke-Check -Mode update -Overrides @{ CODEX_STUB_CAP_FAIL = 'features' } -Prefs @{ ErrBroken = '1' }
  if ($script:rc -eq 2) { Assert 'p_broken_stderr' '被拒：仍 exit 2' 0 } else { Assert 'p_broken_stderr' "被拒：仍 exit 2（實際 $($script:rc)）" 1 }
  AssertMatch 'p_broken_stderr' '被拒：REFUSED 哨兵仍在' '(?m)^UPDATE_BASELINE=REFUSED\r?$'
  Invoke-Check -Mode force -Prefs @{ ErrBroken = '1' }   # 無 baseline：NO_BASELINE 診斷寫不出去，smoke 仍要跑
  Assert 'p_broken_stderr' '無 baseline：仍 exit 0' $script:rc
  AssertMatch 'p_broken_stderr' '無 baseline：smoke 有跑' 'read-only smoke test'
  if (Test-Path -LiteralPath (CacheFile)) { Assert 'p_broken_stderr' '無 baseline：快取寫入' 0 } else { Assert 'p_broken_stderr' '無 baseline：快取寫入' 1 }
}
function t_p_no_write_warning_ast {   # 靜態守衛：SUT 不得有靜態可解析的 Write-Warning（動態命令名/$PSCmdlet.WriteWarning 抓不到）
  $script:currentTest = 'p_no_ww_ast'
  $perr = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile([System.IO.Path]::GetFullPath($script:sut), [ref]$null, [ref]$perr)
  if (($null -eq $perr) -or ($perr.Count -eq 0)) { Assert 'p_no_ww_ast' 'SUT 無 parse error' 0 } else { Assert 'p_no_ww_ast' "SUT 有 $($perr.Count) 個 parse error" 1 }
  $hits = @()
  if ($ast) {
    foreach ($c in @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true))) {
      $nm = $c.GetCommandName(); if (-not $nm) { continue }
      if ((($nm -split '\\')[-1]) -ieq 'Write-Warning') { $hits += ('L' + $c.Extent.StartLineNumber) }
    }
  }
  if ($hits.Count -eq 0) { Assert 'p_no_ww_ast' 'SUT 無 Write-Warning（0 處）' 0 } else { Assert 'p_no_ww_ast' ('SUT 有 Write-Warning ' + $hits.Count + ' 處（' + ($hits -join ',') + '）；改用 [Console]::Error.WriteLine') 1 }
}

$allTests = @(
  't_happy_path','t_offline_unknown','t_fake_pass_rejected','t_ansi_stripped',
  't_h1_leading_warning','t_h1_warning_has_version','t_h1_no_version',
  't_h5_multiline','t_h5_blank_second_line','t_h5_junk','t_h5_prerelease_current',
  't_h3_npm_hang','t_h3_partial_stdout_discarded','t_h3_print_then_fail',
  't_h4_empty_cache_miss','t_h4_oldformat_cache_miss','t_h4_truncated_line_miss','t_h4_future_mtime_miss','t_h4_newformat_cache_hit',
  't_h2_exact_ok','t_h2_not_ok_rejected','t_h2_refusal_rejected','t_h2_no_flag_when_unsupported',
  't_h4_missing_latest_field','t_h4_missing_verdict_field','t_h2_large_help_keeps_lastmsg','t_h1_huge_banner_no_crash',
  't_smoke_stderr_noise_no_crash',
  't_b_no_autocreate_then_update','t_b_no_drift','t_b_drift_warns_no_rewrite','t_b_update_baseline',
  't_b_empty_ambiguous_unknown','t_b_query_fail_unknown_update_refused','t_b_unparseable_blocks_update','t_b_corrupt_baseline',
  't_b_flag_missing_no_cache','t_b_near_flag_not_matched','t_b_version_empty_no_cache_hit','t_b_cache_version_mismatch_miss',
  't_b_probe_stderr_immune','t_b_boilerplate_zero_is_empty','t_b_mcp_drift_and_fail','t_b_mcp_all_unknown_unparseable',
  't_b_marketplace_identity_drift','t_b_hooks_unparseable','t_b_flag_incompat_cache_not_trusted',
  't_console_cp437_utf8','t_console_cp437_cache_hit',
  't_p_warn_refused_marker','t_p_warn_no_baseline_smoke_runs','t_p_warn_corrupt_baseline_smoke_runs',
  't_p_warn_smoke_fail_deletes_cache','t_p_warn_nosentinel_deletes_cache','t_p_native_smoke_fail_keeps_rc',
  't_p_all_stop_smoke_fail','t_p_native_success_unaffected','t_p_broken_stderr_failure_state','t_p_no_write_warning_ast'
)

# 受測 host 自檢：真的用 $script:sutExe 跑一支探針，讓 child 自報 PSEdition／PSVersion。
# 用探針檔而非 -Command：WinPS 5.1 傳給 native 的引數若含雙引號會被拆壞（-Command 字串很容易踩到）。
# 回傳 $true ＝ child 確實是 -Shell 宣稱的那個 host。
function Test-SutHost {
  $probe = Join-Path $stubRoot 'sut-host-probe.ps1'
  [System.IO.File]::WriteAllText($probe, ('$PSVersionTable.PSEdition' + "`r`n" + '$PSVersionTable.PSVersion.ToString()' + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $global:LASTEXITCODE = $null
  $lines = @(Invoke-SutProcess $probe | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  $probeRc = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  $edition = if ($lines.Count -ge 1) { $lines[0] } else { '?' }
  $version = if ($lines.Count -ge 2) { $lines[1] } else { '?' }
  Write-Output ("runner host = " + $PSVersionTable.PSEdition + " " + $PSVersionTable.PSVersion.ToString() + " / -Shell = " + $Shell)
  Write-Output ("CODEX-CHECK-SUT-HOST=" + $Shell + " " + $edition + " " + $version + " path=" + $script:sutExe)
  $major = -1
  try { $major = ([version]$version).Major } catch { $major = -1 }
  $ok = ($probeRc -eq 0) -and $(if ($Shell -eq 'pwsh') { ($edition -eq 'Core') -and ($major -ge 7) } else { ($edition -eq 'Desktop') -and ($major -eq 5) })
  if ($ok) { Assert 'sut_host' ("受測 host 自報 " + $edition + " " + $version + " 與 -Shell " + $Shell + " 相符") 0 }
  else { Assert 'sut_host' ("受測 host 自報 " + $edition + " " + $version + "（rc=" + $probeRc + "）與 -Shell " + $Shell + " 不符") 1 }
  return $ok
}

# AST 守衛：SUT 只能經 Invoke-SutProcess 啟動（否則 host 自檢與案例走不同路徑，自檢就不是證據）。
function Test-SutLaunchSite {
  $tok = $null; $perr = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:testsFile, [ref]$tok, [ref]$perr)
  $cmds = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
  $bad = @()
  foreach ($c in $cmds) {
    $inHelper = $false; $p = $c.Parent
    while ($p) { if (($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($p.Name -eq 'Invoke-SutProcess')) { $inHelper = $true; break }; $p = $p.Parent }
    if ($inHelper) { continue }
    $nm = [string]$c.GetCommandName()
    $dyn = $c.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst]
    $hasFile = @($c.CommandElements | Where-Object { ($_ -is [System.Management.Automation.Language.CommandParameterAst]) -and ($_.ParameterName -eq 'File') }).Count -gt 0
    if (($nm -match '^(?i)(powershell|pwsh)(\.exe)?$') -or ($dyn -and $hasFile)) { $bad += ('L' + $c.Extent.StartLineNumber + ' ' + $c.Extent.Text) }
  }
  $via = @($cmds | Where-Object { $_.GetCommandName() -eq 'Invoke-SutProcess' }).Count
  if (($bad.Count -eq 0) -and ($via -eq 2)) { Assert 'sut_launch_site' 'SUT 只經 Invoke-SutProcess 啟動（案例與 host 自檢同一路徑）' 0 }
  else { Assert 'sut_launch_site' ('SUT 啟動點不唯一 via=' + $via + ' ' + ($bad -join ' | ')) 1 }
}

try {
  # ── CODEX-CHECK-CP437：console code page（記錄、設定、還原都在本 try／finally 之內）────────────────
  # SUT 的輸出契約是 UTF-8（codex-check.ps1 檔頭）⇒ runner 一律以 UTF-8 解碼 child 輸出。
  # ⚠️ 這個 setter 會呼叫 SetConsoleOutputCP，把共用 console 切到 65001 —— 所以 child 的起跑 code page
  #    由 Invoke-SutProcess 每次明確切回 ${script:sutConsoleCp}：預設是這裡記下的**環境值**（CI／維護機是 65001；
  #    在非 UTF-8 主控台本機跑時，既有各案也照樣在該 code page 下跑），437 由 t_console_cp437_* 案內指定。
  # ⚠️ 必須在本 try 之內：放在檔頭的話，找不到受測 host 的 exit 2 等提前結束會跳過 finally 的還原。
  $script:origOutEnc = [Console]::OutputEncoding
  $script:origInEnc  = [Console]::InputEncoding
  try {
    if (-not ('CodexCheckTests.ConsoleCp' -as [type])) {
      Add-Type -Namespace CodexCheckTests -Name ConsoleCp -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern uint GetConsoleOutputCP();'
    }
  } catch { Write-Output ("note: 無法載入 GetConsoleOutputCP（" + $_.Exception.Message + "）—— code page 案的前提會紅") }
  $script:envConsoleCp = Get-ConsoleOutputCp
  if (-not $script:envConsoleCp) { $script:envConsoleCp = $script:origOutEnc.CodePage }
  $script:sutConsoleCp = $script:envConsoleCp
  try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}
  Write-Output ("console code page = " + $script:envConsoleCp + "（環境值；既有各案的 child 以它起跑）；runner 以 UTF-8 解碼 child 輸出")

  Assert-Bom $script:sut 'SUT'           # 檔頭 BOM 斷言（SUT 與 tests）
  Assert-Bom $script:testsFile 'tests'
  $sutHostOk = $false
  # Test-SutHost 會 Write-Output 兩行證據再回傳布林：最後一個物件才是判定。
  Test-SutHost | ForEach-Object { if ($_ -is [bool]) { $sutHostOk = $_ } else { Write-Output $_ } }
  Test-SutLaunchSite
  $sel = if ($Tests.Count -gt 0) { $Tests } else { $allTests }
  # host 不對時跑案例沒有意義（量到的是別的 host）—— 直接停在這裡，TOTAL 會帶著那一條 FAIL。
  if (-not $sutHostOk) { $sel = @() }
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
  # CODEX-CHECK-CP437：還原 runner 的 console 編碼。setter 會連共用 console 的 code page 一起改回
  # （chcp 改過 input code page，所以 InputEncoding 也要還原）。
  if ($script:origOutEnc) { try { [Console]::OutputEncoding = $script:origOutEnc } catch {} }
  if ($script:origInEnc)  { try { [Console]::InputEncoding  = $script:origInEnc } catch {} }
}
if ($script:fails -gt 0) { exit 1 } else { exit 0 }
