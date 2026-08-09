# 既有使用者修復：hook 可能從來沒有生效過（macOS／Linux）

> 2026-07-28。**只影響 macOS 與 Linux**，且只影響 **2026-07-28 以前**照舊版
> `AI-INSTALL.md` 安裝的人。Windows 一直都是對的，不受影響。

> **2026-08-08 修訂。** 本文件**下列五個**缺陷已修。**「已修」只涵蓋這五條**——
> 其餘章節不在本次修訂範圍內，特別是第 3.1 節（見該節開頭的 ⛔）：
>
> 1. 第 1 節的 probe 對「JSON 合法但形狀不對」**不 fail-closed**——`hooks.PreToolUse`
>    是字串時會 exit 0 並把 gate 數成 0，判定成「兩邊都沒有 gate……重做安裝」，
>    而重裝正是可能造成重複註冊的動作。現在**逐層驗形狀，異形一律非 0 退出**。
> 2. 判定表把「`settings.json` 已有 ≥1 筆」一律當成正常，且「兩邊都有」在第 2 節
>    沒有對應分支。現在拆成 **1** 與 **≥2**，第 2 節也拆成 **A（還沒有）** 與
>    **B（已經有／重複）** 兩支，B 是**減法**不是搬移。
> 3. 第 2 節的粒度從「整個 outer entry」改為 **handler**——避免把掛在同一個 entry
>    的其他 hook 一起搬走或刪掉。停手條件改由 probe **機械判定**，本文件不再摘要一份。
> 4. 新舊 probe **都**只在 `command` 裡找 needle，因此漏掉 Claude Code 官方支援的
>    **exec form**（`{"type":"command","command":"node","args":["…gate.js"]}`）。那會被數成 0、
>    判成「兩邊都沒有 gate」，接著 `AI-INSTALL` 步驟 2 叫人再加一筆——
>    **這支診斷自己製造出它要防的重複註冊**。現在看到 exec form 一律**停手（exit 3）**：
>    不宣稱看得懂它，但也不再給出會造成重複註冊的答案。
> 5. 第 2 節的備份先前只有 bash 版，Windows 使用者被導去 `AI-INSTALL` 步驟 1b，
>    但 1b **只備 `settings.json`**，漏掉 B 分支真正會刪的 `settings.local.json`。
>    改成三平台共用的 [`tools/backup-settings.js`](../tools/backup-settings.js)。
>
> **probe 已從本文件抽成 [`tools/probe-gate-registration.js`](../tools/probe-gate-registration.js)。**
> 原因有二：內嵌的 bash heredoc 在 Windows 的 PowerShell 跑不動（而「重複註冊」三平台都會發生，
> `AI-INSTALL` 步驟 2 會叫三平台的人都跑它）；而且內嵌在 markdown 裡的邏輯沒有任何回歸案守著。
> 現在有 [`tests/probe-gate-registration.test.js`](../tests/probe-gate-registration.test.js)：**44 案**，
> 對修訂前那版（`5cc50e0`）反向驗證為 **7 PASS／37 FAIL**，通過的 7 個恰為行為未改變的對照組。
>
> ⚠️ **這支 probe 的範圍刻意很窄，而且它每次執行都會把範圍印在最後**（不是只在找到 gate 時）。
> **本文件不再複述那份清單**——請以它印出來的為準；有兩個案子（`scope-*`）專門釘住
> 「它**不**驗什麼」，確保文案與行為不會再各走各的。
> 這段話本身已經寫錯過兩次（先寫成「無關的畸形會被略過」，與實作相反；再寫成「唯二例外」，
> 漏了「非 gate 的 handler 不驗 `type` 型別」這第三類），所以現在改成**只指向單一來源**。
>
> ⚠️ **證據範圍**：probe 的行為有跨平台的自動化回歸案；第 2 節的修訂是**文件層的靜態修正**，
> **未**在真實受影響的 macOS／Linux 環境端到端驗證。

## 症狀

舊版安裝指引叫你把 hook 註冊進 `~/.claude/settings.local.json`。
**那不是 user scope。** 它只在「**從家目錄啟動** Claude Code」時才生效——
因為那時它剛好就是專案層的 `.claude/settings.local.json`。

所以如果你平常是 `cd ~/projects/foo && claude` 這樣用，
**gate 從安裝到現在一次都沒有被叫用過**，超級模式的攔截完全沒有作用。

原因與完整實測證據見 [`verify-settings-scope.md`](verify-settings-scope.md)。

---

## 1. 診斷（唯讀，不會改任何東西）

> **Windows 也會用到本節。** 本文件的 *migration*（第 2 節）確實只影響 macOS／Linux，
> 但「重跑安裝會在陣列尾端 append 出第二筆 gate」**三平台都會發生**，所以
> [`AI-INSTALL.md`](AI-INSTALL.md) 步驟 2 也會叫 Windows 使用者先跑這支 probe。
> probe 本身是純 Node，三平台同一條指令。

