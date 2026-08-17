# `run-windows.ps1` 的 mutation control runner —— 證明測試臺**有牙齒**。
#
# 為什麼要有這支：`run-windows.ps1` 全綠只證明「沒少跑案」，不證明案子做了它宣稱的動作。
# 2026-08-14 實測過，刪掉某案的 stimulus、保留 assertion，變數沿用上一次的成功結果 →
# **案數不變、全綠、exit 0，mutant 存活**。所以驗收一律要跑本檔。
#
# ⚠️ **本檔存在的直接理由**：2026-08-15 的驗收只記了 control 的**數字**，沒記產生 mutant 的
# **精確方式**。結果 control 2 的 `123/3` 與後來重跑的 `122/4` 對不起來，而且**無法判定誰對**——
# 因為「搬到首掃之前」有「緊貼 anchor」與「更早但仍在首掃前」兩種放法，兩者預期紅的條數不同，
# 而 08-15 的 mutant 產物沒有保存。（2026-08-17 合併前 Codex 審查指出。）
# 本檔把放法釘死成**緊貼 anchor**，任何人重跑都會得到同一組數字。
#
# 用法（在 repo 根目錄）：
#   pwsh -NoProfile -File tests\ai-install\run-mutation-controls.ps1
#   pwsh -NoProfile -File tests\ai-install\run-mutation-controls.ps1 -Shell powershell
#
# 每個 control 都先做**注入自我檢查**，任何一條不成立就中止且不產出檔案：
# 錨點命中數必須恰為 1、兩行必須相鄰、行數變化必須符合預期、產出的 hash 必須真的改變。
# 沒有這些，「mutant 殺很多」與「測試臺根本沒跑起來」在輸出上長得一模一樣。
param([string]$Shell = 'pwsh', [string]$OutDir = '')

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$SUT  = Join-Path $repo 'tests\ai-install\run-windows.ps1'
$DOC  = Join-Path $repo 'docs\AI-INSTALL.md'
$out  = if ($OutDir) { $OutDir } else { Join-Path $env:TEMP ('m13c-controls-' + [guid]::NewGuid().ToString('N')) }
New-Item -ItemType Directory -Force -Path $out | Out-Null
"輸出目錄：$out"
"受測 SUT：$SUT  (blob $(git -C $repo hash-object $SUT))"
"受測文件：$DOC  (blob $(git -C $repo hash-object $DOC))"

$sutText = [IO.File]::ReadAllText($SUT)
$failures = 0

function Assert-One($text, $needle, $label) {
  $n = ([regex]::Matches($text, [regex]::Escape($needle))).Count
  if ($n -ne 1) { throw "SELFCHECK[$label] 錨點命中 $n 次（預期 1）—— 注入會打到不該打的地方" }
}

# ⚠️ 變異後的 SUT **必須放回 tests\ai-install\**：harness 用 `$PSScriptRoot\..\..` 定位 repo，
# 放到別處會解析到不相干目錄、1c 抄不到 payload，於是滿螢幕「1c 安裝成功」變紅 ——
# 看起來像 mutant 殺很大，其實是測試臺沒跑起來。（2026-08-17 實際踩過，得到 108/18 這種假數字。）
function New-MutantSut($label, $text) {
  $p = Join-Path (Split-Path $SUT -Parent) "run-windows.mutant-$label.ps1"
  [IO.File]::WriteAllText($p, $text, (New-Object Text.UTF8Encoding $true))
  if ((Get-FileHash -LiteralPath $p).Hash -eq (Get-FileHash -LiteralPath $SUT).Hash) {
    Remove-Item -LiteralPath $p -Force; throw "SELFCHECK[$label] 產出與原檔 hash 相同＝實際沒注入"
  }
  $p
}

