# AI-INSTALL.md Windows 區塊測試臺
# 從文件抽出 ```powershell 區塊 → 用假 USERPROFILE 執行 → 檢查檔案系統狀態
# 含變異注入：錯誤分支不注入就走不到，等於沒驗。
param([string]$Shell = 'pwsh', [string]$Doc = '')

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$doc  = if ($Doc) { $Doc } else { Join-Path $repo 'docs\AI-INSTALL.md' }
"受測文件：$doc"
# ⚠️ 不要用固定路徑。舊版寫死 $env:TEMP\ai-install-harness 並在開頭遞迴刪除 ——
# 使用者剛好有同名資料、或兩個測試臺並行時，後啟動的會直接刪掉前者的資料
# （實測撞過 Access Denied 而中止清理）。改成每次用 GUID 新建，
# 清理只針對「本次建立且符合本前綴」的路徑。
$work = Join-Path $env:TEMP ('ai-install-harness-' + [guid]::NewGuid().ToString('N'))

# 抽取
$lines = Get-Content -LiteralPath $doc -Encoding UTF8
$blocks = @(); $cur = $null
foreach ($l in $lines) {
  if ($l -match '^```powershell\s*$') { $cur = New-Object System.Collections.ArrayList; continue }
  if ($null -ne $cur -and $l -match '^```\s*$') { $blocks += ,($cur -join "`n"); $cur = $null; continue }
  if ($null -ne $cur) { [void]$cur.Add($l) }
}
function Pick($needle) {
  $m = @($blocks | Where-Object { $_ -like "*$needle*" })
  if ($m.Count -ne 1) { throw "抽取失敗：'$needle' 命中 $($m.Count) 個區塊（預期 1）" }
  $m[0]
}
$B1b = Pick 'backup ts='
$B1c = Pick 'install OK'
$Brb = Pick 'Test-Exactly1'
$B0a = Pick 'GIT_BASH_OK'
"抽取：0a=$($B0a.Length) 字元, 1b=$($B1b.Length) 字元, 1c=$($B1c.Length) 字元, rollback=$($Brb.Length) 字元"

$PLACEHOLDER = '<貼上 1b 印出的值>'
if ($Brb -notlike "*$PLACEHOLDER*") { throw '回滾區塊找不到 ts 佔位符，抽取邏輯已過期' }

