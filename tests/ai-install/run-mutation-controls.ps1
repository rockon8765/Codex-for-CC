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
# ⚠️ 本檔必須是 **UTF-8 with BOM**（.gitattributes 另外釘 CRLF）。5.1 讀無 BOM 的
# 含中文 .ps1 會亂碼；第一版建檔時 BOM 被剝掉，實測補上後 5.1 才解析得正確。
# 兩個 host 直接跑本檔都驗過（`powershell -NoProfile -File …` 亦 4/4 rc=0）。
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
$script:mutantFiles = New-Object System.Collections.ArrayList

function Assert-One($text, $needle, $label) {
  $n = ([regex]::Matches($text, [regex]::Escape($needle))).Count
  if ($n -ne 1) { throw "SELFCHECK[$label] 錨點命中 $n 次（預期 1）—— 注入會打到不該打的地方" }
}

# ⚠️ 變異後的 SUT **必須放回 tests\ai-install\**：harness 用 `$PSScriptRoot\..\..` 定位 repo，
# 放到別處會解析到不相干目錄、1c 抄不到 payload，於是滿螢幕「1c 安裝成功」變紅 ——
# 看起來像 mutant 殺很大，其實是測試臺沒跑起來。（2026-08-17 實際踩過，得到 108/18 這種假數字。）
# ⚠️ 檔名帶 GUID，**不用固定名稱**：固定名稱會覆寫並在結束時刪掉同名的既有檔案
# （使用者剛好有一支同名腳本就遭殃），而且兩個 runner 並行時會互相踩。
# 這與 `run-windows.ps1` 的 `$work` 用 GUID 是同一個理由、同一次教訓。
function New-MutantSut($label, $text) {
  $p = Join-Path (Split-Path $SUT -Parent) ("run-windows.mutant-{0}-{1}.ps1" -f $label, [guid]::NewGuid().ToString('N'))
  if (Test-Path -LiteralPath $p) { throw "SELFCHECK[$label] 變異檔名撞到既有檔案：$p" }
  # BOM 必要：5.1 讀無 BOM 的含中文 .ps1 會亂碼，而受測 harness 本身就含中文。
  [IO.File]::WriteAllText($p, $text, (New-Object Text.UTF8Encoding $true))
  if ((Get-FileHash -LiteralPath $p).Hash -eq (Get-FileHash -LiteralPath $SUT).Hash) {
    Remove-Item -LiteralPath $p -Force; throw "SELFCHECK[$label] 產出與原檔 hash 相同＝實際沒注入"
  }
  [void]$script:mutantFiles.Add($p)
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

# ⚠️ **只比 PASS／FAIL 總數是不夠的**（2026-08-17 第三輪 Codex 審查抓到的 blocker，本檔第一版就是那樣）：
# 「該紅的那條牙齒變綠 ＋ 某條不相關的斷言變紅」是**等量交換**，總數完全相同 ⇒ 假綠。
# 這與 repo 早就記載的「案數不變、全綠、mutant 存活」是同一個病，只是搬到了 control 層。
# 所以這裡釘三樣，缺一不可：
#   (a) **具名失敗集合逐條精確相等**（順序無關、`-ceq` 大小寫敏感、多一條少一條都算 FAIL）；
#   (b) **精確退出碼**，不是「任意非零」；
#   (c) 案數守衛型的 control 另外釘 **STOP 那一行的完整字面**（含「實跑 125、預期 126」兩個數字），
#       不是「log 裡任何地方出現 STOP 就算」。
function Invoke-Control($label, $sutPath, $docPath, $expect) {
  $log = Join-Path $out "$label-$Shell.log"
  & pwsh -NoProfile -File $sutPath -Shell $Shell -Doc $docPath *> $log
  $rc = $LASTEXITCODE
  $lines = @(Get-Content -LiteralPath $log)

  # 實際的具名失敗集合：抓 `  FAIL  <名稱>`，只取名稱那一行（詳情是下一行、縮排更深）。
  $actualFails = @($lines | Where-Object { $_ -cmatch '^  FAIL  ' } | ForEach-Object { $_ -creplace '^  FAIL  ', '' })
  $expectFails = @($expect.Fails)
  $missing = @(Compare-Object $expectFails $actualFails -CaseSensitive | Where-Object SideIndicator -eq '<=' | ForEach-Object InputObject)
  $extra   = @(Compare-Object $expectFails $actualFails -CaseSensitive | Where-Object SideIndicator -eq '=>' | ForEach-Object InputObject)

  $problems = @()
  if ($rc -ne $expect.Rc) { $problems += "rc=$rc（預期 $($expect.Rc)）" }
  foreach ($m in $missing) { $problems += "該紅卻沒紅：$m" }
  foreach ($e in $extra)   { $problems += "不該紅卻紅了：$e" }
  if ($expect.ContainsKey('StopLine')) {
    # 釘完整字面（含兩個數字）。只找 'STOP 案數不符' 會讓「實跑 100／預期 126」也算過。
    if (-not ($lines | Where-Object { $_ -ceq $expect.StopLine })) {
      $problems += "找不到預期的案數守衛訊息（逐字）：$($expect.StopLine)"
    }
  } else {
    # 非 STOP 型的 control 反過來要求**不可**出現案數守衛訊息——否則「少跑一堆案」會被
    # 誤讀成「牙齒有效」。
    if ($lines | Where-Object { $_ -cmatch 'STOP 案數不符' }) { $problems += '不該出現案數守衛訊息，但出現了（案數被改動）' }
  }

  $ok = $problems.Count -eq 0
  if (-not $ok) { $script:failures++ }
  "{0}  [{1}] rc={2}  具名失敗 {3} 條（預期 {4}）" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $label, $rc, $actualFails.Count, $expectFails.Count
  $actualFails | ForEach-Object { "        紅：$_" }
  $problems    | ForEach-Object { "     ❌ $_" }
}

try {

# 期望的具名失敗集合。**改動 harness 的斷言字串時這裡要一起改**，那是刻意的摩擦：
# 它逼你確認「名字換了」與「牙齒掉了」是兩回事。
$STEP2 = '前置：settings 已與備份不同（否則 settings 型的違規看不見）'
$WIDE  = '寬 oracle（整個假家目錄）抓到預掃前的 mutation'
$HOME_UNCHANGED = '中止後整個假家目錄未變（hook／settings 也在內）'
$SRC_ANCHOR = '來源錨點：三串各唯一、兩行相鄰、anchor 是第一個 Assert-NoReparseUnder、且來源在 anchor 之後'
$OUTPUT_DIFF = '產出：行數不變、各恰一份、兩行相鄰且緊貼 anchor、且確實與原檔不同'

"`n=== control 1：Set-Step2Settings 的寫入行改成 no-op（保留 Check）==="
# ⚠️ 錨點必須帶換行＋兩格縮排：這行字面在檔案裡有兩份（[C1] 的行內版未縮排、函式內縮排兩格）。
$c1a = "`n  Set-Content -LiteralPath `"`$h\.claude\settings.json`" -Value '{`"new`":true,`"hooks`":{`"PreToolUse`":[]}}' -NoNewline"
Assert-One $sutText $c1a 'c1'
Invoke-Control 'c1-step2-noop' (New-MutantSut 'c1' ($sutText.Replace($c1a, "`n  # MUTANT-C1 no-op"))) $DOC @{
  Rc = 1
  # 四條 fixture 前置 ＋ settings 目標的寬 oracle。⚠️ `[M13c][hook]` 的寬 oracle **不在**這裡：
  # hook 目標不依賴 step2，它仍然該綠。少了這個區辨，本 control 就只是「有紅就好」。
  Fails = @(
    "[M13][備份子樹] $STEP2"
    "[M13][live 子樹] $STEP2"
    "[M13c][hook] $STEP2"
    "[M13c][settings] $STEP2"
    "[M13c][settings] $WIDE"
  )
}

"`n=== control 2：把 hook 還原兩行搬到首掃之前（緊貼 anchor）==="
Invoke-Control 'c2-hook-premove' $SUT (New-MutantDoc 'hook') @{
  Rc = 1
  # hook 目標的兩道守衛 ＋ 兩條 M13 寬 oracle。⚠️ `[M13c][settings]` 三條必須**保持綠**。
  Fails = @(
    "[M13][備份子樹] $HOME_UNCHANGED"
    "[M13][live 子樹] $HOME_UNCHANGED"
    "[M13c][hook] $SRC_ANCHOR"
    "[M13c][hook] $OUTPUT_DIFF"
  )
}

"`n=== control 3：刪掉 [C3] 一條無副作用的 Check ==="
$c3a = "Check '正確 ts 的回滾必須成功（否則上面全是假通過）' `$r.Ok `$r.Out"
Assert-One $sutText $c3a 'c3'
Invoke-Control 'c3-minus-one-check' (New-MutantSut 'c3' ($sutText.Replace($c3a, '# MUTANT-C3 刪掉一條 Check'))) $DOC @{
  Rc = 1
  # 刪的是**無副作用**的一條，所以不該有任何具名失敗——紅的只能是案數守衛本身。
  Fails = @()
  # 釘完整字面含兩個數字：只找 'STOP 案數不符' 的話，「實跑 100、預期 126」也會過。
  StopLine = '  STOP 案數不符：實跑 125、預期 126 —— 有案被刪除或跳過，或新增後忘了更新 EXPECTED_CHECKS'
}

"`n=== control 4：把 settings 還原兩行搬到首掃之前（緊貼 anchor）==="
Invoke-Control 'c4-settings-premove' $SUT (New-MutantDoc 'settings') @{
  Rc = 1
  # 與 control 2 完全對稱。⚠️ `[M13c][hook]` 三條必須**保持綠**——這正是
  # 「settings 目標不是靠 hook 目標順帶通過」的證據。
  Fails = @(
    "[M13][備份子樹] $HOME_UNCHANGED"
    "[M13][live 子樹] $HOME_UNCHANGED"
    "[M13c][settings] $SRC_ANCHOR"
    "[M13c][settings] $OUTPUT_DIFF"
  )
}

} finally {
  foreach ($f in $script:mutantFiles) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
}

"`n========================================"
# ⚠️ 釘的是**具名失敗集合 ＋ 精確 rc**，不是總數、也不是「有紅就好」。
# 只比總數會被「該紅的變綠 ＋ 不相關的紅一條」等量交換掉 ——
# 那是 repo 早就記載的「案數不變、全綠、mutant 存活」搬到 control 層。
# 對不上就是有東西變了，要人去看，不可以自動放寬。
if ($failures -gt 0) { "mutation control 有 $failures 個結果不符預期"; exit 1 }
"全部 4 個 mutation control 的具名失敗集合與 rc 皆符合預期"
exit 0
