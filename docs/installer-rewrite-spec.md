# 安裝器改寫規格（執行載體）

> 建立於 2026-07-28。**這份是實作合約，不是提案。** 經兩輪對抗設計審查定案
> （第一輪 BLOCK 三個 CRITICAL、第二輪 BLOCK 但給出「最小可放行集合」）。
> 實作進度回寫本檔末尾的驗收表。

## 0. 為什麼要改寫

`docs/AI-INSTALL.md` 目前把「備份 → 安裝 → 驗證 → 回滾」這條**會刪檔**的狀態機
寫成複製貼上的程式碼區塊，而且是 PowerShell 與 bash 兩套平行翻譯。
2026-07-27 的第七～九輪對抗審查連續在裡面找到實質缺陷：

| 輪次 | 缺陷 | 根因 |
|---|---|---|
| 7 | 萬用字元 `ts` 繞過預檢，live 刪除後**還原成錯誤版本** | PowerShell `Test-Path` 展開 pattern，與 `-LiteralPath` 脫鉤 |
| 8 | 內嵌 junction 被 `Copy-Item -Recurse` **實體化**，只列檔案的指紋看不出來 | 兩套實作各自的 link 語義 |
| 8 | POSIX collision loop 漏斷鏈 symlink，`: >` 跟隨鏈把檔案建到備份區外 | `[ -e ]` 對斷鏈為 false |
| 9 | POSIX 掛載點偵測不到，回滾的遞迴刪除跨進掛載樹刪外部資料 | `find -type l` 抓不到掛載點 |

**共同根因**：同一個修法要翻譯成兩種語義，且刪除語義依賴 OS 工具的預設行為。

## 1. 設計決策（含被推翻的假設）

### D1 單一 Node 核心 + 少量平台 adapter

Node 已是**硬性前置**（hook 本體是 `.js`，安裝驗證步驟本來就跑 `node`），
所以用 Node 不新增依賴。

**實測支撐**（2026-07-28）：

| 判斷 | Windows 斷鏈 junction | Linux 斷鏈 symlink |
|---|---|---|
| `fs.lstatSync()` | 正常回傳，`isSymbolicLink()=true` | 正常回傳，`isSymbolicLink()=true` |
| `fs.existsSync()` | **false**（跟隨，瞎） | **false**（跟隨，瞎） |

`lstat` 一份程式碼就正確回答了 `Test-Path` 與 `[ -e ]` **各自答錯**的問題。

**但不要誇大**：Node 只統一了部分 link 語義。mount table、reparse point、
command quoting、原子替換仍需平台 adapter。這是「一份核心 + adapter」，
不是「只靠 `lstat` 就跨平台」。

- Node 下限 **≥ 22.3.0**（`fs.cpSync` 自該版脫離 experimental；Node 20 已 EOL）
- CI 需測 Node 22 與 24
- 安裝器位置：`tools/install.js`（repo 工具，不是三平台 payload）

### D2 掛載防護：祖先 **＋ 受管子樹的所有後代**

> ⚠️ **這裡有一個被實測推翻的假設，留著當紀錄。**
> 原設計主張「刪除一律改成 rename 到隔離區，跨掛載邊界會 EXDEV 失敗，等於 OS 幫我擋」。
> **實測（2026-07-28，Windows）**：把同 volume junction 內部的檔案 rename 到隔離區
> **成功**，外部資料被搬走；EXDEV 只在跨磁碟機時觸發。
> 審查方另補一刀：即使子節點是掛載點，**rename 的是父目錄**時 Linux 也會成功，
> 掛載拓撲整個被拖進隔離區。
> **結論：EXDEV 不是防護，主動偵測是必要的。**

規格：

- 任何寫入或搬移前，檢查**目標的所有祖先**，**以及受管 live 子樹的所有後代**
- Linux：解析 `/proc/self/mountinfo`，用 mount point 與 mount ID 判定，**不能只比 `st_dev`**
  （同檔案系統的 bind mount `st_dev` 相同）
- Windows：遞迴拒絕任何 reparse point（`Attributes & ReparsePoint`）
- macOS：解析 `mount` 輸出
- 隔離區與每個 rename 來源**必須同 mount/volume**；
  **EXDEV 後禁止 fallback 成 copy+delete**（那會把可逆操作變回破壞性操作）
- 偵測不到就中止，不得假定普通目錄安全

### D3 永不刪除，只搬到隔離區

安裝器**沒有任何 unlink/rmdir 的破壞性路徑**。所有「刪除」語義一律是
`rename(目標, ~/.claude/.super-mode-quarantine/<txid>/<相對路徑>)`。

