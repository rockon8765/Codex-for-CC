# 驗收紀錄 — F2：Windows `[M13c]` 補上 settings 目標（2026-08-15 起，2026-08-17 收尾）

對應 backlog 的 `F2`。**本文件只記錄本分支上跑出來的證據，不代表 `main` 的狀態。**

> **2026-08-17 收尾**（合併前 Codex 審查 BLOCK，三項全屬實，逐項已查證）：
> 1. F2 關閉條件 (d) 要求 hook／settings **各自**預移的 mutation control，08-15 只做了 hook
>    → 已補 **control 4**（settings 預移），兩 host 皆 `122/4`。
> 2. 分支尖端 `backlog.md` 仍寫 `F2` OPEN、且「`112` 案仍無 CI」→ 已改（並註明案數唯一權威是
>    `$EXPECTED_CHECKS`，不要抄文件裡的數字）。
> 3. `run-windows.ps1` 註解宣稱 POSIX「同日一起修」→ 不實，已改。
>    ⚠️ **另查到第二處 Codex 沒點到的**：同檔 `[M13c]` 註解寫「（POSIX 側有釘失敗訊息）」，
>    但 `main` 的 `run-posix.sh` 同樣只判 `rc -ne 0`，那個「有釘」只存在於已停擺的分支。一併移除。
>
> 收尾過程另外訂正了本檔兩處**自己的**錯誤：control 2 的數字、以及「兩 host 逐行 diff 無差異」
> 這個不可能成立的宣稱。詳見下方各節。

## 受測版本

| 項目 | 值 |
|---|---|
| 基準 | `main` = `22bb8c4ac00bb68338c7c0f11157dd561a425da7`（2026-08-15 `git ls-remote` 觀測，**非現值**） |
| SUT `tests/ai-install/run-windows.ps1`（08-15 那輪） | blob `bfec1fafaf48e7108c81a50d2ed73fb0ff6b9227`（＝ `22bb8c4..eb5cdd7` 的淨差異） |
| SUT `tests/ai-install/run-windows.ps1`（**08-17 收尾後、本批最終**） | blob `aeee60bc0792b032ca2da71b3b22713bdd221550`（與上一列的差異**僅為註解**，已用 `git diff -U0` 逐行確認無非註解變更） |
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

| 輪次 | host | 受測文件 | 摘要 | rc |
|---|---|---|---|---|
| 08-15 | `pwsh` 7.6.3 | 現行 | `PASS=126 FAIL=0` | 0 |
| 08-15 | WinPS 5.1 | 現行 | `PASS=126 FAIL=0` | 0 |
| 08-15 | `pwsh` 7.6.3 | `4a96698` | `PASS=112 FAIL=14` | 1 |
| 08-15 | WinPS 5.1 | `4a96698` | `PASS=112 FAIL=14` | 1 |
| **08-17（最終 SUT）** | `pwsh` 7.6.3 | 現行 | `PASS=126 FAIL=0` | 0 |
| **08-17（最終 SUT）** | WinPS 5.1 | 現行 | `PASS=126 FAIL=0` | 0 |
| **08-17（最終 SUT）** | `pwsh` 7.6.3 | `4a96698` | `PASS=112 FAIL=14` | 1 |
| **08-17（最終 SUT）** | WinPS 5.1 | `4a96698` | `PASS=112 FAIL=14` | 1 |

08-17 這四趟是**獨立重跑**，不是沿用 08-15 的數字；反向用的舊文件抽出後
`git hash-object` ＝ `46c3cb01…`，與本檔上表釘的 blob 相符。

反向的 14 條**具名失敗集合恰為**：`[M11]` 4 條、`[M13]` 4 條、`[M13c]` 6 條（hook／settings 各 3）。
⚠️ `[M11]` 那 4 條的斷言字串**沒有 `[M11]` 前綴**（是裸的 `[備份子樹]`／`[live 子樹]`），
歸屬靠 log 的區段標題判定 —— 這是 backlog 已記載的標籤重複問題，不是本批引進的。
⚠️ 每次都核對 log 首行的**實際 `-Doc` 路徑**，避免「靜默退回預設文件」那種假綠（本 repo 在 POSIX 側踩過）。

