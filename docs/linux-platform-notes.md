# 超級模式 — Linux 平台差異與部署注意事項

> **這份是現行參考，不是史料。** 記錄 Linux 版與 macOS 版的實際差異、Linux 專屬的部署坑、
> 以及最近一次原生驗證的結果。安裝或修改 `linux/` 之前先讀 §3。
> （2026-07-27 從 `linux/skills/超級模式/FIX-PLAN.md` 移出——它不該躺在會被整個目錄複製到
> `~/.claude/skills/` 的安裝 payload 裡；已完成的修復／移植過程史料改放 [`history/`](history/)。）
>
> 版本：2026-07-03 v1.0 ｜ 依據：本 repo 的 macOS 版（`macos/`，其移植過程紀錄與 I1–I9 不變量定義見 [`history/FIX-PLAN-macos-2026-07-03.md`](history/FIX-PLAN-macos-2026-07-03.md)）
> 性質：**起初是機械式移植**（2026-07-03），所有發現、不變量（I1–I9）、驗收條件沿用 macOS 版。
> ⚠️ **但 2026-07-26 起，「差異只剩 BSD vs GNU userland」這句已不成立**——下表已按實測重寫。真實狀況：hook 有 3 處**平台語義**差異、`codex-check.sh` 有一整層功能尚未移植（macOS 549 行 vs Linux 123 行）、`codex-exec.sh` 有一處**三平台不一致**。本文件只記錄「哪裡不同、為什麼、怎麼驗」。
> 語言慣例：說明用繁體中文；程式碼／指令／檔名／旗標一律英文。

---

## 1. 與 macOS 版的逐檔差異

| 檔案 | 差異 | 原因 |
|---|---|---|
| `hooks/super-mode-consult-gate.js` | ❌ **不相同**（vs macOS：+12 / −10 行）。**現存 2 處是真實語義差異、其餘是註解**：<br>① `norm()`：macOS `toLowerCase()`（APFS 大小寫不敏感），Linux **不 lowercase**（否則 `/home/user/Proj` 會被誤判在 `/home/user/proj` 內）<br>② `isRunnerTouchingSensitive()`：Linux **case-preserving**，與 `norm()` 對齊（避免 home/tmpdir 含大寫時漏偵測）<br>（**已消除**的第三項：`isSecurityCriticalPath()` 的 `.codex-check-baseline` 於 2026-07-26 補上——補前 Linux 上寫該檔**零憑證放行**，與 win/mac 不一致。⚠️ 這是**為未來功能預留**的保護路徑：產生該檔的 `codex-check` baseline 功能在 Linux 版**尚未實作**。） | 平台檔案系統大小寫語義不同。**①②勿與 mac 版互抄**——實測誤植成 `toLowerCase()` 後，真 Linux 上 gate-cases 由 120 掉到 118，且失敗的只有專為此設計的兩案（在 Windows 主機上跑則會假綠，見 §4.1） |
| `scripts/codex-consult.sh` | **逐位元組相同**（實測 SHA256 相符） | 純 POSIX + codex CLI，無 BSD 依賴 |
| `scripts/codex-exec.sh` | ❌ **不相同**（2 行）：macOS 有 `--disable remote_plugin`，Linux **沒有** | ⚠️ **這不是 Linux 落後，是三平台不一致**——`windows/codex-exec.ps1` 同樣沒有；該旗標是 Mac 端單方面加的硬化（`8bbd43f`）。維護者已明確**暫緩**收緊 `--disable`，故本版**刻意不移植**。要改請三平台一起改 |
| `scripts/codex-check.sh` | ❌ **差距遠不只 `stat`**：macOS **549 行** vs Linux **123 行**。Linux 只有 H1–H5（版本抽取／npm watchdog／能力探測），**能力面盤點與 baseline diff 整段不存在**（`capability`/`baseline` 關鍵字：macOS 25／58 處，Linux **0／0**） | 移植中的開發項目。規格見 [`docs/handoff-0143-capability-surface-port.md`](handoff-0143-capability-surface-port.md) 與 [`docs/handoff-capability-baseline-port.md`](handoff-capability-baseline-port.md)。共通的 `stat -f %m` → `stat -c %Y` 翻譯仍成立 |
| `scripts/super-mode.sh` | `stat -f %m` → `stat -c %Y` | 同上 |
| `tests/run-gate-tests.js` | **逐位元組相同** | 佔位符機制（`__TMP__`/`__BASE__`）本就跨平台 |
| `tests/gate-cases.json` | 假路徑字面 `/Users/user/...` → `/home/user/...` | 僅字面一致性；判定邏輯不依賴路徑前綴（homedir 豁免走 `__BASE__`） |
| `tests/run-e2e.sh` | 假 repo 路徑同上翻譯 | 同上（測試內 `HOME` 被覆寫成暫存目錄） |
| `SKILL.md` | 標題與「平台備註」段 | Homebrew 文案 → npm global / 可攜式 node 注意事項；標明 GNU coreutils 假設 |
| `references/orchestration.md` | 標題；註冊 snippet 的 hook 指令與說明 | 家目錄佔位符 `/home/user/`；補「node 不在 PATH 要用絕對路徑」警告（見 §3） |
| `settings.snippet.json` | hook 指令路徑與 `_comment` | 同上 |
| 平台紀錄 | 本文件（`docs/linux-platform-notes.md`，取代 macOS 版全文） | macOS 版是移植過程紀錄（現在在 `docs/history/`），對 Linux 使用者只需差異與驗證。**三平台的這類文件一律不放進 skill payload** |
| `../CLAUDE-global-rule.md` | marker 標記 `(macos)` → `(linux)` | 「Codex 討論夥伴」snippet；內容與 macOS 版相同（Bash + `.sh -n`），2026-07-05 merge 同步時補 |

