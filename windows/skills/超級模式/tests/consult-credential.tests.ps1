# consult-credential.tests.ps1 -- codex-consult.ps1 的憑證鑄造整合測試（假 codex）。
#
# 為什麼需要這支：consult-answer.test.js 測的是**判準本體**（純函式）。
# 這支測的是 **caller 的接線**——那是 2026-08-18 這批真正新增的風險面：
#   codex 的 stdout 有沒有正確餵給判準（而不是把 stderr 或 log 一起餵進去）、
#   43 有沒有真的不鑄造、哨兵檢查會不會被「exit 0 的空模組」騙過、
#   憑證寫入是不是原子的、失敗時舊憑證有沒有被動到。
#
# 做法：用 SUPER_MODE_CODEX_CMD 換掉 codex 本體，用 USERPROFILE 換掉家目錄，
#       所以完全不碰真的 codex、不碰真的 ~/.claude。
#
# ⚠️ 每個案例都釘**具名斷言**與**精確退出碼**，不比總數。

#
# 受測 host 用 -Shell 切換：codex-consult.ps1 必須在 pwsh 7.x 與 Windows PowerShell 5.1
# 兩邊都成立（使用者的 PowerShell 工具用哪一支不由我們決定）。
param([ValidateSet('pwsh', 'powershell')][string]$Shell = 'pwsh')

$ErrorActionPreference = 'Stop'
$script:pass = 0
$script:fail = 0
$script:failed = @()

