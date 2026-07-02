<#
.SYNOPSIS
  超級模式 §3 派工：把任務簡報交給 Codex 執行（workspace-write 沙箱）。
  交回後 Claude 必須 review diff，不合格退回重做。
.PARAMETER Dir
  Codex 的工作目錄（專案根，Windows 路徑）。Codex 沙箱進不到 WSL UNC 路徑。
.PARAMETER Prompt
  任務簡報文字（短簡報限定；含 ; | & 標點的 inline 簡報可能被 consult-gate 誤判）。
.PARAMETER PromptFile
  從檔案讀任務簡報。**建議一律用這個** — 簡報寫進 scratchpad（gate 豁免路徑）再傳入。
.PARAMETER OutFile
  Codex 最終回覆落地路徑（--output-last-message）。不給就自動放 ~/.claude/super-mode-logs/。
.EXAMPLE
  .\codex-exec.ps1 -Dir C:\proj -PromptFile <scratchpad>\task.txt
.NOTES
  派工一律用 run_in_background:true 跑本腳本（重任務常超過工具 10 分鐘上限）。
  全程輸出自動存 ~/.claude/super-mode-logs/codex_exec_<ts>.txt。
  STDIN 佈線(v3)：簡報正規化成 UTF-8(無 BOM)暫存檔，用 cmd /s /c 的 `<` 重導向
  位元組直達 codex。不要用 PowerShell pipe — PS 5.1 在 script 內設 $OutputEncoding
  對 native pipe 不生效(作用域坑)，中文會全變 '?'；positional 傳 prompt 會被
  codex.ps1 shim word-split。
#>
param(
  [Parameter(Mandatory = $true)][string]$Dir,
  [string]$Prompt,
  [string]$PromptFile,
  [string]$OutFile
)
$codexCmd = "C:\npm\codex.cmd"

# codex 輸出是 UTF-8：讓 PowerShell 正確解碼進 transcript
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

function Read-TextSmart([string]$path) {
  # BOM 嗅探：UTF-16LE / UTF-8 BOM / 其餘一律當 UTF-8(Claude Write 工具與 bash 的產物)
  $b = [System.IO.File]::ReadAllBytes($path)
  if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2) }
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) }
  return [System.Text.Encoding]::UTF8.GetString($b)
}

if ($PromptFile) { $p = Read-TextSmart $PromptFile }
elseif ($Prompt) { $p = $Prompt }
else { throw "需提供 -Prompt 或 -PromptFile" }
if ([string]::IsNullOrWhiteSpace($p)) { throw "Prompt is empty." }

$logDir = Join-Path $env:USERPROFILE ".claude\super-mode-logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$log = Join-Path $logDir ("codex_exec_{0}.txt" -f $stamp)
if (-not $OutFile) { $OutFile = Join-Path $logDir ("codex_exec_{0}_last.txt" -f $stamp) }

$Dir = $Dir.TrimEnd('\')
if ($Dir -match '^[A-Za-z]:$') { $Dir += '\' }

# 正規化落地 UTF-8(無 BOM)暫存簡報，cmd `<` 重導向 → 位元組直達 codex
$brief = Join-Path $env:TEMP ("codex_brief_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
$errFile = Join-Path $env:TEMP ("codex_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
[System.IO.File]::WriteAllText($brief, $p, (New-Object System.Text.UTF8Encoding $false))
try {
  # stderr 導到獨立檔(編號佔位符 {4})；不可用 2>&1(會回灌 stdout)。$LASTEXITCODE 仍是 codex 退出碼。
  $inner = '"{0}" exec --sandbox workspace-write --skip-git-repo-check -C "{1}" --output-last-message "{2}" < "{3}" 2> "{4}"' -f $codexCmd, $Dir, $OutFile, $brief, $errFile
  & cmd.exe /d /s /c $inner | ForEach-Object { $_; Add-Content -LiteralPath $log -Value $_ -Encoding utf8 }
  $code = $LASTEXITCODE
  if (Test-Path $errFile) {
    Add-Content -LiteralPath $log -Value "===== STDERR =====" -Encoding utf8
    [System.IO.File]::ReadAllText($errFile, (New-Object System.Text.UTF8Encoding $false)) | Add-Content -LiteralPath $log -Encoding utf8
  }
}
finally {
  Remove-Item -LiteralPath $brief -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
}

if ($code -eq 0) {
  Write-Output "exec OK -- transcript: $log ; last message: $OutFile"
} else {
  Write-Warning "codex-exec: codex exited [$code]. transcript: $log"
}
exit $code
