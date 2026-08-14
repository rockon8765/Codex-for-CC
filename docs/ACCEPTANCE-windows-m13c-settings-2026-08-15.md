# 驗收紀錄 — F2：Windows `[M13c]` 補上 settings 目標（2026-08-15）

對應 backlog 的 `F2`。**本文件只記錄本分支上跑出來的證據，不代表 `main` 的狀態。**

## 受測版本

| 項目 | 值 |
|---|---|
| 基準 | `main` = `22bb8c4ac00bb68338c7c0f11157dd561a425da7`（2026-08-15 `git ls-remote` 觀測，**非現值**） |
| SUT `tests/ai-install/run-windows.ps1` | blob `bfec1fafaf48e7108c81a50d2ed73fb0ff6b9227`（＝ `22bb8c4..eb5cdd7` 的淨差異） |
| 受測文件 `docs/AI-INSTALL.md` | blob `a2b3d69f676112f138e2d48deb459c80afadafc8`（**與 `22bb8c4` 相同，未隨本批變動**） |
| 反向驗證文件 | blob `46c3cb010182b7ad7911e2b6d842254f8a860635`（＝ `4a96698:docs/AI-INSTALL.md`，抽出後 `git hash-object` 比對相符） |
| host A | `pwsh` 7.6.3 |
| host B | Windows PowerShell 5.1.26100.9168 |

**刻意未帶入** `22bb8c4..eb5cdd7` 區間的其他改動：`tests/ai-install/run-posix.sh`、
兩份 macOS handoff、`README.md`、`docs/backlog.md` 的 POSIX 相關敘述。
那些屬於已裁示 ⛔ 停擺的 POSIX 批次（`snap` 需重新設計），**不得隨本批進 main**。

**為什麼不是 `9c24946`**：`22bb8c4..3450219` 之間只有 `9c24946` 與 `eb5cdd7` 動過本檔，
`eb5cdd7` 才補上兩條防假綠——驗「來源本來就在 anchor 之後」與「產出與原檔確實不同」。
`9c24946` 的 blob 是 `e2b69652…`，**已知缺這兩道牙齒**（下方 control 2 就是它抓不到的那個 mutant）。

## 正向與反向

| host | 受測文件 | 摘要 | rc |
|---|---|---|---|
| `pwsh` 7.6.3 | 現行 | `PASS=126 FAIL=0` | 0 |
| WinPS 5.1 | 現行 | `PASS=126 FAIL=0` | 0 |
| `pwsh` 7.6.3 | `4a96698` | `PASS=112 FAIL=14` | 1 |
| WinPS 5.1 | `4a96698` | `PASS=112 FAIL=14` | 1 |

反向的 14 條**具名失敗集合恰為**：`[M11]` 4 條、`[M13]` 4 條、`[M13c]` 6 條（hook／settings 各 3）。
兩 host 逐行 `diff` 無差異。⚠️ 每次都核對 log 首行的**實際 `-Doc` 路徑**，
避免「靜默退回預設文件」那種假綠（本 repo 在 POSIX 側踩過）。

## Mutation control（三個，全部案數不變或由守衛攔下）

| # | 注入 | 結果 | 證明了什麼 |
|---|---|---|---|
| 1 | `Set-Step2Settings` 的寫入行改成 no-op（保留 `Check`） | `PASS=121 FAIL=5`、rc=1 | 🔴 **settings 目標的牙齒來自 fixture**。四條「前置：settings 已與備份不同」變紅，**且 `[M13c][settings]` 的寬 oracle 也變紅**——沒有 step2，settings 型 mutant 就是 OLD→OLD、寬 oracle 也看不到。**這就是 `main@22bb8c4` 現況的直接復現。** `[M13c][hook]` 的寬 oracle 仍綠（hook 目標不依賴 step2） |
| 2 | **改產品文件**：把 hook 還原的相鄰兩行搬到第一個 `Assert-NoReparseUnder` **之前**（行數不變） | `PASS=123 FAIL=3`、rc=1 | `[M13c][hook] 來源錨點…且來源在 anchor 之後` 變紅＝**`eb5cdd7` 補的那道守衛有牙齒**（`9c24946` 抓不到）。**額外收穫**：`[M13]` 兩條「中止後整個假家目錄未變」也變紅——這個 mutant 是真實的產品順序缺陷，fail-closed 契約測試本身就攔得住 |
| 3 | 刪掉 `[C3]` 一條無副作用的 `Check` | `PASS=125 FAIL=0`、**`STOP 案數不符`**、rc=1 | 案數守衛擋得住「少一案」 |

每個注入都先做自我檢查才執行：錨點命中數必須為 1、前後文比對、行數變化符合預期、檔案 hash 確實改變；
跑完一律 `git checkout --` 還原並以 hash 複驗。

⚠️ **案數守衛只是最後一道結構保險，不能替代上面三類證據。**
2026-08-14 實測：刪掉某案的 stimulus、保留 assertion，變數沿用上一次的成功結果 →
**案數不變、全綠、exit 0，mutant 存活**。

## 這批**只能**宣稱什麼

> 既有安裝（copy arm）情境下，hook 與 settings 的**內容型**提前還原可被觀測。

**不得**擴張成「完整 M13」。**仍未涵蓋**：`.absent`（刪除）分支、純 ACL mutation、
「途中改壞再改回」的事件型副作用、被快照刻意排除的 `AppData\Local\Microsoft\PowerShell` 子樹、
以及 **Windows 側仍然無 CI**。POSIX 側的同型缺口不在本批範圍。

## 平台門

本批**只動 Windows harness**，`docs/AI-INSTALL.md` 的產品 bytes 未變
⇒ 正確的平台門是**原生 Windows 的 5.1 ＋ 7.x**，**不需要三平台重驗**。
若日後動到產品文件、POSIX harness 或三平台 payload，驗收範圍必須重新擴大。

## 原始 log

`~/.claude/super-mode-logs/f2-windows-m13c-20260815/`
（`a-{pwsh,powershell}-{fwd,rev}.log`、`m1-step2-noop.log`、`m2-hook-moved-before-scan.log`、`m3-minus1check.log`）
