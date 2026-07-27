# Backlog — 已知未完成項

> 建立於 2026-07-27。三份 FIX-PLAN 移出 skill payload 時，未完成的項目不能只留在史料裡，
> 所以彙整到這裡。**這份只列「還沒做」的事**；已完成的過程紀錄在 [`history/`](history/)，
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
| **repo 缺 `.gitattributes`** | `core.autocrlf=true` 且無 `.gitattributes` → Windows 工作目錄的 `.sh` 是 CRLF（committed blob 仍是 LF，所以 clone 出來正常）。但**直接從 Windows 工作目錄複製** `.sh` 到 Unix 機器會拿到 CRLF，`set -euo pipefail` 會炸成 `pipefail: invalid option name`。本次驗證就踩過一次。加 `*.sh text eol=lf` 可以根治，但屬本次 scope 外，待拍板 |
| **mac／Windows 沒有 CI** | 只有 Linux 有（`.github/workflows/linux.yml`）。Windows 與 macOS 的原生回歸仍靠人工，每次 promote 都得手動跑 |
