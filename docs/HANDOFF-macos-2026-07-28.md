# HANDOFF — macOS 原生驗證（2026-07-28 批）

> ## ⛔ 不要安裝這個分支
> 本分支的改動**只在 Windows 與 WSL2 上跑過**，macOS 未經真機驗證。
> **不要**把這個分支的檔案複製進 `~/.claude/`，**不要**照 `docs/AI-INSTALL.md` 安裝它。
> 這份 handoff 做的是：在**隔離的 worktree 裡**跑測試 + 一項需要真 Claude Code 的行為實測，
> 把**原始輸出**貼回來。驗證通過後由 Windows 端 promote，那時才輪到部署。

**待驗證的 SHA**：`53cbc5ff0929ae4f2b29b8177818891ad17bc068`
**分支**：`refactor/context-engineering-2026-07-27-pending-native-macos`

---

## 0. 三件事，優先序如下

| # | 任務 | 為什麼非 mac 不可 | 需要 |
|---|---|---|---|
| **A** | **`settings.local.json` scope 行為實測** | 這是**目前最重要的未知**。若家目錄的 `settings.local.json` 不被載入，照現行指引安裝的 macOS／Linux 使用者 **hook 從來沒生效過** | 真的 Claude Code，會動到你的 `~/.claude`（有備份與還原步驟） |
| **B** | 2026-07-27 context-engineering 批次的原生回歸 | `gate-cases` 有 mac 專屬語義（`/private/tmp`↔`/tmp` 等價、`os.tmpdir()` 是 `/var/folders/...`） | 只跑測試，唯讀 |
| **C** | `AI-INSTALL` POSIX 流程在 **BSD userland** 的驗證 | 該流程剛從 GNU 專屬寫法移植成可攜，**推論可攜、未實測** | 只跑測試，用假 HOME，唯讀 |

**A 與 B/C 可以分開做。** 若只想做低風險的部分，做 B 和 C 就好，A 另外再說。

---

## 1. 前置

```bash
node --version      # 需 ≥ 18；C 項不依賴新語法
sw_vers             # 確認是 macOS
```

取得待驗證的樹（**用完整 SHA，不要用分支名**——分支可能被後續 push 移動）：

```bash
cd <你本地的 Codex-for-CC clone>
git fetch origin refactor/context-engineering-2026-07-27-pending-native-macos
git worktree add --detach /tmp/mac-verify-0728 53cbc5ff0929ae4f2b29b8177818891ad17bc068
cd /tmp/mac-verify-0728
git rev-parse HEAD    # 必須等於 53cbc5ff0929ae4f2b29b8177818891ad17bc068
```

### blob 核對（證明樹沒被動過手腳）

```bash
for f in "macos/hooks/super-mode-consult-gate.js" \
         "macos/settings.snippet.json" \
         "macos/skills/超級模式/SKILL.md" \
         "macos/skills/超級模式/tests/gate-cases.json" \
         "macos/skills/超級模式/tests/matcher-contract.test.js" \
         "docs/AI-INSTALL.md" \
         "tests/ai-install/run-posix.sh"; do
  printf "%s  %s\n" "$(git rev-parse HEAD:"$f")" "$f"
done
```

期望值（任一不符就停下回報）：

| blob | 檔案 |
|---|---|
| `0e2bbc7858e0c6a6ca2fb68acbc6661c55a22658` | `macos/hooks/super-mode-consult-gate.js` |
| `565ca42626180553273e852729b72b956292e466` | `macos/settings.snippet.json` |
| `3fe1084a486f1ec33098fc81bc3fbaaf11521a97` | `macos/skills/超級模式/SKILL.md` |
| `ded377c801cbe9de40719aa1de816b96df0c789b` | `macos/skills/超級模式/tests/gate-cases.json` |
| `5a1356b39ee43633ecf95506d38a440e6987e67e` | `macos/skills/超級模式/tests/matcher-contract.test.js` |
| `103c386c65a9dd1a33a95e256cf7ac67e9624fe0` | `docs/AI-INSTALL.md` |
| `b83a6373ac2bc6c1c4f71c5546c1d97ff6987639` | `tests/ai-install/run-posix.sh` |

### 確認真的在 darwin 上跑（防假 PASS）

```bash
node -e 'if (process.platform !== "darwin") { console.error("NOT DARWIN: " + process.platform); process.exit(2) } console.log("platform=darwin OK, tmpdir=" + require("os").tmpdir())'
```

**exit 2 就代表整份驗證作廢**——曾有過「在容器／WSL 裡呼到別的 node」的假驗證。

---

## 2. 任務 B：context-engineering 批次回歸（唯讀）

```bash
cd "/tmp/mac-verify-0728/macos/skills/超級模式/tests"
node --check ../../../hooks/super-mode-consult-gate.js && echo "syntax OK"
node run-gate-tests.js
node matcher-contract.test.js
bash consult-schema.tests.sh
bash run-e2e.sh
```

| 指令 | 期望 |
|---|---|
| `node --check …` | `syntax OK` |
| `node run-gate-tests.js` | **`PASS 117/117`** |
| `node matcher-contract.test.js` | exit 0（會印工具名一致的訊息）|
| `bash consult-schema.tests.sh` | **4/4** |
| `bash run-e2e.sh` | 沿用該腳本既有的全綠判準 |

`run-gate-tests.js` 會**優先載入同樹的 hook**（相對路徑），不會吃到你 `~/.claude` 的安裝版。
若它印出的 hook 路徑不在 `/tmp/mac-verify-0728` 底下，停下來回報。

---

## 3. 任務 C：`AI-INSTALL` POSIX 流程在 BSD 上的驗證（唯讀，用假 HOME）