# 把 hook／settings 還原的相鄰兩行**原樣搬到**第一個 Assert-NoReparseUnder 之前，**緊貼**它。
# 搬移（而非注入一行）是最強的 mutant 形式：產物就是產品自己的程式碼，只是順序錯了。
function New-MutantDoc($target) {
  $lines = @(Get-Content -LiteralPath $DOC -Encoding UTF8)
  if ($target -eq 'hook') {
    $L1 = 'if (Test-Path -LiteralPath $hbak -PathType Leaf) { Copy-Item -LiteralPath $hbak -Destination $hook -Force }'
    $L2 = 'elseif (Get-Entry $hook) { Remove-Item -LiteralPath $hook -Force }'
  } else {
    $L1 = 'if (Test-Path -LiteralPath $setbak -PathType Leaf) { Copy-Item -LiteralPath $setbak -Destination $setf -Force }'
    $L2 = 'elseif (Get-Entry $setf) { Remove-Item -LiteralPath $setf -Force }'
  }
  # ⚠️ **不要**把錨點叫 `$A`。PowerShell 的變數名**不分大小寫**，
  # 下面的 `$outArr` 若寫成 `$a` 就會把 `$A` 蓋掉，錨點變成陣列、`Idx` 一律回 -1，
  # 於是自我檢查以「產出未緊貼 anchor」失敗——2026-08-17 實際踩到，自我檢查先紅才發現。
  $anchor = "if (Test-Path -LiteralPath `$sbak -PathType Container) { Assert-NoReparseUnder 'skill 備份' `$sbak }"

  function Idx($ls, $n) { for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -ceq $n) { return $i } } return -1 }
  function Cnt($ls, $n) { @($ls | Where-Object { $_ -ceq $n }).Count }

  $i1 = Idx $lines $L1; $i2 = Idx $lines $L2; $ia = Idx $lines $anchor
  $iFirst = -1
  for ($k = 0; $k -lt $lines.Count; $k++) { if ($lines[$k] -clike '*Assert-NoReparseUnder *') { $iFirst = $k; break } }
  if ((Cnt $lines $L1) -ne 1 -or (Cnt $lines $L2) -ne 1 -or (Cnt $lines $anchor) -ne 1) { throw "SELFCHECK[$target] 三串不是各恰一份" }
  if ($i2 -ne $i1 + 1) { throw "SELFCHECK[$target] 來源兩行不相鄰" }
  if ($iFirst -ne $ia) { throw "SELFCHECK[$target] anchor 不是第一個 Assert-NoReparseUnder 呼叫" }
  # 缺陷若**已經**在產品裡（來源本來就在 anchor 之前），搬移會變成不搬，測試照樣綠卻什麼都沒證明。
  if ($i1 -le $ia)     { throw "SELFCHECK[$target] 來源本來就不在 anchor 之後 —— 搬移無意義，請先確認產品順序" }

  $acc = New-Object System.Collections.ArrayList
  $skip = $false
  foreach ($ln in $lines) {
    if ($ln -ceq $L1) { $skip = $true; continue }
    if ($skip -and ($ln -ceq $L2)) { $skip = $false; continue }
    if ($ln -ceq $anchor) { [void]$acc.Add($L1); [void]$acc.Add($L2) }
    [void]$acc.Add($ln)
  }
  $outArr = $acc.ToArray()
  $m1 = Idx $outArr $L1; $m2 = Idx $outArr $L2; $ma = Idx $outArr $anchor
  if ($outArr.Count -ne $lines.Count) { throw "SELFCHECK[$target] 行數變了" }
  if ((Cnt $outArr $L1) -ne 1 -or (Cnt $outArr $L2) -ne 1) { throw "SELFCHECK[$target] 搬移後不是各恰一份" }
  if ($m2 -ne $m1 + 1 -or $ma -ne $m2 + 1) { throw "SELFCHECK[$target] 產出未緊貼 anchor（本檔刻意釘死「緊貼」這個放法）" }
  $p = Join-Path $out "AI-INSTALL.mut-$target.md"
  [IO.File]::WriteAllLines($p, $outArr, (New-Object Text.UTF8Encoding $false))
  if ((Get-FileHash -LiteralPath $p).Hash -eq (Get-FileHash -LiteralPath $DOC).Hash) { throw "SELFCHECK[$target] hash 未變" }
  # ⚠️ 進度訊息一律走 `Write-Host`。用裸字串會**進到 pipeline**，於是本函式回傳
  # 「訊息 ＋ 路徑」的陣列，呼叫端拿訊息當路徑用（實際踩過：`Cannot find path '  自我檢查 OK…'`）。
  Write-Host "  自我檢查 OK：來源 $i1/$i2、anchor $ia → 產出 $m1/$m2/$ma、行數 $($outArr.Count) 不變"
  $p
}

