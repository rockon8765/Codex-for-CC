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

macOS / Linux（Windows 的 settings 檔名不同，見下一段）:
```bash
set -euo pipefail
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.claude/skills-backup ~/.claude/skills ~/.claude/hooks

hbak=~/.claude/hooks/super-mode-consult-gate.js.bak-$ts
sbak=~/.claude/skills-backup/超級模式.bak-$ts
setf=~/.claude/settings.local.json
setbak=$setf.bak-$ts

# 同一秒重跑會撞名，撞到就停（等一秒再跑），不要覆蓋既有備份
for p in "$hbak" "$hbak.absent" "$sbak" "$sbak.absent" "$setbak" "$setbak.absent"; do
  [ -e "$p" ] && { echo "已存在 ts=$ts 的備份產物（$p），等一秒後重跑，中止"; exit 1; }
done

# 型別要對才算「有」或「沒有」：skill 必須是目錄、hook/settings 必須是一般檔案。
# 型別不對（例如 skill 位置是一般檔案、或壞掉的 symlink）就中止 —— 若誤判成 .absent，
# 回滾會把安裝前就存在的東西當成「全新安裝」刪掉。
h=~/.claude/hooks/super-mode-consult-gate.js
s=~/.claude/skills/超級模式

if [ -f "$h" ]; then
  cp "$h" "$hbak"; cmp -s "$h" "$hbak" || { echo "hook 備份不完整，中止"; exit 1; }
elif [ -e "$h" ] || [ -L "$h" ]; then echo "$h 存在但不是一般檔案（或壞掉的 symlink），狀態不明，中止"; exit 1
else : > "$hbak.absent"; fi

if [ -d "$s" ]; then
  cp -R "$s" "$sbak"; diff -r "$s" "$sbak" >/dev/null || { echo "skill 備份與 live 不一致，中止"; exit 1; }
elif [ -e "$s" ] || [ -L "$s" ]; then echo "$s 存在但不是目錄（或壞掉的 symlink），狀態不明，中止"; exit 1
else : > "$sbak.absent"; fi

if [ -f "$setf" ]; then
  cp "$setf" "$setbak"; cmp -s "$setf" "$setbak" || { echo "settings 備份不完整，中止"; exit 1; }
elif [ -e "$setf" ] || [ -L "$setf" ]; then echo "$setf 存在但不是一般檔案（或壞掉的 symlink），狀態不明，中止"; exit 1
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

foreach ($p in @($hbak, "$hbak.absent", $sbak, "$sbak.absent", $setbak, "$setbak.absent")) {
  if (Test-Path $p) { throw "已存在 ts=$ts 的備份產物（$p），等一秒後重跑，中止" }
}

function Get-TreeFingerprint($root) {
  Get-ChildItem $root -Recurse -File -Force | ForEach-Object {
    '{0}|{1}' -f $_.FullName.Substring($root.Length).TrimStart('\'), (Get-FileHash $_.FullName -Algorithm SHA256).Hash
  } | Sort-Object
}
# 型別要對才算「有」或「沒有」：skill 必須是目錄、hook/settings 必須是一般檔案。
# 型別不對就中止 —— 若誤判成 .absent，回滾會把安裝前就存在的東西當「全新安裝」刪掉。
# ⚠️ 已知限制（Windows）：`Test-Path` 無法區分「沒有這個項目」與「指向不存在目標的 symlink」，
#    兩者都回 false。所以**斷掉的 symlink 會被當成「不存在」**、建立 .absent 標記。
#    POSIX 版用 `[ -e ] || [ -L ]` 沒有這個問題。本機無管理員權限、無法建立 symlink 實測修法，
#    因此不放未經驗證的偵測碼進來 —— 這是刻意的取捨，記在 docs/backlog.md。
#    若你的 ~/.claude 底下這三個位置可能是 symlink，請先人工確認再安裝。
if (Test-Path $hook -PathType Leaf) {
  Copy-Item $hook $hbak
  if ((Get-FileHash $hook).Hash -ne (Get-FileHash $hbak).Hash) { throw "hook 備份不完整，中止" }
} elseif (Test-Path $hook) { throw "$hook 存在但不是一般檔案，狀態不明，中止" }
else { New-Item -ItemType File -Path "$hbak.absent" | Out-Null }

if (Test-Path $skill -PathType Container) {
  Copy-Item -Recurse $skill $sbak
  if (((Get-TreeFingerprint (Resolve-Path $skill).Path) -join "`n") -ne ((Get-TreeFingerprint (Resolve-Path $sbak).Path) -join "`n")) {
    throw "skill 備份與 live 不一致，中止"
  }
} elseif (Test-Path $skill) { throw "$skill 存在但不是目錄，狀態不明，中止" }
else { New-Item -ItemType File -Path "$sbak.absent" | Out-Null }

if (Test-Path $setf -PathType Leaf) {
  Copy-Item $setf $setbak
  if ((Get-FileHash $setf).Hash -ne (Get-FileHash $setbak).Hash) { throw "settings 備份不完整，中止" }
} elseif (Test-Path $setf) { throw "$setf 存在但不是一般檔案，狀態不明，中止" }
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
if (-not (Test-Path "$src\SKILL.md")) { throw "來源不對（請在 repo 根目錄執行），中止" }

Copy-Item -Recurse $src "$env:USERPROFILE\.claude\skills\" -Force
Copy-Item $hooksrc $hook -Force
# 已從 payload 移出的檔案（2026-07-27 起 FIX-PLAN.md 改放 repo 的 docs/）：
$stale = "$live\FIX-PLAN.md"
if (Test-Path $stale) { Remove-Item -Force $stale }

$srcRoot = (Resolve-Path $src).Path
Get-ChildItem $srcRoot -Recurse -File -Force | ForEach-Object {
  $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\')
  $dst = Join-Path $live $rel
  if (-not (Test-Path $dst)) { throw "安裝驗證失敗：live 缺少 $rel" }
  if ((Get-FileHash $_.FullName).Hash -ne (Get-FileHash $dst).Hash) { throw "安裝驗證失敗：$rel 與來源不符" }
}
if ((Get-FileHash $hooksrc).Hash -ne (Get-FileHash $hook).Hash) { throw "安裝驗證失敗：hook 與來源不符" }
if (Test-Path $stale) { throw "安裝驗證失敗：FIX-PLAN.md 未清除" }
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
> 還原用**複製**而非搬移，備份留在原地——所以可以重複執行，重跑結果相同；中途失敗時備份仍在，
> 重跑本段即可。
>
> ⚠️ settings 是**整檔還原**成 1b 當時的內容。若你在 1b 之後對 settings 做過與本安裝無關的修改，
> 那些修改會一併被還原掉——回滾請緊接在步驟 3 失敗後執行。

macOS / Linux:
```bash
set -euo pipefail
ts='<貼上 1b 印出的值>'          # 例：20260727-154409
sbak=~/.claude/skills-backup/超級模式.bak-$ts
hbak=~/.claude/hooks/super-mode-consult-gate.js.bak-$ts
setf=~/.claude/settings.local.json
setbak=$setf.bak-$ts

