# 超級模式移植紀錄（FIX-PLAN · Linux 版）

> 版本：2026-07-03 v1.0 ｜ 依據：本 repo 的 macOS 版（`macos/`，其 FIX-PLAN 記錄了自 Windows 參考版移植 + Phase 1–5 全數完成的過程）
> 性質：**機械式移植**。macOS bash 版與 Linux 的差異只剩 BSD vs GNU userland 與文件內的平台文案；所有發現、不變量（I1–I9）、驗收條件全數沿用 macOS 版，本文件只記錄「哪裡不同、為什麼、怎麼驗」。
> 語言慣例：說明用繁體中文；程式碼／指令／檔名／旗標一律英文。

---

## 1. 與 macOS 版的逐檔差異

| 檔案 | 差異 | 原因 |
|---|---|---|
| `hooks/super-mode-consult-gate.js` | **逐位元組相同** | hook 是純 Node，無平台分支；I9 的 `.sh` basename 排除在 Linux 同義成立 |
| `scripts/codex-consult.sh` | **逐位元組相同** | 純 POSIX + codex CLI，無 BSD 依賴 |
| `scripts/codex-exec.sh` | **逐位元組相同** | 同上 |
| `scripts/codex-check.sh` | `stat -f %m` → `stat -c %Y` | BSD stat（macOS）→ GNU stat（Linux）；語意同為「檔案 mtime epoch 秒」 |
| `scripts/super-mode.sh` | `stat -f %m` → `stat -c %Y` | 同上 |
| `tests/run-gate-tests.js` | **逐位元組相同** | 佔位符機制（`__TMP__`/`__BASE__`）本就跨平台 |
| `tests/gate-cases.json` | 假路徑字面 `/Users/user/...` → `/home/user/...` | 僅字面一致性；判定邏輯不依賴路徑前綴（homedir 豁免走 `__BASE__`） |
| `tests/run-e2e.sh` | 假 repo 路徑同上翻譯 | 同上（測試內 `HOME` 被覆寫成暫存目錄） |
| `SKILL.md` | 標題與「平台備註」段 | Homebrew 文案 → npm global / 可攜式 node 注意事項；標明 GNU coreutils 假設 |
| `references/orchestration.md` | 標題；註冊 snippet 的 hook 指令與說明 | 家目錄佔位符 `/home/user/`；補「node 不在 PATH 要用絕對路徑」警告（見 §3） |
| `settings.snippet.json` | hook 指令路徑與 `_comment` | 同上 |
| `FIX-PLAN.md` | 本文件（取代 macOS 版全文） | macOS 版是移植過程紀錄，對 Linux 使用者只需差異與驗證 |
| `../CLAUDE-global-rule.md` | marker 標記 `(macos)` → `(linux)` | 「Codex 討論夥伴」snippet；內容與 macOS 版相同（Bash + `.sh -n`），2026-07-05 merge 同步時補 |

## 2. 不變量對照（沿用 macOS 版 I1–I9）

- **I1–I7**：hook 逐位元組相同、憑證／旗標語意不變 → 直接沿用，由 34 案例回歸測試臺背書（見 §4）。
- **I8**（UTF-8 不亂碼）：Linux 預設 UTF-8 locale，天然成立；驗收同 macOS——部署後實跑一輪中文簡報 consult/exec。
- **I9**（`*.sh` 不得被 scratchpad／`~/.claude` 豁免）：與 macOS 同義成立，測試案例背書。

## 3. Linux 專屬注意事項（部署前必讀）

1. **GNU coreutils 假設**：腳本用 `stat -c %Y`。Alpine/BusyBox 或其他非 GNU stat 環境需自行確認；BSD userland 請改用 `macos/`。
2. **node 不一定在 PATH**：不少 Linux 機器的 Node 是可攜式安裝（如 `~/.local/node/bin`）、不在系統 PATH。hook 由 Claude Code 直接以 `command` 啟動，**PATH 找不到 node 時 hook 會靜默不跑、gate 形同虛設**。settings 註冊時一律建議寫 node 絕對路徑。部署後用一次故意違規的 Write 驗證 gate 真的會 deny。
3. **codex 位置**：npm global 安裝常落在 `~/.local/bin/codex` 或 npm prefix 的 `bin/`；只要在 PATH 上即可，腳本不寫死路徑。
4. 其餘部署步驟與 macOS 版相同：hook 複製到 `~/.claude/hooks/`（skill 目錄內不留副本——I3 的唯一保護目錄）、skill 目錄放 `~/.claude/skills/超級模式/`、snippet 合併進 `settings.local.json`。

## 4. 驗證紀錄（2026-07-03，Linux x86_64 / GNU coreutils / Node v22.14.0 / codex-cli 0.142.5）

| 項目 | 指令 | 結果 |
|---|---|---|
| hook 語法 | `node --check hooks/super-mode-consult-gate.js` | ✅ |
| 回歸測試臺 | `node tests/run-gate-tests.js`（34 案例，Linux 實機） | ✅ 34/34 |
| e2e stdin 水管 | `bash tests/run-e2e.sh`（11 案例，Linux 實機） | ✅ 11/11 |
| 腳本語法 | `bash -n` scripts ×4 + run-e2e.sh | ✅ |
| live 端到端（I8 實跑） | macOS FIX-PLAN Phase 5 劇本 | 🔴 **未跑**——本移植機上尚未跑過真實 codex 一輪（不燒額度前提下無法驗）。部署者請照 macOS 版 FIX-PLAN Phase 5 步驟 1–9 走一遍再視為完成 |

> 測試臺與 e2e 對「已部署到 `~/.claude/hooks/` 的 hook」實跑（與 repo 內副本 sha256 相同：`b316dc5d…`）。gate-cases.json 的 `/home/user` 路徑翻譯不影響判定，34/34 背書。
