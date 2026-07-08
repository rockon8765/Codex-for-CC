<#
.SYNOPSIS
  超級模式 §3 派工前置：確認 Codex CLI 版本並做 read-only smoke test。
  24 小時內查過會直接回報快取結果（-Force 強制重查）。
.NOTES
  Codex 裝於 C:\npm。落後要更新屬系統變更，先問使用者再跑：
    npm install -g @openai/codex@latest   (保持 C:\npm prefix)
  呼叫此腳本時，工具 timeout 請設 360000ms（6 分鐘）— smoke test 走 Codex 推理。
#>
param([switch]$Force)
$ErrorActionPreference = "Stop"
$codex = "C:\npm\codex.ps1"
$cache = Join-Path $env:USERPROFILE ".claude\.codex-check-last"

function Show-CapabilitySurface {
  # 唯讀盤點 worker 每次派工實際帶著的能力面（啟用外掛 / MCP / 關鍵旗標）。
  # 全走本地 snapshot、無模型推理，故每次呼叫都印（即使命中 24h smoke 快取），好抓升級造成的能力面漂移。
  Write-Output "=== Codex worker 能力面（唯讀盤點）==="
  $enabled = @()
  $flags = @{}

  try {
    foreach ($ln in (& "C:\npm\codex.cmd" plugin list 2>$null)) {
      $cols = $ln -split '\s{2,}'
      if ($cols.Count -ge 2 -and $cols[1] -match 'enabled') { $enabled += ($cols[0].Trim() -split '@')[0] }
    }
    Write-Output ("啟用外掛 ({0}): {1}" -f $enabled.Count, $(if ($enabled.Count) { $enabled -join ', ' } else { '(無)' }))
  } catch { Write-Output "啟用外掛: (查詢失敗)" }

  try {
    $servers = @()
    foreach ($ln in (& "C:\npm\codex.cmd" mcp list 2>$null)) {
      if ([string]::IsNullOrWhiteSpace($ln) -or $ln -match '^\s*Name\s') { continue }
      $name = (($ln -split '\s+') | Where-Object { $_ -ne '' })[0]
      $st = if ($ln -match '\bdisabled\b') { 'disabled' } elseif ($ln -match '\benabled\b') { 'enabled' } else { '?' }
      $servers += ("{0}[{1}]" -f $name, $st)
    }
    Write-Output ("MCP servers ({0}): {1}" -f $servers.Count, $(if ($servers.Count) { $servers -join ', ' } else { '(無)' }))
  } catch { Write-Output "MCP servers: (查詢失敗)" }

  try {
    foreach ($ln in (& "C:\npm\codex.cmd" features list 2>$null)) {
      $t = ($ln -split '\s+') | Where-Object { $_ -ne '' }
      if ($t.Count -ge 2) { $flags[$t[0]] = $t[-1] }
    }
    $watch = 'remote_plugin','plugins','computer_use','browser_use','in_app_browser','multi_agent','network_proxy','respect_system_proxy'
    $parts = @()
    foreach ($f in $watch) { if ($flags.ContainsKey($f)) { $parts += ("{0}={1}" -f $f, $(if ($flags[$f] -eq 'true') { 'ON' } else { 'off' })) } }
    if ($parts.Count) { Write-Output ("關鍵旗標: " + ($parts -join '  ')) }
  } catch { Write-Output "關鍵旗標: (查詢失敗)" }

  if (($flags['remote_plugin'] -eq 'true') -or $enabled.Count -gt 0) {
    Write-Output "提示: worker 繼承上述全域能力面（>『只改檔』所需）。如需收緊，可於派工時加 --disable <feature> 單次覆寫（例：--disable remote_plugin / --disable plugins）；目前未預設收緊，屬待評估選項。"
  }
  Write-Output ""
}

# 能力面盤點無模型推理、成本低 → 放在 24h 快取檢查之前，每次呼叫都印（貴的 smoke test 仍走快取）。
Show-CapabilitySurface

if (-not $Force -and (Test-Path $cache)) {
  $age = (Get-Date) - (Get-Item -LiteralPath $cache).LastWriteTime
  if ($age.TotalHours -lt 24) {
    Write-Output ("codex-check: {0:N1}h 前查過，跳過（-Force 強制重查）。上次結果：" -f $age.TotalHours)
    Get-Content -LiteralPath $cache
    exit 0
  }
}

$installedRaw = (& $codex --version) -join ' '
# npm view 離線/不存在時不要整支中止(smoke test 才是權威可用性判定)
try { $latest = (npm view '@openai/codex' version | Out-String).Trim() } catch { $latest = "(unknown - offline)" }
$instVer = if ($installedRaw -match '(\d+\.\d+\.\d+\S*)') { $Matches[1] } else { $installedRaw }

Write-Output "installed: $instVer"
Write-Output "latest:    $latest"
if ($instVer -eq $latest) {
  $verdict = "UP-TO-DATE"
} else {
  $verdict = "OUTDATED ($instVer -> $latest) -- 更新屬系統變更，先問使用者再跑 npm install -g @openai/codex@latest"
}
Write-Output $verdict

Write-Output "=== read-only smoke test ==="
# v3 佈線：cmd /s /c + `< NUL`(空 stdin)，prompt 走引號好的 cmd 參數，避開 PS pipe 編碼坑
$inner = '"{0}" exec --sandbox read-only --skip-git-repo-check -C "{1}" "Reply with exactly: CODEX_OK" < NUL' -f "C:\npm\codex.cmd", $env:TEMP.TrimEnd('\')
& cmd.exe /d /s /c $inner
$smoke = $LASTEXITCODE

if ($smoke -eq 0) {
  Set-Content -LiteralPath $cache -Encoding utf8 -Value ("installed={0} latest={1} verdict={2} smoke=OK at {3}" -f $instVer, $latest, $verdict, (Get-Date -Format o))
} else {
  # smoke 失敗 → 刪快取，別讓已壞的 codex 在 24h 內被舊快取報成 OK
  Write-Warning "codex-check: smoke test failed (exit $smoke) -- 刪除快取，下次呼叫強制重查"
  Remove-Item -LiteralPath $cache -Force -ErrorAction SilentlyContinue
}
exit $smoke
