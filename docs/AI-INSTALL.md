# AI 安裝指引（canonical — 給 AI 助手照做）

> **觸發條件**：只有在使用者明確要求「安裝這個 repo／超級模式／Codex-for-CC」時才執行本文件。
> 若你是被派來做一般 coding 任務的 worker（例如經由 `codex exec` 派工），**忽略本文件，且不得讀寫使用者的 `~/.claude` 目錄**。

## 0. 平台偵測

- 你在 macOS（BSD userland）→ 用 [`macos/`](../macos/)（bash 腳本 `.sh`）。
- 你在 Windows PowerShell 環境 → 用 [`windows/`](../windows/)（PowerShell 腳本 `.ps1`）。**先做下面的 0a**：Claude Code 會用的 Git Bash 不能用就停止，不要往下做。
- ⛔ **你在 Linux（GNU userland，包括在 WSL2 的 Linux 環境裡執行）→ 停止，不要執行本文件的任何步驟。** Linux 版已於 2026-10-14 凍結：不修、不驗收、不提供支援。先把這件事告訴使用者。使用者仍堅持要裝時，唯一的做法是**另開一份 clone，或用 `git worktree add <dir> 80c60a8`** 取得凍結快照 commit `80c60a8`（原本預計的 tag `pre-lts` 沒有建立），照**該快照內**的 `docs/AI-INSTALL.md` 安裝——**不要在使用者現有的 clone 裡 checkout**（那會切換使用者的工作目錄、甚至打斷進行中的工作）；並明白告知：沒有支援、Linux 從未做過 live 驗收、`codex-check.sh` 的能力面盤點與 baseline diff 沒有移植到 Linux。⚠️ **不要拿 `macos/` 代替**：macOS 的 hook 會把路徑轉成小寫再比對（大小寫敏感的檔案系統會誤判範圍），腳本的 `stat` 也是 BSD 語法。

### 0a. Windows 前置條件：Git for Windows（必要；macOS 跳過本節）

