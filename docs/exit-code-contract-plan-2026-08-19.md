# 退出碼契約修復規畫書（2026-08-19）

> **狀態（2026-08-19 最後更新）**：分支 `fix/exit-code-contract-2026-08-19-pending-native-macos`，**尚未合併**。
>
> ## ⚠️ 本文件的定位（2026-08-19 訂正）
>
> 這是**這一批的規畫與過程紀錄**，合併後即為史料。
> **「還沒做什麼」的唯一真相是 [`backlog.md`](backlog.md)**，不是本文件。
> 特別是 **§9.2 的「仍未做」表已被取代**——它曾被當成 backlog 用，
> 造成「plan 說未完成、backlog 記舊實作、驗證散綁三個 commit」的三頭馬車
> （2026-08-19 Codex 第五輪指出，我接受）。查未完成項目請一律看 backlog 的
> `QUOTA-CLASSIFIER`／`TRANSCRIPT-PREFLIGHT`／`POSIX-EXEC-QUIET`／
> `CODEX-CHECK-WARNING`／`BSD-GREP-INVALID-BYTES`／`WINDOWS-CI` 六列。
>
> 讀本文件是為了理解「當時為什麼這樣決定」與「哪些結論是被推翻的」。
>
> **本文件的定位**：這一批的合約。實作時以本文件的驗收標準為準；
> 過程中若發現本文件錯了，**改本文件**，不要讓實作與文件默默分岔。

---

## 1. 一句話

`codex-consult.ps1` / `codex-exec.ps1` 對呼叫端承諾「哨兵訊息 ＋ 專屬退出碼」，
但這個承諾在**至少兩種合法的 PowerShell preference 組合**下會塌成 `rc=1`、哨兵消失；
而且哨兵送錯 stream、分類判準綁在磁碟寫入是否成功上。

---

## 2. 已確立的事實

### 2.1 量測（我在本機實測，非推論）

環境：Windows 11、pwsh **7.6.3**、假 codex（`SUPER_MODE_CODEX_CMD` 接縫）、`-NoProfile`。
受測目標＝**真的** `codex-consult.ps1` 配額路徑，期望 `rc=42` ＋ stderr 有 `CONSULT_UNAVAILABLE_QUOTA`。

| # | `$ErrorActionPreference` | `$PSNativeCommandUseErrorActionPreference` | `$WarningPreference` | rc | 哨兵位置 |
|---|---|---|---|---|---|
| 1 | Continue | false | 預設 | 42 | **stdout**（錯） |
| 2 | Continue | false | Stop | 1 | 例外訊息 |
| 3 | Stop | false | 預設 | 42 | stdout（錯） |
| 4 | **Stop** | **true** | 預設 | **1** | **無** |
| 5 | Continue | true | 預設 | 42 | stdout（錯）＋ stderr 多出 `NativeCommandExitException` |

- 第 2 列 = 原始缺陷（`Write-Warning` 在 `Stop` 下變終止性例外，走不到 `exit`）。
- 第 4 列 = **`cc49808` 沒有修到的第二條路**（native 非零退出直接丟例外，連 `$code = $LASTEXITCODE` 都到不了）。
- 第 1/3/5 列的「哨兵在 stdout」= warning stream 跨 process 會落到 OS stdout，
  呼叫端在 stderr 看不到哨兵，反而污染 `-Quiet` 摘要與 `--output-schema` 的 stdout 解析。

`$PSNativeCommandUseErrorActionPreference` 在本機 `-NoProfile` pwsh 7.6.3 **預設 `False`**
⇒ 第 4 列需要使用者主動打開兩個非預設值。**這降低了發生率，但不改變契約是壞的。**

### 2.2 POSIX 早就做了對應防護（跨平台等價性論據）

`macos`/`linux` 的 `codex-consult.sh:144-154`：

```bash
set +e
codex exec ... < "$brief_tmp" 2> "$err_tmp" | tee -a "$log" | tee "$ans_tmp"
code=${PIPESTATUS[0]}
set -e
```

「呼叫 native 之前解除 shell 的 abort-on-failure、之後還原」在本 repo 是**既有的跨平台約定**。
Windows 漏了這一步。⇒ 修這件事**不是範圍擴張，是補齊等價性**。

### 2.3 Windows 側同一份檔案裡已經有正確先例