保留的兩個真實性質（EXDEV 那條已撤回）：

1. **可逆**：任何錯誤搬移都還原得回來，crash 最壞後果是「東西在隔離區、live 缺一塊」
2. **原子**：rename 沒有半完成狀態

隔離區 v1 **永久保留**、不做時間式 GC。`--status` 顯示容量、年齡、哪些 transaction 仍依賴它。
日後若要清理，另開**明確破壞性**的 `--prune <txid>`，只處理已 `COMMITTED` 且不再需要復原的，
不得偷偷塞進安裝收尾。

### D4 日誌與復原（把六態機收斂成一個終端標記）

不做 `PREPARED → APPLYING → VERIFYING → COMMITTED` 全套狀態機，但**必須**有：

- **durable transaction header**：`{txid, command, intent, version}`（append + fsync）
- **每筆 operation**：`{path, beforeType, beforeHash|null, desiredHash, quarantinePath}`
  ——先 append + fsync，再實際修改
- **復原判斷同時看 `(live, quarantine)`**，不能只看 live：
  crash 在「舊的已搬進隔離區、新的尚未建立」時 live 是空的，只看 live 會誤判成 drift
- **`COMMITTED` 終端紀錄**：只有在 runtime 驗證通過後才 append + fsync
- **沒有 `COMMITTED` 的 transaction**，`--recover` 採**單一確定政策：一律恢復 pre-state**，
  不猜測是否要繼續安裝

**為什麼終端標記無法省略**：「所有 live 都等於 `desiredHash`」這個檔案狀態，
在「runtime 驗證尚未跑」與「runtime 驗證已通過」兩種情況下**完全相同**，
但安裝的承諾天差地別。這是唯一無法由內容推導的狀態。

### D5 動作前提：逐項雜湊比對

- `== desiredHash` → 這是我寫的，可以搬走／還原
- `== beforeHash` → 我沒寫成功（crash 在寫入前），略過
- 兩者皆非 → **drift，停手報 conflict，絕不動它**

### D6 settings 是獨立的 operation 型別

整檔雜湊與 semantic patch 互相衝突：使用者事後加一個無關的 permission，
整檔 hash 就同時不等於 `beforeHash` 與 `desiredHash`，解除安裝會永遠報 conflict。

規格：

- **provenance 單位是「我們自己的 PreToolUse handler entry」**，不是整份 JSON
- 無關欄位改變**可以接受**；只有自己的 entry 被改、重複、或變得無法唯一識別才 conflict
- 唯一且完全符合舊 canonical entry → 更新；
  同 command 出現多次／與其他 handler 共用 matcher group／同 basename 指向不同路徑 → **conflict，不猜**
- **嚴格 JSON parse**，只容許移除 UTF-8 BOM；有註解、尾逗號、parse error 就**不動檔**
- **optimistic concurrency**：產生 patched JSON 後，在原子替換**前**重新讀取並比對整檔 hash；
  期間被其他程式（編輯器、ECC）改過就重試或中止，不得覆蓋
- 原子替換用同目錄暫存檔 + rename，保留權限
- 隔離區備份的是**替換當下**的完整 settings 檔

### D7 settings target

- **預設 `~/.claude/settings.json`**（官方文件明定的 user scope）
- target 抽成**單一常數**
- 任何 alternate target（例如 `~/.claude/settings.local.json`）**必須靠真實 nonce probe 證明**，
  不得只憑執行檔字串或推測。未定案的證據與驗證程序見 [`verify-settings-scope.md`](verify-settings-scope.md)
- probe 要在隔離 cwd 用唯一 nonce 證明「這一筆、這個 command」真的執行過，
  避免被專案內另一個 hook 造成假陽性
- **probe 跑不了或失敗 → 標記 `INSTALLED_UNVERIFIED`、不寫 `COMMITTED`、回傳非零**。
  普通 warning 不夠

### D8 併發鎖

- `open(..., 'wx')` 原子建立鎖檔，內含 `{pid, txid, startTime}`
- 偵測到既有鎖 → 中止
- 提供 `--break-lock <txid>`：核對 PID 與 process start identity，**仍存活就拒絕**；
  無法確認時要求明確 force
- **不做時間式 stale 自動回收**
- Node 官方明示 `wx` 的 exclusive 語義在網路檔案系統上可能失效 → 明說只支援本機 filesystem

### D9 不進安裝器的東西

