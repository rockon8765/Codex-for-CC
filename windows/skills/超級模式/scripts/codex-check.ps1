<#
.SYNOPSIS
  超級模式 §3 派工前置：確認 Codex CLI 版本並做 read-only smoke test。
  24 小時內查過會直接回報快取結果（-Force 強制重查）。
.NOTES
  Codex 裝於 C:\npm。落後要更新屬系統變更，先問使用者再跑：
    npm install -g @openai/codex@latest   (保持 C:\npm prefix)
  呼叫此腳本時，工具 timeout 請設 360000ms（6 分鐘）— smoke test 走 Codex 推理。
  能力面 baseline（~/.claude/.codex-check-baseline）：不自動建立——無 baseline 時警示 NO_BASELINE，
  以 -UpdateBaseline 建立/更新（唯一支援途徑；先過盤點檢查、等 smoke 通過才落檔）。結果以輸出行
  UPDATE_BASELINE=OK / REFUSED / NOT_APPLIED 為權威訊號（被拒回 exit 2，但 smoke 失敗 passthrough 也可能
  是 2，automation 勿只看 exit code）。姿態 A：漂移只警示、不影響 exit code；依賴旗標缺失時不寫也不採信
  smoke 快取（不讓 24h 快取蓋掉不相容訊號）。
#>
param([switch]$Force, [switch]$UpdateBaseline)
$ErrorActionPreference = "Stop"
# -UpdateBaseline 通過盤點檢查後先掛起，等 smoke 通過（或快取命中=近期 smoke OK）才真正落檔（見 Invoke-BaselineCheck）。
$baselinePending = $false
# 可注入執行檔路徑（seam）：production 預設不變，測試用 env 覆寫指向 stub。
# PATH stub 攔不到 C:\npm 絕對路徑，故用專屬 env 注入而非改 PATH。
$codexCmd = if ($env:CODEX_CHECK_CODEX_CMD) { $env:CODEX_CHECK_CODEX_CMD } else { 'C:\npm\codex.cmd' }
$npmCmd   = if ($env:CODEX_CHECK_NPM_CMD)   { $env:CODEX_CHECK_NPM_CMD }   else { 'npm' }
$cache = Join-Path $env:USERPROFILE ".claude\.codex-check-last"
$baselineFile = Join-Path $env:USERPROFILE ".claude\.codex-check-baseline"
# consult/exec 腳本實際依賴的 exec 旗標（升級後若從 help 消失＝相容性斷裂訊號，要大聲講）。
# 短旗標 -C/-c 也是真依賴，但 help 內單字母比對誤報率高（易撞其他旗標/縮寫），不納入探測——
# 其為 CLI 核心介面，消失時上述長旗標幾乎必同動。
$requiredFlags = @('--ephemeral', '--output-last-message', '--output-schema', '--sandbox', '--skip-git-repo-check')
# baseline 段落序（也是檔內行序；captured 不參與比對）
$capSections = @('codex_version', 'exec_flags', 'plugins', 'mcp', 'features', 'hooks')

# H1（前移）：版本抽取原在快取檢查後；能力面 snapshot 要含版本、快取命中要驗版本一致（堵「24h 內
# 升級仍回報舊結果」的盲點），故每次呼叫先讀。錨定行優先 → 退回第一個版本樣 token → 抽不到留空走 UNKNOWN(installed)。
$instVer = ""
try {
  $installedRaw = @(& $codexCmd --version)
  foreach ($ln in $installedRaw) {
    $s = [string]$ln
    if ($s -match '^codex(-cli)?\s') {
      $mm = [regex]::Match($s, '\d+\.\d+\.\d+\S*')
      if ($mm.Success) { $instVer = $mm.Value; break }
    }
  }
  if (-not $instVer) {
    # D5 fallback：錨定行沒有才退回全輸出第一個版本樣 token（banner 誤中風險見規劃書 D5）。
    foreach ($ln in $installedRaw) {
      $mm2 = [regex]::Match([string]$ln, '[0-9]+\.[0-9]+\.[0-9]+[^ ]*')
      if ($mm2.Success) { $instVer = $mm2.Value; break }
    }
  }
} catch { $instVer = "" }