`codex-consult.ps1:88-96`（validator）與 `:190-194`（schema check）都是
「存 `$prevEap` → `$ErrorActionPreference='Continue'` → 跑 native → 抓 `$LASTEXITCODE` → 還原」，
而且註解已寫明理由。**只有 codex 本體的呼叫點沒套。**

### 2.4 同型缺陷的完整站點清單

| 檔案 | 行 | 型 | 後果 |
|---|---|---|---|
| `codex-consult.ps1` | 223 | native rc 擷取前可能中止 | rc 塌成 1、哨兵消失 |
| `codex-consult.ps1` | 308 / 311 | `Write-Warning` 緊接 `exit` | 同上（`cc49808` 已改，但不完整） |
| `codex-exec.ps1` | 100 | native rc 擷取前可能中止 | rc 塌成 1 |
| `codex-exec.ps1` | 115 | `Write-Warning` 緊接 `exit` | 同上（`cc49808` 已改） |
| `codex-check.ps1` | 268 | `Write-Warning` 緊接 `UPDATE_BASELINE=REFUSED` ＋ `exit 2` | **哨兵與 rc 一起消失** |
| `codex-check.ps1` | 289 / 293 | `Write-Warning` 緊接 `return` | 整支中止；首次安裝無 baseline 時 smoke 根本不跑 |
| `codex-check.ps1` | 468 | `& cmd.exe` 後才抓 `$smokeExit` | 擷取前中止 |
| `codex-check.ps1` | 513 / 515 | `Write-Warning` 緊接 `Remove-Item` 清快取 | **壞快取不會被刪**，下次非 `-Force` 仍命中舊綠快取，把壞掉的 codex 報成可用 |

### 2.5 `QUOTA-CLASSIFIER` 的實證診斷（2026-08-19，**推翻了 Codex 的一條建議**）

Codex 第二輪建議「分類器直接吃 captured stderr，不再重讀 log」。我照做之後去翻**真實逐字稿**驗證，
發現這條建議建立在一個錯誤的前提上：它假設 stderr 是乾淨的錯誤通道。**在本 repo 不是。**

**方法**：對 `~/.claude/super-mode-logs/` 的 88 份 `codex_consult_*.txt`，
以 `===== STDERR =====` 切成 stdout / stderr 兩段，分別套用現行判準 regex。

**結果**：

| 命中位置 | 份數 |
|---|---|
| 只在 stdout 命中 | **0** |
| 兩段都命中 | 10 |
| **只在 stderr 命中** | **47** |

而這 47 份**幾乎全是成功的諮詢**（exit 0，根本不是配額失敗）。原因是
**codex 把推理軌跡與工具輸出寫到 stderr**，其中包含：

- `FIX-PLAN-macos-2026-07-03.md:401:` —— **grep 的行號前綴**，正是 2026-08-13 事故的同一種東西；
- `CONSULT_UNAVAILABLE_QUOTA` —— codex 讀了**我們自己的原始碼**，那個字串裡就有 `QUOTA`。

⇒ **stderr 是本 repo 最吵的輸入，不是最乾淨的。** 「換 stream」根本不是這題的解法。

**2026-08-13 事故的地面真相**（逐字稿 `codex_consult_20260813_041806_f7b3fe.txt`）：

- `===== STDERR =====` 出現在**位置 0** ⇒ 那次 **stdout 是空的**，整份 303KB 都是 stderr。
- 真正的失敗原因是 codex 自己印的：
  `ERROR: This content was flagged for possible cybersecurity risk...`（OpenAI 內容過濾），**與配額無關**。
- ⇒ **只改成 stderr-only 並不能修掉這次事故**（stdout 本來就是空的，兩者等價）。

**因此判準的問題不是「哪一條 stream」，是「stream 裡的哪一部分」。**
真正的 codex 致命錯誤是**行首 `ERROR: ` 的行、出現在 stderr 尾端**；
誤陽性則散布在中段的推理軌跡裡。

⚠️ **我們手上沒有任何一份「真的配額耗盡」的逐字稿樣本**，
所以**無法從證據寫出精確的正例匹配式**。這一點必須誠實寫進實作，見 P0-14。

---

## 3. Codex 兩輪反方審查：立場與我的裁決

### 3.1 第一輪（`codex_consult_20260819_024544_ffc91c.txt`，裁決 BLOCK）

