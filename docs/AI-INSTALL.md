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

**1b. 開一個安裝交易（記住印出的 `TX` 路徑，回滾要用）**

> ⚠️ **交易目錄一定要在 `~/.claude/skills/` 外面**（本文放 `~/.claude/install-tx.XXXXXXXX`）。
> 備份或暫存若留在 `~/.claude/skills/` 底下，Claude Code 的 skill loader 會把它**當成另一個
> skill 註冊**——名稱與 description 幾乎相同，會干擾 skill 選擇。（2026-07-27 實際發生過。）
>
> ⚠️ **這段是 fail-closed 的**：任何一步失敗就直接中止，不會印出 `TX=`。所以「有印出 `TX=`」
> 才等於「這個交易確實建立成功」——不要把「有跑過 1b」當成已備份。
>
> **回滾只需要記住一個值：`TX` 這個交易目錄路徑。** 目錄本身就是狀態紀錄（manifest）：
> 裡面有沒有 `old-hook` / `replaced-skill` 就代表安裝前有沒有既存的 hook / skill。
> 這樣回滾不必靠人工填布林值——**手填布林值是真的會出錯的**：PowerShell 裡字串 `"False"`
> 在 `if ($x)` 會走 **true** 分支，把輸出的 `False` 當字串填回去就會嘗試還原不存在的備份。
>
> 交易目錄用 `mktemp` / GUID 產生**唯一路徑**，不是固定名稱——固定路徑會讓兩個同時進行的
> 安裝互相清掉對方的暫存。

macOS / Linux:
```bash
set -euo pipefail
mkdir -p ~/.claude/skills ~/.claude/hooks
tx=$(mktemp -d "$HOME/.claude/install-tx.XXXXXXXX")   # 唯一路徑，且在 skills/ 外面

if [ -e ~/.claude/hooks/super-mode-consult-gate.js ]; then
  cp ~/.claude/hooks/super-mode-consult-gate.js "$tx/old-hook"
  [ -s "$tx/old-hook" ] || { echo "hook 備份不完整，中止"; exit 1; }
fi
echo "TX=$tx"
```
Windows:
```powershell
$ErrorActionPreference = 'Stop'
$hook  = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
$skill = "$env:USERPROFILE\.claude\skills\超級模式"
New-Item -ItemType Directory -Force -Path (Split-Path $hook), (Split-Path $skill) | Out-Null
$tx = Join-Path "$env:USERPROFILE\.claude" ("install-tx." + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tx | Out-Null

if (Test-Path $hook) {
  Copy-Item $hook "$tx\old-hook"
  if (-not (Get-Item "$tx\old-hook").Length) { throw "hook 備份不完整，中止" }
}
"TX=$tx"
```

**1c. 安裝（staging → 逐檔驗證 → 非破壞性交換）**

> ⚠️ **舊的 live 不是被刪掉，是被「搬到交易目錄」。** 順序是：驗證來源 → 複製到交易目錄裡的
> staging → **逐檔比對來源與 staging 的內容** → 把舊 live 搬進交易目錄 → 把新版搬進來。
> 最後一步若失敗，會**立刻把舊 live 搬回原位**再中止——所以不存在「刪了卻換不上」的窗口。
> 舊 live 留在交易目錄裡，就是回滾要用的備份。
>
> 為什麼不直接複製上去（合併語意）：上游**刪掉**的檔案會留在 live 變成殘留。例如
> 2026-07-27 把 `FIX-PLAN.md` 移出 payload 後，只做複製的話 live 會留著那份已完成的舊修復
> 規劃書，未來的 agent 可能誤讀重跑。搬移式交換沒有這個問題。
>
> 完整性判準是**逐檔內容比對**，不是「幾個目錄存在」——後者抓不到截斷或部分複製。

