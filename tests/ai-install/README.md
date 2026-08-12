# `docs/AI-INSTALL.md` 的安裝流程測試臺

驗證 [`docs/AI-INSTALL.md`](../../docs/AI-INSTALL.md) 步驟 1b（備份）、1c（安裝）、
步驟 3（回滾）的 code block 真的具備文件所聲稱的性質。

**做法**：程式化抽出文件裡的 code block（依 powershell / bash fence 標記，以內容關鍵字
定位）→ 用**假 `USERPROFILE`／`HOME`** 執行 → 檢查檔案系統狀態。測的是**文件本身**，
不是另一份複製品——文件改了，測試就跟著測新版。

## 執行

```powershell
pwsh       -File .\tests\ai-install\run-windows.ps1                    # PowerShell 7
powershell -File .\tests\ai-install\run-windows.ps1 -Shell powershell  # Windows PowerShell 5.1
```

```bash
bash tests/ai-install/run-posix.sh
```

兩者都在**全部通過時 exit 0**，任何一案失敗即 exit 1。

⚠️ **`-Shell powershell`（5.1）先前跑不完，2026-08-12 才修好。**
5.1 會把 native command 寫到 stderr 的輸出包成 `NativeCommandError` 的 ErrorRecord，
撞上本檔開頭的 `$ErrorActionPreference = 'Stop'` 就讓**整個測試臺**當場中止（7.x 不會）。
實測連未改動的 `ad8ff12` 也一樣：一路綠到 `[M1]` 第一個「被拒」案就停，
因為那是第一個會寫 stderr 的子行程。**所以在那之前，Windows 側實際只有 pwsh 一個 host 有覆蓋**
——README 宣傳兩種跑法，但第二種跑不完。已在 `Invoke-Block` 內以**函式作用域**
降級為 `Continue` 修掉（離開函式自動還原，其餘斷言的 Stop 語義不變）；
子行程的成敗本來就一律以 `$LASTEXITCODE` 判斷，不該由 host 的錯誤串流決定。

同一次順帶硬化了 `Invoke-Block` 的兩個既有弱點（合併前 Codex 審查指出，**已復現**）：

- **host 未先解析**：executable 不存在時 `& $exe` **不會設定 `$LASTEXITCODE`**，
  上一次成功留下的 `0` 會被沿用 →「找不到 host 卻判定成功」。
  兩個 host 實測皆然（先跑 `cmd /c exit 0`、再呼叫不存在的 exe，`rc` 仍是 `0`）。
  現行寫法最後是靠 `$out` 為 null、`.Trim()` 再爆掉才變紅——那是**偶然**的誤紅保護，不是結構。
  → 改成啟動時用 `Get-Command -CommandType Application -ErrorAction Stop` 解析成絕對路徑並印出。
- **呼叫前未重設、事後未驗型別** → 改成每次呼叫前 `$global:LASTEXITCODE = $null`、
  事後 `$rc -isnot [int]` 就 throw，並用 `("$out").Trim()` 安全轉字串。
  實測：加了重設之後 `rc` 為 null、型別檢查正確拒絕判定成敗。

⚠️ 摘要行印的是 host **名稱**（`pwsh` / `powershell`）而不是解析後的絕對路徑——
交接文件與反向驗證都在比對那一行。

指定別的文件版本（用途見下方「反向驗證」）：
- Windows：`-Doc <path>`
- POSIX：`--doc <path>`，或環境變數 `DOC=<path>`

⚠️ **POSIX 版的 `--doc` 是 2026-08-10 才加的**（在那之前**完全沒有參數解析**，
傳 `--doc` 會被靜默忽略、改測 repo 自己的文件 → 反向驗證印全綠卻什麼都沒量到）。
現在未知參數／位置參數／缺值／**空字串**／重複 `--doc`／檔案不存在一律 **exit 2**；
`DOC=` 與 `--doc` 指到不同檔案視為歧義，直接拒絕。
空字串之所以也拒絕：`--doc "$D/f"` 在 `$D` 未設時會展開成 `--doc ""`，
若退回預設就會產生一次「看起來全綠、其實測錯檔案」的假綠。
這些規則由 [`run-posix-args.test.sh`](run-posix-args.test.sh) 守著（已進 Linux CI）。

**跑完請看輸出開頭的「受測文件：」與「文件 hash：」兩行**——
那是「目標到底有沒有換掉」的唯一證據，只比 `PASS=`／`FAIL=` 數字看不出來。

## 為什麼有變異注入

