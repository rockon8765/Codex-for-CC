# settings target 批次的後續工作（2026-08-08 盤點）

> **取代** `docs/remediation-plan-2026-07-28.md`（v4）。原文封存在 annotated tag
> `archive/remediation-plan-2026-07-28`（＝分支 `fix/post-merge-review-2026-07-28` 的尖端 `19fb2e8`）。
>
> **為什麼取代而不是繼續勾 v4 的驗收表**：v4 的**事實**大致仍成立，但作為**執行合約**已失效——
> §7 流程圖把封存排在 merge 之後、同一行括號卻要求 merge 之前；§9 仍把 `main` `0b12c6d`
> 已完成的 M2／M3 自我檢查列為未完成；§9 寫 `--settings`、§1 正文寫 `--settings` ＋ `--hook`；
> §8 的 `tests/ai-install` 基準 66／64 已變 69／68；而 §1 的 A1 呼叫點表**有實質錯誤**（見 §1.1）。
>
> **本檔刻意保持 compact。** 完整的原始分析在上面那個 tag，不要複製回來。

## 0. 基準

| 項目 | 值 |
|---|---|
| 基準 | `origin/main` ＝ `1aeb010`（動工前仍應 `git fetch` 復驗）|
| 工作分支 | `fix/settings-target-successor-2026-08-08` |
| gate 基準 | Windows **109**／macOS **117**／Linux **121**（點 `gate-cases.json` 實測，與 v4 相同）|
| ai-install 測試臺基準 | Windows **69**／POSIX **68**（v4 寫的 66／64 已過時）|

---

## 1. 2026-08-08 盤點

### 1.1 `matcher-contract` 呼叫點（v4 的 A1 表有實質錯誤）

**需要標旗標的「指令型」呼叫點共 15 處**（v4 表只列 8 列）：

| 形態 | 位置 |
|---|---|
| repo 佈局 | `.github/workflows/linux.yml:81`（CI，無旗標）、`docs/AI-INSTALL.md:28`、`:33`（步驟 1a，repo 相對）|
| live 絕對路徑 | `docs/AI-INSTALL.md:309`、`:316`（步驟 3）、`README.md:189`、`:205`、`:216`、`docs/MIGRATION-hook-settings-target.md:150`（§3.1）、`macos/…/orchestration.md:115`、`linux/…/orchestration.md:117` |
| **相對路徑（實測會 module-not-found）** | `macos/…/orchestration.md:102`、`linux/…/orchestration.md:104`（皆為 ECC 段的「重跑」指示）、`macos/settings.snippet.json:2`、`linux/settings.snippet.json:2`（`_comment`）|

**另有 22 處是「非指令」，不可照 v4 修改**：`README.md:139`／`:148`／`:157`（目錄樹列檔名，3）、
`orchestration.md:85`／`:87`（三平台散文敘述，3）、`docs/verify-settings-scope.md:50`／`:70`／`:164`（分析，3）、
`docs/opus5-alignment-plan-2026-07.md`（規劃書，6）、`linux`／`macos` 的
`hooks/super-mode-consult-gate.js:49`（註解，2）、三平台 `matcher-contract.test.js:13`（自身，3）、
`docs/linux-platform-notes.md:59`／`:81`（驗證紀錄，2）。

> 排除 `docs/history/` 與 `HANDOFF-*` 後，全 repo 共 **37 處**命中 `matcher-contract.test.js`＝15 指令型 ＋ 22 非指令。
> （含 history／handoff 則為 19 檔 49 處。）**動工前請自行復跑這個盤點**，不要沿用本表的數字——
> v4 就是敗在數字被當成長期真值。

**v4 的兩個具體錯誤**：

