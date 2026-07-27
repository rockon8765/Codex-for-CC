# Backlog — 已知未完成項

> 建立於 2026-07-27。三份 FIX-PLAN 移出 skill payload 時，未完成的項目不能只留在史料裡，
> 所以彙整到這裡。**主體是「還沒做」的事**；末尾另有一張「已完成」小表，只放**曾經列在本檔
> 又被做掉**的項目，用途是防止同一題被重複開啟——完整的過程紀錄仍在 [`history/`](history/)。
> 各平台目前有哪些功能以 [README「功能差距」段](../README.md) 為準。

## 平台功能落差

| 項目 | 狀態 | 來源 |
|---|---|---|
| `codex-check.sh` 的能力面盤點與 baseline diff **尚未移植到 Linux**（macOS 549 行 vs Linux 123 行；`capability`/`baseline` 關鍵字 macOS 25/58 處、Linux 0/0） | 進行中 | [`linux-platform-notes.md`](linux-platform-notes.md) §1 |
| Linux 版 live 端到端（I8 中文簡報實跑一輪真 codex） | 未跑 | [`linux-platform-notes.md`](linux-platform-notes.md) §4.2 |
| `--disable remote_plugin` 三平台不一致（macOS 有，Windows/Linux 沒有）。這不是 Linux 落後，是 Mac 端單方面硬化（`8bbd43f`），維護者已明確**暫緩**收緊 `--disable`。要改請三平台一起改 | 暫緩 | [`linux-platform-notes.md`](linux-platform-notes.md) §1 |

## 已評估後暫緩的項目

| 項目 | 結論 | 來源 |
|---|---|---|
| `codex exec resume` 續談 | 實測行不通：resume 不吃 `--sandbox`／`-C`，`--json` 會污染 pipe。重開前必須先過 per-resume sandbox override 的 GATE | [`history/FIX-PLAN-windows-2026-07-02.md`](history/FIX-PLAN-windows-2026-07-02.md) Phase 5.3 |
| 改用 MCP／SDK 取代 `.ps1`／`.sh` 包裝 | 切換工作量高、現行腳本可運作 | [`history/FIX-PLAN-windows-2026-07-02.md`](history/FIX-PLAN-windows-2026-07-02.md) Phase 5.4 |

## 本次（2026-07-27 context-engineering 整理）產生的待辦

| 項目 | 說明 |
|---|---|
| **`-Prompt`／`-p` inline 淘汰 stage 2** | 目前是 stage 1：同時給 `-Prompt` 與 `-PromptFile` 直接報錯、單獨用 inline 出 deprecation 警告。改成硬錯誤要等一個 release window，並先確認沒有外部呼叫端還在用 |
| **mac／Windows 沒有 CI** | 只有 Linux 有（`.github/workflows/linux.yml`）。Windows 與 macOS 的原生回歸仍靠人工，每次 promote 都得手動跑 |
| **`AI-INSTALL.md` 備份步驟會製造重複 skill** | 步驟 1b 把備份放在 `~/.claude/skills/` 底下（`超級模式.bak-<ts>`），會被 Claude Code 的 skill loader 註冊成**第二個 skill**——名稱與 description 幾乎相同，干擾 skill 選擇。修法（備份改放 `~/.claude/skills-backup/`、回滾一併更新）已完成並附測試臺，但**留在驗證分支** `refactor/context-engineering-2026-07-27-pending-native-macos`：該分支的對抗審查在同一份文件的刪除／回滾狀態機裡連續找到多項缺陷，尚未收斂到可進 main。詳見該分支的 `docs/backlog.md` 與 `tests/ai-install/` |

## 已完成（留紀錄，避免重複開題）

| 項目 | 處置 |
|---|---|
| ~~repo 缺 `.gitattributes`~~ | **2026-07-27 已加**。`* text=auto` 打底；`*.sh` 一律 `eol=lf`，另**逐檔明列** `codex-check-stubs/codex` 與 `codex-check-stubs/npm`（三平台各 2 個無副檔名的 `#!/bin/bash` 腳本，`*.sh` 抓不到；刻意不用萬用字元，否則日後放進該目錄的 binary fixture 會被強制當文字正規化）；`*.js`／`*.json`／`*.yml`／`*.md` 也是 `eol=lf`；`*.ps1` 為 `eol=crlf`（Windows 原生執行，另有 UTF-8 BOM 需求——BOM 與行尾是兩回事）。加入後 `git status` 無偽差異，`git ls-files --eol` 確認 index 全部 `i/lf`。⚠️ **只保證新的 checkout**：既有 clone 的工作目錄不會因為加了本檔就自動重寫（詳見檔頭註解）|