正常路徑走不到「驗證失敗」那些分支——不注入等於沒驗。所以測試臺會主動製造故障：
把備份換成別的型別、換成 link、竄改安裝結果、用壞掉的 `ts`、讓備份與 `.absent` 並存等。

**每個注入點都有自我檢查**：注入用的錨點字串若因文件改寫而失效，該案會明確 FAIL
（`變異確實注入（否則本案等於沒測）`），不會靜默變成假通過。

### POSIX 的 `[M13]`／`[M13b]`／`[M13c]`（2026-08-12 補齊，與 Windows 對等）

POSIX 側 2026-08-10 就有 `[M13]`（`chmod 000` 注入），但它**只快照 `.claude/skills`**——
與 Windows 第一版同型的窄 oracle。2026-08-12 補齊：

- `[M13]` 兩變體各多比一份**整個假 HOME** 的快照。
- `[M13c]`：把回滾裡**既有的**還原兩行**原樣搬到**第一個 `scan_no_link` 之前，
  **hook 與 settings 兩個目標各跑一次**。
  搬移（而不是另外注入一行）是最強的證據形式——產物就是產品自己的程式碼，只是順序錯了。
  同時斷言「窄 oracle 看不到」＋「寬 oracle 抓得到」，兩條一起看才知道加寬買到了什麼。
  **四條在 Linux 都 PASS ⇒ 缺口與修法都被實證。**
- **`simulate_step2`**：M13／M13c 在快照前模擬安裝步驟 2 改動 settings。
  ⚠️ **沒有這一步，settings 型的違規看不見**——`seed` 寫的 settings 與 1b 的備份一模一樣
  （1c 不碰 settings），把 settings 還原搬到預掃前只是 `OLD → OLD`、內容雜湊不變、mutant 存活。
  C1／C2 早就有這個手法（註解寫「否則還原斷言恆真」），**M13 當初漏了**。
  Windows 側同型、同日一起修。這是「oracle 夠寬，但 fixture 讓它沒東西可看」的例子——
  **加寬 oracle 不等於補上覆蓋**。
- **`run()` 清掉 `BASH_ENV`／`ENV`、釘 `HISTFILE=/dev/null`**：非互動 bash（含 3.2）會 source
  `$BASH_ENV`。繼承進來的 startup 檔若往假 HOME 寫東西，寬 oracle 會**誤紅**，
  M13c 的「有變」還可能被**不相干的側檔冒充**。A／B 實測：修正前在 `BASH_ENV` 下
  兩條寬 oracle 斷言誤紅，修正後 125/0（對現行腳本的等價 A／B 是 `123/2`；
  早期版本記載的 `109/2` 是 `aa74cfa` 的舊案數 111，對現行腳本不可復現）。
  ⚠️ **必須用 `command bash`，不能只清環境變數。** 只清 `BASH_ENV`／`ENV` 而仍以**名稱**
  呼叫 `bash`，父 shell 已載入的 `bash()` 函式照樣攔得到（函式解析優先於 PATH）。
  A／B（父層定義攔截所有 `bash` 的函式）：修正前 **`82/43`、被攔截 29 次**；
  修正後 `125/0`、攔截 **0 次**。清環境是給 child 用的，`command` 才是給這一行用的。

#### `snap` 的演進：三次都錯在同一個地方 —— 想用「值」表達「失敗」

| 版本 | 做法 | 為什麼錯 |
|---|---|---|
| v1 | `find … \| sort`，掃不動就吞掉 | find 的 rc 被 `sort` 蓋掉 → **兩次都掃不動時兩份殘缺快照「相等」**，`=` 斷言假通過 |
| v2 | 失敗回含 `$RANDOM` 的哨兵 | 對 `=` 有效、**對 `!=` 必定成立** → M13b／M13c 的寬 oracle 假綠。**方向性哨兵在雙向 oracle 下必然有一邊假綠** |
| v3 | 失敗回非 0，呼叫點 `\|\| die_snap` | 對，但**只接了 3/16 個呼叫點**；界線「那些樹從不 chmod」不成立——snap 也會因 `readlink`／`cksum`／IO 失敗 |
| **v4（現行）** | **mode 進快照；「讀不到」記成 `UNREADABLE`／`UNREADABLE-DIR`；16 個呼叫點全接 `\|\| die_snap`** | — |

**v4 的關鍵是：不可讀是一種觀測值，不是錯誤。** 資訊不再遺失，比較在兩個方向都成立，
也不需要在快照前動任何權限。

