<#
.SYNOPSIS
  超級模式開關旗標（給 consult-gate hook 用）。
    -On [-Scope <dir>]  啟用。-Scope 限定只在該專案路徑內強制（Windows 專案建議都帶，
                        避免擋到其他 session）；WSL/UNC 專案省略 -Scope 用全域強制。
    -Off                退出：清掉旗標與諮詢憑證，順手清舊逐字稿（範圍見 .NOTES）。收尾時**必跑**。
    (無參數)            查目前狀態。
.NOTES
  旗標：~/.claude/.super-mode-active（第一行 = Scope 路徑或空；mtime = 啟用時間）。
  憑證：~/.claude/.super-mode-consult-ok（由 codex-consult.ps1 寫）。
  防殘留：hook 會把超過 8 小時的旗標視為 stale 自動解除；但正常收尾仍請跑 -Off。
  逐字稿清理（-Off）：只刪 ~/.claude/super-mode-logs **頂層**、檔名符合 codex-consult／codex-exec
  產生格式、且 LastWriteTime 超過 14 天的檔；不進子目錄、不碰其他檔名。刪除／列舉失敗逐項寫
  stderr（前綴 OFF_CLEANUP_ERROR），但 -Off 照常完成（旗標與憑證已先清掉、仍印 OFF、exit 0）。
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
  # 順手清理超過 14 天的舊逐字稿（日誌保留政策）。backlog：OFF-CLEANUP-RECURSIVE。
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
    $cleanupErrors = 0
    $candidates = @()
    $listErr = $null
    try {
      # 列舉錯誤收進 -ErrorVariable 逐項回報，列得到的照樣清（不因單一錯誤放棄整批）。
      $candidates = @(Get-ChildItem -LiteralPath $logDir -File -ErrorAction SilentlyContinue -ErrorVariable listErr |
        Where-Object { ($_.Name -cmatch $transcriptRe) -and ($_.LastWriteTime -lt $cutoff) })
    }
    catch {
      $cleanupErrors++
      [Console]::Error.WriteLine("OFF_CLEANUP_ERROR: 無法列舉 $logDir -- $($_.Exception.Message)")
    }
    foreach ($le in @($listErr)) {
      if ($null -eq $le) { continue }
      $cleanupErrors++
      [Console]::Error.WriteLine("OFF_CLEANUP_ERROR: 列舉 $logDir 時出錯 -- $($le.Exception.Message)")
    }
    foreach ($old in $candidates) {
      try { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction Stop }
      catch {
        $cleanupErrors++
        [Console]::Error.WriteLine("OFF_CLEANUP_ERROR: 無法刪除 $($old.FullName) -- $($_.Exception.Message)")
      }
    }
    if ($cleanupErrors -gt 0) {
      [Console]::Error.WriteLine("OFF_CLEANUP_ERROR: 逐字稿清理有 $cleanupErrors 個錯誤、未完整；旗標與憑證已清除，super mode 仍為 OFF。")
    }
  }
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
