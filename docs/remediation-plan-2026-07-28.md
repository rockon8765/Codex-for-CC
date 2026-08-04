# 修復規劃書 — settings target 批次的**後續**缺陷（2026-07-28）

> **本批唯一的執行載體。** 進度回寫 **§9 驗收表**。換 session 接手請從本檔開始，
> 另讀 [`backlog.md`](backlog.md)。完成後標為封存（比照
> [`HANDOFF-opus5-builtin-gate-macos.md`](HANDOFF-opus5-builtin-gate-macos.md)）。
>
> ⚠️ **執行者限制**：本檔 §11 的 `codex-consult` 指令會讀寫 `~/.claude`，
> 依 [`AGENTS.md`](../AGENTS.md) 的 worker guard，**只能由主 session 或使用者本人執行**；
> 被派工的一般 coding worker **不得**執行該節，也不得讀寫使用者的 `~/.claude`。

## 版本說明

- **v1／v2 的前提已作廢**：它們假設「這批還在驗證分支上、要清阻擋項才能進 main」。
  實際上整批**已經合併進 main**（`origin/main` = `67a7ae6`）。
- **v3 → v4**：修掉第二輪審查指出的 8 項——A1 規劃內部不一致、D 組漏掉公開文件、
  handoff／commit 順序無可執行分支、A2 盤點漏一處、B1「唯一」為錯誤陳述且缺一個 guard、
  C 的標注標準規劃書自己不符、Mac 全綠的證據強度寫過頭、兩處帳面算術錯誤。

## 0. 現況

| 項目 | 值 |
|---|---|
| 基準 | `origin/main` = **`67a7ae6`**（撰寫時；動工前仍應 `git fetch` 復驗）|
| 工作分支 | `fix/post-merge-review-2026-07-28`（自 `67a7ae6` 開出）|
| 本機基準實測 | gate **109／117／121**、Windows 測試臺 **66/66**、POSIX 測試臺 **64/64** |

**已復驗的 git 事實**：`67a7ae6` 是雙親 merge（`b05cf60` + `18e1f75`）；
`53cbc5f`、`06adac5` 皆可解析且是 main ancestor（**合併用 merge 非 rebase，原 SHA 保留**）；
`18e1f75..6f7839b` = 23 commits、`18e1f75..origin/main` = 25；`6f7839b...origin/main` = `0 4`
（原尖端零領先）。原驗證分支已依使用者指示刪除（**依撰寫當時的 `ls-remote` 查證**）。

> ⚠️ **不要用 `git diff main...HEAD`（三個點）判斷「相對 main 改了什麼」**——三點是
> 「共同祖先到 HEAD」，會忽略 main 那一側。本批就因此誤報過。
> 用兩個點，或 `git merge-base --is-ancestor origin/main HEAD`。

**本批範圍**：合併前審查提出 9 條 finding，**6 條已修並隨批進 main**（#2／#3／#5／#6／#7／#8）。
**剩 3 條原 finding 未修**（原 #1 rebase 已因 merge 完成而消失、原 #4／#9 仍在），
加上後續兩輪審查新增的項目，**拆成 4 個 workstream：A1、A2、B1、C**。

---

## 1. A1 — 舊安裝者跑 matcher-contract 仍會假綠

**最反直覺的一條。** 真正受影響的人是在 `9293636`（首次移除 `settings.local.json` 候選與
fallback）**之前**安裝的，他們**已安裝的** `matcher-contract.test.js` 就是舊版，
候選清單裡還有 `settings.local.json`。

**失敗鏈**：`settings.json` 沒 gate、`settings.local.json` 有 gate → 舊的 installed matcher
挑到 local → **PASS** → 若 deny probe 又剛好從家目錄啟動，local 會被當專案設定載入而 deny
→ 使用者判定修復完成，但從一般專案啟動仍**完全沒有 gate**。

**呼叫點的真實分佈**（v3 寫「AI-INSTALL 本來就指向 live」**不精確**）：

