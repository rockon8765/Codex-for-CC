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

> ⚠️ **備份一定要放在 `~/.claude/skills/` 外面**（本文用 `~/.claude/skills-backup/`）。
> 備份若留在 `~/.claude/skills/` 底下，Claude Code 的 skill loader 會把它**當成另一個
> skill 註冊**——名稱與 description 幾乎相同，會干擾 skill 選擇。（2026-07-27 實際發生過。）
>
> ⚠️ **這段是 fail-closed 的**：備份指令失敗就直接中止，不會印出 `ts`。所以「有印出 `ts`」
> 才等於「備份確實成功」——不要把「有跑過 1b」當成有備份。同時記下 `had_skill` / `had_hook`
> 兩個旗標，回滾時要靠它們分辨「還原舊版」與「刪掉全新安裝」。

macOS / Linux:
```bash
set -euo pipefail
ts=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.claude/skills-backup ~/.claude/skills ~/.claude/hooks

had_hook=0;  [ -e ~/.claude/hooks/super-mode-consult-gate.js ] && had_hook=1
had_skill=0; [ -d ~/.claude/skills/超級模式 ]                  && had_skill=1

if [ "$had_hook" = 1 ]; then
  cp ~/.claude/hooks/super-mode-consult-gate.js ~/.claude/hooks/super-mode-consult-gate.js.bak-$ts
  [ -s ~/.claude/hooks/super-mode-consult-gate.js.bak-$ts ] || { echo "hook 備份不完整，中止"; exit 1; }
fi
if [ "$had_skill" = 1 ]; then
  cp -R ~/.claude/skills/超級模式 ~/.claude/skills-backup/超級模式.bak-$ts
  [ -f ~/.claude/skills-backup/超級模式.bak-$ts/SKILL.md ] || { echo "skill 備份不完整，中止"; exit 1; }
fi
echo "backup ts=$ts had_skill=$had_skill had_hook=$had_hook"
```
Windows:
```powershell
$ErrorActionPreference = 'Stop'
$ts     = Get-Date -Format yyyyMMdd-HHmmss
$hook   = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
$skill  = "$env:USERPROFILE\.claude\skills\超級模式"
$bakDir = "$env:USERPROFILE\.claude\skills-backup"
New-Item -ItemType Directory -Force -Path $bakDir, (Split-Path $hook), (Split-Path $skill) | Out-Null

$hadHook  = Test-Path $hook
$hadSkill = Test-Path $skill

if ($hadHook)  {
  Copy-Item $hook "$hook.bak-$ts"
  if (-not (Test-Path "$hook.bak-$ts")) { throw "hook 備份不完整，中止" }
}
if ($hadSkill) {
  Copy-Item -Recurse $skill "$bakDir\超級模式.bak-$ts"
  if (-not (Test-Path "$bakDir\超級模式.bak-$ts\SKILL.md")) { throw "skill 備份不完整，中止" }
}
"backup ts=$ts hadSkill=$hadSkill hadHook=$hadHook"
```

**1c. 安裝（staging → 驗證 → 交換）**

> ⚠️ **不要直接對 live 做「先刪再複製」。** 刪除必須發生在**新版已經完整就緒**之後，否則權限
> 不足、磁碟滿、跑錯工作目錄、複製到一半失敗，都會讓使用者的 live 被刪掉卻換不上新版。
> 本段的順序是：驗證來源 → 複製到 `~/.claude/skills/` **外面**的 staging → 驗證 staging 完整
> → 才交換 live。任何一步失敗都在碰 live 之前就停。
>
> 為什麼不能直接複製上去（合併語意）：上游**刪掉**的檔案會留在 live 變成殘留。例如
> 2026-07-27 把 `FIX-PLAN.md` 移出 payload 後，只做複製的話 live 會留著那份已完成的舊修復
> 規劃書，未來的 agent 可能誤讀重跑。staging 交換沒有這個問題。
>
> staging 目錄同樣**必須在 `~/.claude/skills/` 外面**，理由同 1b（會被當成另一個 skill）。