⚠️ **順帶刪掉了 `unlock_tree`**（v3 時為了讓後置快照掃得動而加的 `chmod -R u+rwX` 整個假 HOME）。
在「快照不記 mode」的前提下，它等於**主動銷毀證據**：產品若在中止前 `chmod 000 "$setf"`
（已違反契約），正規化後快照相同 → `125/0` 假綠。
**我當時的論證是「snap 不記 mode，所以正規化不影響比對內容」——正好講反了。**
A／B 實測：舊版對該 mutant `125/0`（存活），新版 `123/2`（抓到，紅的正是兩條寬 oracle）。
權限正規化改到 `cleanup` trap 裡，**在所有斷言之後**。

⚠️ **BEFORE 快照要在 `chmod 000` 之後取**：我們自己的注入也會改 mode，
在 chmod 前取會把它算成違規（實測 3 條假紅）。chmod 後取則兩邊都看到同一個
`UNREADABLE-DIR` 紀錄，而**產品**的 mode 違規仍然看得見。

⚠️ **`cksum` 的錯誤要先取整行再切欄**：`ck=$(cksum < "$p" | cut …) || exit 1` 在內層 `sh -c`
只看得到 `cut` 的狀態（父層的 `pipefail` 不會傳進去）。
A／B：讓 `cksum` 一律 exit 9 → 舊版 `125/0`，新版 rc 2。

⚠️ **平台不對稱（已知，未做）**：POSIX 的快照記 mode，Windows 的 `Get-Snapshot`
記內容雜湊與 reparse 旗標但**不記 ACL** —— 所以純 ACL 型的違規在 Windows 側看不到。
記進 backlog，不假裝兩邊等價。
- **搬移的自我檢查必須包含相鄰性與 `bash -n`**：awk 只丟掉 L1／L2 兩行，
  若日後有人在兩行之間插入 `elif`，中間那些行會留在原處 → 產出**語法壞掉**的區塊；
  而 locked scan 會先 `exit 1`，bash 根本還沒讀到尾端的語法錯誤，於是三條斷言**全部照樣綠**。
  （合併前 Codex 審查用同形狀 awk 實跑出 `bash_n_rc=2` 但 `runtime_rc=7`。）
- `[M13b]`：把 `scan_no_link` 裡「掃描失敗 → 中止」那一行換成把錯誤吞掉，斷言 live 確實被動過。
  ⚠️ POSIX 的保護有**兩層**（顯式 rc 檢查 ＋ 區塊開頭的 `set -e`），與 Windows 只靠一行
  `$ErrorActionPreference = 'Stop'` 不同。本變異拆掉的是顯式那層——
  `set -e` 對 `if ! cmd; then` 的**條件式**本來就不生效，所以擋不住這個變異。
- 注入自我檢查改成 **chmod 前必須掃得動、chmod 後必須掃不動**。
  舊寫法只驗「chmod 後 `find` 非零」，但 `$ROOT` 算錯時 `find` 一樣非零 →
  「注入生效」通過、回滾又因不相干的理由中止、live 剛好沒被動 → **整案假綠**。前後對照才證明得了因果。
- 錨點比對一律用 `grep -cxF`／`grep -nxF`（**整行**精確比對）。
  Windows 側在同一批用子字串比對連續踩了兩次坑（見下），整行比對從源頭避開。
- ⚠️ POSIX 這側**不必**像 Windows 把探針送進 child 行程：產品跑在同 uid 的 `bash` 子行程、
  用的是同一支 `find`，沒有 parent／child 的 host 不對稱問題。

### Windows 的 `[M13]`：怎麼讓列舉**真的**失敗（2026-08-12）

「列舉失敗必須在任何 mutation 之前中止」是回滾的**資料安全契約**：掃不動時若 fail-open，
就會先刪 live、再從一棵沒驗證過的樹還原。POSIX 側 2026-08-10 就有動態案（`chmod 000`），
Windows 側在那之前只有 `$ErrorActionPreference = 'Stop'` 的**靜態推論**。

注入手法是**對自己下 Deny ACE**：目錄的擁有者即使沒有管理員權限也隱含保有 `WRITE_DAC`，
所以「拒絕自己 `ListDirectory`」以及事後把它拿掉都做得到，不需要提權。實測本機 non-elevated，
`pwsh 7.6.3` 與 `Windows PowerShell 5.1.26100` 都拋 `UnauthorizedAccessException`；
**同一段拿掉 `Stop` 則只記 1 筆非終止錯誤、列舉「完成」**——那正是 fail-open 的樣子。