1. **`docs/linux-platform-notes.md` 被標成要加 `--live`**，但該檔的兩處
   （`:59`、`:81`）是**驗證紀錄表格**（`| node tests/matcher-contract.test.js | ✅ |`），
   是「當時跑過什麼」的史實。照 v4 修改**等於竄改歷史紀錄**。
   （該檔真正相關的是 `:44` 的**註冊指示**，屬 A2 不屬 A1——v4 的 A2 收了它，A1 表卻又列一次。）
2. **「兩份 POSIX orchestration ＝ 相對路徑」把三種不同形態混成一列**：
   每份 orchestration 有 3 處，只有 ECC 段那處是相對路徑，
   該檔的**正式測試指令**（`:115`／`:117`）早就是 live 絕對路徑，不需要改。

### 1.2 `matcher-contract` 的功能缺口（v4 沒點破）

現行三平台的 `matcher-contract.test.js` 用 `__dirname` 解出 repo snippet 路徑，
且採「repo 佈局**排他**」：只要 `settings.snippet.json` 存在就一定驗它。
**因此從 checkout 執行時無法指向 live** —— 而 `MIGRATION §3.1` 正是要「驗 live」。
換言之 §3.1 在現行程式碼下**做不到它宣稱的事**。
這讓 A1 的 `--live` 從「衛生」升級為**功能缺口**。

### 1.3 註冊入口（共 10 處）

`docs/AI-INSTALL.md`（步驟 2，canonical）、`README.md` 三平台手動安裝各一、
`docs/linux-platform-notes.md`、三份 `settings.snippet.json` 的 `_comment`、
`macos`／`linux` 的 `orchestration.md`。

> ⚠️ 先前把 `docs/MIGRATION-hook-settings-target.md` 也算成註冊入口（記為 11 處）是**錯的**——
> 那個 `合併進` 命中的是 §3.1 的**標題**（「matcher 是否真的合併進去了」），不是註冊指示。
> Windows 的 snippet 也在名單內：它從沒受 `settings.local.json` 那個 bug 影響，
> 但**重複註冊的問題三平台都有**。

它們目前**都只說「合併」**，沒有任何一處說明「已經有一筆時該怎麼辦」——
標準重跑安裝本身就可能 append 第二筆。
（v4 的 A2 盤點是對的，只是把 README 算成 1 處，實際是 3 處。）

### 1.4 遞迴刪除路徑（只有 2 處）

`docs/AI-INSTALL.md:400`（POSIX 回滾 `rm -rf`）與 `:464`（Windows 回滾 `Remove-Item -Recurse`）。
其餘 4 處命中（`:66`／`:67`／`:110`／`:458`）都是**警語與註解**，不是刪除動作。
→ **B1 的程式碼面只有 2 個地點**，比 v4 描述的範圍小得多。

### 1.5 `~/.claude/settings.json` 的寫入者（威脅模型已變更）

當初逼出「改用 `settings.local.json`」那個錯誤決定的理由是「ECC 會覆寫 `settings.json`」。
**ECC 已於 2026-08-04 從維護者機器卸載**（`~/.claude/scripts` 現為空、`~/.claude/ecc-mirror` 不存在），
所以 v4 §4 那段「本機觀察」（記載 7 支 `ecc-*.ps1` 與 mirror plugin 版本）**已無法復現**。

**但威脅模型並未消失，只是換人**：實測 `~/.claude/settings.json` 的 top-level key 為
`permissions`／`hooks`／**`enabledPlugins`**／`autoUpdatesChannel`／`skipWorkflowUsageWarning`／`theme`。
**Claude 的 plugin manager 是同一個檔的寫入者。**
→ C 的正確修法不是「移除警告」，而是**泛化成「任何會寫 `~/.claude/settings.json` 的工具」並具名 plugin manager**——
那比原本的 ECC 版本**證據更紮實**。

> ⚠️ 目前**沒有**證據顯示 plugin manager 會動 `hooks`；只證明它寫同一個檔。不要把 ECC 的舊斷言換成對 plugin manager 的新斷言。

---

## 2. v4 驗收表的逐列去處

