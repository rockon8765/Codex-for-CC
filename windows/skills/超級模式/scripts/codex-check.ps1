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
# 可注入執行檔路徑（seam）：production 預設不變，測試用 env 覆寫指向 stub。
# PATH stub 攔不到 C:\npm 絕對路徑，故用專屬 env 注入而非改 PATH。
$codexCmd = if ($env:CODEX_CHECK_CODEX_CMD) { $env:CODEX_CHECK_CODEX_CMD } else { 'C:\npm\codex.cmd' }
$npmCmd   = if ($env:CODEX_CHECK_NPM_CMD)   { $env:CODEX_CHECK_NPM_CMD }   else { 'npm' }
$cache = Join-Path $env:USERPROFILE ".claude\.codex-check-last"

function Show-CapabilitySurface {
  # 唯讀盤點 worker 每次派工實際帶著的能力面（啟用外掛 / MCP / 關鍵旗標）。
  # 全走本地 snapshot、無模型推理，故每次呼叫都印（即使命中 24h smoke 快取），好抓升級造成的能力面漂移。
  Write-Output "=== Codex worker 能力面（唯讀盤點）==="
  $enabled = @()
  $flags = @{}

  try {
    foreach ($ln in (& $codexCmd plugin list 2>$null)) {
      $cols = $ln -split '\s{2,}'
      if ($cols.Count -ge 2 -and $cols[1] -match 'enabled') { $enabled += ($cols[0].Trim() -split '@')[0] }
    }
    Write-Output ("啟用外掛 ({0}): {1}" -f $enabled.Count, $(if ($enabled.Count) { $enabled -join ', ' } else { '(無)' }))
  } catch { Write-Output "啟用外掛: (查詢失敗)" }

  try {
    $servers = @()
    foreach ($ln in (& $codexCmd mcp list 2>$null)) {
      if ([string]::IsNullOrWhiteSpace($ln) -or $ln -match '^\s*Name\s') { continue }
      $name = (($ln -split '\s+') | Where-Object { $_ -ne '' })[0]
      $st = if ($ln -match '\bdisabled\b') { 'disabled' } elseif ($ln -match '\benabled\b') { 'enabled' } else { '?' }
      $servers += ("{0}[{1}]" -f $name, $st)
    }
    Write-Output ("MCP servers ({0}): {1}" -f $servers.Count, $(if ($servers.Count) { $servers -join ', ' } else { '(無)' }))
  } catch { Write-Output "MCP servers: (查詢失敗)" }

  try {
    $trueFeats = @()
    foreach ($ln in (& $codexCmd features list 2>$null)) {
      $t = ($ln -split '\s+') | Where-Object { $_ -ne '' }
      if ($t.Count -ge 2) {
        $flags[$t[0]] = $t[-1]            # 末欄 = enabled(true/false)；status 可能含空格但只取首(name)尾(enabled)
        if ($t[-1] -eq 'true') { $trueFeats += $t[0] }
      }
    }
    # 改為「列出所有 enabled=true 的 feature」而非比對 8 個白名單：升級新增的 stable/true 能力面
    # 會自動被盤到，白名單會漏報漂移(2026-07-10 教訓：hooks/memories/browser_use_full_cdp_access 都不在舊白名單)。
    Write-Output ("啟用 features ({0}): {1}" -f $trueFeats.Count, $(if ($trueFeats.Count) { ($trueFeats | Sort-Object) -join ', ' } else { '(無)' }))
    # 高風險子集：這些若 ON 代表 worker 能力面超出「只讀/只改檔」，升級後尤其要盯。
    $hot = 'hooks','memories','remote_plugin','plugins','skill_mcp_dependency_install','computer_use','browser_use','browser_use_external','browser_use_full_cdp_access','in_app_browser','multi_agent','apps','guardian_approval','network_proxy','respect_system_proxy'
    $hotOn = @($hot | Where-Object { $flags[$_] -eq 'true' })
    if ($hotOn.Count) { Write-Output ("  * 高風險能力面 ON: " + (($hotOn | Sort-Object) -join ', ')) }
  } catch { Write-Output "features: (查詢失敗)" }

  # hooks 盤點(2026-07-10)：hooks 已 stable。config 的 [hooks.state."<id>"] 段列出「受信任、會在
  # codex exec(含唯讀 consult) 時執行」的 hook——這是 read-only 沙箱心智模型之外的執行面，
  # 升級/裝新 plugin 可能靜默新增，故每次盤出來讓人看見。唯讀讀 config.toml，不改任何檔。
  try {
    $cfg = Join-Path $env:USERPROFILE ".codex\config.toml"
    if (Test-Path $cfg) {
      $hooks = @()
      foreach ($ln in (Get-Content -LiteralPath $cfg)) {
        if ($ln -match '^\[hooks\.state\."([^"]+)"\]') { $hooks += (($Matches[1] -split ':')[0]) }
      }
      $hooks = @($hooks | Select-Object -Unique)
      if ($hooks.Count) { Write-Output ("受信任 hooks ({0}): {1}" -f $hooks.Count, ($hooks -join ', ')) }
    }
  } catch {}

  if (($flags['remote_plugin'] -eq 'true') -or $enabled.Count -gt 0) {
    Write-Output "提示: worker 繼承上述全域能力面（>『只改檔』所需）。如需收緊，可於派工時加 --disable <feature> 單次覆寫（例：--disable remote_plugin / --disable plugins）；目前未預設收緊，屬待評估選項。"
  }
  Write-Output ""
}