### 1.1 看 hook 現在註冊在哪

**用語意解析，不要用 `grep`。** 全文 `grep` 會命中 `_comment` 裡的說明字、其他 hook 事件、
甚至無效 JSON 裡的殘骸，把受影響的人誤判成正常。下面這支直接解析
`hooks.PreToolUse[].hooks[].command`（`node` 是 hook 本身的前置，一定有）：

```
cd <你 clone 的 Codex-for-CC>
node tools/probe-gate-registration.js
```

**三平台同一條指令**（Windows 的 PowerShell、macOS／Linux 的 bash 都照抄）。
它是唯讀的，不會改任何檔案。

> 這支 probe 住在**本 repo 的 checkout 裡**（安裝時不會被複製到 `~/.claude/`）。
> 手邊沒有 checkout 就重新 clone 一份——你當初就是從它安裝的，而且 probe 唯讀，
> clone 下來只為了跑它不會有任何副作用。
> 它先前是內嵌在本節的 bash heredoc，那形態在 Windows 的 PowerShell 跑不動，
> 也沒有任何回歸案守著，2026-08-08 抽出來。

先看**退出碼**：

| 退出碼 | 意義 | 該做什麼 |
|---|---|---|
| **0** | 判定可執行 | 照它印出的「判定：」那行做 |
| **1** | 讀不到或形狀不合 | **先修好再重跑，不要往下做** |
| **3** | 停手 | 需要人工判斷，本文件涵蓋不了——請開 issue |

> ⛔ **不要照筆數自己推規則。** 下面的判定表只是對照用，**唯一的真相是 probe 印出來的那行**。
> 2026-08-08 的合併前審查抓到過：只要有地方自己摘要成「已經有一筆就不要再加」，
> 就會漏掉「那一筆只在 `settings.local.json`」——那份不是 user scope，gate 等於沒生效。

判定表（`exit 0` 時的對應關係）：

| `settings.json` | `settings.local.json` | 判定 | 去第 2 節的哪一支 |
|---|---|---|---|
| **1** | 0 | **正常**，不用往下做 | — |
| **≥2** | 任意 | **已經重複註冊**（多半是重跑安裝 append 出來的）| **B** |
| 1 | ≥1 | 兩邊都有 —— **只從 `settings.local.json` 移除，不要搬** | **B** |
| 0 | ≥1 | **受影響**：gate 只在 local，從非家目錄啟動完全不生效 | **A** |
| 0 | 0 | 可能還沒安裝，或註冊在別處——照 `AI-INSTALL` 步驟 2 重做 | — |

> **為什麼「≥1／0」要拆成「1」與「≥2」**：舊版把兩者都算「正常」，於是
> `settings.json` 裡有兩筆重複 gate 時會被判成不用修。而重複註冊正是
> 「照著安裝指引再跑一次」最容易產生的狀態。

`exit 3`（停手）的**條件寫在 probe 裡，本文件刻意不複述**——它會直接印出命中的是哪一條
（判定依據是**兩個檔的聯集**，不是只看 `settings.json`）。

> ⚠️ **probe 只驗「註冊的形狀」。** 它**不驗** `command`／`args` 指到的檔案是否還存在，
> 也不驗 hook 真的會被叫起。所以「判定：正常」不等於「gate 一定會生效」——
> 決定性的驗證是第 3.2 節。

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

> **哪一支適用哪個平台。** 本文件開頭說「只影響 macOS／Linux」講的是 **A**
> （gate 只註冊在 `settings.local.json`）——那確實是 POSIX 專屬的歷史問題。
> 但 **B（重複註冊）三平台都會發生**，Windows 使用者也會被
> [`AI-INSTALL.md`](AI-INSTALL.md) 步驟 2 導到這裡。2.2 是手動編輯 JSON，本來就與平台無關；
> 2.1 的備份見下方各平台指引。

### 2.1 先備份

```
cd <你 clone 的 Codex-for-CC>
node tools/backup-settings.js
```

**三平台同一條指令。** 它會備份 `~/.claude/settings.json` 與 `~/.claude/settings.local.json`
（不存在的略過），檔名加 `.bak-<時間戳>`。