| v4 §9 列 | 判定 | 去處 |
|---|---|---|
| A1 加 `--repo`／`--live`／`--settings` | **仍開放**，且因 §1.2 升級為功能缺口 | A1 |
| A1 全部呼叫點標旗標 | **部分過時**，依 §1.1 重新盤點（15 指令型／22 非指令）| A1 |
| A1 舊 installed verifier fixture | **不做**——census 兩台取樣皆無此狀態（§4.4）| 已結案 |
| A1 doc-contract 測試 | **改設計**：改為「非 canonical 文件連向唯一指引」，取代掃遍所有 Markdown | A1 |
| A2 D6 conflict 規則＋後置條件 | **仍開放**（檔頭警告已先行 containment）| A2 |
| A2 註冊入口全數納入 | **仍開放**，盤點更新為 10 處（§1.3）| A2 |
| B1 rollback 掃 `$sbak` 與 live 樹 | **仍開放**，範圍收斂為 2 個程式碼地點（§1.4）| B1 |
| B1 五類測試 ＋ M2／M3 自我檢查 | M2／M3 **已完成**（`main` `0b12c6d`）；五類測試仍開放 | B1 |
| B1 反向驗證（基準 `67a7ae6`） | **仍開放**，基準需改（main 已前進到 `1aeb010`）| B1 |
| C 七檔 11 處降級 | **改寫**：證據基礎消失但威脅模型換人（§1.5）| C |
| C-opt 上游 ECC 事實 | **刪除**（ECC 已卸載，核實上游無剩餘價值）| — |
| C 規劃書自我收斂 | **作廢**（隨 v4 封存）| — |
| D README 驗證區塊 ＋ legacy notice | 驗證區塊**仍開放**（新增：浮動 `67a7ae6..HEAD` 也要釘死）；legacy notice **延後**至 MIGRATION 修好 | D |
| D backlog L28／L32／L34 | L32 **已完成**（`main` `2290ebe`）；L28、7→8 仍開放；新增「可 promote」已過時 | D |
| D 舊 Mac handoff 標 archived | **仍開放**（檔首仍指向已刪除的分支）| D |
| scoped 回歸矩陣＋數字回填 | **基準過時**（見 §0）| 併入各項 |
| checkpoint → Mac handoff → waiver | **改設計**：單一 successor 分支多 commit，對最終 SHA 一次 Mac 驗證 | 流程 |
| Codex 合併前審查／fetch 復驗／併入 main | **保留**（全域規則）| 流程 |
| 封存 handoff 與規劃書 | **進行中**（tag 已建，待推遠端）| 進行中 |

---

## 3. 工作項

| # | 項目 | 狀態 |
|---|---|---|
| 0 | MIGRATION 檔頭 containment 警告 ＋ backlog 追蹤列 | ✅ `b7b34c4` |
| 1 | 三台唯讀 installed census | ✅ **Windows ＋ macOS 已取樣**（§4.4 對照表）；Linux 未取樣。結論：A1 的舊 verifier fixture **不做**（無證據支持），並發現第三種狀態「skill 已裝但沒有 verifier 檔」|
| 2 | B1：兩處回滾加子樹掃描（`$sbak` **僅在選中時**掃；live 不存在＝**無子樹可掃**，不得當掃描失敗）＋ 針對性測試 | ✅ **三平台完成**（macOS 原生見 §4.4）|
| 3 | A2：probe 逐層驗形狀並 fail-closed；第 2 節改 handler 粒度＋補「main 已有一筆」分支；10 處註冊入口改冪等／衝突停手 | ✅ **三平台完成**（macOS 原生見 §4.4）|
| 4 | A1：`--repo`／`--live` 顯式模式、印出實際受驗路徑、修 §1.1 的 4 處相對路徑 | ✅ **三平台完成**（macOS 原生見 §4.4）|
| 5 | C：泛化為「任何 `settings.json` 寫入者」並具名 plugin manager | ✅ |
| 6 | D：README 驗證區塊（寫「**後於 07-31 完成複驗**」，不要竄改當時的誠實記錄）、README 浮動 `..HEAD` 釘死、backlog L28／7→8／「可 promote」、舊 Mac handoff 標 archived | ✅ |
| 7 | README legacy notice（排在 #3 之後）| ✅ |
| 8 | 把 legacy backup **子樹**掃描補進 `installer-rewrite-spec.md` 的 legacy 回滾節與驗收表 | ✅ |
| 9 | 刪除舊分支（**最後一步**：successor 進 main ＋ 遠端 tag 可取回之後）| ☐ |
| 10 | macOS 原生驗證 ＋ census —— 交接文件＝[`HANDOFF-macos-2026-08-08.md`](HANDOFF-macos-2026-08-08.md)（釘 `224ad8e`）| ✅ **2026-08-08 回報，八項全數符合預期**（§4.4）|