function Check([string]$name, [bool]$cond, [string]$detail) {
  if ($cond) { $script:pass++; return }
  $script:fail++
  $script:failed += $name
  Write-Output ("  FAIL  " + $name + $(if ($detail) { "`n        " + $detail } else { "" }))
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script = Join-Path $here "..\scripts\codex-consult.ps1"
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("consult-cred-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$fakeHome = Join-Path $root "home"
New-Item -ItemType Directory -Path (Join-Path $fakeHome ".claude") -Force | Out-Null
$repo = Join-Path $root "repo"
New-Item -ItemType Directory -Path $repo -Force | Out-Null
$brief = Join-Path $root "brief.md"
Set-Content -LiteralPath $brief -Value "測試用簡報" -Encoding utf8
$token = Join-Path $fakeHome ".claude\.super-mode-consult-ok"

# 假 codex：把 STDOUT_FILE 的內容原樣吐到 stdout，退出碼取 EXIT_CODE。
$fakeCodex = Join-Path $root "fake-codex.cmd"
@'
@echo off
type "%STDOUT_FILE%"
exit /b %EXIT_CODE%
'@ | Set-Content -LiteralPath $fakeCodex -Encoding ascii

function Run-Consult([string]$answer, [int]$exitCode, [string[]]$extra) {
  $ansFile = Join-Path $root ("ans-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + ".txt")
  [System.IO.File]::WriteAllText($ansFile, $answer, (New-Object System.Text.UTF8Encoding $false))
  $outF = Join-Path $root "o.txt"; $errF = Join-Path $root "e.txt"
  $argv = @("-NoProfile", "-File", $script, "-Dir", $repo, "-PromptFile", $brief) + $extra
  $env:SUPER_MODE_CODEX_CMD = $fakeCodex
  $env:STDOUT_FILE = $ansFile
  $env:EXIT_CODE = "$exitCode"
  $oldHome = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  try {
    $pr = Start-Process -FilePath $Shell -ArgumentList $argv -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput $outF -RedirectStandardError $errF
    return @{
      Code = $pr.ExitCode
      Out  = (Get-Content -LiteralPath $outF -Raw -ErrorAction SilentlyContinue)
      Err  = (Get-Content -LiteralPath $errF -Raw -ErrorAction SilentlyContinue)
    }
  } finally { $env:USERPROFILE = $oldHome }
}

$long = "x" * 60

try {
  Write-Output "§1 合格回覆 → 鑄造"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult ("ALLOW: 可以做`n" + $long) 0 @()
  Check "1a ALLOW 合格 → exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "1b ALLOW 合格 → 憑證存在" (Test-Path -LiteralPath $token) "憑證沒寫出來"
  Check "1c 憑證內容綁 repo" ((Get-Content -LiteralPath $token -Raw) -match [regex]::Escape($repo.Replace('\', '\\'))) `
    ("內容=" + (Get-Content -LiteralPath $token -Raw))

  Write-Output "`n§2 BLOCK 仍鑄造（憑證是收據不是授權），但訊息要講"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult ("BLOCK: 不要做`n" + $long) 0 @()
  Check "2a BLOCK → exit 0" ($r.Code -eq 0) ("exit=" + $r.Code)
  Check "2b BLOCK → 憑證仍存在" (Test-Path -LiteralPath $token) "BLOCK 應該仍鑄造"
  Check "2c BLOCK → stdout 明說裁決為 BLOCK" ($r.Out -match 'BLOCK') ("out=" + $r.Out)

  Write-Output "`n§3 不合格回覆 → 43 且不鑄造，且**不動既有憑證**"
  # 先放一個既有憑證，內容與 mtime 都記下來
  Set-Content -LiteralPath $token -Value '{"repo":"OLD","ts":"old"}' -Encoding utf8
  $beforeBytes = [System.IO.File]::ReadAllBytes($token)
  $beforeTime = (Get-Item -LiteralPath $token).LastWriteTimeUtc
  Start-Sleep -Milliseconds 1100   # 讓 mtime 有機會不同，否則「沒變」證明不了什麼
  $r = Run-Consult "hi" 0 @()
  Check "3a 過短 → exit 43" ($r.Code -eq 43) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "3b 過短 → stderr 有 UNUSABLE" ($r.Err -match 'CONSULT_UNUSABLE_ANSWER') ("err=" + $r.Err)
  Check "3c 既有憑證 bytes 未變" `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$beforeBytes, [byte[]][System.IO.File]::ReadAllBytes($token))) "憑證內容被動過"
  Check "3d 既有憑證 mtime 未變" `
    ((Get-Item -LiteralPath $token).LastWriteTimeUtc -eq $beforeTime) "憑證 mtime 被動過（gate 只看 mtime，這等於偷偷續期）"

  Write-Output "`n§4 空回覆 / 無裁決"
  $r = Run-Consult "" 0 @()
  Check "4a 空回覆 → 43" ($r.Code -eq 43) ("exit=" + $r.Code)
  $r = Run-Consult ("這是一段夠長但沒有裁決首行的散文" + $long) 0 @()
  Check "4b 無裁決首行 → 43 且 NO_VERDICT" (($r.Code -eq 43) -and ($r.Err -match 'CONSULT_NO_VERDICT')) `
    ("exit=" + $r.Code + " err=" + $r.Err)

  Write-Output "`n§5 討論模式：短回覆放行、但不鑄造"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult "短" 0 @("-NoCredential")
  Check "5a 討論模式短回覆 → exit 0" ($r.Code -eq 0) ("exit=" + $r.Code + " err=" + $r.Err)
  Check "5b 討論模式不鑄造" (-not (Test-Path -LiteralPath $token)) "討論模式竟然寫了憑證"
  $r = Run-Consult "" 0 @("-NoCredential")
  Check "5c 討論模式空回覆仍 43" ($r.Code -eq 43) ("exit=" + $r.Code)

  Write-Output "`n§6 codex 自己失敗時，判準不該被叫、也不該鑄造"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $r = Run-Consult ("ALLOW: 可以`n" + $long) 7 @()
  Check "6a codex exit 7 → 沿用退出碼" ($r.Code -eq 7) ("exit=" + $r.Code)
  Check "6b codex 失敗 → 不鑄造" (-not (Test-Path -LiteralPath $token)) "codex 失敗卻鑄了憑證"

  Write-Output "`n§7 判準不可用 → 45（fail-closed，且不鑄造）"
  Remove-Item -LiteralPath $token -Force -ErrorAction SilentlyContinue
  $oldNode = $env:SUPER_MODE_NODE
  $env:SUPER_MODE_NODE = Join-Path $root "no-such-node.exe"
  try {
    $r = Run-Consult ("ALLOW: 可以`n" + $long) 0 @()
    Check "7a SUPER_MODE_NODE 無效 → 非 0（不靜默退回 PATH）" ($r.Code -ne 0) ("exit=" + $r.Code)
    Check "7b 不鑄造" (-not (Test-Path -LiteralPath $token)) "判準不可用卻鑄了憑證"
  } finally { $env:SUPER_MODE_NODE = $oldNode }
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item Env:SUPER_MODE_CODEX_CMD -ErrorAction SilentlyContinue
  Remove-Item Env:STDOUT_FILE -ErrorAction SilentlyContinue
  Remove-Item Env:EXIT_CODE -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output ("CONSULT-CREDENTIAL " + $script:pass + "/" + ($script:pass + $script:fail))
if ($script:fail -gt 0) {
  Write-Output ("失敗清單：" + ($script:failed -join "、"))
  foreach ($n in $script:failed) { Write-Output ("FAILED-CASE: " + $n) }
  exit 1
}
exit 0