> 這支是 **fail-fast** 的：任何一步失敗就中止並回非 0，**不會印出 `backup ts=`**。
> 所以「有印出 `ts`」才等於「該備份的都完成且逐位元組比對過」。
> 它**先全部預檢、再全部複製**，讓大部分的失敗在還沒動手之前就被攔下；
> 複製階段若失敗，它會**盡力**回收本次登記過的備份並如實印出結果。
>
> ⚠️ **「中止時什麼都不會留下」是 best-effort，不是保證**，而且它**不是交易式的**：
> 預檢到複製之間若有人換掉來源檔、或建立了預檢時還不存在的 settings 檔，它不會察覺
> （唯一真的關掉的 race 是目的檔撞名）。它假設你在自己的機器上手動操作、
> 沒有並行的安裝程序。完整範圍寫在
> [`tools/backup-settings.js`](../tools/backup-settings.js) 的檔頭。
>
> **為什麼是 Node 而不是 bash ＋ PowerShell 兩份**：第 2 節的 **B 分支三平台都會用到**，
> 而 B 會**刪除** `settings.local.json` 裡的 gate handler。先前這裡只有 bash 版，
> Windows 使用者曾被導去用 `AI-INSTALL` 步驟 1b —— 但 1b 是「安裝前的三件式備份」，
> 它**只備 `settings.json`**，正好漏掉 B 真正會刪的那個檔。
> 同一段備份邏輯寫成兩份 shell 版本則遲早演化到不一致。
> 回歸案：[`tests/backup-settings.test.js`](../tests/backup-settings.test.js)。

### 2.2 手動修正（**刻意不提供自動腳本**，理由見下）

> **粒度是「handler」不是「整個條目」。** `hooks.PreToolUse` 的一個 outer entry
> 底下可以掛**多個** handler，那些 handler 可能與本 skill 無關。
> 舊版叫你搬「整個條目」，於是：outer entry 還掛著別的 hook 時，
> 搬過去會把不相關的 hook 一併升到 user scope，刪掉則會把它們一併移除。
>
> **先數清楚再動手。** 「跑 `super-mode-consult-gate` 的 **handler**」在兩個檔各有幾個？
> 第 1 節的 probe 印的就是這個數字（它只判斷 shell form；exec form 會直接叫你停手）。
>
> ⚠️ **probe 退出碼 3 ＝ 停手**：本文件涵蓋不了，請開 issue 或人工判斷。
> **停手條件由 probe 機械判定，本文件刻意不再抄一份**——上一次同一條規則寫兩遍，
> 兩份副本就演化到不一致，導致「照唯一真相操作會刪掉使用者僅存的 gate」。

**先跑第 1 節的 probe，照它指的 A 或 B 做。**

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

（`command` 保留你原本的絕對路徑，不要改——**除非那個路徑指到的檔案已經不存在**，見 3.2）：

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

**重跑第 1 節的 probe 就是在驗這件事**：它印「判定：正常，不用修。」且**退出碼為 0**
才算完成。任何其他判定都代表還沒做完——特別是「已經重複註冊」。

> **為什麼不給自動腳本？** 這個 repo 在 2026-07-27 花了九輪對抗審查才學到：
> **把「搬移＋刪除」這種會動使用者檔案的狀態機寫成複製貼上的 markdown，
> 每補一個洞就多一層沒有測試守著的分支。** 這件事的正確位置是
> [`installer-rewrite-spec.md`](installer-rewrite-spec.md) 規劃中的安裝器
> （D6 settings semantic patch），那裡有測試臺與 conflict 處理。
> 在它做好之前，手動編輯兩個小 JSON 比一段沒測過的腳本安全。

---

## 3. 驗證

> **完成判準＝第 2 節的後置條件（probe 印「判定：正常，不用修。」且 exit 0）＋ 下面的 3.2。**
> 3.1 是**補充**，不是必要條件——它跑的是你已安裝的那份 verifier，對本文件的讀者不可靠，
> 理由見 3.1 開頭的 ⛔。（2026-08-08 以前這裡寫「兩步都要做」，那對「verifier 根本不存在」
> 的機器來說是無法完成的流程。）

### 3.1 靜態：matcher 是否真的合併進去了

> ⛔ **這一節對「2026-07-28 以前安裝」的人不可靠——也就是對本文件的讀者不可靠。**
> 它跑的是**你已安裝**的那份 verifier，而那份有兩種壞法，2026-08-08 的兩台真機取樣各命中一種：
>
> - **舊版會假綠**：候選清單裡還有 `settings.local.json`，gate 只註冊在 local 時它照樣 PASS。
> - **根本不存在**：有的機器 `~/.claude/skills/超級模式/tests/` 裡沒有這個檔——因為舊指引
>   那條「★ 必跑」在該機器上從沒成功跑過，執行會直接 module-not-found。
>
> **所以本次修訂的完成判準是 2.2 的後置條件（＝第 1 節 probe 印「正常，不用修。」且 exit 0）
> ＋ 下面的 3.2 端到端觸發。** 本節當補充看，不要拿它當唯一驗收。

**用 checkout 裡的 verifier 加 `--live`，不要跑你已安裝的那一份**（理由就是上面的 ⛔）。
`--live` 明確指定「驗 `~/.claude/settings.json` ＋ `~/.claude/hooks/super-mode-consult-gate.js`」，
所以從 checkout 執行也驗得到 live。在 Codex-for-CC 的 checkout 根目錄跑（`macos` 換成你的平台）：