## 4. 已拍板的決策

- **B1＝硬化現行回滾**（2026-08-08 定案，維護者拍板）。
  理由：`tools/` 目前不存在、`installer-rewrite-spec.md` 的 12 項驗收全空，
  且該 spec 自己規定「三平台原生綠之前舊 markdown 繼續服役」——
  所以 rewrite **不是**現行 B1 的 mitigation，讓一條真實資料損失路徑無限期等下去不划算。

## 4.1 B1 的驗證紀錄（2026-08-08）

新增 `[M11]`（回滾期內嵌 link，備份子樹／live 子樹兩個變體）與
`[M12]`（live 不存在時回滾仍須成功——防 fail-closed 寫過頭）。

| 執行 | 結果 |
|---|---|
| Windows pwsh 7 | **86/86** exit 0（基準 69）|
| Windows：測試臺跑 pwsh、**受測區塊跑 PS 5.1** | **86/86** exit 0 |
| Linux WSL2／ext4 | **85/85** exit 0（基準 68）|
| 反向驗證（兩平台各自對 `1aeb010` 的 `AI-INSTALL.md`）| 各 **4 FAIL**，且完全是 M11 的四條斷言；M12 在修正前也 PASS（它是守護不是修復）|
| macOS | ✅ **85/85** exit 0（26.6.1 arm64／bash 3.2.57 原生，見 §4.4）|

## 4.2 A2 的驗證紀錄（2026-08-08）

probe 改寫成逐層驗形狀、異形一律 `exit 1`；第 2 節拆成 **A（還沒有）**／**B（已經有／重複）**
兩支且粒度改為 handler；判定表把 `≥1` 拆成 `1` 與 `≥2`；10 處註冊入口全部加上
「不是冪等、先數再動手」與後置條件。

probe 以假 `HOME` 餵 **9 種**輸入實測（Node v24.16.0），**9/9 符合預期**：

| 輸入 | 期望 | 結果 |
|---|---|---|
| 頂層 `null`／`PreToolUse` 物件／`PreToolUse` **字串**／entry 非物件／`command` 非字串 | exit **1** | 皆 exit 1，並印出具體是哪一層不合 |
| 正常 1 筆（**對照組**） | exit 0「正常」 | ✅ |
| `main` 2 筆 | exit 0「已經重複註冊」 | ✅ |
| `main` 1 ＋ `local` 1 | exit 0「只從 local 移除，不要搬」 | ✅ |
| `main` 0 ＋ `local` 1 | exit 0「受影響」 | ✅ |

**修正前的行為**：`PreToolUse` 是字串時 **exit 0** 且判定成「兩邊都沒有 gate……重做安裝」。

回歸：`tests/ai-install` Windows **86/86**、Linux **85/85**；gate **109／117／121**；
三平台 `matcher-contract` 皆 exit 0（snippet 的 `_comment` 有改動，這支會讀）。