# H2 help（前移、單次抓取）：同時供 (a) skill 依賴旗標探測 (b) smoke 的 --output-last-message 能力判定。
# stderr 合流下沉 cmd 層（鏡像 smoke 的 4c3d477 修法）：PS 5.1 EAP=Stop 下 PS 層 2>&1 會把 native stderr
# 包成 terminating NativeCommandError，一行噪音就整段炸成 FAILED（2026-07-16 對抗審查實測重現）。
# rc 必須 =0 才採信（clap 出錯時 usage 文字也含旗標名，rc!=0 的輸出不可拿來當 help）。
$helpOut = ''
$helpOk = $false
try {
  $helpOut = (& cmd.exe /d /s /c ('"{0}" exec --help 2>&1' -f $codexCmd)) | Out-String
  if ($LASTEXITCODE -eq 0 -and $helpOut) { $helpOk = $true }
} catch { $helpOk = $false }
$useLastmsg = ($helpOk -and ($helpOut -match '--output-last-message'))

# 能力面 snapshot：每段回 Items（排序正規化）+ Status 四態（OK / EMPTY / UNPARSEABLE / FAILED）。
# FAILED      = 查詢丟例外或 rc!=0（查不到 ≠ 能力消失，絕不當成「無能力」）；
# UNPARSEABLE = rc=0、有輸出但解析 0 筆（或 mcp state 全 '?'）—— 疑升級改了輸出格式，禁止寫進 baseline
#               （堵「parser 壞掉 → EMPTY → -UpdateBaseline 一鍵洗白」的門，Codex 諮詢 2026-07-16）；
# EMPTY       = rc=0 且原始輸出為空 —— 大概率真的沒有（與非空 baseline 比對時仍走歧義警示）。
# features 例外：只要解析到表（含全 false）即 OK，Items=enabled=true 清單 → true→false 翻轉呈現為真漂移。
function Get-CapabilitySnapshot {
  $snap = @{}

  $p = @{ Items = @(); Status = 'FAILED' }
  try {
    # stderr 丟棄下沉 cmd 層（2>NUL）：同 help 的 PS 5.1 EAP=Stop stderr 地雷（見上）。
    $lines = @(& cmd.exe /d /s /c ('"{0}" plugin list 2>NUL' -f $codexCmd)); $rc = $LASTEXITCODE
    if ($rc -eq 0) {
      # rawN 排除已知 boilerplate（零外掛訊息 'No ...'、Marketplace 前導/路徑行、表頭）：
      # 乾淨機器零外掛屬 EMPTY 而非 UNPARSEABLE，否則新機永遠建不了 baseline（2026-07-16 真 codex 實測）。
      $rawN = @($lines | Where-Object { -not ([string]::IsNullOrWhiteSpace($_) -or $_ -match '^\s*No\b' -or $_ -match '(?i)marketplace' -or $_ -match '^\s*PLUGIN(\s|$)') }).Count
      foreach ($ln in $lines) {
        $cols = $ln -split '\s{2,}'
        # 保留完整 name@marketplace 識別：@ 尾綴是 marketplace 限定詞（VERSION 是獨立欄），
        # 剝掉會讓「同名外掛換 marketplace」在 diff 隱形（供應鏈識別變更正是 baseline 要抓的）。
        if ($cols.Count -ge 2 -and $cols[1] -match 'enabled') { $p.Items += $cols[0].Trim() }
      }
      $p.Status = if ($p.Items.Count) { 'OK' } elseif ($rawN -gt 0) { 'UNPARSEABLE' } else { 'EMPTY' }
    }
  } catch {}
  $p.Items = @($p.Items | Sort-Object)
  $snap['plugins'] = $p

  $m = @{ Items = @(); Status = 'FAILED' }
  try {
    $lines = @(& cmd.exe /d /s /c ('"{0}" mcp list 2>NUL' -f $codexCmd)); $rc = $LASTEXITCODE
    if ($rc -eq 0) {
      # 'No MCP servers configured...' 屬零項 boilerplate → 排除於解析與 rawN（乾淨機器走 EMPTY）
      $rawN = @($lines | Where-Object { -not ([string]::IsNullOrWhiteSpace($_) -or $_ -match '^\s*Name\s' -or $_ -match '^\s*No\b') }).Count
      foreach ($ln in $lines) {
        if ([string]::IsNullOrWhiteSpace($ln) -or $ln -match '^\s*Name\s' -or $ln -match '^\s*No\b') { continue }
        # @() 強制陣列：單 token 行經管線 unroll 成 scalar String 後 [0] 會取到首字元（Char）
        $toks = @(($ln -split '\s+') | Where-Object { $_ -ne '' })
        if (-not $toks.Count) { continue }
        $name = $toks[0]
        $st = if ($ln -match '\bdisabled\b') { 'disabled' } elseif ($ln -match '\benabled\b') { 'enabled' } else { '?' }
        $m.Items += ("{0}[{1}]" -f $name, $st)
      }
      $unk = @($m.Items | Where-Object { $_ -match '\[\?\]$' }).Count
      # state 全部判不出（全 '?'）＝疑格式失真，不是可接受的新能力面 → UNPARSEABLE
      if ($m.Items.Count -and $unk -eq $m.Items.Count) { $m.Status = 'UNPARSEABLE' }
      elseif ($m.Items.Count) { $m.Status = 'OK' }
      elseif ($rawN -gt 0) { $m.Status = 'UNPARSEABLE' }
      else { $m.Status = 'EMPTY' }
    }
  } catch {}
  $m.Items = @($m.Items | Sort-Object)
  $snap['mcp'] = $m

  $f = @{ Items = @(); Status = 'FAILED'; Flags = @{} }
  try {
    $lines = @(& cmd.exe /d /s /c ('"{0}" features list 2>NUL' -f $codexCmd)); $rc = $LASTEXITCODE
    if ($rc -eq 0) {
      $rawN = @($lines | Where-Object { -not ([string]::IsNullOrWhiteSpace($_) -or $_ -match '^\s*No\b') }).Count
      foreach ($ln in $lines) {
        $t = ($ln -split '\s+') | Where-Object { $_ -ne '' }
        if ($t.Count -ge 2) {
          $f.Flags[$t[0]] = $t[-1]          # 末欄 = enabled(true/false)；status 可能含空格但只取首(name)尾(enabled)
          if ($t[-1] -eq 'true') { $f.Items += $t[0] }
        }
      }
      $f.Status = if ($f.Flags.Count) { 'OK' } elseif ($rawN -gt 0) { 'UNPARSEABLE' } else { 'EMPTY' }
    }
  } catch {}
  $f.Items = @($f.Items | Sort-Object)
  $snap['features'] = $f

  # hooks 盤點(2026-07-10)：config 的 [hooks.state."<id>"] 段＝「受信任、會在 codex exec(含唯讀 consult)
  # 時執行」的 hook——read-only 沙箱心智模型之外的執行面。本地檔自控格式：檔不存在＝真的無 hooks
  # （OK 空、非 EMPTY 歧義）。唯讀讀 config.toml，不改任何檔。
  $h = @{ Items = @(); Status = 'OK' }
  try {
    $cfg = Join-Path $env:USERPROFILE ".codex\config.toml"
    $cfgRaw = ''
    if (Test-Path $cfg) {
      $cfgRaw = [string](Get-Content -LiteralPath $cfg -Raw)
      foreach ($ln in ($cfgRaw -split "`r?`n")) {
        if ($ln -match '^\[hooks\.state\."([^"]+)"\]') { $h.Items += (($Matches[1] -split ':')[0]) }
      }
    }
    $h.Items = @($h.Items | Select-Object -Unique | Sort-Object)
    # config 內有 hooks.state 段但一筆都解析不到（如 TOML 改用單引號/裸鍵序列化）→ UNPARSEABLE，
    # 不可当成「無 hooks」寫進 baseline（hooks 是 read-only 心智模型外的執行面，洗白代價最高）。
    if ($h.Items.Count -eq 0 -and $cfgRaw -match 'hooks\.state') { $h.Status = 'UNPARSEABLE' }
  } catch { $h.Status = 'FAILED' }
  $snap['hooks'] = $h

  $fl = @{ Items = @(); Status = 'FAILED' }
  if ($helpOk) {
    foreach ($rf in $requiredFlags) {
      # 旗標邊界比對：--sandbox 不得被 --sandbox-policy 之類的近似旗標滿足（前後須為空白/=/</,/行界）
      if ($helpOut -match ('(?m)(^|[\s,])' + [regex]::Escape($rf) + '([\s=<,]|$)')) { $fl.Items += $rf }
    }
    $fl.Status = if ($fl.Items.Count) { 'OK' } else { 'UNPARSEABLE' }
  }
  $fl.Items = @($fl.Items | Sort-Object)
  $snap['exec_flags'] = $fl

  $v = @{ Items = @(); Status = 'FAILED' }
  if ($instVer) { $v.Items = @($instVer); $v.Status = 'OK' }
  $snap['codex_version'] = $v

  return $snap
}