⚠️ **不要照抄 POSIX 的 root 前置守衛。** 那邊必須先擋 root，是因為 root 會忽略權限位元、
讓 `chmod 000` 整個失效；Windows 這邊 Deny ACE 在存取檢查裡優先於 Allow，
提權本身並不會讓注入失效（`Get-ChildItem` 不會去用 `SeBackupPrivilege`）。
真正會讓它失效的是「檔案系統不支援 ACL」「行程啟用了備份權限」這類情況，
而那些**無法可靠地前置偵測**——所以改由「注入自我檢查」當唯一權威：
注入沒生效就直接 FAIL，不給綠燈、也不靜默跳過（本測試臺沒有 SKIP 機制，
加一個會改動結尾 `PASS=`／`FAIL=` 摘要行的契約，而交接文件與反向驗證都靠那一行）。

⚠️ **注入自我檢查跑在受測 host 的 child 行程裡，不是 parent。** 自檢跑在 parent host、
產品跑在 `$exe` child，兩者不保證同一個 host（`-Shell powershell` 時 parent 仍可能是 pwsh），
token 與 provider 行為不能當成邏輯上相同。所以探針是送進 `Invoke-Block` 執行。

探針印的是 `ENUM=FAIL TYPE=<例外型別>`，斷言**釘死 `UnauthorizedAccessException`**。
只認「有沒有拋錯」的話，任何不相干的錯誤（路徑打錯、暫存目錄被清掉…）都能冒充成
「Deny ACE 生效」，本案就變成假通過。兩個 host 實測都是 `UnauthorizedAccessException`。

#### oracle 的範圍：整個假家目錄，不是只有 `.claude\skills`

契約說的是「**任何** mutation 之前中止」。第一版我只快照 `.claude\skills`，
**那是可復現的 surviving mutant**（合併前 Codex 審查抓到）：產品在預掃**之後**才改
hook 與 settings，所以把 hook mutation 搬到預掃前，窄 oracle 會全綠放行。

現在每個變體都比兩份快照：`中止後 live 未變`（skills，訊息清楚）
＋ `中止後整個假家目錄未變（hook／settings 也在內）`（真正對應契約的那條）。

`[M13c]` 是這條加寬的**牙齒測試**：把回滾裡**既有的**還原兩行**原樣搬到**預掃之前，
然後同時斷言**窄 oracle 看不到**（證明缺口真實存在）與**寬 oracle 抓得到**（證明加寬有效）。
兩條要一起看才有意義——少了前者，讀者無從判斷加寬到底買到了什麼。

⚠️ **hook 與 settings 兩個目標各跑一次。** 第一版只做 hook，而且是**注入**一行而非搬移；
第二版改成搬移並補上 settings 目標，理由有二：

1. **settings 型的同契約 mutant 原本測不到**，而且在 `Set-Step2Settings` 之前**根本殺不掉**
   ——`Add-ExistingInstall` 寫的 settings 與 1b 的備份一模一樣（1c 不碰 settings），
   把 settings 還原搬到預掃前只是 `OLD → OLD`、雜湊不變。
   **那是 fixture 的盲點，不是 oracle 的**——加寬 oracle 不等於補上覆蓋。
2. **搬移比注入強**：產物就是產品自己的程式碼，只是順序錯了。
   代價是自我檢查要更嚴：驗來源兩行相鄰、驗產出相鄰且緊貼 anchor、
   再驗**產出仍可解析**（`[scriptblock]::Create`）。少了最後一條，
   日後有人在兩行之間插入東西時，搬移會產出語法壞掉的區塊，
   而回滾可能在讀到錯誤之前就先中止 → 後面三條全部假綠。

⚠️ **這是狀態 oracle，不是事件 oracle。** 快照相等只能證明「最終內容相同」，
**不能**證明「途中從未刪除又還原」。產品目前沒有任何失敗後還原的邏輯，所以狀態比對足以當證據，
但不要把它讀成「證明 mutation 從未開始」。真要那樣宣稱得加 mutation-reached sentinel
或代理所有 `Remove-Item`／`Copy-Item`。

#### `[M13b]`：證明**是哪一行**讓它 fail-closed

把區塊開頭的 `Stop` 改成 `Continue`、其餘完全不動，`拿掉 Stop 後 live 確實被動過` 必須成立。
沒有這一案，日後有人刪掉那行時只會知道 `[M13]` 紅了，不會知道紅在哪裡。

