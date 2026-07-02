# Codex-for-CC — 超級模式 (Super Mode)

一個 **Claude Code** skill：讓 Claude 當**指揮（orchestrator）**、**OpenAI Codex CLI** 當**執行（worker）**，把繁重的實作工作外包給 Codex（藉此節省 Claude Code 用量），而 Claude 專注在規劃、審查、並以 spec 當作合約。

一個 `PreToolUse` 的 **consult-gate** hook 負責強制這套紀律：超級模式啟用期間，會改變狀態的工具呼叫（寫檔、shell、MCP 寫入、外發型內建工具）**預設一律拒絕（default-deny）**，除非 Claude 手上有一份 20 分鐘內、由「先跑一次唯讀 Codex 諮詢」換來的「第二意見」憑證。

---

## 兩個平台版本

這個 repo 為**兩個平台提供同一個 skill**。它們**行為等價** — 相同的發現、相同的不變量（I1–I8，外加 macOS 專屬的 I9）、相同的驗收條件 — 但*實作機制*依平台翻譯（PowerShell vs bash、BOM 處理、stdin 佈線、路徑規則）。挑你機器對應的那個：

| | [`windows/`](windows/) | [`macos/`](macos/) |
|---|---|---|
| Hook/腳本執行環境 | PowerShell 5.1 + Node | bash/zsh + Node |
| 執行腳本 | `*.ps1` | `*.sh` |
| Codex CLI 位置 | `C:\npm\codex.cmd`（寫死） | `PATH` 上的 `codex`（Homebrew npm global） |
| Gate 拒絕機制 | `permissionDecision` / exit 2 | stderr + exit 2 |
| 接 hook 的設定檔 | `settings.json` | `settings.local.json` |
| 修復紀錄 | [`windows/skills/超級模式/FIX-PLAN.md`](windows/skills/超級模式/FIX-PLAN.md) | [`macos/skills/超級模式/FIX-PLAN.md`](macos/skills/超級模式/FIX-PLAN.md) |

> **現況。** 對 Windows 版的稽核找出了幾個真實問題（一個 gate 繞過、Codex 靜默失敗、成本反模式）；Phase 1–4 已實作、驗證並部署，Phase 5 已評估。macOS 版是這份工作的**已驗證移植** — 發現與不變量沿用、機制翻譯，並以 34 案例回歸測試臺 + 真實端到端跑驗證過。各平台完整的逐步紀錄在各自的 `FIX-PLAN.md`（上表連結）。

---

## Claude vs Codex — 誰在哪裡跑（請先讀這段）

一個常見誤解：*「我開 Claude Code 的 UltraCode 模式時，子代理就會變成 Codex。」* **不會。** 這個專案有**兩套彼此獨立**、但很容易被混為一談的機制：

**1. Claude Code UltraCode / Workflow — Anthropic 自己的多代理**
- 它派出去的子代理**永遠是 Claude 模型** — 絕不是 Codex。
- 它們的 token **全額計入你的 Claude 額度**（沒有折扣；你可以把個別 agent 指定成 Haiku 來降成本，但它們仍然是 Claude）。
- 所以 UltraCode 本身**不會省 Claude 用量 — 反而更花**（更多 Claude agent = 更多 Claude token）。它的用途是*品質*（多角度、對抗式審查），不是省錢。

**2. 這個 skill 的 Codex offload — 省 Claude 用量真正的來源**
- Codex **不是一種子代理類型** — UltraCode 無法派出「Codex agent」。
- Codex 只在**一個地方**做事：主線的 Claude（orchestrator）主動 shell out 去跑 `codex-exec`（Windows 是 `.ps1`／macOS 是 `.sh` → `codex exec`）。那是一個獨立的外部 CLI 程序，算在你的 ChatGPT/Codex 方案上 — **不是**你的 Claude 額度。
- 把繁重的實作工作交給 Codex，才是省 Claude 用量的關鍵。

兩者疊在一起時（見 skill §5）：

```text
主線 Claude（orchestrator）
├─ UltraCode Workflow ─────► 派出【Claude 子代理】：唯讀的研究 / 規劃 / 審查
│                            （Claude — 算你的 Claude 額度）
└─ 主線 Claude 派工 ───────► shell out 跑 `codex exec` ─► 【Codex】：實際寫程式
                            （Codex — 算你的 ChatGPT / Codex 方案額度）
```

**鐵則（§5 強制）：** Workflow/子代理**絕不可**自己呼叫 Codex — 只有主線 orchestrator 能派 Codex。否則 N 個平行的 Claude 子代理會各自 shell out 去跑 Codex，燒爆 Codex 額度、還互搶那份唯一共用的諮詢憑證。

**結論：** UltraCode → *更多* Claude；省 Claude 用量 → Codex offload。它們是**不同的旋鈕**，可以搭配（Claude 子代理審查、Codex 寫程式）— 但開 UltraCode 永遠不會把子代理變成 Codex。

---

## 這個 repo 有什麼

```
windows/                         # PowerShell 版（已稽核、已部署）
  settings.snippet.json
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  FIX-PLAN.md  references/orchestration.md
    scripts/  super-mode.ps1  codex-consult.ps1  codex-exec.ps1  codex-check.ps1
    tests/    run-gate-tests.js  run-gate-tests.ps1  gate-cases.json

macos/                           # bash 版（已移植、已驗證）
  settings.snippet.json
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  FIX-PLAN.md  references/orchestration.md
    scripts/  super-mode.sh  codex-consult.sh  codex-exec.sh  codex-check.sh
    tests/    run-gate-tests.js  run-e2e.sh  gate-cases.json
```