function Show-CapabilitySurface {
  # 唯讀盤點 worker 每次派工實際帶著的能力面（啟用外掛 / MCP / 關鍵旗標）。
  # 全走本地 snapshot、無模型推理，故每次呼叫都印（即使命中 24h smoke 快取），好抓升級造成的能力面漂移。
  param($snap)
  Write-Output "=== Codex worker 能力面（唯讀盤點）==="

  $p = $snap['plugins']
  if ($p.Status -eq 'FAILED') { Write-Output "啟用外掛: (查詢失敗)" }
  elseif ($p.Status -eq 'UNPARSEABLE') { Write-Output "啟用外掛: (UNPARSEABLE -- 有輸出但解析 0 筆，疑升級改了輸出格式，請人工確認)" }
  else { Write-Output ("啟用外掛 ({0}): {1}" -f $p.Items.Count, $(if ($p.Items.Count) { $p.Items -join ', ' } else { '(無)' })) }

  $m = $snap['mcp']
  if ($m.Status -eq 'FAILED') { Write-Output "MCP servers: (查詢失敗)" }
  elseif ($m.Status -eq 'UNPARSEABLE') { Write-Output "MCP servers: (UNPARSEABLE -- 有輸出但無法解析/state 全 '?'，疑格式失真，請人工確認)" }
  else { Write-Output ("MCP servers ({0}): {1}" -f $m.Items.Count, $(if ($m.Items.Count) { $m.Items -join ', ' } else { '(無)' })) }

  $f = $snap['features']
  if ($f.Status -eq 'FAILED') { Write-Output "features: (查詢失敗)" }
  elseif ($f.Status -eq 'UNPARSEABLE') { Write-Output "features: (UNPARSEABLE -- 有輸出但解析 0 筆，疑升級改了輸出格式，請人工確認)" }
  else {
    # 「列出所有 enabled=true 的 feature」而非比對 8 個白名單：升級新增的 stable/true 能力面
    # 會自動被盤到，白名單會漏報漂移(2026-07-10 教訓：hooks/memories/browser_use_full_cdp_access 都不在舊白名單)。
    Write-Output ("啟用 features ({0}): {1}" -f $f.Items.Count, $(if ($f.Items.Count) { $f.Items -join ', ' } else { '(無)' }))
    # 高風險子集：這些若 ON 代表 worker 能力面超出「只讀/只改檔」，升級後尤其要盯。
    $hot = 'hooks','memories','remote_plugin','plugins','skill_mcp_dependency_install','computer_use','browser_use','browser_use_external','browser_use_full_cdp_access','in_app_browser','multi_agent','apps','guardian_approval','network_proxy','respect_system_proxy'
    $hotOn = @($hot | Where-Object { $f.Flags[$_] -eq 'true' })
    if ($hotOn.Count) { Write-Output ("  * 高風險能力面 ON: " + (($hotOn | Sort-Object) -join ', ')) }
  }

  $h = $snap['hooks']
  if ($h.Status -eq 'FAILED') { Write-Output "受信任 hooks: (解析失敗)" }
  elseif ($h.Status -eq 'UNPARSEABLE') { Write-Output "受信任 hooks: (UNPARSEABLE -- config 有 hooks.state 段但解析 0 筆，疑序列化格式變更，請人工確認)" }
  elseif ($h.Items.Count) { Write-Output ("受信任 hooks ({0}): {1}" -f $h.Items.Count, ($h.Items -join ', ')) }

  # skill 依賴旗標探測：升級後旗標從 exec --help 消失＝consult/exec 腳本可能已不相容，要大聲講。
  $fl = $snap['exec_flags']
  if ($fl.Status -eq 'FAILED') { Write-Output "skill 依賴旗標: (exec --help 查詢失敗，無法探測)" }
  elseif ($fl.Status -eq 'UNPARSEABLE') { Write-Output "skill 依賴旗標: (UNPARSEABLE -- help 有輸出但一個依賴旗標都比對不到，疑 help 格式大改，請人工確認)" }
  else {
    $missing = @($requiredFlags | Where-Object { $fl.Items -notcontains $_ })
    if ($missing.Count) { Write-Output ("  * 警告: skill 依賴旗標不在 exec --help: {0} -- consult/exec 腳本可能已不相容，升級後請重驗" -f ($missing -join ', ')) }
  }

  if (($f.Status -ne 'FAILED' -and $f.Flags['remote_plugin'] -eq 'true') -or $p.Items.Count -gt 0) {
    Write-Output "提示: worker 繼承上述全域能力面（>『只改檔』所需）。如需收緊，可於派工時加 --disable <feature> 單次覆寫（例：--disable remote_plugin / --disable plugins）；目前未預設收緊，屬待評估選項。"
  }
  Write-Output ""
}