## 2. 不變量對照（沿用 macOS 版 I1–I9）

- **I1–I7**：憑證／旗標語意不變 → 沿用，由 **120 案**回歸測試臺背書（見 §4）。⚠️ 原文寫「hook 逐位元組相同」，**2026-07-26 起不成立**（見 §1 表格；差異是刻意的平台語義，不是漂移）。
- **I8**（UTF-8 不亂碼）：Linux 預設 UTF-8 locale，天然成立；驗收同 macOS——部署後實跑一輪中文簡報 consult/exec。
- **I9**（`*.sh` 不得被 scratchpad／`~/.claude` 豁免）：與 macOS 同義成立，測試案例背書。

## 3. Linux 專屬注意事項（部署前必讀）

1. **GNU coreutils 假設**：腳本用 `stat -c %Y`。Alpine/BusyBox 或其他非 GNU stat 環境需自行確認；BSD userland 請改用 `macos/`。
2. **node 不一定在 PATH**：不少 Linux 機器的 Node 是可攜式安裝（如 `~/.local/node/bin`）、不在系統 PATH。hook 由 Claude Code 直接以 `command` 啟動，**PATH 找不到 node 時 hook 會靜默不跑、gate 形同虛設**。settings 註冊時一律建議寫 node 絕對路徑。部署後用一次故意違規的 Write 驗證 gate 真的會 deny。
3. **codex 位置**：npm global 安裝常落在 `~/.local/bin/codex` 或 npm prefix 的 `bin/`；只要在 PATH 上即可，腳本不寫死路徑。
4. 其餘部署步驟與 macOS 版相同：hook 複製到 `~/.claude/hooks/`（skill 目錄內不留副本——I3 的唯一保護目錄）、skill 目錄放 `~/.claude/skills/超級模式/`、snippet 合併進 `settings.local.json`。

## 4. 驗證紀錄

### 4.0（2026-07-27）Linux 原生 —— context-engineering 整理後複驗

環境：WSL2 / ext4 / glibc / Node v22.23.1。**從 `git clone` 的 checkout 跑，不是從 Windows 工作目錄複製**
（後者因 `core.autocrlf=true` 會拿到 CRLF 的 `.sh`，`set -euo pipefail` 會炸成
`pipefail: invalid option name` —— 這是假陽性，不是程式壞掉，見 [`backlog.md`](backlog.md)）。