> ⚠️ **v4 §8 的 PS 5.1 指令是錯的。** 它寫 `powershell -File .\tests\ai-install\run-windows.ps1 -Shell powershell`，
> 但 `-Shell` 選的是「執行**被抽出的區塊**」用哪個 shell，測試臺本身必須跑在 pwsh 下。
> 把測試臺本身跑在 5.1，`Invoke-Block` 的 `& $exe … 2>&1` 會在 `$ErrorActionPreference='Stop'`
> 之下把子程序的 stderr 變成終止性 `NativeCommandError`，在 `[M1]` 就中斷。
> 實測 `1aeb010` 的乾淨 worktree 同樣如此，**與本批改動無關**。正確寫法：
> `pwsh -File .\tests\ai-install\run-windows.ps1 -Shell powershell`。

## 4.3 A1 的驗證紀錄（2026-08-08）

`matcher-contract.test.js`（三平台同一 blob）加上 `--repo`／`--live`／`--settings <p> --hook <p>`
三種明確模式，一律印出實際受驗的兩條路徑；不給旗標＝**兩階段淘汰的第一階段**
（印 deprecation 到 stderr、行為與退出碼完全不變）。15 個指令型呼叫點全部標上旗標。

**`--live` 為什麼是功能缺口而非潔癖**：舊版用 `__dirname` 解 repo snippet 且「repo 佈局排他」，
所以**從 checkout 執行永遠只驗 repo snippet**。`--live` 現在明確驗
`~/.claude/settings.json` ＋ `~/.claude/hooks/super-mode-consult-gate.js` 這一對
（hook 也要跟著換，否則會拿 checkout 的 hook 去對 live 的 settings）。

**反向驗證（對 `1aeb010` 實跑）**：

| 舊版行為 | 實測結果 |
|---|---|
| 從 checkout 無旗標 | PASS —— 驗的是 repo snippet，但輸出不說是哪一份 |
| 從 checkout 加 `--live` | **旗標被靜默忽略，照樣 PASS** |

第二列是本項最重要的發現：**舊的 installed verifier 收到 `--live` 會假綠**。
所以 `MIGRATION §3.1` 改成「用 checkout 的 verifier」是必要條件，不是建議，
且該節已寫明這個實測。

| 參數驗證 | 退出碼 |
|---|---|
| `--settings` 缺 `--hook`（或反之）／`--repo --live` 併用／`--settings` 與 `--repo` 併用／未知旗標／`--settings` 後缺值 | 全部 **2** |

回歸：三平台 `--repo` exit 0、gate **109／117／121**、三份 snippet JSON 可解析、
`tests/ai-install` Windows **86/86**。

## 4.4 macOS 原生驗證與 census 結果（2026-08-08 回報）

**環境**：macOS 26.6.1（25G76）arm64、內建 `bash 3.2.57(1)-release`
（`which -a bash` 只有 `/bin/bash`，確認非 Homebrew 5.x）、Node v26.4.0、Claude Code 2.1.220。
受驗 SHA `224ad8e`，**7 筆 blob 全符**。

| 項目 | 結果 |
|---|---|
| A-1 `run-posix.sh` | **85/85** exit 0。`[M11]`（備份子樹／live 子樹兩變體）與 `[M12]` 全綠——BSD 的 `ln -s`／`find -type l`／`cp -R` 無 GNU 專屬語義漏網 |
| A-2 gate ＋ `matcher-contract --repo` | **117/117**；`--repo` exit 0 |
| A-3 參數契約 | 三個 `exit 2`、deprecated 落 stderr、無旗標 `exit 0`，全符 |
| A-4 反向驗證 | **PASS=81 FAIL=4**，且**恰為** M11 那四條。還原後 `git status --porcelain` 空、blob 回到 `d0781cbd4b48` |
| A-5 probe 四輸入 | 三個 `exit 1` ＋ 對照組 `exit 0`，全符 |

### ⚠️ 一處平台差異（非缺陷，但會咬未來的自動化）

