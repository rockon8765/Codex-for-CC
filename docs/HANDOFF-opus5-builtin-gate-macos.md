# HANDOFF — macOS 原生驗證：Opus 5 對齊 + gate 內建工具面補齊

> # ✅ 已完成／封存（2026-07-26）——**不要再照跑**
> macOS 原生驗證**已完成**（darwin arm64：gate-cases **116/116**、`matcher-contract` exit 0、
> `run-e2e.sh` 11/11、`GATE_UNDER_TEST` 確認指向 worktree），該批改動**已 promote 進 main**。
> 本檔保留為歷史紀錄與**格式範本**。下方的期望值（114/114 等）是**當時**的數字、**已過時**；
> 「不要安裝這個分支」也僅適用於當時那個 pending 分支。
> **Linux 原生驗證仍未做**——要做時請以本檔為格式另備一份 handoff，期望值重新從
> `linux/skills/超級模式/tests/gate-cases.json` 取（目前 118 案）。

> ## ⛔ 不要安裝這個分支（以下為當時內容，保留原樣）
> 本分支的 macOS／Linux 改動**只在 Windows 上以 node 跑過邏輯回歸，未經真機驗證**。
> **不要**把這個分支的檔案複製進 `~/.claude/`，**不要**照 `docs/AI-INSTALL.md` 安裝它。
> 這份 handoff 只做一件事：在**隔離的 worktree 裡**跑測試、把原始輸出貼回來。
> 驗證通過後由 Windows 端 ff-only promote 進 main，那時才輪到部署。

---

## 0. 為什麼需要 mac 真機

這次改動碰到兩個**平台語義**的東西，Windows 上的 node 跑得過不代表 mac 行為正確：

1. **`isRunnerTouchingSensitive()` 是新抽出來的共用函式**（Bash 與新的 Monitor 分支共用）。
   mac 版用 `toLowerCase()` + `/private/(tmp|var|etc)/` 摺疊 + `HITS` 命中清單；
   Linux 版刻意是 **case-preserving**（不 `toLowerCase()`）。抽函式時很容易把兩者寫反 ——
   需要在 mac 真機上確認 `/private/tmp`↔`/tmp` 等價與 `os.tmpdir()` 的實際值仍讓判定成立。
2. **`os.tmpdir()` 在 mac 是 `/var/folders/...`（經 `/private` 摺疊）**，Windows 上是 `C:\...\Temp`。
   `__TMP__` placeholder 的替換結果不同，runner 相關案例只有在 mac 上跑才算數。

## 1. 這次改了什麼（摘要）

**gate（三平台 `hooks/super-mode-consult-gate.js`）**
- `MUTATING_BUILTIN` 增列 `Artifact` / `ScheduleWakeup` / `EnterWorktree` / `ExitWorktree`。
- 新增 **`Monitor` 獨立分支**：有 `command` → 走 Bash 同一套唯讀分類器；**沒有 `command`（純 WebSocket）→ 一律要憑證**。
  這一條不能省：**`isReadOnlyCommand("") === true`**（空字串沒有任何 segment 可否決），
  讓空字串走分類器等於 fail-open，純 ws 的 Monitor 會被放行。
- 抽出 `isRunnerTouchingSensitive(cmd, claudeDir)` 供 Bash 與 Monitor 共用（避免兩套判準漂移）。

**settings matcher（三平台 `settings.snippet.json`）**
- 加 `Monitor|…|Artifact|ScheduleWakeup|EnterWorktree|ExitWorktree`。
  hook 的清單**只有在 matcher 也列到時才生效** —— matcher 不匹配，hook 根本不會被叫起。

**新測試 `tests/matcher-contract.test.js`（三平台，md5 一致）**
- 把 hook 的 `MUTATING_FILE_TOOLS` / `MUTATING_BUILTIN` / shell 分支與 settings matcher 雙向釘死。
- repo 佈局讀 `settings.snippet.json`；裝到 `~/.claude` 後改讀真正生效的 `settings.json` / `settings.local.json`。

**文件（三平台 SKILL.md / orchestration.md + README）**：模型與 effort 的繼承姿態、成本敘述澄清、
子代理 fan-out 約束、gate 攔截面清單同步。

## 2. 前置

- macOS 真機、Node.js（`node --version` ≥ 18 即可；本測試不依賴新語法）。
- 一個**乾淨的工作副本**，且**不要**在你日常的 `~/.claude` 上操作。
- 全程唯讀＋跑測試，不會改到你機器上的任何設定。

## 3. 步驟

### 3.1 取得待驗證的樹（用完整 SHA，不要用分支名）

```bash
cd <你本地的 Codex-for-CC clone>
git fetch origin feat/opus5-alignment-builtin-gate-pending-native
git worktree add --detach /tmp/opus5-verify <FINAL_HANDOFF_SHA>
cd /tmp/opus5-verify
git rev-parse HEAD          # 必須等於 <FINAL_HANDOFF_SHA>

# 確認這棵樹確實建立在你先前推的 macOS baseline 移植 commit 之上（不依賴 commit 數量）
git merge-base --is-ancestor b103184757b2e320f60a3bef742183fca5c16053 HEAD \
  && echo "rebased on b103184 OK" || echo "FAIL: 不在 b103184 之上"
```

用 `--detach` + 完整 SHA 是刻意的：分支名可能被後續 push 移動，detached 才能釘死「驗的就是要 merge 的 bytes」。