macOS / Linux:
```bash
set -euo pipefail
# tx 用 1b 印出的 TX= 值
src="macos/skills/超級模式"                      # Linux 改成 linux/skills/超級模式
hooksrc="macos/hooks/super-mode-consult-gate.js" # Linux 改成 linux/hooks/...
live=~/.claude/skills/超級模式
hook=~/.claude/hooks/super-mode-consult-gate.js
[ -d "$tx" ] || { echo "找不到交易目錄 $tx，中止"; exit 1; }
[ -f "$src/SKILL.md" ] || { echo "來源不對（請在 repo 根目錄執行），中止"; exit 1; }
# 一個交易只能用一次。重複使用會把來源複製進既有的 new-skill 裡，變成難懂的「不一致」錯誤。
if [ -e "$tx/new-skill" ] || [ -e "$tx/replaced-skill" ]; then
  echo "交易 $tx 已經用過（或上次失敗留下殘留）。請重跑 1b 取得新的 TX，中止"; exit 1
fi

cp -R "$src" "$tx/new-skill"
cp "$hooksrc" "$tx/new-hook"
# 逐檔內容比對：staging 必須與來源完全一致
diff -r "$src" "$tx/new-skill" >/dev/null || { echo "staging 與來源不一致，live 未被更動，中止"; exit 1; }
cmp -s "$hooksrc" "$tx/new-hook" || { echo "hook staging 與來源不一致，live 未被更動，中止"; exit 1; }

# 非破壞性交換：舊的先搬進交易目錄（它同時就是回滾用的備份）
[ -d "$live" ] && mv "$live" "$tx/replaced-skill"
if ! mv "$tx/new-skill" "$live"; then
  [ -d "$tx/replaced-skill" ] && mv "$tx/replaced-skill" "$live"   # 換不上就立刻搬回來
  echo "交換失敗，已還原舊版，中止"; exit 1
fi
# hook 也走「同目錄暫存 → 置換」，避免複製到一半留下受損的 hook
mv "$tx/new-hook" "$hook.incoming" && mv "$hook.incoming" "$hook"
echo "安裝完成。回滾請用 TX=$tx"
```
Windows:
```powershell
$ErrorActionPreference = 'Stop'
# $tx 用 1b 印出的 TX= 值
$src     = ".\windows\skills\超級模式"
$hooksrc = ".\windows\hooks\super-mode-consult-gate.js"
$live    = "$env:USERPROFILE\.claude\skills\超級模式"
$hook    = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
if (-not (Test-Path $tx)) { throw "找不到交易目錄 $tx，中止" }
if (-not (Test-Path "$src\SKILL.md")) { throw "來源不對（請在 repo 根目錄執行），中止" }
# 一個交易只能用一次。重複使用會把來源複製進既有的 new-skill 裡，變成難懂的「不一致」錯誤。
if ((Test-Path "$tx\new-skill") -or (Test-Path "$tx\replaced-skill")) {
  throw "交易 $tx 已經用過（或上次失敗留下殘留）。請重跑 1b 取得新的 TX，中止"
}

Copy-Item -Recurse $src "$tx\new-skill"
Copy-Item $hooksrc "$tx\new-hook"
function Get-TreeFingerprint($root) {
  Get-ChildItem $root -Recurse -File | ForEach-Object {
    '{0}|{1}' -f $_.FullName.Substring($root.Length).TrimStart('\'), (Get-FileHash $_.FullName -Algorithm SHA256).Hash
  } | Sort-Object
}
if (((Get-TreeFingerprint (Resolve-Path $src).Path) -join "`n") -ne ((Get-TreeFingerprint "$tx\new-skill") -join "`n")) {
  throw "staging 與來源不一致，live 未被更動，中止"
}
if ((Get-FileHash $hooksrc).Hash -ne (Get-FileHash "$tx\new-hook").Hash) {
  throw "hook staging 與來源不一致，live 未被更動，中止"
}

if (Test-Path $live) { Move-Item $live "$tx\replaced-skill" }
try { Move-Item "$tx\new-skill" $live }
catch {
  if (Test-Path "$tx\replaced-skill") { Move-Item "$tx\replaced-skill" $live }   # 換不上就搬回來
  throw "交換失敗，已還原舊版，中止"
}
Move-Item "$tx\new-hook" "$hook.incoming" -Force
Move-Item "$hook.incoming" $hook -Force
"安裝完成。回滾請用 TX=$tx"
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

回滾**只需要 1b 印出的 `TX` 路徑**。狀態全部從交易目錄本身讀，不用人工填任何布林值
（手填布林值會出錯：PowerShell 裡字串 `"False"` 在 `if ($x)` 會走 **true** 分支）。
判讀規則：交易目錄裡有 `replaced-skill` ⇒ 安裝前有既存 skill，還原它；沒有 ⇒ 是全新安裝，刪掉。
hook 同理看 `old-hook`。兩者各自判斷，因為可能只有其中一個是全新安裝。
**找不到 `TX` 就停手回報使用者，不要盲目刪 live。**

macOS / Linux:
```bash
set -euo pipefail
# tx 用 1b 印出的 TX= 值
live=~/.claude/skills/超級模式
hook=~/.claude/hooks/super-mode-consult-gate.js
[ -d "$tx" ] || { echo "找不到交易目錄 $tx，停止（不要盲目刪 live），回報使用者"; exit 1; }

rm -rf "$live"
[ -d "$tx/replaced-skill" ] && mv "$tx/replaced-skill" "$live"     # 沒有就代表是全新安裝，維持刪除

if [ -e "$tx/old-hook" ]; then cp "$tx/old-hook" "$hook"; else rm -f "$hook"; fi
rm -f "$hook.incoming"                                             # 1c 中途失敗可能留下
echo "已回滾（交易目錄 $tx 保留，確認無誤後自行刪除）"
```
Windows:
```powershell
$ErrorActionPreference = 'Stop'
# $tx 用 1b 印出的 TX= 值
$live = "$env:USERPROFILE\.claude\skills\超級模式"
$hook = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
if (-not (Test-Path $tx)) { throw "找不到交易目錄 $tx，停止（不要盲目刪 live），回報使用者" }

if (Test-Path $live) { Remove-Item -Recurse -Force $live }
if (Test-Path "$tx\replaced-skill") { Move-Item "$tx\replaced-skill" $live }

if (Test-Path "$tx\old-hook") { Copy-Item "$tx\old-hook" $hook -Force }
elseif (Test-Path $hook) { Remove-Item -Force $hook }
if (Test-Path "$hook.incoming") { Remove-Item -Force "$hook.incoming" }
"已回滾（交易目錄 $tx 保留，確認無誤後自行刪除）"
```

**若交易目錄裡沒有 `old-hook`（hook 屬全新安裝）**，還要**移除步驟 2 加進 settings 的 hook 區塊**——
否則 settings 會指向一個已經不存在的 hook。

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
5. 安裝交易目錄（`~/.claude/install-tx.*`，裡面是舊版 skill 與 hook 的備份）與逐字稿（`~/.claude/super-mode-logs/`）**不會自動清除**——確認不再需要回滾後自行刪除。
