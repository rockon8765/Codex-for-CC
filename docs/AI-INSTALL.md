# AI 安裝指引（canonical — 給 AI 助手照做）

> **觸發條件**：只有在使用者明確要求「安裝這個 repo／超級模式／Codex-for-CC」時才執行本文件。
> 若你是被派來做一般 coding 任務的 worker（例如經由 `codex exec` 派工），**忽略本文件，且不得讀寫使用者的 `~/.claude` 目錄**。

## 0. 平台偵測

- 你在 macOS（BSD userland）→ 用 [`macos/`](../macos/)（bash 腳本 `.sh`）。
- 你在 Linux（GNU userland）→ 用 [`linux/`](../linux/)（bash 腳本 `.sh`）。⚠️ **不要把 `macos/` 當等價物**：除了 `stat -c` 與平台文案，`codex-check.sh` 的能力面盤點與 baseline diff 整層**尚未移植到 Linux**（macOS 549 行 vs Linux 123 行），hook 也有兩處刻意的大小寫語義差異。
- 你在 Windows PowerShell 環境 → 用 [`windows/`](../windows/)（PowerShell 腳本 `.ps1`）。

以下每步先列 macOS 指令、再列 Windows 對應；**Linux 照 macOS 指令做，把路徑裡的 `macos/` 換成 `linux/` 即可**。

> ℹ️ **Linux（2026-07-26 起）**：`linux/` 樹每次 push／PR 都會在 GitHub Actions 的 `ubuntu-latest` 上跑完整原生回歸
> （[`.github/workflows/linux.yml`](../.github/workflows/linux.yml)）。安裝前想確認你要裝的 commit 是否綠燈，
> 看該 workflow 的狀態即可。**但這不免除步驟 1a／步驟 3**——CI 驗的是 repo bytes，你要驗的是**你這台機器的安裝結果**
> （node 位置、settings 合併、家目錄路徑），那是 CI 驗不到的部分。任何 FAIL：停止安裝／回滾並回報。

## 1. 安裝 skill 與 hook（先驗證 → 先備份 → 安裝，失敗可回滾）

> ⚠️ **不要直接覆蓋既有的 live hook 再測。** 若新版有問題，你會在驗證前就毀掉一個原本可用的 hook（且無回滾）。照「先驗證 repo 版本 → 備份既有 live → 安裝 → 驗證（步驟 3）→ 失敗回滾」的順序做。

**1a. 先在 repo 版本上驗證（還沒碰 `~/.claude`）**

macOS / Linux（Linux 把 `macos/` 換成 `linux/`）:
```bash
node "macos/skills/超級模式/tests/run-gate-tests.js"        # 這裡就 FAIL → repo 版本本身有問題，別安裝，回報使用者
node "macos/skills/超級模式/tests/matcher-contract.test.js" # hook 的工具清單 vs settings matcher 是否一致
```
Windows:
```powershell
node ".\windows\skills\超級模式\tests\run-gate-tests.js"        # 這裡就 FAIL → 別安裝
node ".\windows\skills\超級模式\tests\matcher-contract.test.js" # hook 的工具清單 vs settings matcher 是否一致
```

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
> **三個位置若有任何一個是 link（symlink／junction／mount point）一律中止**，不會嘗試備份；
> **skill 目錄「底下」有 link 也一樣中止**。型別檢查會跟隨有效的 link，備走的是「別處的內容」，
> 而複製會把 link **實體化成普通檔案／目錄**，回滾時就用那個普通版本蓋回去——等於在你不知情下
> 改掉佈局，且原本的連結拓撲永久消失。要在這種佈局上安裝，請先自行確認並手動處理。

