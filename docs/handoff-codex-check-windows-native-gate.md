# Handoff：codex-check Windows 原生驗收（promote gate）— 2026-07-13

> **給 Windows 執行 session（agentic worker）**：本文件是唯一驗收依據。逐項執行、如實記錄輸出；**全綠且徵得使用者同意後**才可把本分支併入 main。任何一項紅 → 在本分支上修（TDD：先讓失敗可重現、再修、再全跑），修完重跑全部驗收項，不可只重跑該項。

## 背景

- 分支：`fix/codex-check-hardening-windows-pending-native`（fork 自 5fd2465）。HEAD 應為 `0ac2a80`＋本 handoff commit。
- 內容：codex-check.ps1 的 H1–H5 強化（與 main 上 macOS/Linux 版同語義）＋ 27 案合成測試臺。commit 序：`54e5be7` seam → `3e16111` 測試臺 → `8f4f40b` H1–H5 → `8f7b7fe` 語法修 → `42905bd` InvariantCulture 時間戳 → `ad49bd6` H4 全欄位 regex＋鏡像測試 → `00ea972` H3 捕捉 npm 原生 exit code → `0ac2a80` H1 補 D5 fallback。
- POSIX 版（語義基準）已在 main（`bfdbba8`）：mac 41/41、Debian 41/41、真 codex `-f` 綠。設計決策見 `docs/codex-check-hardening-plan-2026-07.md` D1–D5（讀 main 版含執行紀錄）。
- 全部 ps1 變更**只經手動追蹤、從未在 Windows 執行過**——這就是本 gate 存在的原因。

## 環境前提

- Windows 10/11＋**Windows PowerShell 5.1**（`powershell.exe`，不是 pwsh；pwsh 可另跑但不算數）。
- 真 codex CLI 已裝（預設 `C:\npm\codex.cmd`；不同路徑用 `$env:CODEX_CHECK_CODEX_CMD` 指向，npm 同理 `$env:CODEX_CHECK_NPM_CMD`）。
- repo clone＋`git checkout fix/codex-check-hardening-windows-pending-native`。

## 驗收清單（逐項打勾＋留存輸出）

- [ ] **1. PS 5.1 parse**：兩檔（`scripts/codex-check.ps1`、`tests/codex-check.tests.ps1`）過 `[System.Management.Automation.Language.Parser]::ParseFile`，0 error。
- [ ] **2. BOM**：兩檔開頭 `EF BB BF`（runner 內建斷言會再驗一次）。
- [ ] **3. 合成測試臺全綠**：`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\codex-check.tests.ps1`——以 runner 自報 TOTAL/FAIL 為準（$allTests 27 案），FAIL 必須 0。**已知高風險項**（紅了照修，勿繞過）：
  - `t_h1_huge_banner_no_crash`：30000 字元 prefix 經 cmd stub `echo %VAR%` 展開，可能踩 cmd.exe ~8191 字元行處理限制 → 若因此紅，把測試 prefix 縮到 ~7900 或改 stub 輸出方式（保持「短首行＋巨量後續」攻擊形狀），並在報告註明。
  - `t_h3_*`：`Start-Job`/`$using:` 的 env 繼承、`$LASTEXITCODE` 捕捉（print-then-fail 必須 UNKNOWN）——全部第一次真跑。
  - anti-live 斷言：每案 trace 不得出現 `C:\npm`（防打到真 codex）。
- [ ] **4. Stop-Job 清理**：跑完 t_h3 系列後 `Get-Job` 無殘留 job、`tasklist` 無孤兒 node/ping 行程（計畫明載的真機驗證項）。
- [ ] **5. 真 codex `-Force`**：`powershell.exe -NoProfile -File scripts\codex-check.ps1 -Force` → exit 0、精確 sentinel（transcript 有噪音也要正確判 OK）、快取行 `format=2 installed=… latest=… verdict=… smoke=OK at …`（InvariantCulture 時間戳）。
- [ ] **6. cache hit**：立即無參數重跑 → 「跳過」訊息＋exit 0。
- [ ] **7. 語義對照抽查**：H1–H5 verdict/訊息字串與 main 版 bash（`macos/skills/超級模式/scripts/codex-check.sh`）逐字相同（機制翻譯除外）。

## 全綠之後（promote 協定）

1. 徵使用者同意。
2. `git checkout main && git pull && git merge fix/codex-check-hardening-windows-pending-native`——分支只動 `windows/` 檔與本 handoff，main 自 fork 後只動 macos//linux//docs，預期無衝突；有衝突即停下回報。
3. push main；`git ls-remote` 核對；刪遠端分支。
4. 更新 `docs/codex-check-hardening-plan-2026-07.md`：勾銷「Windows 原生 promote gate」checkbox＋執行紀錄補一行（含本機驗收輸出摘要）。
5. main 自此可宣稱「H1–H5 三平台語義等價」（linux 能力面盤點段仍缺，屬另一 handoff，勿混入）。

## 明確排除（勿順手做）

- linux 能力面盤點段移植、runner setup fail-fast、capability probe deadline——各自獨立 handoff。
- `codex-exec.ps1` 補 `--disable remote_plugin`＋memories 隔離（三平台等價債 C′）——**不在本 gate**，另案處理。
- 盤點段語義統一（mac 8-feature 白名單 vs windows 07-10 全量語義）——promote 本分支不需要動它。

## 紀律

- commit 格式 `fix(超級模式): ...`／`test(超級模式): ...`，無 attribution trailer；回滾只用 `git revert`；禁 force push。
- 修測試臺可改測試；修 SUT 語義必須維持與 bash 版逐字同義——拿不準就先問使用者，不要單方面改語義。