# --- 能力面 baseline：機器 diff 取代「印出來靠人眼比」（2026-07-16，Codex 諮詢定案）。 ---
# 姿態 A：只警示、不改 exit code、不擋派工。唯一更新途徑 = -UpdateBaseline（人為/AI 檢視後的明確動作），
# 絕不因偵測到漂移而自動改寫——否則 baseline 淪為「上次看到什麼」而非「上次接受什麼」。
function Read-BaselineFile {
  # 回 hashtable；檔不存在回 $null；存在但格式不符回 @{ corrupt=$true }（不自動覆寫，防誤蓋真 baseline）。
  if (-not (Test-Path -LiteralPath $baselineFile)) { return $null }
  $h = @{}
  try {
    foreach ($ln in (Get-Content -LiteralPath $baselineFile)) {
      if ([string]$ln -match '^([a-z_]+)=(.*)$') {
        if ($h.ContainsKey($Matches[1])) { return @{ corrupt = $true } }   # 重複 key 拒收（嚴格 parser）
        $h[$Matches[1]] = $Matches[2]
      }
    }
  } catch { return @{ corrupt = $true } }
  if ($h['format'] -ne '1') { return @{ corrupt = $true } }
  foreach ($k in $capSections) { if (-not $h.ContainsKey($k)) { return @{ corrupt = $true } } }
  return $h
}