### ⚠️ 「兩 host 逐行 `diff` 無差異」不成立（2026-08-17 訂正）

本檔原本這樣寫。**實測不對**，而且不可能對：

- 斷言字串裡嵌了 `ts`（時間戳記），兩次執行本來就不同 → 正向 10 處、反向 8 處字面差異。
- 其中 **`[C2]` 有一條是時鐘競態分支**：同一位置在 `pwsh` 印 `不同秒重跑允許`、在 5.1 印 `同秒重跑被拒`。
  這**不是** host 差異，是「第二次執行有沒有落在同一秒」的隨機結果，同一 host 重跑也會變。

**成立的不變量改成這個**（本輪實測）：把 `\d{8}-\d{6}` 正規化後，兩 host
**逐位置的 PASS／FAIL 判定完全相同**（正向 126/126、反向 126/126，`逐位置判定完全相同=True`）。
引用時請用這句，不要用「逐行 diff 無差異」。

## Mutation control（**四個**，2026-08-17 全數對最終 SUT 重跑，host＝`pwsh` 7.6.3）

| # | 注入 | 結果 | 證明了什麼 |
|---|---|---|---|
| 1 | `Set-Step2Settings` 的寫入行改成 no-op（保留 `Check`） | `PASS=121 FAIL=5`、rc=1 | 🔴 **settings 目標的牙齒來自 fixture**。四條「前置：settings 已與備份不同」變紅，**且 `[M13c][settings]` 的寬 oracle 也變紅**——沒有 step2，settings 型 mutant 就是 OLD→OLD、寬 oracle 也看不到。**這就是 `main@22bb8c4` 現況的直接復現。** `[M13c][hook]` 的寬 oracle 仍綠（hook 目標不依賴 step2） |
| 2 | **改產品文件**：把 **hook** 還原的相鄰兩行搬到第一個 `Assert-NoReparseUnder` **之前**（行數不變） | `PASS=122 FAIL=4`、rc=1 | `[M13c][hook]` 的**兩道守衛都變紅**：「來源在 anchor 之後」＋「產出與原檔確實不同」——**`eb5cdd7` 補的正是這兩道**（`9c24946` 兩道都沒有）。**額外收穫**：`[M13]` 兩條「中止後整個假家目錄未變」也變紅——這個 mutant 是真實的產品順序缺陷，fail-closed 契約測試本身就攔得住 |
| 3 | 刪掉 `[C3]` 一條無副作用的 `Check` | 實跑 125、**`STOP 案數不符`**、rc=1 | 案數守衛擋得住「少一案」 |
| **4** | **改產品文件**：把 **settings** 還原的相鄰兩行搬到第一個 `Assert-NoReparseUnder` **之前**（行數不變） | `PASS=122 FAIL=4`、rc=1 | **本批新增，08-15 驗收缺的就是這一個。** 與 control 2 完全對稱：`[M13c][settings]` 兩道守衛都變紅＋`[M13]` 兩條。⇒ settings 目標**不是**靠 hook 目標順帶通過，它自己的守衛獨立有牙齒。**同一注入在 WinPS 5.1 也是 `PASS=122 FAIL=4`、rc=1，失敗集合逐條相同** |

### ⚠️ 訂正：08-15 的 control 2 數字是錯的

本檔原記 control 2 ＝ `PASS=123 FAIL=3`。**2026-08-17 重跑實測為 `122/4`。**
多出來的那一條是 `[M13c][hook] 產出：…且確實與原檔不同`。這條**必然**會紅：
把兩行搬到 anchor 正前方之後，harness 自己的 `Move-TwoLinesBefore` 變成 no-op
⇒ `$m13cMut -cne $Brb` 為 false。control 4 對 settings 得到同樣的 4 條，兩者對稱。
⇒ 判定**原本的 3 是漏記**，不是行為變了（SUT 這兩輪只差註解）。

### 注入紀律

每個注入都先做自我檢查才執行：錨點命中數必須為 1、兩行相鄰、行數變化符合預期、檔案 hash 確實改變；
任何一條不成立就中止且**不產出檔案**。變異 SUT 用完即刪，跑完 `git status --porcelain` 複驗工作區。