| Codex 的指控 | 我的複驗 | 裁決 |
|---|---|---|
| 契約在 `EAP=Stop` ＋ native pref 下仍塌成 1 | **屬實**（§2.1 第 4 列，我自己量的） | **採納** |
| backlog 說「改 `codex-check` 會炸掉 runner、必須重做捕捉臺」是錯的 | **屬實**：`codex-check.tests.ps1:277-281` 早就把 EAP 降成 `Continue` 再還原 | **採納**，`cc49808` 的 backlog 敘述要訂正 |
| backlog 說「三平台沒有任何測試提到 `CONSULT_UNAVAILABLE_QUOTA`」與同 commit 自相矛盾 | **屬實** | **採納**，改成「缺的是分類器誤陽性負例」 |
| 新測試沒接上任何例行入口 | **屬實**：`run-gate-tests.ps1` 只跑 JS | **採納** |
| 靜態守衛可被 `write-warning`／模組限定名／行中呼叫繞過 | **屬實**（.NET regex 預設大小寫敏感，我又錨了 `^\s*`） | **採納** |
| `SKILL.md:73` 把 42 寫成「哨兵**或** exit 42」 | **屬實** | **採納**（列為 D-3） |

### 3.2 第二輪（`codex_consult_20260819_083727_e25b6d.txt`，裁決 BLOCK）

| Codex 的立場 | 我的裁決 | 理由 |
|---|---|---|
| **我提的折衷（pipeline 內 `Add-Content -ErrorAction Stop`）是錯的** —— `-ErrorAction Stop` 會刻意凌駕本地 EAP，在擷取 rc 前中止 | **採納，且這是我這輪最大的錯** | 邏輯直接成立：我為了保住 log 完整性，把我正在修的「提前中止」換個地方再犯一次 |
| 第三案：**B ＋ 完整 drain ＋ 延遲裁決** | **採納為主設計**（§4） | 它同時解決 rc 擷取、log 失敗、以及分類輸入來源三個問題 |
| `EAP=Continue` 只避免提前終止，**不等於完整中和**（第 5 列 stderr 會多出 `NativeCommandExitException`） | **採納** | 我自己的量測第 5 列就有這個現象，我原本沒把它當回事 |
| 分類器應直接吃 **captured stderr**，不要重讀 log | **部分採納 —— 前半對、後半錯** | 「判準不該綁在磁碟寫入成功上」完全正確，已採納。但「stderr 是比較乾淨的輸入」這個隱含前提**經實證推翻**（§2.5）：88 份真實逐字稿中，47 份**只在 stderr** 命中配額 regex，且幾乎都是成功諮詢——因為 codex 把推理軌跡與工具輸出（含 grep 行號前綴、含我們自己原始碼裡的 `QUOTA` 字串）都寫到 stderr。**stderr 是最吵的輸入，不是最乾淨的。** 判準的軸線是「文字的哪一部分」而不是「哪一條 stream」 |
| 測試永遠只餵 `exit 7` ⇒ 產品改成寫死 `exit 7` 仍全綠 | **採納** | 這正是「案數守衛不等於牙齒」的同型問題 |
| 假 codex 必須分開控制 stdout / stderr；要有「stdout 含 `401:`、stderr 非配額」負例 | **採納** | 這條同時是 D-2 的測試地基 |
| exec seam 的 `Test-Path` 不夠（要 `PathType Leaf`＋FileSystem provider＋`Assert-CmdSafePath`＋nonce attestation＋child timeout） | **採納** | 我這輪已經誤打真 codex 4 次，timeout 這條是切身之痛 |
| AST 守衛抓不到動態呼叫 ⇒ 規則要改稱「禁止**靜態可解析**的 `Write-Warning`」 | **採納** | 避免又一次宣稱過大 |
| 聚合器要用**顯式 manifest**，不能只用檔數；且必須接進 `AI-INSTALL` 步驟 1a／步驟 3 兩張 canonical 清單 | **採納** | 只補 README 清單確實不算接上入口 |
| `codex-check.tests.ps1` 寫死 `powershell.exe` ⇒ 從 pwsh 啟動 runner 不代表 SUT 在 pwsh 跑過 | **採納** | 碼證屬實 |
| **D-1 清單不完整**：還要含 `:468` smoke 的 native rc 擷取 | **採納**（已併入 §2.4 表） | 我自己複驗屬實 |
| **排序：classifier 不得晚於 transport 單獨部署** | **部分採納**，見下 | |

**關於排序的裁決（我與 Codex 的分歧點）**

