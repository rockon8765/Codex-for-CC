# AI-INSTALL.md Windows 區塊測試臺
# 從文件抽出 ```powershell 區塊 → 用假 USERPROFILE 執行 → 檢查檔案系統狀態
# 含變異注入：錯誤分支不注入就走不到，等於沒驗。
param([string]$Shell = 'pwsh', [string]$Doc = '')

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$doc  = if ($Doc) { $Doc } else { Join-Path $repo 'docs\AI-INSTALL.md' }
"受測文件：$doc"
# ⚠️ 不要用固定路徑。舊版寫死 $env:TEMP\ai-install-harness 並在開頭遞迴刪除 ——
# 使用者剛好有同名資料、或兩個測試臺並行時，後啟動的會直接刪掉前者的資料
# （實測撞過 Access Denied 而中止清理）。改成每次用 GUID 新建，
# 清理只針對「本次建立且符合本前綴」的路徑。
$work = Join-Path $env:TEMP ('ai-install-harness-' + [guid]::NewGuid().ToString('N'))

# 抽取
$lines = Get-Content -LiteralPath $doc -Encoding UTF8
$blocks = @(); $cur = $null
foreach ($l in $lines) {
  if ($l -match '^```powershell\s*$') { $cur = New-Object System.Collections.ArrayList; continue }
  if ($null -ne $cur -and $l -match '^```\s*$') { $blocks += ,($cur -join "`n"); $cur = $null; continue }
  if ($null -ne $cur) { [void]$cur.Add($l) }
}
function Pick($needle) {
  $m = @($blocks | Where-Object { $_ -like "*$needle*" })
  if ($m.Count -ne 1) { throw "抽取失敗：'$needle' 命中 $($m.Count) 個區塊（預期 1）" }
  $m[0]
}
$B1b = Pick 'backup ts='
$B1c = Pick 'install OK'
$Brb = Pick 'Test-Exactly1'
"抽取：1b=$($B1b.Length) 字元, 1c=$($B1c.Length) 字元, rollback=$($Brb.Length) 字元"

$PLACEHOLDER = '<貼上 1b 印出的值>'
if ($Brb -notlike "*$PLACEHOLDER*") { throw '回滾區塊找不到 ts 佔位符，抽取邏輯已過期' }