# 執行器
# 先把 host 解析成絕對路徑，找不到就在這裡失敗。不解析的話，executable 不存在時
# `& $exe` **不會設定 `$LASTEXITCODE`**，於是上一次成功留下的 0 會被沿用
# ——「找不到 host 卻判定成功」。（合併前 Codex 審查用最小探針在 5.1 與 7.x 都復現；
# 現行寫法最後是靠 `$out` 為 null、`.Trim()` 再爆掉才變紅，那是偶然的誤紅保護，不是結構。）
$exeName = if ($Shell -eq 'pwsh') { 'pwsh' } else { 'powershell' }
$exe = try { (Get-Command $exeName -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
       catch { throw "找不到可執行的 host '$exeName'（-Shell $Shell）：$($_.Exception.Message)" }
"執行 host：$exe"
function Invoke-Block($code, $fakeHome) {
  $f = Join-Path $work 'block.ps1'
  [IO.File]::WriteAllText($f, $code, (New-Object Text.UTF8Encoding $true))
  $prev = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  # ⚠️ **Windows PowerShell 5.1 專屬**：native command 寫 stderr 時，5.1 會把它包成
  # `NativeCommandError` 的 ErrorRecord；撞上本檔開頭的 `$ErrorActionPreference = 'Stop'`
  # 就會讓**整個測試臺**當場中止。7.x 不會。實測（HEAD ad8ff12、未含 M13 的版本亦同）：
  # `-Shell powershell` 一路綠到 `[M2]` 之前，然後停在 M1 第一個「被拒」案 ——
  # 那是第一個會寫 stderr 的子行程。也就是說 README 宣傳的 5.1 跑法先前**跑不完**，
  # Windows 側實際只有 pwsh 一個 host 有覆蓋。
  # 這裡只在**函式作用域**內降級（離開函式自動還原，不影響其他斷言的 Stop 語義）：
  # 子行程的成敗一律以 `$LASTEXITCODE` 判斷，本來就不該由 host 的錯誤串流決定。
  $ErrorActionPreference = 'Continue'
  # 每次呼叫前重設：不重設就可能沿用上一次的退出碼（見上方 host 解析的註解）。
  $global:LASTEXITCODE = $null
  try {
    $out = & $exe -NoProfile -NonInteractive -File $f 2>&1 | Out-String
    $rc = $LASTEXITCODE
  } finally { $env:USERPROFILE = $prev }
  # 拿不到整數退出碼就無法判定成敗 —— 明確炸掉，不要退化成「$rc -eq 0 為 false」而看似正常。
  if ($rc -isnot [int]) { throw "子行程沒有回傳整數退出碼（rc=[$rc]），無法判定成敗：$f" }
  [pscustomobject]@{ Ok = ($rc -eq 0); Out = ("$out").Trim() }
}
function Invoke-Rollback($ts, $fakeHome) { Invoke-Block ($Brb.Replace($PLACEHOLDER, $ts)) $fakeHome }

# ── 步驟 0a（Git Bash 前置條件）的執行器 ─────────────────────────────────
# 寫死的兩個位置用字串替換換成假路徑（[G] 第一條自檢它恰一處）；PATH 與 CLAUDE_CODE_GIT_BASH_PATH 每案明設或明刪；
# 需要時另外切換目前目錄（子行程繼承它）。不這樣做的話，結果會取決於跑測試的機器有沒有裝 Git
# （CI runner 與維護機都有），「找不到」那幾條分支永遠測不到。
$GB_FIXED = "@('C:\Program Files\Git\bin\bash.exe', 'C:\Program Files (x86)\Git\bin\bash.exe')"
$GB_TOKENS = @('GIT_BASH_MISSING', 'GIT_BASH_INVALID', 'GIT_BASH_UNDECIDABLE')
function Invoke-GitBashCheck($fixed1, $fixed2, $pathDirs, $envGb, $cwd) {
  $code = $B0a.Replace($GB_FIXED, ("@('{0}', '{1}')" -f $fixed1.Replace("'", "''"), $fixed2.Replace("'", "''")))
  $f = Join-Path $work 'gitbash.ps1'
  [IO.File]::WriteAllText($f, $code, (New-Object Text.UTF8Encoding $true))
  $prevPath = $env:PATH; $prevGb = $env:CLAUDE_CODE_GIT_BASH_PATH
  $ErrorActionPreference = 'Continue'   # 與 Invoke-Block 同理：只在函式作用域降級
  $global:LASTEXITCODE = $null
  if ($cwd) { Push-Location -LiteralPath $cwd }
  try {
    $env:PATH = (@($pathDirs) + (Join-Path $env:SystemRoot 'System32')) -join ';'
    if ($envGb) { $env:CLAUDE_CODE_GIT_BASH_PATH = $envGb } else { Remove-Item Env:\CLAUDE_CODE_GIT_BASH_PATH -ErrorAction SilentlyContinue }
    $out = & $exe -NoProfile -NonInteractive -File $f 2>&1 | Out-String
    $rc = $LASTEXITCODE
  } finally {
    if ($cwd) { Pop-Location }
    $env:PATH = $prevPath
    if ($null -ne $prevGb) { $env:CLAUDE_CODE_GIT_BASH_PATH = $prevGb } else { Remove-Item Env:\CLAUDE_CODE_GIT_BASH_PATH -ErrorAction SilentlyContinue }
  }
  if ($rc -isnot [int]) { throw "子行程沒有回傳整數退出碼（rc=[$rc]），無法判定成敗：$f" }
  [pscustomobject]@{ Ok = ($rc -eq 0); Out = ("$out").Trim() }
}
# 「停止」＝退出碼非 0、沒有任何一行以 GIT_BASH_OK path= 開頭、含預期的那個代號、且不含另外兩個代號。
function Test-GbStop($r, $token) {
  if ($r.Ok -or ($r.Out -cmatch '(?m)^GIT_BASH_OK path=')) { return $false }
  if ($r.Out -cnotmatch $token) { return $false }
  foreach ($t in $GB_TOKENS) { if (($t -cne $token) -and ($r.Out -cmatch $t)) { return $false } }
  $true
}
# 「通過」＝退出碼 0，且**恰好一行** GIT_BASH_OK path=…，路徑等於預期（Windows 路徑不分大小寫）。
function Test-GbOk($r, $want) {
  $okLines = @(($r.Out -split "\r?\n") | Where-Object { $_ -cmatch '^GIT_BASH_OK path=' })
  $r.Ok -and ($okLines.Count -eq 1) -and ($okLines[0] -ieq "GIT_BASH_OK path=$want")
}
# 8.3 短檔名換成長檔名：GitHub runner 的 $env:TEMP 是 C:\Users\RUNNER~1\…，而 where.exe 回的是長檔名，
# 不換的話「路徑等於預期」那幾案會在 CI 誤紅。
function Get-LongPath($p) {
  $full = [IO.Path]::GetFullPath($p)
  $acc = [IO.Path]::GetPathRoot($full)
  foreach ($seg in @($full.Substring($acc.Length).Split('\') | Where-Object { $_ })) {
    $hit = @([IO.Directory]::GetFileSystemEntries($acc, $seg))
    $acc = if ($hit.Count -eq 1) { $hit[0] } else { Join-Path $acc $seg }
  }
  $acc
}
# 假 bash.exe：測試臺當場用 .NET Framework 內建的 csc.exe 編一支小程式。它回應旁邊 <exe>.reply 的內容
# （HANG＝睡 10 分鐘；RC1:<文字>＝印文字並以 1 結束），並把收到的參數附加到 <exe>.args。
# 這樣正向案用的是**真的可執行檔、真的回 MINGW**，不是內容為 FAKE 的檔案；
# 而產品區塊沒有任何只為測試存在的開關——注入全在測試臺這一側（區塊文字、環境變數、目前目錄、檔案系統）。
$FAKE_BASH_CS = @'
using System;
using System.IO;
using System.Threading;
static class FakeBash {
  static int Main(string[] args) {
    string self = System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName;
    File.AppendAllText(self + ".args", string.Join("|", args) + "\n");
    string reply = File.ReadAllText(self + ".reply");
    if (reply.StartsWith("HANG")) { Thread.Sleep(600000); return 0; }
    int rc = 0;
    if (reply.StartsWith("RC1:")) { rc = 1; reply = reply.Substring(4); }
    Console.Out.Write(reply);
    return rc;
  }
}
'@
function Build-FakeBash($exePath) {
  $ErrorActionPreference = 'Continue'
  $cs = [IO.Path]::ChangeExtension($exePath, '.cs')
  [IO.File]::WriteAllText($cs, $FAKE_BASH_CS)
  $csc = @((Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
           (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')) |
         Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $csc) { return '找不到 .NET Framework 的 csc.exe' }
  $global:LASTEXITCODE = $null
  $o = & $csc /nologo /target:exe "/out:$exePath" $cs 2>&1 | Out-String
  ("csc=$csc rc=$LASTEXITCODE " + $o).Trim()
}
function Test-FakeBashRuns($exePath) {
  $ErrorActionPreference = 'Continue'
  if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { return $false }
  [IO.File]::WriteAllText("$exePath.reply", 'MINGW64_NT-10.0-99999')
  $global:LASTEXITCODE = $null
  $o = (& $exePath -c '/usr/bin/uname -s' 2>&1 | Out-String).Trim()
  ($LASTEXITCODE -eq 0) -and ($o -ceq 'MINGW64_NT-10.0-99999')
}
function New-FakeBash($rel, $reply) {
  $p = Join-Path $gbRoot $rel
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
  if (Test-Path -LiteralPath $gbFakeExe -PathType Leaf) { Copy-Item -LiteralPath $gbFakeExe -Destination $p -Force }
  [IO.File]::WriteAllText("$p.reply", $reply)
  $p
}
function Get-GbArgs($p) { if (Test-Path -LiteralPath "$p.args") { ("" + (Get-Content -LiteralPath "$p.args" -Raw)).Trim() } else { '' } }
function Clear-GbArgs($p) { Remove-Item -LiteralPath "$p.args" -Force -ErrorAction SilentlyContinue }

function New-FakeHome($name) {
  $h = Join-Path $work $name
  if (Test-Path -LiteralPath $h) { Remove-Item -LiteralPath $h -Recurse -Force }
  New-Item -ItemType Directory -Force -Path "$h\.claude\hooks", "$h\.claude\skills" | Out-Null
  $h
}
function Add-ExistingInstall($h) {
  Set-Content -LiteralPath "$h\.claude\hooks\super-mode-consult-gate.js" -Value 'OLD-HOOK' -NoNewline
  New-Item -ItemType Directory -Force -Path "$h\.claude\skills\超級模式" | Out-Null
  Set-Content -LiteralPath "$h\.claude\skills\超級模式\SKILL.md" -Value 'OLD-SKILL' -NoNewline
  Set-Content -LiteralPath "$h\.claude\settings.json" -Value '{"old":true}' -NoNewline
}
function Get-Snapshot($h) {
  if (-not (Test-Path -LiteralPath $h)) { return '<none>' }
  # 比對整個假 USERPROFILE，但明確忽略 pwsh 自己在被重導的 HOME 下建的 profile 資料
  # （典型是 AppData\Local\Microsoft\PowerShell\StartupProfileData-*），那是測試臺雜訊。
  # 明確忽略而非縮小比對範圍，否則未來新增的 .claude 之外副作用會逃過檢查。
  # ⚠️ 據實說明範圍：排除樣式是 `*\AppData\Local\Microsoft\PowerShell*`，
  # **比 `StartupProfileData-*` 寬** —— 整個 PowerShell 子樹都不比對。
  # 這是 fail-safe 方向的取捨（寧可漏看該子樹，也不要每次執行都因 host 自建檔案誤紅），
  # 但代價是：若產品哪天真的往那個子樹寫東西，這裡看不到。（第二輪 Codex 審查要求寫清楚。）
  (Get-ChildItem -LiteralPath $h -Recurse -Force |
    Where-Object { $_.FullName -notlike '*\AppData\Local\Microsoft\PowerShell*' } |
    Sort-Object FullName | ForEach-Object {
      $lk = if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { 'L' } else { '' }
      if ($_.PSIsContainer) { "D$lk|$($_.FullName.Substring($h.Length))" }
      else { "F$lk|$($_.FullName.Substring($h.Length))|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
  }) -join "`n"
}
function Get-Ts($out) { if ($out -match 'backup ts=(\d{8}-\d{6})') { $Matches[1] } else { $null } }

# 本檔預期跑出的**總案數**（PASS + FAIL）。結尾會硬斷言。
# 沒有這一條，刪掉任何一個 Check 仍會印 `PASS=111 FAIL=0` 並 exit 0 ——「少一案」是抓不到的假綠。
# ⚠️ 這個總數與受測文件**無關**（反向驗證只會改變 PASS/FAIL 的分佈，不會改變案數），
# 所以它是穩定的不變量。新增或移除案時必須同步更新，那是刻意的摩擦。
# 2026-10-17：126 → 161（+23 條 [G] 步驟 0a、+12 條 [M18] 1c 重掃）。同步點：run-mutation-controls.ps1 control 3 的
# StopLine、.github/workflows/windows.yml 的 PASS 數與 step 名稱、tests/ai-install/README.md 的 control 表。
$EXPECTED_CHECKS = 161
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail) {
  if ($cond) { $script:pass++; "  PASS  $name" }
  else { $script:fail++; "  FAIL  $name`n        $detail" }
}

New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location $repo
try {

"`n[G] 步驟 0a：Claude Code 會用哪一個 Git Bash、那一個能不能用（不能用就停止安裝）"
# 判準：「停止」見 Test-GbStop（代號要對：MISSING／INVALID／UNDECIDABLE 互不相混）；「通過」見 Test-GbOk（恰好一行）。
# fixture 建不起來時**不跳過**：案數固定，該紅的案自然變紅（同 [M13b] 的慣例）。
# ⚠️ 假目錄都在 $env:TEMP 底下、目前目錄是 repo。若有人把 repo 放進 %TEMP%，假 git 會落在目前目錄底下而被排除，
#    「where.exe 找到 git → 通過」那案會誤紅（假紅，不會假綠）。
$gbRoot = Join-Path (Get-LongPath $work) 'gitbash'
New-Item -ItemType Directory -Force -Path $gbRoot | Out-Null
$gbFakeExe = Join-Path $gbRoot 'fakebash.exe'
$gbBuild = Build-FakeBash $gbFakeExe
$gbHits = ([regex]::Matches($B0a, [regex]::Escape($GB_FIXED))).Count
Check '[G] 替換錨點（Claude Code 寫死的兩個位置）在區塊內恰一處（否則本節等於沒測）' ($gbHits -eq 1) "命中 $gbHits 處"
Check '[G] 前置：假 bash.exe 編譯成功，直接執行會回 MINGW64_NT-…（否則正向案等於沒測）' (Test-FakeBashRuns $gbFakeExe) $gbBuild
$gbPf      = New-FakeBash 'pf\Git\bin\bash.exe'        'MINGW64_NT-10.0-26100'
$gbPf86    = New-FakeBash 'pf86\Git\bin\bash.exe'      'MSYS_NT-10.0-26100'
$gbEnvOk   = New-FakeBash 'custom\bash.exe'            'MINGW64_NT-10.0-26100'
$gbEnvNo   = New-FakeBash 'custom\git.exe'             'MINGW64_NT-10.0-26100'
$gbGit     = New-FakeBash 'Git\cmd\git.exe'            'git version 0.0.0'
$gbGitBash = New-FakeBash 'Git\bin\bash.exe'           'MINGW64_NT-10.0-26100'
$gbGitNo   = New-FakeBash 'GitNoBash\cmd\git.exe'      'git version 0.0.0'
$gbWsl     = New-FakeBash 'wsl\bash.exe'               'Linux'                    # 模擬 WSL：可執行，但 uname -s 是 Linux
$gbWslApp  = New-FakeBash 'wsl\WindowsApps\bash.exe'   'MINGW64_NT-10.0-26100'    # 位置像 WSL 的執行別名；回應刻意是 MINGW，只有位置規則擋得到
$gbRc1     = New-FakeBash 'rc1\bash.exe'               'RC1:MINGW64_NT-10.0-26100'
$gbHang    = New-FakeBash 'hang\bash.exe'              'HANG'
$gbText    = Join-Path $gbRoot 'text\bash.exe'      # 不可執行的文字檔
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $gbText) | Out-Null
Set-Content -LiteralPath $gbText -Value 'FAKE' -NoNewline
$gbDir     = Join-Path $gbRoot 'dir\bash.exe'       # 名叫 bash.exe 的目錄
$gbPfDir   = Join-Path $gbRoot 'pfdir\Git\bin\bash.exe'
New-Item -ItemType Directory -Force -Path $gbDir, $gbPfDir | Out-Null
$gbAbs1 = Join-Path $gbRoot 'absent1\bash.exe'; $gbAbs2 = Join-Path $gbRoot 'absent2\bash.exe'
$gbGitCmd = Split-Path -Parent $gbGit; $gbGitNoCmd = Split-Path -Parent $gbGitNo
# 兩個 junction：jgit → Git（where.exe 找到的 git 經過 reparse point）、jcwd → cwd-target（目前目錄經過 reparse point）
$gbJGit = Join-Path $gbRoot 'jgit'; $gbJCwd = Join-Path $gbRoot 'jcwd'; $gbCwdT = Join-Path $gbRoot 'cwd-target'
New-Item -ItemType Directory -Force -Path $gbCwdT | Out-Null
cmd /c "mklink /J `"$gbJGit`" `"$(Split-Path -Parent $gbGitCmd)`"" | Out-Null; $gbJr1 = $LASTEXITCODE
cmd /c "mklink /J `"$gbJCwd`" `"$gbCwdT`"" | Out-Null; $gbJr2 = $LASTEXITCODE
$gbJOk = ($gbJr1 -eq 0) -and ($gbJr2 -eq 0) -and (@($gbJGit, $gbJCwd | Where-Object {
  $je = Get-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
  ($null -ne $je) -and (($je.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) }).Count -eq 2)
Check '[G] 前置：兩個 junction 確實建立（否則 UNDECIDABLE 兩案等於沒測）' $gbJOk "mklink rc=$gbJr1/$gbJr2"

$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $null $null
Check '[G] 什麼都沒有 → 停止（GIT_BASH_MISSING）' (Test-GbStop $r 'GIT_BASH_MISSING') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @((Split-Path -Parent $gbWsl)) $null $null
Check '[G] PATH 上只有 WSL 的 bash.exe → 仍然停止（PATH 上的 bash 不算）' (Test-GbStop $r 'GIT_BASH_MISSING') $r.Out
Clear-GbArgs $gbEnvOk
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $gbEnvOk $null
$gbArgs = Get-GbArgs $gbEnvOk
Check '[G] CLAUDE_CODE_GIT_BASH_PATH 指向可用的 bash.exe → 通過、用它，而且恰好實際執行過一次 uname 探測' ((Test-GbOk $r $gbEnvOk) -and ($gbArgs -ceq '-c|/usr/bin/uname -s')) "$($r.Out)`n        args=[$gbArgs]"
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $gbEnvNo $null
Check '[G] CLAUDE_CODE_GIT_BASH_PATH 檔名不是 bash／sh → 退回自動偵測（此案找不到 → 停止）' (Test-GbStop $r 'GIT_BASH_MISSING') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() (Join-Path $gbRoot 'nope\bash.exe') $null
Check '[G] CLAUDE_CODE_GIT_BASH_PATH 指向不存在的檔 → 退回自動偵測（此案找不到 → 停止）' (Test-GbStop $r 'GIT_BASH_MISSING') $r.Out
$r = Invoke-GitBashCheck $gbPf $gbAbs2 @() $null $null
Check '[G] 第一個寫死位置（Program Files）可用 → 通過' (Test-GbOk $r $gbPf) $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbPf86 @() $null $null
Check '[G] 第二個寫死位置（Program Files (x86)）可用、uname 是 MSYS_NT → 通過' (Test-GbOk $r $gbPf86) $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @($gbGitCmd) $null $null
Check '[G] PATH 上的 git 在 <Git>\cmd、<Git>\bin\bash.exe 可用 → 通過' (Test-GbOk $r $gbGitBash) $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @($gbGitNoCmd) $null $null
Check '[G] PATH 上的 git 旁邊沒有 bin\bash.exe → 停止' (Test-GbStop $r 'GIT_BASH_MISSING') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @($gbGitNoCmd, $gbGitCmd) $null $null
Check '[G] 只看 where.exe 的第一個 git（與 Claude Code 相同）→ 第一個旁邊沒有 bash 就停止' (Test-GbStop $r 'GIT_BASH_MISSING') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @($gbGitCmd) $null (Split-Path -Parent $gbGitCmd)
Check '[G] where.exe 找到的 git 在目前目錄底下 → 排除（與 Claude Code 相同）→ 停止' (Test-GbStop $r 'GIT_BASH_MISSING') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $gbDir $null
Check '[G] CLAUDE_CODE_GIT_BASH_PATH 指向名叫 bash.exe 的目錄 → Claude Code 會用它，判為不可用（GIT_BASH_INVALID）' (Test-GbStop $r 'GIT_BASH_INVALID') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $gbText $null
Check '[G] CLAUDE_CODE_GIT_BASH_PATH 指向不可執行的文字檔 → GIT_BASH_INVALID' (Test-GbStop $r 'GIT_BASH_INVALID') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $gbWsl $null
Check '[G] CLAUDE_CODE_GIT_BASH_PATH 指向 uname -s 回 Linux 的 bash（WSL）→ GIT_BASH_INVALID' (Test-GbStop $r 'GIT_BASH_INVALID') $r.Out
Clear-GbArgs $gbWslApp
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $gbWslApp $null
$gbArgs = Get-GbArgs $gbWslApp
Check '[G] CLAUDE_CODE_GIT_BASH_PATH 指向 WindowsApps\bash.exe → GIT_BASH_INVALID，而且根本沒有執行它' ((Test-GbStop $r 'GIT_BASH_INVALID') -and ($gbArgs -eq '')) "$($r.Out)`n        args=[$gbArgs]"
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $gbRc1 $null
Check '[G] 探測輸出像 MINGW 但退出碼非 0 → GIT_BASH_INVALID' (Test-GbStop $r 'GIT_BASH_INVALID') $r.Out
# 另外釘耗時：假 bash 睡 10 分鐘後會以 0 結束、沒有輸出，所以「沒有逾時、一直等」的寫法最後也會判 INVALID ——
# 只看代號的話那種寫法照樣綠。產品逾時是 15 秒，這裡給 90 秒的餘裕（含子行程啟動）。
$gbSw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @() $gbHang $null
$gbSecs = [int]$gbSw.Elapsed.TotalSeconds
Check '[G] 探測卡住不結束 → 逾時後 GIT_BASH_INVALID（不會卡死安裝）' ((Test-GbStop $r 'GIT_BASH_INVALID') -and ($gbSecs -lt 90)) "耗時 ${gbSecs} 秒`n        $($r.Out)"
$r = Invoke-GitBashCheck $gbPfDir $gbPf86 @() $null $null
Check '[G] 第一個寫死位置是目錄、第二個可用 → Claude Code 會用第一個，判為不可用（不改試第二個）' (Test-GbStop $r 'GIT_BASH_INVALID') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @((Join-Path $gbJGit 'cmd')) $null $null
Check '[G] where.exe 找到的 git 經過 junction → 無法判定，停止（GIT_BASH_UNDECIDABLE）' (Test-GbStop $r 'GIT_BASH_UNDECIDABLE') $r.Out
$r = Invoke-GitBashCheck $gbAbs1 $gbAbs2 @($gbGitCmd) $null $gbJCwd
Check '[G] 目前目錄經過 junction → 無法判定，停止（GIT_BASH_UNDECIDABLE）' (Test-GbStop $r 'GIT_BASH_UNDECIDABLE') $r.Out

"`n[C1] 既有安裝 -> 安裝 -> 回滾（含冪等）"
$h = New-FakeHome 'c1'; Add-ExistingInstall $h
$snap0 = Get-Snapshot "$h\.claude\skills\超級模式"
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '1b 成功並印出 ts' ($r.Ok -and $ts) $r.Out
$r = Invoke-Block $B1c $h
Check '1c 安裝成功' ($r.Ok -and $r.Out -match 'install OK') $r.Out
Check '安裝後 live 已換成新版' ((Get-Snapshot "$h\.claude\skills\超級模式") -ne $snap0) '安裝沒有改變 live'
# 模擬步驟 2 把 hook 條目合併進 settings。**沒有這一步，下面的「settings 還原」斷言恆真**
# ——settings 從頭到尾都是 OLD，就算把回滾的 settings 還原程式碼整段刪掉也照樣綠。
Set-Content -LiteralPath "$h\.claude\settings.json" -Value '{"new":true,"hooks":{"PreToolUse":[]}}' -NoNewline
Check '前置：settings 已被步驟 2 改動（否則還原斷言恆真）' ((Get-Content -LiteralPath "$h\.claude\settings.json" -Raw) -ne '{"old":true}') '注入失敗，本案的 settings 斷言無效'
for ($i = 1; $i -le 3; $i++) {
  $r = Invoke-Rollback $ts $h
  Check "第 $i 次回滾成功" $r.Ok $r.Out
  Check "第 $i 次回滾後 skill 等於安裝前" ((Get-Snapshot "$h\.claude\skills\超級模式") -eq $snap0) '還原內容不符'
  Check "第 $i 次回滾後 hook 還原" ((Get-Content -LiteralPath "$h\.claude\hooks\super-mode-consult-gate.js" -Raw) -eq 'OLD-HOOK') 'hook 未還原'
  Check "第 $i 次回滾後 settings 還原" ((Get-Content -LiteralPath "$h\.claude\settings.json" -Raw) -eq '{"old":true}') 'settings 未還原'
}

"`n[C2] 全新安裝 -> 回滾應刪除"
$h = New-FakeHome 'c2'
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '1b 成功' ($r.Ok -and $ts) $r.Out
# 三個 .absent 標記都要在——少一個就代表某個元件的「全新安裝」語義沒被記錄
foreach ($m in @("skills-backup\超級模式.bak-$ts.absent",
                 "hooks\super-mode-consult-gate.js.bak-$ts.absent",
                 "settings.json.bak-$ts.absent")) {
  Check ".absent 標記已建立：$m" (Test-Path -LiteralPath "$h\.claude\$m" -PathType Leaf) "缺 $m"
}
$r = Invoke-Block $B1c $h
Check '1c 安裝成功' $r.Ok $r.Out
# 模擬步驟 2 建立了原本不存在的 settings。**沒有這一步，「回滾後 settings 已刪除」
# 就是恆真**（它從頭到尾都不存在），刪掉回滾的 settings 刪除程式碼也測不出來。
Set-Content -LiteralPath "$h\.claude\settings.json" -Value '{"hooks":{"PreToolUse":[]}}' -NoNewline
Check '前置：步驟 2 已建立 settings（否則刪除斷言恆真）' (Test-Path -LiteralPath "$h\.claude\settings.json") '注入失敗'
$r = Invoke-Rollback $ts $h
Check '回滾成功' $r.Ok $r.Out
Check '回滾後 skill 已刪除' (-not (Test-Path -LiteralPath "$h\.claude\skills\超級模式")) 'skill 殘留'
Check '回滾後 hook 已刪除' (-not (Test-Path -LiteralPath "$h\.claude\hooks\super-mode-consult-gate.js")) 'hook 殘留'
Check '回滾後 settings 已刪除' (-not (Test-Path -LiteralPath "$h\.claude\settings.json")) 'settings 殘留'

"`n[M1] 變異注入：ts 含萬用字元（第七輪 HIGH 回歸）"
$h = New-FakeHome 'm1'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts1 = Get-Ts $r.Out
Start-Sleep -Seconds 1
$r = Invoke-Block $B1b $h; $ts2 = Get-Ts $r.Out
Check '兩個不同 ts 的備份都建立了' ($ts1 -and $ts2 -and $ts1 -ne $ts2) "ts1=$ts1 ts2=$ts2"
$r = Invoke-Block $B1c $h
$after = Get-Snapshot $h
foreach ($bad in @(($ts2.Substring(0,$ts2.Length-1) + '?'), ($ts2.Substring(0,8) + '-*'), ($ts2.Substring(0,$ts2.Length-1) + '[0-9]'))) {
  $r = Invoke-Rollback $bad $h
  Check "ts='$bad' 被拒" (-not $r.Ok) "竟然成功：$($r.Out)"
  Check "ts='$bad' 後 live 完全未變" ((Get-Snapshot $h) -eq $after) 'live 被動過'
}

"`n[M2] 變異注入：ts 格式錯、以及格式對但不存在"
$h = New-FakeHome 'm2'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
$after = Get-Snapshot $h
$goodTs = $ts
foreach ($bad in @('abc', '20260727-15440', '99999999-999999', '20260727_154409', ($goodTs + "`n"), (' ' + $goodTs))) {
  $r = Invoke-Rollback $bad $h
  Check "ts='$bad' 被拒" (-not $r.Ok) "竟然成功：$($r.Out)"
  Check "ts='$bad' 後 live 完全未變" ((Get-Snapshot $h) -eq $after) 'live 被動過'
}

"`n[M3] 變異注入：skill 備份被換成 junction"
$h = New-FakeHome 'm3'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
$sbak = "$h\.claude\skills-backup\超級模式.bak-$ts"
$elsewhere = Join-Path $work 'm3-elsewhere'
New-Item -ItemType Directory -Force -Path $elsewhere | Out-Null
Set-Content -LiteralPath "$elsewhere\SKILL.md" -Value 'WRONG-TARGET' -NoNewline
Remove-Item -LiteralPath $sbak -Recurse -Force
cmd /c "mklink /J `"$sbak`" `"$elsewhere`"" | Out-Null
$mkRc = $LASTEXITCODE
# 注入成功與否要自己驗：mklink 失敗時備份只是「不見了」，rollback 會改用
# 「找不到有效備份」這個**不相干的理由**拒絕 —— 一樣非零，本案於是永遠不會紅。
# rc 與型別兩個都驗：型別擋「根本沒建成」，
# rc 擋「建立失敗但原地剛好有殘留 reparse point」——後者只驗型別會漏。
# （實測：link 路徑被佔時 mklink 回 1；指向不存在目標回 0，那是 /J 的正常行為。）
$bakItem = Get-Item -LiteralPath $sbak -Force -ErrorAction SilentlyContinue
Check '前置：junction 備份確實建立' ($mkRc -eq 0 -and $null -ne $bakItem -and ($bakItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) "mklink rc=$mkRc 或不是 reparse point，本案等於沒測"
$after = Get-Snapshot "$h\.claude\skills"
$r = Invoke-Rollback $ts $h
Check 'junction 備份被拒' (-not $r.Ok) "竟然成功：$($r.Out)"
Check 'junction 備份被拒後 live 未變' ((Get-Snapshot "$h\.claude\skills") -eq $after) 'live 被動過'

"`n[M4] 變異注入：live skill 位置是 junction"
$h = New-FakeHome 'm4'
$elsewhere = Join-Path $work 'm4-elsewhere'
New-Item -ItemType Directory -Force -Path $elsewhere | Out-Null
Set-Content -LiteralPath "$elsewhere\SKILL.md" -Value 'ELSEWHERE' -NoNewline
cmd /c "mklink /J `"$h\.claude\skills\超級模式`" `"$elsewhere`"" | Out-Null
$mkRc = $LASTEXITCODE
# 同上：mklink 失敗時 live 位置根本不存在，1b 會走「原本沒安裝」那條分支——
# 中止與否的理由就換了一個，前置不驗的話本案的區辨性是假的。
$liveItem = Get-Item -LiteralPath "$h\.claude\skills\超級模式" -Force -ErrorAction SilentlyContinue
Check '前置：live junction 確實建立' ($mkRc -eq 0 -and $null -ne $liveItem -and ($liveItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) "mklink rc=$mkRc 或不是 reparse point，本案等於沒測"
$r = Invoke-Block $B1b $h
Check '1b 對 junction live 中止' (-not $r.Ok) "竟然成功：$($r.Out)"
# 1b 依序處理 hook -> skill -> settings，hook 那步會先建 .absent 才輪到 skill 中止。
# 文件聲明的性質是「中止就不印 ts，所以有印 ts 才等於三個備份都完成」——驗這個。
Check '1b 中止時未印出 ts（部分產物不算完成）' (-not (Get-Ts $r.Out)) "竟印出 ts：$($r.Out)"
Check '1b 沒有為 junction 的 skill 建 .absent' (-not (Test-Path -LiteralPath "$h\.claude\skills-backup" -PathType Container) -or -not (Get-ChildItem -LiteralPath "$h\.claude\skills-backup" -Force -Filter '*.absent' -ErrorAction SilentlyContinue)) 'skill 被誤標成 .absent'

"`n[M5] 變異注入：skill 備份被換成一般檔案"
$h = New-FakeHome 'm5'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
$sbak = "$h\.claude\skills-backup\超級模式.bak-$ts"
Remove-Item -LiteralPath $sbak -Recurse -Force
Set-Content -LiteralPath $sbak -Value 'not-a-dir' -NoNewline
# 與 M3／M4 同一形狀（注入手法換成寫檔而已）：寫檔沒成功時備份只是「不見了」，
# rollback 會改用「找不到有效備份」這個**不相干的理由**拒絕 —— 一樣非零，本案照樣綠。
# 要驗到「是一般檔案、且不是 reparse point」才算真的走到 precheck 的型別分支。
$m5Item = Get-Item -LiteralPath $sbak -Force -ErrorAction SilentlyContinue
Check '前置：一般檔案備份確實建立' ($null -ne $m5Item -and -not $m5Item.PSIsContainer -and ($m5Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) '不是一般檔案，本案等於沒測'
$after = Get-Snapshot "$h\.claude\skills"
$r = Invoke-Rollback $ts $h
Check '型別錯的備份被拒' (-not $r.Ok) "竟然成功：$($r.Out)"
Check '型別錯被拒後 live 未變' ((Get-Snapshot "$h\.claude\skills") -eq $after) 'live 被動過'

"`n[M6] 變異注入：備份與 .absent 同時存在"
$h = New-FakeHome 'm6'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
New-Item -ItemType File -Path "$h\.claude\skills-backup\超級模式.bak-$ts.absent" | Out-Null
$after = Get-Snapshot "$h\.claude\skills"
$r = Invoke-Rollback $ts $h
Check '兩者並存被拒' (-not $r.Ok) "竟然成功：$($r.Out)"
Check '兩者並存被拒後 live 未變' ((Get-Snapshot "$h\.claude\skills") -eq $after) 'live 被動過'

"`n[M7] 變異注入：安裝後 live 與來源不符（安裝驗證必須抓到）"
$h = New-FakeHome 'm7'
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$anchor = '$srcRoot = (Resolve-Path -LiteralPath $src).Path'
$mut = $B1c.Replace($anchor, 'Set-Content -LiteralPath "$live\SKILL.md" -Value "TAMPERED" -NoNewline' + "`n" + $anchor)
Check '變異確實注入（否則本案等於沒測）' ($mut -ne $B1c) '注入失敗：錨點字串已改變'
$r = Invoke-Block $mut $h
Check '安裝驗證抓到竄改' ((-not $r.Ok) -and ($r.Out -match '安裝驗證失敗')) "未抓到：$($r.Out)"

"`n[M8] 1b 重跑"
$h = New-FakeHome 'm8'; Add-ExistingInstall $h
$r1 = Invoke-Block $B1b $h; $ts = Get-Ts $r1.Out
$r2 = Invoke-Block $B1b $h
if ((Get-Ts $r2.Out) -eq $ts -or -not $r2.Ok) {
  Check '同秒重跑被拒' (-not $r2.Ok) "竟然成功：$($r2.Out)"
} else {
  Check '不同秒重跑允許' $r2.Ok $r2.Out
}

"`n[M9] 變異注入：live skill 樹「內部」有 junction（第八輪 HIGH 回歸）"
foreach ($variant in @(@{n='空目標'; fill=$false}, @{n='非空目標'; fill=$true})) {
  $tag = "m9-$($variant.n)"
  $h = New-FakeHome $tag; Add-ExistingInstall $h
  $tgt = Join-Path $work "$tag-target"
  New-Item -ItemType Directory -Force -Path $tgt | Out-Null
  if ($variant.fill) { Set-Content -LiteralPath "$tgt\payload.txt" -Value 'X' -NoNewline }
  New-Item -ItemType Directory -Force -Path "$h\.claude\skills\超級模式\references" | Out-Null
  cmd /c "mklink /J `"$h\.claude\skills\超級模式\references\shared`" `"$tgt`"" | Out-Null
  $isJunction = ((Get-Item -LiteralPath "$h\.claude\skills\超級模式\references\shared" -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
  Check "[$($variant.n)] 前置：內嵌 junction 確實建立" $isJunction '不是 reparse point，本案等於沒測'
  $r = Invoke-Block $B1b $h
  Check "[$($variant.n)] 1b 對內嵌 junction 中止" (-not $r.Ok) "竟然成功：$($r.Out)"
  Check "[$($variant.n)] 1b 未印出 ts" (-not (Get-Ts $r.Out)) "竟印出 ts：$($r.Out)"
  $bakJ = "$h\.claude\skills-backup\超級模式.bak-*\references\shared"
  Check "[$($variant.n)] 沒有留下被實體化的備份" (-not (Get-ChildItem -Path $bakJ -ErrorAction SilentlyContinue)) 'junction 已被複製成普通目錄'
}

"`n[M11] 變異注入：回滾期的內嵌 link（頂層乾淨、link 藏在子樹）"
# 與 M3／M9 的差別：M3 換掉的是**備份頂層**，M9 驗的是 **1b**。
# 本案兩者的頂層都完全合法，link 只藏在子樹裡，而且要到**回滾**才會被用到 ——
# 那正是舊版的破口：預檢只看頂層 → 通過 → 先刪掉 live → 再從錯誤拓撲還原。
foreach ($case in @(@{ n='備份子樹'; where='bak' }, @{ n='live 子樹'; where='live' })) {
  $tag = "m11-$($case.where)"
  $h = New-FakeHome $tag; Add-ExistingInstall $h
  $r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
  Check "[$($case.n)] 前置：1b 成功並印出 ts" ($r.Ok -and $ts) $r.Out
  $r = Invoke-Block $B1c $h
  Check "[$($case.n)] 前置：1c 安裝成功" $r.Ok $r.Out

  $tgt = Join-Path $work "$tag-target"
  New-Item -ItemType Directory -Force -Path $tgt | Out-Null
  Set-Content -LiteralPath "$tgt\payload.txt" -Value 'OUTSIDE' -NoNewline

  $root = if ($case.where -eq 'bak') { "$h\.claude\skills-backup\超級模式.bak-$ts" }
          else                       { "$h\.claude\skills\超級模式" }
  New-Item -ItemType Directory -Force -Path "$root\references" | Out-Null
  cmd /c "mklink /J `"$root\references\shared`" `"$tgt`"" | Out-Null
  $mkRc = $LASTEXITCODE
  $e = Get-Item -LiteralPath "$root\references\shared" -Force -ErrorAction SilentlyContinue
  $isJ = ($null -ne $e) -and ((($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) -ne 0)
  # rc ＋型別雙驗（同 M3）：注入沒成功的話，回滾會因**不相干的理由**失敗，本案永遠不會紅。
  Check "[$($case.n)] 前置：內嵌 junction 確實建立" (($mkRc -eq 0) -and $isJ) "mklink rc=$mkRc, isJunction=$isJ"

  $after = Get-Snapshot "$h\.claude\skills"
  $r = Invoke-Rollback $ts $h
  Check "[$($case.n)] 回滾中止" (-not $r.Ok) "竟然成功：$($r.Out)"
  # 這條才是 B1 的重點：舊版是「先刪 live、還原時才炸」，所以 live 必須原封不動。
  Check "[$($case.n)] 被拒後 live 未變" ((Get-Snapshot "$h\.claude\skills") -eq $after) 'live 被動過'
  Check "[$($case.n)] junction 外部目標未被刪" (Test-Path -LiteralPath "$tgt\payload.txt") '外部真實資料被刪'
}

"`n[M12] live skill 不存在時的回滾必須成功（B1 前置條件的守護）"
# 掃描寫成 fail-closed 時很容易連「沒有子樹可掃」也一起擋掉，
# 那會讓「live 已被手動移除、想從備份還原」這條**合法**路徑永久失敗。
# 這與 M11 是同一形狀 bug 的兩面，一起犯就要一起修。
$h = New-FakeHome 'm12'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '前置：1b 成功並印出 ts' ($r.Ok -and $ts) $r.Out
$r = Invoke-Block $B1c $h
Check '前置：1c 安裝成功' $r.Ok $r.Out
Remove-Item -LiteralPath "$h\.claude\skills\超級模式" -Recurse -Force
Check '前置：live skill 確實已移除' (-not (Test-Path -LiteralPath "$h\.claude\skills\超級模式")) 'live 還在，本案等於沒測'
$r = Invoke-Rollback $ts $h
Check '回滾仍成功' $r.Ok $r.Out
Check '回滾後 live skill 已還原' (Test-Path -LiteralPath "$h\.claude\skills\超級模式\SKILL.md" -PathType Leaf) '沒有還原'

# 注入自我檢查的探針，會被送進**受測 host 的 child 行程**執行（見 Test-EnumBlocked）。
# ⚠️ 例外**型別**要一起印出來並釘住。只認「有沒有拋錯」的話，任何不相干的錯誤
# （路徑打錯、暫存目錄被清掉…）都能冒充成「Deny ACE 生效」，本案就變成假通過。
# 我們要的是 UnauthorizedAccessException，不是隨便一個例外。（第二輪 Codex 審查建議。）
$m13ProbeTpl = @'
$ErrorActionPreference = 'Stop'
try { $null = @(Get-ChildItem -LiteralPath '<ROOT>' -Recurse -Force -ErrorAction Stop); 'ENUM=OK' }
catch { "ENUM=FAIL TYPE=$($_.Exception.GetType().Name)" }
'@

"`n[M13] 列舉失敗必須在任何 mutation 之前中止（fail-closed 契約本身）"
# M11 驗「掃到 link」、M12 驗「沒有子樹可掃」，但**掃不動**這條路徑在 Windows 側先前
# 只有區塊開頭 `$ErrorActionPreference = 'Stop'` 的**靜態推論**，沒有動態測試
# （POSIX 側 2026-08-10 已補 `[M13]`，Windows 側當時列為單獨一批）。
# 那條才是資料安全契約：列舉失敗時若 fail-open，就會先刪 live、再從一棵沒驗證過的樹還原。
#
# 注入手法＝**對自己下 Deny ACE**（POSIX 側是 `chmod 000`）。目錄的擁有者即使沒有管理員
# 權限也隱含保有 WRITE_DAC，所以「拒絕自己 ListDirectory」以及事後把它拿掉都做得到。
#
# ⚠️ **不要照抄 POSIX 的 root 前置守衛。** 那邊必須先擋 root，是因為 root 會忽略權限位元、
# 讓 `chmod 000` 整個失效。Windows 這邊不一樣：Deny ACE 在存取檢查裡優先於 Allow，
# 提權本身並不會讓注入失效（`Get-ChildItem` 不會去用 SeBackupPrivilege）。真正會讓它失效的是
# 「檔案系統不支援 ACL」「行程啟用了備份權限」這類情況 ——**那些無法可靠地前置偵測**，
# 所以改由下面的**注入自我檢查當唯一權威**：注入沒生效就直接 FAIL，不給綠燈、也不靜默跳過
# （本測試臺沒有 SKIP 機制，加一個會改動結尾 `PASS=/FAIL=` 摘要行的契約，
# 而交接文件與反向驗證都靠那一行）。
#
# 斷言名稱一律帶 `[M13]` 前綴：M11 也用 `[備份子樹]`／`[live 子樹]`，不加前綴的話
# 「前置：1b 成功並印出 ts」等名稱會在兩個區塊裡重複，反向驗證就沒辦法逐條核對。
#
# ⚠️ **這是狀態 oracle，不是事件 oracle。** 快照相等只能證明「最終內容相同」，
# 不能證明「途中從未刪除又還原」。產品目前沒有任何失敗後還原的邏輯，所以狀態比對足以當證據，
# 但**文件不要把它讀成「證明 mutation 從未開始」**。（合併前 Codex 審查要求講清楚。）
$m13Me = [Security.Principal.WindowsIdentity]::GetCurrent().User

function New-LockedDir($root) {
  # 在 <root>\references\locked 放一個檔再上鎖：空目錄有機會被「剛好 rmdir 掉」而讓注入
  # 自己消失（POSIX 側正是這個差異造成 GNU／BSD 退出碼不一致），
  # 放了檔才讓「掃不動的子樹裡有真實資料」這件事成立。
  $p = "$root\references\locked"
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  Set-Content -LiteralPath "$p\payload.txt" -Value 'LOCKED' -NoNewline
  $p
}
function Set-DenyEnumerate($path) {
  $rule = New-Object Security.AccessControl.FileSystemAccessRule(
    $script:m13Me, 'ListDirectory', 'ContainerInherit,ObjectInherit', 'None', 'Deny')
  $acl = Get-Acl -LiteralPath $path; $acl.AddAccessRule($rule); Set-Acl -LiteralPath $path -AclObject $acl
  $rule
}
function Clear-DenyEnumerate($path, $rule) {
  $acl = Get-Acl -LiteralPath $path
  $null = $acl.RemoveAccessRule($rule)
  Set-Acl -LiteralPath $path -AclObject $acl
}
# 模擬安裝步驟 2 把 hook 條目合併進 settings。
# ⚠️ **沒有這一步，settings 型的違規在 M13 是看不見的。**
# `Add-ExistingInstall` 寫的 settings 與 1b 的備份一模一樣（1c 不碰 settings），
# 所以把回滾的「settings 還原」搬到預掃之前只是 OLD → OLD ——
# 內容雜湊不變、快照相等、mutant 存活。C1／C2 早就有這個手法
#（註解寫「否則還原斷言恆真」），**M13 當初漏了**。
# ⚠️ **POSIX 側有同型缺口，但尚未修。** `run-posix.sh` 的 `[M13]` 一樣沒有這個 fixture，
# 修法只存在於已裁示 ⛔ 停擺的 `test/posix-m13-wide-oracle-…` 分支，**不在 main 上**。
# 本批刻意只動 Windows；不要把這裡讀成「兩邊都補好了」。
function Set-Step2Settings($h, $ts, $label) {
  Set-Content -LiteralPath "$h\.claude\settings.json" -Value '{"new":true,"hooks":{"PreToolUse":[]}}' -NoNewline
  $cur = Get-Content -LiteralPath "$h\.claude\settings.json" -Raw
  $bak = Get-Content -LiteralPath "$h\.claude\settings.json.bak-$ts" -Raw
  Check "$label 前置：settings 已與備份不同（否則 settings 型的違規看不見）" ($cur -cne $bak) '注入失敗：settings 仍等於備份'
}
# 整行精確比對的小工具。**一律用 `-ceq`（大小寫敏感、整行相等）**，
# 不用 `-like`／`-match` —— 本批在 Windows 側因為子字串比對連續踩了兩次坑。
function Get-ExactLineCount($lines, $needle) { @($lines | Where-Object { $_ -ceq $needle }).Count }
function Get-ExactLineIndex($lines, $needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -ceq $needle) { return $i } }
  return -1
}
# 把相鄰的兩行**原樣搬到** anchor 之前（不是另外注入一行）。
# 搬移是最強的證據形式：產物就是產品自己的程式碼，只是順序錯了。
function Move-TwoLinesBefore($lines, $l1, $l2, $anchor) {
  $out = New-Object System.Collections.ArrayList
  $skip = $false
  foreach ($ln in $lines) {
    if ($ln -ceq $l1) { $skip = $true; continue }
    if ($skip -and ($ln -ceq $l2)) { $skip = $false; continue }
    if ($ln -ceq $anchor) { [void]$out.Add($l1); [void]$out.Add($l2) }
    [void]$out.Add($ln)
  }
  ,$out.ToArray()
}
function Test-EnumBlocked($root, $fakeHome) {
  # 注入自我檢查要在**受測 host 的 child 行程**裡跑。自檢跑在 parent、產品跑在 `$exe` child，
  # 兩者不保證是同一個 host（`-Shell powershell` 時 parent 仍可能是 pwsh），
  # token 與 provider 行為不能當成邏輯上相同。（合併前 Codex 審查指出。）
  (Invoke-Block ($script:m13ProbeTpl.Replace('<ROOT>', $root)) $fakeHome).Out
}

foreach ($case in @(@{ n='備份子樹'; where='bak' }, @{ n='live 子樹'; where='live' })) {
  $tag = "m13-$($case.where)"
  $h = New-FakeHome $tag; Add-ExistingInstall $h
  $r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
  Check "[M13][$($case.n)] 前置：1b 成功並印出 ts" ($r.Ok -and $ts) $r.Out
  $r = Invoke-Block $B1c $h
  Check "[M13][$($case.n)] 前置：1c 安裝成功" $r.Ok $r.Out

  Set-Step2Settings $h $ts "[M13][$($case.n)]"

  $root = if ($case.where -eq 'bak') { "$h\.claude\skills-backup\超級模式.bak-$ts" }
          else                       { "$h\.claude\skills\超級模式" }
  $locked = New-LockedDir $root

  # 兩份快照都必須在 Deny **之前**取 —— Get-Snapshot 自己也是 -Recurse，之後同樣掃不動。
  $beforeSkills = Get-Snapshot "$h\.claude\skills"
  $beforeHome   = Get-Snapshot $h

  $denyRule = Set-DenyEnumerate $locked
  try {
    $probeOut = Test-EnumBlocked $root $h
    Check "[M13][$($case.n)] 前置：列舉真的失敗（在受測 host 內驗證注入生效）" ($probeOut -match 'ENUM=FAIL TYPE=UnauthorizedAccessException') "probe 輸出：$probeOut —— Deny ACE 沒咬到（檔案系統不支援 ACL？行程有備份權限？），不能給綠燈"
    $r = Invoke-Rollback $ts $h
  } finally {
    # 先還原權限，後面的 Get-Snapshot 與 $work 清理才掃得動
    Clear-DenyEnumerate $locked $denyRule
  }
  Check "[M13][$($case.n)] 列舉失敗 → 回滾中止" (-not $r.Ok) "竟然成功：$($r.Out)"
  # 這條才是重點。修正前也會非零（Remove-Item／Copy-Item 自己撞權限），
  # 但**那時 live 已經被刪了**，所以區辨力全在這一條，不在退出碼。
  Check "[M13][$($case.n)] 中止後 live 未變" ((Get-Snapshot "$h\.claude\skills") -eq $beforeSkills) 'live 被動過'
  # ⚠️ 契約講的是「**任何** mutation 之前中止」，不是「skill 樹未變」。
  # 產品在預掃之後還會改 hook 與 settings；只快照 skills 的話，把 hook mutation 搬到
  # 預掃之前仍會全綠 —— 那是合併前 Codex 審查抓到的 surviving mutant，`[M13c]` 就是它的牙齒測試。
  Check "[M13][$($case.n)] 中止後整個假家目錄未變（hook／settings 也在內）" ((Get-Snapshot $h) -eq $beforeHome) '假家目錄有東西被動過（skills 之外也要看）'
}

"`n[M13b] 變異注入：拿掉 Stop 後保護必須消失（證明 M13 的區辨力來自那一行）"
# M13 只證明「現在是 fail-closed」，不證明**是哪一行讓它 fail-closed**。
# 本案把區塊開頭的 Stop 改成 Continue、其餘完全不動：列舉錯誤退回非終止錯誤 →
# `$bad` 為 $null → 守衛不拋 → 走到 `Remove-Item -Recurse` → live 被動過。
# 沒有這一案，日後有人把那行刪掉時只會知道 M13 紅了，不會知道紅在哪裡。
$m13Anchor = "`$ErrorActionPreference = 'Stop'"
# 錨點必須**行首錨定**：區塊裡還有一句註解含同樣字面
#（`# 本區塊開頭的 $ErrorActionPreference = 'Stop' 讓真正的列舉失敗…直接拋出＝fail-closed。`），
# 用 `String.Replace` 會連註解一起改掉 —— 那就不是「其餘完全不動」的單點變異了。
# 這是散文含程式碼字面、被未錨定比對抓走的同一形狀（同 2026-08-10 那批的 `RESULT_CODE=`），
# 而且是本案的自我檢查先紅才發現的，不是事先想到的。
$m13Re   = [regex]('(?m)^' + [regex]::Escape($m13Anchor) + '$')
$m13Hits = $m13Re.Matches($Brb)
$m13Ok   = ($m13Hits.Count -eq 1) -and ($m13Hits[0].Index -eq 0)
$m13Idx  = if ($m13Hits.Count -ge 1) { $m13Hits[0].Index } else { 'n/a' }
Check '[M13b] 變異錨點唯一且在區塊開頭（否則本案等於沒測）' $m13Ok "命中 $($m13Hits.Count) 次、index=$m13Idx（預期 1 次、index 0）"
# 錨點失效時**刻意不跳過**後面兩案，改用未變異的區塊讓它們自然變紅：
# 案數必須釘死，少印一案是抓不到的假綠。
$m13Mut = if ($m13Ok) { "`$ErrorActionPreference = 'Continue'" + $Brb.Substring($m13Hits[0].Length) } else { $Brb }
$m13Diff = @(Compare-Object ($Brb -split "`n") ($m13Mut -split "`n")).Count
Check '[M13b] 變異確實注入且只動一行' (($m13Mut -ne $Brb) -and ($m13Diff -eq 2)) "差異行數=$m13Diff（預期 2：一去一回；0＝沒注入，>2＝動到不該動的行）"
$h = New-FakeHome 'm13b'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '[M13b] 前置：1b 成功並印出 ts' ($r.Ok -and $ts) $r.Out
$r = Invoke-Block $B1c $h
Check '[M13b] 前置：1c 安裝成功' $r.Ok $r.Out
# ⚠️ 鎖的是**備份**子樹，不是 live。鎖 live 的話，fail-open 之後的負向訊號要依賴
# `Remove-Item -Recurse` 對一棵**部分不可存取**的樹「刪掉一些才失敗」——那是 provider 語義，
# 日後若改成更早、更原子地拒絕就會誤紅。鎖備份則是：預掃 fail-open → 第一個 mutation
# 刪除一棵**完全可存取**的 live → 訊號穩定。（合併前 Codex 審查建議，已採納。）
$m13bLocked = New-LockedDir "$h\.claude\skills-backup\超級模式.bak-$ts"
$before = Get-Snapshot "$h\.claude\skills"
$denyRule = Set-DenyEnumerate $m13bLocked
try {
  $probeOut = Test-EnumBlocked "$h\.claude\skills-backup\超級模式.bak-$ts" $h
  Check '[M13b] 前置：列舉真的失敗（在受測 host 內驗證注入生效）' ($probeOut -match 'ENUM=FAIL TYPE=UnauthorizedAccessException') "probe 輸出：$probeOut —— Deny ACE 沒咬到，本案等於沒測"
  $r = Invoke-Block ($m13Mut.Replace($PLACEHOLDER, $ts)) $h
} finally {
  Clear-DenyEnumerate $m13bLocked $denyRule
}
# 只釘「live 被動過」：那正是 M13 主斷言的否命題。**不**額外釘退出碼——
# 錯誤是否終止會隨 host 版本而異，釘了只會製造平台雜訊（同 M13／POSIX 的教訓）。
Check '[M13b] 拿掉 Stop 後 live 確實被動過（保護來自該行）' ((Get-Snapshot "$h\.claude\skills") -ne $before) "live 未變（回滾 ok=$($r.Ok)）：本案已失去意義，M13 的區辨力來源需重新確認"

"`n[M13c] 變異注入：把預掃**後**的還原步驟原樣搬到預掃之前（證明 oracle 夠寬）"
# 合併前 Codex 審查抓到的 surviving mutant：契約說的是「**任何** mutation 之前中止」，
# 但原本只快照 `.claude\skills`。產品在預掃**之後**才還原 hook 與 settings，
# 所以「把還原搬到預掃前」這個違規，窄 oracle 會全綠放行。
#
# ⚠️ **兩個目標都要跑**：hook 與 settings。只跑 hook 的話，settings 型的同契約 mutant
# 仍然沒被測到 —— 而且在 `Set-Step2Settings` 之前它根本殺不掉，因為 settings 等於它的備份
#（那是 fixture 的盲點，不是 oracle 的）。
#
# ⚠️ 改用**搬移**而非注入（第一版是注入一行）。Codex 評注入為「對 oracle 是等價類」，
# 但也指出**搬既有兩行才是最強證據** —— 產物就是產品自己的程式碼，只是順序錯了。
# 搬移的代價是自我檢查要更嚴：驗來源兩行相鄰、驗產出相鄰且緊貼 anchor、
# 再驗**產出仍可解析**。少了最後一條，日後若有人在兩行之間插入東西，
# 搬移會產生語法壞掉的區塊，而回滾可能在讀到錯誤之前就先中止 → 後面三條全部假綠。
$m13cAnchor = "if (Test-Path -LiteralPath `$sbak -PathType Container) { Assert-NoReparseUnder 'skill 備份' `$sbak }"
$brbLines = $Brb -split "`n"
foreach ($tgt in @(
  @{ n='hook';     l1="if (Test-Path -LiteralPath `$hbak -PathType Leaf) { Copy-Item -LiteralPath `$hbak -Destination `$hook -Force }"
                   l2="elseif (Get-Entry `$hook) { Remove-Item -LiteralPath `$hook -Force }" },
  @{ n='settings'; l1="if (Test-Path -LiteralPath `$setbak -PathType Leaf) { Copy-Item -LiteralPath `$setbak -Destination `$setf -Force }"
                   l2="elseif (Get-Entry `$setf) { Remove-Item -LiteralPath `$setf -Force }" })) {

  $c1 = Get-ExactLineCount $brbLines $tgt.l1
  $c2 = Get-ExactLineCount $brbLines $tgt.l2
  $ca = Get-ExactLineCount $brbLines $m13cAnchor
  $i1 = Get-ExactLineIndex $brbLines $tgt.l1
  $i2 = Get-ExactLineIndex $brbLines $tgt.l2
  $ia = Get-ExactLineIndex $brbLines $m13cAnchor
  # anchor 必須真的是**第一個** Assert-NoReparseUnder 呼叫
  #（定義行是 `function Assert-NoReparseUnder($name, $path) {`，沒有空格，抓不到）
  $iFirstScan = -1
  for ($k = 0; $k -lt $brbLines.Count; $k++) { if ($brbLines[$k] -clike '*Assert-NoReparseUnder *') { $iFirstScan = $k; break } }
  # ⚠️ 還要驗**來源本來就在 anchor 之後**。少了這一條，若產品哪天把還原挪到預掃前
  #（也就是缺陷已經存在於產品裡），這個「搬移」會變成不搬 —— 測試照樣綠，卻什麼都沒證明。
  Check "[M13c][$($tgt.n)] 來源錨點：三串各唯一、兩行相鄰、anchor 是第一個 Assert-NoReparseUnder、且來源在 anchor 之後" `
    (($c1 -eq 1) -and ($c2 -eq 1) -and ($ca -eq 1) -and ($i2 -eq $i1 + 1) -and ($ia -ge 0) -and ($iFirstScan -eq $ia) -and ($i1 -gt $ia)) `
    "c1=$c1 c2=$c2 anchor=$ca i1=$i1 i2=$i2 firstScan=$iFirstScan anchorIdx=$ia（舊版文件沒有預掃，anchor 會是 0）"

  $mutLines = Move-TwoLinesBefore $brbLines $tgt.l1 $tgt.l2 $m13cAnchor
  $m1 = Get-ExactLineIndex $mutLines $tgt.l1
  $m2 = Get-ExactLineIndex $mutLines $tgt.l2
  $ma = Get-ExactLineIndex $mutLines $m13cAnchor
  $m13cMut = $mutLines -join "`n"
  # 還要驗**產出與原檔真的不同**：所有位置條件都可能在「什麼都沒搬」時碰巧成立。
  Check "[M13c][$($tgt.n)] 產出：行數不變、各恰一份、兩行相鄰且緊貼 anchor、且確實與原檔不同" `
    (($mutLines.Count -eq $brbLines.Count) -and ((Get-ExactLineCount $mutLines $tgt.l1) -eq 1) -and `
     ((Get-ExactLineCount $mutLines $tgt.l2) -eq 1) -and ($m1 -ge 0) -and ($m2 -eq $m1 + 1) -and ($ma -eq $m2 + 1) -and `
     ($m13cMut -cne $Brb)) `
    "lines=$($brbLines.Count)/$($mutLines.Count) l1=$m1 l2=$m2 anchor=$ma"
  # 解析檢查是上一條的**獨立**保險：相鄰性驗位置，解析驗「這東西還能不能跑」。
  $parseOk = $true; $parseErr = ''
  try { $null = [scriptblock]::Create($m13cMut) } catch { $parseOk = $false; $parseErr = $_.Exception.Message }
  Check "[M13c][$($tgt.n)] 產出的區塊語法正確（可解析）" $parseOk "解析失敗：$parseErr —— 執行時可能先中止而讓後面三條假綠"

  $h = New-FakeHome "m13c-$($tgt.n)"; Add-ExistingInstall $h
  $r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
  Check "[M13c][$($tgt.n)] 前置：1b 成功並印出 ts" ($r.Ok -and $ts) $r.Out
  $r = Invoke-Block $B1c $h
  Check "[M13c][$($tgt.n)] 前置：1c 安裝成功" $r.Ok $r.Out
  Set-Step2Settings $h $ts "[M13c][$($tgt.n)]"
  $m13cRoot = "$h\.claude\skills-backup\超級模式.bak-$ts"
  $m13cLocked = New-LockedDir $m13cRoot
  $beforeSkills = Get-Snapshot "$h\.claude\skills"
  $beforeHome   = Get-Snapshot $h
  $denyRule = Set-DenyEnumerate $m13cLocked
  try {
    $probeOut = Test-EnumBlocked $m13cRoot $h
    Check "[M13c][$($tgt.n)] 前置：列舉真的失敗（在受測 host 內驗證注入生效）" ($probeOut -match 'ENUM=FAIL TYPE=UnauthorizedAccessException') "probe 輸出：$probeOut —— Deny ACE 沒咬到，本案等於沒測"
    $r = Invoke-Block ($m13cMut.Replace($PLACEHOLDER, $ts)) $h
  } finally {
    Clear-DenyEnumerate $m13cLocked $denyRule
  }
  # ⚠️ 這裡**不**釘失敗訊息：Windows 的中止是 `Get-ChildItem` 未攔截的
  # .NET 例外，沒有產品自己的訊息可釘，釘 cmdlet 名稱等於綁死實作。
  # 「非零是不是來自語法錯誤」改由上面的解析檢查結構性排除。
  Check "[M13c][$($tgt.n)] 回滾仍中止" (-not $r.Ok) "竟然成功：$($r.Out)"
  # 這兩條要一起看才有意義：前者證明**缺口真實存在**（只看 skills 會放行違規），
  # 後者證明**加寬確實抓得到**。少了前者，讀者無從判斷加寬有沒有買到東西。
  Check "[M13c][$($tgt.n)] 窄 oracle（只看 skills）看不到這個違規" ((Get-Snapshot "$h\.claude\skills") -eq $beforeSkills) 'skills 也變了，本案已無法示範窄 oracle 的盲點'
  Check "[M13c][$($tgt.n)] 寬 oracle（整個假家目錄）抓到預掃前的 mutation" ((Get-Snapshot $h) -ne $beforeHome) '寬 oracle 也沒抓到 —— 搬移沒生效或加寬無效'
}

"`n[M18] 1c：1b 之後才出現的 reparse point（junction）→ 在第一個 mutation 前中止，live 與 junction 目標都不變"
# 與 POSIX 的 [M18]（假 stat 模擬掛載點）對應（F4 MOUNT-RMRF，Codex 反方：1c 前也要重掃）。
# Windows 用 junction：它與 NTFS 掛載資料夾同為 IO_REPARSE_TAG_MOUNT_POINT，偵測走同一個 ReparsePoint 屬性；
# 建真的掛載資料夾要系統管理員權限，這裡不做（以 junction 覆蓋同一個屬性，推論）。
# sub＝live 的 references 是 junction（1c 的 Copy-Item 會把來源的 references\* 寫進去）；root＝live skill 本身是 junction。
foreach ($case in @(@{ n='子樹'; where='sub' }, @{ n='頂層'; where='root' })) {
  $tag = "m18-$($case.where)"
  $h = New-FakeHome $tag; Add-ExistingInstall $h
  $r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
  Check "[M18][$($case.n)] 前置：1b 成功並印出 ts" ($r.Ok -and $ts) $r.Out
  $tgt = Join-Path $work "$tag-target"
  New-Item -ItemType Directory -Force -Path $tgt | Out-Null
  Set-Content -LiteralPath "$tgt\mounted-payload.txt" -Value 'MOUNTED' -NoNewline
  $jp = if ($case.where -eq 'sub') { "$h\.claude\skills\超級模式\references" } else { "$h\.claude\skills\超級模式" }
  if ($case.where -eq 'root') { Remove-Item -LiteralPath $jp -Recurse -Force }
  cmd /c "mklink /J `"$jp`" `"$tgt`"" | Out-Null
  $mkRc = $LASTEXITCODE
  $e = Get-Item -LiteralPath $jp -Force -ErrorAction SilentlyContinue
  $isJ = ($null -ne $e) -and ((($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) -ne 0)
  # rc ＋型別雙驗（同 M3）：注入沒成功的話，1c 會走一般路徑，本案的區辨力就是假的。
  Check "[M18][$($case.n)] 前置：junction 確實建立" (($mkRc -eq 0) -and $isJ) "mklink rc=$mkRc, isJunction=$isJ"
  $beforeHome = Get-Snapshot $h
  $beforeTgt  = Get-Snapshot $tgt
  $r = Invoke-Block $B1c $h
  Check "[M18][$($case.n)] 1c 中止" (-not $r.Ok) "竟然成功：$($r.Out)"
  Check "[M18][$($case.n)] 中止理由是 link／reparse point 且註明 live 未變更" (($r.Out -match 'reparse point') -and ($r.Out -match '（live 未變更）')) $r.Out
  # 契約是「任何 mutation 之前中止」：看整個假家目錄（1c 在 skill 之後還會複製 hook），不是只看 skills。
  Check "[M18][$($case.n)] 中止後整個假家目錄未變" ((Get-Snapshot $h) -eq $beforeHome) '假家目錄有東西被動過'
  Check "[M18][$($case.n)] junction 目標（模擬掛載的磁碟）沒有被寫入" ((Get-Snapshot $tgt) -eq $beforeTgt) '1c 的 Copy-Item 寫穿到 junction 目標'
}

"`n[C3] 對照組（確認上面的斷言不是永遠為真）"
$h = New-FakeHome 'c3'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
$r = Invoke-Rollback $ts $h
Check '正確 ts 的回滾必須成功（否則上面全是假通過）' $r.Ok $r.Out

} finally {
  Pop-Location
  # 只清理本次建立、且符合本前綴的路徑
  if ($work -match 'ai-install-harness-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Host "work 路徑不符預期前綴，不清理：$work"
  }
}

"`n========================================"
# 摘要行沿用 host **名稱**（不是解析後的絕對路徑）：交接文件與反向驗證都在比對這一行。
"$exeName  PASS=$script:pass  FAIL=$script:fail"
$ranChecks = $script:pass + $script:fail
if ($ranChecks -ne $EXPECTED_CHECKS) {
  "  STOP 案數不符：實跑 $ranChecks、預期 $EXPECTED_CHECKS —— 有案被刪除或跳過，或新增後忘了更新 EXPECTED_CHECKS"
  exit 1
}
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
