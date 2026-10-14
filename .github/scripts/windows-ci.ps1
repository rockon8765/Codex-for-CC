# windows-ci.ps1 -- .github/workflows/windows.yml 專用的 CI 輔助腳本。
#
# ⚠️ 這支**不屬於 skill payload**（不會被 AI-INSTALL 複製到 ~/.claude），只給 GitHub Actions 用。
#    它也是 .ps1 ⇒ 依 .gitattributes 維持 CRLF，並且必須是 UTF-8 with BOM（5.1 讀無 BOM 的含中文 .ps1 會亂碼）。
#    Lint 動作會檢查包含本檔在內的所有 tracked .ps1。
#
# 為什麼把邏輯放這裡而不是寫在 YAML 的 run 區塊：
#   1. run 區塊刻意保持 **ASCII-only**。runner 把 run 區塊寫成暫存 .ps1 再交給 host 執行，
#      Windows PowerShell 5.1 讀那個檔時的編碼本 repo 沒有實測過；中文路徑（超級模式）一律
#      從 workflow 的 env 或本檔取得，不出現在 run 區塊。
#   2. 每一支測試都要經過同一套「啟動 → 收集 → 精確比對 marker」流程（Run 動作），
#      不讓各 step 各寫一份、各自漏掉 exit code 或 marker 其中一個。
#   3. 守衛（金絲雀 codex、~/.claude 斷言）三個 job 都要，集中在這裡才不會漂移。
#
# 動作（-Action）：
#   InstallCanary  在 C:\npm\codex.cmd 與 PATH 最前面各放一支會「大聲失敗」的假 codex，並先自我測試。
#                  ⚠️ 只在 GitHub Actions 上執行；本機執行會被拒絕（否則會蓋掉維護者真的 codex）。
#   Preflight      斷言 ~/.claude 不存在、PATH 上第一個 codex 是金絲雀。
#   Postflight     斷言金絲雀沒被叫到、金絲雀檔案未被改動、~/.claude 仍不存在。
#   Evidence       把 OS build、ImageOS、ImageVersion、pwsh／WinPS／node 版本、code page、TEMP 短名、
#                  8dot3 狀態等寫進 <證據目錄>\env-<Name>.txt（由 YAML 上傳成 artifact）。
#   Lint           所有 tracked .ps1：目前 host 的 parser 0 error、含非 ASCII 者必須有 UTF-8 BOM、行尾全為 CRLF；
#                  另外 node --check windows/ 底下的 hook 與 lib。YAML 分別在 pwsh 與 5.1 各跑一次。
#   Run            以 -Exe／-ArgList 啟動一支測試，輸出逐行印進 log 並存檔；要求 exit 0、
#                  每個 -Require（多行模式 regex）都命中、每個 -Forbid 都不命中。
#   Mutate8dot3    8.3 短名的變異注入：拿掉 hook 的 realpathSync.native，class-b-8dot3 必須變紅。
#
# 5.1 相容：Lint 會在 Windows PowerShell 5.1 下執行本檔，所以不用 `??`、三元運算子等 7.x 語法。
[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('InstallCanary', 'Preflight', 'Postflight', 'Evidence', 'Lint', 'Run', 'Mutate8dot3')]
  [string]$Action,
  [string]$Name = '',
  [string]$Exe = '',
  [string[]]$ArgList = @(),
  [string[]]$Require = @(),
  [string[]]$Forbid = @()
)

$ErrorActionPreference = 'Stop'
$script:repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:isCi = ($env:GITHUB_ACTIONS -eq 'true')

function Get-TempRoot {
  if ($env:RUNNER_TEMP) { return $env:RUNNER_TEMP }
  return [System.IO.Path]::GetTempPath()
}
function Get-EvidenceDir {
  $d = Join-Path (Get-TempRoot) 'ci-evidence'
  if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  return $d
}
function Fail([string]$msg) {
  # ::error:: 讓 GitHub 在摘要頁標紅；本機執行時只是一行普通文字。
  Write-Host ("::error::" + $msg)
  exit 1
}

# ── 金絲雀 ────────────────────────────────────────────────────────────────────
$script:canaryNpmDir = 'C:\npm'
$script:canaryPathDir = Join-Path (Get-TempRoot) 'codex-canary-bin'
$script:canaryHitLog = Join-Path (Get-TempRoot) 'codex-canary-hits.log'
$script:canaryHashFile = Join-Path (Get-TempRoot) 'codex-canary.sha256'