Codex 的具體反例成立：`EAP=Stop`＋native=true 環境下，修 transport 之**前**是 rc 1（訊號根本沒送出），
修**之後**會穩定走到整份 log 分類器、`\b401\b` 命中 `401:` 前綴、輸出**錯誤的**配額哨兵＋42。
所以「本批把已知錯誤的 authoritative signal 擴張到新的可達環境」這句話是對的，我原本的反駁沒有涵蓋這個環境。

**但我採納它的結論，主要理由不是它給的風險論據，而是另一個更實際的理由**：
第三案要求分類器改吃 captured stderr、假 codex 要分離 stdout/stderr——
**transport 重構與 classifier 修復是同一次重構**。分兩批做等於把同一組測試裝置寫兩次。

風險論據我認為**成立但偏小**（需要兩個非預設 preference 同時打開，而預設環境的誤判在修改前就已存在）。
我把這一點記在這裡，是因為未來若要縮小範圍，該被重新檢視的是這個論據，不是那個工程論據。

---

## 4. 設計決定

### 4.1 結構化 outcome（核心）

native 呼叫段落產出一個結構，之後**所有**裁決都只看這個結構：

```
{ nativeRc, stdout, stderr, transcriptError }
```

- `stdout` / `stderr`：**在記憶體裡捕捉的原始內容**，在刪除任何 temp 檔之前就取得。
- `transcriptError`：log 寫入失敗時記錄**第一個**錯誤，然後**繼續 drain**，不中止。
- 配額分類器改吃 `stderr`（＋必要時 `stdout`），**不再重讀 log 檔**。

### 4.2 native 呼叫段落的守則

1. 啟動 codex **之前**，以「失敗就中止」的方式建立／開啟 log（此時中止是安全的，還沒有 native rc 要保）。
2. 進入 capture scope：若 `$PSNativeCommandUseErrorActionPreference` 存在則暫設 `$false`；
   同時把 `$ErrorActionPreference` 降為 `Continue`（保護 WinPS 5.1 的 `NativeCommandError` 路徑）。
   兩者都在離開 scope 時還原。
3. 逐行 echo ＋ 收集 ＋ 嘗試寫 log；寫入失敗只記 `transcriptError`，**繼續 drain**。
4. pipeline 完整結束後**立刻**擷取 native rc。
5. 讀取並保留 raw stderr，**之後**才清 temp。
6. 離開 scope，還原 preference，才開始裁決。

### 4.3 雙重失敗的優先序（必須明訂，否則實作會各憑感覺）

| native | transcript | 結果 |
|---|---|---|
| 成功 (rc 0) | 失敗 | **`exit 46` ＋ 專屬哨兵；不得鑄證、不得印 `exec OK`** |
| 非零 | 失敗 | 保留配額分類或原 rc，**另附** transcript 失敗診斷 |
| 非零 | 成功 | 現行語義（42 或原 rc） |

`46` 目前未被使用（已用：12 / 42 / 43 / 44 / 45）。

> ⚠️ **未決**：新增 `46` 會破壞三平台等價性——POSIX 的 log append 同樣可能失敗且同樣沒有處理。
> 要嘛三平台一起加，要嘛都不加而改用其他語義。**本文件傾向三平台一起加**，列為 §5 的 P0-9。

---

## 5. 任務清單

> 驗收標準一律要求：**具名斷言**、**精確退出碼**、**變異注入證明有牙齒**。
> 「全綠」本身不是驗收證據。

### P0（本批必做）