macOS / Linux（Windows 的 settings 檔名不同，見下一段）:
```bash
set -euo pipefail
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.claude/skills-backup ~/.claude/skills ~/.claude/hooks

hbak=~/.claude/hooks/super-mode-consult-gate.js.bak-$ts
sbak=~/.claude/skills-backup/超級模式.bak-$ts
setf=~/.claude/settings.local.json
setbak=$setf.bak-$ts

# 同一秒重跑會撞名，撞到就停（等一秒再跑），不要覆蓋既有備份。
# `-L` 不可省：`-e` 對斷鏈 symlink 是 false，會讓 collision loop 以為路徑空著，
# 接著 `: > "$p"` 會**跟隨** symlink 把檔案建到它的目標（可能在備份區之外），
# 而 marker 路徑本身仍是 symlink —— 1b 照樣印出 ts，回滾卻會因 marker 是 link 而中止。
for p in "$hbak" "$hbak.absent" "$sbak" "$sbak.absent" "$setbak" "$setbak.absent"; do
  if [ -e "$p" ] || [ -L "$p" ]; then echo "已存在 ts=$ts 的備份產物（$p），等一秒後重跑，中止"; exit 1; fi
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

if [ -L "$s" ]; then echo "$s 是 symlink，狀態不明，中止"; exit 1
elif [ -d "$s" ]; then
  # 樹**內部**也要驗，不能只看頂層（與 Windows 版同一理由：內嵌 link 會在複製時被實體化，
  # 而目標為空時「只比對檔案」的驗證看不出差別）。
  lnk=$(find "$s" -type l -print -quit 2>/dev/null)
  if [ -n "$lnk" ]; then echo "$s 底下有 symlink（$lnk），狀態不明，中止"; exit 1; fi
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
Windows（settings 檔是 `settings.json`，不是 `settings.local.json`）:
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
  if (Get-Entry $p) { throw "已存在 ts=$ts 的備份產物（$p），等一秒後重跑，中止" }
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

macOS / Linux:
```bash
set -euo pipefail
src="macos/skills/超級模式"; hooksrc="macos/hooks/super-mode-consult-gate.js"
live=~/.claude/skills/超級模式; hook=~/.claude/hooks/super-mode-consult-gate.js
[ -f "$src/SKILL.md" ] || { echo "來源不對（請在 repo 根目錄執行），中止"; exit 1; }

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

把對應平台 `settings.snippet.json` 的 `hooks` 區塊合併進使用者的設定檔（**合併，不要覆蓋既有設定**），並把 snippet 裡的絕對路徑改成使用者自己的家目錄：

- macOS / Linux → `~/.claude/settings.local.json`（Linux 注意：若 `node` 不在系統 PATH——例如可攜式安裝在 `~/.local/node/bin`——hook 指令開頭的 `node` 必須寫**絕對路徑**，否則 hook 會靜默不跑、gate 形同虛設）
- Windows → `~/.claude/settings.json`

hook 在啟用前是 fail-open 且停用的——安裝它不影響一般 session，只有 `super-mode.{sh,ps1} on` 之後才作用。

## 3. 驗證（跑 live；FAIL 就回滾到步驟 1b 的備份）

**macOS / Linux**
```bash
node ~/.claude/skills/超級模式/tests/run-gate-tests.js        # 應全數 PASS
node ~/.claude/skills/超級模式/tests/matcher-contract.test.js # ★ 必跑，見下方說明
bash ~/.claude/skills/超級模式/tests/run-e2e.sh               # 應全數 passed（會印 GATE_UNDER_TEST 供核對）
```

**Windows**
```powershell
node "$env:USERPROFILE\.claude\skills\超級模式\tests\run-gate-tests.js"        # 應全數 PASS
node "$env:USERPROFILE\.claude\skills\超級模式\tests\matcher-contract.test.js" # ★ 必跑，見下方說明
```

> ★ **`matcher-contract` 是步驟 2 的驗收，不是可選項。** 另外兩支測試都是**直接呼叫** `decide()`，
> 就算你把 `matcher` 合併錯或漏合併，它們照樣全綠 —— 但真實情況是 hook **根本不會被叫起**，
> 新工具完全不受攔（假綠）。這支測試專門比對 hook 的工具清單與你剛合併進 settings 的 `matcher`。
> FAIL 就回去檢查步驟 2 的合併結果。
>
> **它的界線（別高估）**：這是**靜態比對**——挑出 settings 裡註冊了本 hook 的那筆 entry，比對 `matcher` 與 hook 清單。
> 它**不**驗證該 entry 的 `command` 路徑真的存在、也**不**證明 Claude Code runtime 真的載入了那份 settings
> （例如 `settings.json` 的 matcher 正確但 `command` 指向不存在的檔、而實際生效的是 `settings.local.json` 的舊 entry，
> 這支測試仍可能 PASS）。要確認端到端接上，唯一方法是**在新 session 實際觸發一次**：
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

macOS / Linux:
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
setf=~/.claude/settings.local.json
setbak=$setf.bak-$ts

