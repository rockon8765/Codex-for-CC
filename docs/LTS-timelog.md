# LTS 工時記錄

> 規則見 [`LTS-ADMISSION-PLAN.md` §3.4](LTS-ADMISSION-PLAN.md#budget)：當下記起訖時間；估計值標「（推論）」；每月和 commit、consult 逐字稿的時間戳對帳一次，差距超過 25% 就標記。
> 2026-10-17 起不設總工時上限與截止日（使用者裁決，見[備忘 §8.9](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)；原為 115h／2027-01-15）；工時照記，只當紀錄。類別對應計畫 §3.1 的分配表（數字只是預估與預警）。
> 公開文件：證據欄只寫 commit、文件或「本機逐字稿（不進 repo）」，不寫個人路徑。

| 日期 | 起訖 | 時數（h） | 類別 | 內容 | 證據 |
|---|---|---:|---|---|---|
| 2026-10-14 | ≈00:50–04:15 | ≈3.4 | P 規劃 | 規劃與分析：Claude 主代理與子代理的唯讀調查、准入計畫草稿 v1–v3、兩輪子代理審查、Codex 反方審查（起點 00:50 是本 session 開始時間的估計，推論；草稿 v3 曾記為 01:17，兩者差異未核對。終點與時數同為估計） | [備忘 §8](DECISION-MEMO-lts-2026-09-30.md#lts-decision-2026-10-14)；[`LTS-ADMISSION-PLAN.md`](LTS-ADMISSION-PLAN.md)；本機 consult 逐字稿（不進 repo） |
| 2026-10-14 | 08:30–11:15 | ≈2.75（推論：牆鐘時間，主要是代理執行） | S0 治理文字＋W-CI＋W-MUST（拆分待結算時補記） | 批次 1：備忘 §8、AGENTS.md 建置期段、CLAUDE.md、README 橫幅、Linux 凍結第一階段文件、backlog 同步、本檔與准入計畫；`windows.yml` 與測試 host 參數化（C1／C3）；F2 off 清理修正（Windows／macOS） | 批次 1 commit（2026-10-15 建立） |
| 2026-10-15 | ≈01:20–02:45（起點推論：當天第一次 consult 是 01:31） | ≈1.4（推論：牆鐘時間，主要是代理與測試執行） | 審查＋W-CI＋W-MUST | 批次 1 commit 前：Codex 反方諮詢、多代理審查、使用者四項裁決；F2 白名單收緊、consult-schema 家目錄隔離、文件訂正；全套重跑；定位 [`CONSULT-TOKEN-REPLACE-FLAKE`](backlog.md#CONSULT-TOKEN-REPLACE-FLAKE) | 批次 1 commit；[備忘 §8.7／§8.8](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-15)；本機 consult 逐字稿（不進 repo） |
| 2026-10-17 | ≈00:58–03:55（起點推論：本 session 的暫存目錄建於 01:03） | ≈3.0（推論：牆鐘時間，主要是代理執行） | 保留（歸類為推論，使用者可改） | 上游漂移稽核（Claude Code 2.1.295／2.1.301、Codex CLI 0.163.0）：6 條研究線、9 個對抗驗證、Codex 反方一輪；依使用者裁決做事實訂正與 backlog 10/17 登錄，並做本機 consult 設定與 codex-check baseline 更新；commit 前 4 鏡頭多代理審查；之後依使用者裁決取消工時上限與截止日，並記錄 AGENTS.md 建置期段的逐字核准；再修計畫 §8 殘留的上限文字、DOC-FIX 編號改名、補記審查輪數、建 10/28 檢查點報告骨架 | 本日兩個 commit；[`AUDIT-upstream-drift-2026-10-17.md`](AUDIT-upstream-drift-2026-10-17.md)；[backlog 10/17 登錄](backlog.md#drift-1017)；本機 consult 逐字稿（不進 repo） |
| 2026-10-17 | ≈20:20–21:35（推論：10/28 報告 §3 最後修改於 20:48，本段暫存目錄建於 21:14） | ≈1.3（推論：牆鐘時間） | 保留（歸類為推論，使用者可改） | 10/28 檢查點報告 §3：寫入 Mac 環境盤點與使用者確認（驗收機、時段、T1–T7、Codex 安裝方式）；給 Mac 的盤點與 F2 同步提示；依使用者改裁決還原本機 consult 設定，並在 backlog、稽核補記；把單次 push 紀錄集中到備忘 §8.10 | [`CHECKPOINT-lts-2026-10-28.md`](CHECKPOINT-lts-2026-10-28.md)；[backlog 10/17 登錄 D 段](backlog.md#drift-1017-decisions) |
| 2026-10-17～18 | ≈21:35–01:15（推論：起點接上一列；最後一輪審查結束於 01:03） | ≈3.7（推論：牆鐘時間，主要是代理、測試與 Codex 執行） | W-MUST＋審查 | 備忘 §8.10 push 紀錄集中（`040b344`）與本機安裝同步（F2）；使用者 10/17 晚上四項裁決（備忘 §8.11）後，五項新 MUST（F4、`CONSULT-TOKEN-REPLACE-FLAKE`、`CC-NOBASH-FAILCLOSED`、`CODEX-CHECK-CP437`、`CODEX-CHECK-WARNING`）：設計與原型、Codex 設計諮詢（第 1 輪）、三組平行實作、合併後兩 host 全套驗證、Codex 最後一輪審查（第 2 輪）、backlog／計畫／本檔更新 | 本機逐字稿（不進 repo）；backlog 各列 2026-10-18 補記 |
| 2026-10-18 | ≈01:15–03:00（推論：接上一列；本段 Codex 審查結束於 02:4x） | ≈1.75（推論：牆鐘時間，主要是測試與 Codex 執行） | W-MUST＋審查 | `e250db0` 提交與推送（CI 兩個 workflow 首次即綠）；F4 Mac 真機驗證結果寫回文件（F4 關閉）；`CODEX-CHECK-SH-STDERR` 列 MUST（備忘 §8.12）、實作、牙齒驗證、Codex 第 1 輪審查、Mac 驗收提示 | 本機逐字稿（不進 repo）；backlog 該列 2026-10-18 補記 |

**累計**：≈17.4h（不設上限，不再計算剩餘）

<a id="review-rounds"></a>
## 審查輪數帳（計畫 §3.2）

> 一輪＝對同一個 ID 的 diff 呼叫一次審查；同一次呼叫涵蓋幾個 ID 就各記一輪；每個 ID 最多 2 輪。計數採計畫 §3.2 的保守細則：一次 workflow 對它涵蓋的每個 ID 各記一輪；讀了該 ID 的 diff 或實作的 Codex 諮詢另記一輪。

| 日期 | 審查 | 涵蓋 ID | 結論 |
|---|---|---|---|
| 2026-10-14 | 批次 1 合併前審查（Claude 子代理；呼叫次數未記錄，以 1 次計，推論） | G1、G2、G4、G5、G6、C1、C3、F2 | 指出的問題已在批次 1 內修正（證據見各檔「2026-10-14 合併前審查」註解） |
| 2026-10-15 | Codex 反方諮詢（讀了 F2 實作與 CI／suite 的計數） | F2、C1、C3 | 部分反對；處置見[備忘 §8.8](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-15) |
| 2026-10-15 | commit 前多代理審查（5 個維度，各配 1 個對抗驗證） | G1、G2、G4、G5、G6、C1、C3、F2 | 存活 11 條；兩類阻擋問題依規則交使用者裁決（備忘 §8.7） |
| 2026-10-17 | Codex 反方諮詢（10/17 上游漂移稽核；讀了 `AGENTS.md` 作為規則依據） | G2 | 依保守計法記一輪；諮詢主題是上游漂移，沒有提出 G2 的阻擋問題（推論：讀檔是為了引用規則，不是審查 G2）。使用者 2026-10-17 確認保留這一輪 |
| 2026-10-17 | Codex 反方諮詢（「接下來做什麼」的排序；讀了 `windows.yml`） | C1 | 依保守計法記一輪。⚠️ 未事先徵得使用者同意，違反本帳下方「C1 在批次 1 之後不再開審查輪，要再審須使用者明示同意」的約定（Claude 疏失，2026-10-17 已向使用者報告）。Codex 沒有提出 C1 的阻擋問題，只指出 F11／F12 增加案數時要同步 `windows.yml` 釘死的 `PASS=126` |
| 2026-10-17 | Codex 反方諮詢（五項修補設計；讀了原型 diff） | `CONSULT-TOKEN-REPLACE-FLAKE`、`CC-NOBASH-FAILCLOSED`、F4、`CODEX-CHECK-CP437`、`CODEX-CHECK-WARNING` | 部分同意；10 點全部採納後才實作（Git Bash 要實跑確認、F4 的 1c 也要重掃、判準只用裝置號、整合測試等）。依保守計法這五個 ID 各記一輪，之後各只剩一輪 |
| 2026-10-18 | Codex 反方審查，最後一輪（依共用檔分三次平行呼叫：A／B＋C／D＋E；三份回報都說只讀了本組的 diff） | `CONSULT-TOKEN-REPLACE-FLAKE`、`CC-NOBASH-FAILCLOSED`、F4、`CODEX-CHECK-CP437`、`CODEX-CHECK-WARNING` | 無阻擋：`CODEX-CHECK-CP437` PASS，其餘 PASS-WITH-NONBLOCKING；非阻擋項記在 backlog 各列的 2026-10-18 補記。F4 仍要 Mac 真機驗證才關閉。五個 ID 各達 2 輪上限，之後不再送審 |
| 2026-10-18 | Codex 反方審查（只讀本 ID 的三個路徑；簡報禁止讀 Windows codex-check 與 AI-INSTALL，避免已滿兩輪的 ID 再被計一輪） | `CODEX-CHECK-SH-STDERR` | PASS-WITH-NONBLOCKING，無阻擋；兩個測試缺口已補（只動測試）。第 2 輪保留，留給 Mac 原生驗收若需要修正時使用 |

**累計（保守計法）**：C1 4 輪；F2、C3 各 3 輪；G2 3 輪，其他 G 類各 2 輪；`CONSULT-TOKEN-REPLACE-FLAKE`、`CC-NOBASH-FAILCLOSED`、F4、`CODEX-CHECK-CP437`、`CODEX-CHECK-WARNING` 各 2 輪，已達上限；`CODEX-CHECK-SH-STDERR` 1 輪（2026-10-18 更新）。F2／C1／C3 已超過每個 ID 2 輪的上限：10/15 的兩輪同一天、針對同一個 staged 狀態，合計為一輪的話是 2 輪，但本帳不採這個寬鬆計法。第 2 輪後仍有的阻擋問題已停下交使用者裁決，使用者選擇「授權修，不再送審」，所以這三個 ID 在批次 1 之後不再開審查輪，修正以實跑測試與變異檢查驗證。之後要再審，須使用者明示同意。
