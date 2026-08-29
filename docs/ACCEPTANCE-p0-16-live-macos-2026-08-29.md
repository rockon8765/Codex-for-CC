# P0-16 live 驗收 —— macOS 側（2026-08-29）

> 狀態：**通過（五項全綠）**。Windows 側見 [`ACCEPTANCE-p0-16-live-windows-2026-08-28.md`](ACCEPTANCE-p0-16-live-windows-2026-08-28.md)。
> 至此 **P0-16 兩平台皆達成**，不需要 release waiver。
> 規格：[`exit-code-contract-plan-2026-08-19.md`](exit-code-contract-plan-2026-08-19.md) 的 **P0-16**
> 「部署到 live 並跑 live suite」，判準「repo 改好 ≠ 生效」。

## 1. Attestation

| 項目 | 值 |
|---|---|
| 分支 | `fix/exit-code-contract-closure-2026-08-28` |
| 受驗 tip | `13cd098`（live suite 執行時的 repo checkout） |
| 機器 | Darwin 25.6.0 arm64／`/bin/bash` 3.2.57／brew bash 5.3.15／BSD grep 2.6.0-FreeBSD／node 26.7.0 |
| live skill 樹 vs 分支（@ `021a399`） | **20 個 payload 檔逐位元相符、0 不符**；另有**兩個具名排除項** `scripts/codex-check.sh.bak-20260713`、`scripts/codex-exec.sh.bak-20260713`（部署前即存在，非本輪產生，未刪） |
| live hook | 部署為 tip 版，digest `c66b1503d0917eec`（原為 `b103184` 的 `0d8667de4156a944`） |
| live settings matcher | 就地替換為 snippet 值；`PreToolUse entries` 前後皆 **3**、gate 條目前後皆 **1**（未變兩筆） |

## 2. 結果（五項全綠）

| # | live 檢查 | 尾行 | rc |
|---|---|---|:--:|
| 1 | `run-gate-tests.js` | `PASS 117/117` | 0 |
| 2 | `matcher-contract.test.js --live` | `PASS` ＋ `RESULT_CODE=OK` | 0 |
| 3 | `run-e2e.sh` | `---- 11 passed, 0 failed ----` | 0 |
| 4 | `exit-code-contract.smoke.sh` | `pass=27 fail=0 [sut-bash=5.3.15(1)-release locale=C]` | 0 |
| 5 | `fault-injection.smoke.sh` | `pass=18 fail=0 [sut-bash=5.3.15(1)-release locale=C]` | 0 |

## 3. 走到全綠的過程（兩個根因，都不是本批造成）

達成五項全綠需要修**兩個既有的 live 漂移**。兩者都與本批改動無關
（`git diff 325065c..tip -- '*hooks*'` 完全空白），但都真實存在，記錄如下以免日後重蹈。

### 根因 A —— live hook 陳舊（`b103184`，2026-07-16）

- 症狀：`run-gate-tests` **`PASS 105/117`（12 紅）**、`matcher-contract --live` = `HOOK_UNPARSEABLE`
- 12 紅分佈：Monitor 6／Artifact 2／ScheduleWakeup 1／Worktree 2／A2 子代理分支 1
- **單變量反事實（Windows）**：同組測試、同機、只換 hook —— tip hook `109/109` vs `b103184` `97/109`
- **單變量反事實 (b)（macOS，不碰 live）**：live runner/cases × repo hook = **`PASS 117/117`**
  ⇒ 那 12 紅**全部**來自 hook 版本，與 live 的 runner/cases 無關
- 處置：部署 tip 版 hook → `run-gate-tests` 轉 `117/117`

> ⚠️ **本輪的一個過程教訓**：第二輪曾把這 12 紅回報成「2 紅」（只列了已分析的兩個、未報總數）。
> 是「Windows 反事實預測 12、macOS 回報 2」這個**數字對不上**才逼出重查。
> **歸因看起來成立但數字對不上時，先別放行。**

### 根因 B —— live settings matcher 陳舊（自 2026-07-26 起）

- 症狀：hook 部署後 `matcher-contract --live` **仍**紅，轉為 `MATCHER_DRIFT`
- 缺 5 個工具名：`Monitor`／`Artifact`／`ScheduleWakeup`／`EnterWorktree`／`ExitWorktree`
- 溯源：這 5 個名字是 `09340e3`（2026-07-26）**同時**加進 hook 與 `macos/settings.snippet.json`
  ⇒ 該機 settings 落後約一個月。對照：Windows live settings 五個**全有**，僅 macOS 漂移
- **被遮蔽性**：`matcher-contract` 在 `HOOK_UNPARSEABLE` 時會在做 matcher 契約比對**之前**返回，
  所以根因 B 在根因 A 修好之前是**看不見的**。是 no-deploy 反事實 (a)
  （`--settings <live> --hook <repo>`）讓它在部署前就提早浮出
- 處置：就地替換既有那一筆的 matcher 字串（**非 append**）→ `RESULT_CODE=OK`

> ⚠️ **這個根因暴露了 canonical 指引的缺口**，已於 `13cd098` 修進 `AI-INSTALL` 步驟 2：
> 該步驟的判定矩陣完全 route 在 `tools/probe-gate-registration.js` 上，而**該 probe 不驗 matcher 內容**
> ——本例中它改前改後都回 `OK_NORMAL`。照矩陣字面走會得到「已經裝好了，什麼都不要做」。
> **抓得到 matcher 過時的是步驟 3 的 `--live`。**

## 4. 備份與回滾

| 元件 | 備份 |
|---|---|
| skill 樹 | `~/.claude/skills-backup/超級模式.bak-20260828-172600/` |
| hook | `~/.claude/hooks/super-mode-consult-gate.js.bak-20260828-172600` |
| settings（hook 部署輪） | `~/.claude/settings.json.bak-20260828-172600` |
| settings（matcher 替換輪） | `~/.claude/settings.json.bak-20260829-160420`（另有 `settings.local.json` 同 ts） |

三個元件安裝前皆存在（無 `.absent` 標記）。

## 5. 未涵蓋（不得誤讀為已驗）

1. **Linux 側的 live 驗收未做。** CI 只跑 repo 層（`ubuntu-latest`），不含 live 部署。
2. 本檔只結 P0-16。`SUITE_RESULT`／五項全綠**不等於**「本批全部驗過」——
   例如 `QUOTA-CLASSIFIER` 仍為開放項（見 [`backlog.md`](backlog.md)）。
3. 兩台機器的 settings 現已一致，但**沒有任何機制持續守住這件事**——
   `probe` 不驗內容，`--live` 只在有人跑安裝驗證時才會跑。