## 運作方式（一個里程碑）

下面的指令用 macOS（`.sh`）的名稱；Windows 對應的是 `.ps1` 腳本、用 `-On/-Off/-Scope` 之類的 flag（見 [`windows/`](windows/)）。

1. **啟用**並指定專案範圍：`super-mode.sh on --scope <repo>`（寫入 `~/.claude/.super-mode-active`）。
2. **Spec-first** — 沒有講好的 spec/plan md 就不動手實作。
3. **動手前先諮詢** — 把簡報寫進 scratchpad，跑 `codex-consult.sh`；成功後會寫入 `~/.claude/.super-mode-consult-ok`，解鎖被 gate 攔的動作 20 分鐘。
4. **派工** — 寫一份自足的任務簡報，在背景跑 `codex-exec.sh -q`；由 Codex 寫程式。
5. **審查** — Claude 審 `_last.txt` + `git diff`；不合格就退回重派。
6. **里程碑回寫** — 勾掉 spec md 的項目，然後 commit（commit 會把憑證降到剩 3 分鐘，逼下一個里程碑重新諮詢）。
7. **關閉** — `super-mode.sh off`（清掉旗標 + 憑證，並清除超過 14 天的 log）。hook 也會自癒：超過 8 小時的旗標會被視為殘留並自動移除。

**設計上就是 fail-open：** 沒有旗標、或 hook 出任何錯 / 輸入異常時，gate 一律放行 — 一般（非超級模式）的 session 絕不會被卡住。

## 安裝

**macOS**
```bash
# 1. Skill → ~/.claude/skills/    2. Hook → ~/.claude/hooks/
cp -R "macos/skills/超級模式" ~/.claude/skills/
cp    "macos/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
# 3. 把 hook 接到 ~/.claude/settings.local.json（見 macos/settings.snippet.json），
#    並把絕對路徑改成你自己家目錄的路徑。
# 4. 驗證：
node ~/.claude/skills/超級模式/tests/run-gate-tests.js   # PASS 34/34
bash ~/.claude/skills/超級模式/tests/run-e2e.sh          # 11 passed
```

**Windows**
```powershell
Copy-Item -Recurse ".\windows\skills\超級模式" "$env:USERPROFILE\.claude\skills\"
Copy-Item ".\windows\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\"
# 然後把 hook 接到 ~/.claude/settings.json（見 windows/settings.snippet.json）。
```

hook **在啟用前是 fail-open 且停用的** — 安裝它不會影響一般 session；只有在 `super-mode.{sh,ps1} on` 之後才會作用。

## 環境假設（請依你的機器調整）

**macOS**
- **bash/zsh** 執行環境；hook 用 **Node**；`codex` 在 `PATH` 上（Homebrew npm global 在 `/opt/homebrew/lib/node_modules/@openai/codex`）。腳本（用 `$HOME`）與 hook（`os.homedir()`）都沒寫死路徑；只有 `settings.local.json` 裡的 hook 指令需要你的絕對家目錄路徑。
- 路徑等價已處理：gate 會把 `/private/tmp` ↔ `/tmp`、`/private/var` ↔ `/var` 正規化，讓 Claude Code 的 scratchpad（`/private/tmp/claude-*`）被正確當成豁免的暫存路徑。

**Windows**
- **Windows 11**、**PowerShell 5.1** 執行環境。**Codex CLI** 在 `C:\npm\codex.cmd`（位置不同就改 `$codexCmd`）。使用者家目錄在 settings matcher 指令與部分文件中寫死為 `C:\Users\user`。

**兩者共通**
- 認證：腳本用你已登入的 Codex CLI（沒有內嵌、也不需要 API key）。
- **Codex CLI 大約每週改版** — flag/行為會漂移。任何碰到 Codex flag 的地方，先用 `codex exec --help` 重新確認（各 FIX-PLAN 的 Phase 0/5 都這樣假設）。

## 已知的坑（血淚換來的）

**Windows 專屬** — **不要**移植到 macOS：
- Claude 的寫檔工具產生的是**無 BOM** 的 UTF-8；PowerShell 5.1 讀無 BOM 的含中文 `.ps1` 會亂碼。改完任何 `.ps1` 後，要重新補上 UTF-8 BOM 並重新驗證語法（見 `windows/.../FIX-PLAN.md` §0.5）。
- 簡報透過 `cmd /s /c "... < file"` 餵給 Codex，因為 PS 5.1 的 `$OutputEncoding` 對 native pipe 不生效（非 ASCII 會變成 `?`）。

**macOS**
- 沒有 BOM 問題 — 那些步驟已刻意移除。簡報以一般 stdin 重導向（`< file`）送給 Codex；stderr 收到獨立檔再併進 log（絕不用 `2>&1`，那會把 Codex 的雜訊回灌進 Claude 的 context）。
- `set -e` + pipeline 會吞掉 Codex 的 exit code — 腳本用固定的 `set +e … ${PIPESTATUS[0]} … set -e` 寫法（FIX-PLAN §0.5）。

## 現況與後續

每個平台都有一份分階段、弱 AI 可照做的修復計畫（每一步都有目的 / 驗收 / 對抗未來變化 / 回滾，另含不變量清單與回歸測試臺規格），且本身都經過對抗式驗證：

- Windows：[`windows/skills/超級模式/FIX-PLAN.md`](windows/skills/超級模式/FIX-PLAN.md)
- macOS：[`macos/skills/超級模式/FIX-PLAN.md`](macos/skills/超級模式/FIX-PLAN.md)