| 呼叫點 | 目前 | 應標 |
|---|---|---|
| `.github/workflows/linux.yml`（CI） | 無旗標 | `--repo` |
| `AI-INSTALL` **步驟 1a** | repo 相對路徑 | `--repo` |
| `AI-INSTALL` **步驟 3** | live 絕對路徑 | `--live` |
| `README` | — | `--live` |
| `MIGRATION` §3.1 | live 絕對路徑 | `--live`，且改用**當前 checkout** 的版本 |
| 兩份 snippet 的 `_comment` | **相對路徑** | `--live` |
| 兩份 POSIX `orchestration.md` | **相對路徑** | `--live` |
| `docs/linux-platform-notes.md` | 見 A2 | `--live` |

**修法**：

- `matcher-contract.test.js` 加明確模式：`--repo` / `--live`，或
  `--settings <path> --hook <path>`
- **auto（無旗標）只作舊呼叫端的相容 fallback**，並在輸出中標明「auto 模式」
- **所有現役呼叫點都顯式標旗標**（上表）——只改 MIGRATION 是不夠的，
  否則 canonical 路徑仍依賴 auto，而 auto 在 repo 目錄下會驗 repo snippet 而 PASS
- 三平台同步（三份檔目前 byte 相同，改完復驗仍相同）

**驗證**：

- 反向測試加**舊 installed verifier fixture**（`9922220` 那份），檢查**特定錯誤訊息**；
  `module not found` 之類**不得**算成預期的 FAIL
- **doc-contract 測試**：掃**全部非歷史呼叫點**，從實際文件抽出指令，
  **遇到無旗標即 FAIL**——否則只證明程式行為、沒證明文件指示被改對

---

## 2. A2 — 修復文件會製造重複註冊，且「語義等價」不可操作

**問題**：[`MIGRATION`](MIGRATION-hook-settings-target.md) §1.1 判定「兩邊都有 → 移除 local」，
但 §2.2 無條件要求搬「整個 outer entry」。

**失敗情境**：

- main 是舊 matcher、local 是新 matcher → 追加會重複，只刪 local 又留下壞 entry
- outer entry 同時含 gate 與其他 handler → 搬整筆會把不相關 hook 升到 user scope；
  刪整筆會移除不相關 hook
- main 已有兩筆、其中一筆正確 → 存在式判斷成立，結果仍是兩筆
- 現行 matcher 的 `.some()`／`.find()` **只驗第一筆**，兩筆或同 entry 兩個 gate handler
  **仍會 PASS**

**`node …gate.js` 與「絕對 Node 路徑 …gate.js」不是語義等價**——PATH、Node 版本、
執行環境都不同。**視為 conflict，不得自動選。**

**修法**：沿用 [installer 規格 D6 conflict 規則](installer-rewrite-spec.md)——嚴格 JSON parse；
gate handler **恰一筆**且不得與其他 handler 共用 matcher group；matcher 不得有空項或重複項、
集合須等於 canonical；重複／共享 entry／路徑或欄位不同 → **一律停手**。

> ⚠️ **「完全一致」比較的對象是「彼此競爭的 handlers」**（例如 main 的一筆 vs local 的一筆），
> **不是**拿使用者的真實絕對路徑去比對 snippet 裡的 placeholder——後者必然不同，
> 會讓每個人都撞 conflict。

**明確後置條件**：

```
~/.claude/settings.json        gate handler = 1
~/.claude/settings.local.json  gate handler = 0
```

**註冊入口盤點**（**v3 漏了最後一項**）：`AI-INSTALL` 步驟 2、`README` 快速安裝、
三份 snippet、兩份 POSIX orchestration、**`docs/linux-platform-notes.md:44`**
（同樣指示把 snippet「合併進」settings，且屬現行參考而非史料）。
它們目前都只說「合併」，**標準重跑安裝本身就可能 append 第二筆**。
doc-contract 應驗證**所有現役註冊入口**。

---

## 3. B1 — rollback 沒有掃描備份樹內嵌的 link