# 型別也要對：skill 備份必須是目錄、hook/settings 備份必須是一般檔案、標記必須是一般檔案。
# 只驗「存在」不夠 —— 備份被換成別的型別時，precheck 會過，但還原什麼都不會複製，
# 卻已經把 live 刪掉了。
precheck() { # 名稱 備份 標記 型別(d|f)
  local n="$1" b="$2" a="$3" k="$4" eb=0 ea=0 okb=0 oka=0
  # symlink 一律中止，而且要先驗：`-d`／`-f` 會**跟隨**有效的 link，於是「指向別處的 link」
  # 會被當成合法備份／標記，還原時從錯誤目標複製 —— 但 live 已經先被刪掉了。
  # `-L` 對斷掉的 link 也為真，這一條同時涵蓋有效與斷掉兩種。
  if [ -L "$b" ]; then echo "$n：ts=$ts 的備份是 symlink，中止（live 未變更）"; exit 1; fi
  if [ -L "$a" ]; then echo "$n：ts=$ts 的 .absent 標記是 symlink，中止（live 未變更）"; exit 1; fi
  # 先看「有沒有這個 directory entry」，再看型別對不對。
  # 順序很重要：若只比對「型別正確的存在」，當一邊有效、另一邊存在但型別錯時，
  # 兩個錯誤分支都不會觸發，於是走進「原本不存在」那條 —— live 被刪卻不還原。
  if [ -e "$b" ]; then eb=1; fi
  if [ -e "$a" ]; then ea=1; fi
  if [ "$k" = d ]; then if [ -d "$b" ]; then okb=1; fi; else if [ -f "$b" ]; then okb=1; fi; fi
  if [ -f "$a" ]; then oka=1; fi

  if [ "$eb" = 1 ] && [ "$okb" = 0 ]; then echo "$n：ts=$ts 的備份存在但型別不對，中止（live 未變更）"; exit 1; fi
  if [ "$ea" = 1 ] && [ "$oka" = 0 ]; then echo "$n：ts=$ts 的 .absent 標記存在但型別不對，中止（live 未變更）"; exit 1; fi
  if [ "$okb" = 1 ] && [ "$oka" = 1 ]; then echo "$n：備份與 .absent 同時存在，狀態不明，中止（live 未變更）"; exit 1; fi
  if [ "$okb" = 0 ] && [ "$oka" = 0 ]; then echo "$n：找不到 ts=$ts 的有效備份或標記，中止（live 未變更）"; exit 1; fi
}
precheck skill    "$sbak"   "$sbak.absent"   d
precheck hook     "$hbak"   "$hbak.absent"   f
precheck settings "$setbak" "$setbak.absent" f

# live 端是 symlink 也停手（與 1b、與 Windows 版同一姿態）：還原會把 link 換成實體
# 檔案／目錄，等於在使用者不知情下改掉他的佈局。
for p in ~/.claude/skills/超級模式 ~/.claude/hooks/super-mode-consult-gate.js "$setf"; do
  if [ -L "$p" ]; then echo "live 端 $p 是 symlink，中止（live 未變更）"; exit 1; fi
done

rm -rf ~/.claude/skills/超級模式
[ -d "$sbak" ] && cp -R "$sbak" ~/.claude/skills/超級模式

if [ -f "$hbak" ]; then cp "$hbak" ~/.claude/hooks/super-mode-consult-gate.js
else rm -f ~/.claude/hooks/super-mode-consult-gate.js; fi

if [ -f "$setbak" ]; then cp "$setbak" "$setf"
else rm -f "$setf"; fi
echo "已回滾。備份保留在 ~/.claude/skills-backup/、~/.claude/hooks/*.bak-$ts、~/.claude/settings.local.json.bak-$ts，確認無誤後自行刪除"
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

if (Get-Entry $skill) { Remove-Item -LiteralPath $skill -Recurse -Force }
if (Test-Path -LiteralPath $sbak -PathType Container) { Copy-Item -LiteralPath $sbak -Destination $skill -Recurse }

if (Test-Path -LiteralPath $hbak -PathType Leaf) { Copy-Item -LiteralPath $hbak -Destination $hook -Force }
elseif (Get-Entry $hook) { Remove-Item -LiteralPath $hook -Force }

