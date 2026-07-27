# 待驗證：`~/.claude/settings.local.json` 到底會不會被載入？

> 建立於 2026-07-28。**這是一個未定案的問題，不是結論。** 在真機測出結果之前，
> 不要改動 `macos/settings.snippet.json`、`linux/settings.snippet.json` 或安裝指引。

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