> **不是「唯一的資料損失路徑」**（v3 的說法與 [`backlog.md`](backlog.md) 記載的
> mount 損失路徑矛盾）。正確說法：**本批四個 workstream 中唯一新增的「穩定樹」
> 資料損失 finding**。

**與 1b 不重複**（審查方試過用 1b 取代 B1，反論失敗）：1b 驗「**建立備份當下**的 live」，
B1 驗「**真正使用時**可能已漂移的 backup」。兩步之間沒有持久 manifest 或完整性證明。

**失敗情境**：1b 之後備份內的 `references/shared` 被換成 symlink／junction，頂層仍是普通目錄
→ 預檢通過 → **live 被刪** → 從錯誤圖形還原。Windows 的 `Copy-Item -Recurse`
還會把 junction 目標實體化。

**位置**：[`AI-INSTALL.md`](AI-INSTALL.md) 的 POSIX `precheck()` 與 Windows `Test-Exactly1`。

**修法**（rollback code block 內用**同一個 helper** 掃兩棵樹，都必須在任何 mutation 前完成）：

| 掃描對象 | 前置條件（**兩個都不可省**） |
|---|---|
| `$sbak` 子樹 | **只有在 precheck 已確認選中 skill backup 時才掃**——全新安裝只有 `.absent`、沒有 `$sbak`，無條件掃會讓**合法 rollback 永遠失敗** |
| 目前 live skill 子樹 | **live skill 不存在時視為「沒有子樹可掃」**，不得把 `find` 的非零退出當成「掃描失敗 fail-closed」——否則合法的還原（live 已被手動移除）會被永久擋住。這與上一列是**同一形狀的 bug**，一起犯一起修 |

- POSIX：有 symlink 或**真正的掃描失敗**一律中止（fail-closed，偵測退出碼、不吞 stderr，
  不用 GNU 專屬的 `-print -quit`）
- Windows：任何 `ReparsePoint` 一律中止；`Remove-Item -Recurse` 之前尤其必要

**測試至少涵蓋**：backup 內嵌 link／live 內嵌 junction／`.absent` 正常 rollback／
**live 不存在時的正常 rollback**／真正的掃描錯誤 fail-closed。

**⚠️ 既有測試臺的缺陷一併修**：現有 POSIX M2 與 Windows M3 建 link 後**沒有自我檢查**。
若 `ln`／`mklink` 失敗，rollback 會因「備份不存在」而失敗，**測試照樣假綠**。
要先斷言 `-L`／`ReparsePoint` 與 native exit code。

**宣稱界線**：B1 只能宣稱修掉「**穩定樹中的** symlink/reparse」缺口。POSIX mount 與
scan-copy 的 TOCTOU 留 installer rewrite backlog，**不得宣稱資料損失類全部結案**。

---

## 4. C — ECC 措辭超出可證範圍

### 本機觀察（**依 C 自己訂的標注標準完整標注**）

- **日期**：2026-07-28
- **範圍**：`~/.claude/scripts\*.ps1` 全目錄共 **7 支**（全部是 `ecc-*`，無其他 `.ps1`）——
  `ecc-daily-update`／`ecc-drift-check`／`ecc-exec-diff`／`ecc-freeze-review`／
  `ecc-mirror-build`／`ecc-promote`／`ecc-rules-sync`。
  ⚠️ v3 寫「5 支」是**錯的**（`drift-check` 與 `freeze-review` 是後來加的）；
  掃描本身用萬用字元涵蓋全目錄，但描述說少了
- **版本**：ECC mirror plugin `2.20260726.2053`（`~/.claude/ecc-mirror/.claude-plugin/plugin.json`）
- **觀察**：`ecc-promote.ps1` 的 `$Settings` 只出現兩次——L50 賦值、
  L132 當 `Copy-Item` **來源**複製到備份目錄。**未見寫入路徑。**
- **未窮舉**：未追 dot-source 函式、外部 CLI、ECC plugin cache 內的 installer、
  上游官方 installer。**這是「未發現寫入路徑」，不是「不會覆寫」。**

### 修法

