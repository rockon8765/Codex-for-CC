# codex-consult.ps1 -- super-mode section 3.5 advice gate (v3).
# Runs a read-only Codex second opinion. Codex writes nothing; it only reviews
# the evidence/plan you pass in. On success, writes a consult credential so the
# super-mode consult-gate allows change actions for ~20 minutes, and saves the
# full transcript to ~/.claude/super-mode-logs/codex_consult_<ts>.txt.
#
# Params:
#   -Dir         Codex working dir (project root, Windows path; WSL UNC not reachable -> feed evidence via the brief).
#   -PromptFile  Read the consult brief from a file. THE way to pass a brief --
#                write it to the session scratchpad (gate-exempt path), pass path.
#   -Prompt      DEPRECATED (stage 1: warns, still works; a later release errors).
#                Inline briefs containing ; | & trip the consult-gate's command
#                parsing and get blocked. Passing both -Prompt and -PromptFile is
#                now a hard error instead of silently preferring the file.
#   -NoCredential  Discussion-partner mode (outside super-mode): same read-only
#                consult, but do NOT mint the consult-gate credential.
#   -SchemaFile  Optional (T2b): JSON schema path; constrains Codex's final reply
#                shape via --output-schema. read-only + ephemeral unchanged. Fails
#                fast (before invoking codex) if the file is missing or invalid JSON.
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
  [string]$PromptFile,
  [switch]$NoCredential,
  [string]$SchemaFile   # 可選(T2b)：JSON schema 檔路徑；給了就讓 Codex 回覆符合此結構(--output-schema)，好機器驗收。只約束輸出形狀，不改 read-only/ephemeral。
)

$codexCmd = "C:\npm\codex.cmd"
# 測試接縫：讓整合測試能換掉 codex 本體。POSIX 兩支呼叫的是裸 `codex`(吃 PATH)，
# 本來就能用 stub 目錄攔截；Windows 這支寫死絕對路徑，沒有這個 override 就完全測不到
# 「codex 回了什麼 → 判準怎麼判 → 憑證寫不寫」這條新邏輯。
# ⚠️ 只換「執行哪支程式」，不改任何判準或鑄造規則；正式使用不需要設它。
if ($env:SUPER_MODE_CODEX_CMD) {
  if (-not (Test-Path -LiteralPath $env:SUPER_MODE_CODEX_CMD)) {
    throw "SUPER_MODE_CODEX_CMD 指向不存在的檔案: $($env:SUPER_MODE_CODEX_CMD)"
  }
  $codexCmd = (Resolve-Path -LiteralPath $env:SUPER_MODE_CODEX_CMD).Path
}

# $Dir / $SchemaFile 會拼進 cmd /c 字串執行 → 進 cmd 前必須擋注入面(fail-closed)。
# cmd 即使在雙引號內也會展開 %VAR%(! 可能延遲展開；& | < > ^ 為運算子)；合法 repo/schema 路徑不含這些字元。
function Assert-CmdSafePath([string]$value, [string]$name) {
  if ($value -match '[%!"&|<>^]') { throw ($name + ' 含 cmd 不安全字元(% ! " & | < > ^ 之一)，拒絕以防注入: ' + $value) }
}

# codex 輸出是 UTF-8：讓 PowerShell 正確解碼進 transcript
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}

function Read-TextSmart([string]$path) {
  # BOM 嗅探：UTF-16LE / UTF-8 BOM / 其餘一律當 UTF-8(Claude Write 工具與 bash 的產物)
  $b = [System.IO.File]::ReadAllBytes($path)
  if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2) }
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return [System.Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) }
  return [System.Text.Encoding]::UTF8.GetString($b)
}

# ── validator（憑證鑄造判準）─────────────────────────────────────────────────
# 判準是三平台共用的單一 node 模組 lib/consult-answer.js。這裡只負責「找到 node、
# 找到模組、確認它真的活著」——任何判準邏輯都不在這支裡（那正是要消除的副本）。
$validatorPath = Join-Path $PSScriptRoot "..\lib\consult-answer.js"

