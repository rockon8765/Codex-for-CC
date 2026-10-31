# 參數面回歸：codex-consult.ps1 的 -SchemaFile 驗證 + cmd 注入守衛（T2b），
# 以及 consult/exec 的 -Prompt/-PromptFile 互斥 fail-fast（C5 stage 1）。
# 所有 case 都在「呼叫 codex 之前」失敗(throw) → 不需真 codex、不 mint 憑證。
# ⚠️ 但不是零副作用：dir-pct-unsafe 會先在家目錄建 super-mode-logs、寫空逐字稿才 throw，
#    所以案例一律在暫存家目錄下跑（見下方「家目錄隔離」），並驗證真的 ~/.claude 沒被碰。
#
# ── 受測 host（2026-10-14 LTS C3）──────────────────────────────────────────────
# 本檔的 T 案是**同行程**呼叫受測腳本 ⇒ 受測 host 就是「跑本檔的那個 host」，
# 由 run-windows-suite.ps1 的 manifest 分 pwsh／powershell 兩條腿各跑一次。
# TStream 案要跨 process，原本寫死 `powershell` ⇒ pwsh 腿的 TStream 其實量的是 5.1 child。
# 現在 child 跟著目前 host 走（Core → pwsh、Desktop → powershell），並先做 host 自檢：
# 經同一條 `cmd /c` 路徑叫起 child、讓它自報 PSEdition／PSVersion，必須與目前 host 同 edition、
# 同 major。證據行：
#   CONSULT-SCHEMA-HOST=<本行程 PSEdition> <PSVersion> child=<child PSEdition> <PSVersion>
# suite 的 marker 同時要求這一行與 `CONSULT-SCHEMA n/n`。
# ⚠️ 自檢與 TStream **共用同一個 child 命令列組裝點**（Get-ChildInv；-File 與 -Command 兩種形狀都自檢），
#    並有 AST 守衛（child-launch-site）：Get-ChildInv 之外不得出現以「powershell／pwsh＋空白」開頭的字串
#    字面值，Get-ChildInv 恰好被呼叫 3 次。⚠️ 它擋的是「把既有啟動點換成寫死 host」；另外新增的啟動路徑
#    （裸字指令 powershell、Start-Process、事後 -replace 命令列）擋不住（2026-10-15 審查以變異實測確認）。2026-10-14 合併前審查實測：第一版的自檢另走一條路，把 TStream
#    改回寫死 powershell 之後 pwsh 腿照樣全綠 —— 那樣的自檢不是證據。
$consult = Join-Path $PSScriptRoot "..\scripts\codex-consult.ps1"
$exec    = Join-Path $PSScriptRoot "..\scripts\codex-exec.ps1"
$dir = "C:\"                       # 安全 -Dir；case 1-4 在 schema 階段就 throw、不會用到它
$tmp = $env:TEMP
$pass = 0; $fail = 0