# 執行器
# 先把 host 解析成絕對路徑，找不到就在這裡失敗。不解析的話，executable 不存在時
# `& $exe` **不會設定 `$LASTEXITCODE`**，於是上一次成功留下的 0 會被沿用
# ——「找不到 host 卻判定成功」。（合併前 Codex 審查用最小探針在 5.1 與 7.x 都復現；
# 現行寫法最後是靠 `$out` 為 null、`.Trim()` 再爆掉才變紅，那是偶然的誤紅保護，不是結構。）
$exeName = if ($Shell -eq 'pwsh') { 'pwsh' } else { 'powershell' }
$exe = try { (Get-Command $exeName -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
       catch { throw "找不到可執行的 host '$exeName'（-Shell $Shell）：$($_.Exception.Message)" }
"執行 host：$exe"
function Invoke-Block($code, $fakeHome) {
  $f = Join-Path $work 'block.ps1'
  [IO.File]::WriteAllText($f, $code, (New-Object Text.UTF8Encoding $true))
  $prev = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  # ⚠️ **Windows PowerShell 5.1 專屬**：native command 寫 stderr 時，5.1 會把它包成
  # `NativeCommandError` 的 ErrorRecord；撞上本檔開頭的 `$ErrorActionPreference = 'Stop'`
  # 就會讓**整個測試臺**當場中止。7.x 不會。實測（HEAD ad8ff12、未含 M13 的版本亦同）：
  # `-Shell powershell` 一路綠到 `[M2]` 之前，然後停在 M1 第一個「被拒」案 ——
  # 那是第一個會寫 stderr 的子行程。也就是說 README 宣傳的 5.1 跑法先前**跑不完**，
  # Windows 側實際只有 pwsh 一個 host 有覆蓋。
  # 這裡只在**函式作用域**內降級（離開函式自動還原，不影響其他斷言的 Stop 語義）：
  # 子行程的成敗一律以 `$LASTEXITCODE` 判斷，本來就不該由 host 的錯誤串流決定。
  $ErrorActionPreference = 'Continue'
  # 每次呼叫前重設：不重設就可能沿用上一次的退出碼（見上方 host 解析的註解）。
  $global:LASTEXITCODE = $null
  try {
    $out = & $exe -NoProfile -NonInteractive -File $f 2>&1 | Out-String
    $rc = $LASTEXITCODE
  } finally { $env:USERPROFILE = $prev }
  # 拿不到整數退出碼就無法判定成敗 —— 明確炸掉，不要退化成「$rc -eq 0 為 false」而看似正常。
  if ($rc -isnot [int]) { throw "子行程沒有回傳整數退出碼（rc=[$rc]），無法判定成敗：$f" }
  [pscustomobject]@{ Ok = ($rc -eq 0); Out = ("$out").Trim() }
}
function Invoke-Rollback($ts, $fakeHome) { Invoke-Block ($Brb.Replace($PLACEHOLDER, $ts)) $fakeHome }

function New-FakeHome($name) {
  $h = Join-Path $work $name
  if (Test-Path -LiteralPath $h) { Remove-Item -LiteralPath $h -Recurse -Force }
  New-Item -ItemType Directory -Force -Path "$h\.claude\hooks", "$h\.claude\skills" | Out-Null
  $h
}
function Add-ExistingInstall($h) {
  Set-Content -LiteralPath "$h\.claude\hooks\super-mode-consult-gate.js" -Value 'OLD-HOOK' -NoNewline
  New-Item -ItemType Directory -Force -Path "$h\.claude\skills\超級模式" | Out-Null
  Set-Content -LiteralPath "$h\.claude\skills\超級模式\SKILL.md" -Value 'OLD-SKILL' -NoNewline
  Set-Content -LiteralPath "$h\.claude\settings.json" -Value '{"old":true}' -NoNewline
}
function Get-Snapshot($h) {
  if (-not (Test-Path -LiteralPath $h)) { return '<none>' }
  # 比對整個假 USERPROFILE，但明確忽略 pwsh 自己在被重導的 HOME 下建的 profile 資料
  # （AppData\Local\Microsoft\PowerShell\StartupProfileData-*），那是測試臺雜訊。
  # 明確忽略而非縮小比對範圍，否則未來新增的 .claude 之外副作用會逃過檢查。
  (Get-ChildItem -LiteralPath $h -Recurse -Force |
    Where-Object { $_.FullName -notlike '*\AppData\Local\Microsoft\PowerShell*' } |
    Sort-Object FullName | ForEach-Object {
      $lk = if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { 'L' } else { '' }
      if ($_.PSIsContainer) { "D$lk|$($_.FullName.Substring($h.Length))" }
      else { "F$lk|$($_.FullName.Substring($h.Length))|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
  }) -join "`n"
}
function Get-Ts($out) { if ($out -match 'backup ts=(\d{8}-\d{6})') { $Matches[1] } else { $null } }

# 本檔預期跑出的**總案數**（PASS + FAIL）。結尾會硬斷言。
# 沒有這一條，刪掉任何一個 Check 仍會印 `PASS=111 FAIL=0` 並 exit 0 ——「少一案」是抓不到的假綠。
# ⚠️ 這個總數與受測文件**無關**（反向驗證只會改變 PASS/FAIL 的分佈，不會改變案數），
# 所以它是穩定的不變量。新增或移除案時必須同步更新，那是刻意的摩擦。
$EXPECTED_CHECKS = 112
$script:pass = 0; $script:fail = 0
function Check($name, $cond, $detail) {
  if ($cond) { $script:pass++; "  PASS  $name" }
  else { $script:fail++; "  FAIL  $name`n        $detail" }
}

New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location $repo
try {

"`n[C1] 既有安裝 -> 安裝 -> 回滾（含冪等）"
$h = New-FakeHome 'c1'; Add-ExistingInstall $h
$snap0 = Get-Snapshot "$h\.claude\skills\超級模式"
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '1b 成功並印出 ts' ($r.Ok -and $ts) $r.Out
$r = Invoke-Block $B1c $h
Check '1c 安裝成功' ($r.Ok -and $r.Out -match 'install OK') $r.Out
Check '安裝後 live 已換成新版' ((Get-Snapshot "$h\.claude\skills\超級模式") -ne $snap0) '安裝沒有改變 live'
# 模擬步驟 2 把 hook 條目合併進 settings。**沒有這一步，下面的「settings 還原」斷言恆真**
# ——settings 從頭到尾都是 OLD，就算把回滾的 settings 還原程式碼整段刪掉也照樣綠。
Set-Content -LiteralPath "$h\.claude\settings.json" -Value '{"new":true,"hooks":{"PreToolUse":[]}}' -NoNewline
Check '前置：settings 已被步驟 2 改動（否則還原斷言恆真）' ((Get-Content -LiteralPath "$h\.claude\settings.json" -Raw) -ne '{"old":true}') '注入失敗，本案的 settings 斷言無效'
for ($i = 1; $i -le 3; $i++) {
  $r = Invoke-Rollback $ts $h
  Check "第 $i 次回滾成功" $r.Ok $r.Out
  Check "第 $i 次回滾後 skill 等於安裝前" ((Get-Snapshot "$h\.claude\skills\超級模式") -eq $snap0) '還原內容不符'
  Check "第 $i 次回滾後 hook 還原" ((Get-Content -LiteralPath "$h\.claude\hooks\super-mode-consult-gate.js" -Raw) -eq 'OLD-HOOK') 'hook 未還原'
  Check "第 $i 次回滾後 settings 還原" ((Get-Content -LiteralPath "$h\.claude\settings.json" -Raw) -eq '{"old":true}') 'settings 未還原'
}

"`n[C2] 全新安裝 -> 回滾應刪除"
$h = New-FakeHome 'c2'
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '1b 成功' ($r.Ok -and $ts) $r.Out
# 三個 .absent 標記都要在——少一個就代表某個元件的「全新安裝」語義沒被記錄
foreach ($m in @("skills-backup\超級模式.bak-$ts.absent",
                 "hooks\super-mode-consult-gate.js.bak-$ts.absent",
                 "settings.json.bak-$ts.absent")) {
  Check ".absent 標記已建立：$m" (Test-Path -LiteralPath "$h\.claude\$m" -PathType Leaf) "缺 $m"
}
$r = Invoke-Block $B1c $h
Check '1c 安裝成功' $r.Ok $r.Out
# 模擬步驟 2 建立了原本不存在的 settings。**沒有這一步，「回滾後 settings 已刪除」
# 就是恆真**（它從頭到尾都不存在），刪掉回滾的 settings 刪除程式碼也測不出來。
Set-Content -LiteralPath "$h\.claude\settings.json" -Value '{"hooks":{"PreToolUse":[]}}' -NoNewline
Check '前置：步驟 2 已建立 settings（否則刪除斷言恆真）' (Test-Path -LiteralPath "$h\.claude\settings.json") '注入失敗'
$r = Invoke-Rollback $ts $h
Check '回滾成功' $r.Ok $r.Out
Check '回滾後 skill 已刪除' (-not (Test-Path -LiteralPath "$h\.claude\skills\超級模式")) 'skill 殘留'
Check '回滾後 hook 已刪除' (-not (Test-Path -LiteralPath "$h\.claude\hooks\super-mode-consult-gate.js")) 'hook 殘留'
Check '回滾後 settings 已刪除' (-not (Test-Path -LiteralPath "$h\.claude\settings.json")) 'settings 殘留'

"`n[M1] 變異注入：ts 含萬用字元（第七輪 HIGH 回歸）"
$h = New-FakeHome 'm1'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts1 = Get-Ts $r.Out
Start-Sleep -Seconds 1
$r = Invoke-Block $B1b $h; $ts2 = Get-Ts $r.Out
Check '兩個不同 ts 的備份都建立了' ($ts1 -and $ts2 -and $ts1 -ne $ts2) "ts1=$ts1 ts2=$ts2"
$r = Invoke-Block $B1c $h
$after = Get-Snapshot $h
foreach ($bad in @(($ts2.Substring(0,$ts2.Length-1) + '?'), ($ts2.Substring(0,8) + '-*'), ($ts2.Substring(0,$ts2.Length-1) + '[0-9]'))) {
  $r = Invoke-Rollback $bad $h
  Check "ts='$bad' 被拒" (-not $r.Ok) "竟然成功：$($r.Out)"
  Check "ts='$bad' 後 live 完全未變" ((Get-Snapshot $h) -eq $after) 'live 被動過'
}

"`n[M2] 變異注入：ts 格式錯、以及格式對但不存在"
$h = New-FakeHome 'm2'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
$after = Get-Snapshot $h
$goodTs = $ts
foreach ($bad in @('abc', '20260727-15440', '99999999-999999', '20260727_154409', ($goodTs + "`n"), (' ' + $goodTs))) {
  $r = Invoke-Rollback $bad $h
  Check "ts='$bad' 被拒" (-not $r.Ok) "竟然成功：$($r.Out)"
  Check "ts='$bad' 後 live 完全未變" ((Get-Snapshot $h) -eq $after) 'live 被動過'
}

"`n[M3] 變異注入：skill 備份被換成 junction"
$h = New-FakeHome 'm3'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
$sbak = "$h\.claude\skills-backup\超級模式.bak-$ts"
$elsewhere = Join-Path $work 'm3-elsewhere'
New-Item -ItemType Directory -Force -Path $elsewhere | Out-Null
Set-Content -LiteralPath "$elsewhere\SKILL.md" -Value 'WRONG-TARGET' -NoNewline
Remove-Item -LiteralPath $sbak -Recurse -Force
cmd /c "mklink /J `"$sbak`" `"$elsewhere`"" | Out-Null
$mkRc = $LASTEXITCODE
# 注入成功與否要自己驗：mklink 失敗時備份只是「不見了」，rollback 會改用
# 「找不到有效備份」這個**不相干的理由**拒絕 —— 一樣非零，本案於是永遠不會紅。
# rc 與型別兩個都驗：型別擋「根本沒建成」，
# rc 擋「建立失敗但原地剛好有殘留 reparse point」——後者只驗型別會漏。
# （實測：link 路徑被佔時 mklink 回 1；指向不存在目標回 0，那是 /J 的正常行為。）
$bakItem = Get-Item -LiteralPath $sbak -Force -ErrorAction SilentlyContinue
Check '前置：junction 備份確實建立' ($mkRc -eq 0 -and $null -ne $bakItem -and ($bakItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) "mklink rc=$mkRc 或不是 reparse point，本案等於沒測"
$after = Get-Snapshot "$h\.claude\skills"
$r = Invoke-Rollback $ts $h
Check 'junction 備份被拒' (-not $r.Ok) "竟然成功：$($r.Out)"
Check 'junction 備份被拒後 live 未變' ((Get-Snapshot "$h\.claude\skills") -eq $after) 'live 被動過'

"`n[M4] 變異注入：live skill 位置是 junction"
$h = New-FakeHome 'm4'
$elsewhere = Join-Path $work 'm4-elsewhere'
New-Item -ItemType Directory -Force -Path $elsewhere | Out-Null
Set-Content -LiteralPath "$elsewhere\SKILL.md" -Value 'ELSEWHERE' -NoNewline
cmd /c "mklink /J `"$h\.claude\skills\超級模式`" `"$elsewhere`"" | Out-Null
$mkRc = $LASTEXITCODE
# 同上：mklink 失敗時 live 位置根本不存在，1b 會走「原本沒安裝」那條分支——
# 中止與否的理由就換了一個，前置不驗的話本案的區辨性是假的。
$liveItem = Get-Item -LiteralPath "$h\.claude\skills\超級模式" -Force -ErrorAction SilentlyContinue
Check '前置：live junction 確實建立' ($mkRc -eq 0 -and $null -ne $liveItem -and ($liveItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) "mklink rc=$mkRc 或不是 reparse point，本案等於沒測"
$r = Invoke-Block $B1b $h
Check '1b 對 junction live 中止' (-not $r.Ok) "竟然成功：$($r.Out)"
# 1b 依序處理 hook -> skill -> settings，hook 那步會先建 .absent 才輪到 skill 中止。
# 文件聲明的性質是「中止就不印 ts，所以有印 ts 才等於三個備份都完成」——驗這個。
Check '1b 中止時未印出 ts（部分產物不算完成）' (-not (Get-Ts $r.Out)) "竟印出 ts：$($r.Out)"
Check '1b 沒有為 junction 的 skill 建 .absent' (-not (Test-Path -LiteralPath "$h\.claude\skills-backup" -PathType Container) -or -not (Get-ChildItem -LiteralPath "$h\.claude\skills-backup" -Force -Filter '*.absent' -ErrorAction SilentlyContinue)) 'skill 被誤標成 .absent'

"`n[M5] 變異注入：skill 備份被換成一般檔案"
$h = New-FakeHome 'm5'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
$sbak = "$h\.claude\skills-backup\超級模式.bak-$ts"
Remove-Item -LiteralPath $sbak -Recurse -Force
Set-Content -LiteralPath $sbak -Value 'not-a-dir' -NoNewline
# 與 M3／M4 同一形狀（注入手法換成寫檔而已）：寫檔沒成功時備份只是「不見了」，
# rollback 會改用「找不到有效備份」這個**不相干的理由**拒絕 —— 一樣非零，本案照樣綠。
# 要驗到「是一般檔案、且不是 reparse point」才算真的走到 precheck 的型別分支。
$m5Item = Get-Item -LiteralPath $sbak -Force -ErrorAction SilentlyContinue
Check '前置：一般檔案備份確實建立' ($null -ne $m5Item -and -not $m5Item.PSIsContainer -and ($m5Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) '不是一般檔案，本案等於沒測'
$after = Get-Snapshot "$h\.claude\skills"
$r = Invoke-Rollback $ts $h
Check '型別錯的備份被拒' (-not $r.Ok) "竟然成功：$($r.Out)"
Check '型別錯被拒後 live 未變' ((Get-Snapshot "$h\.claude\skills") -eq $after) 'live 被動過'

"`n[M6] 變異注入：備份與 .absent 同時存在"
$h = New-FakeHome 'm6'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
New-Item -ItemType File -Path "$h\.claude\skills-backup\超級模式.bak-$ts.absent" | Out-Null
$after = Get-Snapshot "$h\.claude\skills"
$r = Invoke-Rollback $ts $h
Check '兩者並存被拒' (-not $r.Ok) "竟然成功：$($r.Out)"
Check '兩者並存被拒後 live 未變' ((Get-Snapshot "$h\.claude\skills") -eq $after) 'live 被動過'

"`n[M7] 變異注入：安裝後 live 與來源不符（安裝驗證必須抓到）"
$h = New-FakeHome 'm7'
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$anchor = '$srcRoot = (Resolve-Path -LiteralPath $src).Path'
$mut = $B1c.Replace($anchor, 'Set-Content -LiteralPath "$live\SKILL.md" -Value "TAMPERED" -NoNewline' + "`n" + $anchor)
Check '變異確實注入（否則本案等於沒測）' ($mut -ne $B1c) '注入失敗：錨點字串已改變'
$r = Invoke-Block $mut $h
Check '安裝驗證抓到竄改' ((-not $r.Ok) -and ($r.Out -match '安裝驗證失敗')) "未抓到：$($r.Out)"

"`n[M8] 1b 重跑"
$h = New-FakeHome 'm8'; Add-ExistingInstall $h
$r1 = Invoke-Block $B1b $h; $ts = Get-Ts $r1.Out
$r2 = Invoke-Block $B1b $h
if ((Get-Ts $r2.Out) -eq $ts -or -not $r2.Ok) {
  Check '同秒重跑被拒' (-not $r2.Ok) "竟然成功：$($r2.Out)"
} else {
  Check '不同秒重跑允許' $r2.Ok $r2.Out
}

"`n[M9] 變異注入：live skill 樹「內部」有 junction（第八輪 HIGH 回歸）"
foreach ($variant in @(@{n='空目標'; fill=$false}, @{n='非空目標'; fill=$true})) {
  $tag = "m9-$($variant.n)"
  $h = New-FakeHome $tag; Add-ExistingInstall $h
  $tgt = Join-Path $work "$tag-target"
  New-Item -ItemType Directory -Force -Path $tgt | Out-Null
  if ($variant.fill) { Set-Content -LiteralPath "$tgt\payload.txt" -Value 'X' -NoNewline }
  New-Item -ItemType Directory -Force -Path "$h\.claude\skills\超級模式\references" | Out-Null
  cmd /c "mklink /J `"$h\.claude\skills\超級模式\references\shared`" `"$tgt`"" | Out-Null
  $isJunction = ((Get-Item -LiteralPath "$h\.claude\skills\超級模式\references\shared" -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
  Check "[$($variant.n)] 前置：內嵌 junction 確實建立" $isJunction '不是 reparse point，本案等於沒測'
  $r = Invoke-Block $B1b $h
  Check "[$($variant.n)] 1b 對內嵌 junction 中止" (-not $r.Ok) "竟然成功：$($r.Out)"
  Check "[$($variant.n)] 1b 未印出 ts" (-not (Get-Ts $r.Out)) "竟印出 ts：$($r.Out)"
  $bakJ = "$h\.claude\skills-backup\超級模式.bak-*\references\shared"
  Check "[$($variant.n)] 沒有留下被實體化的備份" (-not (Get-ChildItem -Path $bakJ -ErrorAction SilentlyContinue)) 'junction 已被複製成普通目錄'
}

"`n[M11] 變異注入：回滾期的內嵌 link（頂層乾淨、link 藏在子樹）"
# 與 M3／M9 的差別：M3 換掉的是**備份頂層**，M9 驗的是 **1b**。
# 本案兩者的頂層都完全合法，link 只藏在子樹裡，而且要到**回滾**才會被用到 ——
# 那正是舊版的破口：預檢只看頂層 → 通過 → 先刪掉 live → 再從錯誤拓撲還原。
foreach ($case in @(@{ n='備份子樹'; where='bak' }, @{ n='live 子樹'; where='live' })) {
  $tag = "m11-$($case.where)"
  $h = New-FakeHome $tag; Add-ExistingInstall $h
  $r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
  Check "[$($case.n)] 前置：1b 成功並印出 ts" ($r.Ok -and $ts) $r.Out
  $r = Invoke-Block $B1c $h
  Check "[$($case.n)] 前置：1c 安裝成功" $r.Ok $r.Out

  $tgt = Join-Path $work "$tag-target"
  New-Item -ItemType Directory -Force -Path $tgt | Out-Null
  Set-Content -LiteralPath "$tgt\payload.txt" -Value 'OUTSIDE' -NoNewline

  $root = if ($case.where -eq 'bak') { "$h\.claude\skills-backup\超級模式.bak-$ts" }
          else                       { "$h\.claude\skills\超級模式" }
  New-Item -ItemType Directory -Force -Path "$root\references" | Out-Null
  cmd /c "mklink /J `"$root\references\shared`" `"$tgt`"" | Out-Null
  $mkRc = $LASTEXITCODE
  $e = Get-Item -LiteralPath "$root\references\shared" -Force -ErrorAction SilentlyContinue
  $isJ = ($null -ne $e) -and ((($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) -ne 0)
  # rc ＋型別雙驗（同 M3）：注入沒成功的話，回滾會因**不相干的理由**失敗，本案永遠不會紅。
  Check "[$($case.n)] 前置：內嵌 junction 確實建立" (($mkRc -eq 0) -and $isJ) "mklink rc=$mkRc, isJunction=$isJ"

  $after = Get-Snapshot "$h\.claude\skills"
  $r = Invoke-Rollback $ts $h
  Check "[$($case.n)] 回滾中止" (-not $r.Ok) "竟然成功：$($r.Out)"
  # 這條才是 B1 的重點：舊版是「先刪 live、還原時才炸」，所以 live 必須原封不動。
  Check "[$($case.n)] 被拒後 live 未變" ((Get-Snapshot "$h\.claude\skills") -eq $after) 'live 被動過'
  Check "[$($case.n)] junction 外部目標未被刪" (Test-Path -LiteralPath "$tgt\payload.txt") '外部真實資料被刪'
}

"`n[M12] live skill 不存在時的回滾必須成功（B1 前置條件的守護）"
# 掃描寫成 fail-closed 時很容易連「沒有子樹可掃」也一起擋掉，
# 那會讓「live 已被手動移除、想從備份還原」這條**合法**路徑永久失敗。
# 這與 M11 是同一形狀 bug 的兩面，一起犯就要一起修。
$h = New-FakeHome 'm12'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '前置：1b 成功並印出 ts' ($r.Ok -and $ts) $r.Out
$r = Invoke-Block $B1c $h
Check '前置：1c 安裝成功' $r.Ok $r.Out
Remove-Item -LiteralPath "$h\.claude\skills\超級模式" -Recurse -Force
Check '前置：live skill 確實已移除' (-not (Test-Path -LiteralPath "$h\.claude\skills\超級模式")) 'live 還在，本案等於沒測'
$r = Invoke-Rollback $ts $h
Check '回滾仍成功' $r.Ok $r.Out
Check '回滾後 live skill 已還原' (Test-Path -LiteralPath "$h\.claude\skills\超級模式\SKILL.md" -PathType Leaf) '沒有還原'

# 注入自我檢查的探針，會被送進**受測 host 的 child 行程**執行（見 Test-EnumBlocked）。
$m13ProbeTpl = @'
$ErrorActionPreference = 'Stop'
try { $null = @(Get-ChildItem -LiteralPath '<ROOT>' -Recurse -Force -ErrorAction Stop); 'ENUM=OK' }
catch { 'ENUM=FAIL' }
'@

"`n[M13] 列舉失敗必須在任何 mutation 之前中止（fail-closed 契約本身）"
# M11 驗「掃到 link」、M12 驗「沒有子樹可掃」，但**掃不動**這條路徑在 Windows 側先前
# 只有區塊開頭 `$ErrorActionPreference = 'Stop'` 的**靜態推論**，沒有動態測試
# （POSIX 側 2026-08-10 已補 `[M13]`，Windows 側當時列為單獨一批）。
# 那條才是資料安全契約：列舉失敗時若 fail-open，就會先刪 live、再從一棵沒驗證過的樹還原。
#
# 注入手法＝**對自己下 Deny ACE**（POSIX 側是 `chmod 000`）。目錄的擁有者即使沒有管理員
# 權限也隱含保有 WRITE_DAC，所以「拒絕自己 ListDirectory」以及事後把它拿掉都做得到。
#
# ⚠️ **不要照抄 POSIX 的 root 前置守衛。** 那邊必須先擋 root，是因為 root 會忽略權限位元、
# 讓 `chmod 000` 整個失效。Windows 這邊不一樣：Deny ACE 在存取檢查裡優先於 Allow，
# 提權本身並不會讓注入失效（`Get-ChildItem` 不會去用 SeBackupPrivilege）。真正會讓它失效的是
# 「檔案系統不支援 ACL」「行程啟用了備份權限」這類情況 ——**那些無法可靠地前置偵測**，
# 所以改由下面的**注入自我檢查當唯一權威**：注入沒生效就直接 FAIL，不給綠燈、也不靜默跳過
# （本測試臺沒有 SKIP 機制，加一個會改動結尾 `PASS=/FAIL=` 摘要行的契約，
# 而交接文件與反向驗證都靠那一行）。
#
# 斷言名稱一律帶 `[M13]` 前綴：M11 也用 `[備份子樹]`／`[live 子樹]`，不加前綴的話
# 「前置：1b 成功並印出 ts」等名稱會在兩個區塊裡重複，反向驗證就沒辦法逐條核對。
#
# ⚠️ **這是狀態 oracle，不是事件 oracle。** 快照相等只能證明「最終內容相同」，
# 不能證明「途中從未刪除又還原」。產品目前沒有任何失敗後還原的邏輯，所以狀態比對足以當證據，
# 但**文件不要把它讀成「證明 mutation 從未開始」**。（合併前 Codex 審查要求講清楚。）
$m13Me = [Security.Principal.WindowsIdentity]::GetCurrent().User

function New-LockedDir($root) {
  # 在 <root>\references\locked 放一個檔再上鎖：空目錄有機會被「剛好 rmdir 掉」而讓注入
  # 自己消失（POSIX 側正是這個差異造成 GNU／BSD 退出碼不一致），
  # 放了檔才讓「掃不動的子樹裡有真實資料」這件事成立。
  $p = "$root\references\locked"
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  Set-Content -LiteralPath "$p\payload.txt" -Value 'LOCKED' -NoNewline
  $p
}
function Set-DenyEnumerate($path) {
  $rule = New-Object Security.AccessControl.FileSystemAccessRule(
    $script:m13Me, 'ListDirectory', 'ContainerInherit,ObjectInherit', 'None', 'Deny')
  $acl = Get-Acl -LiteralPath $path; $acl.AddAccessRule($rule); Set-Acl -LiteralPath $path -AclObject $acl
  $rule
}
function Clear-DenyEnumerate($path, $rule) {
  $acl = Get-Acl -LiteralPath $path
  $null = $acl.RemoveAccessRule($rule)
  Set-Acl -LiteralPath $path -AclObject $acl
}
function Test-EnumBlocked($root, $fakeHome) {
  # 注入自我檢查要在**受測 host 的 child 行程**裡跑。自檢跑在 parent、產品跑在 `$exe` child，
  # 兩者不保證是同一個 host（`-Shell powershell` 時 parent 仍可能是 pwsh），
  # token 與 provider 行為不能當成邏輯上相同。（合併前 Codex 審查指出。）
  (Invoke-Block ($script:m13ProbeTpl.Replace('<ROOT>', $root)) $fakeHome).Out
}

foreach ($case in @(@{ n='備份子樹'; where='bak' }, @{ n='live 子樹'; where='live' })) {
  $tag = "m13-$($case.where)"
  $h = New-FakeHome $tag; Add-ExistingInstall $h
  $r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
  Check "[M13][$($case.n)] 前置：1b 成功並印出 ts" ($r.Ok -and $ts) $r.Out
  $r = Invoke-Block $B1c $h
  Check "[M13][$($case.n)] 前置：1c 安裝成功" $r.Ok $r.Out

  $root = if ($case.where -eq 'bak') { "$h\.claude\skills-backup\超級模式.bak-$ts" }
          else                       { "$h\.claude\skills\超級模式" }
  $locked = New-LockedDir $root

  # 兩份快照都必須在 Deny **之前**取 —— Get-Snapshot 自己也是 -Recurse，之後同樣掃不動。
  $beforeSkills = Get-Snapshot "$h\.claude\skills"
  $beforeHome   = Get-Snapshot $h

  $denyRule = Set-DenyEnumerate $locked
  try {
    $probeOut = Test-EnumBlocked $root $h
    Check "[M13][$($case.n)] 前置：列舉真的失敗（在受測 host 內驗證注入生效）" ($probeOut -match 'ENUM=FAIL') "probe 輸出：$probeOut —— Deny ACE 沒咬到（檔案系統不支援 ACL？行程有備份權限？），不能給綠燈"
    $r = Invoke-Rollback $ts $h
  } finally {
    # 先還原權限，後面的 Get-Snapshot 與 $work 清理才掃得動
    Clear-DenyEnumerate $locked $denyRule
  }
  Check "[M13][$($case.n)] 列舉失敗 → 回滾中止" (-not $r.Ok) "竟然成功：$($r.Out)"
  # 這條才是重點。修正前也會非零（Remove-Item／Copy-Item 自己撞權限），
  # 但**那時 live 已經被刪了**，所以區辨力全在這一條，不在退出碼。
  Check "[M13][$($case.n)] 中止後 live 未變" ((Get-Snapshot "$h\.claude\skills") -eq $beforeSkills) 'live 被動過'
  # ⚠️ 契約講的是「**任何** mutation 之前中止」，不是「skill 樹未變」。
  # 產品在預掃之後還會改 hook 與 settings；只快照 skills 的話，把 hook mutation 搬到
  # 預掃之前仍會全綠 —— 那是合併前 Codex 審查抓到的 surviving mutant，`[M13c]` 就是它的牙齒測試。
  Check "[M13][$($case.n)] 中止後整個假家目錄未變（hook／settings 也在內）" ((Get-Snapshot $h) -eq $beforeHome) '假家目錄有東西被動過（skills 之外也要看）'
}

"`n[M13b] 變異注入：拿掉 Stop 後保護必須消失（證明 M13 的區辨力來自那一行）"
# M13 只證明「現在是 fail-closed」，不證明**是哪一行讓它 fail-closed**。
# 本案把區塊開頭的 Stop 改成 Continue、其餘完全不動：列舉錯誤退回非終止錯誤 →
# `$bad` 為 $null → 守衛不拋 → 走到 `Remove-Item -Recurse` → live 被動過。
# 沒有這一案，日後有人把那行刪掉時只會知道 M13 紅了，不會知道紅在哪裡。
$m13Anchor = "`$ErrorActionPreference = 'Stop'"
# 錨點必須**行首錨定**：區塊裡還有一句註解含同樣字面
#（`# 本區塊開頭的 $ErrorActionPreference = 'Stop' 讓真正的列舉失敗…直接拋出＝fail-closed。`），
# 用 `String.Replace` 會連註解一起改掉 —— 那就不是「其餘完全不動」的單點變異了。
# 這是散文含程式碼字面、被未錨定比對抓走的同一形狀（同 2026-08-10 那批的 `RESULT_CODE=`），
# 而且是本案的自我檢查先紅才發現的，不是事先想到的。
$m13Re   = [regex]('(?m)^' + [regex]::Escape($m13Anchor) + '$')
$m13Hits = $m13Re.Matches($Brb)
$m13Ok   = ($m13Hits.Count -eq 1) -and ($m13Hits[0].Index -eq 0)
$m13Idx  = if ($m13Hits.Count -ge 1) { $m13Hits[0].Index } else { 'n/a' }
Check '[M13b] 變異錨點唯一且在區塊開頭（否則本案等於沒測）' $m13Ok "命中 $($m13Hits.Count) 次、index=$m13Idx（預期 1 次、index 0）"
# 錨點失效時**刻意不跳過**後面兩案，改用未變異的區塊讓它們自然變紅：
# 案數必須釘死，少印一案是抓不到的假綠。
$m13Mut = if ($m13Ok) { "`$ErrorActionPreference = 'Continue'" + $Brb.Substring($m13Hits[0].Length) } else { $Brb }
$m13Diff = @(Compare-Object ($Brb -split "`n") ($m13Mut -split "`n")).Count
Check '[M13b] 變異確實注入且只動一行' (($m13Mut -ne $Brb) -and ($m13Diff -eq 2)) "差異行數=$m13Diff（預期 2：一去一回；0＝沒注入，>2＝動到不該動的行）"
$h = New-FakeHome 'm13b'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '[M13b] 前置：1b 成功並印出 ts' ($r.Ok -and $ts) $r.Out
$r = Invoke-Block $B1c $h
Check '[M13b] 前置：1c 安裝成功' $r.Ok $r.Out
# ⚠️ 鎖的是**備份**子樹，不是 live。鎖 live 的話，fail-open 之後的負向訊號要依賴
# `Remove-Item -Recurse` 對一棵**部分不可存取**的樹「刪掉一些才失敗」——那是 provider 語義，
# 日後若改成更早、更原子地拒絕就會誤紅。鎖備份則是：預掃 fail-open → 第一個 mutation
# 刪除一棵**完全可存取**的 live → 訊號穩定。（合併前 Codex 審查建議，已採納。）
$m13bLocked = New-LockedDir "$h\.claude\skills-backup\超級模式.bak-$ts"
$before = Get-Snapshot "$h\.claude\skills"
$denyRule = Set-DenyEnumerate $m13bLocked
try {
  $probeOut = Test-EnumBlocked "$h\.claude\skills-backup\超級模式.bak-$ts" $h
  Check '[M13b] 前置：列舉真的失敗（在受測 host 內驗證注入生效）' ($probeOut -match 'ENUM=FAIL') "probe 輸出：$probeOut —— Deny ACE 沒咬到，本案等於沒測"
  $r = Invoke-Block ($m13Mut.Replace($PLACEHOLDER, $ts)) $h
} finally {
  Clear-DenyEnumerate $m13bLocked $denyRule
}
# 只釘「live 被動過」：那正是 M13 主斷言的否命題。**不**額外釘退出碼——
# 錯誤是否終止會隨 host 版本而異，釘了只會製造平台雜訊（同 M13／POSIX 的教訓）。
Check '[M13b] 拿掉 Stop 後 live 確實被動過（保護來自該行）' ((Get-Snapshot "$h\.claude\skills") -ne $before) "live 未變（回滾 ok=$($r.Ok)）：本案已失去意義，M13 的區辨力來源需重新確認"

"`n[M13c] 變異注入：把一個 mutation 搬到預掃之前（證明 M13 的 oracle 夠寬）"
# 合併前 Codex 審查抓到的 surviving mutant：契約說的是「**任何** mutation 之前中止」，
# 但我原本只快照 `.claude\skills`。產品在預掃**之後**才改 hook 與 settings，
# 所以「把 hook mutation 搬到預掃前」這個違規，舊的窄 oracle 會全綠放行。
# 本案就是那條加寬的牙齒測試：注入一個預掃前的 hook mutation，然後同時檢查
# **窄 oracle 看不到**（證明缺口真實存在）與**寬 oracle 抓得到**（證明加寬有效）。
$m13cAnchor = "if (Test-Path -LiteralPath `$sbak -PathType Container) { Assert-NoReparseUnder 'skill 備份' `$sbak }"
# ⚠️ 注入行要帶一個**唯一標記**才數得準：產品本來就有
# `elseif (Get-Entry $hook) { Remove-Item -LiteralPath $hook -Force }`，
# 而它**包含**不帶標記的注入字串當子字串 —— 直接數會得到 2 次。
# 這是本批第三次撞上同一個「未錨定／子字串比對」的坑（前兩次：註解含 `$ErrorActionPreference = 'Stop'` 字面、
# 以及上一批散文含 `RESULT_CODE=`），三次都是自我檢查先紅才發現的。
$m13cMarker = '# M13C-PRE-SCAN-MUTATION'
$m13cInject = "if (Get-Entry `$hook) { Remove-Item -LiteralPath `$hook -Force } $m13cMarker"
$m13cHits = ([regex]::Matches($Brb, [regex]::Escape($m13cAnchor))).Count
$m13cOk   = ($m13cHits -eq 1)
Check '[M13c] 變異錨點唯一（否則本案等於沒測）' $m13cOk "錨點命中 $m13cHits 次（預期 1）—— 舊版文件沒有預掃，本案在反向驗證時本來就會紅"
$m13cMut = if ($m13cOk) { $Brb.Replace($m13cAnchor, $m13cInject + "`n" + $m13cAnchor) } else { $Brb }
$m13cAdded = (($m13cMut -split "`n").Count - ($Brb -split "`n").Count)
$m13cInjHits = ([regex]::Matches($m13cMut, [regex]::Escape($m13cMarker))).Count
Check '[M13c] 變異確實注入且只多一行' (($m13cMut -ne $Brb) -and ($m13cAdded -eq 1) -and ($m13cInjHits -eq 1)) "多出 $m13cAdded 行、注入標記出現 $m13cInjHits 次（預期 1／1）"
$h = New-FakeHome 'm13c'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
Check '[M13c] 前置：1b 成功並印出 ts' ($r.Ok -and $ts) $r.Out
$r = Invoke-Block $B1c $h
Check '[M13c] 前置：1c 安裝成功' $r.Ok $r.Out
$m13cRoot = "$h\.claude\skills-backup\超級模式.bak-$ts"
$m13cLocked = New-LockedDir $m13cRoot
$beforeSkills = Get-Snapshot "$h\.claude\skills"
$beforeHome   = Get-Snapshot $h
$denyRule = Set-DenyEnumerate $m13cLocked
try {
  $probeOut = Test-EnumBlocked $m13cRoot $h
  Check '[M13c] 前置：列舉真的失敗（在受測 host 內驗證注入生效）' ($probeOut -match 'ENUM=FAIL') "probe 輸出：$probeOut —— Deny ACE 沒咬到，本案等於沒測"
  $r = Invoke-Block ($m13cMut.Replace($PLACEHOLDER, $ts)) $h
} finally {
  Clear-DenyEnumerate $m13cLocked $denyRule
}
Check '[M13c] 回滾仍中止' (-not $r.Ok) "竟然成功：$($r.Out)"
# 這兩條要一起看才有意義：前者證明**缺口真實存在**（只看 skills 會放行違規），
# 後者證明**加寬確實抓得到**。少了前者，讀者無從判斷加寬有沒有買到東西。
Check '[M13c] 窄 oracle（只看 skills）看不到這個違規' ((Get-Snapshot "$h\.claude\skills") -eq $beforeSkills) 'skills 也變了，本案已無法示範窄 oracle 的盲點'
Check '[M13c] 寬 oracle（整個假家目錄）抓到預掃前的 mutation' ((Get-Snapshot $h) -ne $beforeHome) '寬 oracle 也沒抓到 —— 注入沒生效或 M13 的加寬無效'

"`n[C3] 對照組（確認上面的斷言不是永遠為真）"
$h = New-FakeHome 'c3'; Add-ExistingInstall $h
$r = Invoke-Block $B1b $h; $ts = Get-Ts $r.Out
$r = Invoke-Block $B1c $h
$r = Invoke-Rollback $ts $h
Check '正確 ts 的回滾必須成功（否則上面全是假通過）' $r.Ok $r.Out

} finally {
  Pop-Location
  # 只清理本次建立、且符合本前綴的路徑
  if ($work -match 'ai-install-harness-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $work)) {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Host "work 路徑不符預期前綴，不清理：$work"
  }
}

"`n========================================"
# 摘要行沿用 host **名稱**（不是解析後的絕對路徑）：交接文件與反向驗證都在比對這一行。
"$exeName  PASS=$script:pass  FAIL=$script:fail"
$ranChecks = $script:pass + $script:fail
if ($ranChecks -ne $EXPECTED_CHECKS) {
  "  STOP 案數不符：實跑 $ranChecks、預期 $EXPECTED_CHECKS —— 有案被刪除或跳過，或新增後忘了更新 EXPECTED_CHECKS"
  exit 1
}
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
