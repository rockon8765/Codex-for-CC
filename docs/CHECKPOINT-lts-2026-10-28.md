# LTS 檢查點報告：2026-10-28（草稿）

> 狀態：**草稿（骨架）**，2026-10-17 建立；檢查點當天定稿，交使用者裁決是否通過。
> 判定規則見[計畫 §3.3](LTS-ADMISSION-PLAN.md#checkpoints)：依關鍵產物判定，不看工時多寡；沒達成時交使用者重新裁決，預設退出（使用者 2026-10-17 選擇「維持預設退出」，見[備忘 §8.9](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)）。
> 本檔是公開文件：證據只放 commit、CI run 與文件連結；逐字稿留在維護者本機、不進 repo。「（推論）」標沒有直接證據的判斷。

## 總覽

| # | 必要產物（計畫 §3.3） | 現況（2026-10-17） | 證據 |
|---|---|---|---|
| ① | `windows.yml` 在 `lts/build` 上對 pwsh 7 與 WinPS 5.1 兩個 host 實際跑起來（不要求全綠） | ✅ 已達成 | [§1](#ci) |
| ② | 第一個阻擋問題已定位，附證據 | ✅ 已達成（以 `CONSULT-TOKEN-REPLACE-FLAKE` 為準，待使用者確認） | [§2](#first-blocker) |
| ③ | Mac 驗收環境與時段已由使用者確認 | ⬜ **未做，待使用者** | [§3](#mac) |
| 附 | 10/15 起的實記工時，與完成所需工時的預測 | 🟡 草稿（推論） | [§4](#hours) |

<a id="ci"></a>
## 1. Windows CI（產物 ①）

| SHA | 內容 | CI run | 嘗試次數 | 結論 |
|---|---|---|---|---|
| `06b0bab` | 批次 1（S0、C1、C3、F2） | [38616121393](https://github.com/rockon8765/Codex-for-CC/actions/runs/38616121393) | 1 | success |
| `0d7b358` | 10/17 上游漂移稽核、事實訂正、backlog 登錄 | [38953090180](https://github.com/rockon8765/Codex-for-CC/actions/runs/38953090180) | 1 | success |
| `82fdaa2` | 取消工時上限、AGENTS.md 核准紀錄 | [38956089580](https://github.com/rockon8765/Codex-for-CC/actions/runs/38956089580) | 1 | success |

- 三個 run 的 5 個 job 全部 success：`suite -Mode repo + lint + 8.3 mutation`、`ai-install harness (pwsh)`、`ai-install harness (powershell)`、`node tests (node 22)`、`node tests (node 24)`。
- host 涵蓋：`suite` 以 pwsh 當 runner 跑全套，其中 codex-check、consult-schema 有 pwsh／5.1 兩條腿，off-cleanup 有兩個 child host；5.1 當 runner 只跑 `-Filter` smoke（全套以 5.1 當 runner 只有本機證據，見 `windows.yml` 檔頭）。`ai-install harness` 以 matrix 在 pwsh 與 Windows PowerShell 5.1 各跑一輪，兩邊都是 `PASS=126 FAIL=0`。
- 附帶觀察：三個不同 SHA 都是首次執行就綠，沒有重跑，已符合 11/25 目標裡「3 個不同 SHA 連續綠」這一項；只改文件的 SHA 也算數（C1 不設 paths 過濾）。但 A1 是在 RC SHA 上判定，而且已知的 `CONSULT-TOKEN-REPLACE-FLAKE` 仍未處理——**三綠不代表它已消失**。

<a id="first-blocker"></a>
## 2. 第一個阻擋問題（產物 ②）

- **[`CONSULT-TOKEN-REPLACE-FLAKE`](backlog.md#CONSULT-TOKEN-REPLACE-FLAKE)**（2026-10-15 定位）：Windows consult 在憑證已存在時用 `File.Replace` 換掉舊憑證，偶發失敗並走 exit 44（`CONSULT_TOKEN_WRITE_FAILED`）；舊憑證保留，照設計 fail-closed。本機壓力重現：pwsh 1/40、WinPS 5.1 2/40。原因定位到 `File.Replace` 呼叫；「防毒或索引服務短暫開著該檔」仍是推論。
- 影響：會讓 CI flaky，擋 A1。
- 狀態：待使用者裁決（[計畫 §9](LTS-ADMISSION-PLAN.md) 第 4 點）。Codex 2026-10-17 建議先備妥最小修補授權方案：只處理憑證替換的短暫失敗，保留原子替換、舊憑證保留與最終 exit 44 的語義；短暫重試只是候選修法；驗證要涵蓋「暫時失敗後成功」與「持續失敗仍正確拒絕」，不得用測試裡先睡一下或 workflow 重跑代替修復。
- 另一個需要追蹤的候選（不是「第一個」）：[`CC-NOBASH-FAILCLOSED`](backlog.md#CC-NOBASH-FAILCLOSED)（2026-10-17 登錄；§6 第 1 條候選，可能碰 MVS-1、MVS-4，待在沒有 Git Bash 的 Windows 環境 live 確認）。

<a id="mac"></a>
## 3. Mac 驗收環境與時段（產物 ③，待使用者）

計畫的預設時段（[§3.3](LTS-ADMISSION-PLAN.md#checkpoints)）：

- 時段 1（macOS CI 可行性、V4-mac）：12 月上旬，至少 6h。
- 時段 2（M0–M10 兩趟）：2027-01-04 至 01-12，約 10h，分兩天。

待使用者確認並填寫：

| 項目 | 使用者確認 |
|---|---|
| 可用的 Mac（macOS 版本、架構） | （待填） |
| 測試帳號由使用者親自建立（V4） | （待填） |
| 時段 1 的日期 | （待填） |
| 時段 2 的日期 | （待填） |
| 確認日期與原話 | （待填） |

另：11/25 前要在 GitHub 的 macOS runner 試跑一次 `macos.yml` smoke（不需要 Mac、不要求綠，[計畫 §2.3](LTS-ADMISSION-PLAN.md#m-phase)）；每次 push 仍要使用者逐次同意。

<a id="hours"></a>
## 4. 工時與完成預測（推論）

- 10/15 起的實記（[`LTS-timelog.md`](LTS-timelog.md)；都是牆鐘時間估計）：10/15 ≈1.4h；10/17 ≈3.0h。10/14 起累計 ≈10.6h。2026-10-17 起不設工時上限。
- 完成所需工時的初步預測（推論）：以[計畫 §3.1](LTS-ADMISSION-PLAN.md#budget) 的預估、扣掉已完成的 F2 為基礎，還沒依實績校正——
  - W 階段剩餘：W-MUST 約 10h、W-驗收約 12h、W-准入審查約 3h，合計約 25h。
  - M 階段：M-CI＋Linux 第二階段約 18h、M-MUST 約 6h、M-驗收約 14h、M-准入審查約 2h，合計約 40h。
  - 缺陷修補與審查超支：0–16h（保留；其中約 2h 是 11/25 前的 `macos.yml` smoke）。
  - 合計約 65–81h。CI 的歷史估計（30–56h）高於本表分到的份額，M 階段可能偏樂觀。
- 節奏（Codex 2026-10-17 建議，不是新的停止門檻）：每週更新一次「完成的產物、卡住的依賴、剩餘工時區間、下一個檢查點的預測」。

## 5. 判定（10/28 當天填）

| 項目 | 結果 |
|---|---|
| ① | （待填） |
| ② | （待填） |
| ③ | （待填） |
| 使用者裁決（原話） | （待填） |