function Write-BaselineFile {
  # atomic：唯一 tmp → Move-Item -Force（同快取寫入模式）。行式格式方便人讀與未來 bash 移植。
  param($snap)
  $lines = @('format=1', ('captured=' + (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture)))
  foreach ($k in $capSections) { $lines += ('{0}={1}' -f $k, (@($snap[$k].Items) -join ',')) }
  $tmp = "$baselineFile.tmp.$PID." + [guid]::NewGuid().ToString('N')
  try {
    Set-Content -LiteralPath $tmp -Encoding utf8 -Value ($lines -join "`r`n")
    Move-Item -LiteralPath $tmp -Destination $baselineFile -Force
  } finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
  }
}

function Invoke-BaselineCheck {
  param($snap)
  $badSections = @($capSections | Where-Object { $snap[$_].Status -eq 'FAILED' -or $snap[$_].Status -eq 'UNPARSEABLE' })
  $bl = Read-BaselineFile

  if ($UpdateBaseline) {
    if ($badSections.Count) {
      # 使用者明確要求 mutation 卻被拒 → exit 2（誠實命令契約：exit 0 會讓 automation 誤以為已接受）。
      # marker 行是權威訊號：smoke 失敗 passthrough 也可能 exit 2（clap 慣例），單看 exit code 有歧義。
      Write-Warning ("codex-check: 盤點含查詢失敗/解析失真段（{0}）→ 拒絕更新 baseline（查不到/解析不了 ≠ 能力消失，不能寫進 baseline）" -f ($badSections -join ', '))
      Write-Output "UPDATE_BASELINE=REFUSED"
      exit 2
    }
    if ($bl -and -not $bl.corrupt) {
      foreach ($k in $capSections) {
        if ($snap[$k].Status -eq 'EMPTY' -and $bl[$k] -ne '') {
          Write-Output ("  * 注意: {0} 段現為空、原 baseline 非空 -- 若非刻意移除，請先人工確認再信任新 baseline" -f $k)
        }
      }
    }
    # 延後寫入：等 smoke 通過才落檔。否則「先寫檔、smoke 才失敗 exit 2」會讓 automation 誤讀成
    # 「被拒、舊 baseline 還在」，實際上已被無聲替換且無備份可回（2026-07-16 對抗審查證實）。
    $script:baselinePending = $true
    Write-Output "codex-check: 盤點通過 -- baseline 將於 smoke 通過（或快取命中）後寫入"
    return
  }

  if ($null -eq $bl) {
    # 不自動建立（Codex 諮詢 2026-07-16 裁決）：自動建立會讓「刪檔重跑」成為第二條更新途徑；
    # baseline 的語義必須是「你接受過的能力面」，不是「上次看到的能力面」。
    Write-Warning "codex-check: NO_BASELINE -- 尚無能力面 baseline；檢視上方盤點後執行 codex-check.ps1 -UpdateBaseline 建立"
    return
  }
  if ($bl.corrupt) {
    Write-Warning "codex-check: baseline 檔格式不符 → 視為無 baseline（不自動覆寫）；請檢視後用 -UpdateBaseline 重建: $baselineFile"
    return
  }

  $driftLines = @(); $unknownLines = @()
  foreach ($k in $capSections) {
    $cur = $snap[$k]
    $old = @(); if ($bl[$k] -ne '') { $old = @($bl[$k] -split ',') }
    if ($cur.Status -eq 'FAILED') { $unknownLines += ("  {0}: 查詢失敗（查不到 ≠ 能力消失，不視為漂移）" -f $k); continue }
    if ($cur.Status -eq 'UNPARSEABLE') { $unknownLines += ("  {0}: 有輸出但解析失敗（UNPARSEABLE）-- 疑升級改了輸出格式，請人工確認；不視為漂移" -f $k); continue }
    if ($cur.Status -eq 'EMPTY' -and $old.Count -gt 0) {
      $unknownLines += ("  {0}: 盤點為空但 baseline 有 {1} 項 -- 可能升級改了輸出格式、也可能能力真的全移除，請人工確認" -f $k, $old.Count)
      continue
    }
    $new = @($cur.Items)
    $added   = @($new | Where-Object { $old -notcontains $_ })
    $removed = @($old | Where-Object { $new -notcontains $_ })
    if ($k -eq 'codex_version') {
      if ($added.Count -or $removed.Count) { $driftLines += ("  codex_version: {0} -> {1}" -f $bl[$k], ($new -join ',')) }
    } else {
      if ($added.Count)   { $driftLines += ("  {0} +: {1}" -f $k, ($added -join ', ')) }
      if ($removed.Count) { $driftLines += ("  {0} -: {1}" -f $k, ($removed -join ', ')) }
    }
  }
  if ($unknownLines.Count) {
    Write-Output "*** 能力面 UNKNOWN 段（無法與 baseline 比對）***"
    foreach ($ln in $unknownLines) { Write-Output $ln }
  }
  if ($driftLines.Count) {
    Write-Output ("*** 能力面漂移 vs baseline (captured {0}) ***" -f $bl['captured'])
    foreach ($ln in $driftLines) { Write-Output $ln }
    Write-Output "檢視上述變更；確認符合預期後執行 codex-check.ps1 -UpdateBaseline 接受為新 baseline。（提醒非閘門，不影響 exit code）"
  } elseif (-not $unknownLines.Count) {
    Write-Output ("能力面 vs baseline (captured {0})：無漂移" -f $bl['captured'])
  }
  Write-Output ""
}