function Invoke-Control($label, $sutPath, $docPath, $expectSummary) {
  $log = Join-Path $out "$label-$Shell.log"
  & pwsh -NoProfile -File $sutPath -Shell $Shell -Doc $docPath *> $log
  $rc = $LASTEXITCODE
  $sum = (Get-Content $log | Select-Object -Last 1).Trim()
  $stop = @(Get-Content $log | Select-String -Pattern 'STOP 案數不符').Count -gt 0
  $actual = if ($stop) { 'STOP' } else { ($sum -replace '^\S+\s+','') }
  $ok = ($actual -eq $expectSummary) -and ($rc -ne 0)
  if (-not $ok) { $script:failures++ }
  "{0}  [{1}] rc={2}  實得「{3}」 預期「{4}」" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $label, $rc, $actual, $expectSummary
  Get-Content $log | Select-String -Pattern '^  FAIL' | ForEach-Object { "        " + $_.Line.Trim() }
}

"`n=== control 1：Set-Step2Settings 的寫入行改成 no-op（保留 Check）==="
# ⚠️ 錨點必須帶換行＋兩格縮排：這行字面在檔案裡有兩份（[C1] 的行內版未縮排、函式內縮排兩格）。
$c1a = "`n  Set-Content -LiteralPath `"`$h\.claude\settings.json`" -Value '{`"new`":true,`"hooks`":{`"PreToolUse`":[]}}' -NoNewline"
Assert-One $sutText $c1a 'c1'
$p = New-MutantSut 'c1' ($sutText.Replace($c1a, "`n  # MUTANT-C1 no-op"))
try { Invoke-Control 'c1-step2-noop' $p $DOC 'PASS=121  FAIL=5' } finally { Remove-Item -LiteralPath $p -Force }

"`n=== control 2：把 hook 還原兩行搬到首掃之前（緊貼 anchor）==="
Invoke-Control 'c2-hook-premove' $SUT (New-MutantDoc 'hook') 'PASS=122  FAIL=4'

"`n=== control 3：刪掉 [C3] 一條無副作用的 Check ==="
$c3a = "Check '正確 ts 的回滾必須成功（否則上面全是假通過）' `$r.Ok `$r.Out"
Assert-One $sutText $c3a 'c3'
$p = New-MutantSut 'c3' ($sutText.Replace($c3a, '# MUTANT-C3 刪掉一條 Check'))
try { Invoke-Control 'c3-minus-one-check' $p $DOC 'STOP' } finally { Remove-Item -LiteralPath $p -Force }

"`n=== control 4：把 settings 還原兩行搬到首掃之前（緊貼 anchor）==="
Invoke-Control 'c4-settings-premove' $SUT (New-MutantDoc 'settings') 'PASS=122  FAIL=4'

"`n========================================"
# ⚠️ 這裡釘的是**具體數字**，不是「有紅就好」。數字對不上就是有東西變了，要人去看，
# 不可以自動放寬 —— 「mutant 有被殺」是最容易被當成好消息收下的假訊號。
if ($failures -gt 0) { "mutation control 有 $failures 個結果不符預期"; exit 1 }
"全部 4 個 mutation control 結果符合預期"
exit 0
