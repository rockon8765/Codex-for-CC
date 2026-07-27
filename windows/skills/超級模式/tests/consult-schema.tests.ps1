# 參數面回歸：codex-consult.ps1 的 -SchemaFile 驗證 + cmd 注入守衛（T2b），
# 以及 consult/exec 的 -Prompt/-PromptFile 互斥 fail-fast（C5 stage 1）。
# 所有 case 都在「呼叫 codex 之前」失敗(throw) → 不需真 codex、不 mint 憑證、無副作用。
$consult = Join-Path $PSScriptRoot "..\scripts\codex-consult.ps1"
$exec    = Join-Path $PSScriptRoot "..\scripts\codex-exec.ps1"
$dir = "C:\"                       # 安全 -Dir；case 1-4 在 schema 階段就 throw、不會用到它
$tmp = $env:TEMP
$pass = 0; $fail = 0
function T($name, $expect, [hashtable]$params, $scriptPath) {
  if (-not $scriptPath) { $scriptPath = $consult }
  $threw = $false; $msg = ""
  try { & $scriptPath @params 2>&1 | Out-Null } catch { $threw = $true; $msg = "$($_.Exception.Message)" }
  if ($threw -and $msg -match [regex]::Escape($expect)) { Write-Output "PASS  $name"; $script:pass++ }
  else { Write-Output "FAIL  $name (threw=$threw msg=$msg)"; $script:fail++ }
}
# 建「檔名含不安全字元、但內容是合法 JSON」的檔，逼流程走過 Test-Path/Resolve-Path 才撞守衛
$pct = Join-Path $tmp "t2b_pct_%x.json"; Set-Content -LiteralPath $pct -Value '{}' -Encoding utf8
$amp = Join-Path $tmp "t2b_amp_&x.json"; Set-Content -LiteralPath $amp -Value '{}' -Encoding utf8
$bad = Join-Path $tmp "t2b_bad.json";    Set-Content -LiteralPath $bad -Value '{nope' -Encoding utf8

T "schema-not-found"  "SchemaFile not found"  @{ Dir=$dir; Prompt='t'; SchemaFile="C:\__t2b_no_such__.json" }
T "schema-bad-json"   "is not valid JSON"     @{ Dir=$dir; Prompt='t'; SchemaFile=$bad }
T "schema-pct-unsafe" "不安全字元"            @{ Dir=$dir; Prompt='t'; SchemaFile=$pct }
T "schema-amp-unsafe" "不安全字元"            @{ Dir=$dir; Prompt='t'; SchemaFile=$amp }
T "dir-pct-unsafe"    "不安全字元"            @{ Dir='C:\proj\%EVIL%'; Prompt='t' }

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
  $argstr = "-Dir C:\ -Prompt t -SchemaFile $noSchema"
  $inv = if ($preface) { "powershell -NoProfile -Command ""$preface; & '$scriptPath' $argstr""" }
         else          { "powershell -NoProfile -File ""$scriptPath"" $argstr" }
  cmd /c "$inv > ""$o"" 2> ""$er""" | Out-Null
  $so = [string](Get-Content -LiteralPath $o  -Raw -ErrorAction SilentlyContinue)
  $se = [string](Get-Content -LiteralPath $er -Raw -ErrorAction SilentlyContinue)
  Remove-Item -LiteralPath $o, $er -Force -ErrorAction SilentlyContinue
  # 三個條件：stdout 乾淨、deprecation 在 stderr、且流程有走到 deprecation 之後（sentinel 錯誤）
  $ok = ($so -notmatch 'DEPRECATED') -and ($se -match 'DEPRECATED') -and ($se -match 'SchemaFile not found')
  if ($ok) { Write-Output "PASS  $name"; $script:pass++ }
  else { Write-Output "FAIL  $name (stdout=[$so] stderr=[$se])"; $script:fail++ }
}
TStream "c5-deprecation-stderr-only (consult)" $consult $null
TStream "c5-deprecation-stderr-only (exec)"    $exec    $null
TStream "c5-deprecation-not-terminating (WarningPreference=Stop)" $consult "`$WarningPreference='Stop'"

Remove-Item -LiteralPath $pct, $amp, $bad -Force -ErrorAction SilentlyContinue
Write-Output ""
Write-Output ("CONSULT-SCHEMA {0}/{1}" -f $pass, ($pass + $fail))
if ($fail -gt 0) { exit 1 }