- **移除**把 ECC 指名為現行必然威脅的斷言（兩處「這是真實的衝突」）
- **不要**換成另一個沒證據的說法（例如「舊 installer 已確認會覆寫」）
- payload／snippet 保持短而可行動，泛化成「任何安裝器、同步或 promote 工具」
- **公開文件標注標準**：`backlog.md` 與 `verify-settings-scope.md` **都是公開文件**，
  不因名稱叫 backlog／verify 就變私有。可寫本機局部觀察，
  但**必須標日期、版本、範圍與未窮舉性**，不得升格成產品結論。
  **本規劃書自己也受此約束**（見上一段，已補齊）

**為什麼不保留「可能過時但無害」的警告**：審查方實際嘗試替它辯護並失敗——
把 ECC 說成現行覆寫者，可能促使使用者再次避開正確的 user-scope 檔、
自製另一個不受載入的替代設定，**重建出與本次 bug 相同的失效架構**。

### 檔案盤點（`git grep` 實測：7 檔 11 處）

| 檔案 | 處數 |
|---|---|
| `macos/skills/超級模式/references/orchestration.md` | 2 |
| `linux/skills/超級模式/references/orchestration.md` | 2 |
| `docs/verify-settings-scope.md` | 3 |
| `docs/AI-INSTALL.md` | 1 |
| `docs/MIGRATION-hook-settings-target.md` | 1 |
| `macos/settings.snippet.json` | 1 |
| `linux/settings.snippet.json` | 1 |

另：[`installer-rewrite-spec.md`](installer-rewrite-spec.md) 把 ECC 列為具名例子 → 泛化；
[`history/FIX-PLAN-macos-2026-07-03.md`](history/FIX-PLAN-macos-2026-07-03.md)
是**歷史文件不改寫**，**檔首**加醒目 banner。
README 與 backlog 經確認**沒有**該宣稱。

### C-opt 上游 ECC 事實（**不得阻塞 C**）

審查方提供但**尚未經本端核對**的證據（前例：它曾給過錯誤的 checkout SHA）。
**做法**：用 `gh api` 解析 **repo identity、tag／commit SHA 與 blob**，不只讀 main branch。
驗收判準是「**已核實並寫入，或明確省略**」。

---

## 5. D — 公開狀態一致性（**v3 嚴重低估，不只兩項**）

`b05cf60` 已處理：backlog 的 macOS 驗證兩列、`tests/ai-install/README.md` 的「macOS 未跑過」。

**仍要做的**：

| 位置 | 現況 | 處置 |
|---|---|---|
| [`README.md`](../README.md) 驗證區塊 | 仍公開宣稱本批 macOS **「未原生驗證」**，與 `b05cf60` 直接衝突 | 更新（**最嚴重**：使用者會照它重開已完成的 Mac 驗證）|
| `backlog.md` L28 | 仍說「promote 後即可刪驗證分支」 | 分支已刪，改寫 |
| `backlog.md` L34 | 寫 `53cbc5f..6f7839b` 有 **7** commits | **實測是 8**；改成 8，或精確寫成 `9922220..6f7839b` 的 7 |
| `backlog.md` L32 | 仍說測試臺「只在驗證分支上」 | 已 committed 進 main，改成「已 committed、尚未接 CI」|
| `HANDOFF-macos-2026-07-28.md` | 未標狀態 | 標 completed／archived |
| **README 安裝段** | 無 legacy notice | **新增醒目提示**：2026-07-28 前安裝者可能受影響，連到 [`MIGRATION`](MIGRATION-hook-settings-target.md)，並明寫**舊的 installed matcher 不可作為驗收依據**（缺陷已在 main，無法由 git 判斷是否已有外部使用者受影響）|

---

## 6. macOS 驗證的證據強度（**用詞已修正**）

**可宣稱的**：**據 `b05cf60` 回寫**，Mac 端於 2026-07-31 對尖端 `6f7839b` 重驗全綠
（gate 117/117、`matcher-contract` exit 0、`consult-schema` 4/4、`run-e2e` 11/11、
`run-posix.sh` 64/64）。

