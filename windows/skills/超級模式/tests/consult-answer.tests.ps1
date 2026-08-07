# consult-answer.tests.ps1 -- 憑證鑄造判準的單元測試
#
# 補的是 Codex 審查指出的缺口：舊的 consult-schema.tests.ps1 只測「啟動 codex 前」的參數錯誤，
# 完全沒有覆蓋鑄證條件；而鑄證條件唯一的驗證方式曾經是「真的叫一次 codex」——要額度、要網路、
# CI 跑不了，等於沒有回歸保護。這裡直接測純函式。
#
# 用法：pwsh -NoProfile -File tests/consult-answer.tests.ps1   （exit 0 = 全過）

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\consult-answer.lib.ps1')

$script:pass = 0
$script:fail = 0
function Check([string]$name, [bool]$cond, [string]$detail = '') {
  if ($cond) { $script:pass++; Write-Output "PASS  $name" }
  else { $script:fail++; Write-Output "FAIL  $name $detail" }
}

$long = 'x' * 80

# --- 一般模式（會鑄證）---
$r = Test-ConsultAnswer -Lines @("ALLOW: 可以做", $long)
Check 'allow-verdict-mints' ($r.Ok -and $r.Verdict -ceq 'ALLOW') ("Ok=$($r.Ok) Verdict=$($r.Verdict)")

$r = Test-ConsultAnswer -Lines @("BLOCK: 不要做", $long)
Check 'block-verdict-mints-with-BLOCK' ($r.Ok -and $r.Verdict -ceq 'BLOCK') ("Verdict=$($r.Verdict)")

$r = Test-ConsultAnswer -Lines @("", "   ", "ALLOW: 前面有空行", $long)
Check 'first-nonempty-line-used' ($r.Ok -and $r.Verdict -ceq 'ALLOW') ("Verdict=$($r.Verdict)")

# --- 拒絕鑄證 ---
$r = Test-ConsultAnswer -Lines @()
Check 'empty-answer-rejected' ((-not $r.Ok) -and $r.Code -eq 43 -and $r.Reason -match 'UNUSABLE') $r.Reason

$r = Test-ConsultAnswer -Lines @("HELLO")
Check 'too-short-rejected' ((-not $r.Ok) -and $r.Code -eq 43) $r.Reason

$r = Test-ConsultAnswer -Lines @("有限狀態機是一種模型，用來描述系統行為。$long")
Check 'long-but-no-verdict-rejected' ((-not $r.Ok) -and $r.Reason -match 'NO_VERDICT') $r.Reason

# 大小寫敏感：PowerShell 的 -match 預設不分大小寫，會讓 'allow:' 意外過關
$r = Test-ConsultAnswer -Lines @("allow: 小寫不算", $long)
Check 'lowercase-verdict-rejected' ((-not $r.Ok) -and $r.Reason -match 'NO_VERDICT') $r.Reason
$r = Test-ConsultAnswer -Lines @("Allow: 混合大小寫不算", $long)
Check 'mixedcase-verdict-rejected' (-not $r.Ok) $r.Reason

# 零寬字元湊字數：'ALLOW:' + 34 個 U+200B 曾可達 40 字門檻
$zw = [string][char]0x200B
$r = Test-ConsultAnswer -Lines @(("ALLOW:" + ($zw * 60)))
Check 'zero-width-padding-rejected' ((-not $r.Ok) -and $r.Code -eq 43) $r.Reason

# 首行有裁決但整體仍過短 → 仍拒（門檻不因有裁決而豁免）
$r = Test-ConsultAnswer -Lines @("ALLOW: ok")
Check 'verdict-but-too-short-rejected' (-not $r.Ok) $r.Reason

# --- 討論模式（不鑄證，不驗裁決格式）---
$r = Test-ConsultAnswer -Lines @("這是一段沒有裁決首行的正常討論回覆。$long") -NoCredential
Check 'discussion-mode-no-verdict-ok' ($r.Ok -and $r.Verdict -eq 'DISCUSSION') ("Ok=$($r.Ok)")
$r = Test-ConsultAnswer -Lines @("短") -NoCredential
Check 'discussion-mode-still-rejects-empty-ish' (-not $r.Ok) $r.Reason

# --- schema 模式：驗 JSON 而非字數 ---
$r = Test-ConsultAnswer -Lines @('{"ok":true}') -SchemaFile 'C:\some\schema.json'
Check 'schema-short-json-accepted' ($r.Ok -and $r.Verdict -eq 'SCHEMA') ("Ok=$($r.Ok) Reason=$($r.Reason)")
$r = Test-ConsultAnswer -Lines @("這不是 JSON，只是四十個字以上的散文說明文字，用來確認 -SchemaFile 不能當免驗金牌。") -SchemaFile 'C:\some\schema.json'
Check 'schema-non-json-rejected' ((-not $r.Ok) -and $r.Reason -match 'NOT_JSON') $r.Reason

Write-Output ""
Write-Output "CONSULT-ANSWER $script:pass/$($script:pass + $script:fail)"
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
