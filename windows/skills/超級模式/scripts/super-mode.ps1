<#
.SYNOPSIS
  超級模式開關旗標（給 consult-gate hook 用）。
    -On [-Scope <dir>]  啟用。-Scope 限定只在該專案路徑內強制（Windows 專案建議都帶，
                        避免擋到其他 session）；WSL/UNC 專案省略 -Scope 用全域強制。
                        -Scope 必須是存在的磁碟機目錄，其他值一律拒收、不啟用。
    -Off                退出：清掉旗標與諮詢憑證，順手清舊逐字稿（範圍見 .NOTES）。收尾時**必跑**。
    -Cleanup [-DryRun]  只清舊逐字稿（範圍與 -Off 相同），**不碰旗標與憑證**，不影響其他 session。
                        -DryRun 只印符合條件的檔數與位元組數、不刪。日常只用討論模式
                        （codex-consult.ps1 -NoCredential）、從不開關超級模式時，靠它執行保留期限。
    (無參數)            查目前狀態。
    其他組合（-On／-Off／-Cleanup 同傳、-Scope 沒搭配 -On、-DryRun 沒搭配 -Cleanup、多餘引數）
    一律 exit 2，而且不動旗標、憑證與逐字稿。（PowerShell 在參數綁定階段就拒絕的寫法——例如
    同一個開關給兩次——輪不到本腳本檢查，退出碼由 PowerShell 決定，不是 2；同樣不動任何狀態。）
.NOTES
  旗標：~/.claude/.super-mode-active（第一行 = Scope 路徑或空；mtime = 啟用時間）。
  憑證：~/.claude/.super-mode-consult-ok（由 codex-consult.ps1 寫）。
  防殘留：hook 會把超過 8 小時的旗標視為 stale 自動解除；但正常收尾仍請跑 -Off。
  逐字稿清理（-Off）：只刪 ~/.claude/super-mode-logs **頂層**、檔名符合 codex-consult／codex-exec
  產生格式、且 LastWriteTime 超過 14 天的檔；不進子目錄、不碰其他檔名。刪除／列舉失敗逐項寫
  stderr（前綴 OFF_CLEANUP_ERROR），但 -Off 照常完成（旗標與憑證已先清掉、仍印 OFF、exit 0）。
  逐字稿清理（-Cleanup，2026-11-18）：同一組條件；刪除／列舉失敗的前綴是 CLEANUP_ERROR，而且 exit 1。
  stdout 一行摘要：`transcript cleanup: deleted=<n> bytes=<b> failed=<n>`，-DryRun 時是
  `transcript cleanup (dry-run): matched=<n> bytes=<b> ...`。
#>
param([switch]$On, [switch]$Off, [switch]$Cleanup, [switch]$DryRun, [string]$Scope)
$claude = Join-Path $env:USERPROFILE ".claude"
$flag   = Join-Path $claude ".super-mode-active"
$token  = Join-Path $claude ".super-mode-consult-ok"

# 參數錯誤：一律在改動任何狀態之前拒絕（2026-11-18；macOS super-mode.sh 同一組檢查的平台翻譯）。
# ⚠️ 旗標與憑證是全機單一檔，打錯的指令若照做會波及其他 session：`-On -Off` 同傳曾經走 -On
#    （沒帶 -Scope 還會變成全域強制）、`-Off -Scope <dir>` 曾經忽略 -Scope 照常關掉全機模式。
# 本腳本沒有 [CmdletBinding()]：綁不上的多餘引數落在 $args；單一多餘引數會依位置綁到 -Scope，
# 沒帶 -On 時由第三條攔下，帶了 -On 就走下面 -Scope 的既有驗證。
# ⚠️ 用 [Console]::Error 不用 Write-Error：呼叫端的 preference 若是 Stop，Write-Error 會變終止性例外，退出碼就不是 2。
$usageError = $null
if ($args.Count -gt 0) { $usageError = '不認得的參數: ' + ($args -join ' ') }
elseif ($On -and $Off) { $usageError = '-On 與 -Off 不能同時給' }
elseif ($Cleanup -and ($On -or $Off)) { $usageError = '-Cleanup 不能與 -On／-Off 同時給（-Cleanup 只清逐字稿，不動旗標與憑證）' }
elseif ($PSBoundParameters.ContainsKey('DryRun') -and -not $Cleanup) {
  # 看「有沒有帶 -DryRun」，不看值（同下面的 -Scope）：`-Off -DryRun:$false` 不得照做 -Off。
  $usageError = '-DryRun 只能搭配 -Cleanup'
}
elseif ($PSBoundParameters.ContainsKey('Scope') -and -not $On) {
  $usageError = '-Scope 只能搭配 -On（-Off 一律清掉全機的旗標與憑證，沒有 scope；查狀態不帶參數）'
}
if ($usageError) {
  [Console]::Error.WriteLine('super-mode.ps1: ' + $usageError)
  [Console]::Error.WriteLine('usage: super-mode.ps1 [-On [-Scope <dir>]] | [-Off] | [-Cleanup [-DryRun]] | (no args = status)')
  exit 2
}

