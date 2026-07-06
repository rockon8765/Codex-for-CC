<!-- BEGIN CODEX-DISCUSSION-PARTNER v1 source: https://github.com/rockon8765/Codex-for-CC (windows) -->
## Codex 討論夥伴（常駐）

凡是要交給使用者的**決策型輸出**——方案選項、建議、規劃、設計/架構判斷、風險評估、策略、結論性判斷——**交付前先諮詢 Codex 討論**，再由 Claude 裁決。團隊約定：重要判斷需經 Codex 反方檢核；Claude 保有最終決定權。

- **可跳過**：純事實問答（查檔、查狀態、一句話能答）、純執行進度回報、翻譯/改寫、機械性小修。拿不準算不算決策型 → 問。
- **做法**：簡報用 Write 工具寫進 scratchpad → 用 PowerShell 工具跑
  `~/.claude/skills/超級模式/scripts/codex-consult.ps1 -Dir <相關 repo；無 repo 用目前工作目錄> -NoCredential -PromptFile <brief>`（工具 timeout 360000ms；`-NoCredential` = 討論模式，不 mint 超級模式憑證）。
- **簡報必須逼 Codex 當反方**：附上 Claude 初判，明文要求它：反對初判、給失敗情境、給替代排序、標注信心。不准寫成引導它附和的簡報。每個反對點答四問（什麼會壞／為何脆弱／影響／怎麼改）；安全就直說不灌水；推論須標注。
- **單輪為預設**（Claude 初判 → Codex 挑戰 → Claude 裁決）；只有 Codex 指出致命風險、雙方結論相反、或決策不可逆/高成本時才加問第二輪，**上限 2 輪**。
- **回覆使用者時標注 Codex 立場**（同意/反對/補充了什麼）與最終裁決理由；有分歧要明說，不可默默採納或默默忽略。
- **非工程主題也照問**，但 Codex 定位是**結構化反方**（漏了什麼、假設哪裡弱、排序合不合理），不是領域權威；事實與即時資料另行查證，由 Claude 負責。
- **超級模式啟用時**：其 SKILL.md §3.5 里程碑諮詢節奏優先，勿雙重諮詢；那時**不加** `-NoCredential`（要正常 mint 憑證）。
- **失敗處理**：看到 `CONSULT_UNAVAILABLE_QUOTA`（exit 42）或連續失敗 ≥2 次 → 本 session 停用討論、直接告知使用者並照常交付純 Claude 結論，勿空轉重試。
- **隱私**：諮詢逐字稿落地 `~/.claude/super-mode-logs/`；涉敏感個資/財務明細的討論，簡報只放去識別化摘要。
<!-- END CODEX-DISCUSSION-PARTNER -->