⚠️ 它鎖的是**備份**子樹，不是 live。鎖 live 的話，fail-open 之後的負向訊號要依賴
`Remove-Item -Recurse` 對一棵**部分不可存取**的樹「刪掉一些才失敗」——那是 provider 語義，
日後若改成更早、更原子地拒絕就會誤紅。鎖備份則是：預掃 fail-open → 第一個 mutation
刪除一棵**完全可存取**的 live → 訊號穩定。

#### 案數硬斷言（`EXPECTED_CHECKS`）

結尾會斷言 `PASS + FAIL` 等於一個寫死的常數。**沒有這一條，刪掉任何一個 `Check`
仍會印 `PASS=125 FAIL=0` 並 exit 0**——「少一案」是抓不到的假綠。
這個總數與受測文件**無關**（反向驗證只改變 PASS／FAIL 的分佈，不改變案數），所以是穩定的不變量。
新增或移除案時必須同步更新常數，那是刻意的摩擦。

POSIX 側 2026-08-12 起也有（`EXPECTED_CHECKS_NONROOT=125` / `EXPECTED_CHECKS_ROOT=86`）。
POSIX 需要兩個常數是因為 root 之下 `[M13]`／`[M13b]`／`[M13c]` 整體換成**一條硬失敗**
（root 忽略 `chmod`、注入無效，那時給綠燈等於宣稱驗過一條沒驗到的契約）。
兩個值都實測過：少一案 → `PASS=124 FAIL=0` **但 STOP 觸發、exit 1**；
root 分支（用 PATH 前置的假 `id` 模擬）→ `PASS=85 FAIL=1`＝86，不觸發 STOP。

#### 為什麼 `列舉失敗 → 回滾中止` **沒有**加失敗訊息 signature（考慮過並否決）

「只驗退出碼不夠、要驗失敗原因含指定 signature」是本 repo 的既有教訓，所以我實測量了一輪：

| | 現行版（B1 之後） | `4a96698`（B1 之前） |
|---|---|---|
| 失敗的 cmdlet | `Get-ChildItem`（**預掃**） | `Remove-Item`／`Copy-Item`（**mutation 已經開始**） |
| 輸出含被鎖住的完整路徑 | ✅ | ✅ |
| 輸出含產品自己的 `中止（live 未變更）` | ❌（是未攔截的 .NET 例外） | ❌ |

- **路徑 signature 不具區辨力**：舊版一樣印得出 `…\references\locked`，因為 `Remove-Item`
  自己撞權限時也會把路徑寫進訊息。加了不會在反向驗證變紅，等於裝飾。
- **cmdlet 名稱有區辨力，但會把測試綁死在現行實作上**：日後若改成
  「`try { Get-ChildItem } catch { throw "掃描…中止（live 未變更）" }`」（POSIX 側就是這樣寫的），
  釘 `Get-ChildItem` 的斷言會**誤紅一個更好的實作**。
- 而 `中止後 live 未變` 已經在做同一件區辨，**且與實作無關**——它直接陳述契約本身。

所以維持不加。順帶記下這次量測的副產品，它讓「為什麼這條契約重要」變成具體證據而非理論：
**舊版的失敗來自 `Remove-Item`／`Copy-Item`，也就是 live 已經被動過之後才報錯。**

⚠️ 錨點必須**行首錨定**：區塊裡有一句註解也含 `$ErrorActionPreference = 'Stop'` 這個字面，
`String.Replace` 會連註解一起改掉，就不是「其餘完全不動」的單點變異了。
這與 2026-08-10 那批「散文裡的 `RESULT_CODE=` 被未錨定 oracle 抓走」是同一形狀，
而且是**自我檢查先紅才發現的**，不是事先想到的。所以 `[M13b]` 除了驗錨點唯一＋位在 index 0，
還用 `Compare-Object` 驗「變異只動一行」（差異行數必須恰為 2，一去一回）。

**同一個坑在本批出現三次**，三次都是自我檢查先紅：

1. 上一批：產品**散文**裡的 `RESULT_CODE=` 字面被未錨定 oracle 抓成假標記。
2. `[M13b]`：回滾區塊的**註解**含 `$ErrorActionPreference = 'Stop'` 字面 → `String.Replace` 會連註解一起改。
3. `[M13c]`（**第一版，注入式**）：注入行 `if (Get-Entry $hook) { Remove-Item -LiteralPath $hook -Force }`
   是產品既有的 `elseif (Get-Entry $hook) { … }` 的**子字串** → 直接數會得到 2 次。
   當時的修法是讓注入行帶唯一標記再數標記；**第二版改成搬移之後，
   所有比對都改用整行精確相等（`-ceq` / `grep -cxF`），從源頭避開這一類坑**。

