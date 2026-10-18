# LTS 檢查點報告：2026-10-28（草稿）

> ⛔ **2026-10-19 起停止適用**：使用者決定停止 LTS，本 repo 改為個人工具（[備忘 §8.16](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-19)）。本檔只供歷史查閱，內容不構成目前的規則、待辦或授權。

> 狀態：**草稿（骨架）**，2026-10-17 建立；檢查點當天定稿，交使用者裁決是否通過。
> 判定規則見[計畫 §3.3](LTS-ADMISSION-PLAN.md#checkpoints)：依關鍵產物判定，不看工時多寡；沒達成時交使用者重新裁決，預設退出（使用者 2026-10-17 選擇「維持預設退出」，見[備忘 §8.9](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)）。
> 本檔是公開文件：證據只放 commit、CI run 與文件連結；逐字稿留在維護者本機、不進 repo。「（推論）」標沒有直接證據的判斷。

## 總覽

| # | 必要產物（計畫 §3.3） | 現況（2026-10-17） | 證據 |
|---|---|---|---|
| ① | `windows.yml` 在 `lts/build` 上對 pwsh 7 與 WinPS 5.1 兩個 host 實際跑起來（不要求全綠） | ✅ 已達成 | [§1](#ci) |
| ② | 第一個阻擋問題已定位，附證據 | ✅ 已達成（以 `CONSULT-TOKEN-REPLACE-FLAKE` 為準，待使用者確認） | [§2](#first-blocker) |
| ③ | Mac 驗收環境與時段已由使用者確認 | ✅ 已達成（2026-10-17 使用者確認驗收機與時段；兩項細節留到 M 階段開工前） | [§3](#mac) |
| 附 | 10/15 起的實記工時，與完成所需工時的預測 | 🟡 草稿（推論） | [§4](#hours) |

<a id="ci"></a>
## 1. Windows CI（產物 ①）

截至 2026-10-17 21:25。之後的 push 與其 CI 首跑結果逐筆記在[備忘 §8.10](DECISION-MEMO-lts-2026-09-30.md#push-ledger)；10/28 定稿時用 `gh run list` 一次重整本表。

| SHA | 內容 | CI run | 嘗試次數 | 結論 |
|---|---|---|---|---|
| `06b0bab` | 批次 1（S0、C1、C3、F2） | [38616121393](https://github.com/rockon8765/Codex-for-CC/actions/runs/38616121393) | 1 | success |
| `0d7b358` | 10/17 上游漂移稽核、事實訂正、backlog 登錄 | [38953090180](https://github.com/rockon8765/Codex-for-CC/actions/runs/38953090180) | 1 | success |
| `82fdaa2` | 取消工時上限、AGENTS.md 核准紀錄 | [38956089580](https://github.com/rockon8765/Codex-for-CC/actions/runs/38956089580) | 1 | success |
| `0a2145d` | 計畫 §8 訂正、DOC-FIX 改名、輪數帳、本報告骨架 | [38957753829](https://github.com/rockon8765/Codex-for-CC/actions/runs/38957753829) | 1 | success |
| `8a0b953` | 本報告 §3、consult 改回跟隨 config 的補記 | [39036096539](https://github.com/rockon8765/Codex-for-CC/actions/runs/39036096539) | 1 | success |

- 截至 2026-10-17 21:25 的五個 run，5 個 job 全部 success：`suite -Mode repo + lint + 8.3 mutation`、`ai-install harness (pwsh)`、`ai-install harness (powershell)`、`node tests (node 22)`、`node tests (node 24)`。
- host 涵蓋：`suite` 以 pwsh 當 runner 跑全套，其中 codex-check、consult-schema 有 pwsh／5.1 兩條腿，off-cleanup 有兩個 child host；5.1 當 runner 只跑 `-Filter` smoke（全套以 5.1 當 runner 只有本機證據，見 `windows.yml` 檔頭）。`ai-install harness` 以 matrix 在 pwsh 與 Windows PowerShell 5.1 各跑一輪，兩邊都是 `PASS=126 FAIL=0`。
- 附帶觀察：五個不同 SHA 都是首次執行就綠，沒有重跑，已符合 11/25 目標裡「3 個不同 SHA 連續綠」這一項；只改文件的 SHA 也算數（C1 不設 paths 過濾）。但 A1 是在 RC SHA 上判定，而且已知的 `CONSULT-TOKEN-REPLACE-FLAKE` 仍未處理——**三綠不代表它已消失**。

<a id="first-blocker"></a>
## 2. 第一個阻擋問題（產物 ②）

- **[`CONSULT-TOKEN-REPLACE-FLAKE`](backlog.md#CONSULT-TOKEN-REPLACE-FLAKE)**（2026-10-15 定位）：Windows consult 在憑證已存在時用 `File.Replace` 換掉舊憑證，偶發失敗並走 exit 44（`CONSULT_TOKEN_WRITE_FAILED`）；舊憑證保留，照設計 fail-closed。本機壓力重現：pwsh 1/40、WinPS 5.1 2/40。原因定位到 `File.Replace` 呼叫；「防毒或索引服務短暫開著該檔」仍是推論。
- 影響：會讓 CI flaky，擋 A1。
- 狀態：待使用者裁決（[計畫 §9](LTS-ADMISSION-PLAN.md) 第 4 點）。Codex 2026-10-17 建議先備妥最小修補授權方案：只處理憑證替換的短暫失敗，保留原子替換、舊憑證保留與最終 exit 44 的語義；短暫重試只是候選修法；驗證要涵蓋「暫時失敗後成功」與「持續失敗仍正確拒絕」，不得用測試裡先睡一下或 workflow 重跑代替修復。 **2026-10-18 更新**：使用者 10/17 裁決修補（[備忘 §8.11](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17b)），已在 `lts/build` 修好並通過最後一輪審查（PASS-WITH-NONBLOCKING，細節見 backlog 該列）。修補進 CI 後，仍要在之後的 SHA 上照 A1 規則重新累積「3 個不同 SHA 連續綠」才能說它不再擋 A1；不宣稱統計上 flake 已消失。
- 另一個需要追蹤的候選（不是「第一個」）：[`CC-NOBASH-FAILCLOSED`](backlog.md#CC-NOBASH-FAILCLOSED)（2026-10-17 登錄；§6 第 1 條候選，可能碰 MVS-1、MVS-4，待在沒有 Git Bash 的 Windows 環境 live 確認）。 **2026-10-18 更新**：使用者裁決 Windows 安裝必須先有 Git for Windows（備忘 §8.11），不再需要找沒有 Git Bash 的環境實測；AI-INSTALL 0a 已在 `lts/build` 實作並通過最後一輪審查。

<a id="mac"></a>
## 3. Mac 驗收環境與時段（產物 ③）

**現況**：環境盤點已完成（2026-10-17，由 Mac 上的 Claude 唯讀執行，結果由使用者貼回）；同日使用者確認由這台 Mac 擔任驗收機、兩段時段採計畫預設（見 3.3）。仍待決定的只剩兩項，都排在 M 階段開工前。

### 3.1 環境盤點（2026-10-17）

| 項目 | 盤點結果 |
|---|---|
| macOS／架構 | macOS 27.0.1（build 26A434）／arm64。CI runner 釘的是 `macos-26`，兩種版本組合要分開記錄（[計畫 §4.2](LTS-ADMISSION-PLAN.md#admission-conditions)） |
| `/bin/bash` | GNU bash 3.2.57；預設 shell 為 zsh。日常帳號 PATH 上的 bash 是 Homebrew 5.x；新帳號的 PATH 應會先解析到 `/bin/bash`（推論） |
| Codex CLI | codex-cli 0.163.0，日常帳號以 Homebrew 的 npm 全域安裝 |
| Claude Code | 2.1.301，官方原生安裝程式，只裝在日常帳號 |
| node | 日常帳號 PATH 上優先的是 conda 套件的 node 25.8.2；另有 Homebrew node 26.10.0（兩個帳號共用） |
| Git／Xcode CLT | 系統 git 2.54.0（Apple Git-157），日常帳號另用 Homebrew git 2.56.0；Xcode CLT 已安裝 |
| 自動更新 | 日常帳號有排程，每天自動更新 codex 與 claude |
| 超級模式（日常帳號） | 已安裝，內容與 `main` `5b7c2ed` 的 macos 樹相同；與 `lts/build` `0a2145d` 相比有 3 檔不同，且少了 `tests/off-cleanup.tests.sh`。驗收須在測試帳號重新安裝（MVS-4），不能沿用這份 |
| 測試帳號 | 沒有 |
| 磁碟剩餘空間 | 約 32Gi（新裝約需 1GB，推論） |

### 3.2 要當驗收環境還缺的（盤點者的判斷，多為推論）

1. **V4-mac 測試帳號**要由使用者親自建立（計畫排在時段 1，10/28 只需確認）。比照 W0：標準帳號、不給管理者權限、家目錄名稱不用 `user`。不能建成管理者，因為 Homebrew 前綴對 admin 群組可寫，會動到日常帳號的 Homebrew。
2. **Codex CLI 不能共用**：Homebrew 的 bin 會出現在每個帳號的 PATH，但日常帳號的 codex 套件目錄只有擁有者可讀（每日更新腳本的 umask 造成，每天都會重設），測試帳號執行會失敗（推論，未以第二個帳號實測）。測試帳號要另裝 Codex CLI（使用者層級的 npm prefix，排在 Homebrew bin 之前，因為腳本呼叫不帶路徑的 `codex`），`codex login` 由使用者親自完成。
3. **Claude Code** 要在測試帳號重新安裝（MVS-4），並由使用者登入。
4. **測試帳號的工具解析**：預期 bash→`/bin/bash` 3.2.57、git→系統 git 2.54.0、python3→系統 3.9.6、node→Homebrew 26.10.0、uuidgen 與 perl→系統、claude→找不到（推論）。M0 要在測試帳號實測，逐項記錄 `command -v`。只有 hook 的執行環境找不到 node 時，才需要照 AI-INSTALL 步驟 2 把 node 改寫成絕對路徑。
5. **隔離**：日常帳號的部分資料（例如 consult 逐字稿、skills、hooks）同機的其他標準帳號讀得到（推論；認證檔與設定檔不可讀）。另外，測試帳號的 settings 若漏改家目錄路徑，hook 會在不報錯的情況下跑到日常帳號那份非 RC 的版本——M 版的 W2／W3 要核對 hook 路徑。
6. **測試帳號要自己 clone repo，並在 RC SHA 上驗收**；目前還沒有 `rc-` tag。
7. **不在這台機器上的前置**：`lts/build` 還沒有 `macos.yml`（C2）；11/25 前要在 GitHub 的 macOS runner 試跑一次 smoke（不需要 Mac、不要求綠，[計畫 §2.3](LTS-ADMISSION-PLAN.md#m-phase)），每次 push 仍要使用者同意；M0–M10 清單要在 M 階段開工前由使用者核准並凍結。

### 3.3 待使用者確認與決定

| 項目 | 使用者確認 |
|---|---|
| 由這台 Mac 擔任驗收機 | 確認 |
| 時段 1（macOS CI 可行性＋V4-mac；預設 12 月上旬，至少 6h） | 採預設：12 月上旬，至少 6h（具體日期之後可改） |
| 時段 2（M0–M10 兩趟；預設 2027-01-04 至 01-12，約 10h，分兩天） | 採預設：2027-01-04 至 01-12，約 10h，分兩天；另加 T1–T7（見下列） |
| macOS 的 T1–T7 排在哪個時段（預設兩段都沒包含；計畫 M-驗收的 14h 有算 T1–T7） | 併入時段 2（M0–M10 兩趟之後；時段 2 可能要延長約半天，推論） |
| 測試帳號的 Codex CLI 安裝方式 | 使用者層級的 npm prefix，排在 Homebrew bin 之前；`codex login` 由使用者親自完成 |
| 驗收前是否收緊日常帳號家目錄的權限 | （M 階段開工前決定） |
| 兩趟之間怎麼凍結版本（Claude Code 自動更新、共用的 Homebrew node、macOS 更新） | （M 階段開工前決定） |
| 確認日期與原話 | 2026-10-17。使用者選擇的選項原文：「確認，時段用預設 (Recommended)」「併入時段 2 (Recommended)」「使用者層級 npm prefix (Recommended)」 |

兩個時段都需要使用者本人在場：codex／claude 登入、當次接受 codex-check baseline（V5），以及安裝全域規則前的同意（W7）。

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