| 項目 | 結果 |
|---|---|
| `node --check` hook | ✅ |
| `bash -n`（scripts ×4 + tests ×3） | ✅ |
| `node tests/run-gate-tests.js` | ✅ **121/121**（新增 1 案：deny 訊息須含子代理分支） |
| `node tests/matcher-contract.test.js` | ✅ |
| `bash tests/run-e2e.sh` | ✅ 11/11 |
| `bash tests/consult-schema.tests.sh` | ✅ **4/4**（新增 2 案：`-p`/`-f` 互斥 fail-fast） |

GitHub CI 於本批推上遠端後才會跑，綠燈與否以 CI 狀態為準。

### 4.1（2026-07-26）Linux 原生 —— 兩個獨立環境 + 持續性 CI

> ⚠️ 以下數字屬 **2026-07-26 那個 revision**，不代表目前 tip（案例數已增加，見 §4.0）。

| 環境 | 內容 |
|---|---|
| WSL2 | ext4 / glibc / Node **v22.23.1**（官方 tarball，SHA256 核對） |
| GitHub Actions | `ubuntu-latest`（Ubuntu 24.04）/ Node **v22.23.1** |

兩者跑**同一份 bytes**（`run-e2e.sh` 印出的 `GATE_BLOB` 相同）。結果：

| 項目 | 結果 |
|---|---|
| `node --check` hook | ✅ |
| `bash -n`（scripts ×4 + tests ×3） | ✅ |
| `node tests/run-gate-tests.js` | ✅ **120/120** |
| `node tests/matcher-contract.test.js` | ✅ |
| `bash tests/run-e2e.sh` | ✅ 11/11，`GATE_UNDER_TEST` 指向 repo 內 hook |
| `bash tests/codex-check.tests.sh` | ✅ TOTAL 41 FAIL 0 |
| `bash tests/consult-schema.tests.sh` | ✅ 2/2 |

**變異測試（非空驗證，重要）**：把 `isRunnerTouchingSensitive()` 換成 macOS 的 `toLowerCase()` 後，
真 Linux 上 gate-cases 變 **118/120**，且失敗的**只有**那兩筆專為此設計的 `/TMP` 案例。
**同一個誤植在 Windows 主機上跑，卻會被另外 3 個案例擋下**——但那 3 案的區辨性來自 Windows 的
`os.tmpdir()` 含大寫（`C:\Users\...\Temp`）；真 Linux 的 `tmpdir` 是全小寫 `/tmp`，那 3 案會**假綠**。
**結論：跨宿主跑 `run-gate-tests.js` 不能取代 Linux 原生驗證。** 該變異測試已寫進 CI
（[`.github/workflows/linux.yml`](../.github/workflows/linux.yml)），防止這層守護日後被悄悄拆掉。

**仍未涵蓋**：以上皆為直接呼叫 `decide()`，不證明 Claude Code runtime 真的載入 settings 並叫起 hook；
端到端只能在新 session 實際觸發一次。

### 4.2（2026-07-03，歷史）Linux x86_64 / GNU coreutils / Node v22.14.0 / codex-cli 0.142.5

| 項目 | 指令 | 結果 |
|---|---|---|
| hook 語法 | `node --check hooks/super-mode-consult-gate.js` | ✅ |
| 回歸測試臺 | `node tests/run-gate-tests.js`（34 案例，Linux 實機） | ✅ 34/34 |
| e2e stdin 水管 | `bash tests/run-e2e.sh`（11 案例，Linux 實機） | ✅ 11/11 |
| 腳本語法 | `bash -n` scripts ×4 + run-e2e.sh | ✅ |
| live 端到端（I8 實跑） | macOS 移植紀錄 Phase 5 劇本 | 🔴 **未跑**——本移植機上尚未跑過真實 codex 一輪（不燒額度前提下無法驗）。部署者請照 [`history/FIX-PLAN-macos-2026-07-03.md`](history/FIX-PLAN-macos-2026-07-03.md) Phase 5 步驟 1–9 走一遍再視為完成 |

> 測試臺與 e2e 對「已部署到 `~/.claude/hooks/` 的 hook」實跑（與 repo 內副本 sha256 相同：`b316dc5d…`）。gate-cases.json 的 `/home/user` 路徑翻譯不影響判定，34/34 背書。