錨點失效時**刻意不跳過**後面的案，改用未變異的區塊讓它們自然變紅。
**這一點是實測過的，不是推論**：把受測文件的回滾區塊第一行縮排一格
（縮排不改變 PowerShell 語義，產品仍 fail-closed，只讓 `(?m)^` 失去命中），
harness 印 **109 PASS／3 FAIL**、**總案數仍為 112**，紅的恰好是那三條 `[M13b]`。
⚠️ 注意這只證明「錨點失效不會**少**案」，**不等於**「案數已釘死」——後者要靠上面的
`EXPECTED_CHECKS`（這個區別是合併前 Codex 審查指出的，我原本把兩件事混為一談）。

## 反向驗證（改動守衛後務必做）

> **定義**：把新寫的回歸測試拿去跑**修正前**的版本，**它必須失敗**。
> 綠色有兩種可能——程式真的修好了，或**這個測試根本測不到那個 bug**；
> 反向驗證就是用來排除後者。相當於 TDD 的 RED 步驟事後補做，
> 也可以看成變異測試的特例（差別在於不必人工改壞程式碼，直接拿真正的舊版本當壞版本）。

新增的回歸案必須對**修正前的版本**失敗，否則它只是裝飾：

```bash
git show <修正前的 commit>:docs/AI-INSTALL.md > /tmp/before.md
DOC=/tmp/before.md bash tests/ai-install/run-posix.sh
```

```powershell
git show <修正前的 commit>:docs/AI-INSTALL.md | Set-Content -LiteralPath $env:TEMP\before.md -Encoding UTF8
.\tests\ai-install\run-windows.ps1 -Doc $env:TEMP\before.md
```

兩者都**應該要 FAIL**。

### ⚠️ 反向驗證的失敗**總數會因平台而異** —— 要逐條核對，不要比總數

2026-08-10 macOS 原生驗收實測：B1 的反向驗證（對 B1 之前的 `4a96698` 文件）
在 **Linux 是 `88 PASS／7 FAIL`，在 macOS 是 `89 PASS／6 FAIL`**。
差的那一條是 `[M13] [live] 列舉失敗 → 回滾中止`。

原因不是 B1 有問題，是**那條斷言本身就不具區辨力**（它只看退出碼）：

| | mode-000 子目錄下的 `rm -rf` |
|---|---|
| GNU（Linux） | 用 `rmdir` 移除得掉 → **exit 0** → 修正前「回滾成功」→ 斷言 FAIL |
| BSD（macOS） | 拒絕進入該目錄 → **exit 1** → 修正前也「回滾中止」→ 斷言意外 PASS |

`run-posix.sh` 的 M13 註解早就寫明「區辨力全在下一條，不在退出碼」。
**真正的判準是 `[live] 中止後 live 未變`** —— 它在兩個平台上都正確地：
修正前 FAIL（`rm` 已經動過 live 才報錯）、B1 之後 PASS（預掃在任何 mutation 之前中止）。
macOS 的同機 A／B 已證實這一點。

**所以驗收條件請釘「具區辨力的斷言名稱」，不要釘總數**：
M11 四條（`[bak]`／`[live]` 各「回滾中止」＋「被拒後 live 未變」）
＋ M13 的「中止後 live 未變」（`[bak]`／`[live]`）必須 FAIL；
`[live] 列舉失敗 → 回滾中止` 是否 FAIL **依平台而定，不列入判準**。

#### ✅ 這個平台差異已於 2026-08-12 消除（成因是 fixture，不是平台）

根因是**被鎖的目錄是空的**：GNU 的 `rm -rf` 能直接 `rmdir` 掉一個空的 mode-000 目錄（exit 0），
BSD 則拒絕進入（exit 1）。現在 `make_locked()` 會在裡面放一個 `payload.txt`，
兩邊的 `rm -rf` 都失敗，那條在兩個平台都 PASS。

順帶讓「掃不動的子樹裡有真實資料」這件事成立——空目錄的注入有可能**被 `rmdir` 掉而自己消失**。