| ID | 任務 | 驗收標準 |
|---|---|---|
| **P0-0** | 改寫 `cc49808` 的 commit 訊息與 backlog 敘述（該 commit 宣稱「契約已修好」是**假的**） | backlog 兩處錯誤敘述訂正；不得留下「已修」字樣 |
| **P0-1** | 依 §4 重寫 `codex-consult.ps1:214-230` 與 `codex-exec.ps1:92-104` 的 native 段落 | §2.1 五種組合全部 rc 正確、哨兵在 stderr、stdout 不含哨兵 |
| **P0-2** | 分類器改吃**記憶體捕捉的 stream**（不回頭重讀 log） | 「log 完全寫不出去」時分類結果**不變**。⚠️ 依 §2.5，這只解決「判準綁在磁碟寫入成功上」這個問題，**完全不解決誤陽性**——換成 stderr-only 對 2026-08-13 那次事故是**等價的**（該次 stdout 為空）。精度問題全部歸 P0-14。 |
| **P0-3** | 三平台 `46`／transcript 失敗語義（§4.3） | 三平台行為等價；POSIX 亦實作 |
| **P0-4** | preference 矩陣測試：pwsh 跑 2³ 完整矩陣（Warning × EAP × native）；WinPS 跑 2²，native 標 N/A | 另**禁止** stderr 出現 `NativeCommandExitException` / `NativeCommandError` |
| **P0-5** | passthrough 至少用**兩個不同** rc（例如 7 與 23）＋ 普通 `rc42` 無哨兵負例 | 產品改成寫死 `exit 7` 必須紅 |
| **P0-6** | 假 codex 改成可**分別**控制 stdout / stderr；新增「stdout 空、stderr 真配額」與「stdout 含 `401:`、stderr 非配額」兩案 | 後者必須**不**產生配額哨兵（這條在 D-2 修完前會紅——刻意，見 §6） |
| **P0-7** | transcript fault injection：log 目錄不是目錄／初次開檔失敗／執行中寫入失敗／stderr append 失敗 | 斷言完整 drain、無成功、無鑄證、符合 §4.3 優先序 |
| **P0-8** | `codex-exec.ps1` 專屬測試接縫 `SUPER_MODE_CODEX_CMD_EXEC` | FileSystem provider ＋ `PathType Leaf` ＋ resolve 後過 `Assert-CmdSafePath`；stub 用 nonce 證明**恰執行一次**；child timeout 防誤打 live codex |
| **P0-9** | 靜態守衛改 AST（`Parser::ParseFile`） | parse error **視為失敗**；遞迴掃 nested AST；模組限定名取最後一節不分大小寫比較；**規則名稱改為「禁止靜態可解析的 `Write-Warning`」** |
| **P0-10** | 聚合器 `tests/run-windows-suite.ps1`：**顯式 manifest**（檔名／args／host／timeout／預期 marker），逐支開新 process | 刪掉真 runner 補 dummy 必須被抓到 |
| **P0-11** | 接進 canonical 入口：`docs/AI-INSTALL.md` 步驟 1a（repo 驗證）與步驟 3（live 驗證）兩張清單 ＋ README 檔案清單 | 只補 README **不算**完成 |
| **P0-12** | 兩 host 全跑，並 **attest 實際 child host／版本** | 特別注意 `codex-check.tests.ps1` 寫死 `powershell.exe` |
| **P0-13** | 位元層驗收：UTF-8 BOM ＋ working-tree CRLF | `.gitattributes` **不會**自動修復被 `sed -i` 洗掉的既有工作檔 |
| **P0-14** | **D-2 併入本批**（見 §3.2 排序裁決）：三平台配額分類器修正 ＋ 三平台回歸測試 | 依 §2.5 的診斷，判準要從「在整段文字裡找子字串」改成「**只認 codex 自己的錯誤行**」：(a) 只掃 stderr **尾端**有限行數；(b) 只比對**行首錯誤標記**（實測樣本為 `ERROR: `）的行；(c) 保留 `\b` 邊界並讓 POSIX 對齊 Windows。⚠️ **手上沒有真配額失敗的樣本** ⇒ 不得宣稱「精確辨識配額」。哨兵文案必須降級為**「疑似配額/認證失敗（未確證）」**，並保留逐字稿路徑讓人自己看。負例（必須不命中）：stderr 中段含 `…md:401:` 的 grep 行號前綴、含本 repo 原始碼裡的 `CONSULT_UNAVAILABLE_QUOTA` 字串、以及 `ERROR: This content was flagged…` 的內容過濾失敗。 |
| **P0-15** | **D-3 併入本批**：消費契約改成「rc 42 **且** 精確哨兵」 | 三份 `SKILL.md` ＋ 三份 `CLAUDE-global-rule.md` ＋ 相關測試註解與操作指引**全部**統一，否則仍會有 consumer 單獨把 raw rc42 讀成配額 |
| **P0-16** | 部署到 live（`docs/AI-INSTALL.md`）並跑 live suite | **repo 改好 ≠ 生效**；本輪就是被這個咬過 |

### D（另批，寫進 backlog）