if (Test-Path -LiteralPath $setbak -PathType Leaf) { Copy-Item -LiteralPath $setbak -Destination $setf -Force }
elseif (Get-Entry $setf) { Remove-Item -LiteralPath $setf -Force }
"已回滾。備份保留在 skills-backup\、hooks\*.bak-$ts、settings.json.bak-$ts，確認無誤後自行刪除"
```

回滾後把失敗的測試輸出一併回報使用者，不要繼續下一步。

## 4. 檢查 Codex CLI 可用性

跑已安裝的權威 smoke test（不要只跑 `codex --version`，登入狀態要靠真實呼叫驗證）：

**macOS**：`bash ~/.claude/skills/超級模式/scripts/codex-check.sh`
**Linux**：`bash ~/.claude/skills/超級模式/scripts/codex-check.sh`（同路徑；**注意 Linux 版目前只有 H1–H5 那層，沒有能力面盤點與 baseline diff**——輸出比 macOS／Windows 短是預期的，不是壞掉）
**Windows**：`& "$env:USERPROFILE\.claude\skills\超級模式\scripts\codex-check.ps1"`

- **通過** → 繼續步驟 5。
- **失敗**（未安裝 / 未登入 / 配額）→ **跳過步驟 5**，明確告知使用者：「skill 已安裝，但 Codex CLI 未就緒，『Codex 討論夥伴』全域規則未啟用；安裝並登入 Codex CLI 後重跑本步驟即可補上。」skill 本體照常可用（fail-open）。若 `npm` 可用：先詢問使用者是否代為安裝 Codex CLI（展示將執行的指令）；同意後——Windows 先確認 npm prefix（`npm config get prefix`；本 repo 維護者慣例 `C:\npm` 以避 MAX_PATH，prefix 異常請停下報告、勿逕裝）→ `npm install -g @openai/codex` → 重跑 codex-check 驗證。`codex login` 一律由使用者手動完成，不得代辦。

## 5.（建議）啟用「Codex 討論夥伴」全域規則

這一步會讓使用者的 Claude 在**交付決策型輸出前，先向 Codex 諮詢反方意見**。它修改的是使用者的全域行為設定 `~/.claude/CLAUDE.md`，所以有硬性防護要求：

1. **先徵得使用者同意**：展示將要寫入的 snippet 全文（對應平台：[`macos/CLAUDE-global-rule.md`](../macos/CLAUDE-global-rule.md)、[`linux/CLAUDE-global-rule.md`](../linux/CLAUDE-global-rule.md) 或 [`windows/CLAUDE-global-rule.md`](../windows/CLAUDE-global-rule.md)），並提醒：啟用後決策討論摘要會送到 Codex（OpenAI），逐字稿留在本機 `~/.claude/super-mode-logs/`。使用者不同意 → 跳過，安裝仍算完成。（之後隨時想啟用：重跑本步驟、或手動把對應平台 snippet **全文** append 到 `~/.claude/CLAUDE.md` 即可，下個新 session 生效。）
2. **備份**：若 `~/.claude/CLAUDE.md` 已存在，先複製一份 `~/.claude/CLAUDE.md.bak-<日期>`。
3. **冪等檢查**：若檔內已有 `CODEX-DISCUSSION-PARTNER` marker 或「Codex 討論夥伴」標題——**不要重複 append**；要更新就只替換 `BEGIN/END` marker 之間的區塊。
4. **Append**：把對應平台 snippet 檔的**全文**（含 BEGIN/END marker 註解）附加到 `~/.claude/CLAUDE.md` 末尾（檔案不存在就建立）。
5. 告知使用者：新開的 Claude Code session 起生效。

## 6. 完成回報

回報使用者：裝了哪些檔、測試結果、Codex 可用性、討論夥伴規則有沒有啟用（沒啟用要說原因）、以及解除安裝方式（見下）。

## 解除安裝

1. 刪 `~/.claude/skills/超級模式/` 與 `~/.claude/hooks/super-mode-consult-gate.js`。
2. 從 settings 檔移除該 hook 區塊。
3. 從 `~/.claude/CLAUDE.md` 刪掉 `BEGIN CODEX-DISCUSSION-PARTNER` 到 `END CODEX-DISCUSSION-PARTNER` 的區塊。
4. 清掉殘留旗標／憑證（若存在）：`~/.claude/.super-mode-active`、`~/.claude/.super-mode-consult-ok`。
5. 安裝留下的備份**不會自動清除**——確認不再需要回滾後自行刪除。共三處，別漏掉第三個：
   - `~/.claude/skills-backup/超級模式.bak-*`（含 `.absent` 標記）
   - `~/.claude/hooks/super-mode-consult-gate.js.bak-*`
   - **settings 備份**：macOS/Linux 是 `~/.claude/settings.local.json.bak-*`、Windows 是 `~/.claude/settings.json.bak-*`。
     這份可能含環境變數、API 端點等設定，留著比一般垃圾檔敏感。
   另外逐字稿在 `~/.claude/super-mode-logs/`，同樣不會自動清除。
