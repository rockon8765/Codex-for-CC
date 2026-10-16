# LTS 工時記錄

> 規則見 [`LTS-ADMISSION-PLAN.md` §3.4](LTS-ADMISSION-PLAN.md#budget)：當下記起訖時間；估計值標「（推論）」；每月和 commit、consult 逐字稿的時間戳對帳一次，差距超過 25% 就標記。
> 總額硬上限 115h、截止 2027-01-15。類別對應計畫 §3.1 的分配表。
> 公開文件：證據欄只寫 commit、文件或「本機逐字稿（不進 repo）」，不寫個人路徑。

| 日期 | 起訖 | 時數（h） | 類別 | 內容 | 證據 |
|---|---|---:|---|---|---|
| 2026-10-14 | ≈00:50–04:15 | ≈3.4 | P 規劃 | 規劃與分析：Claude 主代理與子代理的唯讀調查、准入計畫草稿 v1–v3、兩輪子代理審查、Codex 反方審查（起點 00:50 是本 session 開始時間的估計，推論；草稿 v3 曾記為 01:17，兩者差異未核對。終點與時數同為估計） | [備忘 §8](DECISION-MEMO-lts-2026-09-30.md#lts-decision-2026-10-14)；[`LTS-ADMISSION-PLAN.md`](LTS-ADMISSION-PLAN.md)；本機 consult 逐字稿（不進 repo） |
| 2026-10-14 | 08:30–11:15 | ≈2.75（推論：牆鐘時間，主要是代理執行） | S0 治理文字＋W-CI＋W-MUST（拆分待結算時補記） | 批次 1：備忘 §8、AGENTS.md 建置期段、CLAUDE.md、README 橫幅、Linux 凍結第一階段文件、backlog 同步、本檔與准入計畫；`windows.yml` 與測試 host 參數化（C1／C3）；F2 off 清理修正（Windows／macOS） | 批次 1 commit（2026-10-15 建立） |
| 2026-10-15 | ≈01:20–02:45（起點推論：當天第一次 consult 是 01:31） | ≈1.4（推論：牆鐘時間，主要是代理與測試執行） | 審查＋W-CI＋W-MUST | 批次 1 commit 前：Codex 反方諮詢、多代理審查、使用者四項裁決；F2 白名單收緊、consult-schema 家目錄隔離、文件訂正；全套重跑；定位 [`CONSULT-TOKEN-REPLACE-FLAKE`](backlog.md#CONSULT-TOKEN-REPLACE-FLAKE) | 批次 1 commit；[備忘 §8.7／§8.8](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-15)；本機 consult 逐字稿（不進 repo） |
| 2026-10-17 | ≈00:58–03:20（起點推論：本 session 的暫存目錄建於 01:03） | ≈2.4（推論：牆鐘時間，主要是代理執行） | 保留（歸類為推論，使用者可改） | 上游漂移稽核（Claude Code 2.1.295／2.1.301、Codex CLI 0.163.0）：6 條研究線、9 個對抗驗證、Codex 反方一輪；依使用者裁決做事實訂正與 backlog 10/17 登錄，並做本機 consult 設定與 codex-check baseline 更新；commit 前 4 鏡頭多代理審查 | 本日 commit；[`AUDIT-upstream-drift-2026-10-17.md`](AUDIT-upstream-drift-2026-10-17.md)；[backlog 10/17 登錄](backlog.md#drift-1017)；本機 consult 逐字稿（不進 repo） |

**累計**：≈10.0h｜**剩餘**：≈105.0h

<a id="review-rounds"></a>
## 審查輪數帳（計畫 §3.2）

> 一輪＝對同一個 ID 的 diff 呼叫一次審查；同一次呼叫涵蓋幾個 ID 就各記一輪；每個 ID 最多 2 輪。計數採計畫 §3.2 的保守細則：一次 workflow 對它涵蓋的每個 ID 各記一輪；讀了該 ID 的 diff 或實作的 Codex 諮詢另記一輪。

| 日期 | 審查 | 涵蓋 ID | 結論 |
|---|---|---|---|
| 2026-10-14 | 批次 1 合併前審查（Claude 子代理；呼叫次數未記錄，以 1 次計，推論） | G1、G2、G4、G5、G6、C1、C3、F2 | 指出的問題已在批次 1 內修正（證據見各檔「2026-10-14 合併前審查」註解） |
| 2026-10-15 | Codex 反方諮詢（讀了 F2 實作與 CI／suite 的計數） | F2、C1、C3 | 部分反對；處置見[備忘 §8.8](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-15) |
| 2026-10-15 | commit 前多代理審查（5 個維度，各配 1 個對抗驗證） | G1、G2、G4、G5、G6、C1、C3、F2 | 存活 11 條；兩類阻擋問題依規則交使用者裁決（備忘 §8.7） |

**累計（保守計法）**：F2、C1、C3 各 3 輪，G 類各 2 輪。F2／C1／C3 已超過每個 ID 2 輪的上限：10/15 的兩輪同一天、針對同一個 staged 狀態，合計為一輪的話是 2 輪，但本帳不採這個寬鬆計法。第 2 輪後仍有的阻擋問題已停下交使用者裁決，使用者選擇「授權修，不再送審」，所以這三個 ID 在批次 1 之後不再開審查輪，修正以實跑測試與變異檢查驗證。之後要再審，須使用者明示同意。