function Get-CanaryFiles {
  return @(
    (Join-Path $script:canaryNpmDir 'codex.cmd'),
    (Join-Path $script:canaryNpmDir 'codex.ps1'),
    (Join-Path $script:canaryPathDir 'codex.cmd'),
    (Join-Path $script:canaryPathDir 'codex.ps1')
  )
}

function Invoke-InstallCanary {
  # ⚠️ 雙重保險：本機上 C:\npm\codex.cmd 就是維護者真的 codex。
  if (-not $script:isCi -or -not $env:RUNNER_TEMP) {
    Fail "InstallCanary 只能在 GitHub Actions 上執行（GITHUB_ACTIONS=true 且有 RUNNER_TEMP）。本機執行會覆寫真的 C:\npm\codex.cmd，已拒絕。"
  }
  foreach ($f in (Get-CanaryFiles)) {
    if (Test-Path -LiteralPath $f) { Fail ("金絲雀目標已存在：" + $f + " —— runner 映像上不該有 codex；不覆寫，請先查明。") }
  }
  New-Item -ItemType Directory -Force -Path $script:canaryNpmDir, $script:canaryPathDir | Out-Null
  $log = $script:canaryHitLog
  # cmd 版：只寫一行一定安全的紀錄（%~f0 不含使用者輸入），足以判定「被叫到」。
  # ⚠️ 不記 %*：未跳脫的引數含 & | > 之類字元時，cmd 會自己解讀，紀錄可能被截斷或執行到片段
  #    （2026-10-14 合併前審查指出，已刪掉原本的 args 行）。
  $cmdLines = @(
    '@echo off',
    ('>>"' + $log + '" echo CANARY-HIT cmd %~f0'),
    'echo ::error::CANARY: a test invoked codex (%~f0). Tests must use the stub seams, never the real codex. 1>&2',
    'exit /b 97'
  )
  $ps1Lines = @(
    ('Add-Content -LiteralPath ''' + $log + ''' -Value (''CANARY-HIT ps1 '' + $MyInvocation.MyCommand.Path + '' args: '' + ($args -join '' ''))'),
    '[Console]::Error.WriteLine(''::error::CANARY: a test invoked codex ('' + $MyInvocation.MyCommand.Path + ''). Tests must use the stub seams, never the real codex.'')',
    'exit 97'
  )
  $ascii = New-Object System.Text.ASCIIEncoding
  foreach ($dir in @($script:canaryNpmDir, $script:canaryPathDir)) {
    [System.IO.File]::WriteAllText((Join-Path $dir 'codex.cmd'), (($cmdLines -join "`r`n") + "`r`n"), $ascii)
    [System.IO.File]::WriteAllText((Join-Path $dir 'codex.ps1'), (($ps1Lines -join "`r`n") + "`r`n"), $ascii)
  }

  # 自我測試：金絲雀自己要先證明「被叫到就會留下紀錄、回非零」。沒有這一步，
  # 「沒有命中」與「金絲雀根本壞了」在 Postflight 看起來一模一樣。
  foreach ($f in (Get-CanaryFiles)) {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = $null
    if ($f -like '*.cmd') { & cmd.exe /d /c $f 'canary-selftest' 2>&1 | Out-Null }
    else { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $f 'canary-selftest' 2>&1 | Out-Null }
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $hit = (Test-Path -LiteralPath $log) -and ((Get-Content -LiteralPath $log -Raw) -match 'CANARY-HIT')
    if ($rc -ne 97 -or -not $hit) { Fail ("金絲雀自我測試失敗：" + $f + " rc=" + $rc + " 紀錄=" + $hit) }
    Write-Host ("canary self-test OK: " + $f + " (rc=97, hit logged)")
  }
  Remove-Item -LiteralPath $log -Force

  $hashes = foreach ($f in (Get-CanaryFiles)) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash + '  ' + $f }
  [System.IO.File]::WriteAllLines($script:canaryHashFile, [string[]]$hashes, (New-Object System.Text.UTF8Encoding $false))
  # 之後的 step 才會吃到 GITHUB_PATH（本 step 內不生效）；Preflight 會驗證確實排在最前面。
  Add-Content -LiteralPath $env:GITHUB_PATH -Value $script:canaryPathDir
  Write-Host ("canary installed: " + $script:canaryNpmDir + " and " + $script:canaryPathDir + " (prepended to PATH for later steps)")
}

# 回傳 $true ＝ 沒有 ~/.claude。不直接 exit，讓 Postflight 能把所有問題一次印完。
function Test-NoClaudeHome([string]$when) {
  $cands = @()
  if ($env:USERPROFILE) { $cands += (Join-Path $env:USERPROFILE '.claude') }
  if ($HOME) { $cands += (Join-Path $HOME '.claude') }
  $cands = @($cands | Select-Object -Unique)
  $ok = $true
  foreach ($c in $cands) {
    if (Test-Path -LiteralPath $c) {
      Write-Host ("::error::" + $when + "：出現 " + $c + " —— 測試可能驗到（或寫到）非待驗 bytes，或有測試沒隔離好家目錄。")
      $ok = $false
    }
  }
  if ($ok) { Write-Host ($when + ": no ~/.claude (" + ($cands -join ', ') + ")") }
  return $ok
}

function Invoke-Preflight {
  if (-not (Test-NoClaudeHome 'preflight')) { exit 1 }
  if ($script:isCi) {
    $first = Get-Command codex -All -ErrorAction SilentlyContinue | Select-Object -First 1
    $src = ''
    if ($first) { $src = [string]$first.Source }
    if (-not $src.StartsWith($script:canaryPathDir, [StringComparison]::OrdinalIgnoreCase)) {
      Fail ("PATH 上第一個 codex 不是金絲雀：'" + $src + "'（預期在 " + $script:canaryPathDir + " 底下）")
    }
    $where = @(& cmd.exe /d /c 'where codex' 2>$null)
    if ($where.Count -lt 1 -or -not ([string]$where[0]).StartsWith($script:canaryPathDir, [StringComparison]::OrdinalIgnoreCase)) {
      Fail ("cmd 的 where codex 第一筆不是金絲雀：" + ($where -join ' | '))
    }
    Write-Host ("preflight: first codex on PATH = " + $src + "; where codex[0] = " + $where[0])
  } else {
    Write-Host "preflight: not on GitHub Actions -- canary PATH check skipped (local run)"
  }
}

function Invoke-Postflight {
  $bad = $false
  if (Test-Path -LiteralPath $script:canaryHitLog) {
    $t = Get-Content -LiteralPath $script:canaryHitLog -Raw
    if ($t -and $t.Trim()) {
      Write-Host "::error::CANARY HIT -- some test invoked codex outside the stub seams:"
      Write-Host $t
      $bad = $true
    }
  }
  if ($script:isCi) {
    if (-not (Test-Path -LiteralPath $script:canaryHashFile)) {
      Write-Host "::error::canary hash file missing -- InstallCanary did not complete"
      $bad = $true
    } else {
      foreach ($line in (Get-Content -LiteralPath $script:canaryHashFile)) {
        $parts = $line -split '  ', 2
        $f = $parts[1]
        if (-not (Test-Path -LiteralPath $f)) { Write-Host ("::error::canary file removed by a test: " + $f); $bad = $true; continue }
        if ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne $parts[0]) { Write-Host ("::error::canary file modified by a test: " + $f); $bad = $true }
      }
    }
  }
  if (-not $bad) { Write-Host "postflight: canary not hit, canary files intact" }
  if (-not (Test-NoClaudeHome 'postflight')) { $bad = $true }
  if ($bad) { exit 1 }
}

# ── UTF-8 console ─────────────────────────────────────────────────────────────
# ⚠️ 2026-10-14 本機實測：把 console code page 換成 437（GitHub Windows 映像是 en-US，推論為 437），
#    codex-check.tests.ps1 的中文斷言（'無漂移'、'跳過'…）會紅 3/14 —— SUT 的中文輸出經 pipe
#    變成 '?'。這是「會紅」，不是測試假象：en-US 主控台的使用者看到的 codex-check 中文訊息同樣會變 '?'，
#    是否屬產品缺陷待裁決（docs/backlog.md 的 CODEX-CHECK-CP437；W 驗收要在 cp437 主控台實跑取證）。
#    維護機與所有既有 Windows 證據都是 code page 65001。所以 Run 先把共用 console
#    切到 65001，child 繼承後才與維護機同條件；並**實際叫起 child 驗證**，切不過去就停。
#    ⇒ 本 CI **不**涵蓋非 UTF-8 console code page（見 YAML 檔頭的「涵蓋範圍」）。
function Set-Utf8Console {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & cmd.exe /d /c 'chcp 65001 >nul' 2>&1 | Out-Null
  $ErrorActionPreference = $prev
  try { [Console]::OutputEncoding = $utf8 } catch { Write-Host ("warn: cannot set [Console]::OutputEncoding: " + $_.Exception.Message) }
  foreach ($h in @('pwsh', 'powershell')) {
    $cp = [string](& $h -NoProfile -Command '[Console]::OutputEncoding.CodePage' 2>&1 | Select-Object -Last 1)
    if ($cp.Trim() -ne '65001') { Fail ("child " + $h + " 的 console code page 是 '" + $cp.Trim() + "'，不是 65001 —— 中文斷言會紅（SUT 中文輸出在非 UTF-8 下變 '?'；是否屬產品缺陷待裁決，見 CODEX-CHECK-CP437），停止。") }
  }
}

# ── Evidence ──────────────────────────────────────────────────────────────────
function Invoke-Native([string]$exe, [string[]]$argv) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $o = & $exe @argv 2>&1 | ForEach-Object { [string]$_ }
    return (($o | Where-Object { $_ -ne $null }) -join ' | ').Trim()
  } catch { return ('<error: ' + $_.Exception.Message + '>') }
  finally { $ErrorActionPreference = $prev }
}

function Invoke-Evidence {
  if (-not $Name) { Fail 'Evidence 需要 -Name' }
  $L = New-Object System.Collections.Generic.List[string]
  function Add([string]$k, $v) { $L.Add(('{0,-24} {1}' -f ($k + ':'), [string]$v)) }
  Add 'generated_utc' ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
  Add 'job' $Name
  foreach ($k in @('GITHUB_SHA', 'GITHUB_REF', 'GITHUB_EVENT_NAME', 'GITHUB_WORKFLOW', 'GITHUB_JOB', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT',
                   'ImageOS', 'ImageVersion', 'RUNNER_OS', 'RUNNER_ARCH', 'RUNNER_ENVIRONMENT')) {
    Add $k ([Environment]::GetEnvironmentVariable($k))
  }
  if ($env:GITHUB_SERVER_URL -and $env:GITHUB_REPOSITORY -and $env:GITHUB_RUN_ID) {
    Add 'run_url' ($env:GITHUB_SERVER_URL + '/' + $env:GITHUB_REPOSITORY + '/actions/runs/' + $env:GITHUB_RUN_ID)
  }
  try {
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    # ⚠️ ProductName 在 Windows 11 上仍顯示「Windows 10 …」（本機實測 "Windows 10 Pro"）—— 以 os_build 為準。
    Add 'os_product' ([string]$cv.ProductName + '  (registry ProductName; see os_build)')
    Add 'os_edition' $cv.EditionID
    Add 'os_display_version' $cv.DisplayVersion
    Add 'os_build' ([string]$cv.CurrentBuild + '.' + [string]$cv.UBR)
  } catch { Add 'os_registry' ('<error: ' + $_.Exception.Message + '>') }
  Add 'os_version_string' ([Environment]::OSVersion.VersionString)
  Add 'is_admin' (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
  Add 'evidence_host' ($PSVersionTable.PSEdition + ' ' + $PSVersionTable.PSVersion.ToString())
  Add 'pwsh' (Invoke-Native 'pwsh' @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'))
  Add 'pwsh_path' ((Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source)
  Add 'powershell' (Invoke-Native 'powershell' @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'))
  Add 'powershell_path' ((Get-Command powershell -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source)
  Add 'node' (Invoke-Native 'node' @('-v'))
  Add 'node_path' ((Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source)
  Add 'git' (Invoke-Native 'git' @('--version'))
  try {
    $nls = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage'
    Add 'system_acp' $nls.ACP
    Add 'system_oemcp' $nls.OEMCP
  } catch { Add 'system_codepage' ('<error: ' + $_.Exception.Message + '>') }
  Add 'console_cp_before' (Invoke-Native 'cmd.exe' @('/d', '/c', 'chcp'))
  Add 'winps_default_enc_cp' (Invoke-Native 'powershell' @('-NoProfile', '-Command', '[Text.Encoding]::Default.CodePage'))
  Add 'culture' ((Get-Culture).Name + ' / ui=' + (Get-UICulture).Name)
  Add 'USERPROFILE' $env:USERPROFILE
  Add 'TEMP' $env:TEMP
  Add 'TMP' $env:TMP
  Add 'temp_long' (Invoke-Native 'node' @('-p', 'require(''fs'').realpathSync.native(require(''os'').tmpdir())'))
  Add 'temp_short' (Invoke-Native 'cmd.exe' @('/d', '/c', 'for %I in ("%TEMP%") do @echo %~sI'))
  Add 'workspace' $env:GITHUB_WORKSPACE
  $drives = @('C:')
  if ($env:GITHUB_WORKSPACE -and $env:GITHUB_WORKSPACE.Length -ge 2) { $drives += $env:GITHUB_WORKSPACE.Substring(0, 2) }
  foreach ($d in ($drives | Select-Object -Unique)) { Add ('8dot3_' + $d.TrimEnd(':')) (Invoke-Native 'fsutil.exe' @('8dot3name', 'query', $d)) }
  Add 'execpolicy_pwsh' (Invoke-Native 'pwsh' @('-NoProfile', '-Command', 'Get-ExecutionPolicy -List | ForEach-Object { $_.Scope.ToString() + ''='' + $_.ExecutionPolicy.ToString() }'))
  Add 'execpolicy_winps' (Invoke-Native 'powershell' @('-NoProfile', '-Command', 'Get-ExecutionPolicy -List | ForEach-Object { $_.Scope.ToString() + ''='' + $_.ExecutionPolicy.ToString() }'))
  # backup-settings.test.js 的 symlink 案是否會被 SKIP，取決於這一項。
  $probeDir = Join-Path (Get-TempRoot) ('symlink-probe-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  try {
    New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
    $tgt = Join-Path $probeDir 't.txt'; Set-Content -LiteralPath $tgt -Value 'x'
    New-Item -ItemType SymbolicLink -Path (Join-Path $probeDir 'l.txt') -Target $tgt -ErrorAction Stop | Out-Null
    Add 'can_create_symlink' 'yes'
  } catch { Add 'can_create_symlink' ('no: ' + $_.Exception.Message) }
  finally { Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue }
  Add 'claude_home_exists' (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude'))
  Add 'codex_on_path' ((@(Get-Command codex -All -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Source })) -join ' | ')
  Add 'C_npm_codex_cmd_exists' (Test-Path -LiteralPath 'C:\npm\codex.cmd')

  $out = Join-Path (Get-EvidenceDir) ('env-' + $Name + '.txt')
  [System.IO.File]::WriteAllLines($out, $L.ToArray(), (New-Object System.Text.UTF8Encoding $false))
  $L | ForEach-Object { Write-Host $_ }
  Write-Host ("evidence written: " + $out)
}

# ── Lint ──────────────────────────────────────────────────────────────────────
function Invoke-Lint {
  $hostTag = $PSVersionTable.PSEdition + ' ' + $PSVersionTable.PSVersion.ToString()
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  # core.quotepath=false：否則 git 會把「超級模式」印成 \350\266\205... 的八進位跳脫。
  $prevOut = [Console]::OutputEncoding
  try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}
  $files = @(& git -C $script:repo -c core.quotepath=false ls-files -- '*.ps1' 2>$null)
  $gitRc = $LASTEXITCODE
  try { [Console]::OutputEncoding = $prevOut } catch {}
  $ErrorActionPreference = $prev
  if ($gitRc -ne 0 -or $files.Count -eq 0) { Fail ("git ls-files 取不到 .ps1 清單（rc=" + $gitRc + "，" + $files.Count + " 個）") }
  $bad = 0
  foreach ($rel in $files) {
    $p = Join-Path $script:repo $rel
    if (-not (Test-Path -LiteralPath $p)) { Write-Host ("FAIL  missing in working tree: " + $rel); $bad++; continue }
    $b = [System.IO.File]::ReadAllBytes($p)
    $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $nonAscii = $false
    $start = 0; if ($hasBom) { $start = 3 }
    for ($i = $start; $i -lt $b.Length; $i++) { if ($b[$i] -ge 0x80) { $nonAscii = $true; break } }
    $lf = 0; $crlf = 0; $loneCr = 0
    for ($i = 0; $i -lt $b.Length; $i++) {
      if ($b[$i] -eq 0x0A) { $lf++; if ($i -gt 0 -and $b[$i - 1] -eq 0x0D) { $crlf++ } }
      elseif ($b[$i] -eq 0x0D -and ($i + 1 -ge $b.Length -or $b[$i + 1] -ne 0x0A)) { $loneCr++ }
    }
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errs)
    $why = @()
    if ($nonAscii -and -not $hasBom) { $why += 'non-ASCII without UTF-8 BOM' }
    if ($crlf -ne $lf -or $loneCr -gt 0) { $why += ("line endings not all CRLF (lf=" + $lf + " crlf=" + $crlf + " loneCR=" + $loneCr + ")") }
    if ($errs -and $errs.Count -gt 0) { $why += ("parse errors under " + $hostTag + ": " + $errs.Count + " (first: line " + $errs[0].Extent.StartLineNumber + " " + $errs[0].Message + ")") }
    if ($why.Count -gt 0) { Write-Host ("FAIL  " + $rel + " -- " + ($why -join '; ')); $bad++ }
    else { Write-Host ("OK    " + $rel + "  bom=" + $hasBom + " crlf=" + $crlf) }
  }
  # node --check：hook 與 lib（只在 node 存在時；三個 job 都裝了 node）。
  if (Get-Command node -CommandType Application -ErrorAction SilentlyContinue) {
    $js = @(Get-ChildItem -LiteralPath (Join-Path $script:repo 'windows') -Recurse -File -Filter '*.js' |
            Where-Object { $_.FullName -match '\\(hooks|lib)\\' } | ForEach-Object { $_.FullName })
    foreach ($j in $js) {
      $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      $o = & node --check $j 2>&1 | Out-String
      $rc = $LASTEXITCODE
      $ErrorActionPreference = $prev
      if ($rc -ne 0) { Write-Host ("FAIL  node --check " + $j + "`n" + $o); $bad++ } else { Write-Host ("OK    node --check " + $j) }
    }
    if ($js.Count -eq 0) { Write-Host "FAIL  no hook/lib .js found under windows/"; $bad++ }
  }
  Write-Host ("lint [" + $hostTag + "]: ps1=" + $files.Count + " fail=" + $bad)
  if ($bad -gt 0) { exit 1 }
}

# ── Run ───────────────────────────────────────────────────────────────────────
function Invoke-Run {
  if (-not $Name -or -not $Exe) { Fail 'Run 需要 -Name 與 -Exe' }
  if ($Require.Count -eq 0) { Fail ("Run [" + $Name + "] 沒有任何 -Require —— 只看 exit code 會被「空輸出但 exit 0」騙過，拒跑。") }
  Set-Utf8Console
  $exePath = $null
  try { $exePath = (Get-Command $Exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
  catch { Fail ("找不到受測 host／執行檔 '" + $Exe + "'：" + $_.Exception.Message) }
  $log = Join-Path (Get-EvidenceDir) ($Name + '.log')
  $lines = New-Object System.Collections.Generic.List[string]
  Write-Host ("::group::" + $Name)
  Write-Host ("RUN  " + $exePath + " " + ($ArgList -join ' '))
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $global:LASTEXITCODE = $null
  & $exePath @ArgList 2>&1 | ForEach-Object { $s = [string]$_; $lines.Add($s); Write-Host $s }
  $rc = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $sw.Stop()
  Write-Host "::endgroup::"
  $lines.Add(('[windows-ci] exe=' + $exePath + ' rc=' + $rc + ' seconds=' + [int]$sw.Elapsed.TotalSeconds))
  [System.IO.File]::WriteAllLines($log, $lines.ToArray(), (New-Object System.Text.UTF8Encoding $false))

  $text = ($lines.ToArray() -join "`n")
  $problems = @()
  if ($rc -isnot [int]) { $problems += ('沒有取得退出碼（host 可能根本沒啟動）：' + [string]$rc) }
  elseif ($rc -ne 0) { $problems += ('exit=' + $rc) }
  foreach ($r in $Require) {
    if ($text -cmatch ('(?m)' + $r)) { Write-Host ("OK    require  " + $r) }
    else { $problems += ('缺少必要輸出：' + $r) }
  }
  foreach ($f in $Forbid) {
    if ($text -cmatch ('(?m)' + $f)) { $problems += ('出現禁止的輸出：' + $f) }
    else { Write-Host ("OK    forbid   " + $f) }
  }
  if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host ("::error title=" + $Name + "::" + $p) }
    exit 1
  }
  Write-Host ("PASS  " + $Name + "  (rc=0, " + $Require.Count + " require, " + $Forbid.Count + " forbid, " + [int]$sw.Elapsed.TotalSeconds + "s; log: " + $log + ")")
}

# ── 8.3 變異注入 ──────────────────────────────────────────────────────────────
# class-b-8dot3.test.js 守的是「8.3 短名寫 settings.json 也要被擋」，靠的是 hook 的
# canonicalize() 呼叫 fs.realpathSync.native 把短名解回長名。拿掉那一行，測試**必須**變紅，
# 而且紅的理由必須是「canonicalize 沒解開別名」—— 不是「找不到 hook」之類的意外。
# 對照組：同一個 step 內先跑未變異版，必須是 PASS（8dot3 關掉的 volume 會 SKIP，那就證明不了牙齒）。
function Invoke-Mutate8dot3 {
  Set-Utf8Console
  $testRel = 'skills\超級模式\tests\class-b-8dot3.test.js'
  $src = Join-Path $script:repo 'windows'
  $orig = Join-Path $src $testRel
  if (-not (Test-Path -LiteralPath $orig)) { Fail ("找不到 " + $orig) }

  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $o1 = @(& node $orig 2>&1 | ForEach-Object { [string]$_ }); $rc1 = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $o1 | ForEach-Object { Write-Host ("  [control] " + $_) }
  if ($rc1 -ne 0 -or -not (($o1 -join "`n") -cmatch '(?m)^PASS$')) {
    Fail ("對照組（未變異）不是 PASS（rc=" + $rc1 + "）—— 8dot3 可能停用，變異結果沒有意義。")
  }

  $dst = Join-Path (Get-TempRoot) ('windows-mut-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  try {
    Copy-Item -LiteralPath $src -Destination $dst -Recurse
    $hook = Join-Path $dst 'hooks\super-mode-consult-gate.js'
    $needle = 'try { real = fs.realpathSync.native(cur); }'
    $t = [System.IO.File]::ReadAllText($hook)
    $n = ([regex]::Matches($t, [regex]::Escape($needle))).Count
    if ($n -ne 1) { Fail ("SELFCHECK 變異點命中 " + $n + " 次（預期 1）—— canonicalize 已被改寫，請更新本動作。") }
    $t2 = $t.Replace($needle, 'try { real = cur; }')
    [System.IO.File]::WriteAllText($hook, $t2, (New-Object System.Text.UTF8Encoding $false))
    if ([System.IO.File]::ReadAllText($hook).Contains($needle)) { Fail 'SELFCHECK 變異沒有寫進去' }
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & node --check $hook 2>&1 | Out-Null; $rcChk = $LASTEXITCODE
    $o2 = @(& node (Join-Path $dst $testRel) 2>&1 | ForEach-Object { [string]$_ }); $rc2 = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($rcChk -ne 0) { Fail 'SELFCHECK 變異後的 hook 語法錯誤 —— 變異方式要修，不能當成「測試抓到了」' }
    $o2 | ForEach-Object { Write-Host ("  [mutant]  " + $_) }
    $txt2 = $o2 -join "`n"
    # 變異體要證明它載入的是**變異後**的 hook：canonicalize 的輸出應保留短名（~），且以正確理由失敗。
    if ($rc2 -eq 0 -or $txt2 -cmatch '(?m)^PASS$') { Fail '變異後 class-b-8dot3 仍 PASS —— 8.3 守衛已無測試牙齒（假綠）。' }
    if ($txt2 -cnotmatch '(?m)^FAIL: canonicalize did not resolve the 8\.3 alias to settings\.json$') {
      Fail ("變異後雖然紅了，但不是預期的理由（應為 canonicalize 沒解開 8.3 別名）。rc=" + $rc2)
    }
    Write-Host "PASS  8.3 mutation killed (realpath removed -> class-b-8dot3 red for the expected reason)"
  } finally {
    if ($dst -match 'windows-mut-[0-9a-f]{8}$' -and (Test-Path -LiteralPath $dst)) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

switch ($Action) {
  'InstallCanary' { Invoke-InstallCanary }
  'Preflight'     { Invoke-Preflight }
  'Postflight'    { Invoke-Postflight }
  'Evidence'      { Invoke-Evidence }
  'Lint'          { Invoke-Lint }
  'Run'           { Invoke-Run }
  'Mutate8dot3'   { Invoke-Mutate8dot3 }
}
exit 0