| ID | 任務 | 為什麼不在本批 |
|---|---|---|
| **D-1** | `codex-check.ps1` 全部站點（§2.4 表後五列，含 `:468` smoke） | 可獨立 commit 放同一分支；但 Codex 指出**同一次 merge／安裝 = 同一個 release**，所以要嘛範圍補完整、要嘛移出本 release。**本文件選擇移出**，理由是 `codex-check` 的 runner 還要改成可選 host，那是另一個工程 |
| **D-2'** | Windows CI（本 repo 目前只有 Linux CI） | 持續交付基礎設施，不是本次契約成立的最低條件 |

---

## 6. 刻意會紅的測試

P0-6 的「stdout 含 `401:`、stderr 非配額」案，在 P0-14 修完之前**必然是紅的**。
這是刻意的：先讓誤判有紅燈，再修判準。**不得為了讓 suite 變綠而先放寬這個案子。**

---

## 7. 已知限制與未涵蓋範圍（先寫，避免事後宣稱過大）

- 本批的動態證據**只在本機一台 Windows 11 上取得**；macOS / Linux 的 POSIX 改動（P0-3、P0-14）
  在本機**無法原生驗證**，需要另外的 pending-native 驗證流程。
- AST 守衛**抓不到**動態命令名（`& $cmd`）與 `$PSCmdlet.WriteWarning()`。
- `$PSNativeCommandUseErrorActionPreference` 的預設值只在**本機 pwsh 7.6.3 `-NoProfile`** 觀測為 `False`；
  其他版本／有 profile 的環境未觀測。
- 「假 codex」只模擬 stdout/stderr/rc 三件事，**不模擬** codex 的逾時、部分輸出、串流中斷。


---

## 9. Codex 第三輪（`codex_consult_20260819_160631_11e561.txt`，裁決 **BLOCK**）

⚠️ **這一輪的重點是：我在修前兩輪問題的過程中，自己引進了四個 Critical。**
「前兩輪的指控全部修完」是真的，但那不等於這批可以合併。

### 9.1 已修（本輪處置）

| 等級 | 缺陷 | 是誰引進的 | 處置 |
|---|---|---|---|
| Critical | POSIX smoke 的 `root="$(mktemp -d)"` 沒有 fail-closed，而本檔是 `set -uo pipefail`（**無 `-e`**）⇒ mktemp 失敗時 `$root` 為空，`rm -rf "$root/home/…"` 變成對**根目錄**動手 | **我，本批** | fail-closed ＋ 絕對路徑檢查 ＋ `safe_root()` 守衛，trap 與每個破壞性操作前都過 |
| Critical | 契約測試 §3a 只設 consult 接縫、刻意不設 exec 接縫 ⇒ exec **fallback 到真的 `C:\npm\codex.cmd`**（workspace-write），而斷言「fake 沒被叫到」**正好因為打了真 codex 而通過** | **我，本批** | 改成 poison stub：兩個接縫**永遠**都指向 stub，隔離用 poison 證明（rc 99 ＋ POISON trace），任何情況都不會 fallback |
| Critical | 聚合器把 matcher 寫死 `--repo`，但我把它接進 `AI-INSTALL` **步驟 3（live）** ⇒ 乾淨 live 安裝 `SETTINGS_UNREADABLE` → 依文件要 rollback | **我，本批** | 加 `-Mode repo\|live`，兩處呼叫點分別帶 `-Mode repo` / `-Mode live` |
| Critical | 聚合器用 `Start-Process -ArgumentList` **陣列** ⇒ 含空白的路徑被拆開、整個 suite 假紅（`consult-credential.tests.ps1` §11 早就記載過這個坑） | **我，本批** | 自己逐一加引號組成單一字串；另加「受測 host 不存在」的明確訊息 |
| High | POSIX 分類器 `printf … \| grep -q` 在 `pipefail` 下，grep 命中即關管線 → printf 得 SIGPIPE 141 → 整條非零 → `if` 判 false ⇒ **明明命中卻漏判**。小輸入塞得進 pipe buffer 看不出來，大逐字稿才會炸 | **我，本批** | 改用 here-string（不開管線）；`grep \| head` 加 `\|\| true`。**補回歸測試**：40 行×10KB 的 quota ERROR；變異注入退回管線寫法 → rc 7、哨兵消失（實測） |
| High | 三平台判準不等價：`ERROR- quota` 只有 Windows 命中；`auth401beta` 只有 POSIX 命中 | **我，本批** | 統一成「ERROR 後接非英數或行尾」與「數字兩側非英數」 |
| High | `exit $code` 在 `$code` 為 `$null` 時實際 **exit 0**（cmd.exe 找不到、native 沒啟動） | 既有 | 拿不到整數退出碼 → 映射成 **127**（＝POSIX 的 command not found，維持等價）＋ 專屬哨兵 |