### 3.2 blob 核對（證明樹沒被動過手腳）

```bash
cd /tmp/opus5-verify
for f in "macos/hooks/super-mode-consult-gate.js" \
         "macos/settings.snippet.json" \
         "macos/skills/超級模式/SKILL.md" \
         "macos/skills/超級模式/references/orchestration.md" \
         "macos/skills/超級模式/tests/gate-cases.json" \
         "macos/skills/超級模式/tests/matcher-contract.test.js"; do
  printf "%s  %s\n" "$(git rev-parse HEAD:"$f")" "$f"
done
```

期望值（逐字比對，任何一個不符就停下來回報）：

| blob | 檔案 |
|---|---|
| `71d4453cbccc66afb30871e3354fde688743d997` | `macos/hooks/super-mode-consult-gate.js` |
| `565ca42626180553273e852729b72b956292e466` | `macos/settings.snippet.json` |
| `6a55be9396db2ba08e2bf996741e70a049793724` | `macos/skills/超級模式/SKILL.md` |
| `a02d4f085d08b02fe0fa82de357d4cae2e070e84` | `macos/skills/超級模式/references/orchestration.md` |
| `a17c80be9995f567ba1ce603b3282dc0a28481b8` | `macos/skills/超級模式/tests/gate-cases.json` |
| `5a1356b39ee43633ecf95506d38a440e6987e67e` | `macos/skills/超級模式/tests/matcher-contract.test.js` |

### 3.3 確認你真的在 darwin 上跑（防假 PASS）

```bash
node -e 'if (process.platform !== "darwin") { console.error("NOT DARWIN: " + process.platform); process.exit(2) } console.log("platform=darwin OK, tmpdir=" + require("os").tmpdir())'
```

**這一步 exit 2 就代表整份驗證作廢** —— 曾經有過「在 WSL 裡呼到 Windows node、`process.platform` 是 win32」的假驗證陷阱。

### 3.4 跑測試

```bash
cd "/tmp/opus5-verify/macos/skills/超級模式/tests"
node --check ../../../hooks/super-mode-consult-gate.js && echo "syntax OK"
node run-gate-tests.js
node matcher-contract.test.js
bash run-e2e.sh            # 若這支存在；stdin 端到端
```

**期望輸出**

| 指令 | 期望 |
|---|---|
| `node --check …` | `syntax OK`（無輸出即無語法錯） |
| `node run-gate-tests.js` | `PASS 114/114` |
| `node matcher-contract.test.js` | `PASS matcher-contract (15 個工具名 + mcp__.* 兩邊一致)`、exit 0 |
| `bash run-e2e.sh` | 沿用該腳本既有的全綠判準 |

`run-gate-tests.js` 會**優先載入同樹的 `macos/hooks/super-mode-consult-gate.js`**（相對路徑），
不會吃到你 `~/.claude` 的安裝版。若它印出的 hook 路徑不在 `/tmp/opus5-verify` 底下，停下來回報。

### 3.5 針對本次改動的重點案例（在上面 114 案裡，請確認這幾筆是 pass 而非被跳過）

- `T5 Monitor: ws-only(無 command) denies` ← **最關鍵**，就是 fail-open 那個坑
- `T5 Monitor: 唯讀 tail|grep allows`
- `T5 Monitor: 唯讀 runner 指向 scratchpad denies` ← 這筆吃 `os.tmpdir()`，mac 上才有意義
- `T5 builtin: Artifact without token denies` / `Artifact with fresh token allows`
- `T5 builtin: 未納管 builtin (TaskCreate) 仍放行`

## 4. ⚠️ 不要做這些

- **不要** `cp` 任何檔案到 `~/.claude/`（skill、hook、settings 都不要）。
- **不要**從 `~/.claude/skills/超級模式/tests/` 跑 `matcher-contract.test.js`。
  mac 的 hook 是註冊在 **`settings.local.json`**，而你的 live settings **還沒**加上新的 matcher，
  在 live 跑它一定 FAIL —— 那是預期的，不是 bug。live 部署是 promote 之後才做的事。
- **不要**對這個分支開 PR、merge 或 push 任何東西。
- **不要** force push。
- 驗完請 `git worktree remove /tmp/opus5-verify`。

## 5. 回報格式

把**原始輸出**貼回來（不要只寫「全過」）：

1. `git rev-parse HEAD` 的值，以及 `rebased on b103184 OK` 那行
2. 6 筆 blob 的實際輸出
3. `platform=darwin OK, tmpdir=…` 那行
4. `node run-gate-tests.js` 的最後一行（含數字）
5. `matcher-contract.test.js` 的整行輸出 + exit code
6. 任何 FAIL 的完整訊息

**有任何一項不符就停在那裡回報，不要自行修**。若是測試邏輯本身的問題（例如 mac 特有的路徑等價），
回報現象即可，由 Windows 端決定改法 —— 這樣才能保證「驗的 bytes」與「merge 的 bytes」是同一份。

## 6. 驗證通過後（Windows 端執行，不是你）

- `git fetch` 確認 `origin/main` 未再前進 → `git merge --ff-only <FINAL_HANDOFF_SHA>` → push → `ls-remote` 核對 → 刪遠端驗證分支。
- **promote 進 main 前必須先取得使用者同意**（repo 既有慣例：推驗證分支不用問，推 main 要問）。
- Linux 端另需相同流程的原生驗證（`linux/` 樹，期望同為 `PASS 114/114`）。