⚠️ 上面那條「總數會因平台而異」的教訓**仍然成立**（釘名稱不要釘總數），
只是這個**特定**的差異已經沒有了。Linux 與 macOS 實測**皆為 `107 PASS／18 FAIL`**
（macOS 2026-08-13 原生驗證完成），見 [`HANDOFF-macos-posix-m13-2026-08-12.md`](../../docs/HANDOFF-macos-posix-m13-2026-08-12.md)。

### POSIX 側對 `4a96698` 的反向驗證（2026-08-12，Linux 實測）

| | 現行文件 | `4a96698` |
|---|---|---|
| Linux（WSL2 ext4、bash 5.x、非 root）| **125 PASS／0 FAIL** exit 0 | **107／18** exit 1 |
| macOS 26.6.1 arm64（系統 bash **3.2.57**、非 root）| **125 PASS／0 FAIL** exit 0 | **107／18** exit 1 |

✅ **macOS 已於 2026-08-13 原生驗證，兩平台逐條相同。**
其中最值得記的是：**2026-08-10 那個「同一條退出碼斷言在兩平台結論相反」的差異確實消失了**
——macOS 的反向驗證從 `89/6` 變成 `107/18`，與 Linux 一致。根因（空的 mode-000 目錄）修對了。

⚠️ 驗證者**沒有只信 B-6／B-7 的綠燈**，而是先證明注入真的有觸發：bash 3.2.57 確實會為
非互動腳本 source `$BASH_ENV`；裸 `bash -n` 確實被劫持（rc=77）而 `command bash -n` 不會（rc=0）；
B-6 的 glob 確實命中 harness 佈局。再於暫存副本上 A／B（拿掉 `run()` 的環境清理）得到 `123/2`，
紅的恰好是兩條 `中止後整個假 HOME 未變`。**「綠燈可能是因為注入沒生效」是這個測試臺最該防的假綠，
這次的驗證方式正好示範了該怎麼排除它。**

失敗的**十八條**：M11 四條 ＋ M13 四條快照（`中止後 live 未變`／`中止後整個假 HOME 未變`
× `[bak]`／`[live]`）＋ `[M13b]` 兩條錨點／注入
＋ `[M13c]` **八條**（hook／settings 各四：`來源錨點`／`產出`／`回滾仍中止…原因`／`窄 oracle 看不到`）。
逐條清單見 handoff §3。M13b／M13c 的錨點在舊版落空是**預期且正確的**——
`4a96698` 根本沒有 `scan_no_link`。

### Windows 側對 `4a96698`（B1 之前）的反向驗證實測（2026-08-12）

| host | 現行文件 | `4a96698` |
|---|---|---|
| `pwsh` 7.6.3 | **126 PASS／0 FAIL** exit 0 | **112／14** exit 1 |
| Windows PowerShell 5.1.26100 | **126 PASS／0 FAIL** exit 0 | **112／14** exit 1 |

失敗的**恰好**是這十四條，兩個 host 逐條相同：

M11（本來就有，4 條）
- `[備份子樹] 回滾中止`、`[備份子樹] 被拒後 live 未變`
- `[live 子樹] 回滾中止`、`[live 子樹] 被拒後 live 未變`

M13（4 條）
- `[M13][備份子樹] 中止後 live 未變`、`[M13][備份子樹] 中止後整個假家目錄未變（hook／settings 也在內）`
- `[M13][live 子樹] 中止後 live 未變`、`[M13][live 子樹] 中止後整個假家目錄未變（hook／settings 也在內）`

M13c（6 條，hook／settings 各 3）
- `[M13c][<目標>] 來源錨點：三串各唯一、兩行相鄰、anchor 是第一個 Assert-NoReparseUnder、且來源在 anchor 之後`
- `[M13c][<目標>] 產出：行數不變、各恰一份、兩行相鄰且緊貼 anchor、且確實與原檔不同`
- `[M13c][<目標>] 窄 oracle（只看 skills）看不到這個違規`

M13c 那些在舊版紅是**預期且正確的**：`4a96698` 根本沒有預掃那一行，所以錨點必然落空，
而未變異的舊區塊會刪掉 live，窄 oracle 也就看得到差異。

⚠️ **Windows 的 `回滾仍中止` 在舊版是 PASS，POSIX 的對應條目卻是 FAIL** ——
因為 POSIX 那條還要求「中止原因是掃描失敗」（釘產品自己的訊息），舊版沒有 `scan_no_link`
所以不可能出現該訊息；Windows 那條只驗非零（沒有產品訊息可釘，見上面的取捨說明）。
這正是「反向驗證的失敗總數會因平台而異」的又一個實例——**釘名稱不要釘總數**。