function Resolve-NodeExe {
  # 1) SUPER_MODE_NODE 若有設就必須有效——**不靜默退回 PATH**。設了卻壞掉是設定錯誤，
  #    默默改用別的 node 會讓使用者以為自己指定的那支在跑。
  if ($env:SUPER_MODE_NODE) {
    if (-not (Test-Path -LiteralPath $env:SUPER_MODE_NODE)) {
      throw "SUPER_MODE_NODE 指向不存在的檔案: $($env:SUPER_MODE_NODE)"
    }
    return (Resolve-Path -LiteralPath $env:SUPER_MODE_NODE).Path
  }
  # 2) PATH 上的 node。⚠️ gate hook 走的是 settings.json 裡的**絕對路徑**，所以
  #    「hook 正常但 caller 找不到 node」是真的會發生的組合 → 訊息要講清楚怎麼修。
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Invoke-Validator([string]$nodeExe, [string]$answerFile, [string[]]$extraArgs) {
  # 一律以 argv 呼叫（不拼字串、不過 cmd）——這裡沒有 cmd 注入面。
  $argv = @($validatorPath, "--answer-file", $answerFile) + $extraArgs
  $outFile = Join-Path $env:TEMP ("consult_v_out_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  $errFile2 = Join-Path $env:TEMP ("consult_v_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  try {
    $proc = Start-Process -FilePath $nodeExe -ArgumentList $argv -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput $outFile -RedirectStandardError $errFile2
    $so = if (Test-Path $outFile) { [System.IO.File]::ReadAllText($outFile) } else { "" }
    $se = if (Test-Path $errFile2) { [System.IO.File]::ReadAllText($errFile2) } else { "" }
    return @{ Code = $proc.ExitCode; Out = $so; Err = $se }
  } finally {
    Remove-Item -LiteralPath $outFile, $errFile2 -Force -ErrorAction SilentlyContinue
  }
}

function Test-ValidatorSentinel($r) {
  # ⚠️ 不可只看 exit 0：空模組、被截斷的檔、被 shim 掉的 node 都會自然 exit 0。
  #    成功的定義是「stdout 恰好一行且以 CONSULT-ANSWER-OK 開頭」。
  $lines = @($r.Out -split "`r?`n" | Where-Object { $_ -ne "" })
  return ($lines.Count -eq 1 -and $lines[0].StartsWith("CONSULT-ANSWER-OK"))
}

function Assert-ValidatorUsable([string]$nodeExe) {
  # preflight：在燒掉一次諮詢**之前**就確認判準跑得動，而且不是「永遠放行」或「永遠拒絕」。
  # 兩個探針缺一不可——只驗好樣本會放過 always-OK 的空模組，只驗壞樣本會放過 always-43。
  $good = Join-Path $env:TEMP ("consult_pf_g_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  $bad = Join-Path $env:TEMP ("consult_pf_b_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
  try {
    [System.IO.File]::WriteAllText($good, ("ALLOW: preflight" + "`n" + ("x" * 60)), (New-Object System.Text.UTF8Encoding $false))
    [System.IO.File]::WriteAllText($bad, "hi", (New-Object System.Text.UTF8Encoding $false))
    $rg = Invoke-Validator $nodeExe $good @()
    $rb = Invoke-Validator $nodeExe $bad @()
    if ($rg.Code -ne 0 -or -not (Test-ValidatorSentinel $rg)) {
      throw "好樣本沒通過（exit=$($rg.Code) stdout=$($rg.Out.Trim())）"
    }
    if ($rb.Code -ne 43) { throw "壞樣本沒被擋（exit=$($rb.Code)）—— 判準可能是空的或被替換" }
  } finally {
    Remove-Item -LiteralPath $good, $bad -Force -ErrorAction SilentlyContinue
  }
}

$nodeExe = Resolve-NodeExe
if (-not $nodeExe -or -not (Test-Path -LiteralPath $validatorPath)) {
  [Console]::Error.WriteLine("CONSULT_VALIDATOR_UNAVAILABLE: " +
    $(if (-not $nodeExe) { "找不到 node（PATH 上沒有，且未設 SUPER_MODE_NODE）。" }
      else { "找不到判準模組: $validatorPath。" }) +
    "未鑄造憑證，**既有憑證未變**。修法：把 node 加進 PATH，或設 SUPER_MODE_NODE 指向 node 執行檔" +
    "（gate hook 用的是 settings.json 裡的絕對路徑，所以 hook 正常不代表 caller 找得到 node）。")
  exit 45
}
try { Assert-ValidatorUsable $nodeExe }
catch {
  [Console]::Error.WriteLine("CONSULT_VALIDATOR_UNAVAILABLE: 判準模組 preflight 失敗 -- $_ 。" +
    "未鑄造憑證，**既有憑證未變**。")
  exit 45
}

# C5 stage 1：介面收斂取代散文規則。舊行為是兩個都給就靜默採用 -PromptFile(呼叫端無從
# 察覺自己的 inline 被丟掉) → 改 fail-fast。inline 單獨使用仍可跑，但出 deprecation 警告。
if ($PromptFile -and $Prompt) {
  throw "同時給了 -Prompt 與 -PromptFile：語意不明確(舊行為靜默採用 -PromptFile)，拒絕執行。請只給 -PromptFile。"
}
if ($PromptFile)   { $p = Read-TextSmart $PromptFile }
elseif ($Prompt)   {
  $p = $Prompt
  # 用 [Console]::Error 而非 Write-Warning：實測 powershell.exe -File 跨 process 時 warning stream
  # 會落到 OS stdout(污染 -Quiet 摘要與 --output-schema 的 stdout 解析)，且 $WarningPreference='Stop'
  # 會把它變成 ActionPreferenceStopException —— staged deprecation 的「仍可跑」承諾就破功了。
  [Console]::Error.WriteLine("[DEPRECATED] -Prompt(inline) 將於未來版本改為錯誤。inline 簡報含 ; | & 等標點會被 consult-gate 的指令解析誤判成串接指令而擋下。請改用 -PromptFile：用 Write 工具把簡報寫進 scratchpad(gate 豁免路徑)再傳路徑。")
}
else               { throw "Provide -PromptFile (preferred) or -Prompt (deprecated)." }
if ([string]::IsNullOrWhiteSpace($p)) { throw "Prompt is empty." }

# T2b：給了 -SchemaFile 就轉絕對路徑並在啟動 Codex 前先驗證可解析(fail-fast)。只約束輸出形狀，不改沙箱(read-only/ephemeral 不變)。
$schemaArg = ""
if ($SchemaFile) {
  if (-not (Test-Path -LiteralPath $SchemaFile)) { throw "SchemaFile not found: $SchemaFile" }
  $SchemaFile = (Resolve-Path -LiteralPath $SchemaFile).Path   # consult 有 -C 換工作根，必須絕對路徑
  Assert-CmdSafePath $SchemaFile 'SchemaFile'                  # 進 cmd /c 前擋注入字元
  # ⚠️ 2026-08-18：這裡原本用 ConvertFrom-Json，而 POSIX 兩支用的是 node 的 JSON.parse。
  #    那不是同一個 JSON 方言（pwsh 7.x 接受註解與 trailing comma、WinPS 5.1 拒；兩者都接受
  #    NaN 與 01，node 全拒）⇒ 同一份 schema 檔會在不同平台一邊過一邊不過。改成三平台
  #    都走 node，JSON 的判準才只有一個。
  $schemaCheck = & $nodeExe -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' $SchemaFile 2>&1
  if ($LASTEXITCODE -ne 0) { throw "SchemaFile is not valid JSON (strict, node): $SchemaFile -- $schemaCheck" }
  $schemaArg = '--output-schema "{4}" '   # 併入 $inner 最高編號 {4}(不動 codex{0}/dir{1}/brief{2}/stderr{3})
}

$logDir = Join-Path $env:USERPROFILE ".claude\super-mode-logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$log = Join-Path $logDir ("codex_consult_{0}_{1}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"), ([guid]::NewGuid().ToString('N').Substring(0, 6)))  # 去重後綴防同秒碰撞

$Dir = $Dir.TrimEnd('\')
if ($Dir -match '^[A-Za-z]:$') { $Dir += '\' }
Assert-CmdSafePath $Dir 'Dir'   # $Dir 也進 cmd /c 字串(既有注入面)，一併 fail-closed

# 正規化落地 UTF-8(無 BOM)暫存簡報，cmd `<` 重導向 → 位元組直達 codex
$brief = Join-Path $env:TEMP ("codex_brief_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
$errFile = Join-Path $env:TEMP ("codex_err_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
# codex 的 **stdout 專用**副本，餵給判準用。⚠️ 不能拿 $log 代替：log 事後會被接上
# "===== STDERR =====" 區段，把 stderr 一起送進判準會改變裁決（例如 schema 模式的 JSON 解析）。
$answerFile = Join-Path $env:TEMP ("codex_answer_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
[System.IO.File]::WriteAllText($brief, $p, (New-Object System.Text.UTF8Encoding $false))
try {
  # stderr 導到獨立檔(編號佔位符 {3})；不可用 2>&1(會回灌 stdout)。$LASTEXITCODE 仍是 codex 退出碼。
  # 5.2：--ephemeral 讓短命唯讀諮詢不落地 Codex session 檔(下游不 resume 此 session，留著純浪費)
  # memories 隔離(2026-07-10)：Codex 全域 config 開了 [memories]，會把過往記憶注入 session。
  # consult 必須是「獨立第二意見」→ use_memories=false 斷讀入(否則反方審查被過往記憶污染)、
  # generate_memories=false 斷寫出(否則簡報進全域 memories，下次 consult 又讀到，形成自我強化閉環)。
  # 0.144.1 實測：加這兩個 -c 後 MEMORIES: NO_MEMORIES_VISIBLE、exit 0、MCP 工具面/沙箱邊界皆不受影響。
  $inner = ('"{0}" exec --sandbox read-only --ephemeral --skip-git-repo-check -c memories.use_memories=false -c memories.generate_memories=false -C "{1}" ' + $schemaArg + '< "{2}" 2> "{3}"') -f $codexCmd, $Dir, $brief, $errFile, $SchemaFile
  $answerLines = New-Object System.Collections.Generic.List[string]
  & cmd.exe /d /s /c $inner | ForEach-Object { $_; $answerLines.Add([string]$_); Add-Content -LiteralPath $log -Value $_ -Encoding utf8 }
  $code = $LASTEXITCODE
  [System.IO.File]::WriteAllText($answerFile, ($answerLines -join "`n"), (New-Object System.Text.UTF8Encoding $false))
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
  # ⚠️ 2026-08-18：codex exit 0 **不再等於**可以鑄證。舊行為讓 codex 回空字串或幾個字
  #    也照樣解鎖 gate 20 分鐘，而那種情況通常正代表諮詢其實沒送到。
  #    判準本體在三平台共用的 lib/consult-answer.js，這裡只負責叫它並看結果。
  $vArgs = @()
  if ($NoCredential) { $vArgs += "--no-credential" }
  if ($SchemaFile) { $vArgs += "--schema" }
  $v = Invoke-Validator $nodeExe $answerFile $vArgs
  Remove-Item -LiteralPath $answerFile -Force -ErrorAction SilentlyContinue

  if ($v.Code -ne 0 -or -not (Test-ValidatorSentinel $v)) {
    if ($v.Code -eq 43) {
      [Console]::Error.WriteLine($v.Err.Trim() + " transcript: $log")
      [Console]::Error.WriteLine("（未鑄造新憑證；**既有憑證（若有）未被移除**，其原本的有效期不受本次影響。）")
      exit 43
    }
    # exit 0 但沒有哨兵 = 判準沒真的跑（空模組／被截斷／被 shim 掉的 node 都會自然 exit 0）。
    [Console]::Error.WriteLine("CONSULT_VALIDATOR_UNAVAILABLE: 判準回了 exit $($v.Code) 但沒有預期的成功哨兵" +
      "（stdout='$($v.Out.Trim())'）。未鑄造憑證，**既有憑證未變**。transcript: $log")
    exit 45
  }

  if ($NoCredential) {
    # Discussion-partner mode: no credential, so a casual consult can never
    # unlock super-mode gated actions in a concurrent session on this repo.
    Write-Output "consult OK -- no credential (discussion mode); transcript: $log"
  } else {
    $token = Join-Path $env:USERPROFILE ".claude\.super-mode-consult-ok"
    # 憑證決策範圍：綁定本次諮詢的 repo(-Dir)。hook 會比對後續動作路徑是否在此 repo 下。
    $cred = @{ repo = $Dir; ts = (Get-Date -Format o) } | ConvertTo-Json -Compress
    # 原子寫入：同目錄暫存檔 → 寫入 → 讀回驗證 → rename 才是 commit point。
    # ⚠️ 封存版(380462f)是「直接寫目標檔、寫完才讀回」，讀回失敗時 exit 44 但**舊憑證原封不動**，
    #    訊息卻說「未取得憑證」——它自己的註解點名了這個風險卻沒處理。這裡改掉。
    # ⚠️ 失敗時**刻意不刪除舊憑證**：那是另一個 session 可能還在用的合法收據，
    #    刪它等於引進撤銷語義（那是「動作授權」那批的事）。改成訊息誠實交代。
    $tokenTmp = $token + ".tmp-" + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
      [System.IO.File]::WriteAllText($tokenTmp, $cred, (New-Object System.Text.UTF8Encoding $false))
      $readBack = [System.IO.File]::ReadAllText($tokenTmp)
      if ($readBack -ne $cred) { throw "暫存檔讀回內容與寫入不符" }
      # 同目錄單一 rename 取代（MoveFileEx + REPLACE_EXISTING）。內容在成為目標檔之前就已寫完
      # 並讀回驗證過，所以不會有「半寫的憑證被 gate 讀到」。
      # ⚠️ 不用 [System.IO.File]::Replace()：目標不存在時它在 .NET Framework／.NET 兩邊
      #    丟的例外型別不一致（2026-08-18 實測 WinPS 走到 ArgumentException 而非
      #    FileNotFoundException，害我為後者寫的 catch 完全沒接到）。Move-Item -Force
      #    兩種情況（目標存在／不存在）都走同一條路，少一個分歧面。
      # ⚠️ 措辭克制：這是「單一 rename」不是「跨系統的原子性保證」。
      Move-Item -LiteralPath $tokenTmp -Destination $token -Force -ErrorAction Stop
    } catch {
      Remove-Item -LiteralPath $tokenTmp -Force -ErrorAction SilentlyContinue
      [Console]::Error.WriteLine("CONSULT_TOKEN_WRITE_FAILED: 諮詢完成且回覆合格，但憑證寫入失敗: $_ 。" +
        "**既有憑證（若有）未被移除**。請檢查 $token 的權限後重跑。transcript: $log")
      exit 44
    }
    $verdictNote = ($v.Out.Trim() -split '\s+')[-1]
    if ($verdictNote -ceq 'BLOCK') {
      Write-Output "consult OK -- credential written, but Codex 裁決為 BLOCK：依 §3.5 不得執行原動作，先向使用者回報。transcript: $log"
    } else {
      Write-Output "consult OK -- credential written; transcript: $log"
    }
  }
} else {
  Remove-Item -LiteralPath $answerFile -Force -ErrorAction SilentlyContinue
  # 配額/認證類失敗 → 明確標記 + 專屬 exit 42，讓上層 fail-fast、別在額度最稀缺時空轉重試
  $tail = ""
  try { $tail = (Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue) } catch {}
  if ($tail -match '(?i)usage limit|rate limit|\b429\b|quota|not logged in|unauthorized|\b401\b') {
    Write-Warning "CONSULT_UNAVAILABLE_QUOTA: codex 配額/認證失敗 (exit $code)。停止重試諮詢，向使用者回報；經同意可跑 super-mode.ps1 -Off 降級為一般模式。transcript: $log"
    exit 42
  }
  Write-Warning "codex-consult: codex exited [$code] -- no credential written. transcript: $log"
}
exit $code