# 能力面盤點無模型推理、成本低 → 放在 24h 快取檢查之前，每次呼叫都印（貴的 smoke test 仍走快取）。
Show-CapabilitySurface

# H4：命中需「恰一行 + 全行格式（format=2 前綴 + installed/latest/verdict 全欄位 + ISO-ish 時戳）+ 0<=age<86400s」；否則落回全檢。
if (-not $Force -and (Test-Path -LiteralPath $cache)) {
  $cacheLines = @(Get-Content -LiteralPath $cache)
  $fmtOk = ($cacheLines.Count -eq 1) -and ($cacheLines[0] -match '^format=2 installed=[^ ]* latest=.+ verdict=.+ smoke=OK at [0-9]+-[0-9]+-[0-9]+T[0-9:]+[+-][0-9]+$')
  if ($fmtOk) {
    $ageSec = ((Get-Date) - (Get-Item -LiteralPath $cache).LastWriteTime).TotalSeconds
    if ($ageSec -ge 0 -and $ageSec -lt 86400) {
      Write-Output ("codex-check: {0}h 前查過，跳過（-f 強制重查）。上次結果：" -f [int][math]::Floor($ageSec / 3600))
      Get-Content -LiteralPath $cache
      exit 0
    }
  }
}

# H1：優先從 codex(-cli) 錨定行抽版本；抽不到 → $instVer 留空（下方走 UNKNOWN(installed)，不再落回原字串比較）。
$installedRaw = & $codexCmd --version
$instVer = ""
foreach ($ln in @($installedRaw)) {
  $s = [string]$ln
  if ($s -match '^codex(-cli)?\s') {
    $mm = [regex]::Match($s, '\d+\.\d+\.\d+\S*')
    if ($mm.Success) { $instVer = $mm.Value; break }
  }
}