# 能力面盤點＋baseline 比對無模型推理、成本低 → 放在 24h 快取檢查之前，每次呼叫都跑（貴的 smoke test 仍走快取）。
$capSnap = Get-CapabilitySnapshot
Show-CapabilitySurface $capSnap
Invoke-BaselineCheck $capSnap
# 依賴旗標相容性：全數命中才算確立。未確立（缺旗標/help 失真/抓取失敗）→ 本次 smoke 成功也不寫 24h 快取，
# 不讓快取把「可能不相容」蓋成綠燈——下次呼叫仍全檢、再警示一次。
$flagsCompatible = ($capSnap['exec_flags'].Status -eq 'OK' -and @($requiredFlags | Where-Object { $capSnap['exec_flags'].Items -notcontains $_ }).Count -eq 0)

# H4：命中需「恰一行 + 全行格式（format=2 前綴 + installed/latest/verdict 全欄位 + ISO-ish 時戳）+ 0<=age<86400s」；否則落回全檢。
if (-not $Force -and (Test-Path -LiteralPath $cache)) {
  $cacheLines = @(Get-Content -LiteralPath $cache)
  $fmtOk = ($cacheLines.Count -eq 1) -and ($cacheLines[0] -match '^format=2 installed=([^ ]*) latest=.+ verdict=.+ smoke=OK at [0-9]+-[0-9]+-[0-9]+T[0-9:]+[+-][0-9]+$')
  if ($fmtOk) {
    # 快取版本鍵：版本解析不到或與快取行 installed 不同（如 24h 內手動升級/降級）→ 當 miss 全檢，
    # 不回報過期結果。注意空字串==空字串也不許命中——身分未知不可拿快取背書（Codex 諮詢 2026-07-16）。
    if (-not $instVer) {
      Write-Output "codex-check: 當前版本解析不到 → 不採信快取、當 miss 全檢"
    } elseif ($Matches[1] -cne $instVer) {
      Write-Output ("codex-check: 快取版本 {0} 與當前 {1} 不符 → 當 miss 全檢（升級/降級後首跑）" -f $Matches[1], $instVer)
    } elseif (-not $flagsCompatible) {
      # 對稱守衛：寫入側不讓不相容結果進快取，命中側也不讓「本次盤點已示警」被舊綠快取蓋掉。
      Write-Output "codex-check: 依賴旗標相容性未確立 → 不採信快取、當 miss 全檢"
    } else {
      $ageSec = ((Get-Date) - (Get-Item -LiteralPath $cache).LastWriteTime).TotalSeconds
      if ($ageSec -ge 0 -and $ageSec -lt 86400) {
        if ($baselinePending) {
          # 快取命中＝近期 smoke OK，等同放行條件 → 落檔
          Write-BaselineFile $capSnap
          Write-Output "能力面 baseline 已更新: $baselineFile"
          Write-Output "UPDATE_BASELINE=OK"
        }
        Write-Output ("codex-check: {0}h 前查過，跳過（-f 強制重查）。上次結果：" -f [int][math]::Floor($ageSec / 3600))
        Get-Content -LiteralPath $cache
        exit 0
      }
    }
  }
}