**不可宣稱**：本端已自行複驗 Mac 執行環境與 exit code。`b05cf60` 只改了 backlog 與
測試 README，**repo 內沒有保存原始終端輸出、git note 或 CI artifact**。

**本端能獨立復驗的**：7 筆核對 blob 確有 6 筆變動、未變的是 `gate-cases.json`、
`GATE_BLOB` 相符、且 `6f7839b..67a7ae6` 沒再改動受測 bytes。

**B1／A1／A2 會再動 POSIX 程式碼與 `matcher-contract`**，那會讓 07-31 的結論對這些部分失效。
處置見 §7 的分支決策。

> **不得把「臨時改寫驗證政策」當成與真機重驗等價的逃生門。**

---

## 7. 順序（**v3 的順序無可執行分支，已重寫**）

```
[ A1+A2 可執行契約 + fixtures ‖ B1 程式碼 + 針對性測試 ‖ C-opt 查證 ]
→ A1+A2+C+D 一次文件收斂
→ scoped 回歸矩陣（含 PS 5.1）+ 針對性反向驗證
→ ★ checkpoint commit（不是 final）
→ 問使用者：是否再發 Mac handoff
   ├─ 要 → 發新 handoff（釘 checkpoint SHA／blob／新 PASS 數）→ 等 Mac 回報
   │        → 回寫結果 → 重跑受影響測試 → **final commit**
   └─ 不要 → 在 README／backlog **明文記錄「本批新 delta 未經 macOS 驗證」的 waiver**
            （provisional 狀態，不得留白）→ **final commit**
→ Codex 合併前審查
→ git fetch
   ├─ origin/main 未前進 → 取得使用者同意 → 併入 main
   └─ origin/main 已前進 → 同步 → **重跑受影響測試 → 重新審查** → 再回到上一步
→ checkout 離開 main
→ 封存 handoff 與本規劃書（**在 merge 之前完成，避免 merge 後產生新的未提交修改**）
```

**為什麼這樣排**：A1／A2／C 都會改**同一批** snippet、orchestration、`AI-INSTALL`、
`MIGRATION`、`linux-platform-notes`，必須合成一次文件 delta；B1 改程式碼，
可平行但要先於文件定稿。

---

## 8. 驗證

### 紀律（不打折）

1. **反向驗證**：新回歸案必須對**修正前**版本 FAIL，否則只是裝飾。
   定義見 [`../tests/ai-install/README.md`](../tests/ai-install/README.md)
2. **變異注入**：錯誤分支不注入走不到；注入點要有「注入是否成功」的自我檢查
3. **不放未經驗證的程式碼進 canonical 安裝指引**

### 維護者本機驗不了的三件事

| 項目 | 原因 | 變通 |
|---|---|---|
| NTFS symlink | 無管理員權限、開發者模式未開 | junction（`mklink /J`）可代理測 reparse 路徑 |
| bind mount 端到端 | WSL2 無免密碼 sudo | 只能驗 parser，**parser 正確 ≠ 防護已驗證** |
| macOS 全部 | 沒有 Mac | 走 `HANDOFF-macos-*.md` 交接 |

### scoped 回歸矩陣

> 刻意**不叫「全部測試」**——本批不跑 `codex-check`、`consult-schema`、`run-e2e`
> （那些屬 Mac handoff 的 Task B）。

```powershell
node "<平台>\skills\超級模式\tests\run-gate-tests.js"                   # 基準 109 / 117 / 121
node "<平台>\skills\超級模式\tests\matcher-contract.test.js" --repo     # exit 0
pwsh       -File .\tests\ai-install\run-windows.ps1                     # 基準 66
powershell -File .\tests\ai-install\run-windows.ps1 -Shell powershell   # ★ 5.1，B1 改的是 PowerShell 回滾
```

```bash
bash tests/ai-install/run-posix.sh                                      # 基準 64
```

**上面是 `67a7ae6` 的實測基準；A1／B1 新增案例後必然改變，最終數字實作完回填。**