### 9.2 仍未做（⚠️ **本表已於 2026-08-19 被 [`backlog.md`](backlog.md) 取代**，保留僅為紀錄當時的判斷；**不要**拿它當現況）

| 等級 | 項目 | 為什麼還沒做 |
|---|---|---|
| High | 分類器仍會被 `ERROR: MCP quota-monitor failed to initialize` 這種**含 quota 字樣但與配額無關**的錯誤行誤判；反向地，真配額 ERROR 後若有超過 40 行清理訊息就漏判 | 沒有真配額樣本可校準，調任何閾值都是猜。列 backlog |
| High | log 目錄建立與 temp brief 寫入仍在 transcript 的 catch 之外 ⇒ EAP=Stop ＋ 唯讀父目錄/滿碟時直接 rc 1，沒有 46 哨兵 | 未做 |
| High | POSIX `codex-exec.sh` 的 `-q` 分支仍直接 `>> "$log"`，log 失敗時分不出 transport failure 與 codex rc，也不保證 drain | 未做 |
| Blocker | **原生 macOS 驗證：已完成（2026-08-19）**，見 [`HANDOFF-macos-exit-code-contract-2026-08-19.md`](HANDOFF-macos-exit-code-contract-2026-08-19.md)。bash 3.2.57 ＋ BSD userland：smoke 19/0、gate 117/117、`run-posix.sh` **95/0**（Windows 上的 30 個 symlink FAIL 全部消失 ⇒ 證實是環境天花板不是缺陷）、兩個 mutant 都照預期變紅 ⇒ 守衛在 3.2/BSD 下確有牙齒。⚠️ **但覆蓋矩陣仍缺一格：bash 5.x × BSD userland**（該機 PATH 的 bash 就是 /bin/bash，驗證者自己指出 B 區塊恆真、無獨立價值）。那不是假想組合——Homebrew bash 會排在 PATH 前面。⚠️ **原生 Linux 仍未驗**。 | 部分完成 |
| Medium | Linux CI 只跑 `bash -n`，沒有真的執行測試 | 未做 |
| Low | `Resolve-CodexOverride` 在 consult/exec 完整重複 | PowerShell 無共用 lib，與 `Assert-CmdSafePath` 同樣的既有取捨 |

### 9.3 Codex 說對、我接受的一句話

> 「『疑似、未確證』只改善文字誠實度，沒有改善 recall 或 precision。
> 消費端仍把『哨兵＋42』當權威控制訊號；假陽性仍停止重試，假陰性仍完全沒有訊號。」

⇒ **不得**把「文案降級」當成分類器的驗收理由。真正的驗收要等到有真配額樣本。

---

## 8. 過程中我自己引進的缺陷（留紀錄）

1. 用 Git Bash 的 `sed -i` 改 `.ps1`，把 313 個 CRLF 洗成 LF（repo 規定 CRLF）。已還原、改用 Python 重做並逐位元複驗。**教訓：Git Bash 的 `sed -i` 會吃掉 CR，不要用它改 CRLF 檔。**
2. 測試 wrapper 用 `Start-Process -ArgumentList` 傳空字串會整組位移；**PowerShell 陣列 splat 會變成位置參數**（`-Dir` 不被認成參數名）。兩者都會讓案子「以錯誤的理由通過」。已改 hashtable splat ＋ 環境變數傳參。
3. `cc49808` 宣稱「退出碼契約已修好」——**假的**，只修了兩條路裡的一條。
4. **測試會誤打真 codex**：§3a 讓 exec 接縫留空 ⇒ fallback 到真的 `C:\npm\codex.cmd`，而斷言「stub 沒被叫到」正好因此通過。**我聲稱防住的東西，被我自己的測試繞過。**
5. **POSIX smoke 可能對根目錄 `rm -rf`**（`mktemp -d` 未 fail-closed）。
6. **聚合器讓乾淨 live 安裝必敗**（matcher 寫死 `--repo`）＋ **含空白路徑會假紅**（`Start-Process -ArgumentList` 陣列不保留 argv 邊界——這個坑 repo 內早有記載）。
7. **POSIX 分類器 SIGPIPE 靜默失效**（`printf | grep -q` ＋ `pipefail`）。
8. 探針誤打真 codex 4 次（`codex-exec.ps1` 沒有測試接縫，我沒先確認就跑）。P0-8 的 child timeout 就是為了防這個。

