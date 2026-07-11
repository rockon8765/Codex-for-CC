# 超級模式 consult-gate — 姿態決策紀錄（Posture ADR，2026-07）

> 這是三平台 hook 檔頭（`super-mode-consult-gate.js`）引用的定案紀錄。
>
> 第二輪安全稽核的**完整執行紀錄**（Codex ultra 反方 N1–N8 / C1–C13、P0.1 三輪對抗迭代、
> 探針臺、逐輪 token 成本）**未併入 main**——它描述的是 `security/consult-gate-p0.1-candidate`
> 分支的中間 gate 狀態，放進 main 會讓讀者把 candidate 的階段性改動誤當 main 現況。
> 完整版保存在該 candidate 分支的同名檔與 git history。本檔只保留**穩定的姿態決策**與**已知殘餘**，
> 這些不隨分支狀態變動、對外誠實。

## ✅ 定案（2026-07-11）— 姿態 A：gate = 諮詢紀律提醒，非安全邊界

consult-gate（`super-mode-consult-gate.js`）的定位是**盡力而為的諮詢紀律提醒**，對「合作型 Claude」有效；
**不是安全邊界**。三個查證磁碟的事實決定了這個定位：

1. **`super-mode.ps1 -Off` 是一鍵解除、且是設計行為**——`-Off` 在 gate 的放行白名單、會刪掉旗標憑證，
   deny 訊息本身就教 Claude 這樣關。gate 從來不是對抗性邊界。
2. **test-runner confused-deputy**——`npm test` / `pytest` 白名單只看命令字串、不看子程序副作用；
   跑一個惡意 repo 的測試會以使用者權限任意執行。連合作型 Claude 都可能誤中。
3. **`--sandbox read-only` 只包 `codex-consult` 子程序**，不包主 Claude 的 Bash/PS/Edit/MCP；
   Windows 原生無內建 Bash sandbox（要 WSL2）→「靠 OS sandbox 兜底」在 Windows 標的是反事實。

**推論**：gate 是 fail-open + regex 分類 + 對手可掌控輸入的機制，本質做不到「不可繞過」。
因此**停止**對 shell verb（`sort -o` / `env CMD`）、NTFS 8.3 短名、symlink 等繞過路徑做窮舉硬化
（那是負面清單窮舉的無底洞）。改為**據實標示**：README / SKILL / hook 檔頭都已標明「非安全邊界」。

真正的安全邊界需要獨立的 containment 平面（OS 級 sandbox / 受限帳號 hard-fail + typed capability
取代 raw shell 猜測 + push/publish broker + MCP 逐工具授權）＝另案大工程，個人/小團隊工具**暫不投**。

### 威脅模型（明訂——姿態 A 保護什麼、不保護什麼）

- **在保護範圍內**：合作型 Claude 因**疏忽**跳過諮詢紀律（漏諮詢就 commit / publish / 派工 / 改安全關鍵檔）。
  gate 把這類失誤擋下、要求先諮詢。這是它唯一可靠達成的性質。
- **不在保護範圍內**（要涵蓋必須走上述 containment 平面）：
  ① 蓄意繞過的 agent（`-Off`、等價 shell verb、alias / wrapper / API / MCP 皆可解除）；
  ② 被 prompt-injection 挾持的主 Claude；
  ③ 惡意 repo 經 test-runner / build 的 confused-deputy 任意執行；
  ④ 無 OS sandbox 時主 Claude 的整個工具面。

## realpath 縱深硬化（P0.1）

三平台 hook 的路徑正規化（`canonicalize()`）在目標平台（`process.platform !== 'win32'`）會對「最近存在的祖先」
呼叫 `fs.realpathSync.native()`，解 symlink / 大小寫 / `/private` 別名後再接回尾段，
讓「經 symlink 指向安全關鍵檔（`settings.json` / hook 本體 / 旗標憑證）」的寫入不會靠詞法 fallback 逃逸。

**定性**：這是 best-effort gate 的**縱深防禦硬化**，**不是**邊界宣稱——它讓「疏忽型」誤放行少一條路，
但不改變上面的威脅模型（蓄意繞過仍有其他路）。

**原生驗證狀態**（realpath 分支只在非 win32 執行，故各平台需在其目標平台原生跑過才算數）：

| 平台 | 狀態 |
|---|---|
| Windows | 原生 win32 通過（realpath 分支在 win 走詞法 fallback，非重點；gate-cases + 8.3 test 綠） |
| Linux | 原生通過（WSL2 / ext4 / glibc / Node v22：gate-cases 全綠 + live symlink 探針證明 realpath 真解析、非死代碼） |
| macOS | **待原生驗證**（BSD userland / `/private` 摺疊 / APFS 大小寫語義與 Linux 不同，不能由 Linux 結果背書） |

## Z 案（MCP 誤分類的完整解法，backlog）

現行 MCP 唯讀判定是無邊界 substring（名字含 `get`/`read`/`resolve`/`view` 就傾向放行）。
已知有名字帶 read-y 字、實際有外發副作用的工具（`set_budget`、`resolve_comment`、`mark_as_read`、
`reply_to_thread`、`request_copilot_review` …）。**現況只做 Y0**：`MCP_FORCE_GATE_ACTION` 精確封已證實清單
（比對 action 尾段、不看 server 名），最小改動、對唯讀 heuristic 零 regression；未列舉的新變體仍可能漏放行
（gate 非邊界＝已接受殘餘）。

**完整解法 Z（backlog，姿態 A 下暫不投）**：action 分詞 + 寫入 token 優先 +
`FORCE_ALLOW` / `FORCE_GATE` 兩張 exact 例外表 + 把未知 MCP 從 policy-only harddeny 改為「諮詢後可解鎖」的三態授權。

## 其他已知殘餘（非本關失敗、姿態 A 下據實列出）

- **case-sensitive APFS（macOS）**：mac hook 的 `norm()` 無條件 `toLowerCase()`（配合 APFS 出廠預設的
  大小寫不敏感）。**支援範圍＝macOS 出廠預設的 case-insensitive APFS**。在**選用**的 case-sensitive APFS 卷上，
  `.claude` 與 `.CLAUDE` 是不同目錄，lowercase 可能把 `.CLAUDE/…` 誤認為 `.claude` 豁免區→誤放行。
  這是姿態 A 下明訂的**支援範圍外**情形，非本關失敗。
- **`/private/tmp`（Linux）錯 oracle**：linux hook 無條件把 `/private/tmp`→`/tmp`（源自 mac 語義，對 linux 是
  過度豁免，因 linux 的 `/private/tmp` 不是 `/tmp` 別名）。低衝擊（提醒過度豁免、非邊界洞）。
- **firmlink（macOS）**：`/Users/…` 與 `/System/Volumes/Data/Users/…` 可能同 inode；`norm()` 只摺 `/private`，
  未統一 Data-volume firmlink 的雙路徑。
- **TOCTOU**：canonicalize 檢查與實際寫入之間，symlink 可被替換。
- **hard link**：realpath 不統一 hard link；canonical path 本就不保證唯一。
- **raw actionPath**：token / repo 範圍比對仍用 raw 路徑，非 canonical identity。
- **Bash / MCP 路徑判定**：未同享 realpath 保護（只有檔案寫入類工具走 canonicalize）。