macOS / Linux:
```bash
set -euo pipefail
src="macos/skills/超級模式"                      # Linux 改成 linux/skills/超級模式
[ -f "$src/SKILL.md" ] || { echo "來源不對（請在 repo 根目錄執行），中止"; exit 1; }

stage_root=~/.claude/skills-staging
rm -rf "$stage_root"; mkdir -p "$stage_root"
cp -R "$src" "$stage_root/"
stage="$stage_root/超級模式"
[ -f "$stage/SKILL.md" ] && [ -d "$stage/scripts" ] && [ -d "$stage/tests" ] \
  || { echo "staging 不完整，live 未被更動，中止"; rm -rf "$stage_root"; exit 1; }

rm -rf ~/.claude/skills/超級模式                  # 到這裡才碰 live：備份已驗、新版已就緒
mv "$stage" ~/.claude/skills/超級模式
rmdir "$stage_root"
cp "macos/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
```
Windows:
```powershell
$ErrorActionPreference = 'Stop'
$src = ".\windows\skills\超級模式"
if (-not (Test-Path "$src\SKILL.md")) { throw "來源不對（請在 repo 根目錄執行），中止" }

$stageRoot = "$env:USERPROFILE\.claude\skills-staging"
if (Test-Path $stageRoot) { Remove-Item -Recurse -Force $stageRoot }
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
Copy-Item -Recurse $src $stageRoot
$stage = Join-Path $stageRoot "超級模式"
if (-not ((Test-Path "$stage\SKILL.md") -and (Test-Path "$stage\scripts") -and (Test-Path "$stage\tests"))) {
  Remove-Item -Recurse -Force $stageRoot; throw "staging 不完整，live 未被更動，中止"
}

$skill = "$env:USERPROFILE\.claude\skills\超級模式"
if (Test-Path $skill) { Remove-Item -Recurse -Force $skill }   # 到這裡才碰 live
Move-Item $stage $skill
Remove-Item -Recurse -Force $stageRoot
Copy-Item ".\windows\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\" -Force
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

用 **1b 印出來的 `ts` / `had_skill` / `had_hook`** 決定每個元件該還原還是刪除——**不要**用「有沒有跑過
1b」來判斷。1b 是 fail-closed 的：有印出那三個值才代表備份確實成功。hook 與 skill 各自判斷，因為
可能只有其中一個是全新安裝。

macOS / Linux:
```bash
set -euo pipefail
# ts / had_skill / had_hook 用 1b 印出來的值填進來
rm -rf ~/.claude/skills-staging                                   # 1c 中途失敗可能留下

if [ "$had_hook" = 1 ]; then
  cp ~/.claude/hooks/super-mode-consult-gate.js.bak-$ts ~/.claude/hooks/super-mode-consult-gate.js
else
  rm -f ~/.claude/hooks/super-mode-consult-gate.js
fi

rm -rf ~/.claude/skills/超級模式
if [ "$had_skill" = 1 ]; then
  mv ~/.claude/skills-backup/超級模式.bak-$ts ~/.claude/skills/超級模式
fi
```
Windows:
```powershell
$ErrorActionPreference = 'Stop'
# $ts / $hadSkill / $hadHook 用 1b 印出來的值填進來
$hook  = "$env:USERPROFILE\.claude\hooks\super-mode-consult-gate.js"
$skill = "$env:USERPROFILE\.claude\skills\超級模式"
$bak   = "$env:USERPROFILE\.claude\skills-backup\超級模式.bak-$ts"
$stageRoot = "$env:USERPROFILE\.claude\skills-staging"
if (Test-Path $stageRoot) { Remove-Item -Recurse -Force $stageRoot }

if ($hadHook) { Copy-Item "$hook.bak-$ts" $hook -Force }
elseif (Test-Path $hook) { Remove-Item -Force $hook }

if (Test-Path $skill) { Remove-Item -Recurse -Force $skill }
if ($hadSkill) { Move-Item $bak $skill }
```

**若 `had_hook` 是 0（hook 屬全新安裝）**，還要**移除步驟 2 加進 settings 的 hook 區塊**——否則 settings
會指向一個已經不存在的 hook。

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
5. 安裝時留下的備份（`~/.claude/skills-backup/超級模式.bak-*`、`~/.claude/hooks/super-mode-consult-gate.js.bak-*`）與逐字稿（`~/.claude/super-mode-logs/`）**不會自動清除**——確認不再需要回滾後自行刪除。