⚠️ **`[M13][…] 列舉失敗 → 回滾中止` 在舊版照樣 PASS**——舊版沒有預掃，
`Remove-Item`／`Copy-Item` 自己撞權限一樣會非零。這與 POSIX 側的結論一致：
**區辨力全在快照那兩條，不在退出碼**。加 M13 之前的基準是 `86／0` 與 `82／4`，
所以這一批的 delta 是「+26 案、反向驗證 +7 條該紅的」。

Windows 的 M13 斷言名稱一律帶 `[M13]` 前綴：M11 也用 `[備份子樹]`／`[live 子樹]`，
不加前綴的話「前置：1b 成功並印出 ts」等名稱會在兩個區塊裡重複，就沒辦法逐條核對
（POSIX 側目前是靠散文加前綴，字串本身仍會重複）。

## 已知界線

- **`run-posix.sh` 已在 Linux（WSL2）與 macOS 實測。**
  2026-07-28 把三處 GNU 專屬寫法移植成可攜（`find -printf` → 在 shell 算型別與相對路徑、
  `md5sum` → POSIX `cksum`、`date -d` → 忙等跨秒）。**BSD userland 已驗證，「可攜」不再是推論**：
  macOS 26.5.2 arm64／內建 `bash 3.2.57(1)-release` 上，`53cbc5f` **59/59**（2026-07-28）、
  分支尖端 `6f7839b` **64/64**（2026-07-31）；反向驗證 `6f7839b` 對 `53cbc5f` 的文件 **5 FAIL**
  （settings-target 那批新斷言）、對 `06adac5` **12 FAIL**（5 + 原本 7 個 symlink 案）。
  **2026-08-04 補驗 `9491719`（注入點 rc + 型別雙重前置檢查）**：macOS 26.6 arm64／
  `bash 3.2.57(1)-release`（`which -a bash` 只有 `/bin/bash`，確認不是 Homebrew 的 5.x）
  **67/67 EXIT=0**。反向驗證改用**變異注入**而非舊版文件（本批動的是測試臺本身，
  舊版沒有這些斷言、跑起來只是案數較少，不會 FAIL）：在 `[M2]` 的 `ln` 之前插一條
  **斷鏈** symlink 佔住目的地 → `ln` 因 EEXIST 回 rc=1、但 `[ -L ]` 仍為真 →
  `前置：symlink 備份確實建立` **FAIL**，而舊斷言「symlink 備份被拒」照樣 PASS
  （總計 66/67 EXIT=1）。這證明區辨性來自 **rc 項本身**，只驗型別會假綠。
  BSD 的 `ln` 訊息是 `ln: <path>: File exists`（GNU 為 `failed to create symbolic link ...`），
  措辭不同但 rc 同為 1，測試臺不 match 訊息字串，故不受影響。
  ⚠️ 佔位**必須用斷鏈** symlink：若用指向現存目錄的有效 symlink，`ln` 會跟隨進去
  在裡面建檔而回 0，隔離不出 rc 項（Linux 上第一次構造即踩此坑）。
  其後 `[M5]` 也補了同型前置檢查，案數增為 **68**，已在同一台 Mac 對 `e1ec53f`
  複跑 **68/68 exit 0**；兩次比對確認 +1 全部落在 `[M5]` —— 本檔共 **13 個具名區塊**
  （`C1`／`C2`／`M1`–`M10`／`C3`），其餘 **12 個**案數逐項相同。
- **抽取靠關鍵字定位**（`backup ts=`／`install OK`／`Test-Exactly1`／`precheck skill`）。
  命中數不等於 1 時直接 abort，不會猜。
- **Windows 快照忽略** `AppData\Local\Microsoft\PowerShell\*`——`pwsh` 自己會在被重導的
  家目錄下建 `StartupProfileData-NonInteractive`，那是測試臺雜訊。其餘整個假家目錄都比對。
- **`run-posix.sh` 抽取時做 `tr -d '\r'`**：Windows 工作目錄的檔可能是 CRLF，會讓
  `set -euo pipefail` 假炸成 `pipefail: invalid option name`。committed blob 依
  [`.gitattributes`](../../.gitattributes) 是 LF，所以這等同真實 Unix checkout。
- **測不到的東西**：NTFS symlink（需管理員權限或開發者模式）、掛載點／bind mount（需 root）。
  這兩項的殘留風險記在 [`docs/backlog.md`](../../docs/backlog.md)。
