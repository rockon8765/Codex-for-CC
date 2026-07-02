<#
.SYNOPSIS
  超級模式開關旗標（給 consult-gate hook 用）。
    -On [-Scope <dir>]  啟用。-Scope 限定只在該專案路徑內強制（Windows 專案建議都帶，
                        避免擋到其他 session）；WSL/UNC 專案省略 -Scope 用全域強制。
    -Off                退出：清掉旗標與諮詢憑證。收尾時**必跑**。
    (無參數)            查目前狀態。
.NOTES
  旗標：~/.claude/.super-mode-active（第一行 = Scope 路徑或空；mtime = 啟用時間）。
  憑證：~/.claude/.super-mode-consult-ok（由 codex-consult.ps1 寫）。
  防殘留：hook 會把超過 8 小時的旗標視為 stale 自動解除；但正常收尾仍請跑 -Off。
#>
param([switch]$On, [switch]$Off, [string]$Scope)
$claude = Join-Path $env:USERPROFILE ".claude"
$flag   = Join-Path $claude ".super-mode-active"
$token  = Join-Path $claude ".super-mode-consult-ok"

if ($On) {
  $content = ""
  if ($Scope) {
    $rp = Resolve-Path -LiteralPath $Scope -ErrorAction SilentlyContinue
    if (-not $rp) { Write-Error "Scope 路徑不存在: $Scope（未啟用，避免誤靜默降級為全域強制）"; exit 1 }
    $content = $rp.Path
  }
  Set-Content -LiteralPath $flag -Value $content -Encoding utf8
  if ($content) { Write-Output "super mode: ON  (scope=$content)" }
  else          { Write-Output "super mode: ON  (scope=GLOBAL — 會影響同機所有並行 session；有 Windows 路徑根就建議帶 -Scope)" }
}
elseif ($Off) {
  if (Test-Path $flag)  { Remove-Item -LiteralPath $flag  -Force }
  if (Test-Path $token) { Remove-Item -LiteralPath $token -Force }
  Write-Output "super mode: OFF"
}
else {
  if (Test-Path $flag) {
    $age = (Get-Date) - (Get-Item -LiteralPath $flag).LastWriteTime
    $first = Get-Content -LiteralPath $flag -TotalCount 1
    if ($first) { $first = $first.TrimStart([char]0xFEFF).Trim() }
    # 與 hook 同一判定：像路徑才算 scope，否則全域
    if ($first -match '^([A-Za-z]:[\\/]|\\\\)') { $scopeMsg = "scope=$first" } else { $scopeMsg = "scope=GLOBAL" }
    Write-Output ("super mode: ON  ({0}; age {1:N1}h; 超過 8h 會被 hook 視為殘留自動解除)" -f $scopeMsg, $age.TotalHours)
  } else {
    Write-Output "super mode: OFF"
  }
}
