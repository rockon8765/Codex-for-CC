# T2b 回歸：codex-consult.ps1 的 -SchemaFile 驗證 + cmd 注入守衛。
# 所有 case 都在「呼叫 codex 之前」失敗(throw) → 不需真 codex、不 mint 憑證、無副作用。
$consult = Join-Path $PSScriptRoot "..\scripts\codex-consult.ps1"
$dir = "C:\"                       # 安全 -Dir；case 1-4 在 schema 階段就 throw、不會用到它
$tmp = $env:TEMP
$pass = 0; $fail = 0
function T($name, $expect, [hashtable]$params) {
  $threw = $false; $msg = ""
  try { & $consult @params 2>&1 | Out-Null } catch { $threw = $true; $msg = "$($_.Exception.Message)" }
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

Remove-Item -LiteralPath $pct, $amp, $bad -Force -ErrorAction SilentlyContinue
Write-Output ""
Write-Output ("CONSULT-SCHEMA {0}/{1}" -f $pass, ($pass + $fail))
if ($fail -gt 0) { exit 1 }