# H1 版本抽取已前移至檔頭（能力面 snapshot 與快取版本鍵需要）——$instVer 於此已就緒。

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
    $verdict = "BEHIND ($instVer -> $latest) -- 中性情報非更新指令：更新屬選擇性系統變更、可能造成參數/外掛/行為漂移；要更新先問使用者（npm install -g @openai/codex@latest），更新後跑 -Force 重驗並檢視漂移"
  } elseif ($cmp -gt 0) {
    $verdict = "AHEAD ($instVer > $latest) -- 本機比 registry 新（prerelease/私建），非落後"
  } else {
    $verdict = "CURRENT ($instVer vs $latest) -- base 版本相同（多半 prerelease 尾綴差異）"
  }
}
Write-Output $verdict

Write-Output "=== read-only smoke test ==="
$tmpDir = $env:TEMP.TrimEnd('\')
# H2：能力探測（非版本閘門）——help 已於檔頭單次抓取，$useLastmsg 已就緒：
#     有 --output-last-message 才用精確 sentinel 路徑；沒有 → legacy marker 路徑。
# GUID 唯一檔名（絕不用固定名，防讀到上輪 stale sentinel）；跑前刪、finally 刪。
$lastMsgPath = Join-Path $tmpDir ("codex-check-lastmsg.$PID." + [guid]::NewGuid().ToString('N') + ".txt")
if (Test-Path -LiteralPath $lastMsgPath) { Remove-Item -LiteralPath $lastMsgPath -Force -ErrorAction SilentlyContinue }
$smokeExit = 1
$sawSentinel = $false
try {
  # v3 佈線：cmd /s /c + `< NUL`(空 stdin)，prompt 走引號好的 cmd 參數，避開 PS pipe 編碼坑。
  # stderr 合流（2>&1）必須做在 cmd 層、不可做在 PS 層：真 codex 會往 stderr 印噪音（實測
  # "Reading additional input from stdin..."），PS 5.1 在 EAP=Stop 下會把 native stderr 包成
  # NativeCommandError 直接 terminating、smoke 中途死掉（2026-07-13 Windows 原生 gate 抓到）。
  # cmd 層合流 = bash 版 `2>&1` 的逐字對應，transcript 語義相同。
  if ($useLastmsg) {
    $inner = '"{0}" exec --sandbox read-only --skip-git-repo-check -C "{1}" --output-last-message "{2}" "Reply with exactly: CODEX_OK" < NUL 2>&1' -f $codexCmd, $tmpDir, $lastMsgPath
  } else {
    $inner = '"{0}" exec --sandbox read-only --skip-git-repo-check -C "{1}" "Reply with exactly: CODEX_OK" < NUL 2>&1' -f $codexCmd, $tmpDir
  }
  # C2：捕捉輸出並回顯。光看 exit code 會把「壞掉但 exit 0」的 codex 誤判成可用，故要驗真回了 CODEX_OK。
  $smokeOut = & cmd.exe /d /s /c $inner
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

if ($smokeExit -eq 0 -and $sawSentinel -and -not $flagsCompatible) {
  # smoke 過但依賴旗標相容性未確立 → 不寫快取（exit 仍以 smoke 為準；快取只是optimization，不能背書相容性）
  Write-Output "codex-check: smoke OK 但依賴旗標相容性未確立 → 不寫 24h 快取（下次呼叫仍全檢）"
  $smoke = 0
} elseif ($smokeExit -eq 0 -and $sawSentinel) {
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
if ($baselinePending) {
  if ($smokeExit -eq 0 -and $sawSentinel) {
    Write-BaselineFile $capSnap
    Write-Output "能力面 baseline 已更新: $baselineFile"
    Write-Output "UPDATE_BASELINE=OK"
  } else {
    Write-Output "UPDATE_BASELINE=NOT_APPLIED（smoke 失敗，baseline 未動）"
  }
}
exit $smoke
