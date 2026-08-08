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
| ~~**macOS 原生驗證（2026-07-27 批次）**~~ **已完成（2026-07-31）** | 該批已在 Mac 真機驗完，且涵蓋分支尖端 `6f7839b`——詳見下方「2026-07-27 批次的 macOS 原生驗證」列。**已 promote 進 main，驗證分支 `refactor/context-engineering-2026-07-27-pending-native-macos` 也已刪除**（本列原寫「promote 後即可刪」，那是待辦語氣，已不成立）|
| **mac／Windows 沒有 CI** | 只有 Linux 有（`.github/workflows/linux.yml`）。Windows 與 macOS 的原生回歸仍靠人工，每次 promote 都得手動跑 |
| **Windows 斷掉的 symlink：殘留不確定（守衛已加，但該分支無法實測）** | `AI-INSTALL` 1b／回滾段現在會用 `Get-Item -LiteralPath -Force` 取 directory entry 並檢查 `ReparsePoint` 屬性，**任何 link 一律中止**。已實測涵蓋：有效 junction、**斷掉的 junction**（`Get-Item -Force` 回非 null、`Attributes` 含 `ReparsePoint` → 中止）。**未涵蓋**：指向不存在目標的 **symlink**——若 `Get-Item -Force` 對它回 null，仍會落入「不存在」分支建立 `.absent`，回滾時該位置被當成全新安裝刪除。**本機無管理員權限、開發者模式亦未開啟，無法建立 NTFS symlink 實測該分支**（WSL2 的 symlink 是 Linux 語義，不能代替）。有管理員權限或開啟開發者模式的環境請補測 dangling file-link／directory-link 兩案，並據實回寫本列。注意：影響**不是零**——若斷鏈的目標日後被還原（同步軟體等），刪掉鏈等於毀掉一個會恢復的連結拓撲 |
| **macOS／Linux 偵測不到掛載點，且回滾的 `rm -rf` 會刪掉掛載內的真實資料（嚴重）** | 1b 的 link 守衛用 `find -type l`，**掛載點是目錄不是 symlink，抓不到**。完整失敗鏈：skill 樹底下有 bind mount → 1b 照常 `cp -R`（把掛載內容實體化）→ `diff -r` 仍相等 → 印出 `ts` → 之後回滾執行 `rm -rf ~/.claude/skills/超級模式` → **跨進掛載樹刪除裡面的資料**。⚠️ **這條路徑早於 link 守衛就存在**（回滾一向用 `rm -rf`，main 目前的版本也是），守衛沒有縮小它、也沒有擴大它。`find -xdev`／`rm --one-file-system` 都不夠（同檔案系統的 bind mount 仍會漏），且後者是 GNU 專屬、會弄壞共用同一段 bash 的 macOS。可靠做法是讀平台 mount table（Linux `/proc/self/mountinfo`、macOS `mount`），**寫法平台不同且本機無 root 無法建立掛載點實測**，因此未實作。已在 AI-INSTALL 用表格明確標示各平台攔得到什麼，並要求有掛載點的使用者先卸載或改用手動安裝 |
| **安裝流程的測試臺尚未接上 CI** | 2026-07-27 為驗證 1b／1c／回滾寫了測試臺（抽出文件 code block → 假 HOME 執行 → 檢查檔案系統，含變異注入），並以「對修正前版本必須 FAIL」做反向驗證。⚠️ **本列原記載「只在驗證分支上、Windows 61 案／POSIX 58 案」已不成立**——測試臺早在 [`cb6b9f7`](https://github.com/rockon8765/Codex-for-CC/commit/cb6b9f7) 就進了 repo（「依 Codex 第九輪 BLOCK」那批），2026-08-04 起為 **Windows 69 案／POSIX 68 案**。**真正還沒做的是接上 CI**：[`linux.yml`](../.github/workflows/linux.yml) 只跑 `linux/` 內的測試，**不含頂層 `tests/ai-install/`**，所以日後有人改動守衛或指紋格式，遠端不會有任何 gate 攔下——目前仍靠人工在三台機器上跑。要嘛把它接進 CI，要嘛依下一列把整個流程改寫成腳本 |
| ~~未定案：`~/.claude/settings.local.json` 會不會被載入~~ **已結案並修正（2026-07-28）** | macOS 真機實測確認它**不是** user scope 的 hook 來源，只有從家目錄啟動時才生效（那時它剛好就是專案層的 `.claude/settings.local.json`）。四組對照實測，加上該機器 143 個 session／11 個啟動目錄／14,477 次 hook 叫用中 gate **0 次**被叫用。已據此修正：兩個 POSIX snippet 的 `_comment`、`AI-INSTALL` 步驟 2 與 1b／回滾的 `setf`、三平台 `matcher-contract`（移除 local 候選**並**移除 `\|\| candidates[0]` fallback）、`run-posix.sh` 的 seed。完整結論與證據見 [`verify-settings-scope.md`](verify-settings-scope.md)；**既有使用者的診斷與修復步驟**見 [`MIGRATION-hook-settings-target.md`](MIGRATION-hook-settings-target.md)。⚠️ 原記載的「執行檔字串矛盾」是**版本方向搞反**——`legacy settings.local.json` 在 2.1.148 命中 0 次、2.1.220 命中 14 次，是**後來才加**的權限遷移碼，與 hook 來源無關；hook 來源列舉字串兩版一字不差 |
| ~~2026-07-27 批次的 macOS 原生驗證~~ **已完成（2026-07-28；尖端 2026-07-31 複驗）** | SHA `53cbc5f` 於 macOS 26.5.2 arm64 / Claude Code 2.1.163 驗證：7 筆 blob 相符、`gate-cases` **117/117**、`matcher-contract` exit 0、`consult-schema` **4/4**、`run-e2e` **11/11**（`GATE_UNDER_TEST` 確認指向 worktree）。同批的 `tests/ai-install/run-posix.sh` 在 BSD userland（bash 3.2.57）**59/59**、反向驗證 7 FAIL 與 Linux 一致——確認 GNU→可攜移植與 symlink 守衛的 fail-open 修正在 macOS 成立。交接文件：[`HANDOFF-macos-2026-07-28.md`](HANDOFF-macos-2026-07-28.md)。**2026-07-31 補驗分支尖端 `6f7839b`**——`53cbc5f` 之後又有 **8** 個 commit（本列原寫 7，2026-08-08 以 `git rev-list --count 53cbc5f..6f7839b` 實測為 8；寫 7 的話對應的區間其實是 `9922220..6f7839b`），原本核對的 7 筆 blob **有 6 筆變動**（gate hook／snippet／SKILL／`matcher-contract`／`AI-INSTALL`／`run-posix.sh`），故整批重跑：`gate-cases` **117/117**、`matcher-contract`（新版排他驗證）exit 0、`consult-schema` **4/4**、`run-e2e` **11/11**（`GATE_BLOB=f1781d6e59a06c78d43ae074545f08ea5f0740d3`）、`run-posix.sh` **64/64**；反向驗證對 `53cbc5f` 的 `AI-INSTALL` **5 FAIL**（settings-target 新斷言）、對 `06adac5` **12 FAIL**（5 + 原本 7 個 symlink）。**分支尖端在 macOS 為綠**；當時的結論是「可 promote」，**該批已於 2026-08-04 前 promote 進 main、驗證分支已刪** |
| **A2 批次的已知殘留（2026-08-09 合併前審查第五輪，維護者裁示先併、這幾項另批處理）** | 三個 P1 已在併入前修掉（`process.exit()` 截斷 stdout → 改 `process.exitCode` 自然結束；README 三段與兩份 payload orchestration 不再自己複述合併步驟、改指向 `AI-INSTALL` 步驟 2，同時封住「handler 誤寫成 `type:"prompt"` → 安裝驗證全綠但 gate 不會被叫起」；`backup-settings` 拿掉守不住的 all-or-nothing 宣稱改成 best-effort 並如實描述）。**以下三項仍開放**：**(a)** `probe-gate-registration` 的範圍說明寫「唯二例外」，實際還有第三類——**非 gate 的 handler 不驗 `type`／`command` 必備性**（`{"type":7,"command":"node /other/hook.js"}` 與 `{"type":"command"}` 都會 exit 0）。要嘛補驗、要嘛把文案改成精確列出實際驗證的欄位。**(b)** `tests/backup-settings.test.js` 的 collision 案用「預建未來 5 秒的候選檔名」觸發撞名，**不是確定性**（排程延遲或時鐘跳動會落出視窗，而且工具若因回歸而忽略撞名 exit 0，目前同樣被歸為 SKIP 而非 FAIL）。建議改用 `node --require` preload 固定 child 的 `Date`，同一手法也能精準測 hash throw／partial destination／unlink failure。**(d)** `tests/backup-settings.test.js` 的 `FIXED_MS = Date.parse("2026-08-09T03:04:05")` **沒有時區**，依規格解析為**本地時間**。macOS 驗證者指出：若剛好在該秒執行，`r.out.includes(tsOf(FIXED_MS))` 這條「注入是否生效」的自我檢查會**貌似通過**（他們實際在該時刻前 177 秒執行，已用真實時鐘值 `030044`／`030107` ≠ 釘死值 `030405` 排除，並在真實時鐘超過釘死時刻後重跑仍 9/9）。**該秒已過去，現在無法再觸發**，但常數留著就是陷阱——修法是挑一個明顯的過去時刻（或加一條「`FIXED_MS` 距 now 至少數秒」的斷言）。**(e)** `HANDOFF-macos-a2-2026-08-08.md` §3 的 `awk` 原本用雙引號包程式（`$/` 在 bash 不是合法展開所以照跑）——**已於 2026-08-09 改成單引號並實測抽出內容逐位元組相同**，此項已結案，留紀錄。 **(c)** **結構性**：gate 辨識（「哪個 handler 是本 hook」）同時住在 `tools/probe-gate-registration.js` 與三份 `matcher-contract.test.js`，且兩邊規則不同（probe 驗 `type`、matcher 不驗；probe 對 exec form 停手、matcher 會判成沒註冊）。正解是抽成共用的 parser／verdict 模組讓兩邊共用——**但那會動到 `matcher-contract.test.js`，屬 A1 的範圍**，必須和 A1 一起做 |
| **安裝流程改寫成 repo 內的腳本（進行中）** | 2026-07-27 的第七～九輪對抗審查連續三輪在同一份 markdown 的刪除／回滾狀態機裡找到實質缺陷（萬用字元 `ts` 繞過預檢並還原錯誤版本、內嵌 link 被實體化、POSIX collision loop 漏斷鏈、掛載點偵測不到）。**2026-07-28 維護者拍板改寫**，經兩輪對抗設計審查定案。**執行載體＝[`installer-rewrite-spec.md`](installer-rewrite-spec.md)**（含設計決策、被實測推翻的 EXDEV 假設、測試分套、shipping gate、驗收表）。要點：單一 Node 核心 + 平台 adapter；永不刪除只搬隔離區；掛載偵測涵蓋祖先與受管子樹後代；雜湊比對為動作前提；settings 走 semantic patch。**分階段交付——三平台原生綠之前不切換 `AI-INSTALL.md`，舊流程維持可用** |
| **安裝流程的殘留檔清單要跟著維護** | 1c 用「複製（合併語意）＋ 逐一刪除已知移除路徑」處理殘留，目前清單只有 `FIX-PLAN.md` 一筆。**日後若再有檔案移出 skill payload，必須同步加進 1c 的清理行**，否則舊檔會留在使用者的 live。這是刻意選的取捨：換來「安裝流程從不整個刪除 live」這個性質 |
| **安裝流程若要自動化，需重新設計為交易式** | 現行 1b/1c 是給人／AI 手動逐段執行的，沒有交易語義與併發保護（兩個同時進行的安裝會互相覆蓋）。2026-07-27 曾嘗試改成 staging＋交易目錄模型，經三輪對抗審查暴露出「刪了卻換不上」「狀態 marker 不完整」「跨交易競爭同一 live」等問題後**整批回退**——結論是交易協定不該寫在複製貼上的 markdown 裡。若日後要做排程／自動安裝，應改寫成 repo 內有測試臺的腳本，而不是繼續加厚文件 |

## 已完成（留紀錄，避免重複開題）

| 項目 | 處置 |
|---|---|
| ~~repo 缺 `.gitattributes`~~ | **2026-07-27 已加**。`* text=auto` 打底；`*.sh` 一律 `eol=lf`，另**逐檔明列** `codex-check-stubs/codex` 與 `codex-check-stubs/npm`（`linux/` 與 `macos/` 各 2 個、共 4 個無副檔名的 `#!/bin/bash` 腳本，`windows/` 沒有該目錄；`*.sh` 抓不到它們。刻意不用萬用字元，否則日後放進該目錄的 binary fixture 會被強制當文字正規化）；`*.js`／`*.json`／`*.yml`／`*.md` 也是 `eol=lf`；`*.ps1` 為 `eol=crlf`（Windows 原生執行，另有 UTF-8 BOM 需求——BOM 與行尾是兩回事）。加入後 `git status` 無偽差異，`git ls-files --eol` 確認 index 全部 `i/lf`。⚠️ **只保證新的 checkout**：既有 clone 的工作目錄不會因為加了本檔就自動重寫（詳見檔頭註解）|
| ~~`AI-INSTALL.md` 備份步驟會製造重複 skill~~ | **2026-07-27 已修**。備份改放 `~/.claude/skills-backup/`——原本放在 `~/.claude/skills/` 底下會被 skill loader 註冊成第二個 skill（description 幾乎相同、干擾選擇）。rollback 路徑一併更新，且還原改用**複製**而非搬移，備份因此留在原地、回滾可重複執行。殘留檔（`FIX-PLAN.md`）改用 1c 的逐一刪除處理，**安裝流程維持「從不整個刪除 live」** |
