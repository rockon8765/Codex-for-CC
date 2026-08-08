# 既有使用者修復：hook 可能從來沒有生效過（macOS／Linux）

> 2026-07-28。**只影響 macOS 與 Linux**，且只影響 **2026-07-28 以前**照舊版
> `AI-INSTALL.md` 安裝的人。Windows 一直都是對的，不受影響。

> **2026-08-08 修訂。** 本文件先前有三個缺陷，已一併修好：
>
> 1. 第 1 節的 probe 對「JSON 合法但形狀不對」**不 fail-closed**——`hooks.PreToolUse`
>    是字串時會 exit 0 並把 gate 數成 0，判定成「兩邊都沒有 gate……重做安裝」，
>    而重裝正是可能造成重複註冊的動作。現在**逐層驗形狀，異形一律 exit 1**。
> 2. 判定表把「`settings.json` 已有 ≥1 筆」一律當成正常，且「兩邊都有」在第 2 節
>    沒有對應分支。現在拆成 **1** 與 **≥2**，第 2 節也拆成 **A（還沒有）** 與
>    **B（已經有／重複）** 兩支，B 是**減法**不是搬移。
> 3. 第 2 節的粒度從「整個 outer entry」改為 **handler**，並明列停手條件——
>    避免把掛在同一個 entry 的其他 hook 一起搬走或刪掉。
>
> ⚠️ **證據範圍**：probe 的行為以假 `HOME` 餵九種輸入實測（含正常對照組）；
> 第 2 節的修訂是**文件層的靜態修正**，**未**在真實受影響的 macOS／Linux 環境端到端驗證。

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
let invalid = false;
// 逐層驗形狀，異形一律 fail-closed。**只數「有沒有 gate」而不驗形狀是不夠的**：
// 舊版寫 `for (const entry of (j.hooks && j.hooks.PreToolUse) || [])`，當
// `hooks.PreToolUse` 是**字串**時會逐字元迭代、靜默數成 0，於是判定成「兩邊都沒有
// gate……照 AI-INSTALL 步驟 2 重做」——假陰性，而且重裝正是可能造成重複註冊的動作。
// （2026-08-08 以假 HOME 餵 null／物件／字串／正常陣列四種輸入實測，最後一種為對照組。）
const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const typeName = (v) => (v === null ? "null" : Array.isArray(v) ? "陣列" : typeof v);
const bad = (label, why) => {
  console.log(label.padEnd(32) + "形狀不合：" + why); invalid = true; return -1;
};
const count = (label, p) => {
  let raw;
  try { raw = fs.readFileSync(p, "utf8"); }
  catch (e) {
    if (e.code === "ENOENT") { console.log(label.padEnd(32) + "檔案不存在"); return 0; }
    console.log(label.padEnd(32) + "讀取失敗：" + e.code); invalid = true; return -1;
  }
  let j;
  try { j = JSON.parse(raw.replace(/^﻿/, "")); }
  catch (e) { console.log(label.padEnd(32) + "JSON 解析失敗：" + e.message); invalid = true; return -1; }
  if (!isObj(j)) return bad(label, "頂層不是物件（是 " + typeName(j) + "）");
  if (!("hooks" in j)) { console.log(label.padEnd(32) + "沒有 hooks 段 —— gate 條目：0 個"); return 0; }
  if (!isObj(j.hooks)) return bad(label, "hooks 不是物件（是 " + typeName(j.hooks) + "）");
  const pre = j.hooks.PreToolUse;
  if (pre === undefined) { console.log(label.padEnd(32) + "沒有 hooks.PreToolUse —— gate 條目：0 個"); return 0; }
  if (!Array.isArray(pre)) return bad(label, "hooks.PreToolUse 不是陣列（是 " + typeName(pre) + "）");
  let n = 0;
  for (let i = 0; i < pre.length; i++) {
    const entry = pre[i];
    if (!isObj(entry)) return bad(label, "PreToolUse[" + i + "] 不是物件（是 " + typeName(entry) + "）");
    if (entry.hooks === undefined) continue;
    if (!Array.isArray(entry.hooks)) return bad(label, "PreToolUse[" + i + "].hooks 不是陣列（是 " + typeName(entry.hooks) + "）");
    for (let k = 0; k < entry.hooks.length; k++) {
      const h = entry.hooks[k];
      if (!isObj(h)) return bad(label, "PreToolUse[" + i + "].hooks[" + k + "] 不是物件（是 " + typeName(h) + "）");
      if (h.command === undefined) continue;
      if (typeof h.command !== "string") return bad(label, "PreToolUse[" + i + "].hooks[" + k + "].command 不是字串（是 " + typeName(h.command) + "）");
      if (h.command.includes(NEEDLE)) n++;
    }
  }
  console.log(label.padEnd(32) + "gate 條目：" + n + " 個");
  return n;
};
const home = os.homedir();
const main  = count("~/.claude/settings.json", path.join(home, ".claude", "settings.json"));
const local = count("~/.claude/settings.local.json", path.join(home, ".claude", "settings.local.json"));
console.log("");
if (invalid) {
  console.log("判定：有檔案無法解析或形狀不合 —— 先修好再重跑，不要往下做。");
  process.exit(1);   // fail-closed：形狀不明時不可以讓人拿 exit 0 當成「已確認沒問題」
}
if (main === 1 && local === 0)     console.log("判定：正常，不用修。");
else if (main > 1)                 console.log("判定：settings.json 裡有 " + main + " 筆 gate —— 已經重複註冊。做第 2 節的『B. 已經有一筆』。");
else if (main === 1 && local >= 1) console.log("判定：兩邊都有 —— **只要從 settings.local.json 移除**，不要搬。做第 2 節的『B. 已經有一筆』。");
else if (main === 0 && local >= 1) console.log("判定：受影響 —— gate 只在 local，從非家目錄啟動完全不生效。做第 2 節的『A. 還沒有』。");
else                               console.log("判定：兩邊都沒有 gate —— 可能還沒安裝，或註冊在別處。照 AI-INSTALL 步驟 2 重做。");
PROBE
```

判定表（上面那段會直接印出結論，這裡列出對應關係）：

| `settings.json` | `settings.local.json` | 判定 | 去第 2 節的哪一支 |
|---|---|---|---|
| **1** | 0 | **正常**，不用往下做 | — |
| **≥2** | 任意 | **已經重複註冊**（多半是重跑安裝 append 出來的）| **B** |
| 1 | ≥1 | 兩邊都有 —— **只從 `settings.local.json` 移除，不要搬** | **B** |
| 0 | ≥1 | **受影響**：gate 只在 local，從非家目錄啟動完全不生效 | **A** |
| 0 | 0 | 可能還沒安裝，或註冊在別處——照 `AI-INSTALL` 步驟 2 重做 | — |
| 任一無法解析／形狀不合 | | **先修好再重跑**，不要往下做（probe 退出碼 **1**）| — |

> **為什麼「≥1／0」要拆成「1」與「≥2」**：舊版把兩者都算「正常」，於是
> `settings.json` 裡有兩筆重複 gate 時會被判成不用修。而重複註冊正是
> 「照著安裝指引再跑一次」最容易產生的狀態。

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

### 2.2 手動修正（**刻意不提供自動腳本**，理由見下）

> **粒度是「handler」不是「整個條目」。** `hooks.PreToolUse` 的一個 outer entry
> 底下可以掛**多個** handler，那些 handler 可能與本 skill 無關。
> 舊版叫你搬「整個條目」，於是：outer entry 還掛著別的 hook 時，
> 搬過去會把不相關的 hook 一併升到 user scope，刪掉則會把它們一併移除。
>
> **先數清楚再動手。** 「`command` 含 `super-mode-consult-gate` 的 **handler**」
> 在兩個檔各有幾個？第 1 節的 probe 印的就是這個數字。
>
> ⚠️ **遇到下列任一情況請停手**，本文件涵蓋不了，請開 issue 或人工判斷：
> - 含 gate 的那個 outer entry 底下**還有其他 handler**
> - `settings.json` 裡有 **≥2 筆** gate handler，但它們的 `matcher` 或 `command` **不一致**
>   （不知道該留哪一筆；一致的話留任一筆即可）

**先看第 1 節判定表指到 A 還是 B。**

#### A. `settings.json` 還沒有 gate

把下面這個條目**加進** `~/.claude/settings.json` 的 `hooks.PreToolUse` 陣列
（**合併，不要覆蓋既有設定**），然後從 `settings.local.json` 移除它的 gate handler
——handler 移除後那個 outer entry 若變成空的（`hooks` 為 `[]`），連 entry 一起刪。

#### B. `settings.json` 已經有 gate（重複註冊，或兩邊都有）

**不要再新增，也不要搬。** 要做的是**減法**：

- `settings.json` 裡保留**恰好一筆** gate handler，其餘刪除
- `settings.local.json` 裡的 gate handler **全部**刪除
- 兩邊只要有 outer entry 因此變成空的，連 entry 一起刪

#### 兩支共用的條目樣板

（`command` 保留你原本的絕對路徑，不要改）：

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

#### 完成後必須成立的後置條件

```
~/.claude/settings.json        gate handler 恰 1 個
~/.claude/settings.local.json  gate handler 0 個（或整個檔不存在）
```

**重跑第 1 節的 probe 就是在驗這件事**：它印「判定：正常，不用修。」且退出碼為 0
才算完成。任何其他判定都代表還沒做完——特別是「已經重複註冊」。

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