---

## 10. Codex 第五輪（`codex_consult_20260819_203617_f5faec.txt`，裁決 **BLOCK**）與處置

8 項解除條件它判「1、2、7 實質達成；3、4、5、6 部分達成；8 規則有牙齒但整合未達成」。
最嚴重的一條我完全同意：

> **我上一輪才修掉「聚合器寫死 `--repo` 導致乾淨 live 安裝必敗」，這一輪加靜態守衛時
> 用同一個模式再犯一次** —— 把 repo-only 的 `tests/no-multibyte-varref.test.js`
> 塞進 repo/live 共用 runner。實測 live 會解析成 `%USERPROFILE%\tests\…`（不存在）。

處置一覽：

| 指控 | 處置 |
|---|---|
| Critical：`-Mode live` 必敗 | manifest 每列可宣告 `Modes`；被 mode 濾掉的**印出來**並計入摘要的 `skipped`。實測 repo 9/9、live ran=8 skipped=1 fail=0 |
| smoke 的 harness attestation 用 `bash --version`（PATH 上的 bash）冒充身分 | 改用 `${BASH_VERSION}`。**attestation 自己說謊比沒有 attestation 更糟** |
| `SMOKE_ALLOW_NO_UTF8_LOCALE=1` 補三個假 PASS，尾行仍 22/0 | 改成降低期望案數，並在**摘要行**加 `LOCALE-DIMENSION-NOT-COVERED` 標記；CI 會 grep 它 |
| HANDOFF 兩處 `$var` 緊接全形字元（它是可貼上執行的 bash） | 已修，並把「注入成功前置檢查」與 `grep -cF` 慣例寫進交接單 |
| 「13 個 commit」 | 實際 **14**，已訂正 |
| backlog 仍描述已淘汰的狀態、plan 冒充 backlog | 本次處理：backlog 重寫成七列現況、檔頭訂立**文件分工**；plan 自我降級為史料 |
| 原生 Linux 是硬阻擋 | 已解決，見下 |

### 10.1 原生 Linux：CI 抓到一個只有真 Linux 會露出來的缺陷

本機 WSL2 是真 GNU/Linux（bash 5.3.9、ext4、`C.utf8`、chmod 有效）但**沒有 node**，
而受測腳本的判準 preflight 需要它 ⇒ 實跑得到 **18 個「實得 45」的假失敗**。
那 18 個全是同一個環境原因的迴聲，卻看起來像 18 個獨立的產品缺陷
⇒ 因此新增 `PREREQ-MISSING` 前置檢查（一句話 ＋ `exit 3`）。

改走 GitHub `ubuntu-latest`（自帶 node，且不必更動使用者的機器），並**永久接進**
[`linux.yml`](../.github/workflows/linux.yml)。第一次跑就抓到：

> `§4c` 的 SIGPIPE 案在 Linux 上 **rc=126（exec 失敗）—— 連 stub 都沒跑起來**。
> 原因是我把 ~400KB 的假 stderr 用**環境變數**傳，撞上 Linux 的
> `MAX_ARG_STRLEN`（單一 argv/env 字串 131072 bytes）。macOS 與 Cygwin 沒有這條限制。

⇒ **那個案子在 macOS 22/0、Git Bash 22/0，兩邊全綠，在 Linux 上卻從來沒執行過。**
兩個非 Linux 環境的綠燈加起來，也證明不了第三個環境。這正是 Codex 堅持要原生 Linux 的理由。

修法：stdout/stderr 內容落檔、環境變數只傳路徑（與 Windows 版的 fixture 檔一致）。
之後 CI 綠：**`pass=22 fail=0` @ `8eb4e08`**，bash 5.2.21、`locale=C.UTF-8 charmap=UTF-8`。

### 10.2 靜態守衛在本輪抓到我三次，全部在中文註解裡

用中文寫關於變數的說明時，後面自然會接全形標點 ⇒ `$VAR，` 命中規則。
這**不是誤報**：shell 不區分註解，註解裡的寫法會被複製進程式碼。
三次我都改寫措辭、**沒有**放寬守衛，並把「在 CJK 文字旁提到變數一律寫 `${VAR}`」
寫進守衛檔頭。**笨而嚴的規則比會解析註解的聰明規則可信。**