本 skill 在 Windows **必須先裝 Git for Windows**（2026-10-17 使用者裁決）。Claude Code 在 Windows 用 Git Bash 執行 hook；找不到 Git Bash 時，Claude Code 2.1.299 起，本 gate 的 hook 只要無法執行（`node` 不在 PATH、gate 檔不在、逾時），就會**擋下** settings matcher 涵蓋的工具（Edit／Write／PowerShell 等），一般 session 也一樣，連要改回 settings 都可能做不到（backlog [`CC-NOBASH-FAILCLOSED`](backlog.md#CC-NOBASH-FAILCLOSED)）。macOS 不受影響。

在 repo 根目錄、**在 Claude Code 裡**跑下面這段（`~/.claude/settings.json` 的 `env` 只有在 Claude Code 裡才會帶進子行程）。它分兩段：

1. **找**：照 Claude Code 自己的找法（2.1.301 讀碼）找出「它會用的那一個」：`CLAUDE_CODE_GIT_BASH_PATH`（檔名要是 `bash.exe`／`sh.exe`／`bash`／`sh`，且路徑存在）→ `C:\Program Files\Git\bin\bash.exe` → `C:\Program Files (x86)\Git\bin\bash.exe` → `where.exe git` 第一個合格結果往上兩層的 `bin\bash.exe`。**PATH 上的 `bash.exe` 一律不算**。
2. **驗**：對那一個實際檢查——必須是**檔案**（不是目錄）；不能是 WSL 的位置（`System32`、`WindowsApps` 的 `bash.exe`，認得出來就不執行，免得啟動 WSL）；實際執行 `-c "/usr/bin/uname -s"`（15 秒逾時）要成功，而且輸出是 `MINGW64_NT-…`／`MSYS_NT-…` 這類 Git for Windows（MSYS2）的結果。不合格時**不改試下一個**：Claude Code 不會改試，它就是會用那一個。

另外，Claude Code 判斷「`where.exe` 找到的 git 在不在目前目錄底下」之前會先 realpath。這段不重做 realpath，所以那個 git 的路徑或目前目錄只要經過 junction／symlink 等 reparse point，就判為**無法判定**（`GIT_BASH_UNDECIDABLE`）並停止，請使用者改設 `CLAUDE_CODE_GIT_BASH_PATH`。

**成功條件（兩個都要）：這段跑完沒有以錯誤結束，而且輸出裡恰好一行 `GIT_BASH_OK path=…`。**

- 成功 → 繼續步驟 1。
- 其他任何結果（`GIT_BASH_MISSING`／`GIT_BASH_INVALID`／`GIT_BASH_UNDECIDABLE`、其他錯誤、沒有輸出、`GIT_BASH_OK` 不只一行）→ **停止，不要執行本文件任何後續步驟**，把訊息原樣轉告使用者。這是 **fail-closed**，與步驟 4「Codex 不可用就跳過」的 fail-open **刻意相反**。
- 不要代為安裝 Git（安裝程式可能要系統管理員權限，由使用者自己裝），也不要拿 WSL 的 `bash.exe` 湊數。使用者裝好或修好 Git、**完全結束並重開 Claude Code**（它每個 host 只找一次 Git Bash 並快取；Desktop 要結束整個 app）之後，從本節重跑。
- 這台機器若**已經裝過**本 skill：補裝 Git 之前，gate 一失敗就會擋工具。要先停用，照文末「解除安裝」第 1、2 步只移除 settings 那一筆、開新 session。

> ⚠️ **驗證範圍**：本節的判斷邏輯以測試臺模擬驗證（[`tests/ai-install/run-windows.ps1`](../tests/ai-install/run-windows.ps1) 的 `[G]` 節：當場編出的假 `bash.exe`、改寫寫死的兩個位置、每案明設 `PATH`／`CLAUDE_CODE_GIT_BASH_PATH`／目前目錄）。Claude Code 2.1.299「沒有 Git Bash 就擋下」本身**未 live 重現**（維護者只有一台裝了 Git 的 Windows）。找法是照抄 2.1.301 的讀碼，上游改版就可能分歧（列入上游漂移稽核的檢查項）。

```powershell
# 步驟 0a（Windows）：Claude Code 會用哪一個 Git Bash？那一個真的能用嗎？
# (A) 找：照 Claude Code 自己的找法（2.1.301 讀碼）找出「它會用的那一個」。
# (B) 驗：對那一個實際檢查（是檔案、不是 WSL 的位置、實際執行回 MINGW／MSYS）。不合格不改試下一個——Claude Code 也不會改試。
# 成功只印一行 GIT_BASH_OK path=<路徑>；其他結果一律 throw（不用 exit：貼進使用者自己的終端機時，exit 會把視窗關掉）。
# 刻意不設 $ErrorActionPreference = 'Stop'：5.1 會把 where.exe 寫到 stderr 的「找不到」包成錯誤而中止整段。
function Test-Exists($p) { try { [bool](Test-Path -LiteralPath $p -ErrorAction Stop) } catch { $false } }
function Get-Entry0a($p) { try { Get-Item -LiteralPath $p -Force -ErrorAction Stop } catch { $null } }
# 路徑本身或任一上層是 reparse point（junction／symlink 等）就回傳 true。
function Test-ReparseChain($p) {
  $q = [IO.Path]::GetFullPath($p)
  while ($q) {
    $e = Get-Entry0a $q
    if ($null -ne $e -and (($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return $true }
    $up = [IO.Path]::GetDirectoryName($q)
    if (-not $up -or $up -eq $q) { break }
    $q = $up
  }
  return $false
}
function Find-ClaudeGitBash {
  # (1) CLAUDE_CODE_GIT_BASH_PATH：檔名必須是 bash.exe／sh.exe／bash／sh 且路徑存在（Claude Code 用 existsSync，目錄也算存在）；
  #     不合格時 Claude Code 只警告、改走自動偵測。
  $p = $env:CLAUDE_CODE_GIT_BASH_PATH
  if ($p) {
    $leaf = ($p.TrimEnd('\', '/') -replace '^.*[\\/]', '').ToLowerInvariant()
    if ((@('bash.exe', 'sh.exe', 'bash', 'sh') -contains $leaf) -and (Test-Exists $p)) { return $p }
    Write-Warning "CLAUDE_CODE_GIT_BASH_PATH=${p} 不可用（不存在或不是 bash／sh），Claude Code 會改走自動偵測"
  }
  # (2) Claude Code 寫死的兩個位置（字面，不看 $env:ProgramFiles）
  foreach ($c in @('C:\Program Files\Git\bin\bash.exe', 'C:\Program Files (x86)\Git\bin\bash.exe')) {
    if (Test-Exists $c) { return $c }
  }
  # (3) where.exe git 的第一個合格結果（存在、不在目前目錄底下、副檔名 .com/.exe/.bat/.cmd），往上兩層的 bin\bash.exe。
  #     Claude Code 只看第一個合格的 git；任何一步都不看 PATH 上的 bash（System32、WindowsApps 的 bash.exe 是 WSL）。
  $sys = if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' }
  $cwdFull = [IO.Path]::GetFullPath((Get-Location).ProviderPath)
  $cwd = $cwdFull.TrimEnd('\')
  $hits = @(& (Join-Path $sys 'System32\where.exe') git 2>$null)
  foreach ($g in $hits) {
    if (-not $g -or -not (Test-Exists $g)) { continue }
    # Claude Code 比對「在不在目前目錄底下」之前會先 realpath。這裡不重做 realpath：
    # 兩邊任一經過 reparse point 就判為無法判定（寧可停下，也不要猜錯 Claude Code 會用哪一個）。
    if ((Test-ReparseChain $g) -or (Test-ReparseChain $cwdFull)) {
      throw ("GIT_BASH_UNDECIDABLE：where.exe 找到的 git（${g}）或目前目錄（${cwdFull}）經過 junction／symlink 等 reparse point，" +
             "無法可靠判定 Claude Code 會用哪一個 Git Bash，停止安裝（本文件後續步驟都不要做）。`n" +
             "請使用者把 CLAUDE_CODE_GIT_BASH_PATH 設成 Git for Windows 的 bash.exe 完整路徑（例如 ~/.claude/settings.json 的 env），" +
             "完全結束並重開 Claude Code 後，在 Claude Code 裡重跑本步驟。")
    }
    $dir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($g)).TrimEnd('\')
    if ($dir -ieq $cwd -or $dir.StartsWith($cwd + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
    $ext = [IO.Path]::GetExtension($g.TrimEnd('.', ' ')).ToLowerInvariant()
    if (@('.com', '.exe', '.bat', '.cmd') -notcontains $ext) { continue }
    $b = [IO.Path]::GetFullPath([IO.Path]::Combine($g, '..', '..', 'bin', 'bash.exe'))
    if (Test-Exists $b) { return $b }
    return $null
  }
  return $null
}
# (B) 驗 Claude Code 會用的那一個：可用就回傳 null，否則回傳不合格的原因。
function Test-GitBashUsable($bash) {
  $e = Get-Entry0a $bash
  if ($null -eq $e) { return '讀不到這個路徑' }
  if ($e.PSIsContainer) { return '是目錄，不是可執行檔' }
  $full = [IO.Path]::GetFullPath($bash)
  # WSL 的 bash.exe（System32／SysWOW64／Sysnative、WindowsApps 的執行別名）：認得出來就不執行（執行會啟動 WSL）。
  if ($full -match '\\WindowsApps\\' -or [IO.Path]::GetDirectoryName($full) -match '\\(System32|SysWOW64|Sysnative)$') {
    return '是 WSL 的 bash.exe（System32／WindowsApps），不是 Git Bash'
  }
  # 實際執行一次：Git for Windows（MSYS2）的 uname -s 是 MINGW64_NT-…／MSYS_NT-… 這類；WSL 是 Linux、Cygwin 是 CYGWIN_NT-…。
  # 用絕對路徑 /usr/bin/uname：直接指向 usr\bin\bash.exe 時，PATH 不一定含 /usr/bin。
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $full
  $psi.Arguments = '-c "/usr/bin/uname -s"'
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  try { $proc = [System.Diagnostics.Process]::Start($psi) } catch { return "無法執行（$($_.Exception.Message)）" }
  try {
    $proc.StandardInput.Close()
    $so = $proc.StandardOutput.ReadToEndAsync()
    $null = $proc.StandardError.ReadToEndAsync()   # 一併讀掉，避免 stderr 塞滿管線而卡住
    if (-not $proc.WaitForExit(15000)) {
      try { $proc.Kill() } catch {}
      return '執行 15 秒仍未結束（逾時）'
    }
    if (-not $so.Wait(5000)) { return '讀不到執行輸出' }
    $rc = $proc.ExitCode
    $uname = $so.Result.Trim()
  } finally { $proc.Dispose() }
  if ($rc -ne 0 -or $uname -cnotmatch '\A(MINGW32|MINGW64|MSYS|UCRT64|CLANG32|CLANG64|CLANGARM64)_NT-\S+\z') {
    return "執行 /usr/bin/uname -s 的結果不是 Git for Windows（MINGW／MSYS）：退出碼=${rc}、輸出=[${uname}]"
  }
  return $null
}
$gitBash = Find-ClaudeGitBash
if (-not $gitBash) {
  throw ("GIT_BASH_MISSING：找不到 Claude Code 會用的 Git Bash，停止安裝（本文件後續步驟都不要做）。`n" +
         "本 skill 在 Windows 必須先裝 Git for Windows：沒有 Git Bash 時，Claude Code 2.1.299 起 gate hook 一旦無法執行，就會擋下 Edit／Write／PowerShell 等工具，連一般 session 也會被卡住。`n" +
         "請使用者：(1) 安裝 Git for Windows（https://git-scm.com/downloads/win ，或 winget install --id Git.Git -e --source winget），用預設安裝位置；" +
         "(2) 完全結束並重開 Claude Code（Desktop 要結束整個 app；它只在啟動時找一次 Git Bash）；(3) 在 Claude Code 裡重跑本步驟。`n" +
         "裝在其他位置：把 CLAUDE_CODE_GIT_BASH_PATH 設成 bash.exe 的完整路徑（例如 ~/.claude/settings.json 的 env），重開 Claude Code 後在 Claude Code 裡重跑本步驟。`n" +
         "C:\Windows\System32\bash.exe 與 WindowsApps\bash.exe 是 WSL，不算 Git Bash。")
}
$why = Test-GitBashUsable $gitBash
if ($why) {
  throw ("GIT_BASH_INVALID：Claude Code 會用的 Git Bash 是 ${gitBash}，但它${why}，停止安裝（本文件後續步驟都不要做）。`n" +
         "Claude Code 不會改試別的位置，它就是會用這一個。請使用者：(1) 若設了 CLAUDE_CODE_GIT_BASH_PATH，改成 Git for Windows 的 bash.exe（例如 C:\Program Files\Git\bin\bash.exe）或把它移除；" +
         "(2) 否則修復或重新安裝 Git for Windows（預設安裝位置）；(3) 完全結束並重開 Claude Code 後，在 Claude Code 裡重跑本步驟。")
}
"GIT_BASH_OK path=$gitBash"
```

> ℹ️ **個人工具（2026-10-19 起；LTS 已停止）**：不提供支援、不做准入，見 [README](../README.md) 頂端說明。

以下每步先列 macOS 指令、再列 Windows 對應。（凍結前本段另有「Linux 照 macOS 指令做」的說明，已隨 Linux 凍結移除。）

> ℹ️ **`linux.yml`（凍結快照 CI）**：GitHub Actions 的 `ubuntu-latest` 仍會跑凍結的 `linux/` 樹與頂層共用測試（`tests/*.test.js` 等），
> 它的綠燈不構成任何平台的支援宣稱，也不代表本文件適用於 Linux。

## 1. 安裝 skill 與 hook（先驗證 → 先備份 → 安裝，失敗可回滾）

> ⚠️ **不要直接覆蓋既有的 live hook 再測。** 若新版有問題，你會在驗證前就毀掉一個原本可用的 hook（且無回滾）。照「先驗證 repo 版本 → 備份既有 live → 安裝 → 驗證（步驟 3）→ 失敗回滾」的順序做。

**1a. 先在 repo 版本上驗證（還沒碰 `~/.claude`）**

macOS:
```bash
node "macos/skills/超級模式/tests/run-gate-tests.js"               # 這裡就 FAIL → repo 版本本身有問題，別安裝，回報使用者
node "macos/skills/超級模式/tests/matcher-contract.test.js" --repo # hook 的工具清單 vs settings matcher 是否一致
bash "macos/skills/超級模式/tests/exit-code-contract.smoke.sh"     # consult 的退出碼契約(42/46/原樣傳回)與配額判準
bash "macos/skills/超級模式/tests/fault-injection.smoke.sh"        # cat/rm/mktemp 故障注入 ＋ 三個 mutant（上一支沒刺激到的三條路）
bash "macos/skills/超級模式/tests/off-cleanup.tests.sh"            # super-mode off 只清頂層白名單逐字稿；暫存 HOME，不碰真的 ~/.claude
bash "macos/skills/超級模式/tests/project-root-marker.tests.sh"    # .codex-project-root ⇒ 單次 project_root_markers 覆寫、-C 不變；stub codex，暫存 HOME
node "tests/no-multibyte-varref.test.js"                           # 禁止 `$var` 緊接多位元組字元（部分 locale 下 bash 會併進變數名）
```
Windows:
```powershell
node ".\windows\skills\超級模式\tests\run-gate-tests.js"               # 這裡就 FAIL → 別安裝
node ".\windows\skills\超級模式\tests\matcher-contract.test.js" --repo # hook 的工具清單 vs settings matcher 是否一致
& ".\windows\skills\超級模式\tests\run-windows-suite.ps1" -Mode repo   # 全部 Windows 測試的單一入口；最後要看到 SUITE_RESULT=OK
#   （已含 tests\no-multibyte-varref.test.js：禁止 $var 緊接多位元組字元）
#   （已含 project-root-marker.tests.ps1：.codex-project-root ⇒ 單次 project_root_markers 覆寫、-C 不變；stub codex，暫存 USERPROFILE）
```

> ℹ️ **`run-windows-suite.ps1` 約需 6 分鐘**（含 codex-check 的 pwsh／5.1 兩條腿，各約 2 分鐘）。
> **工具 timeout 請給 ≥ 600000ms，或改成背景執行**，否則會在跑完前被工具中斷（步驟 3 的 `-Mode live` 同樣適用）。它用**顯式 manifest**
> 逐支開新 process，並檢查每支的**成功 marker**——只看 exit code 會被「空輸出但 exit 0」騙過。
> 它同時涵蓋 pwsh 7 與 WinPS 5.1 兩個 host。

> ℹ️ **`--repo` 不是可選的。** 它明確指定「驗與該檔相鄰的 `settings.snippet.json` ＋ hook」，
> 而這一步要驗的就是 repo 版本。不給旗標會走已淘汰的自動判斷並印 deprecation 警告；
> 步驟 3 用的是 `--live`。兩者都會**印出實際受驗的兩條路徑**，請核對它們是你以為的那一對。

**1b. 備份既有 live（若存在）——記住印出的時間戳 `ts`，回滾要用**

> ⚠️ **備份要放在 `~/.claude/skills/` 外面**（本文用 `~/.claude/skills-backup/`）。
> 備份若留在 `~/.claude/skills/` 底下，Claude Code 的 skill loader 會把它**當成另一個 skill
> 註冊**——名稱與 description 幾乎相同，會干擾 skill 選擇。（2026-07-27 實際踩過。）

備份三個東西：**hook、skill、settings 檔**。settings 也要備，因為步驟 2 會改它——不備的話
回滾只能還原 skill/hook，settings 卻停在新版，變成「舊 hook + 新 matcher」的混版。

> **每個元件都會留下「備份」或「`.absent` 標記」其中之一**（`.absent` = 安裝前本來就沒有這個東西）。
> 回滾靠這個分辨「還原舊版」與「刪掉全新安裝」，**不需要你記或填任何布林值**。
>
> **這段是 fail-fast 的**：任何一步失敗就中止，不會印出 `ts`。所以「有印出 `ts`」才等於
> 「三個備份都確實完成」。skill 的備份會與 live 做逐檔比對，避免部分複製被當成完整備份。
>
> **偵測得到的 link 一律中止**，不會嘗試備份；skill 目錄「底下」的也一樣中止。
> 理由：型別檢查會跟隨有效的 link，備走的是「別處的內容」，而複製會把 link
> **實體化成普通檔案／目錄**，回滾時就用那個普通版本蓋回去——等於在你不知情下改掉佈局，
> 且原本的連結拓撲永久消失。
>
> **各平台實際攔得到什麼（不要當成一致）**：
>
> | | Windows | macOS／Linux |
> |---|---|---|
> | symlink | ✅ 有效與斷掉的 junction 已實測；**斷掉的 symlink 未驗證**（見下方註解） | ✅ 有效與斷掉皆已實測 |
> | junction／NTFS mount point | ✅（都帶 `ReparsePoint` 屬性）| 不適用 |
> | **bind mount／掛載點** | ✅（同上；1b、1c 的第一個 mutation 前、回滾的刪除前各掃一次）。NTFS 掛載資料夾本身**未 live 實測**（建立要系統管理員權限），由 junction 案覆蓋同一個屬性（推論） | ⚠️ macOS：以裝置號（st_dev）偵測，1b、1c 的第一個 mutation 前、回滾的 `rm -rf` 前各一次（1b 之後才掛上的也算）。測試臺以假 `stat` 驗控制流；**2026-10-18 已在 macOS 真機驗證**（hdiutil 拋棄式 APFS image：根掛載、子樹掛載、1b／1c 之後才掛上，都在動 live 前中止、掛載內資料保留）。同裝置號的掛載（Linux bind mount）偵測不到 |
>
> ⚠️ **macOS 的掛載點守衛（2026-10-17 加入，F4 `MOUNT-RMRF`）**：skill 樹底下（或 skill 根目錄本身）
> 有掛載點時，1b、1c、回滾都會在動 live 之前中止，訊息含「掛載點」與「（live 未變更）」——遇到就先卸載再重跑。
> 驗證：測試臺 `run-posix.sh` 以假 `stat` 驗控制流；2026-10-18 另在 macOS 真機（macOS 27.0.1、arm64、`/bin/bash` 3.2、
> 只有內建的 BSD `stat`）以 hdiutil 拋棄式 APFS image 驗證：掛載點的 st_dev 確實與上一層不同；1b 時已掛載、
> 1b 之後才掛上（1c 中止）、1c 之後才掛上（回滾中止）、skill 根目錄本身是掛載點，四種情況都在動 live 之前中止，
> 快照不變、掛載內資料保留；拿修正前的文件反向跑，回滾確實刪掉了掛載內的資料。
> GNU `stat` 排在 PATH 前面的組合只在 Windows 的 Git Bash（GNU coreutils）以測試臺驗過，沒有在 Mac 上驗。
> 修正前的後果很嚴重：1b 會照常備份（`cp -R` 把掛載內容實體化、`diff -r` 仍相等）並印出 `ts`，
> 回滾的 `rm -rf ~/.claude/skills/超級模式` 會**跨進掛載樹刪除裡面的真實資料**。
> 殘留：掃描與 mutation 之間的 TOCTOU 窗口；同裝置號的掛載偵測不到；APFS 磁碟映像以外的掛載（SMB／NFS、macFUSE）
> 沒有實測（推論各有自己的裝置號）。1b 在掃 skill 之前就備份了 hook，所以 1b 因掛載點中止時會留下 hook 的備份檔與空的
> `skills-backup/`（live 不變；與 1b 因 symlink 中止時相同）。
> 記在 [`backlog.md`](backlog.md)。

macOS（Windows 的 settings 檔名不同，見下一段）:
```bash
set -euo pipefail
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.claude/skills-backup ~/.claude/skills ~/.claude/hooks

hbak=~/.claude/hooks/super-mode-consult-gate.js.bak-$ts
sbak=~/.claude/skills-backup/超級模式.bak-$ts
setf=~/.claude/settings.json
setbak=$setf.bak-$ts

# 同一秒重跑會撞名，撞到就停（等一秒再跑），不要覆蓋既有備份。
# `-L` 不可省：`-e` 對斷鏈 symlink 是 false，會讓 collision loop 以為路徑空著，
# 接著 `: > "$p"` 會**跟隨** symlink 把檔案建到它的目標（可能在備份區之外），
# 而 marker 路徑本身仍是 symlink —— 1b 照樣印出 ts，回滾卻會因 marker 是 link 而中止。
for p in "$hbak" "$hbak.absent" "$sbak" "$sbak.absent" "$setbak" "$setbak.absent"; do
  if [ -e "$p" ] || [ -L "$p" ]; then echo "已存在 ts=$ts 的備份產物（${p}），等一秒後重跑，中止"; exit 1; fi
done

# 型別要對才算「有」或「沒有」：skill 必須是目錄、hook/settings 必須是一般檔案。
# 型別不對（例如 skill 位置是一般檔案）就中止 —— 若誤判成 .absent，
# 回滾會把安裝前就存在的東西當成「全新安裝」刪掉。
# symlink 一律中止，而且要**先驗**：`-f`／`-d` 會跟隨有效的 link，把「指向別處的 link」
# 當成一般檔案／目錄備走內容，回滾時卻會把 link 本身換成實體檔案／目錄。`-L` 對斷掉的
# link 也為真，所以這一條同時涵蓋有效與斷掉兩種。
h=~/.claude/hooks/super-mode-consult-gate.js
s=~/.claude/skills/超級模式

if [ -L "$h" ]; then echo "$h 是 symlink，狀態不明，中止"; exit 1
elif [ -f "$h" ]; then
  cp "$h" "$hbak"; cmp -s "$h" "$hbak" || { echo "hook 備份不完整，中止"; exit 1; }
elif [ -e "$h" ]; then echo "$h 存在但不是一般檔案，狀態不明，中止"; exit 1
else : > "$hbak.absent"; fi

# 掛載點守衛（F4 MOUNT-RMRF）：1b、1c 與回滾段各有一份**逐字相同**的副本（測試臺 [M17] 比對，防漂移）。
# `find -type l` 抓不到掛載點（它是目錄不是 symlink），而 1b 的 `cp -R` 會把掛載內容實體化進備份、
# 1c 的 `cp -R` 會把同名檔寫進掛載裡、回滾的 `rm -rf` 會跨進掛載刪掉裡面的資料。
# 判準是 st_dev（裝置號）：根目錄要與上一層同裝置（否則它本身就是掛載點），樹內每個目錄要與根目錄同裝置。
# macOS 上一般使用者建得出的掛載（APFS volume、磁碟映像、SMB／NFS、macFUSE）各有自己的裝置號（推論）；
# 同裝置號的掛載（Linux bind mount）偵測不到。
# 驗證範圍：測試臺以假 stat 驗控制流；2026-10-18 已在 macOS 真機（hdiutil 拋棄式 APFS image：根掛載、子樹掛載、
#    1b／1c 之後才掛上、payload 保留；/bin/bash 3.2＋BSD stat）驗證。GNU stat 在前的組合只在 Git Bash 以測試臺驗過。
# ⚠️ 不能寫死任一種語法：PATH 前面若是 GNU coreutils（例如 Homebrew 的 gnubin），寫死的 `stat -f %d` 在 GNU 上
#    會失敗（`-f` 是「檔案系統狀態」、`%d` 被當成檔名），每次都被擋下；寫死 `-c` 則 macOS 內建的 stat 不認得。
#    所以先偵測語法：`-c` 只有 GNU 認得，BSD（macOS 內建）會拒絕。
# 判定只用 `%d`（一個目錄一行，與目錄名無關：名稱含換行也不會被拆錯行）；路徑只在偵測到之後另外取，當診斷訊息。
# 讀不到、格式不對、掃描失敗一律中止（fail-closed）。不加 `-xdev`：掛載點之內也掃（與 symlink 掃描同範圍）；
# `-exec … {} +` 任一次 stat 失敗，find 會回非零（macOS 與 GNU 的 find 皆然）。
if stat -c %d / >/dev/null 2>&1; then stf=-c; stn='%d %n'; else stf=-f; stn='%d %N'; fi
scan_no_mount() { # 用途名 路徑
  local _dev _par _v _all _bad _at
  [ -d "$2" ] || return 0
  if ! _dev=$(stat "$stf" %d "$2") || ! _par=$(stat "$stf" %d "$(dirname "$2")"); then
    echo "讀取 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  for _v in "$_dev" "$_par"; do
    case "$_v" in ''|*[!0-9]*) echo "$1（$2）的裝置號格式不對（${_v}），狀態不明，中止（live 未變更）"; exit 1 ;; esac
  done
  if [ "$_dev" != "$_par" ]; then echo "$1（$2）本身是掛載點，中止（live 未變更）"; exit 1; fi
  if ! _all=$(find "$2" -type d -exec stat "$stf" %d {} +); then
    echo "掃描 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  if ! _bad=$(printf '%s\n' "$_all" | awk -v d="$_dev" '
        !/^[0-9]+$/ { if (f == "") f = "F" $0; next }
        ($0 "") != (d "") { if (f == "") f = "D" $0 }
        END { print f }'); then
    echo "比對 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  case "$_bad" in
    '') ;;
    F*) echo "$1（$2）底下有讀不懂的裝置號（[${_bad#F}]），狀態不明，中止（live 未變更）"; exit 1 ;;
    *)  _at=$(find "$2" -type d -exec stat "$stf" "$stn" {} + 2>/dev/null |
              awk -v d="$_dev" 'f == "" && ($1 "") != (d "") { f = $0 } END { print f }') || _at='路徑取不到'
        echo "$1（$2）底下有掛載點（裝置號 ${_bad#D}，根目錄是 ${_dev}；${_at}），中止（live 未變更）"; exit 1 ;;
  esac
}

if [ -L "$s" ]; then echo "$s 是 symlink，狀態不明，中止"; exit 1
elif [ -d "$s" ]; then
  # 樹**內部**也要驗，不能只看頂層（與 Windows 版同一理由：內嵌 link 會在複製時被實體化，
  # 而目標為空時「只比對檔案」的驗證看不出差別）。
  # 不用 `-print -quit`（GNU 專屬）也不吞 stderr：實測若 find 因任何原因失敗，
  # `2>/dev/null` 會把錯誤吃掉、變數變成空字串，這道守衛就**靜默失效**（fail-open）。
  # 改成偵測 find 的退出碼，掃描失敗一律中止（fail-closed）。
  if ! lnk=$(find "$s" -type l); then echo "掃描 $s 的 symlink 失敗，狀態不明，中止"; exit 1; fi
  if [ -n "$lnk" ]; then
    echo "$s 底下有 symlink（$(printf '%s\n' "$lnk" | head -n 1)），狀態不明，中止"; exit 1
  fi
  # 掛載點同樣中止（見上方 scan_no_mount）。這只涵蓋 1b 當下；1c 的第一個 mutation 前與回滾的 rm -rf 前會再各偵測一次。
  scan_no_mount 'live skill' "$s"
  cp -R "$s" "$sbak"; diff -r "$s" "$sbak" >/dev/null || { echo "skill 備份與 live 不一致，中止"; exit 1; }
elif [ -e "$s" ]; then echo "$s 存在但不是目錄，狀態不明，中止"; exit 1
else : > "$sbak.absent"; fi

if [ -L "$setf" ]; then echo "$setf 是 symlink，狀態不明，中止"; exit 1
elif [ -f "$setf" ]; then
  cp "$setf" "$setbak"; cmp -s "$setf" "$setbak" || { echo "settings 備份不完整，中止"; exit 1; }
elif [ -e "$setf" ]; then echo "$setf 存在但不是一般檔案，狀態不明，中止"; exit 1
else : > "$setbak.absent"; fi

echo "backup ts=$ts"
```
Windows:
```powershell
$ErrorActionPreference = 'Stop'
$ts     = Get-Date -Format yyyyMMdd-HHmmss
$hook   = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
$skill  = "$env:USERPROFILE\.claude\skills\超級模式"
$bakDir = "$env:USERPROFILE\.claude\skills-backup"
$setf   = "$env:USERPROFILE\.claude\settings.json"
New-Item -ItemType Directory -Force -Path $bakDir, (Split-Path $hook), (Split-Path $skill) | Out-Null
$hbak = "$hook.bak-$ts"; $sbak = "$bakDir\超級模式.bak-$ts"; $setbak = "$setf.bak-$ts"

# ⚠️ 全程用 -LiteralPath。一般 -Path 會把 `[ ]` `?` `*` 當成萬用字元 pattern，
# 家目錄含中括號（Windows 使用者名稱允許）時「存在」判斷會反過來：對真實存在的路徑
# `Test-Path` 回 false、`-LiteralPath` 回 true —— 於是安裝前就有的東西被誤標成 .absent，
# 回滾時被當成「全新安裝」刪掉。（`New-Item` 沒有 -LiteralPath，但它建立時不做 pattern
# 展開，含 `[ ]` 也會產生字面名稱，安全。）
function Get-Entry($p) { Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
function Test-Reparse($e) { $null -ne $e -and (($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) }

foreach ($p in @($hbak, "$hbak.absent", $sbak, "$sbak.absent", $setbak, "$setbak.absent")) {
  if (Get-Entry $p) { throw "已存在 ts=$ts 的備份產物（${p}），等一秒後重跑，中止" }
}

# 指紋涵蓋目錄與 link 狀態，不只檔案。只列檔案的話，空目錄與「junction 被複製成普通空目錄」
# 兩邊都是零檔案 → 判定相等，備份會被當成完整。
function Get-TreeFingerprint($root) {
  Get-ChildItem -LiteralPath $root -Recurse -Force | ForEach-Object {
    $rel = $_.FullName.Substring($root.Length).TrimStart('\')
    $lk  = if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { 'L' } else { '' }
    if ($_.PSIsContainer) { "D$lk|$rel" }
    else { "F$lk|$rel|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
  } | Sort-Object
}
# 型別要對才算「有」或「沒有」：skill 必須是目錄、hook/settings 必須是一般檔案。
# 型別不對就中止 —— 若誤判成 .absent，回滾會把安裝前就存在的東西當「全新安裝」刪掉。
# link 一律中止：`Test-Path -PathType Leaf/Container` 會**跟隨**有效的 link，
# 把「指向別處的 link」當成一般檔案／目錄備走內容，回滾時卻會把 link 本身換成實體檔案／目錄。
# 所以先用 ReparsePoint 屬性攔下（symlink、junction、mount point 皆帶此屬性）。
# ⚠️ 已知殘留限制（Windows）：**指向不存在目標的 symlink** 有可能連 `Get-Item -Force` 都回 null，
#    那樣仍會落入「不存在」分支而建立 .absent。本機無管理員權限、無法建立 symlink 實測該分支
#    （斷掉的 **junction** 已實測會被上面的 ReparsePoint 檢查攔下）。記在 docs/backlog.md。
#    若你的 ~/.claude 底下這三個位置可能是 symlink，請先人工確認再安裝。
$he = Get-Entry $hook
if (Test-Reparse $he) { throw "$hook 是 link／reparse point，狀態不明，中止" }
elseif (Test-Path -LiteralPath $hook -PathType Leaf) {
  Copy-Item -LiteralPath $hook -Destination $hbak
  if ((Get-FileHash -LiteralPath $hook).Hash -ne (Get-FileHash -LiteralPath $hbak).Hash) { throw "hook 備份不完整，中止" }
} elseif ($he) { throw "$hook 存在但不是一般檔案，狀態不明，中止" }
else { New-Item -ItemType File -Path "$hbak.absent" | Out-Null }

$se = Get-Entry $skill
if (Test-Reparse $se) { throw "$skill 是 link／reparse point，狀態不明，中止" }
elseif (Test-Path -LiteralPath $skill -PathType Container) {
  # 樹**內部**也要驗，不能只看頂層：實測 `Copy-Item -Recurse` 會把內嵌 junction
  # **實體化成普通目錄**（不保留 reparse metadata）。若該 junction 的目標目前是空的，
  # 來源與備份的檔案集合都是空的 —— 舊版只列檔案的指紋會判定相等、印出 ts，
  # 於是回滾時 link 拓撲被普通空目錄取代而永久消失。
  $badLink = Get-ChildItem -LiteralPath $skill -Recurse -Force |
             Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
             Select-Object -First 1
  if ($badLink) { throw "$skill 底下有 link／reparse point（$($badLink.FullName)），狀態不明，中止" }
  Copy-Item -LiteralPath $skill -Destination $sbak -Recurse
  if (((Get-TreeFingerprint $se.FullName) -join "`n") -ne ((Get-TreeFingerprint (Get-Entry $sbak).FullName) -join "`n")) {
    throw "skill 備份與 live 不一致，中止"
  }
} elseif ($se) { throw "$skill 存在但不是目錄，狀態不明，中止" }
else { New-Item -ItemType File -Path "$sbak.absent" | Out-Null }

$te = Get-Entry $setf
if (Test-Reparse $te) { throw "$setf 是 link／reparse point，狀態不明，中止" }
elseif (Test-Path -LiteralPath $setf -PathType Leaf) {
  Copy-Item -LiteralPath $setf -Destination $setbak
  if ((Get-FileHash -LiteralPath $setf).Hash -ne (Get-FileHash -LiteralPath $setbak).Hash) { throw "settings 備份不完整，中止" }
} elseif ($te) { throw "$setf 存在但不是一般檔案，狀態不明，中止" }
else { New-Item -ItemType File -Path "$setbak.absent" | Out-Null }

"backup ts=$ts"
```

**1c. 安裝（複製到 live）**

> ℹ️ 複製是**合併**語意：除了下面明列的清理項之外**不會**動到 live 既有的其他檔案，也因此
> **不會**自動刪掉上游已經移除的檔案。前者是刻意的（安裝過程從不整個刪除 live，失敗最多留下
> 部分更新，而 1b 已驗證過的備份可還原）；後者要靠下面那行逐一清理——**只刪明確列名的已知路徑，
> 不做整目錄刪除**。

> ⚠️ **這段自己帶 fail-fast，不要假設它跟 1b 在同一個 shell。** 沒有這道保護時，複製失敗仍會以
> 成功結束，而步驟 3 的測試載入的是**現有的 live hook**——舊版三件套彼此一致的話會全綠，
> 於是「安裝成功」被回報出去，實際上什麼都沒換。所以複製完會**逐檔驗證 live 與來源一致**。

macOS:
```bash
set -euo pipefail
src="macos/skills/超級模式"; hooksrc="macos/hooks/super-mode-consult-gate.js"
live=~/.claude/skills/超級模式; hook=~/.claude/hooks/super-mode-consult-gate.js
[ -f "$src/SKILL.md" ] || { echo "來源不對（請在 repo 根目錄執行），中止"; exit 1; }

# 第一個 live mutation（下面的 cp -R）之前**重新掃描** live skill（F4 MOUNT-RMRF；與 Windows 1c 的 reparse 掃描等價）。
# 1b 的掃描只涵蓋 1b 當下：1b 之後才出現的 symlink 或掛載點，會讓 cp -R 把檔案寫穿到別處、寫進掛載裡。
# 偵測到就在任何 mutation 之前中止；1b 的備份仍在。不防同時修改（TOCTOU），與 1b、回滾的掃描同一個限制。
# 掛載點守衛：與 1b 那份逐字相同（測試臺 [M17] 比對），說明見 1b。
if stat -c %d / >/dev/null 2>&1; then stf=-c; stn='%d %n'; else stf=-f; stn='%d %N'; fi
scan_no_mount() { # 用途名 路徑
  local _dev _par _v _all _bad _at
  [ -d "$2" ] || return 0
  if ! _dev=$(stat "$stf" %d "$2") || ! _par=$(stat "$stf" %d "$(dirname "$2")"); then
    echo "讀取 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  for _v in "$_dev" "$_par"; do
    case "$_v" in ''|*[!0-9]*) echo "$1（$2）的裝置號格式不對（${_v}），狀態不明，中止（live 未變更）"; exit 1 ;; esac
  done
  if [ "$_dev" != "$_par" ]; then echo "$1（$2）本身是掛載點，中止（live 未變更）"; exit 1; fi
  if ! _all=$(find "$2" -type d -exec stat "$stf" %d {} +); then
    echo "掃描 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  if ! _bad=$(printf '%s\n' "$_all" | awk -v d="$_dev" '
        !/^[0-9]+$/ { if (f == "") f = "F" $0; next }
        ($0 "") != (d "") { if (f == "") f = "D" $0 }
        END { print f }'); then
    echo "比對 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  case "$_bad" in
    '') ;;
    F*) echo "$1（$2）底下有讀不懂的裝置號（[${_bad#F}]），狀態不明，中止（live 未變更）"; exit 1 ;;
    *)  _at=$(find "$2" -type d -exec stat "$stf" "$stn" {} + 2>/dev/null |
              awk -v d="$_dev" 'f == "" && ($1 "") != (d "") { f = $0 } END { print f }') || _at='路徑取不到'
        echo "$1（$2）底下有掛載點（裝置號 ${_bad#D}，根目錄是 ${_dev}；${_at}），中止（live 未變更）"; exit 1 ;;
  esac
}
if [ -L "$live" ]; then echo "live 端 $live 是 symlink，中止（live 未變更）"; exit 1; fi
if [ -d "$live" ]; then
  if ! lnk=$(find "$live" -type l); then echo "掃描 $live 的 symlink 失敗，狀態不明，中止（live 未變更）"; exit 1; fi
  if [ -n "$lnk" ]; then
    echo "$live 底下有 symlink（$(printf '%s\n' "$lnk" | head -n 1)），狀態不明，中止（live 未變更）"; exit 1
  fi
fi
scan_no_mount 'live skill' "$live"

cp -R "$src" ~/.claude/skills/
cp "$hooksrc" "$hook"
# 已從 payload 移出的檔案（2026-07-27 起 FIX-PLAN.md 改放 repo 的 docs/）：
rm -f "$live/FIX-PLAN.md"

# 驗證：來源的每個檔案在 live 都要有一份一模一樣的（live 多出來的使用者自有檔案不列入比對）
bad=0
while IFS= read -r -d '' f; do
  cmp -s "$src/$f" "$live/$f" || { echo "安裝驗證失敗：$f 與來源不符"; bad=1; }
done < <(cd "$src" && find . -type f -print0)
cmp -s "$hooksrc" "$hook" || { echo "安裝驗證失敗：hook 與來源不符"; bad=1; }
if [ -e "$live/FIX-PLAN.md" ]; then echo "安裝驗證失敗：FIX-PLAN.md 未清除"; bad=1; fi
[ "$bad" = 0 ] || { echo "安裝未完成 —— 請照下方回滾段還原，中止"; exit 1; }
echo "install OK"
```
Windows:
```powershell
$ErrorActionPreference = 'Stop'
$src = ".\windows\skills\超級模式"; $hooksrc = ".\windows\hooks\super-mode-consult-gate.js"
$live = "$env:USERPROFILE\.claude\skills\超級模式"
$hook = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
# 與 1b 同理，全程 -LiteralPath：家目錄含 `[ ]` 時一般 -Path 會把它當萬用字元，
# 使「live 缺少某檔」的判斷反過來，讓安裝驗證形同虛設。
if (-not (Test-Path -LiteralPath "$src\SKILL.md")) { throw "來源不對（請在 repo 根目錄執行），中止" }

# 第一個 live mutation（下面的 Copy-Item）之前**重新掃描** live skill（F4 MOUNT-RMRF；與 macOS 1c 等價）。
# 1b 的掃描只涵蓋 1b 當下：1b 之後才出現的 junction／symlink／NTFS 掛載資料夾（同為 reparse point），
# 會讓 Copy-Item 把檔案寫穿到別處、寫進掛載的磁碟裡。偵測到就在任何 mutation 之前中止；1b 的備份仍在。
# 與 1b 同一種偵測（ReparsePoint 屬性）。本區塊開頭的 Stop 讓列舉失敗（權限等）直接拋出＝fail-closed。
# 不防同時修改（TOCTOU），與 1b、回滾的掃描同一個限制。
$le = Get-Item -LiteralPath $live -Force -ErrorAction SilentlyContinue
if ($null -ne $le) {
  if (($le.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "live 端 $live 是 link／reparse point，中止（live 未變更）" }
  $badLink = Get-ChildItem -LiteralPath $live -Recurse -Force |
             Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
             Select-Object -First 1
  if ($badLink) { throw "$live 底下有 link／reparse point（$($badLink.FullName)），狀態不明，中止（live 未變更）" }
}

Copy-Item -LiteralPath $src -Destination "$env:USERPROFILE\.claude\skills\" -Recurse -Force
Copy-Item -LiteralPath $hooksrc -Destination $hook -Force
# 已從 payload 移出的檔案（2026-07-27 起 FIX-PLAN.md 改放 repo 的 docs/）：
$stale = "$live\FIX-PLAN.md"
if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force }

$srcRoot = (Resolve-Path -LiteralPath $src).Path
Get-ChildItem -LiteralPath $srcRoot -Recurse -File -Force | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  $dst = Join-Path $live $rel
  if (-not (Test-Path -LiteralPath $dst)) { throw "安裝驗證失敗：live 缺少 $rel" }
  if ((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $dst).Hash) { throw "安裝驗證失敗：$rel 與來源不符" }
}
if ((Get-FileHash -LiteralPath $hooksrc).Hash -ne (Get-FileHash -LiteralPath $hook).Hash) { throw "安裝驗證失敗：hook 與來源不符" }
if (Test-Path -LiteralPath $stale) { throw "安裝驗證失敗：FIX-PLAN.md 未清除" }
"install OK"
```

## 2. 註冊 hook

把對應平台 `settings.snippet.json` 的 `hooks` 區塊合併進 **`~/.claude/settings.json`**
（**合併，不要覆蓋既有設定**），並把 snippet 裡的絕對路徑改成使用者自己的家目錄。
**三平台都是這個檔。**

> ⛔ **這一步不是冪等的，動手前務必先數。** 「合併」照字面做會在陣列尾端**再 append 一筆**，
> 於是重跑一次安裝就多一筆重複的 gate handler。**三平台都會發生。**
>
> ```
> node tools/probe-gate-registration.js
> ```
>
> 這支 probe 是唯讀的，三平台同一條指令（在本 repo 的 checkout 根目錄跑）。
> **不要在這裡自己判斷該怎麼修，照它的退出碼與印出來的判定走**：
>
> | probe 結果 | 做法 |
> |---|---|
> | 退出碼 **1**（讀不到／形狀不合）| **停手**，先修好 settings 再重跑 |
> | 退出碼 **3**（停手）| **停手**，人工判斷——見 [`MIGRATION`](MIGRATION-hook-settings-target.md) 第 2 節開頭 |
> | 退出碼 0 ＋「兩邊都沒有 gate」 | **照本節往下加入** |
> | 退出碼 0 ＋「正常，不用修」 | **已經裝好了，什麼都不要做** |
> | 退出碼 0 ＋ 其他任何判定 | **不要在這裡加**——照它指的 A／B 做 [`MIGRATION`](MIGRATION-hook-settings-target.md) 第 2 節 |
>
> `MIGRATION` 的標題寫「只影響 macOS／Linux」指的是 **A** 分支；
> **B（重複註冊）三平台通用**，Windows 使用者照樣走那一節——它的備份步驟
> （`node tools/backup-settings.js`）也是三平台同一條指令。
>
> ⚠️ **probe 的範圍：它驗「有沒有註冊、有沒有重複」，不驗 matcher 的「內容」**（2026-08-28 實例）。
> 所以**升級既有安裝**時，`OK_NORMAL` **不等於**「什麼都不用做」——它只代表沒有缺漏或重複註冊。
> 若 skill 版本新增了受攔工具名（例如 `09340e3` 加的 `Monitor`／`Artifact`／`ScheduleWakeup`／
> `EnterWorktree`／`ExitWorktree`），舊 settings 的 matcher 會**少那幾個名字而 probe 照樣 OK_NORMAL**，
> 而那些工具在 runtime 下**根本不會叫起 hook** ⇒ 攔截等於沒生效。
> **抓得到這件事的是步驟 3 的 `matcher-contract.test.js --live`**（它會回 `MATCHER_DRIFT` 並列出缺哪幾個）。
> ⇒ **升級既有安裝的正確做法**：跑 probe 確認沒有重複／缺漏後，**另外**用 `--live` 對照，
> 若 `MATCHER_DRIFT` 就把既有那一筆的 matcher **就地換成** snippet 的新值
> （**是替換字串，不是再 append 一筆** —— append 會變成兩筆 gate handler）。
> 2026-08-28 實例：某台 macOS 的 settings 自 2026-07-26 起就少那 5 個名字，probe 一路 `OK_NORMAL`。
>
> ⚠️ **這裡刻意不複述判定矩陣。** 唯一的矩陣在 `MIGRATION` 第 1 節，而 probe 直接印結論。
> 2026-08-08 的合併前審查抓到：本節先前自己抄了一份簡化矩陣，把「`settings.json`=0、
> `local`≥1」（**受影響的舊安裝者，正是 MIGRATION 存在的理由**）誤導向純減法分支
> ——照做會把 local 那筆刪掉又不新增，**使用者僅存的 gate 就消失了**。
> 兩份文件各留一份矩陣，遲早再度分歧；所以這裡只指向單一來源。
>
> **合併完成後，重跑同一支 probe 當驗收**（不是可選項）：
>
> ```
> node tools/probe-gate-registration.js
> ```
>
> 必須印「**判定：正常，不用修。**」且**退出碼 0**。任何其他結果都代表這一步沒做對。
>
> ⚠️ **為什麼合併後一定要再跑一次**：probe 與步驟 3 的 `matcher-contract` **問的是不同問題**，
> 兩者都跑才有完整覆蓋。
>
> 2026-08-09 起，「哪個 handler 是本 gate、它會不會真的攔得住」由**單一共用模組**判斷
> （`skills/超級模式/lib/gate-registration.js`），所以 `type` 不是 `command`、或 handler 帶
> `if`／`async`／`asyncRewake` 這類會讓 gate 不阻擋的欄位、或頂層設了 `disableAllHooks: true` 時，**兩支都會 FAIL**——
> 這一類洞不再需要靠「記得多跑一支」來補。（此前 `matcher-contract` 只比對 `command` 字串，
> `{"type":"prompt", "command":"…gate…"}` 會讓步驟 3 全綠而 gate 根本不會被叫起。）
>
> probe **獨有**的、`matcher-contract` 不做也不該做的是這些：
>
> - 它同時看 `settings.json` **與** `settings.local.json`，`matcher-contract` 只看你指定的那一份
> - 它**數筆數**並判定重複註冊（合併不是冪等的，重跑安裝就會 append 第二筆）
> - 它會攔「gate 與別的 handler 共用同一個 entry」與「多筆註冊互相衝突」，這兩種要人工判斷
>
> 換句話說：`matcher-contract` 回答「這一份 settings 的 matcher 對不對」，
> probe 回答「你的機器上到底註冊了幾筆、在哪、能不能安全地動它」。
>
> **後置條件**：`settings.json` 的 gate handler **恰 1 個**、`settings.local.json` **0 個**。

- 若 `node` 不在系統 PATH——例如可攜式安裝在 `~/.local/node/bin`——
  hook 指令開頭的 `node` 必須寫**絕對路徑**，否則 hook 會靜默不跑、gate 形同虛設。（本條原寫給 Linux 的可攜式 node 安裝；Linux 已凍結，macOS 若同樣用可攜式 node 也適用，推論。）（2026-10-17 事實訂正：依 Claude Code hooks 文件，hook 啟動失敗在預設的 `onFailure: "continue"` 下屬於 non-blocking error——動作照常執行，PreToolUse 會在 transcript 顯示 `<hook name> hook error` 提示——所以不是完全「靜默」；gate 形同虛設的結論不變。以上限 macOS／Linux：Windows 沒有 Git Bash 且 Claude Code ≥2.1.299 時，預設改為失敗即擋（見 backlog `CC-NOBASH-FAILCLOSED`），所以 Windows 在步驟 0a 要求先裝 Git for Windows；`onFailure` 欄位自 2.1.295 起才有。）

> ⚠️ **不要用 `~/.claude/settings.local.json`**（2026-07-27 以前本文件的 macOS／Linux 段是這樣寫的，**那是錯的**）。
>
> 2026-07-28 在 macOS 真機實測：`settings.local.json` **只在專案層**（相對於 Claude Code 的**啟動目錄**）
> 被認得，家目錄那份**不是** user scope。它只有在「剛好從家目錄啟動」時才生效——因為那時
> `~/.claude/settings.local.json` 恰好**就是**專案層的 `.claude/settings.local.json`。
> 實測四組對照（啟動目錄 × 註冊位置）確認了這個規律；並在一台把 gate 只註冊在
> `settings.local.json` 的機器上回溯 143 個 session、11 個不同啟動目錄、14,477 次 hook 叫用，
> 該 gate **被叫用 0 次**。
>
> Claude Code 自己的說明字串也一致（2.1.148 與 2.1.220 皆同）：
> 「User-defined hooks from `~/.claude/settings.json`, `.claude/settings.json`, and
> `.claude/settings.local.json`」——`~/` **只出現在 `settings.json`**。
>
> **`~/.claude/settings.json` 不是只有你在寫。** 任何安裝器、設定同步或 promote 工具都可能改它——
> 而且 **Claude Code 自己的 plugin manager 就是同一個檔的寫入者**（該檔的 top-level key
> 除了 `hooks` 還有 `enabledPlugins`，2026-08-08 於維護者機器實查）。
> ⚠️ 這只證明「有其他寫入者」，**不**證明有哪個工具會覆寫或移除 `hooks` 段——目前沒有這種證據。
>
> 但把 hook 藏到一個不會被載入的檔案並不能解決這件事。正確做法是**任何可能改動該檔的動作之後**，
> 重跑步驟 3 的 `matcher-contract --live`——它現在找不到已註冊的 hook 會直接 FAIL，不再靜默通過。
>
> 📌 **2026-07-28 以前照舊指引裝過的人**：你的 hook 很可能一次都沒生效過。
> 診斷與修復步驟見 [`MIGRATION-hook-settings-target.md`](MIGRATION-hook-settings-target.md)。

hook 在啟用前是 fail-open 且停用的——安裝它不影響一般 session，只有 `super-mode.{sh,ps1} on` 之後才作用。（Windows 前提是已裝 Git for Windows：沒有 Git Bash 時，Claude Code 2.1.299 起會把 hook 失敗改成擋下，見步驟 0a。）

## 3. 驗證（跑 live；FAIL 就回滾到步驟 1b 的備份）

**macOS**
```bash
node ~/.claude/skills/超級模式/tests/run-gate-tests.js               # 應全數 PASS
node ~/.claude/skills/超級模式/tests/matcher-contract.test.js --live # ★ 必跑，見下方說明
bash ~/.claude/skills/超級模式/tests/run-e2e.sh                      # 應全數 passed（會印 GATE_UNDER_TEST 供核對）
bash ~/.claude/skills/超級模式/tests/exit-code-contract.smoke.sh     # 退出碼契約；驗的是**剛安裝的那份** consult
bash ~/.claude/skills/超級模式/tests/fault-injection.smoke.sh        # 故障注入 ＋ mutant；同樣驗**剛安裝的那份**
bash ~/.claude/skills/超級模式/tests/off-cleanup.tests.sh            # off 的逐字稿清理範圍；暫存 HOME，驗**剛安裝的那份** super-mode.sh
bash ~/.claude/skills/超級模式/tests/project-root-marker.tests.sh    # 指示根偵測；驗**剛安裝的那份** codex-exec.sh／codex-consult.sh
```

**Windows**
```powershell
node "$env:USERPROFILE\.claude\skills\超級模式\tests\run-gate-tests.js"               # 應全數 PASS
node "$env:USERPROFILE\.claude\skills\超級模式\tests\matcher-contract.test.js" --live # ★ 必跑，見下方說明
& "$env:USERPROFILE\.claude\skills\超級模式\tests\run-windows-suite.ps1" -Mode live   # 要看到 SUITE_RESULT=OK；驗的是**剛安裝的那份**
```

> ⚠️ **這一步驗的是 live 副本，不是 repo。** 本 repo 的安裝是 `Copy-Item` 實體複製，
> repo 與 `~/.claude` 之間沒有任何連動——「repo 改好」不等於「生效」。
> （2026-08-19 就是被這個咬過：live 停在三個禮拜前的版本，早就修好的東西還在咬人。）

> ★ **`matcher-contract` 是步驟 2 的驗收，不是可選項。** 另外兩支測試都是**直接呼叫** `decide()`，
> 就算你把 `matcher` 合併錯或漏合併，它們照樣全綠 —— 但真實情況是 hook **根本不會被叫起**，
> 新工具完全不受攔（假綠）。這支測試專門比對 hook 的工具清單與你剛合併進 settings 的 `matcher`。
> FAIL 就回去檢查步驟 2 的合併結果。
>
> **它的界線（別高估）**：這是**靜態比對**——挑出 settings 裡註冊了本 hook 的那筆 entry，比對 `matcher` 與 hook 清單。
> 它**不**驗證該 entry 的 `command` 路徑真的存在、也**不**證明 Claude Code runtime 真的載入了那份 settings
> （例如 matcher 正確但 `command` 指向不存在的檔，這支測試仍可能 PASS）。
> 它現在**至少不會**在「hook 根本沒註冊」時假綠——2026-07-28 起找不到已註冊本 hook 的 settings 就直接 FAIL，
> 不再 fallback 去撿一份不相干的 settings 來比對。要確認端到端接上，唯一方法是**在新 session 實際觸發一次**：
> ⚠ hook 設定變更**下個 session 才生效**，所以請在下個 session 開超級模式、於無憑證狀態試一個會被攔的動作，確認真的 deny。

**任何 FAIL → 先回滾、再回報使用者、停止**（不要留一個壞掉的 live hook）：

**只需要 1b 印出的 `ts`。** hook、skill、settings 三者各自是「還原舊版」還是「刪掉全新安裝」，
由 1b 留下的備份／`.absent` 標記決定，不用你判斷或填值。

> **先預檢、全部通過才動 live。** 每個元件都必須**恰好**有備份或 `.absent` 其中一個：
> 兩者都在（狀態不明）或兩者都無（`ts` 給錯、或備份被手動刪掉）**一律停手、完全不動 live**。
> 這是為了避免「skill 還原了、hook 卻靜默略過」而做出舊 skill + 新 hook 的混版。
>
> `ts` 會**先驗形狀**（`yyyyMMdd-HHmmss`）再拿去拼路徑。貼成含 `?`／`*`／`[]` 的值會被擋下——
> 那種值會把「這個備份在不在」變成萬用字元比對，可能比對到**別的** `ts` 的備份，
> 於是預檢通過、live 被刪、再還原成錯誤的版本。備份或標記本身是 link 時同樣中止。
>
> 還原用**複製**而非搬移，備份留在原地——所以可以重複執行，重跑結果相同；中途失敗時備份仍在，
> 重跑本段即可。
>
> ⚠️ settings 是**整檔還原**成 1b 當時的內容。若你在 1b 之後對 settings 做過與本安裝無關的修改，
> 那些修改會一併被還原掉——回滾請緊接在步驟 3 失敗後執行。

macOS:
```bash
set -euo pipefail
ts='<貼上 1b 印出的值>'          # 例：20260727-154409

# ts 必須是 1b 產生的形狀。不驗的話，一個含 glob 字元或路徑分隔的 ts 會讓下面每個
# 由它拼出來的路徑都指到非預期的地方（Windows 版有實測到的具體繞過，見該區塊註解）。
case "$ts" in
  [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
  *) echo "ts 格式不對（應為 yyyyMMdd-HHmmss，例 20260727-154409），中止（live 未變更）"; exit 1 ;;
esac

sbak=~/.claude/skills-backup/超級模式.bak-$ts
hbak=~/.claude/hooks/super-mode-consult-gate.js.bak-$ts
setf=~/.claude/settings.json
setbak=$setf.bak-$ts

# 型別也要對：skill 備份必須是目錄、hook/settings 備份必須是一般檔案、標記必須是一般檔案。
# 只驗「存在」不夠 —— 備份被換成別的型別時，precheck 會過，但還原什麼都不會複製，
# 卻已經把 live 刪掉了。
precheck() { # 名稱 備份 標記 型別(d|f)
  local n="$1" b="$2" a="$3" k="$4" eb=0 ea=0 okb=0 oka=0
  # symlink 一律中止，而且要先驗：`-d`／`-f` 會**跟隨**有效的 link，於是「指向別處的 link」
  # 會被當成合法備份／標記，還原時從錯誤目標複製 —— 但 live 已經先被刪掉了。
  # `-L` 對斷掉的 link 也為真，這一條同時涵蓋有效與斷掉兩種。
  if [ -L "$b" ]; then echo "${n}：ts=$ts 的備份是 symlink，中止（live 未變更）"; exit 1; fi
  if [ -L "$a" ]; then echo "${n}：ts=$ts 的 .absent 標記是 symlink，中止（live 未變更）"; exit 1; fi
  # 先看「有沒有這個 directory entry」，再看型別對不對。
  # 順序很重要：若只比對「型別正確的存在」，當一邊有效、另一邊存在但型別錯時，
  # 兩個錯誤分支都不會觸發，於是走進「原本不存在」那條 —— live 被刪卻不還原。
  if [ -e "$b" ]; then eb=1; fi
  if [ -e "$a" ]; then ea=1; fi
  if [ "$k" = d ]; then if [ -d "$b" ]; then okb=1; fi; else if [ -f "$b" ]; then okb=1; fi; fi
  if [ -f "$a" ]; then oka=1; fi

  if [ "$eb" = 1 ] && [ "$okb" = 0 ]; then echo "${n}：ts=$ts 的備份存在但型別不對，中止（live 未變更）"; exit 1; fi
  if [ "$ea" = 1 ] && [ "$oka" = 0 ]; then echo "${n}：ts=$ts 的 .absent 標記存在但型別不對，中止（live 未變更）"; exit 1; fi
  if [ "$okb" = 1 ] && [ "$oka" = 1 ]; then echo "${n}：備份與 .absent 同時存在，狀態不明，中止（live 未變更）"; exit 1; fi
  if [ "$okb" = 0 ] && [ "$oka" = 0 ]; then echo "${n}：找不到 ts=$ts 的有效備份或標記，中止（live 未變更）"; exit 1; fi
}
precheck skill    "$sbak"   "$sbak.absent"   d
precheck hook     "$hbak"   "$hbak.absent"   f
precheck settings "$setbak" "$setbak.absent" f

# live 端是 symlink 也停手（與 1b、與 Windows 版同一姿態）：還原會把 link 換成實體
# 檔案／目錄，等於在使用者不知情下改掉他的佈局。
for p in ~/.claude/skills/超級模式 ~/.claude/hooks/super-mode-consult-gate.js "$setf"; do
  if [ -L "$p" ]; then echo "live 端 $p 是 symlink，中止（live 未變更）"; exit 1; fi
done

# 頂層不是 link 還不夠 —— 備份或 live 的**子樹裡**若藏著 symlink，`cp -R`（GNU 與 BSD
# 都保留 symlink）會照著錯誤的拓撲還原，而 live 已經先被刪掉了。
# 1b 驗的是「建立備份當下」的 live；備份放在那裡到真正被使用之間可能已經漂移，
# 兩者之間沒有 manifest、也沒有完整性證明。所以這裡要重驗，兩棵樹都必須在任何 mutation 之前掃完。
scan_no_link() { # 用途名 路徑
  local _lnk
  # 路徑不存在＝「沒有子樹可掃」，**不是**掃描失敗。全新安裝只有 .absent、沒有 ${sbak}；
  # live 也可能已被手動移除。把這兩種情況當成 fail-closed，會讓合法的回滾永遠失敗
  # ——那和它要防的資料損失是同一形狀的 bug，一起犯就一起修。
  [ -e "$2" ] || return 0
  # 偵測退出碼：find 真的掃不動（權限等）一律中止（fail-closed）。不吞 stderr，
  # 也不用 GNU 專屬的 `-print -quit`（BSD 沒有）。
  if ! _lnk=$(find "$2" -type l); then
    echo "掃描 $1（$2）失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  if [ -n "$_lnk" ]; then
    echo "$1（$2）底下有 symlink（$(printf '%s\n' "$_lnk" | head -n 1)），狀態不明，中止（live 未變更）"
    exit 1
  fi
}
# ⚠️ **這道守衛的保證範圍**：它拒絕「掃描當下已存在」的內嵌 link，**不防同時修改**。
# 兩次掃描（${sbak}、live）與後續刪除之間仍有 TOCTOU 窗口：別的程序在掃完之後才把子樹換成
# link、或把備份整個移走，這裡看不到。這是複製貼上式安裝流程的固有限制，不是本次新增的回歸。
# 所以**不要**把它讀成「回滾已經安全了」。
# 另外 `find -type l` **抓不到掛載點**（它是目錄不是 symlink）；掛載點由下面的 scan_no_mount 另外擋
# （Windows 的 ReparsePoint 屬性則是連 NTFS 掛載資料夾一起抓）。
#
# `$sbak` 的條件呼叫是**多一層保險，不是缺一不可**：helper 自己已把「路徑不存在」視為成功
# （`[ -e "$2" ] || return 0`），所以就算無條件呼叫一個不存在的 `$sbak` 也不會失敗。
# 保留 `-d` 判斷只是讓意圖更明顯。（2026-08-10 合併前審查指出原註解把它說成必要條件，過強。）
if [ -d "$sbak" ]; then scan_no_link 'skill 備份' "$sbak"; fi
scan_no_link 'live skill' ~/.claude/skills/超級模式

# 掛載點守衛（F4 MOUNT-RMRF）：與 1b 那份逐字相同（測試臺 [M17] 比對），說明見 1b。
if stat -c %d / >/dev/null 2>&1; then stf=-c; stn='%d %n'; else stf=-f; stn='%d %N'; fi
scan_no_mount() { # 用途名 路徑
  local _dev _par _v _all _bad _at
  [ -d "$2" ] || return 0
  if ! _dev=$(stat "$stf" %d "$2") || ! _par=$(stat "$stf" %d "$(dirname "$2")"); then
    echo "讀取 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  for _v in "$_dev" "$_par"; do
    case "$_v" in ''|*[!0-9]*) echo "$1（$2）的裝置號格式不對（${_v}），狀態不明，中止（live 未變更）"; exit 1 ;; esac
  done
  if [ "$_dev" != "$_par" ]; then echo "$1（$2）本身是掛載點，中止（live 未變更）"; exit 1; fi
  if ! _all=$(find "$2" -type d -exec stat "$stf" %d {} +); then
    echo "掃描 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  if ! _bad=$(printf '%s\n' "$_all" | awk -v d="$_dev" '
        !/^[0-9]+$/ { if (f == "") f = "F" $0; next }
        ($0 "") != (d "") { if (f == "") f = "D" $0 }
        END { print f }'); then
    echo "比對 $1（$2）的裝置號失敗，狀態不明，中止（live 未變更）"; exit 1
  fi
  case "$_bad" in
    '') ;;
    F*) echo "$1（$2）底下有讀不懂的裝置號（[${_bad#F}]），狀態不明，中止（live 未變更）"; exit 1 ;;
    *)  _at=$(find "$2" -type d -exec stat "$stf" "$stn" {} + 2>/dev/null |
              awk -v d="$_dev" 'f == "" && ($1 "") != (d "") { f = $0 } END { print f }') || _at='路徑取不到'
        echo "$1（$2）底下有掛載點（裝置號 ${_bad#D}，根目錄是 ${_dev}；${_at}），中止（live 未變更）"; exit 1 ;;
  esac
}
# 這是**回滾當下**的重新偵測（Codex 10/15）：1b 之後才掛上的掛載點也攔得到。
# 只掃 live：`rm -rf` 只刪 live；備份只被讀取（`cp -R` 從掛載讀資料不會刪任何東西）。
# 與 scan_no_link 同樣**不防同時修改**（TOCTOU），不構成「回滾已經安全」的保證。
scan_no_mount 'live skill' ~/.claude/skills/超級模式

rm -rf ~/.claude/skills/超級模式
[ -d "$sbak" ] && cp -R "$sbak" ~/.claude/skills/超級模式

if [ -f "$hbak" ]; then cp "$hbak" ~/.claude/hooks/super-mode-consult-gate.js
else rm -f ~/.claude/hooks/super-mode-consult-gate.js; fi

if [ -f "$setbak" ]; then cp "$setbak" "$setf"
else rm -f "$setf"; fi
echo "已回滾。備份保留在 ~/.claude/skills-backup/、~/.claude/hooks/*.bak-${ts}、~/.claude/settings.json.bak-${ts}，確認無誤後自行刪除"
```
Windows（settings 檔是 `settings.json`）:
```powershell
$ErrorActionPreference = 'Stop'
$ts = '<貼上 1b 印出的值>'        # 例：20260727-154409

# ⚠️ ts 先驗形狀，下面再全程 -LiteralPath。這兩件缺一不可，實測（PowerShell 5.1.26100
# 與 7.6.3 皆同）：含萬用字元的 ts（例 '20260727-15440?'）會讓 `Get-Item -LiteralPath`
# 找不到、而會展開 pattern 的 `Test-Path` 卻比對到真正的備份 —— 於是 eb=0 但 okb=1，
# 四道錯誤分支全部略過、預檢「通過」，接著 live 被刪除，再從萬用字元比對到的**錯誤備份**
# 還原（實測：指定 -154409 卻還原成 -154400，然後才拋錯）。這正是本節「ts 給錯就完全
# 不動 live」的保證被破的路徑。
# 用 \A…\z 而非 ^…$：.NET 的 `$` 會匹配「結尾換行之前」，'20260727-154409<換行>' 也算通過。
if ($ts -notmatch '\A\d{8}-\d{6}\z') { throw "ts 格式不對（應為 yyyyMMdd-HHmmss，例 20260727-154409），中止（live 未變更）" }

$hook   = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
$skill  = "$env:USERPROFILE\.claude\skills\超級模式"
$sbak   = "$env:USERPROFILE\.claude\skills-backup\超級模式.bak-$ts"
$setf   = "$env:USERPROFILE\.claude\settings.json"
$hbak   = "$hook.bak-$ts"; $setbak = "$setf.bak-$ts"

function Get-Entry($p) { Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
function Test-Reparse($e) { $null -ne $e -and (($e.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) }

# 型別也要對：只驗「存在」的話，備份被換成別的型別時 precheck 會過，
# 但還原什麼都不會複製，卻已經把 live 刪掉了。
function Test-Exactly1($name, $bak, $absent, $kind) {
  # 先看 directory entry 在不在（Get-Item -Force 比 Test-Path 誠實），再看型別。
  # 順序很重要：若只比對「型別正確的存在」，當一邊有效、另一邊存在但型別錯時，
  # 兩個錯誤分支都不會觸發，於是走進「原本不存在」那條 —— live 被刪卻不還原。
  $b = Get-Entry $bak
  $a = Get-Entry $absent
  # link 一律中止：-PathType 會**跟隨**有效 link，會把「指向別處的 link」當成合法備份，
  # 還原時從錯誤目標複製 —— 而 live 已經先被刪掉了。（與 1b 同一姿態。）
  if (Test-Reparse $b) { throw "${name}：ts=$ts 的備份是 link／reparse point，中止（live 未變更）" }
  if (Test-Reparse $a) { throw "${name}：ts=$ts 的 .absent 標記是 link／reparse point，中止（live 未變更）" }
  # 型別判斷一律**掛在 entry 存在之上**，維持「型別正確 ⇒ entry 存在」這個不變量。
  # 少了前半段的 `$null -ne`，-Path 的 pattern 展開就能讓兩者脫鉤（見上方 ts 說明）。
  $okb = ($null -ne $b) -and (Test-Path -LiteralPath $bak -PathType $kind)     # Container = 目錄, Leaf = 一般檔
  $oka = ($null -ne $a) -and (Test-Path -LiteralPath $absent -PathType Leaf)
  if ($b -and -not $okb) { throw "${name}：ts=$ts 的備份存在但型別不對，中止（live 未變更）" }
  if ($a -and -not $oka) { throw "${name}：ts=$ts 的 .absent 標記存在但型別不對，中止（live 未變更）" }
  if ($okb -and $oka) { throw "${name}：備份與 .absent 同時存在，狀態不明，中止（live 未變更）" }
  if (-not $okb -and -not $oka) { throw "${name}：找不到 ts=$ts 的有效備份或標記，中止（live 未變更）" }
}
Test-Exactly1 'skill'    $sbak   "$sbak.absent"   'Container'
Test-Exactly1 'hook'     $hbak   "$hbak.absent"   'Leaf'
Test-Exactly1 'settings' $setbak "$setbak.absent" 'Leaf'

# live 端是 link 也停手：`Remove-Item -Recurse` 對 link 的行為隨 PowerShell／Windows
# 組建而異，不值得賭；1b 本來就會在 live 是 link 時中止，這裡維持同一姿態。
if (Test-Reparse (Get-Entry $skill)) { throw "live 端 $skill 是 link／reparse point，中止（live 未變更）" }
if (Test-Reparse (Get-Entry $hook))  { throw "live 端 $hook 是 link／reparse point，中止（live 未變更）" }
if (Test-Reparse (Get-Entry $setf))  { throw "live 端 $setf 是 link／reparse point，中止（live 未變更）" }

# 頂層不是 link 還不夠 —— 備份或 live 的**子樹裡**若藏著 junction／symlink，
# `Remove-Item -Recurse` 對 link 的行為隨組建而異，而 `Copy-Item -Recurse` 會把 junction 的
# 目標**實體化**，於是還原出來的是錯誤的拓撲。
# 1b 驗的是「建立備份當下」的 live；備份放在那裡到真正被使用之間可能已經漂移，
# 兩者之間沒有 manifest、也沒有完整性證明。所以這裡要重驗，兩棵樹都必須在任何 mutation 之前掃完。
function Assert-NoReparseUnder($name, $path) {
  # 路徑不存在＝「沒有子樹可掃」，**不是**掃描失敗。全新安裝只有 .absent、沒有 ${sbak}；
  # live 也可能已被手動移除。把這兩種情況當成 fail-closed，會讓合法的回滾永遠失敗
  # ——那和它要防的資料損失是同一形狀的 bug，一起犯就一起修。
  if (-not (Get-Entry $path)) { return }
  # 本區塊開頭的 $ErrorActionPreference = 'Stop' 讓真正的列舉失敗（權限等）直接拋出＝fail-closed。
  $bad = Get-ChildItem -LiteralPath $path -Recurse -Force |
         Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
         Select-Object -First 1
  if ($bad) { throw "${name}（${path}）底下有 link／reparse point（$($bad.FullName)），狀態不明，中止（live 未變更）" }
}
# ⚠️ **這道守衛的保證範圍**：它拒絕「掃描當下已存在」的 link／reparse point，**不防同時修改**。
# 兩次掃描與後續刪除之間仍有 TOCTOU 窗口，這是複製貼上式安裝流程的固有限制，
# 不是本次新增的回歸。**不要**把它讀成「回滾已經安全了」。
#
# `$sbak` 的條件呼叫是**多一層保險，不是缺一不可**：helper 自己已把「路徑不存在」視為成功
# （`if (-not (Get-Entry $path)) { return }`），無條件呼叫也不會失敗。
# （2026-08-10 合併前審查指出原註解把它說成必要條件，過強。）
if (Test-Path -LiteralPath $sbak -PathType Container) { Assert-NoReparseUnder 'skill 備份' $sbak }
Assert-NoReparseUnder 'live skill' $skill

if (Get-Entry $skill) { Remove-Item -LiteralPath $skill -Recurse -Force }
if (Test-Path -LiteralPath $sbak -PathType Container) { Copy-Item -LiteralPath $sbak -Destination $skill -Recurse }

if (Test-Path -LiteralPath $hbak -PathType Leaf) { Copy-Item -LiteralPath $hbak -Destination $hook -Force }
elseif (Get-Entry $hook) { Remove-Item -LiteralPath $hook -Force }

if (Test-Path -LiteralPath $setbak -PathType Leaf) { Copy-Item -LiteralPath $setbak -Destination $setf -Force }
elseif (Get-Entry $setf) { Remove-Item -LiteralPath $setf -Force }
"已回滾。備份保留在 skills-backup\、hooks\*.bak-${ts}、settings.json.bak-${ts}，確認無誤後自行刪除"
```

回滾後把失敗的測試輸出一併回報使用者，不要繼續下一步。

## 4. 檢查 Codex CLI 可用性

跑已安裝的權威 smoke test（不要只跑 `codex --version`，登入狀態要靠真實呼叫驗證）：

**macOS**：`bash ~/.claude/skills/超級模式/scripts/codex-check.sh`
**Linux**：🧊 已凍結，不適用本文件（見步驟 0）。凍結快照的 `codex-check.sh` 只有 H1–H5 那層，沒有能力面盤點與 baseline diff。
**Windows**：`& "$env:USERPROFILE\.claude\skills\超級模式\scripts\codex-check.ps1"`

- **通過** → 繼續步驟 5。
- **失敗**（未安裝 / 未登入 / 配額）→ **跳過步驟 5**，明確告知使用者：「skill 已安裝，但 Codex CLI 未就緒，『Codex 討論夥伴』全域規則未啟用；安裝並登入 Codex CLI 後重跑本步驟即可補上。」skill 本體照常可用（fail-open）。若 `npm` 可用：先詢問使用者是否代為安裝 Codex CLI（展示將執行的指令）；同意後——Windows 先確認 npm prefix（`npm config get prefix`；本 repo 維護者慣例 `C:\npm` 以避 MAX_PATH，prefix 異常請停下報告、勿逕裝）→ `npm install -g @openai/codex` → 重跑 codex-check 驗證。`codex login` 一律由使用者手動完成，不得代辦。

## 5.（建議）啟用「Codex 討論夥伴」全域規則

這一步會讓使用者的 Claude 在**交付決策型輸出前，先向 Codex 諮詢反方意見**。它修改的是使用者的全域行為設定 `~/.claude/CLAUDE.md`，所以有硬性防護要求：

1. **先徵得使用者同意**：展示將要寫入的 snippet 全文（對應平台：[`macos/CLAUDE-global-rule.md`](../macos/CLAUDE-global-rule.md) 或 [`windows/CLAUDE-global-rule.md`](../windows/CLAUDE-global-rule.md)；Linux 已凍結，不適用），並提醒：啟用後決策討論摘要會送到 Codex（OpenAI），逐字稿留在本機 `~/.claude/super-mode-logs/`。使用者不同意 → 跳過，安裝仍算完成。（之後隨時想啟用：重跑本步驟、或手動把對應平台 snippet **全文** append 到 `~/.claude/CLAUDE.md` 即可，下個新 session 生效。）
2. **備份**：若 `~/.claude/CLAUDE.md` 已存在，先複製一份 `~/.claude/CLAUDE.md.bak-<日期>`。
3. **冪等檢查**：若檔內已有 `CODEX-DISCUSSION-PARTNER` marker 或「Codex 討論夥伴」標題——**不要重複 append**；要更新就只替換 `BEGIN/END` marker 之間的區塊。
4. **Append**：把對應平台 snippet 檔的**全文**（含 BEGIN/END marker 註解）附加到 `~/.claude/CLAUDE.md` 末尾（檔案不存在就建立）。
5. 告知使用者：新開的 Claude Code session 起生效。

> **授權告示**：snippet 有一句規則改寫自 OpenAI codex-plugin-cc（Apache-2.0），出處註解在 BEGIN／END 區塊內的第二行；照第 4 點 append 全文時連同這行一起寫入，照第 3 點更新時只替換 BEGIN／END marker 之間的區塊，不要單獨刪掉它。見 repo 根目錄的 [`LICENSE`](../LICENSE)、[`NOTICE`](../NOTICE) 與 [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)。

## 6. 完成回報

回報使用者：裝了哪些檔、測試結果、Codex 可用性、討論夥伴規則有沒有啟用（沒啟用要說原因）、以及解除安裝方式（見下）。

## 解除安裝

> ⚠️ **順序不可對調：先改 settings、開新 session，再刪檔。** 先刪 gate 檔的話，settings 裡那筆 hook 每次都會因為找不到檔案而失敗：
> 有 Git Bash 時只是每次多一則 hook error 提示；沒有 Git Bash 的 Windows（Claude Code ≥2.1.299）則會擋下 Edit／Write／PowerShell 等工具，
> 連要改回 settings 都做不到（backlog [`CC-NOBASH-FAILCLOSED`](backlog.md#CC-NOBASH-FAILCLOSED)）。
> Windows 使用者日後要移除 Git for Windows，也要先做完下面第 1、2 步。

1. 從 `~/.claude/settings.json` 移除本 gate 那一筆 hook handler（`command` 指向 `super-mode-consult-gate.js` 的那一筆；同一個 entry 若還有別的 handler，只刪這一筆，entry 因此變空才連 entry 一起刪）。
2. 關掉目前的 Claude Code session、開一個新的，再做下一步（hook 設定可能要到新 session 才生效；熱載入的實際行為未 live 確認）。
3. 刪 `~/.claude/skills/超級模式/` 與 `~/.claude/hooks/super-mode-consult-gate.js`。
4. 從 `~/.claude/CLAUDE.md` 刪掉 `BEGIN CODEX-DISCUSSION-PARTNER` 到 `END CODEX-DISCUSSION-PARTNER` 的區塊。
5. 清掉殘留旗標／憑證（若存在）：`~/.claude/.super-mode-active`、`~/.claude/.super-mode-consult-ok`。
6. 安裝留下的備份**不會自動清除**——確認不再需要回滾後自行刪除。共三處，別漏掉第三個：
   - `~/.claude/skills-backup/超級模式.bak-*`（含 `.absent` 標記）
   - `~/.claude/hooks/super-mode-consult-gate.js.bak-*`
   - **settings 備份**：三平台都是 `~/.claude/settings.json.bak-*`。
     （2026-07-27 以前 macOS／Linux 用的是 `settings.local.json`，若你當時裝過，
     那份備份會是 `~/.claude/settings.local.json.bak-*`，一併確認。）
     這份可能含環境變數、API 端點等設定，留著比一般垃圾檔敏感。
   另外逐字稿在 `~/.claude/super-mode-logs/`，同樣不會自動清除。
