# 既有使用者修復：hook 可能從來沒有生效過（macOS／Linux）

> 2026-07-28。**只影響 macOS 與 Linux**，且只影響 **2026-07-28 以前**照舊版
> `AI-INSTALL.md` 安裝的人。Windows 一直都是對的，不受影響。

> ## ⛔ 2026-08-08：本文件目前**只可用於診斷**，第 2 節請先不要執行
>
> 2026-08-08 的複查在本文件裡找到三個缺陷。修好之前，請**只讀第 1 節，不要執行第 2 節**。
>
> **1. 第 1 節的 probe 對「JSON 合法但形狀不對」不 fail-closed。**
> `hooks.PreToolUse` 是**字串**時，probe 會 **exit 0**、把 gate 數成 **0**，
> 於是判定成「兩邊都沒有 gate —— 可能還沒安裝……照 `AI-INSTALL` 步驟 2 重做」。
> 那是**假陰性，而且會把你導去重裝**——重裝正是可能造成重複註冊的動作。
> （`PreToolUse` 是 `null` 或物件時則直接以 `TypeError` 中斷；退出碼非零，但只印 stack trace。）
> **所以：只有在兩個檔的 `hooks.PreToolUse` 確實是「陣列」時，第 1 節的判定才可信。**
>
> **2. 判定表的「兩邊都有」在第 2 節沒有對應分支，照做會變成重複註冊。**
> 判定表對 `≥1 ／ ≥1` 寫的是「要**移除** local 那份」，但第 2 節只有 2.2 一條路，
> 而 2.2 是**無條件**的「整個條目**搬**進 `settings.json`，再從 `settings.local.json` 刪掉」。
> `settings.json` 已經有一筆時照做就會變成**兩筆**。
> **這種情況正確做法是：只從 `settings.local.json` 刪掉，不要搬。**
>
> **3. 2.2 的「整個條目」可能夾帶不相關的 hook。**
> 若那個 `PreToolUse` 條目底下除了 gate 還掛著別的 handler，整筆搬移會把它們一起升到 user scope；
> 整筆刪除則會把它們一起移除。**遇到這種情況請停手。**
>
> **正確的後置條件**（可拿來自我檢查）：
> `~/.claude/settings.json` 的 gate handler **恰 1 個**、`~/.claude/settings.local.json` **0 個**。
>
> ⚠️ **證據範圍**：以上是 2026-08-08 對 `main` 的靜態檢視，加上把第 1 節的 probe 原樣抽出、
> 以假 `HOME` 餵四種 `settings.json`（`null`／物件／字串／正常陣列，最後一種為對照組）
> 在 Node v24.16.0 實跑的結果。**未**在真實受影響的 macOS／Linux 環境端到端驗證。
> 追蹤見 [`backlog.md`](backlog.md)。

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

**用語意解析，不要用 `grep`。** 全文 `grep` 會命中 `_comment` 裡的說明字、其他 hook 事件、
甚至無效 JSON 裡的殘骸，把受影響的人誤判成正常。下面這段直接解析
`hooks.PreToolUse[].hooks[].command`（`node` 是 hook 本身的前置，一定有）：

```bash
node - <<'PROBE'
const fs = require("fs"), os = require("os"), path = require("path");
const NEEDLE = "super-mode-consult-gate";
let unreadable = false;
const count = (label, p) => {
  let raw;
  try { raw = fs.readFileSync(p, "utf8"); }
  catch (e) {
    if (e.code === "ENOENT") { console.log(label.padEnd(32) + "檔案不存在"); return 0; }
    console.log(label.padEnd(32) + "讀取失敗：" + e.code); unreadable = true; return -1;
  }
  let j;
  try { j = JSON.parse(raw.replace(/^﻿/, "")); }
  catch (e) { console.log(label.padEnd(32) + "JSON 解析失敗：" + e.message); unreadable = true; return -1; }
  let n = 0;
  for (const entry of (j.hooks && j.hooks.PreToolUse) || [])
    for (const h of (entry && Array.isArray(entry.hooks) ? entry.hooks : []))
      if (String((h && h.command) || "").includes(NEEDLE)) n++;
  console.log(label.padEnd(32) + "gate 條目：" + n + " 個");
  return n;
};
const home = os.homedir();
const main  = count("~/.claude/settings.json", path.join(home, ".claude", "settings.json"));
const local = count("~/.claude/settings.local.json", path.join(home, ".claude", "settings.local.json"));
console.log("");
if (unreadable)                   console.log("判定：有檔案無法解析 —— 先修好 JSON 再重跑，不要往下做。");
else if (main > 0 && local === 0) console.log("判定：正常，不用修。");
else if (main > 0 && local > 0)   console.log("判定：兩邊都有 —— 要移除 local 那份，否則從家目錄啟動時會重複註冊。往下做第 2 節。");
else if (main === 0 && local > 0) console.log("判定：受影響 —— gate 只在 local，從非家目錄啟動完全不生效。往下做第 2 節。");
else                              console.log("判定：兩邊都沒有 gate —— 可能還沒安裝，或註冊在別處。照 AI-INSTALL 步驟 2 重做。");
PROBE
```

判定表（上面那段會直接印出結論，這裡列出對應關係）：

| `settings.json` | `settings.local.json` | 判定 |
|---|---|---|
| ≥1 | 0 | **正常**，不用往下做 |
| ≥1 | ≥1 | 往下做——要移除 local 那份，否則從家目錄啟動時**重複註冊** |
| 0 | ≥1 | **受影響**，往下做 |
| 0 | 0 | 可能還沒安裝，或註冊在別處——照 `AI-INSTALL` 步驟 2 重做 |
| 任一無法解析 | | **先修好 JSON**，不要往下做 |

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
set -euo pipefail
ts=$(date +%Y%m%d-%H%M%S)
for f in ~/.claude/settings.json ~/.claude/settings.local.json; do
  [ -e "$f" ] || [ -L "$f" ] || continue
  if [ -L "$f" ]; then echo "$f 是 symlink，狀態不明，中止"; exit 1; fi
  if [ ! -f "$f" ]; then echo "$f 存在但不是一般檔案，中止"; exit 1; fi
  b="$f.bak-$ts"
  if [ -e "$b" ] || [ -L "$b" ]; then echo "已存在 $b，等一秒後重跑，中止"; exit 1; fi
  cp "$f" "$b"
  cmp -s "$f" "$b" || { echo "$b 備份不完整，中止"; exit 1; }
done
echo "backup ts=$ts"
```

> 這段是 **fail-fast** 的：任何一步失敗就中止，**不會印出 `ts`**。
> 所以「有印出 `ts`」才等於「該備份的都備份完成且逐位元組比對過」。
> 舊版沒有 `set -e`、沒有撞名拒絕、也沒有 `cmp` 驗證——`cp` 失敗仍會一路跑到底印出
> `backup ts=`，接著你就會在「以為有備份」的狀態下手動改 settings。

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