# H3：npm 查詢走 job 完整生命週期 + 20s watchdog。逾時 → Stop-Job、丟棄部分 stdout（不可拿去比對）。
#     env 收緊（retries=0/timeout=15000）與 job 清理都包 try/finally。
# C3：npm 離線/失敗留 $null（不可拿去跟 installed 比，否則離線就誤報 OUTDATED；smoke 才是權威判定）。
$latest = $null
$prevRetries = $env:npm_config_fetch_retries
$prevTimeout = $env:npm_config_fetch_timeout
$env:npm_config_fetch_retries = '0'
$env:npm_config_fetch_timeout = '15000'
$npmJob = $null
try {
  # D2：rc != 0 一律丟棄 stdout（鏡像 bash 的 `if latest_candidate="$(... npm view ...)"`──只在
  #     npm 的原生 exit code = 0 時才採信輸出）。PS job 的 State=Completed 只代表 scriptblock 跑完，
  #     不代表內部 npm 命令 exit 0──故在 job 內把 $LASTEXITCODE 隨輸出一起帶出來；State=Completed
  #     且 Rc=0 才可信任 stdout，Rc 非 0 或收不到（$null）一律當失敗丟棄，不得進 H5。
  $npmJob = Start-Job -ScriptBlock {
    $o = & $using:npmCmd view '@openai/codex' version 2>$null
    [pscustomobject]@{ Out = $o; Rc = $LASTEXITCODE }
  }
  $done = Wait-Job $npmJob -Timeout 20
  $lvRaw = $null
  if ($done -and $npmJob.State -eq 'Completed') {
    $result = @(Receive-Job $npmJob -ErrorAction SilentlyContinue) | Select-Object -Last 1
    if ($result -and ($null -ne $result.Rc) -and ($result.Rc -eq 0)) {
      # & cmd 輸出可能是陣列（多行）；比照舊碼經 Out-String 正規化成單一字串再交給 H5 判文法。
      $lvRaw = (@($result.Out) | Out-String)
    }
    # else：Rc 非 0（含收不到結果時的 $null）→ $lvRaw 留 $null，丟棄 stdout，不進 H5。
  } else {
    Stop-Job $npmJob -ErrorAction SilentlyContinue
  }
  # H5：先拒多行（$lv 含 CR/LF 即棄）再對版本 token 文法全匹配；否則一律當查不到（→ UNKNOWN）。
  if ($lvRaw) {
    $lv = $lvRaw.Trim()
    if ($lv -and ($lv -notmatch '[\r\n]') -and ($lv -match '^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?$')) {
      $latest = $lv
    }
  }
} catch {
  $latest = $null
} finally {
  if ($npmJob) { Remove-Job $npmJob -Force -ErrorAction SilentlyContinue }
  $env:npm_config_fetch_retries = $prevRetries
  $env:npm_config_fetch_timeout = $prevTimeout
}
$latestDisp = if ($latest) { $latest } else { "(unknown - offline)" }

Write-Output "installed: $instVer"
Write-Output "latest:    $latestDisp"
# C3/H1：版本狀態機。任何 UNKNOWN 都不誤報 OUTDATED（smoke test 才是權威可用性判定）。
if (-not $instVer) {
  $verdict = "UNKNOWN (installed 版本解析不到) -- 無法判定新舊，改看下方 smoke test 認定可用性"
} elseif (-not $latest) {
  $verdict = "UNKNOWN (latest 查不到，可能離線) -- 無法判定新舊，改看下方 smoke test 認定可用性"
} elseif ($instVer -eq $latest) {
  $verdict = "UP-TO-DATE"
} else {
  # 語意版本比較（strip prerelease 尾綴後用 [version] 比）；[version] cast 失敗 → UNKNOWN(版本比較失敗)。
  $cmp = $null
  try {
    $ia = [version]([regex]::Match($instVer, '^\d+\.\d+\.\d+').Value)
    $la = [version]([regex]::Match($latest,  '^\d+\.\d+\.\d+').Value)
    $cmp = $ia.CompareTo($la)
  } catch { $cmp = $null }
  if ($null -eq $cmp) {
    $verdict = "UNKNOWN (版本比較失敗) -- 無法判定新舊，改看下方 smoke test 認定可用性"
  } elseif ($cmp -lt 0) {
    $verdict = "BEHIND ($instVer -> $latest) -- 更新屬系統變更，先問使用者再跑 npm install -g @openai/codex@latest"
  } elseif ($cmp -gt 0) {
    $verdict = "AHEAD ($instVer > $latest) -- 本機比 registry 新（prerelease/私建），非落後"
  } else {
    $verdict = "CURRENT ($instVer vs $latest) -- base 版本相同（多半 prerelease 尾綴差異）"
  }
}
Write-Output $verdict

