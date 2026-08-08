# ✅ 已結案：`~/.claude/settings.local.json` **不是** user scope

> 建立於 2026-07-28，**同日在 macOS 真機測出結論並已據以修正 repo**。
> 下方保留完整程序作為方法紀錄；要重驗或驗別的版本時可照跑。

> **2026-08-08 註記（不改動下方內文）。** 本檔多處把 ECC 具名為「會覆寫
> `~/.claude/settings.json` 的工具」。**那個具名斷言的證據不足，已在現行指引裡撤下並泛化**。
> 現行說法是：該檔有多個寫入者，**Claude Code 自己的 plugin manager 就是其一**
> （top-level key 除 `hooks` 外還有 `enabledPlugins`，2026-08-08 於維護者機器實查），
> 但**沒有證據顯示任何工具會覆寫或移除 `hooks` 段**。
>
> **下方內文刻意保持原樣**——它是 2026-07-28 當下的假設、決策矩陣與實驗紀錄，
> 改寫等於竄改史實。讀它時請把其中的「ECC」理解為「當時假定的那個覆寫者」。

## 結論（2026-07-28，macOS 26.5.2 arm64 / Claude Code 2.1.163）

**`~/.claude/settings.local.json` 不是 user scope 的 hook 來源。**
它只在「**從家目錄啟動** Claude Code」時生效——因為那時它剛好**就是**專案層的
`.claude/settings.local.json`。從任何其他目錄啟動，hook 完全不會被註冊。

四組實測（啟動目錄 × 註冊位置），marker 有無觸發：

| 啟動目錄 | 註冊處 | 結果 |
|---|---|---|
| `/private/tmp/scope-nonhome` | `~/.claude/settings.local.json` | **沒有觸發** |
| `/Users/<user>`（家目錄） | `~/.claude/settings.local.json` | 觸發 |
| `/private/tmp/scope-projtest` | `<專案>/.claude/settings.local.json` | 觸發 |
| `/private/tmp/scope-nonhome` | `~/.claude/settings.json` | 觸發（對照組） |

**程序偏離（誠實記錄）**：原設計的探針掛 `PreToolUse`+Bash、需要互動式新 session。
執行者從既有 session 開巢狀 `claude -p` 一律得到 `401 OAuth access token has been revoked`，
但發現**認證失敗前 `SessionStart` hooks 已經跑完並寫進 transcript**，因此改用 `SessionStart`
當觸發點，其餘照本文件（備份 → 探針 → A/B → 還原）。

### 獨立旁證

- 該機器現役的 gate **只註冊在 `settings.local.json`**。自 hook 建立以來的
  **143 個 transcript、11 個不同啟動目錄、1,183 次 Bash 呼叫、14,477 次 hook 叫用**中，
  gate 被叫用 **0 次**——那 11 個目錄沒有一個是家目錄，與上表完全自洽。
- Claude Code 的 hook 來源列舉字串（**2.1.148 與 2.1.220 皆同**，Windows 端另行核對）：
  `User-defined hooks from ~/.claude/settings.json, .claude/settings.json, and .claude/settings.local.json`
  ——`~/` **只出現在 `settings.json`**，另兩者是專案相對。

### 先前「證據矛盾」的澄清

本檔原記載「執行檔裡有 `legacy settings.local.json` 字串，與官方文件矛盾」。
**方向搞反了**：實際比對兩個版本——`2.1.148` 命中 **0** 次、`2.1.220` 命中 **14** 次，
所以那些字串是**後來才加入**的（Mac 端的 2.1.163 早於它），不是「已被移除」。
且它們是 read／transform／**revoke**，屬**權限**遷移，與 hook 來源無關；
hook 來源的列舉字串兩版一字不差。**矛盾不存在，結論成立。**

## 已據此修正（2026-07-28）

| 位置 | 改動 |
|---|---|
| `macos/settings.snippet.json`、`linux/settings.snippet.json` | `_comment` 改指向 `~/.claude/settings.json`，並說明為何不能用 local |
| `docs/AI-INSTALL.md` 步驟 2 | 三平台統一 `~/.claude/settings.json`，附實測證據與 ECC 覆寫的正確處理方式 |
| `docs/AI-INSTALL.md` 1b／回滾 | POSIX 的 `setf` 一併改為 `settings.json`（否則備份的是沒在用的檔，回滾還原不到） |
| 三平台 `matcher-contract.test.js` | 移除 `settings.local.json` 候選；**移除 `\|\| candidates[0]` fallback**，找不到已註冊的 hook 直接 FAIL |
| `tests/ai-install/run-posix.sh` | seed 與斷言的 settings 檔名同步 |

**`matcher-contract` 的 fallback 是獨立的假綠來源**（Mac 端附帶發現）：即使拿掉 local 候選，
舊的 `|| candidates[0]` 仍會退而撿一份不相干的 settings 比對而 PASS。
反向驗證（重現 Mac 使用者的實際狀態：gate 只在 `settings.local.json`）——
**舊版 exit 0（假綠）、新版 exit 1 並印出可行動訊息**。

