<!-- INSTALL-GUIDE：本段是給「安裝助手 AI」的指引，請保留。
     若超級模式之後要為本 repo 生成派工共用規範，請附加在本段之下，不要覆蓋本檔。 -->
# 給 AI agent 的指引

## 🚧 LTS 建置期（2026-10-14 起；准入前不得宣布支援）

**在動手做任何事之前先讀這段。** 使用者已於 2026-10-14 裁決公開 LTS：平台只有 Windows 與 macOS，範圍是全功能，Linux 凍結。同日使用者以原話「我以為你已經開始修改了，結果花一堆時間在評估時間嗎」指示即刻開工，並選定方向：准入順序「Windows 先、macOS 隨後 (Recommended)」、預算「115h／2027-01-15 (Recommended)」、每週投入 8–10h「可以」（這三項是使用者選擇的選項原文，不是打字原話）。2026-10-17 使用者取消了工時上限與截止日（見[備忘 §8.9](docs/DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)）。原話與選項的逐項紀錄見 [`docs/DECISION-MEMO-lts-2026-09-30.md` §8](docs/DECISION-MEMO-lts-2026-09-30.md#lts-decision-2026-10-14)，計畫見 [`docs/LTS-ADMISSION-PLAN.md`](docs/LTS-ADMISSION-PLAN.md)。

✅ **本段原文已於 2026-10-17 由使用者逐字核准**（計畫 §9 第 1 點）：使用者先選「要改措辭」，打字提出「不要設定工時上限」，再對修改後的全文選擇「核准」（見[備忘 §8.9](docs/DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)）。計畫 §4、§5.2 的原文仍待核准；在那之前，所有工作仍只留在本機的 `lts/build`：不 push 任何東西（分支、tag 都不推）、`main` 完全不動（下面「地點」的兩種例外也不做）（計畫 §9 第 1 點、[備忘 §8.7](docs/DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-15)）。已獲使用者授權的例外都是對 `lts/build` 的單次 push，不推 tag、不動 `main`：2026-10-15 批次 1 的 commit（[備忘 §8.7](docs/DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-15)）；2026-10-17 四次：10/17 上游漂移稽核 commit、取消工時上限並記錄本段核准的 commit、計畫 §8 訂正與 10/28 報告骨架的 commit，以及 10/28 報告 §3 與 consult 改回跟隨 config 補記的 commit（皆見[備忘 §8.9](docs/DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)）。

預設仍是**禁止**：只有下面列出的項目獲得授權，其餘產品變更——`windows/`／`macos/`／`linux/` 底下的腳本與 hook、`tools/`、CI 設定，以及為它們新增的測試——一律不准動。

**地點**：建置只在分支 `lts/build` 進行。`main` 維持凍結快照，到准入才以 PR 合併；在那之前，`main` 只收兩種例外，**每一次都要使用者逐案核准**：① 純文件 commit（例如 README 橫幅）；② 帶 `UNFREEZE <backlog-ID>` 四行的修復，只限已出貨（`main` 上）且可重現的 security 缺陷、資料遺失或上游 breakage（見下方「歷史」）。

**授權範圍（只在 `lts/build`）**

1. **CI**：新增 Windows、macOS 的 workflow；`.github/workflows/linux.yml` 只准刪除（Linux 凍結第二階段）。
2. **測試 host 參數化與證據輸出**：只准做 host／bash 參數化、案數斷言、證據輸出、合成測資。不得放寬任何既有斷言。
3. **Linux 凍結機制**：照計畫 [§2.4](docs/LTS-ADMISSION-PLAN.md#linux-freeze)。`linux/` 只准在第二階段整樹刪除（前提是 macOS CI 已綠），其他任何修改都不准。
4. **MUST 清單**：只限計畫 [§5.1](docs/LTS-ADMISSION-PLAN.md#must) 表列的 ID 及其「路徑」欄。表的任何增刪改都要使用者核准。改 `docs/AI-INSTALL.md` 的可執行區塊算這一項，改了要同步測試臺的案數。
5. **文件**：事實訂正、Linux 凍結標註、backlog 與支援矩陣的狀態維護；**不得改行為規則**（SKILL.md、`references/*.md`、全域規則 snippet 裡規定 AI 怎麼做的條文），計畫 [§5.1](docs/LTS-ADMISSION-PLAN.md#must) 表列的 F1、`WORKER-CONTRACT-TEMPLATE` 除外。

**不在授權內**

- 新功能；計畫列為降級項的便利項目（除非使用者核准）；`INSTALLER-REWRITE`、`GATE-*` 修補。
- `main` 上的任何變更（「地點」所列兩種逐案核准的例外除外：純文件 commit、`UNFREEZE` 修復）。每一次 push、打 tag、合併 PR、改 repo 設定，都要使用者逐次同意。
- 下面這些理由仍**不構成**例外（2026-08-28／29 實際被用過）：
  - 「這是在途工作，只差收尾」
  - 「這是 P0」——若該缺陷**只存在於未合併分支**，那是分支自己引進的，不是已出貨事故
  - 「parity 要求一起改」——包括「Linux 也要一起改」
  - 「已經投入很多測試了」（sunk cost 不是理由）
  - 「只是文件／只是測試」——測試與 CI 接線**同樣算**產品投資

**停止規則**

- **不設總工時上限與截止日**（使用者 2026-10-17 裁決，見[備忘 §8.9](docs/DECISION-MEMO-lts-2026-09-30.md#user-decisions-2026-10-17)；原為 115h／2027-01-15，到上限就停工、預設退出）。工時照樣記在 [`docs/LTS-timelog.md`](docs/LTS-timelog.md)，只當紀錄；計畫 §3.1 的分配數字只是預警，用來重新預測。
- **每個 ID 最多 2 輪審查**；拆 PR、改名都不重置。第 2 輪後仍有阻擋問題：停下交使用者裁決，不得把「不再審」當成「已通過」。
- **新缺陷**：會讓最低範圍（MVS）或必要的准入條件不成立的，只能在上面的授權範圍內修，或交使用者裁決／退出，**不得用揭露文字劃出**。其他照計畫的[新缺陷規則](docs/LTS-ADMISSION-PLAN.md#new-defect-rule)。
- **檢查點 2026-10-28**：依關鍵產物判定，見計畫 [§3.3](docs/LTS-ADMISSION-PLAN.md#checkpoints)。

**commit 標記**（沿用 UNFREEZE 的四行格式，缺一不可）：

```
LTS-BUILD <ID>
範圍：<只動哪些檔>
時限：<幾個 commit／到什麼條件為止>
停止條件：<什麼情況要停下來回報，而不是繼續修>
```

**准入**：Windows 先、macOS 隨後；條件見計畫 [§4](docs/LTS-ADMISSION-PLAN.md#admission)。**PASS 只能由使用者在對話中簽核**（原文記入備忘 §8）；Codex 審查判 FAIL 時，Claude 不得推翻。准入前，README、AI-INSTALL、tag 訊息都不得宣稱受支援。

**唯讀驗收不受限**：把既有版本部署到 live、跑既有測試套件、記錄結果。驗出紅燈照新缺陷規則處理，不邊驗邊修。

**歷史**：2026-08-29 至 2026-10-14 產品層凍結（裁決依據見 [`docs/plugin-reeval-2026-08.md`](docs/plugin-reeval-2026-08.md)；覆核題「永久封存或 LTS」由備忘 §8 了結）。凍結期唯一允許的例外是可重現的、已出貨（`main` 上）的 security 缺陷、資料遺失或上游 breakage，commit 要帶 `UNFREEZE <backlog-ID>` 加同樣的範圍／時限／停止條件三行。建置期間 `main` 仍是凍結快照，這條例外就是上面「地點」所列 `main` 的第二種例外，每一次都要使用者逐案核准；准入後的事故也用 `UNFREEZE`。

---

**Guard：本文件的安裝指令只在「使用者明確要求安裝本 repo」時適用。**
若你是被派工做一般 coding 任務的 worker（例如經由 `codex exec`），請忽略以下安裝指令，並且**不得**讀寫使用者的 `~/.claude` 目錄。

## 安裝本 repo

安裝流程的唯一真相：[`docs/AI-INSTALL.md`](docs/AI-INSTALL.md)。步驟摘要：平台偵測（windows/ 或 macos/；Linux 已凍結，偵測到就停止，見 AI-INSTALL §0）→ 複製 skill 與 hook → 合併 settings snippet → 跑測試驗證 → `codex-check` 確認 Codex CLI 可用 → （經使用者同意後）把 `CLAUDE-global-rule.md` snippet append 進使用者的 `~/.claude/CLAUDE.md`。

硬性防護（不可省略）：

- 改 `~/.claude/CLAUDE.md` 前：**徵得使用者同意、展示將寫入的全文、先備份、冪等**（檔內已有 `CODEX-DISCUSSION-PARTNER` marker → 不重複 append，只替換 marker 區塊）。
- Codex CLI 不可用 → **跳過**討論夥伴規則步驟並明確告知使用者；skill 本體照常安裝（fail-open）。
- 測試有 FAIL → 停下來回報，不要繼續。
