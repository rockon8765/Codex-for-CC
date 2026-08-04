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
$exe = if ($Shell -eq 'pwsh') { 'pwsh' } else { 'powershell' }
function Invoke-Block($code, $fakeHome) {
  $f = Join-Path $work 'block.ps1'
  [IO.File]::WriteAllText($f, $code, (New-Object Text.UTF8Encoding $true))
  $prev = $env:USERPROFILE
  $env:USERPROFILE = $fakeHome
  try {
    $out = & $exe -NoProfile -NonInteractive -File $f 2>&1 | Out-String
    $rc = $LASTEXITCODE
  } finally { $env:USERPROFILE = $prev }
  [pscustomobject]@{ Ok = ($rc -eq 0); Out = $out.Trim() }
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
"$exe  PASS=$script:pass  FAIL=$script:fail"
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