# 型別也要對：skill 備份必須是目錄、hook/settings 備份必須是一般檔案、標記必須是一般檔案。
# 只驗「存在」不夠 —— 備份被換成別的型別時，precheck 會過，但還原什麼都不會複製，
# 卻已經把 live 刪掉了。
precheck() { # 名稱 備份 標記 型別(d|f)
  local n="$1" b="$2" a="$3" k="$4" eb=0 ea=0 okb=0 oka=0
  # 先看「有沒有這個 directory entry」（含壞掉的 symlink），再看型別對不對。
  # 順序很重要：若只比對「型別正確的存在」，當一邊有效、另一邊存在但型別錯時，
  # 兩個錯誤分支都不會觸發，於是走進「原本不存在」那條 —— live 被刪卻不還原。
  if [ -e "$b" ] || [ -L "$b" ]; then eb=1; fi
  if [ -e "$a" ] || [ -L "$a" ]; then ea=1; fi
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
$hook   = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
$skill  = "$env:USERPROFILE\.claude\skills\超級模式"
$sbak   = "$env:USERPROFILE\.claude\skills-backup\超級模式.bak-$ts"
$setf   = "$env:USERPROFILE\.claude\settings.json"
$hbak   = "$hook.bak-$ts"; $setbak = "$setf.bak-$ts"

# 型別也要對：只驗「存在」的話，備份被換成別的型別時 precheck 會過，
# 但還原什麼都不會複製，卻已經把 live 刪掉了。
function Test-Exactly1($name, $bak, $absent, $kind) {
  # 先看 directory entry 在不在（Get-Item -Force 比 Test-Path 誠實），再看型別。
  # 順序很重要：若只比對「型別正確的存在」，當一邊有效、另一邊存在但型別錯時，
  # 兩個錯誤分支都不會觸發，於是走進「原本不存在」那條 —— live 被刪卻不還原。
  $eb = $null -ne (Get-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue)
  $ea = $null -ne (Get-Item -LiteralPath $absent -Force -ErrorAction SilentlyContinue)
  $okb = Test-Path $bak -PathType $kind          # Container = 目錄, Leaf = 一般檔
  $oka = Test-Path $absent -PathType Leaf
  if ($eb -and -not $okb) { throw "${name}：ts=$ts 的備份存在但型別不對，中止（live 未變更）" }
  if ($ea -and -not $oka) { throw "${name}：ts=$ts 的 .absent 標記存在但型別不對，中止（live 未變更）" }
  if ($okb -and $oka) { throw "${name}：備份與 .absent 同時存在，狀態不明，中止（live 未變更）" }
  if (-not $okb -and -not $oka) { throw "${name}：找不到 ts=$ts 的有效備份或標記，中止（live 未變更）" }
}
Test-Exactly1 'skill'    $sbak   "$sbak.absent"   'Container'
Test-Exactly1 'hook'     $hbak   "$hbak.absent"   'Leaf'
Test-Exactly1 'settings' $setbak "$setbak.absent" 'Leaf'

if (Test-Path $skill) { Remove-Item -Recurse -Force $skill }
if (Test-Path $sbak -PathType Container) { Copy-Item -Recurse $sbak $skill }

if (Test-Path $hbak -PathType Leaf) { Copy-Item $hbak $hook -Force }
elseif (Test-Path $hook) { Remove-Item -Force $hook }

if (Test-Path $setbak -PathType Leaf) { Copy-Item $setbak $setf -Force }
elseif (Test-Path $setf) { Remove-Item -Force $setf }
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
