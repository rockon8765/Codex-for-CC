# codex-consult.ps1 -- super-mode section 3.5 advice gate (v3).
# Runs a read-only Codex second opinion. Codex writes nothing; it only reviews
# the evidence/plan you pass in. On success, writes a consult credential so the
# super-mode consult-gate allows change actions for ~20 minutes, and saves the
# full transcript to ~/.claude/super-mode-logs/codex_consult_<ts>.txt.
#
# Params:
#   -Dir         Codex working dir (project root, Windows path; WSL UNC not reachable -> feed evidence via the brief).
#   -Prompt      Consult brief text (short only; punctuation like ; | & in inline
#                prompts can trip the consult-gate's command parsing).
#   -PromptFile  Read the consult brief from a file. PREFERRED -- write the brief
#                to the session scratchpad (gate-exempt path) and pass it here.
# Note: set the calling tool timeout to 360000ms (6 min); Codex reasoning often exceeds the 2-min default.
#
# STDIN wiring (v3): the brief is normalized to a UTF-8(no BOM) temp file and fed to
# codex via `cmd /s /c "... < file"` so the bytes reach codex untouched. Do NOT pipe
# the prompt through PowerShell 5.1 -- in-script $OutputEncoding is not honored for
# native pipes (scope quirk) and non-ASCII turns into '?'; positional args get
# word-split in the codex.ps1 shim handoff.
param(
  [Parameter(Mandatory = $true)][string]$Dir,
  [string]$Prompt,
  [string]$PromptFile
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

if ($PromptFile)   { $p = Read-TextSmart $PromptFile }
elseif ($Prompt)   { $p = $Prompt }
else               { throw "Provide -Prompt or -PromptFile" }
if ([string]::IsNullOrWhiteSpace($p)) { throw "Prompt is empty." }

$logDir = Join-Path $env:USERPROFILE ".claude\super-mode-logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$log = Join-Path $logDir ("codex_consult_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

$Dir = $Dir.TrimEnd('\')
if ($Dir -match '^[A-Za-z]:$') { $Dir += '\' }

# 正規化落地 UTF-8(無 BOM)暫存簡報，cmd `<` 重導向 → 位元組直達 codex
$brief = Join-Path $env:TEMP ("codex_brief_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
$errFile = Join-Path $env:TEMP ("codex_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
[System.IO.File]::WriteAllText($brief, $p, (New-Object System.Text.UTF8Encoding $false))
try {
  # stderr 導到獨立檔(編號佔位符 {3})；不可用 2>&1(會回灌 stdout)。$LASTEXITCODE 仍是 codex 退出碼。
  $inner = '"{0}" exec --sandbox read-only --skip-git-repo-check -C "{1}" < "{2}" 2> "{3}"' -f $codexCmd, $Dir, $brief, $errFile
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
  $token = Join-Path $env:USERPROFILE ".claude\.super-mode-consult-ok"
  Set-Content -LiteralPath $token -Value (Get-Date -Format o) -Encoding utf8
  Write-Output "consult OK -- credential written; transcript: $log"
} else {
  Write-Warning "codex-consult: codex exited [$code] -- no credential written. transcript: $log"
}
exit $code