---

# 附錄：原始驗證程序（保留供重驗）

## 為什麼重要

repo 的 macOS／Linux 安裝指引叫使用者把 hook 註冊進 **`~/.claude/settings.local.json`**，
Windows 則用 `~/.claude/settings.json`。

若家目錄的 `settings.local.json` **不會**被 Claude Code 當成 user settings 載入，
那麼照指引安裝的 macOS／Linux 使用者，**hook 從來沒有被註冊過**，gate 完全不作用。

更糟的是 `matcher-contract.test.js` **抓不到這個問題**——它的候選清單包含
`~/.claude/settings.local.json`，找到就 PASS。那支測試的存在目的正是防假綠，
它自己卻可能是假綠的來源。

## 目前的證據（互相矛盾，所以要實測）

| 來源 | 說法 |
|---|---|
| [官方 settings 文件](https://code.claude.com/docs/en/settings) | User scope **只有** `~/.claude/settings.json`。`settings.local.json` 屬於**專案**的 `.claude/` 目錄（repo 根目錄），不是家目錄 |
| 本機安裝的 Claude Code 執行檔（字串搜尋） | 含有主動處理的訊息：`Failed to read legacy settings.local.json at <path>`、`Transform failed against legacy settings.local.json`、`Failed to revoke from legacy settings.local.json`。代表它**確實會讀**一個被稱為「legacy」的 `settings.local.json`——但字串無法分辨那是 user scope 還是專案 scope |
| repo 現況 | 選 `settings.local.json` 是**刻意**的，理由寫在 snippet 的 `_comment`：避免 ECC 重新安裝時覆寫 `~/.claude/settings.json` |

## 驗證程序

**在 macOS 或 Linux 上做**（Windows 已經用 `settings.json`，不受影響）。
需要能開新的 Claude Code session。

### 0. 先備份

```bash
ts=$(date +%Y%m%d-%H%M%S)
for f in ~/.claude/settings.json ~/.claude/settings.local.json; do
  [ -e "$f" ] && cp "$f" "$f.bak-$ts"
done
echo "backup ts=$ts"
```

### 1. 準備探針 hook

```bash
mkdir -p ~/.claude/hooks
cat > ~/.claude/hooks/scope-probe.js <<'EOF'
const fs = require("fs");
fs.appendFileSync(process.env.HOME + "/.claude/scope-probe-fired.txt",
  new Date().toISOString() + "\n");
process.exit(0);
EOF
rm -f ~/.claude/scope-probe-fired.txt
```

### 2. A 組：只註冊在 `settings.local.json`

把下面這段的 `hooks.PreToolUse` 條目**合併**進 `~/.claude/settings.local.json`
（檔案不存在就建立），並**確認 `~/.claude/settings.json` 裡沒有 `scope-probe`**：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "node /絕對路徑/.claude/hooks/scope-probe.js" }]
      }
    ]
  }
}
```

> `command` 的 `node` 若不在系統 PATH（例如可攜式裝在 `~/.local/node/bin`）要寫絕對路徑，
> 否則 hook 會靜默不跑——那會讓這次測試出現**假陰性**。

### 3. 開**新的** Claude Code session，跑一個 Bash 工具，然後檢查

```bash
cat ~/.claude/scope-probe-fired.txt 2>/dev/null || echo "沒有觸發"
```

### 4. B 組（對照組，**不可省略**）

把同一個條目從 `settings.local.json` 移到 `~/.claude/settings.json`，
清掉 marker，再開新 session、再跑一次 Bash 工具、再檢查。

**對照組是必要的**：若 A 組沒觸發、B 組也沒觸發，代表探針本身壞了（路徑錯、node 找不到、
matcher 不符），而不是 `settings.local.json` 不被載入。沒有對照組的 null 結果無法解讀。

### 5. 還原

```bash
rm -f ~/.claude/hooks/scope-probe.js ~/.claude/scope-probe-fired.txt
# 從步驟 0 的備份還原兩個 settings 檔，並移除探針條目
```

## 結果怎麼解讀

| A 組（local） | B 組（settings.json） | 結論 |
|---|---|---|
| 觸發 | 觸發 | `settings.local.json` 有效，現行指引沒問題。把結論回寫本檔、關掉這個議題 |
| **沒觸發** | 觸發 | **現行 macOS／Linux 指引是壞的**。要改用 `settings.json`，並另外處理 ECC 覆寫問題（例如安裝後加一道重新檢查）。同時 `matcher-contract` 要移除 `settings.local.json` 候選，否則繼續假綠 |
| 沒觸發 | 沒觸發 | 探針本身有問題，重做（先確認 `node` 絕對路徑與 matcher） |

## 測完之後

把結果寫回本檔與 [`backlog.md`](backlog.md)，並在 [`AI-INSTALL.md`](AI-INSTALL.md) 更新
對應敘述。若結論是「要改」，記得三件事一起改：兩個 POSIX snippet 的 `_comment`、
安裝指引步驟 2、以及 `matcher-contract.test.js` 的候選清單。