# ⚠️ 只用執行檔**名稱**（經 PATH 解析）而不是 (Get-Process -Id $PID).Path：
#    pwsh 的完整路徑含空白（C:\Program Files\...），塞進 `cmd /c "..."` 會撞 cmd 的引號剝除規則。
$hostEdition = [string]$PSVersionTable.PSEdition
$hostVersion = $PSVersionTable.PSVersion
$childExe = if ($hostEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
# 唯一的 child 命令列組裝點：host 自檢與 TStream 共用（-File 與 -Command 兩種形狀都自檢）。
function Get-ChildInv([string]$scriptPath, [string]$argstr, [string]$preface) {
  if ($preface) { return "$childExe -NoProfile -Command ""$preface; & '$scriptPath' $argstr""" }
  return "$childExe -NoProfile -File ""$scriptPath"" $argstr"
}
$hostProbe = Join-Path $tmp ("cschema_host_" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".ps1")
[System.IO.File]::WriteAllText($hostProbe, ('$PSVersionTable.PSEdition + '' '' + $PSVersionTable.PSVersion.ToString()' + "`r`n"), (New-Object System.Text.UTF8Encoding $true))
$childSaysF = ([string](cmd /c (Get-ChildInv $hostProbe "" "") 2>&1 | Select-Object -Last 1)).Trim()
$childSaysC = ([string](cmd /c (Get-ChildInv $hostProbe "" "`$null = 0") 2>&1 | Select-Object -Last 1)).Trim()
$childSays = $(if ($childSaysF -eq $childSaysC) { $childSaysF } else { "MISMATCH(-File=" + $childSaysF + ";-Command=" + $childSaysC + ")" })
Remove-Item -LiteralPath $hostProbe -Force -ErrorAction SilentlyContinue
Write-Output ("CONSULT-SCHEMA-HOST=" + $hostEdition + " " + $hostVersion.ToString() + " child=" + $childSays)
$childParts = $childSays -split ' '
$childMajor = -1
if ($childParts.Count -ge 2) { try { $childMajor = ([version]$childParts[1]).Major } catch { $childMajor = -1 } }
if (($childParts[0] -eq $hostEdition) -and ($childMajor -eq $hostVersion.Major)) {
  Write-Output "PASS  host-attestation (child=$childExe)"; $pass++
} else {
  Write-Output "FAIL  host-attestation (child=$childExe 自報 [$childSays]，本行程 $hostEdition $hostVersion)"; $fail++
}
# AST 守衛：child 命令列只能由 Get-ChildInv 組（TStream 與 host 自檢同一路徑）；
# 別處出現以「powershell／pwsh＋空白」開頭的字串字面值，就代表有人把它換成寫死 host（範圍見檔頭）。
$csAst = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$null, [ref]$null)
$csLiteral = @($csAst.FindAll({ param($n) (($n -is [System.Management.Automation.Language.StringConstantExpressionAst]) -or ($n -is [System.Management.Automation.Language.ExpandableStringExpressionAst])) -and ($n.Value -match '^(?i)\s*(powershell|pwsh)(\.exe)?\s') }, $true) | Where-Object { $p = $_.Parent; $in = $false; while ($p) { if (($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($p.Name -eq 'Get-ChildInv')) { $in = $true; break }; $p = $p.Parent }; -not $in })
$csCalls = @($csAst.FindAll({ param($n) ($n -is [System.Management.Automation.Language.CommandAst]) -and ($n.GetCommandName() -eq 'Get-ChildInv') }, $true)).Count
if (($csLiteral.Count -eq 0) -and ($csCalls -eq 3)) { Write-Output "PASS  child-launch-site (Get-ChildInv x3)"; $pass++ }
else { Write-Output ("FAIL  child-launch-site (calls=" + $csCalls + " literal=" + (($csLiteral | ForEach-Object { 'L' + $_.Extent.StartLineNumber }) -join ',') + ")"); $fail++ }
function T($name, $expect, [hashtable]$params, $scriptPath) {
  if (-not $scriptPath) { $scriptPath = $consult }
  $threw = $false; $msg = ""
  try { & $scriptPath @params 2>&1 | Out-Null } catch { $threw = $true; $msg = "$($_.Exception.Message)" }
  if ($threw -and $msg -match [regex]::Escape($expect)) { Write-Output "PASS  $name"; $script:pass++ }
  else { Write-Output "FAIL  $name (threw=$threw msg=$msg)"; $script:fail++ }
}
# ── 家目錄隔離（2026-10-15；backlog CONSULT-SCHEMA-HOME-LEAK）──────────────────────────
# 受測的 codex-consult.ps1 會先建 $env:USERPROFILE\.claude\super-mode-logs、寫一個空逐字稿，之後才驗 -Dir
# （dir-pct-unsafe 就走到這一步才 throw）。所以下面所有案例一律在本檔自建的暫存家目錄下跑；
# TStream 的 child 經 cmd /c 繼承同一個 USERPROFILE。2026-10-15 之前沒有隔離：每跑一次就在真的
# ~/.claude 留一個 0 byte 逐字稿，CI 的 postflight（~/.claude 必須不存在）也因此必紅。
$realHome = $env:USERPROFILE
$realClaude = Join-Path $realHome ".claude"
$realLogDir = Join-Path $realClaude "super-mode-logs"
function Get-RealLogNames {
  if (Test-Path -LiteralPath $realLogDir) { return @(Get-ChildItem -LiteralPath $realLogDir -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }
  return @()
}
$realClaudeBefore = Test-Path -LiteralPath $realClaude
$realLogBefore = Get-RealLogNames
$fakeHome = Join-Path $tmp ("cschema_home_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $fakeHome -Force | Out-Null
$env:USERPROFILE = $fakeHome
try {
  # 建「檔名含不安全字元、但內容是合法 JSON」的檔，逼流程走過 Test-Path/Resolve-Path 才撞守衛
  $pct = Join-Path $tmp "t2b_pct_%x.json"; Set-Content -LiteralPath $pct -Value '{}' -Encoding utf8
  $caret = Join-Path $tmp "t2b_caret_^x.json"; Set-Content -LiteralPath $caret -Value '{}' -Encoding utf8
  $ampCmd = Join-Path $tmp "t2b_amp_&x.cmd"; Set-Content -LiteralPath $ampCmd -Value '@echo off' -Encoding ascii
  $ampJson = Join-Path $tmp "t2b_amp_&x.json"; Set-Content -LiteralPath $ampJson -Value '{}' -Encoding utf8
  $stubCmd = Join-Path $tmp "t2b_stub.cmd"; Set-Content -LiteralPath $stubCmd -Value '@exit /b 0' -Encoding ascii
  $nodeCmd = Join-Path $tmp "t2b_node.cmd"
  Set-Content -LiteralPath $nodeCmd -Value ('@"' + (Get-Command node -CommandType Application | Select-Object -First 1).Source + '" %*') -Encoding ascii
  $bad = Join-Path $tmp "t2b_bad.json";    Set-Content -LiteralPath $bad -Value '{nope' -Encoding utf8

  T "schema-not-found"  "SchemaFile not found"  @{ Dir=$dir; Prompt='t'; SchemaFile="C:\__t2b_no_such__.json" }
  T "schema-bad-json"   "is not valid JSON"     @{ Dir=$dir; Prompt='t'; SchemaFile=$bad }
  T "schema-pct-unsafe" "不安全字元"            @{ Dir=$dir; Prompt='t'; SchemaFile=$pct }
  # & 只對 -Dir／-SchemaFile 放行（正向案例在 project-root-marker.tests.ps1 的 H，那裡才有 stub 擋住真 codex）；其餘字元照擋。
  T "schema-caret-unsafe" "不安全字元"          @{ Dir=$dir; Prompt='t'; SchemaFile=$caret }
  T "dir-pct-unsafe"    "不安全字元"            @{ Dir='C:\proj\%EVIL%'; Prompt='t' }
  T "dir-bang-unsafe"   "不安全字元"            @{ Dir='C:\proj\!EVIL!'; Prompt='t' }
  T "dir-caret-unsafe"  "不安全字元"            @{ Dir='C:\proj\a^b'; Prompt='t' }
  # 接縫路徑不放行 &：npm 的 codex.cmd 有未加引號的 SET dp0=%~dp0，shim 放在含 & 的目錄會斷句。
  $env:SUPER_MODE_CODEX_CMD = $ampCmd
  T "override-amp-unsafe" "不安全字元"          @{ Dir=$dir; Prompt='t' }
  Remove-Item -LiteralPath Env:SUPER_MODE_CODEX_CMD -ErrorAction SilentlyContinue
  $env:SUPER_MODE_CODEX_CMD_EXEC = $ampCmd
  T "exec-override-amp-unsafe" "不安全字元"     @{ Dir=$dir; Prompt='t' } $exec
  Remove-Item -LiteralPath Env:SUPER_MODE_CODEX_CMD_EXEC -ErrorAction SilentlyContinue
  # exec 放寬後的守衛也要有負向案例。exec 是 workspace-write，守衛一旦退化不能走到真 codex ⇒ 先把接縫指向 stub。
  $env:SUPER_MODE_CODEX_CMD_EXEC = $stubCmd
  T "exec-schema-pct-unsafe" "不安全字元"       @{ Dir=$dir; Prompt='t'; SchemaFile=$pct } $exec
  T "exec-schema-caret-unsafe" "不安全字元"     @{ Dir=$dir; Prompt='t'; SchemaFile=$caret } $exec
  T "exec-dir-pct-unsafe" "不安全字元"          @{ Dir='C:\proj\%EVIL%'; Prompt='t' } $exec
  T "exec-dir-bang-unsafe" "不安全字元"         @{ Dir='C:\proj\!EVIL!'; Prompt='t' } $exec
  T "exec-dir-caret-unsafe" "不安全字元"        @{ Dir='C:\proj\a^b'; Prompt='t' } $exec
  Remove-Item -LiteralPath Env:SUPER_MODE_CODEX_CMD_EXEC -ErrorAction SilentlyContinue
  # --check-json 不走 $inner：node 是批次檔時，含 & 的 schema 路徑要在呼叫 node 之前就擋下。
  $env:SUPER_MODE_NODE = $nodeCmd
  $env:SUPER_MODE_CODEX_CMD = $stubCmd
  T "schema-amp-batch-node" "node 是批次檔"     @{ Dir=$dir; Prompt='t'; SchemaFile=$ampJson }
  Remove-Item -LiteralPath Env:SUPER_MODE_NODE, Env:SUPER_MODE_CODEX_CMD -ErrorAction SilentlyContinue

  # C5 stage 1：-Prompt 與 -PromptFile 互斥。舊行為是靜默採用 -PromptFile，呼叫端不會發現
  # 自己的 inline 簡報被丟掉 → 改 fail-fast。consult 與 exec 都要有，兩者是同一個坑。
  T "consult-both-prompt-and-file" "同時給了 -Prompt 與 -PromptFile" @{ Dir=$dir; Prompt='t'; PromptFile=$bad }
  T "exec-both-prompt-and-file"    "同時給了 -Prompt 與 -PromptFile" @{ Dir=$dir; Prompt='t'; PromptFile=$bad } $exec

  # C5 相容性契約：deprecation 通知**只能走 stderr**。
  # 為什麼要跨 process 測：Write-Warning 在同一個 PowerShell session 內是 stream 3，看起來沒問題，
  # 但用 powershell.exe -File 呼叫時 warning 會落到 OS stdout —— codex-exec 的 -Quiet 模式 stdout
  # 就是給呼叫端讀的摘要、--output-schema 的呼叫端也解析 stdout，被 "WARNING:" 前綴污染就壞了。
  # 另外 $WarningPreference='Stop' 會把 Write-Warning 變成 ActionPreferenceStopException，
  # 違背 staged deprecation「inline 仍可跑」的承諾。兩者都實測重現過，故改用 [Console]::Error。
  $noSchema = "C:\__c5_no_such_schema__.json"
  function TStream($name, $scriptPath, $preface) {
    $id = [guid]::NewGuid().ToString('N').Substring(0, 6)
    $o = Join-Path $tmp "c5_$id.out"; $er = Join-Path $tmp "c5_$id.err"
    # 隔離（縱深防禦）：-Dir 用保證不存在的 GUID 路徑、consult 額外帶 -NoCredential。
    # 正常情況下 sentinel 在啟動 codex 之前就 throw，根本走不到；但萬一日後重構讓
    # missing-schema 不再 fail-fast，這兩道能擋住「測試意外啟動真 Codex、甚至 mint 全機憑證」。
    $isolatedDir = "C:\__c5_no_such_dir_$id"
    $extra = if ($scriptPath -like "*codex-consult.ps1") { " -NoCredential" } else { "" }
    $argstr = "-Dir $isolatedDir -Prompt t -SchemaFile $noSchema$extra"
    # child host 跟著目前 host 走（見檔頭）；原本兩條都寫死 powershell。
    $inv = Get-ChildInv $scriptPath $argstr $preface
    cmd /c "$inv > ""$o"" 2> ""$er""" | Out-Null
    $rc = $LASTEXITCODE
    $so = [string](Get-Content -LiteralPath $o  -Raw -ErrorAction SilentlyContinue)
    $se = [string](Get-Content -LiteralPath $er -Raw -ErrorAction SilentlyContinue)
    Remove-Item -LiteralPath $o, $er -Force -ErrorAction SilentlyContinue
    # 四個條件：子行程確實失敗（沒有意外跑成功）、stdout 乾淨、deprecation 在 stderr、
    # 且流程有走到 deprecation 之後（命中 sentinel）。
    $ok = ($rc -ne 0) -and ($so -notmatch 'DEPRECATED') -and ($se -match 'DEPRECATED') -and ($se -match 'SchemaFile not found')
    if ($ok) { Write-Output "PASS  $name"; $script:pass++ }
    else { Write-Output "FAIL  $name (rc=$rc stdout=[$so] stderr=[$se])"; $script:fail++ }
  }
  TStream "c5-deprecation-stderr-only (consult)" $consult $null
  TStream "c5-deprecation-stderr-only (exec)"    $exec    $null
  TStream "c5-deprecation-not-terminating (WarningPreference=Stop)" $consult "`$WarningPreference='Stop'"
}
finally {
  $env:USERPROFILE = $realHome
}
# 隔離的證據：真的 ~/.claude 沒被建出來、真的 logdir 沒有多出檔案。
# ⚠️ 同一時間若另有真的 consult 在跑，真的 logdir 會多出檔案而誤報 FAIL（推論，未遇過）。
$realLogNew = @(Get-RealLogNames | Where-Object { $realLogBefore -notcontains $_ })
$claudeCreated = (-not $realClaudeBefore) -and (Test-Path -LiteralPath $realClaude)
if (($realLogNew.Count -eq 0) -and (-not $claudeCreated)) { Write-Output "PASS  real-home-untouched"; $pass++ }
else { Write-Output ("FAIL  real-home-untouched (真的 logdir 新增=" + ($realLogNew -join ',') + " 建出 .claude=" + $claudeCreated + ")"); $fail++ }
Remove-Item -LiteralPath $fakeHome -Recurse -Force -ErrorAction SilentlyContinue

Remove-Item -LiteralPath $pct, $caret, $ampCmd, $ampJson, $stubCmd, $nodeCmd, $bad -Force -ErrorAction SilentlyContinue
Write-Output ""
Write-Output ("CONSULT-SCHEMA {0}/{1}" -f $pass, ($pass + $fail))
# else 分支不可省。實測三種呼叫方式的差別：
#   `pwsh -File 本檔`（獨立行程）—— 舊版也回 0/1，這條路徑本來就是對的
#   `& 本檔` / dot-source（同一個 PowerShell process 內）—— 舊版成功時回**非零**，
#     因為不呼叫 exit 時 $LASTEXITCODE 沿用本檔最後一個 native 指令
#     （TStream 裡的 cmd /c，那條「刻意期望非零」）的值
# 修的是後者：讓 in-process 呼叫端（例如把多支測試包成一輪的聚合腳本）也拿到 0/1。
# POSIX 版靠末行 `[ "$fail" -eq 0 ]` 天然沒這問題；同目錄 codex-check.tests.ps1 已是此寫法。
if ($fail -gt 0) { exit 1 } else { exit 0 }