⚠️ **本輪自我檢查真的擋下兩次錯誤，兩次都是我引進的**：

1. **control 1 的錨點命中 2 次**——那行 `Set-Content …settings.json … {"new":true…}` 在檔案裡有兩份：
   `[C1]` 的行內版（未縮排）與 `Set-Step2Settings` 內（縮排兩格）。未錨定就會同時改掉兩處。
   修法＝錨點帶上換行與縮排。**這是本 repo 反覆踩的「未錨定／子字串比對」同一形狀。**
2. **變異 SUT 放錯目錄**——harness 用 `$PSScriptRoot\..\..` 定位 repo，把 mutant 放到 scratchpad
   會解析到不相干的目錄，1c 抄不到 payload ⇒ 得到 `108/18`、`125/13` 兩組**看起來殺很大、實際無效**的數字。
   修法＝mutant 一律寫回 `tests/ai-install/` 再跑。⚠️ 這組無效數字**沒有**被寫進上表，
   記在這裡是因為「mutant 殺很多」正是最容易被當成好消息收下的假訊號。

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

08-15 那輪：`~/.claude/super-mode-logs/f2-windows-m13c-20260815/`
（`a-{pwsh,powershell}-{fwd,rev}.log`、`m1-step2-noop.log`、`m2-hook-moved-before-scan.log`、`m3-minus1check.log`）

**2026-08-17 收尾這輪**（log 落在 session scratchpad，會被清掉，所以在此釘 sha256——
log 本身不是耐久證據，能重現的是下面的「怎麼重跑」）：

| 檔 | sha256 |
|---|---|
| `final-fwd-pwsh.log` | `29E6EFEC1927C7B3301EED7750127B603A73BB1CA80E581C1648914A085A246C` |
| `final-fwd-powershell.log` | `BDAF6019AC586071D7321DD0E103D3E8E630650BB6C73BB981BD550C562F36EA` |
| `final-rev-pwsh.log` | `77AA1C21D40B4AA286935C8262217905AEF872FFF91F51C4EA7280A03D9714AD` |
| `final-rev-powershell.log` | `35F83F7C3F588919D409C09B87DE341DC83A22CD694DD0264E9CBC2E83AE0E57` |
| `ctrl-c1-step2-noop-pwsh.log` | `9404F1E7C539837810FDA22DEB0D68ABE0AEF691F3E26011AA93DC3A07DAA922` |
| `ctrl-c2-hook-premove-pwsh.log` | `7541AE65C05283A53229A465752E5AD94EF09CA91144D635F775B5F98751035D` |
| `ctrl-c3-minus-one-check-pwsh.log` | `E18DFFE78FDF235D47A2C49090C3F1BC495EB7ABF02FAFB97702E3F570EE0900` |
| `ctrl-c4-settings-premove-pwsh.log` | `CCB42450C0C2C10999EA238A5C1C18CE9CF4571A24F5C05F15519827894D9CC1` |

變異產物（改產品文件那兩個）：`doc-c2.md` sha256 `5CF842FEF065EA7736EA6F138356FC38DDAE60081597B7999693D03328C391B0`、
`doc-c4.md` sha256 `F9DF911E16AF50E1585F735342746F6784A6911AA5578573C5AC159FE77426FD`。

⚠️ **log 存在 repo 外＝不是可獨立稽核的證據**（合併前 Codex 審查點名）。
在 Windows 接上 CI 之前這是結構限制，不是本批能解的；本檔的態度是
「釘 hash ＋ 寫清楚怎麼重跑」，不是假裝 log 有耐久性。接 CI 後應改存 artifact。

## 怎麼重跑（不依賴上面的 log）

```powershell
pwsh -NoProfile -File tests\ai-install\run-windows.ps1 -Shell pwsh
```

反向驗證：把 `4a96698:docs/AI-INSTALL.md` 抽到暫存檔（`git hash-object` 應為
`46c3cb010182b7ad7911e2b6d842254f8a860635`），用 `-Doc <該檔>` 再跑一次，
**核對 log 首行印出的實際路徑**。`-Shell powershell` 換 5.1。
四個 mutation control 的注入規則見上表，每個都要先過自我檢查。