Write-Output "=== read-only smoke test ==="
$tmpDir = $env:TEMP.TrimEnd('\')
# H2：能力探測（非版本閘門）——help 有 --output-last-message 才用精確 sentinel 路徑；沒有 → legacy marker 路徑。
$useLastmsg = $false
try {
  $helpOut = (& $codexCmd exec --help 2>&1) | Out-String
  if ($helpOut -match '--output-last-message') { $useLastmsg = $true }
} catch { $useLastmsg = $false }
# GUID 唯一檔名（絕不用固定名，防讀到上輪 stale sentinel）；跑前刪、finally 刪。
$lastMsgPath = Join-Path $tmpDir ("codex-check-lastmsg.$PID." + [guid]::NewGuid().ToString('N') + ".txt")
if (Test-Path -LiteralPath $lastMsgPath) { Remove-Item -LiteralPath $lastMsgPath -Force -ErrorAction SilentlyContinue }
$smokeExit = 1
$sawSentinel = $false
try {
  # v3 佈線：cmd /s /c + `< NUL`(空 stdin)，prompt 走引號好的 cmd 參數，避開 PS pipe 編碼坑。
  if ($useLastmsg) {
    $inner = '"{0}" exec --sandbox read-only --skip-git-repo-check -C "{1}" --output-last-message "{2}" "Reply with exactly: CODEX_OK" < NUL' -f $codexCmd, $tmpDir, $lastMsgPath
  } else {
    $inner = '"{0}" exec --sandbox read-only --skip-git-repo-check -C "{1}" "Reply with exactly: CODEX_OK" < NUL' -f $codexCmd, $tmpDir
  }
  # C2：捕捉輸出並回顯。光看 exit code 會把「壞掉但 exit 0」的 codex 誤判成可用，故要驗真回了 CODEX_OK。
  $smokeOut = & cmd.exe /d /s /c $inner 2>&1
  $smokeExit = $LASTEXITCODE
  $smokeOut | ForEach-Object { Write-Output $_ }
  if ($useLastmsg) {
    # 精確比對：讀 lastmsg 檔，剝 CR、trim、略空白行後「恰一非空行 -ceq CODEX_OK」。
    if ($smokeExit -eq 0 -and (Test-Path -LiteralPath $lastMsgPath)) {
      $nonBlank = @()
      foreach ($rawLn in (Get-Content -LiteralPath $lastMsgPath)) {
        $tln = ([string]$rawLn -replace "`r", '').Trim()
        if ($tln -ne '') { $nonBlank += $tln }
      }
      if ($nonBlank.Count -eq 1 -and $nonBlank[0] -ceq 'CODEX_OK') { $sawSentinel = $true }
    }
  } else {
    # legacy：user prompt echo 也含 "CODEX_OK"，要 codex 回覆段（"codex" marker 之後）才算數。
    # 先剝 ANSI 顏色碼，免得 codex 灌色時 marker 行變 "<esc>[..mcodex<esc>[0m" 匹配不到 → 假失敗。
    $joined = [regex]::Replace((($smokeOut -join "`n")), "$([char]27)\[[0-9;]*m", "")
    $parts = $joined -split '(?m)^\s*codex\s*$'
    $sawSentinel = ($parts.Count -ge 2) -and ($parts[-1] -match 'CODEX_OK')
  }
} finally {
  if (Test-Path -LiteralPath $lastMsgPath) { Remove-Item -LiteralPath $lastMsgPath -Force -ErrorAction SilentlyContinue }
}

if ($smokeExit -eq 0 -and $sawSentinel) {
  # H4：atomic 寫入——唯一 tmp（$PID + GUID）→ Move-Item -Force；finally 清殘留 tmp。
  # 時戳走 %z 無冒號格式（+0800）以吻合上方讀取 regex；含 format=2 前綴。
  $now = Get-Date
  $ts = $now.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture) + ($now.ToString("zzz", [System.Globalization.CultureInfo]::InvariantCulture) -replace ':', '')
  $cacheLine = "format=2 installed={0} latest={1} verdict={2} smoke=OK at {3}" -f $instVer, $latestDisp, $verdict, $ts
  $cacheTmp = "$cache.tmp.$PID." + [guid]::NewGuid().ToString('N')
  try {
    Set-Content -LiteralPath $cacheTmp -Encoding utf8 -Value $cacheLine
    Move-Item -LiteralPath $cacheTmp -Destination $cache -Force
  } finally {
    if (Test-Path -LiteralPath $cacheTmp) { Remove-Item -LiteralPath $cacheTmp -Force -ErrorAction SilentlyContinue }
  }
  $smoke = 0
} else {
  # smoke 失敗（exit≠0，或 exit 0 但沒回 CODEX_OK sentinel）→ 刪快取，別讓已壞的 codex 在 24h 內被舊快取報成 OK
  if ($smokeExit -eq 0) {
    Write-Warning "codex-check: smoke exit 0 但無精確 CODEX_OK sentinel（codex 可能壞了）-- 刪快取，下次強制重查"
  } else {
    Write-Warning "codex-check: smoke test failed (exit $smokeExit) -- 刪除快取，下次呼叫強制重查"
  }
  Remove-Item -LiteralPath $cache -Force -ErrorAction SilentlyContinue
  $smoke = if ($smokeExit -ne 0) { $smokeExit } else { 1 }
}
exit $smoke