`matcher-contract` 在 macOS 印出的是 `/private/tmp/cfc-0808/…` 而非 handoff 寫的 `/tmp/…`——
macOS 的 `/tmp` 是指向 `private/tmp` 的 symlink，realpath 解析後即為 `/private/tmp`，同一位置。

> **教訓**：日後若要對「受驗 settings／受驗 hook」那兩行加**自動斷言**，
> 字串比對 `/tmp/...` 在 macOS 會誤判，必須比 realpath。

### census（三台的具名樣本，**不外推**）

| 欄位 | Windows | macOS |
|---|---|---|
| OS | Windows 11 10.0.26200.0 | macOS 26.6.1 (25G76) arm64 |
| Claude Code | 2.1.220 | 2.1.220 |
| installed `matcher-contract` blob | `5edaa7efe4fd…` | **不存在**（`find ~/.claude -name 'matcher-contract*'` 零命中）|
| 是否為含 `settings.local` 候選的舊版 | 否 | **N/A**——沒有已安裝的 verifier |
| `settings.json` gate handler | 1 | 1 |
| `settings.local.json` | 不存在 | **存在**（1497 B）但**無 `hooks` 段**，gate 0 |
| probe 判定／exit | 「正常，不用修。」／0 | 同 |

**WSL2 不是 census 對象**：實查該環境沒有 `~/.claude`，是純驗證環境。
Linux（協作者機器）仍未取樣。

### census 帶來的三個結論

1. **A1 的「舊 installed verifier fixture」不做**（原列為「延後，取決於 census」）。
   兩台取樣中**沒有任何一台**存在「含 `settings.local` 候選的舊版 verifier」——
   Windows 是新版、macOS 根本沒裝過那個檔。為一個沒有任何證據支持的狀態寫 fixture
   不划算；防護面已由 README legacy notice ＋ `MIGRATION §3.1`「用 checkout 的 verifier」覆蓋，
   兩者都不依賴這個 fixture。
   ⚠️ **兩個樣本不等於沒有這種機器**，只是我們沒有證據。日後若 Linux 取樣命中，重開此題。
2. **出現我沒預期的第三種狀態：skill 已安裝、但 `tests/` 裡沒有 `matcher-contract.test.js`。**
   那台 Mac 的 `~/.claude/skills/超級模式/tests/` 有 `run-gate-tests.js`／`run-e2e.sh`／
   `consult-schema.tests.sh`／`codex-check.tests.sh`／`gate-cases.json`，**就是沒有 verifier**。
   代表 README／`AI-INSTALL` 步驟 3 那條「★ 必跑」的指令在該機器上**從未被跑過**
   （會直接 module-not-found）——與 `settings.local.json` 長期失效的歷史一致。
   `MIGRATION §3.1` 改成「用 checkout 的那份」剛好也涵蓋這個狀態。
3. **`settings.local.json` 存在但無 `hooks` 段**是現成的真實樣本，probe 對它輸出
   「沒有 hooks 段 —— gate 條目：0 個」並判定正常。這條路徑先前只有合成測試，
   現在有真機證據。

## 5. 沿用 v4 的紀律（這幾條仍然有效）

1. **反向驗證**：新回歸案必須對**修正前**版本 FAIL，否則只是裝飾
2. **變異注入**：錯誤分支不注入走不到；注入點要有「注入是否成功」的自我檢查（rc ＋型別雙驗）
3. **不放未經驗證的程式碼進 canonical 安裝指引**
4. 本機驗不了：NTFS symlink（無管理員權限，junction 可代理測 reparse）、bind mount 端到端（無免密碼 sudo）、macOS（走 handoff）
5. 量測退出碼**不要**接 `Select-Object -First N`——會提前終止上游管線讓 `$LASTEXITCODE` 失真
6. 判斷「相對 main 改了什麼」用**兩個點**，不要用 `main...HEAD`
