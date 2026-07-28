# 既有使用者修復：hook 可能從來沒有生效過（macOS／Linux）

> 2026-07-28。**只影響 macOS 與 Linux**，且只影響 **2026-07-28 以前**照舊版
> `AI-INSTALL.md` 安裝的人。Windows 一直都是對的，不受影響。

## 症狀

舊版安裝指引叫你把 hook 註冊進 `~/.claude/settings.local.json`。
**那不是 user scope。** 它只在「**從家目錄啟動** Claude Code」時才生效——
因為那時它剛好就是專案層的 `.claude/settings.local.json`。

所以如果你平常是 `cd ~/projects/foo && claude` 這樣用，
**gate 從安裝到現在一次都沒有被叫用過**，超級模式的攔截完全沒有作用。

原因與完整實測證據見 [`verify-settings-scope.md`](verify-settings-scope.md)。

---

## 1. 診斷（唯讀，不會改任何東西）

### 1.1 看 hook 現在註冊在哪

```bash
for f in ~/.claude/settings.json ~/.claude/settings.local.json; do
  if [ -e "$f" ]; then
    printf '%-40s super-mode 命中 %s 次\n' "$f" "$(grep -c 'super-mode-consult-gate' "$f" 2>/dev/null || echo 0)"
  else
    printf '%-40s (不存在)\n' "$f"
  fi
done
```

- `settings.json` 命中 ≥1 → **你沒事**，不用往下做
- 只有 `settings.local.json` 命中 → **你受影響**，往下做
- 兩邊都命中 → 也往下做（要把 local 那份移除，避免從家目錄啟動時重複註冊）

### 1.2 快速看它到底有沒有跑過（**參考用，不是證明**）

Claude Code 會把每個 session 的 transcript 放在 `~/.claude/projects/<啟動目錄的 slug>/`。
目錄名就是啟動目錄，可以看出你都從哪裡開 session：

```bash
ls ~/.claude/projects/ 2>/dev/null
```

若這裡面**沒有**你家目錄對應的那一個（例如 `-Users-yourname` 或 `-home-yourname`），
那 gate 幾乎可以確定一次都沒被叫用過。

> ⚠️ 這只是快速指標。**唯一決定性的驗證是下面第 3 節**——開一個新 session 實際觸發一次。

---

## 2. 修復

### 2.1 先備份

```bash
ts=$(date +%Y%m%d-%H%M%S)
for f in ~/.claude/settings.json ~/.claude/settings.local.json; do
  [ -e "$f" ] && cp "$f" "$f.bak-$ts"
done
echo "backup ts=$ts"
```

### 2.2 手動搬移（**刻意不提供自動腳本**，理由見下）

打開 `~/.claude/settings.local.json`，找到 `hooks.PreToolUse` 裡 `command` 含
`super-mode-consult-gate` 的那個條目，**整個條目**搬到 `~/.claude/settings.json`
的 `hooks.PreToolUse` 陣列裡（**合併，不要覆蓋既有設定**），然後從
`settings.local.json` 刪掉它。

搬過去的條目長這樣（`command` 保留你原本的絕對路徑，不要改）：

```json
{
  "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|Monitor|RemoteTrigger|PushNotification|CronCreate|CronDelete|Artifact|ScheduleWakeup|EnterWorktree|ExitWorktree|mcp__.*",
  "hooks": [
    { "type": "command", "command": "node /你的家目錄/.claude/hooks/super-mode-consult-gate.js" }
  ]
}
```

- 若 `settings.json` 不存在 → 建立 `{"hooks":{"PreToolUse":[ <上面那個條目> ]}}`
- 若 `settings.json` 已有其他 `PreToolUse` 條目 → **加進陣列**，不要取代
- `matcher` 內容**一字不要改**——它必須與 hook 的工具清單完全一致，否則第 3 節的
  `matcher-contract` 會 FAIL（那正是它的用途）
- Linux 且 `node` 不在系統 PATH（例如可攜式裝在 `~/.local/node/bin`）→
  `command` 開頭的 `node` 要寫**絕對路徑**，否則 hook 會靜默不跑

> **為什麼不給自動腳本？** 這個 repo 在 2026-07-27 花了九輪對抗審查才學到：
> **把「搬移＋刪除」這種會動使用者檔案的狀態機寫成複製貼上的 markdown，
> 每補一個洞就多一層沒有測試守著的分支。** 這件事的正確位置是
> [`installer-rewrite-spec.md`](installer-rewrite-spec.md) 規劃中的安裝器
> （D6 settings semantic patch），那裡有測試臺與 conflict 處理。
> 在它做好之前，手動編輯兩個小 JSON 比一段沒測過的腳本安全。

---

## 3. 驗證（**兩步都要做**）

### 3.1 靜態：matcher 是否真的合併進去了

```bash
node ~/.claude/skills/超級模式/tests/matcher-contract.test.js; echo "exit=$?"
```

- `exit=0` → matcher 與 hook 的工具清單一致
- `exit=1` 且訊息說「找不到已註冊本 hook 的 settings」→ 2.2 沒搬成功，回去檢查

> 這支測試在 2026-07-28 之前**會假綠**：它的候選清單含 `settings.local.json`，
> 找到就 PASS，等於驗了一份 Claude Code 根本不載入的檔案。現在已移除該候選，
> 並移除 `|| candidates[0]` 的 fallback——找不到就直接 FAIL。

### 3.2 端到端：真的會被叫起嗎

靜態測試**不能**證明 hook 會被叫起（它只比對兩份檔案的字串）。唯一的確認方式：

1. `cd` 到一個**不是家目錄**的地方（這很重要——從家目錄啟動會讓舊設定也生效，測不出差別）
2. 開一個**新的** Claude Code session（hook 設定變更下個 session 才生效）
3. 開啟超級模式，在**沒有憑證**的狀態下試一個會被攔的動作
4. 應該要被 deny

沒被 deny → hook 沒接上，回到 2.2。

---

## 4. 如果你的 `~/.claude/settings.json` 會被別的工具覆寫

例如 ECC 重新安裝。這是真實的衝突——舊版指引選 `settings.local.json` 就是為了躲它。
但躲進一個**不會被載入的檔案**不能算解法，只是讓問題從「被覆寫」變成「從來沒生效」。

現階段的做法：**覆寫之後重跑 3.1**。它現在找不到已註冊的 hook 會直接 FAIL，
不會再靜默通過，所以你至少會知道要重補。

長期做法記在 [`installer-rewrite-spec.md`](installer-rewrite-spec.md)：
安裝器會做 entry-level 的 semantic patch，並在寫入前重新比對整檔雜湊，
避免蓋掉別的工具同期做的修改。

---

## 5. 收尾

確認 3.1 與 3.2 都過之後，2.1 產生的備份可以自行刪除：

```bash
ls -la ~/.claude/settings*.json.bak-*
```

（確認無誤再刪。這些檔可能含環境變數、API 端點等設定，比一般垃圾檔敏感。）