if ($On) {
  $content = ""
  # 看「有沒有帶 -Scope」，不看值：呼叫端的變數是空的時，不能靜默變成全域強制。
  if ($PSBoundParameters.ContainsKey('Scope')) {
    if ([string]::IsNullOrWhiteSpace($Scope) -or -not (Test-Path -LiteralPath $Scope -PathType Container)) {
      Write-Error "Scope 必須是存在的目錄: '$Scope'（未啟用，避免誤靜默降級為全域強制，或把 repo 內的動作變成 scope 外）"; exit 1
    }
    $rp = Resolve-Path -LiteralPath $Scope -ErrorAction SilentlyContinue
    if (-not $rp) { Write-Error "Scope 路徑不存在: $Scope（未啟用，避免誤靜默降級為全域強制）"; exit 1 }
    # hook 的 readScope 看不懂的值，寫進旗標會被靜默當成全域，所以這裡要比它嚴：
    #   - UNC 的 .Path 帶 provider 前綴；registry 與 session 專屬的 PSDrive 不是 OS 看得到的磁碟機（hook 在 node 裡解析不了）。
    #   - 段尾的點或空白：Win32 會去掉所以 Test-Path 成立，hook 卻判可疑（isDangerousPath）。
    # ⚠️ UNC 不要靠改 .ProviderPath 打開：別名路徑與憑證的比對會對不上，也沒在真 WSL 驗過（2026-10-31 反方審查）。
    if (($rp.Provider.Name -ne 'FileSystem') -or ($rp.Path -notmatch '^[A-Za-z]:[\\/]') -or
        (-not [System.IO.Directory]::Exists($rp.Path)) -or ($rp.Path -match '[ .]([\\/]|$)')) {
      Write-Error "Scope 只支援磁碟機路徑: $($rp.Path)（未啟用）。UNC／WSL 專案請省略 -Scope，改用全域強制。"; exit 1
    }
    $content = $rp.Path
  }
  Set-Content -LiteralPath $flag -Value $content -Encoding utf8
  if ($content) { Write-Output "super mode: ON  (scope=$content)" }
  else          { Write-Output "super mode: ON  (scope=GLOBAL — 會影響同機所有並行 session；有 Windows 路徑根就建議帶 -Scope)" }
}
elseif ($Off -or $Cleanup) {
  # -Off 與 -Cleanup 共用下面的逐字稿清理；只有 -Off 會動旗標與憑證。
  if ($Off) {
    if (Test-Path $flag)  { Remove-Item -LiteralPath $flag  -Force }
    if (Test-Path $token) { Remove-Item -LiteralPath $token -Force }
  }
  # stderr 前綴照模式分開：-Off 的清理失敗不影響結果（照常 OFF、exit 0），-Cleanup 的失敗會 exit 1。
  $errTag = if ($Off) { 'OFF_CLEANUP_ERROR' } else { 'CLEANUP_ERROR' }
  $matched = 0
  $deleted = 0
  $deleteFailed = 0
  [long]$bytes = 0
  $cleanupErrors = 0
  # 清理超過 14 天的舊逐字稿（日誌保留政策）。backlog：OFF-CLEANUP-RECURSIVE。
  # ⚠️ 範圍刻意收窄：只看 super-mode-logs **頂層**（Get-ChildItem 不帶 -Recurse），且檔名必須
  #    符合下面的白名單。子目錄（驗收證據常放那裡）與其他檔名一律不碰。
  # 白名單＝codex-consult／codex-exec 實際產生的檔名（macOS 版用同一條）：
  #   codex_consult_<yyyyMMdd>_<HHmmss>_<後綴>.txt
  #   codex_exec_<yyyyMMdd>_<HHmmss>_<後綴>.txt、codex_exec_<yyyyMMdd>_<HHmmss>_<後綴>_last.txt
  #   後綴＝恰好 6 位小寫 hex（GUID／uuidgen／od）；只有 macOS consult 在 uuidgen 與 od 都不可用時
  #   退回 PID（純數字，長度不定），exec 沒有這個 fallback。2026-07-02 初版（1827df3）沒有後綴，
  #   所以後綴是選配。-cmatch＝區分大小寫。
  #   2026-10-15 收緊（使用者裁決）：後綴原本接受任意長度 hex，現在只認上述產生格式，
  #   `codex_exec_<時間戳>_cafe.txt` 這類短／長後綴的檔不再刪。
  # ⚠️ 錯誤一律逐項寫 stderr、不得靜默；也不用 Write-Warning／Write-Error —— 呼叫端的
  #    preference 若是 Stop，兩者都會變終止性例外，讓 -Off 在印出 OFF 之前中止。
  $logDir = Join-Path $claude "super-mode-logs"
  if (Test-Path -LiteralPath $logDir -PathType Container) {
    $transcriptRe = '^codex_(consult_[0-9]{8}_[0-9]{6}(_([0-9a-f]{6}|[0-9]+))?|exec_[0-9]{8}_[0-9]{6}(_[0-9a-f]{6})?(_last)?)\.txt$'
    $cutoff = (Get-Date).AddDays(-14)
    $candidates = @()
    $listErr = $null
    try {
      # 列舉錯誤收進 -ErrorVariable 逐項回報，列得到的照樣清（不因單一錯誤放棄整批）。
      $candidates = @(Get-ChildItem -LiteralPath $logDir -File -ErrorAction SilentlyContinue -ErrorVariable listErr |
        Where-Object { ($_.Name -cmatch $transcriptRe) -and ($_.LastWriteTime -lt $cutoff) })
    }
    catch {
      $cleanupErrors++
      [Console]::Error.WriteLine("${errTag}: 無法列舉 $logDir -- $($_.Exception.Message)")
    }
    foreach ($le in @($listErr)) {
      if ($null -eq $le) { continue }
      $cleanupErrors++
      [Console]::Error.WriteLine("${errTag}: 列舉 $logDir 時出錯 -- $($le.Exception.Message)")
    }
    $matched = $candidates.Count
    foreach ($old in $candidates) {
      # 大小只供回報：取不到就算 0，不當成清理失敗。
      [long]$size = 0
      try { $size = [long]$old.Length } catch { $size = 0 }
      if ($DryRun) { $bytes += $size; continue }
      try {
        Remove-Item -LiteralPath $old.FullName -Force -ErrorAction Stop
        $deleted++
        $bytes += $size
      }
      catch {
        $cleanupErrors++
        $deleteFailed++
        [Console]::Error.WriteLine("${errTag}: 無法刪除 $($old.FullName) -- $($_.Exception.Message)")
      }
    }
    if ($Off -and $cleanupErrors -gt 0) {
      [Console]::Error.WriteLine("OFF_CLEANUP_ERROR: 逐字稿清理有 $cleanupErrors 個錯誤、未完整；旗標與憑證已清除，super mode 仍為 OFF。")
    }
  }
  if ($Off) {
    Write-Output "super mode: OFF"
  }
  else {
    if ($DryRun) {
      Write-Output "transcript cleanup (dry-run): matched=$matched bytes=$bytes -- 未刪除任何檔（範圍：$logDir 頂層、檔名符合逐字稿格式、超過 14 天）"
    }
    else {
      Write-Output "transcript cleanup: deleted=$deleted bytes=$bytes failed=$deleteFailed"
    }
    if ($cleanupErrors -gt 0) {
      # 與 -Off 不同：部分失敗要讓呼叫端看得到，回非零。
      if ($DryRun) {
        [Console]::Error.WriteLine("CLEANUP_ERROR: 列舉未完整，上面的檔數與位元組數不可信；沒有刪除任何檔，旗標與憑證未變動。")
      }
      else {
        [Console]::Error.WriteLine("CLEANUP_ERROR: 逐字稿清理有 $cleanupErrors 個錯誤、未完整；旗標與憑證未變動。")
      }
      exit 1
    }
    # 成功也要明確 exit 0：-Cleanup 用退出碼表示結果，而同一個行程裡用 & 呼叫時，
    # 沒有 exit 的腳本會讓呼叫端讀到上一個指令留下的 $LASTEXITCODE（例如前一次清理失敗的 1）。
    exit 0
  }
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