**反向驗證基準**：

| 用途 | 基準 | 備註 |
|---|---|---|
| A1／B1 專屬 RED | **`67a7ae6`** | 驗**具名的新 case** 失敗 |
| 廣義歷史 baseline | `06adac5` | **據 `b05cf60` 回寫**，Mac 端 07-31 實測 12 FAIL（5 + 7）；本端須自行重新量測 |

> ⚠️ **量測退出碼不要接 `Select-Object -First N`**——會提前終止上游管線讓
> `$LASTEXITCODE` 失真。把輸出導向檔案再讀。
>
> ℹ️ WSL2 的 `node` 在 `~/.local/node/bin`，不在非登入 shell 的預設 PATH。

---

## 9. 驗收表

| 項目 | 狀態 |
|---|---|
| A1 matcher-contract 加 `--repo`／`--live`／`--settings`（三平台，auto 僅相容 fallback 並標明） | ☐ |
| A1 **全部現役呼叫點**標旗標（CI／1a=`--repo`；步驟 3／README／MIGRATION／snippet×2／orchestration×2／linux-notes=`--live`） | ☐ |
| A1 反向測試含**舊 installed verifier fixture** + 特定錯誤訊息 | ☐ |
| A1 doc-contract 測試（掃全部非歷史呼叫點，無旗標即 FAIL） | ☐ |
| A2 採 D6 conflict 規則 + 後置條件 main=1／local=0 + 比較對象限定為競爭 handlers | ☐ |
| A2 註冊入口全數納入（**含 `linux-platform-notes.md:44`**） | ☐ |
| B1 rollback 掃 `$sbak`（僅選中時）與 live 樹（**live 不存在＝無子樹可掃**） | ☐ |
| B1 五類測試 + 既有 M2／M3 補建 link 的自我檢查 | ☐ |
| B1 反向驗證（基準 `67a7ae6`） | ☐ |
| C 七檔 11 處降級 + installer-spec 泛化 + history 檔首 banner | ☐ |
| C-opt 上游事實已核實並寫入，**或明確省略** | ☐ |
| **C 本規劃書自我收斂**（本機觀察已標日期／版本／範圍／未窮舉） | ☑ 已於 §4 補齊 |
| D README 驗證區塊（macOS 已驗）+ **安裝段 legacy notice** | ☐ |
| D backlog L28／L32／L34（含 7→8 或改用 `9922220..`） | ☐ |
| D 舊 Mac handoff 標 completed／archived | ☐ |
| scoped 回歸矩陣（含 PS 5.1）+ 數字回填 | ☐ |
| checkpoint commit → 問使用者 Mac handoff → 依分支走完（含 waiver 記錄） | ☐ |
| Codex 合併前審查 | ☐ |
| fetch 復驗（前進則同步＋重跑＋重審）→ 使用者同意 → 併入 main → checkout 離開 | ☐ |
| 封存 handoff 與本規劃書（**merge 前完成**） | ☐ |

---

## 10. 不要跟這批混在一起

[`installer-rewrite-spec.md`](installer-rewrite-spec.md) 是已定案但**尚未開工**的規格
（把安裝流程改寫成 `tools/install.js`，經兩輪對抗設計審查）。那是這批結束後的**下一階段**。

## 11. 進 main 的規矩（**限主 session／使用者執行**）

> ⚠️ 本節指令會讀寫 `~/.claude`。依 [`AGENTS.md`](../AGENTS.md) 的 worker guard，
> **被派工的一般 coding worker 不得執行本節**。

- **推 main 前一律先諮詢 Codex，無例外**（純文件也不放寬）：
  `~/.claude/skills/超級模式/scripts/codex-consult.ps1 -Dir <repo> -NoCredential -PromptFile <brief>`
- 簡報要**逼 Codex 當反方**，首行必須是 `ALLOW: <理由>` 或 `BLOCK: <理由>`
- **推驗證分支不用問**；**推 main、force push、刪遠端分支要先問使用者**
- 合併後 checkout 離開 main