```bash
node "macos/skills/超級模式/tests/matcher-contract.test.js" --live; echo "exit=$?"
```

它會先印出**實際受驗的兩條路徑**，請核對它們指向你的家目錄。

- `exit=0` → matcher 與 hook 的工具清單一致
- `exit=1` → 看它印的 `RESULT_CODE=`：
  - `NO_GATE` → 第 2 節沒做成功，回去檢查
  - `BAD_TYPE` → handler 的 `type` 不是 `command`（合法值有 `command`／`http`／`mcp_tool`／
    `prompt`／`agent`，**只有 `command` 會執行 `command` 欄位**）
  - `UNSAFE_FIELD` → handler 帶 `if`／`async`／`asyncRewake`，gate 不會如預期阻擋
    （**不含 `once`**：官方明訂它在 settings 檔會被忽略，擋它是誤紅）
  - `HOOKS_DISABLED` → 該檔設了 `disableAllHooks: true`，**所有 hook 都被停用**
  - `AMBIGUOUS_MATCHER`／`SHAPE_ERROR`／`UNSUPPORTED_EXEC_FORM` → 照訊息處理，
    多筆或衝突的情況以第 1 節的 probe 為準
- `exit=2` → 參數用錯，照它印的用法改

> **為什麼一定要用 checkout 那份**：2026-08-08 兩台真機取樣顯示，已安裝的 verifier
> 要嘛是**會假綠的舊版**（候選清單含 `settings.local.json`），要嘛**根本不存在**。
> 更關鍵的是實測結果：**舊版收到 `--live` 會靜默忽略、照樣 PASS**——
> 所以「跑已安裝那份並加旗標」不但沒有解決問題，還會給你一個看起來更可信的綠燈。
> repo 內的版本已移除該候選與 `|| candidates[0]` fallback，並在 2026-08-09 起
> 把 gate 辨識收斂到與 probe 共用的單一模組。

### 3.2 端到端：真的會被叫起嗎

靜態測試**不能**證明 hook 會被叫起（它只比對兩份檔案的字串）。唯一的確認方式：

1. `cd` 到一個**不是家目錄**的地方（這很重要——從家目錄啟動會讓舊設定也生效，測不出差別）
2. 開一個**新的** Claude Code session（hook 設定變更下個 session 才生效）
3. 開啟超級模式，在**沒有憑證**的狀態下試一個會被攔的動作
4. 應該要被 deny

沒被 deny → hook 沒接上。**先確認 `command`／`args` 指到的檔案真的存在**：
第 1 節的 probe 會把註冊的路徑印出來，但它**只驗註冊的形狀、不驗那個路徑還在不在**。
路徑不存在（家目錄搬過、當初就填錯、或 hook 被刪掉）時 probe 會一直印「正常，不用修。」
——就註冊形狀而言它確實正常。這種情況直接把 `command`／`args` 改成正確的絕對路徑，
再重跑本節。路徑沒問題才回到 2.2 檢查合併結果。

---

## 4. 如果你的 `~/.claude/settings.json` 會被別的工具覆寫

這個檔**不是只有你在寫**：任何安裝器、設定同步或 promote 工具都可能改它，
而且 **Claude Code 自己的 plugin manager 就是同一個檔的寫入者**
（該檔的 top-level key 除了 `hooks` 還有 `enabledPlugins`，2026-08-08 實查）。

> ⚠️ 上述只證明「有其他寫入者」。**目前沒有證據顯示有哪個工具會覆寫或移除 `hooks` 段**——
> 本節先前具名 ECC 並斷言「這是真實的衝突」，那個斷言的證據不足，已於 2026-08-08 撤下。
> 別把舊斷言換成一個對 plugin manager 的新斷言。

舊版指引選 `settings.local.json` 正是為了躲這件事。但躲進一個**不會被載入的檔案**不能算解法，
只是讓問題從「被覆寫」變成「從來沒生效」。

現階段的做法：**任何可能改動該檔的動作之後，重跑 3.1**。它現在找不到已註冊的 hook 會直接 FAIL，
不會再靜默通過，所以你至少會知道要重補。

長期做法記在 [`installer-rewrite-spec.md`](installer-rewrite-spec.md)：
安裝器會做 entry-level 的 semantic patch，並在寫入前重新比對整檔雜湊，
避免蓋掉別的工具同期做的修改。

---

## 5. 收尾

確認**第 2 節的後置條件**（probe 印「判定：正常，不用修。」且 exit 0）與 **3.2** 都過之後，
2.1 產生的備份可以自行刪除：

```bash
ls -la ~/.claude/settings*.json.bak-*
```

（確認無誤再刪。這些檔可能含環境變數、API 端點等設定，比一般垃圾檔敏感。）