這支測試臺會從 `docs/AI-INSTALL.md` **抽出** bash 區塊、用**假 `HOME`** 執行，
再檢查檔案系統狀態。**不會碰你真正的 `~/.claude`。**

```bash
cd /tmp/mac-verify-0728
bash tests/ai-install/run-posix.sh
```

**期望：`bash PASS=59 FAIL=0`**（Linux／WSL2 上是這個數字）。

### 這一項為什麼要 mac 跑

2026-07-28 才把三處 **GNU 專屬**寫法移植成可攜，**macOS 上一次都沒跑過**：

| 原本（GNU 專屬） | 改成 |
|---|---|
| `find -printf` | 型別與相對路徑在 shell 內算（`-exec sh -c … {} +`）|
| `md5sum` | POSIX 的 `cksum` |
| `date -d "+N second"` | 忙等跨秒取得整秒餘裕 |

同一批還修掉了 `AI-INSTALL` 裡一個 **fail-open**：原本 `find "$s" -type l -print -quit 2>/dev/null`
——`-quit` 是 GNU 專屬，而且 `2>/dev/null` 會把 find 的錯誤吞掉、變數變空字串，
守衛靜默失效。已改成偵測退出碼、掃描失敗一律中止。**這條在 BSD 上的行為正是要你驗的。**

### 若有 FAIL

貼完整輸出。特別留意這幾類（都是平台語義，不是邏輯錯）：

- `bash` 版本：macOS 內建 `/bin/bash` 是 **3.2**。若錯誤看起來像語法不支援，回報 `bash --version`
- `readlink`／`cksum`／`find … {} +` 的行為差異
- 假 HOME 底下出現非預期檔案（macOS 可能寫 `.CFUserTextEncoding` 之類）導致快照比對失敗
  ——這是**測試臺**要調整，不是受測流程的錯，回報現象即可

### 反向驗證（可選但建議）

確認這批測試真的有區辨力，而不是恆真：

```bash
cd /tmp/mac-verify-0728
git show 06adac5:docs/AI-INSTALL.md > /tmp/r8pre.md
DOC=/tmp/r8pre.md bash tests/ai-install/run-posix.sh
```

**期望：會 FAIL（Linux 上是 7 個）。** 若這裡全綠，代表測試沒有區辨力，回報。

---

## 4. 任務 A：`settings.local.json` scope 實測（**會動到你的 `~/.claude`**）

完整背景、A/B 程序與結果解讀表在
[`docs/verify-settings-scope.md`](verify-settings-scope.md)（同一棵樹裡）。**照那份做。**

摘要：

- **問題**：repo 的 macOS／Linux 指引把 hook 註冊進 `~/.claude/settings.local.json`。
  官方文件說 user scope **只有** `~/.claude/settings.json`、`settings.local.json` 是**專案**層級。
  但本機 Claude Code 執行檔裡又有「legacy settings.local.json」的主動處理字串。**證據矛盾，要實測。**
- **做法**：放一個只會寫 marker 檔的探針 hook，A 組只註冊在 `settings.local.json`、
  B 組只註冊在 `settings.json`，各開**新 session** 觸發一次，看 marker 有沒有出現。
- **對照組 B 不可省略**：若 A、B 都沒觸發，代表探針本身壞了（`node` 絕對路徑、matcher 不符），
  不是 `settings.local.json` 無效。沒有對照組的 null 結果無法解讀。

⚠️ 這一項會改你的 `~/.claude/settings*.json`。程序第 0 步有備份、第 5 步有還原，**請照做**。
若不想動自己的環境，**跳過 A**，只回報 B 和 C——A 可以之後再找機會做。

---

## 5. ⚠️ 不要做這些

- **不要** `cp` 這棵樹的任何檔案到 `~/.claude/`（任務 A 的探針除外，那是它自己的檔）
- **不要**從 `~/.claude/skills/超級模式/tests/` 跑 `matcher-contract.test.js`
  （你的 live settings 還沒有新版 matcher，在 live 跑一定 FAIL，那是預期的）
- **不要**對這個分支開 PR、merge、push
- **不要** force push
- 驗完 `git worktree remove /tmp/mac-verify-0728`

---

## 6. 回報格式

貼**原始輸出**，不要只寫「全過」：

1. `git rev-parse HEAD` 的值
2. 7 筆 blob 的實際輸出
3. `platform=darwin OK, tmpdir=…` 那行
4. **任務 B**：`run-gate-tests.js` 最後一行（含數字）、`matcher-contract` 整行 + exit code、
   `consult-schema` 的 4/4、`run-e2e.sh` 結果
5. **任務 C**：`bash PASS=… FAIL=…` 那行；有 FAIL 就貼完整段落。另附 `bash --version`
6. **任務 A**（若有做）：A 組與 B 組各自的 marker 檔內容（或「沒有觸發」），
   以及你實際用的 `command` 字串

**有任何一項不符就停在那裡回報，不要自行修。**
若是測試臺本身的平台差異（例如 macOS 在假 HOME 下自動建檔），回報現象即可，
由 Windows 端決定改法——這樣才能保證「驗的 bytes」與「日後 merge 的 bytes」是同一份。

---

## 7. 驗證通過後（Windows 端執行，不是你）

- 任務 B/C 綠 → 回寫 `docs/backlog.md` 的 macOS 待驗證列
- 任務 A 有結論 → 回寫 [`verify-settings-scope.md`](verify-settings-scope.md)，
  並依結論決定是否修 snippet／安裝指引／`matcher-contract` 候選清單
- promote 進 main **必須先取得使用者同意**（repo 慣例：推驗證分支不用問，推 main 要問）
