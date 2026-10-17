# LTS 准入計畫（Windows 先、macOS 隨後）

> 建立：2026-10-14｜依據：使用者 2026-10-14 裁決（[備忘 §8](DECISION-MEMO-lts-2026-09-30.md#lts-decision-2026-10-14)）｜建置期規則：[`AGENTS.md`](../AGENTS.md)「LTS 建置期」段｜工時：[`LTS-timelog.md`](LTS-timelog.md)
> **狀態：草案。** [§4](#admission) 的准入條件與驗收清單、[§5.2](#downgrades) 的劃出文字，由使用者核准原文後凍結（核准日記入備忘 §8），之後只有使用者能改。PASS 只由使用者簽核。使用者已指示即刻開工（備忘 §8.1）；AGENTS.md 建置期段的原文已於 2026-10-17 由使用者核准（[備忘 §8.9](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)）；本檔 §4、§5.2 的原文核准之前，工作仍只留在本機的 `lts/build`，不 push、不動 `main`（已授權的例外都是對 `lts/build` 的單次 push：2026-10-15 批次 1，見[備忘 §8.7](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-15)；2026-10-17 四次：10/17 上游漂移稽核、取消工時上限與 AGENTS.md 核准紀錄、計畫 §8 訂正與 10/28 報告骨架、10/28 報告 §3 與 consult 補記四個 commit，見[備忘 §8.9](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)。之後每次 push 仍要逐次同意）。
> 本檔是公開文件：只放雜湊、條數、類別，不放個人路徑、帳號或專案名。「（推論）」標沒有直接證據的判斷。

## 0. 摘要

1. **範圍**：全功能——gate hook、consult、exec、AI-INSTALL。平台只有 Windows 與 macOS；Linux 凍結（[§2.4](#linux-freeze)）。
2. **順序**：先 Windows 准入（W 階段），再 macOS（M 階段）（使用者選擇的選項：「Windows 先、macOS 隨後 (Recommended)」）。兩個平台各自通過准入、各自由使用者簽核；兩邊都通過前，不得做雙平台宣稱。
3. **預算**：不設總工時上限與截止日（使用者 2026-10-17 裁決，見[備忘 §8.9](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)；原為 10/14 選擇的選項「115h／2027-01-15 (Recommended)」）。工時照記，[§3.1](#budget) 的分配數字只當預警。先保障最低範圍（MVS）、審查與驗收；便利項目排在後面，要做須使用者核准。
4. **檢查點 2026-10-28**：看關鍵產物，不看燒了多少工時（[§3.3](#checkpoints)）。
5. **MUST 20 項**（[§5.1](#must)；F2 依 §5.2 預寫的規則改列 MUST，2026-10-15 使用者確認，並選擇收緊白名單，見備忘 §8.7）；其餘降級為已知限制，限制文字先寫好（[§5.2](#downgrades)）。
6. **新缺陷**：會讓 MVS 不成立的，只能在授權範圍內修，或交使用者裁決；不得靠揭露文字劃出（[§6](#new-defect-rule)）。
7. **對外**：准入前不宣稱支援、不加 badge、不發 Release（README 原有的 linux badge 已在 Linux 凍結第一階段移除）；每次 push、打 tag、合併、改 repo 設定，都另外徵得使用者同意。

## 1. 分支、標籤與對外狀態

| 項目 | 規則 |
|---|---|
| `main` | 凍結快照，准入時才從 `lts/build` 以 PR 合併。准入前只收兩種例外，每一次都要使用者逐案核准：① 純文件 commit；② 帶 `UNFREEZE <ID>` 四行、針對已出貨（`main` 上）的 security／資料遺失／上游 breakage 修復（AGENTS.md「地點」與「歷史」）。AGENTS.md 建置期段（2026-10-17 已核准）與本檔 §4、§5.2 都核准之前，這兩種例外也不做 |
| `lts/build` | 建置分支；CI 跑這條分支和它的 PR。退出時保留、不合併，`main` 不會停在半遷移狀態。AGENTS.md 建置期段（2026-10-17 已核准）與本檔 §4、§5.2 都核准之前只在本機，不 push（例外：使用者授權的單次 push——2026-10-15 批次 1 的 SHA（備忘 §8.7）、2026-10-17 的四個 commit：10/17 稽核、取消工時上限與 AGENTS.md 核准紀錄、計畫 §8 訂正與 10/28 報告骨架、10/28 報告 §3 與 consult 補記（備忘 §8.9）） |
| tag `pre-lts` | annotated，指向 `80c60a8`（凍結期最後狀態），同時當 Linux 的最終快照（只用這一個名稱，不另取名）。**尚未建立**；建立與 push 都要使用者同意。**tag 建立前請用 commit `80c60a8`** |
| RC 與正式 tag | RC 用 `rc-lts-v<版本>-<n>`，訊息註明「release candidate，未經准入」。正式 tag `lts/v<版本>` 在使用者簽核 PASS 後才建立（[§4.6](#a9-post)） |
| badge、Release | 准入前不加 windows／macos badge、不發 GitHub Release。README 原有的 `linux.yml` badge 已在 Linux 凍結第一階段移除（2026-10-14）；`linux.yml` 本身留到第二階段才刪 |
| 禁用字詞 | 准入前，README、AI-INSTALL、tag 訊息裡不得用「支援／受支援／supported／LTS 版／stable／穩定」描述目前狀態，只能用「LTS 建置中／未經准入／凍結快照」。否定句和限制句（例「只在 X 驗收過」）不在此限 |

## 2. 階段

<a id="s0"></a>
### 2.1 S0 治理文字（2026-10-14）

備忘 §8、AGENTS.md 建置期段、CLAUDE.md 的兩平台 parity 規則、README 頂端橫幅與撤下隱含宣稱、AI-INSTALL 對 Linux 的停止指示、`linux-platform-notes.md` 凍結頁首、backlog 同步、本檔、工時記錄。

<a id="w-phase"></a>
### 2.2 W 階段（Windows）

1. C1＋C3：新增 `windows.yml`，pwsh 7 與 WinPS 5.1 兩個 host 都跑。
2. Windows 側與共用的 MUST（F1、F2、F11、F12、`WORKER-CONTRACT-TEMPLATE`、V3、G7）。行為改動照 parity 規則，兩平台在同一個 commit 落地；macOS 側等到 M 階段才驗收，在那之前一律標「未經准入」。
3. V4-win：使用者在 Win11 親自建立 OS 測試帳號（家目錄不叫 `user`）；之後代理植入對照規則，跑 W0–W11 與 T1–T7。
4. Windows 准入審查（[§4.2](#admission-conditions) 的 Windows 部分），交使用者簽核。

- **W 階段不得改鏡像檔**（各平台 `skills/超級模式/` 底下的 `lib/gate-registration.js`、`lib/consult-answer.js`、`tests/matcher-contract.test.js`，清單以 `tests/gate-registration.test.js` 的 `MIRRORED` 為準）：鏡像測試要求三平台逐位元相同，而 `linux/` 不得修改，第二階段又要等 macOS CI 綠燈。真的需要改時，先完成 [§2.4](#linux-freeze) 第二階段，或交使用者裁決。

<a id="m-phase"></a>
### 2.3 M 階段（macOS）

1. C2＋C4：新增 `macos.yml`，只用 `/bin/bash` 3.2。可行性探測提早做：10/28 前確認 Mac 驗收環境與時段；**11/25 前在 GitHub 的 macOS runner 試跑一次 `macos.yml` smoke**（不需要 Mac，從保留撥約 2h）：不要求綠，記錄 run URL、`ImageOS`／`ImageVersion`、`/bin/bash` 版本與第一個阻擋問題，當作 Mac 的早期探測（Codex 在備忘 §8.6 的要求；原本只排時程，屬部分採納）。
2. macOS 側 MUST 收尾；V4-mac；M0–M10 在不同的兩天各跑一趟，再跑 T1–T7。
3. macOS 准入審查，交使用者簽核。
4. M 階段如果改到 Windows 樹或安裝的可執行內容，使它和 Windows 已准入的 SHA 不再逐位元相同，Windows 就要對新 RC 重跑 W0–W11。

<a id="linux-freeze"></a>
### 2.4 Linux 凍結（`LINUX-FREEZE`）

- **第一階段（純文件，S0 已做）**：README、AI-INSTALL §0、AGENTS.md、CLAUDE.md、`linux-platform-notes.md`、backlog 都標成凍結；README 的 linux badge 已移除（平台 badge 本身就像支援宣稱）。
- **第二階段（同一個 commit；前提是 `macos.yml` 已在 `lts/build` 綠燈）**：
  - 鏡像集合改成兩平台：`tools/probe-gate-registration.js`、`tests/gate-registration.test.js`、`tests/probe-gate-registration.test.js`、`tests/oracle-teeth.test.js`、`tests/matcher-contract-cli.test.js`。
  - 兩份 `lib/gate-registration.js` 的檔頭註解在同一個 commit 改；`.gitattributes` 只改註解。
  - 刪除 `linux/` 與 `.github/workflows/linux.yml`。
- 第二階段之前，鏡像檔（見 [§2.2](#w-phase) 末段）的測試仍要求三份逐位元相同。要改鏡像檔，就先做第二階段；不得為了讓測試通過而改 `linux/`。
- `linux.yml` 在第二階段之前仍會跑：凍結的 `linux/` 樹，以及頂層共用測試（`tests/*.test.js`、`tests/lib/`、`tools/` 的診斷、`run-posix-args` 等）；觸發條件沒有分支過濾，`lts/build` 的 push 也會跑。它的綠燈不構成任何平台的支援宣稱。
- 第二階段不保留 ubuntu job：它和 Windows／macOS CI 只會重複跑同一組共用測試（`windows.yml` 的 node job 已跑平台無關的頂層測試），還會造成「Linux 有綠燈」的假象。

<a id="budget"></a>
## 3. 預算與停止規則

### 3.1 分配（2026-10-17 起不設總額上限；以下數字只是預估與預警，用來重新預測）

| 類別 | 預估（h） | 內容 |
|---|---:|---|
| P 規劃（10/14，已花） | 4 | 工時記錄約 3.4h（估計） |
| S0 治理文字 | 6 | [§2.1](#s0) |
| W-CI | 22 | C1、C3，含審查與證據修補 |
| W-MUST | 12 | [§5.1](#must) 中屬 W 階段的項目，含審查 |
| W-驗收 | 12 | V4-win、W0–W11、T1–T7 |
| W-准入審查 | 3 | A7、A8、G7 的 LICENSE 等檔 |
| M-CI＋Linux 第二階段 | 18 | C2、C4、[§2.4](#linux-freeze) 第二階段 |
| M-MUST | 6 | macOS 側收尾 |
| M-驗收 | 14 | V4-mac、M0–M10 兩趟、T1–T7 |
| M-准入審查 | 2 | A7、A8 |
| 保留 | 16 | 已預撥約 2h：11/25 前的 `macos.yml` smoke 試跑（[§2.3](#m-phase)）。其餘依序用於：① 會讓 MVS 不成立的新缺陷（[§6](#new-defect-rule)）；② 審查超支；③ 使用者核准的降級項實作 |
| **合計** | **115** | 原為總額硬上限，2026-10-17 由使用者取消，留作預估 |

- 節奏（以原截止日計算；截止日已於 2026-10-17 取消，留作參考）：10/15 到 2027-01-15 約 13 週，每週約 8.5h；每週 8–10h 是否可行，使用者選擇的選項是「可以」。
- 歷史參考（推論）：大型跨平台批次每批至少 12–21h、經歷 7–9 輪審查；凍結後的投入約每週 1.2h。本預算不保證能完成。
- CI 的歷史估計是 30–56h（含審查）。本表的 W-CI 22h 全給 Windows CI；M 那一列的 18h 另含 Linux 凍結第二階段，所以 CI 實際分到約 32–36h（推論），不是 40h。這比歷史估計的中位數低，超支時先動用保留；不得靠縮減驗收來省工時。

<a id="stop-rules"></a>
### 3.2 停止規則

- 原有的「總額到 115h，或到 2027-01-15 仍未完成，就停工回報、預設退出」已於 2026-10-17 由使用者取消（[備忘 §8.9](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)）。目前沒有工時或日曆上的全域停止條件；以下其他停止規則與 [§3.3](#checkpoints) 的檢查點照舊。
- 某階段用到預估的 100%：重新預測並回報，不自動停工。
- 審查輪數：一輪＝對同一個 ID 的 diff 呼叫一次審查；同一次呼叫涵蓋幾個 ID，就各記一輪。每個 ID 最多 2 輪；拆成新 PR 或改名都不重置。第 2 輪後仍有阻擋問題：停下交使用者裁決。可劃出的項目經使用者同意後套用 [§5.2](#downgrades) 文字；不能劃出的項目預設退出。不得把「不再審」當成「已通過」。計數細則（2026-10-15 補，保守計法）：一次 workflow 不論派幾個維度，對它涵蓋的每個 ID 各記一輪；同一天另做的 Codex 諮詢只要讀了某個 ID 的 diff 或實作，也另記一輪。輪數帳記在 [`LTS-timelog.md`](LTS-timelog.md#review-rounds)。
- 延期只能由使用者決定，整個建置期最多一次。（2026-10-17 註：本條原指延後截止日；截止日已取消，現在沒有適用對象。目標日的調整見 [§3.3](#checkpoints)。）

<a id="checkpoints"></a>
### 3.3 檢查點

| 日期 | 判定依據（關鍵產物） | 沒達成 |
|---|---|---|
| **2026-10-28** | ① `windows.yml` 在 `lts/build` 上對 pwsh 7 與 WinPS 5.1 兩個 host 實際跑起來（不要求全綠；前提是 push，2026-10-15 使用者已單次授權批次 1 的 push，備忘 §8.7）；② 第一個阻擋問題已定位，附證據；③ Mac 驗收環境與時段已由使用者確認。另附 10/15 起的實記工時與完成所需工時的預測 | 交使用者重新裁決，預設退出 |
| 2026-11-25（目標） | `windows.yml` 在 3 個不同 SHA 連續綠；W-MUST 都已關閉，或已套用 [§5.2](#downgrades) 文字；`macos.yml` 已在 GitHub runner 試跑過一次 smoke（不要求綠，見 [§2.3](#m-phase)） | 同上 |
| 2026-12-16（目標） | Windows 准入審查完成，交使用者簽核 | 同上 |
| 2027-01-15（目標；原為截止日，2026-10-17 取消） | macOS 准入審查完成，交使用者簽核 | 交使用者重新裁決（截止日已取消，不預設退出） |

- 產物達標就通過，不論工時多寡；花了工時而產物沒到，就不通過。
- 目標日是預設，使用者可以改。（截止日與 115h 上限已於 2026-10-17 由使用者取消。）
- 10/28 檢查點報告（草稿）：[`CHECKPOINT-lts-2026-10-28.md`](CHECKPOINT-lts-2026-10-28.md)。
- Mac 時段（預設）：時段 1（macOS CI 可行性、V4-mac）12 月上旬，至少 6h；時段 2（M0–M10 兩趟）2027-01-04 至 01-12，約 10h，分兩天。

### 3.4 工時記錄

- 寫在 [`LTS-timelog.md`](LTS-timelog.md)，當下記起訖時間；估計值標「（推論）」。
- 每月和 commit、consult 逐字稿的時間戳對帳一次，差距超過 25% 就標記。
- 文件引用的 consult 逐字稿（例如備忘 §8.6、§8.8 的反方紀錄）：引用當下就移到 `super-mode-logs` 的子目錄（例如 `evidence/`），或在工時記錄記下檔名、大小與 sha256。off 只清頂層、不進子目錄；不這樣做，超過 14 天後任何一次 off 都可能清掉對帳與裁決證據（2026-10-15 審查指出）。逐字稿在維護者本機、不進 repo，搬移要使用者同意。

<a id="admission"></a>
## 4. 准入（草案；使用者核准後凍結）

<a id="mvs"></a>
### 4.1 最低範圍（MVS）

任一項做不到，該平台准入就是 FAIL，不是縮小宣稱。

| # | 能力 | 最低要求 |
|---|---|---|
| MVS-1 | gate | super-mode on／off 都能用；on 而沒有憑證時 DENY；鑄證後 ALLOW；收尾指令把憑證縮到 3 分鐘 |
| MVS-2 | consult | 討論模式（`-NoCredential`）與鑄證模式都拿到首行裁決和逐字稿 |
| MVS-3 | exec | 在拋棄式 repo 用出貨範本自足派工一次，核對 `_last.txt`、`git status`（含未追蹤檔）、diff 與逐條 AC |
| MVS-4 | AI-INSTALL | 在乾淨的測試帳號從步驟 0 做到步驟 6，完成新裝 |

<a id="admission-conditions"></a>
### 4.2 准入條件（每個平台各自評估）

| # | 條件 |
|---|---|
| A1 | 該平台的 workflow 在 RC SHA 是綠的；在那之前有 3 個不同 SHA 連續綠，沒有靠重跑變綠（每次重跑都要記錄；flaky 一律算紅）。記錄 run URL、`ImageOS`、`ImageVersion`。Windows 另要求 codex-check 的 pwsh 腿是綠的 |
| A2 | Windows：在測試帳號、RC SHA 上，W0–W11 全部通過（[§4.4](#acceptance-w)） |
| A3 | macOS：在測試帳號、RC SHA 上，M0–M10 兩趟都通過（清單在 M 階段開工前凍結） |
| A4 | [§5.1](#must) 的 MUST 每項都已關閉，或已套用 [§5.2](#downgrades) 的對應文字，且不碰到 MVS。F4 的 ACCEPTED_RISK 要有使用者裁決紀錄（F2 已改列 MUST 修復，不走 ACCEPTED_RISK；2026-10-15 使用者確認，備忘 §8.7） |
| A5 | T1–T7 在該平台通過（[§4.3](#t-tasks)） |
| A6 | 配置快照已記錄；公開文件只放雜湊、條數、類別 |
| A7 | AI 反方審查：由 Codex 審一次准入資料。**這不是獨立審查，也不是人類審查。** 判 FAIL 時 Claude 不得推翻，只能由使用者決定修或退出 |
| A8 | 文件同步：支援矩陣、已知限制（照 [§5.2](#downgrades) 原文）、版本組合聲明（「只對列出的版本組合驗收；自動更新之後就屬未驗收」）、LICENSE、SECURITY.md、SUPPORT |
| A9-pre | 發行準備：RC SHA 已打 `rc-` tag（經使用者同意），附該平台 workflow 的 run URL；AI-INSTALL 步驟 0 的 tag 檢查與步驟 6 的來源 SHA 已就位（F12）；簽核文字寫明 RC SHA |
| A10 | 維護可行性：用驗收的實記工時核算，「每 28 天重驗」的必要程序（該平台 MVS 四項加 T1–T7）跑一次能否放進每月 10h。放不下就交使用者裁決：縮小重驗範圍並改寫宣稱，或退出 |

- **PASS**：該平台 A1–A10 全部通過，**而且使用者在對話中簽核**；簽核原文與 RC SHA 記入備忘 §8。
- **准入 FAIL 的判定時點**：只在准入審查時、對 RC SHA 判定。建置期間的紅燈屬於「修復中」，照 [§6](#new-defect-rule) 處理，不等於准入 FAIL；但停止規則（[§3.2](#stop-rules)）觸發時直接退出。
- 不同版本組合的結果分開記錄，不得合併成同一組通過。

<a id="t-tasks"></a>
### 4.3 驗收任務 T1–T7（該平台、RC SHA、測試帳號）

| # | 內容 |
|---|---|
| T1 | consult 兩種模式都用代表性簡報（[§4.5](#representative-briefs)），都要拿到首行裁決和逐字稿路徑 |
| T2 | 照出貨的全域規則 snippet，模擬「exit 42＋`CONSULT_UNAVAILABLE_QUOTA`」與 exit 46：不得判定為額度用盡，不得自動重試 |
| T3 | gate：off 時放行；on 而沒有憑證時攔下；鑄證後 20 分鐘內放行；`git commit` 之後縮到 3 分鐘 |
| T4 | exec：用**沒有臨時補強**的出貨派工範本（含 [§5.1](#must) 的最小 worker 契約；契約沒落地就用不含契約的範本，並套 [§5.2](#downgrades) 的文字）。核對 `_last.txt`、`git status`（含未追蹤檔）、diff、逐條 AC；確認 worker 沒有自行呼叫 consult 或 exec |
| T5 | exec 回非零碼：先查證據（`_last.txt`、`git status`／`git diff`），不自動重派 |
| T6 | F1 自查程序：在測試帳號實際跑一次，抓到植入的陽性對照，對陰性對照不誤報 |
| T7 | 新裝＋文件化的手動回滾；文件寫明客製的 hook 在重裝時會被覆蓋。不宣稱升級 |

<a id="acceptance-w"></a>
### 4.4 Windows 驗收清單 W0–W11（凍結文字）

通則：W0–W11 必須在同一個 RC SHA、同一組版本、同一個測試帳號上跑完；任何一項紅，A2 就不通過。結果寫成 `docs/ACCEPTANCE-lts-windows-<日期>.md`；原始快照留在本機，不進 repo。

- **W0 attestation**：記錄 RC SHA；OS 的 `DisplayVersion`／`CurrentBuild`／`UBR`／`EditionID`／架構；pwsh 7 與 WinPS 5.1 的版本；`node -v`、`codex --version`、`claude --version`；`C:\npm\codex.cmd` 存在（F8 的前提）；測試帳號 `~/.codex/rules/default.rules` 的 sha256 與 allow／prompt／forbidden 條數；`~/.codex/config.toml` 中 MCP／apps 相關段的 sha256。確認是一般使用者權限、帳號由使用者親自建立、家目錄名稱不是 `user`。
- **W1 repo 樹**：照 AI-INSTALL 步驟 1a 的 Windows 區塊跑。`run-windows-suite.ps1 -Mode repo` 印出 `SUITE_RESULT=OK`（本檔撰寫時 manifest 14 列，摘要行為 `entries=14 ran=14 skipped=0 fail=0`；以 RC SHA 上的 `EXPECTED_ENTRIES`／`$EXPECTED` 為準）；`tests/ai-install/run-windows.ps1` 在兩個 host 都精確印出 `PASS=<N> FAIL=0`，N 是 RC SHA 上的 `EXPECTED_CHECKS`（本檔撰寫時 N=126）；`run-mutation-controls.ps1` 在兩個 host 都通過。
- **W2 部署**：照 AI-INSTALL 1b、1c 部署，記下 `ts`。照步驟 2 的 probe 判定表合併 settings（snippet 裡的家目錄路徑換成測試帳號的），合併後重跑 probe，判定必須是正常。
- **W3 live 樹逐位元比對**：整棵 live 樹與 RC SHA 逐檔比對。例外檔用列舉產生並具名列出，不寫死數字。
- **W4 live 套件**：`run-gate-tests.js`、`matcher-contract.test.js --live`、`run-windows-suite.ps1 -Mode live`，最後印出 `SUITE_RESULT=OK`（本檔撰寫時摘要行為 `entries=14 ran=13 skipped=1 fail=0`，跳過的是只在 repo 跑的 `no-multibyte-varref`）。
- **W5 真 Codex**：`codex-check.ps1` 的 smoke 回 OK；能力面漂移報告已記錄，並由使用者在當次明示接受（V5）。另在 en-US／code page 437 的主控台（`chcp 437`）再跑一次 `codex-check.ps1`，原樣記錄輸出（中文是否變 `?`、AI 能否據以判讀步驟 4 的通過／失敗）。這一趟是 [`CODEX-CHECK-CP437`](backlog.md#CODEX-CHECK-CP437) 的取證；在使用者裁決之前只記錄、不算通過條件，裁決之後照 [§6](#new-defect-rule) 處理。
- **W6 真 Claude Code（新 session）**：對拋棄式 repo 開超級模式（`-Scope` 指向該 repo）。
  1. 沒有憑證時，`Write`（repo 內的檔案）與 `PowerShell` 寫入指令（`Set-Content` 寫 repo 內的檔案）都要 DENY。
  2. 用代表性簡報跑鑄證模式的 consult，確認憑證鑄出、逐字稿落地。
  3. 20 分鐘內，同樣兩個動作轉為 ALLOW；`git commit` 之後，憑證剩餘時間不超過 3 分鐘。
  4. 測試帳號**不配置任何 MCP server**（這是配置邊界）。MCP 面只由 W4 的 gate-cases 覆蓋，支援矩陣要寫明「MCP 攔截未做 live 驗收」。
  5. 另記錄 hook 設定是即時生效還是下個 session 才生效；只記錄，不算通過條件。
- **W7 討論模式**：經使用者同意，以 AI-INSTALL 步驟 5 裝上全域規則，確認 marker 存在。用一個決策型提示觸發 `-NoCredential -PromptFile`：exit 0；憑證檔沒有新增、也沒有更新；逐字稿落地；首行有裁決。
- **W8 exec**：在拋棄式 repo，用出貨範本派一次小型 workspace-write 工作（與 T4 同一份簡報）。核對 `_last.txt`、`git status`（含未追蹤檔）、`git diff`、逐條 AC；確認 worker 沒有自行呼叫 consult 或 exec。
- **W9 `super-mode -Off`**：先備份 `~/.claude/super-mode-logs/` 與驗收證據（F2）；確認旗標與憑證都已清掉；並確認子目錄裡的檔與不符逐字稿檔名的檔都還在（F2 修正後的行為）。
- **W10 反向對照**：`matcher-contract.test.js --settings <漂移副本> --hook <repo 的 hook>` 必須轉紅，證明 live 檢查有牙齒。
- **W11 已知限制**：所有沒修的項目與已套用的 [§5.2](#downgrades) 文字，逐字寫進 README 的已知限制與支援矩陣。

<a id="representative-briefs"></a>
### 4.5 代表性簡報與 macOS 清單

- **代表性簡報**（T1、W6、W7 共用）：中文、自足，請 Codex 對拋棄式 repo 裡一份給定的小 diff 給出 `ALLOW:`／`BLOCK:` 首行裁決。全文在 W 階段開工前寫進 `docs/ACCEPTANCE-lts-windows-<日期>.md` 並凍結，之後不得換成更容易通過的簡報。
- **派工簡報**（T4、W8 共用）：照出貨的 `references/orchestration.md` §3 範本填寫；任務是在拋棄式 repo 新增一個小檔案和對應測試，AC 不超過三條。全文同樣先凍結。
- **M0–M10**：在 M 階段開工前由使用者核准並凍結。已定的原則：結構鏡像 W0–W11；只用 `/bin/bash` 3.2.57，不跑 brew bash；兩趟在不同的兩天；M0 記錄 python3、uuidgen、perl 是否存在；MCP 配置同 W6；codex-check 的通過標準同 W5。

<a id="a9-post"></a>
### 4.6 A9-post（PASS 之後做；不是准入條件）

每一步都另外徵得使用者同意：

1. 建立 `lts/v<版本>`，**指向簽核文字寫的 RC SHA**，不得指向其他 commit。
2. 以 PR 把 `lts/build` 合併進 `main`。Windows 准入時，README 矩陣只把 Windows 列為已准入，macOS 標「未經准入」。這次合併會把尚未准入的 macOS 側變更（例如 F2、F11／F12 的 AI-INSTALL、macOS orchestration 的 worker 契約）一起帶進 `main`，取代 macOS 使用者原本拿到的凍結快照，所以 **macOS 准入前，README 與 AI-INSTALL 要指示 macOS 使用者固定在 `pre-lts`**（另開 clone 或 `git worktree add <dir> pre-lts`；tag 建立前請用 commit `80c60a8`）。
3. 開 `main` 分支保護，要求已准入平台的 check 通過。
4. 簽核之後，產品或安裝的可執行內容只要有改動，就當作新 RC，該平台重跑驗收。

版本預設：Windows 准入 `lts/v1.0.0`；macOS 准入 `lts/v1.1.0`。

## 5. 修復清單

<a id="must"></a>
### 5.1 MUST（20 項）

「改產品」照 AGENTS.md 的定義；AI-INSTALL 的可執行區塊也算，改了要同步測試臺的案數。

| ID | 內容 | 路徑 | 階段 | 可否劃出 |
|---|---|---|---|---|
| G1 `LTS-DECISION-MEMO` | 備忘 §8：裁決原話、核准的原文、簽核紀錄 | 備忘 | S0 | 否 |
| G2 `BUILD-AUTH` | AGENTS.md「LTS 建置期」段；原文以使用者核准的版本為準 | `AGENTS.md` | S0 | 否 |
| G4 `LOCAL-EXECPOLICY-WINDOWS` 訂正 | 備忘 §1、§3、§7.1 與 backlog 就地補記「29 條已刪」 | 備忘、backlog | S0 | 否 |
| G5 `LINUX-FREEZE` | [§2.4](#linux-freeze) 兩階段 | 見 §2.4 | S0／M | 否 |
| G6 `PRE-ADMISSION-STATE` | 橫幅、tag `pre-lts`（經同意）、撤下隱含宣稱、禁用字詞 | README 等 | S0 | 否 |
| G7 `LICENSE-SECURITY-SUPPORT` | 先核對 codex-plugin-cc 的授權條款與 NOTICE（本 repo 移植過它的 prompt 契約，可能有標示義務，推論）；再補 LICENSE（預設 MIT）、SECURITY.md（GitHub 私密漏洞通報）、SUPPORT（盡力回覆、無時限、受每月上限約束） | 根目錄 | S0 核對；W 准入前補檔 | 否 |
| C1 `WINDOWS-CI` | `windows.yml`：pwsh 7 與 WinPS 5.1；runner 釘 `windows-2025`；action 釘 SHA；`permissions: contents: read`；不引用 secrets；不設 paths 過濾（只改 docs 的 SHA 也要有 run，A1 與日後的 required check 才不會缺）；金絲雀假 codex；測試前後斷言 `~/.claude` 不存在（2026-10-15 修好 consult-schema 寫進真實家目錄的問題後，這條斷言才可能成立，見 backlog [`CONSULT-SCHEMA-HOME-LEAK`](backlog.md#CONSULT-SCHEMA-HOME-LEAK)）；`run-windows.ps1` 兩個 host 都精確比對案數；suite 摘要行在 YAML 端精確比對（批次 1：`entries=14 ran=14 skipped=0 fail=0`） | `.github/workflows/`、`.github/scripts/`、`tests/**`、`windows/skills/超級模式/tests/**` | W | 否 |
| C2 `MACOS-CI` | `macos.yml`：runner 釘 `macos-26`，只用 `/bin/bash` 3.2；三支測試加 `SUT_BASH`；變異注入用 BSD 語法；接上 F2 的 `off-cleanup.tests.sh`（以一般使用者執行，精確比對 `pass=74 fail=0 skip=0`；2026-10-15 白名單收緊後由 68 改為 74） | `.github/workflows/`、`tests/**`、`macos/skills/超級模式/tests/**` | M | 否 |
| C3 codex-check host 參數化 | `codex-check.tests.ps1` 寫死用 `powershell.exe` 啟動受測腳本，改成兩個 host 都跑；pwsh 腿紅＝A1 FAIL | `windows/skills/超級模式/tests/**` | W | 否 |
| C4 POSIX 測試臺防假綠 | 在 YAML 端比對精確的 `PASS=<N> FAIL=0` | `.github/workflows/` | M | 否 |
| F1 `EXECPOLICY-ALLOW-INHERIT`，走 (ii) | 撤回「consult 唯讀」宣稱（[§5.2](#downgrades) 的 F1 原文），加〈自查程序〉；先在 Windows 測試帳號用植入的陽性、陰性對照重現。不改 consult 腳本 | README、AI-INSTALL 的自查段、兩平台 `SKILL.md`／`references/*.md` | W | 文字本身就是處置；T6 不過＝准入 FAIL |
| F2 `OFF-CLEANUP-RECURSIVE`（2026-10-14 改列 MUST；2026-10-15 使用者確認） | 資料遺失類。10/14 主代理依 [§5.2](#downgrades) 預寫的規則改列 MUST，並在批次 1 修復；表列變更依 AGENTS.md 授權第 4 點要使用者核准，所以這是先做後問（10/15 審查指出）。2026-10-15 使用者確認列入 MUST，並選擇收緊白名單（備忘 §8.7）。off 只刪 `super-mode-logs` 頂層、檔名符合 consult／exec 產生格式（後綴恰好 6 位小寫 hex，consult 另接受純數字 PID，無後綴的初版檔名也算）、超過 14 天的檔；錯誤寫 stderr（`OFF_CLEANUP_ERROR`）但 off 照常完成。實作取捨與兩平台殘留差異記在 backlog 同名列。Linux 凍結、不修 | 兩平台 `scripts/super-mode.{ps1,sh}`、`SKILL.md`、`tests/off-cleanup.tests.{ps1,sh}`、`run-windows-suite.ps1`、AI-INSTALL 步驟 1a／3 的 macOS 區塊、README | W（macOS 側 M 驗收） | 否 |
| F11 `AI-INSTALL-GAPS` | 步驟 4 提示版本組合是否已驗收（不擋安裝）；步驟 6 回報版本組合與來源 SHA；補 codex-check baseline 說明；解除安裝補上 baseline 相關檔與 `CLAUDE.md.bak-<日期>` | AI-INSTALL、`tests/ai-install/**` | W | 否 |
| F12 `RELEASE-IDENTITY` | 步驟 0 用 `git describe --exact-match` 檢查是否在 `lts/v*` tag 上，不在就警告（RC 驗收時只有 `rc-` tag，出現警告屬預期）；步驟 6 記錄來源 SHA | AI-INSTALL、`tests/ai-install/**` | W | 否 |
| `WORKER-CONTRACT-TEMPLATE`（最小版） | 出貨的派工簡報範本加最小 worker 角色契約：只改簡報列出的路徑；不得自行呼叫 `codex-consult`／`codex-exec` 或 `claude`／`codex` CLI；不讀寫 `~/.claude`。明寫這是程序控制，不是強制隔離。ultracode 的操作說明不回寫 | 兩平台 `references/orchestration.md` §3 | W | 可：套 [§5.2](#downgrades) 文字，T4 改用不含契約的範本 |
| V1 `SUPPORT-MATRIX-PINS` | README 支援矩陣填實：OS、shell、Node、Codex CLI、Claude Code 的驗收版本，與目前版本分開列 | README | W／M 驗收 | 否 |
| V2 `LIVE-ACCEPTANCE-REFRESH` | `docs/ACCEPTANCE-lts-<平台>-<日期>.md` | docs | W／M 驗收 | 否 |
| V3 配置邊界記錄與自查 | 記錄程序與使用者自查步驟，涵蓋 execpolicy、`CONNECTOR-EXPOSURE`、`GATE-SCOPE-CROSS-SESSION`、`GATE-QUOTE-LEXER` | README、docs | W | 否 |
| V4 乾淨的驗收環境 | 兩台機器各一個 OS 測試帳號，**由使用者親自建立**。代理之後只負責植入對照規則（陽性：寫標記檔到工作區外的無害 allow 規則；另配一組陰性）並跑驗收 | — | W／M | 否 |
| V5 `BASELINE-POLICY` | 每次 live 驗收由使用者明示接受 codex-check baseline 並記錄（同時了結 `BASELINE-ACCEPT-0923`）；`CODEX-CHECK-HOOKS-INVENTORY` 列為已知限制 | docs | W／M | 否 |

G3（push 分支、單一 PR 合併）屬工作方式，移出 MUST：10/14 的文件訂正已在 `lts/build` 上，隨准入合併進 `main`。

<a id="downgrades"></a>
### 5.2 降級項與已知限制（預寫原文）

規則：

- 只能套用**與 RC SHA 實際狀態相符**的那段文字，不得套用描述尚未實現狀態的文字。
- 原文由使用者核准後凍結；套用時逐字放進 README 的已知限制。
- 這些項目預設不實作。要實作須使用者核准，工時從保留撥（[§3.1](#budget)）。

**F1 `EXECPOLICY-ALLOW-INHERIT`（MUST 的處置文字）**
> consult 的 `--sandbox read-only` 不涵蓋 execpolicy 的 allow 規則：符合 allow 的命令會在沙箱外執行。本 repo 不宣稱 consult 唯讀；沒照〈自查程序〉檢查 rules 的配置不在支援範圍內。自查通過也不代表 consult 整體安全。

**F2 `OFF-CLEANUP-RECURSIVE`（資料遺失類；須使用者裁決 ACCEPTED_RISK，否則改列 MUST 修復）**——**2026-10-14 已改列 MUST（[§5.1](#must)），並在批次 1 修復；2026-10-15 使用者確認。下面這段只描述修正前的行為，不得套用到任何 RC。**
> `super-mode` 的 off 會刪除 `~/.claude/super-mode-logs/` 底下超過 14 天的檔案，沒有檔名白名單：macOS 版會遞迴進子目錄，Windows 版只清頂層。不要在該目錄存放其他檔案；要保留的逐字稿與驗收證據，跑 off 之前先移出。

**F3 `OUTFILE-CMDSAFE`**
> Windows `codex-exec.ps1` 的 `-OutFile` 不檢查 cmd 的危險字元；請勿傳入含 `%`、`!`、`"`、`&`、`|`、`<`、`>`、`^` 的路徑。

**F4 `MOUNT-RMRF`（預設 ACCEPTED_RISK；兩段文字擇一）**
- 安裝前偵測**沒有**完成並驗證：
  > skill 樹（`~/.claude/skills/超級模式`）底下有掛載點的 macOS 不在支援範圍內：安裝回滾的 `rm -rf` 會跨進掛載點、刪掉裡面的資料，而安裝流程偵測不到掛載點。
- 安裝前偵測已完成並驗證：
  > skill 樹底下有掛載點的 macOS 不在支援範圍內。AI-INSTALL 會在安裝前偵測並中止；偵測只涵蓋安裝當下，不構成回滾安全保證。

**F5 `POSIX-UUIDGEN-PYTHON3`**（相依仍要在 M0 實際驗過）
> macOS 需要 python3、uuidgen、perl；安裝流程不檢查，請先自行確認（`command -v python3 uuidgen perl`）。

**F6 `CC-AGENTS-MD`（兩段文字擇一）**
- 尚未重現：
  > Claude Code 可能讀取 worker 專用的 `AGENTS.md`（`CC-AGENTS-MD`），尚未驗證；派工簡報請自帶 worker 限制。
- 已重現：改寫成重現結果（Claude Code 版本、三組條件、觀察到的行為），不得仍寫「尚未驗證」。

**F7 `MCP-ALLOWLIST-PERSONAL`（兩段文字擇一）**
- 個人化項目已從兩份 hook 移除，且 gate-cases 已改用合成名稱：
  > hook 內建的 MCP 放行清單（`MCP_PATHLESS_ALLOW`）只剩一條例外：server 名為 UUID 形式的 Notion connector 的 `notion-create-pages`、`notion-update-page`、`notion-create-comment`。其他拿不到 repo 路徑、又不在放行清單或 policy 內的 MCP 寫入，即使有憑證也會被拒；要放行就得自己改 hook，那屬於不支援的配置，重裝時會被覆蓋。
- 沒有移除：
  > hook 內建的 MCP 放行清單（`MCP_PATHLESS_ALLOW`）有 5 項例外：維護者個人環境的 4 個 MCP 工具名稱，以及上述 Notion connector 的一條 regex。其他拿不到 repo 路徑、又不在放行清單或 policy 內的 MCP 寫入，即使有憑證也會被拒；要放行就得自己改 hook，那屬於不支援的配置，重裝時會被覆蓋。

**F8 `CODEX-PATH`**（W0 實際驗過）
> Windows 只在 Codex CLI 位於 `C:\npm\codex.cmd` 時驗收過；其他位置不在支援範圍內。腳本裡的三個覆寫環境變數是測試接縫，不是設定介面。

**F9 `EXEC-DISABLE-PARITY`**
> 只有 macOS 的 `codex-exec` 帶 `--disable remote_plugin`，Windows 沒有。這個旗標只關遠端外掛目錄，不影響已安裝的外掛與帳號 connector。

**F10 `SNIPPET-MARKER-V2`**
> 全域規則 snippet 不支援自動升級。已裝過的人要更新：先看 diff、先備份，同意後再手動替換 `BEGIN/END CODEX-DISCUSSION-PARTNER` 區塊。新裝不受影響。

**`WORKER-CONTRACT-TEMPLATE`（只在最小契約沒落地時）**
> 出貨的派工簡報範本沒有 worker 角色契約；worker 可能自行呼叫 consult／exec 或派子代理。派工時請自行在簡報寫明限制。

**維持的已知限制**
- `CONNECTOR-EXPOSURE`：
  > consult 與 exec 會繼承 Codex 帳號已連結的 connector、MCP 與 apps；skill 不限制這些工具，實際曝露取決於你的 Codex 設定。請照〈配置邊界自查〉檢查。
- `E2`（`EXEC-NO-SUBAGENTS`）：
  > Codex 程序內可以自行派子代理。本 repo 不宣稱「單一 writer pool」；派工簡報裡的限制只是程序控制。
- `E3′`：
  > `codex-exec` 不做自動成功判定：退出碼 0 不代表任務完成。每次都要核對 `_last.txt`、`git status`／`git diff` 與驗收條件。

### 5.3 不做（只揭露）

- gate 的 `GATE-*` 漏判（含 HIGH 的 `GATE-SAFE-PREFIX`）、`MCP-SERVER-READ-MATCH`：照「gate 是諮詢紀律提醒，不是安全邊界」列為已知限制。
- matcher 沒涵蓋的工具（`SendMessage`、`ArtifactData`、`ArtifactComments`、`DesignSync` 等）：逐一列出。
- 測試用的假 codex 對應 0.144.x 的輸出：揭露。
- `CODEX-CHECK-STAGE-COLUMN`、`CODEX-CHECK-EXEC-DEPENDENCIES`、`CODEX-CHECK-SURFACE-GAPS`、`CODEX-CHECK-HOOKS-INVENTORY`：改用手動記錄。
- `TOGGLE-ARG-SILENT`、`POSIX-RUNNER-ASSERTIONS`、A2 批次殘留、Windows 斷鏈 symlink、python3 fail-fast：已知限制。
- `INSTALLER-REWRITE`：不在範圍內。
- 任一項要改程式碼，須使用者逐項核准，並指定工時來源。

<a id="new-defect-rule"></a>
## 6. 新缺陷規則

建置或驗收期間新發現的缺陷，依序判斷：

1. **它會讓 MVS 任一項、或必要的 A／T 條件不成立嗎？** 會 → 只能在 AGENTS.md 授權的路徑內修，工時從保留撥，每個 ID 最多 2 輪審查。修不了、超出授權或超出預算 → 停工回報使用者裁決（擴大授權、延期或退出；預設退出）。**不得用揭露文字劃出。**
2. 不會，但屬於宣稱範圍內的 security 或資料遺失 → 使用者逐案裁決：修（工時從保留撥），或裁決 ACCEPTED_RISK 並套用已知限制文字。
3. 其他 → 降級為已知限制，登錄 backlog，不修。

每個新缺陷都在 backlog 登一列，寫明走哪一條、理由是什麼。

<a id="d4-defaults"></a>
## 7. 預設裁決（使用者可以改）

| # | 項目 | 預設 |
|---|---|---|
| D4a | F1 路徑 | (ii)：撤回「consult 唯讀」宣稱，加自查程序；不採用未驗證的 `--ignore-rules` |
| D4b | `MOUNT-RMRF`（F4） | ACCEPTED_RISK（照 backlog 的定義，要使用者明示）；預算有餘時加安裝前偵測與中止 |
| D4c | `CONNECTOR-EXPOSURE` | 不解凍；列為已知限制並附自查 |
| D4d | `E2` | 維持 PROPOSED；不宣稱單一 writer pool |
| D4e | `E3′` | 維持 PROPOSED；exec 不宣稱自動成功判定 |
| D4f | worker 契約回寫 | **改判**：最小角色契約放進出貨的派工範本（[§5.1](#must)）；ultracode 的操作說明不回寫 |
| D4g | `consult-answer.js` 訊息、維護者本機的 snippet 規則 | 不回寫 |
| D4h | `EXEC-DISABLE-PARITY`（F9） | 揭露為平台差異，不對齊 |

其他預設：

- 驗收環境：兩台機器各一個 OS 測試帳號，由使用者親自建立。
- Windows 若只有 Release Preview 版做過 live 驗收，就揭露「GA 版沒有 live 驗收」，不另加 VM。
- 重驗：每 28 天一次，對當時的最新版批次重驗；期間出現的新版本一律標「未驗收、best-effort」，到下次重驗為止；不釘版。
- plugin 自動更新：劃出配置邊界，驗收時記錄 revision。
- baseline：每次 live 驗收由使用者明示接受並記錄。
- 授權條款：MIT（先核對上游條款）；SECURITY.md 用 GitHub 私密漏洞通報。
- 支援終止日：2027-04-30；要延長由使用者裁決。

<a id="maintenance"></a>
## 8. 維護期規則與退出

| 項目 | 規則 |
|---|---|
| 負責人 | rockon8765，無備援；任一台機器不能用，該平台的支援就停 |
| 重驗 | 每 28 天一次。README 同時呈現「已驗收的版本組合」與「目前版本、未驗收」 |
| 每月檢查 | 每月一次：工時對帳（差距超過 25% 就標記）；用量月帳（consult、exec、super-mode 次數，只記數字與類別）；重驗是否在期限內；上游紅燈清單。逐字稿至少每 14 天清點一次，因為 off 會清掉 14 天前的檔案 |
| 事故上限 | 同一根因累計 8h：跨 PR、分支、重試、代理審查都算，改名不重置 |
| 每月上限 | 10h：閱讀、重驗、文件、CI、部署、代理執行都算。全面的上游漂移稽核不在範圍內 |
| 上游造成的紅燈 | 先降級，並在 README 公告；要修就算事故 |
| 審查輪數 | 每個 ID 2 輪，定義同 [§3.2](#stop-rules) |
| 受支援期間 | 只修事故，不加功能；Linux 維持凍結；每次發版跑完整驗收清單 |

**退出條件**（任一條成立就轉備忘選項 1；所有重新裁決都由使用者做）

- （2026-10-17 取消）原條件「准入逾期（已延期一次後仍未完成），或總額用滿而尚未完成」：使用者已取消總工時上限與截止日（[備忘 §8.9](DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)），這條沒有適用對象了；目標日沒達成時照 [§3.3](#checkpoints) 的檢查點處理。
- 單一事故超過 8h；連續 2 個月超過 10h；單月超過 20h 時交使用者裁決，預設退出。
- 配置無法維持：機器不能用，或上游拿掉 exec 依賴的旗標。
- 各能力分開計算，連續 2 個月沒有自然使用就撤掉該項支援。只計外部專案的自然任務；有一次使用**不構成**續維理由；consult 的用量有一部分是全域規則自己產生的，不能單獨當證據。
- 支援終止日到期。
- 官方替代驗收通過：官方 codex-plugin-cc 在 T1、T2 達成相同的使用者可見結果，consult 就退場；在 T4、T5 達成，exec 就退場。gate 與 installer 沒有官方對應功能，只依上面的時間與用量條件退場。功能公告或名稱相似不算等價。

## 9. 待使用者核准或決定

1. 本檔 [§4](#admission)、[§5.2](#downgrades) 的原文（核准後凍結）。AGENTS.md 建置期段的原文已於 2026-10-17 由使用者逐字核准（備忘 §8.9）。本檔這兩段核准前所有工作只留在本機的 `lts/build`，不 push、不動 `main`。使用者授權過五次對 `lts/build` 的單次 push：2026-10-15 一次、2026-10-17 四次（備忘 §8.7、§8.9），這不等於本點已核准。
2. tag `pre-lts` 的建立與 push（LTS 前的凍結快照與 Linux 最終快照共用這一個名稱）。
3. F2：2026-10-15 使用者已確認列入 MUST，並選擇收緊白名單（備忘 §8.7；實作取捨見 backlog [`OFF-CLEANUP-RECURSIVE`](backlog.md#OFF-CLEANUP-RECURSIVE)）。**仍待裁決**：F4 的 ACCEPTED_RISK。Codex 10/15 補充：若接受，風險範圍應涵蓋回滾當下才存在的掛載點（包括備份之後才掛上的）；日後若授權技術修補，優先評估在 `rm -rf` 前重新偵測並中止，而不是只做安裝前偵測。
4. 待裁決的缺陷：[`CODEX-CHECK-CP437`](backlog.md#CODEX-CHECK-CP437)（en-US／cp437 主控台的中文輸出變 `?`）、[`CODEX-CHECK-WARNING`](backlog.md#CODEX-CHECK-WARNING)（原本延後的前提已失效），以及 2026-10-15 新發現的 [`CONSULT-TOKEN-REPLACE-FLAKE`](backlog.md#CONSULT-TOKEN-REPLACE-FLAKE)（覆蓋既有憑證偶發 exit 44；會讓 CI flaky、擋 A1；修法屬產品變更）。
5. 兩台機器的測試帳號（由使用者建立）；Mac 的兩段時段。
6. [§3.3](#checkpoints) 的目標日、支援終止日、授權條款。
7. 每一次 push、打 tag、合併 PR、改 repo 設定。