- 步驟 4 `codex-check`（已有獨立腳本）
- 步驟 5 `~/.claude/CLAUDE.md` 全域規則——**需要人類明示同意**，維持顯式 opt-in。
  `--uninstall` 也**不得**移除它（無法證明那個區塊由本安裝器建立）

## 2. CLI

```
node tools/install.js                      # 全流程
node tools/install.js --status
node tools/install.js --recover <txid>
node tools/install.js --rollback <txid>
node tools/install.js --rollback-legacy <ts>
node tools/install.js --uninstall
node tools/install.js --break-lock <txid>
node tools/install.js --dry-run
```

- **UUID `txid` 是身份**，時間戳只作顯示
- `--uninstall` 只移除**目前 active transaction 可證明擁有且未 drift** 的 payload 與 settings fragment

### legacy 回滾

舊流程留下的備份（`~/.claude/skills-backup/超級模式.bak-<ts>` 等）**沒有 manifest**。

- 走**獨立**的 `--rollback-legacy <ts>`，不與新的精確回滾混用
- 先完整預檢三個舊備份／`.absent` 狀態
- live 一律**搬 quarantine**，不遞迴刪除
- 掛載／link／型別不明／settings 已變更 → 停止並輸出人工復原指示
- **文件必須誠實說明這是整棵樹復原，不是精確 manifest 回滾**——
  舊備份不可能重建「哪些檔案是當次安裝寫入的」

## 3. 測試分套

| 套件 | 內容 |
|---|---|
| **共通 contract** | 正常安裝、升級、回滾、uninstall、drift、損毀日誌、路徑穿越、併發、**每個持久化邊界的 crash injection** |
| **平台** | Windows junction/reparse；Linux `mountinfo`；macOS mount table 與檔名正規化 |
| **settings** | 嚴格 JSON、重複 entry、共用 matcher group、同步外部修改、command 含空白 |
| **legacy** | 缺件、型別錯、舊 settings 已變更、quarantine 復原 |

沿用現行 `tests/ai-install/` 的兩條紀律：**變異注入**（錯誤分支不注入等於沒驗，
且注入點要有「注入是否成功」的自我檢查）與**反向驗證**（新回歸案必須對修正前版本 FAIL）。

## 4. Shipping gate（分階段，不做大爆炸切換）

1. 實作 engine + 平台 adapter + fake-home/fault-injection 測試。**正式文件不切換**，
   舊 markdown 流程維持可用
2. Windows、Linux、macOS 三平台原生綠 + disposable home canary
3. 通過後**一次**把 `AI-INSTALL.md` 切到 Node CLI，刪掉可複製執行的舊 code block，
   只保留 legacy recovery 說明

**未達 gate 前不得宣稱三平台完成。** 現行測試臺自己也記載了兩件測不到的事
（NTFS symlink 需提權、掛載點需 root），新測試臺同樣要誠實標示。

## 5. 已知無法在維護者本機驗證的項目

| 項目 | 原因 | 處置 |
|---|---|---|
| NTFS **symlink**（有效與斷鏈） | 無管理員權限、開發者模式未開 | junction 可代理測 reparse 路徑；symlink 分支列入 shipping gate |
| **bind mount** 端到端 | WSL2 無免密碼 sudo | parser 可用真實掛載（`/mnt/c`）驗證；**「受管父目錄內含子掛載點」的端到端拒絕測試列入 shipping gate** |
| macOS 全部 | 沒有 Mac | adapter 可先寫，E2E 列入 shipping gate |

**parser 正確 ≠ 防護已驗證。** 文件不得混淆這兩者。

## 6. 驗收表（實作時回寫）

| 項目 | 狀態 |
|---|---|
| D1 Node 核心骨架 + 平台 adapter 介面 | ☐ |
| D2 掛載／reparse 偵測（祖先 + 後代） | ☐ |
| D3 quarantine 搬移（含同 volume 檢查、禁 copy+delete fallback） | ☐ |
| D4 日誌 + `(live, quarantine)` 復原矩陣 + `COMMITTED` | ☐ |
| D5 雜湊比對動作前提 | ☐ |
| D6 settings semantic patch + optimistic concurrency | ☐ |
| D7 target 常數 + nonce probe + `INSTALLED_UNVERIFIED` | ☐ |
| D8 鎖 + `--break-lock` | ☐ |
| legacy `--rollback-legacy` | ☐ |
| 測試四套 | ☐ |
| 三平台原生綠（shipping gate） | ☐ |
| `AI-INSTALL.md` 切換 | ☐ |
