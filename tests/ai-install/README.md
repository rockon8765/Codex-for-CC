# `docs/AI-INSTALL.md` 的安裝流程測試臺

驗證 [`docs/AI-INSTALL.md`](../../docs/AI-INSTALL.md) 步驟 0a（Windows 的 Git Bash 前置檢查，只有 Windows 版測）、
1b（備份）、1c（安裝）、步驟 3（回滾）的 code block 真的具備文件所聲稱的性質。

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

`[M13c]` 是這條加寬的**牙齒測試**：製造一個預掃前的 mutation，然後同時斷言
**窄 oracle 看不到**（證明缺口真實存在）與**寬 oracle 抓得到**（證明加寬有效）。
兩條要一起看才有意義——少了前者，讀者無從判斷加寬到底買到了什麼。

⚠️ **現行實作是「搬移」而非「注入一行」，而且跑 hook／settings 兩個目標**
（2026-08-17 `F2` 批；在那之前只有 hook 一個目標、且是注入式）。
搬移＝把產品自己的相鄰兩行原樣移到 anchor 之前，產物就是產品的程式碼、只是順序錯了，
是比注入更強的證據形式。代價是自我檢查要更嚴，見下面「同一個坑」那節。

⚠️ **settings 目標依賴 `Set-Step2Settings` 這個 fixture。** `Add-ExistingInstall` 寫的
`settings.json` 與 1b 的備份完全相同、1c 不碰 settings，所以少了模擬安裝步驟 2 的那一步，
「把 settings 還原搬到預掃前」只是 OLD → OLD，**連寬 oracle 都看不到**。
這是 fixture 的盲點不是 oracle 的——`F2` 修的就是這個。

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

#### mutation control runner（`run-mutation-controls.ps1`）

`run-windows.ps1` 全綠只證明「**沒少跑案**」，不證明每個案子真的做了它宣稱的動作。
所以另有一支 runner 專門證明測試臺**有牙齒**：

```powershell
pwsh -NoProfile -File tests\ai-install\run-mutation-controls.ps1
```

四個 control，**具名失敗集合 ＋ 精確 rc 釘死**、對不上就 exit 1：

| control | 注入 | 預期紅的（逐條釘死） |
|---|---|---|
| 1 | `Set-Step2Settings` 寫入行改 no-op（保留 `Check`） | 四條「前置：settings 已與備份不同」＋ **`[M13c][settings]` 的寬 oracle**；`[M13c][hook]` 的寬 oracle **必須保持綠** |
| 2 | 產品文件的 **hook** 還原兩行搬到首掃前（**緊貼** anchor） | `[M13]` 兩條寬 oracle ＋ `[M13c][hook]` 的兩道守衛；`[M13c][settings]` **必須保持綠** |
| 3 | 刪掉 `[C3]` 一條無副作用的 `Check` | **零條具名失敗** ＋ 案數守衛那行的完整字面（含「實跑 160、預期 161」；2026-10-17 以前是 125／126） |
| 4 | 產品文件的 **settings** 還原兩行搬到首掃前（**緊貼** anchor） | 與 2 對稱；`[M13c][hook]` **必須保持綠** |

⚠️ **不要退回「只比 PASS／FAIL 總數」**。那樣的話「該紅的牙齒變綠 ＋ 不相關的斷言變紅」
是等量交換、總數不變 ⇒ 假綠。這與 repo 早就記載的「案數不變、全綠、mutant 存活」
是同一個病，只是搬到 control 層。**實測過**：讓寬 oracle 恆真、`[C3]` 恆假之後，
control 1 仍是「具名失敗 5 條（預期 5）」——**總數一模一樣**，靠具名集合才抓得到。
（那次 meta-test 只涵蓋 control 1／2，因為它動到的 `[C3]` 正是 control 3 的注入錨點。）

⚠️ **「緊貼」不是廢話**：搬到更早、但仍在首掃前的位置，預期紅的條數**不一樣**
（「產出與原檔確實不同」那條會變成 PASS）。2026-08-15 的驗收只記了數字沒記放法，
結果 `123/3` 與後來的 `122/4` 到現在無法判定誰對。**這支 runner 就是為了根除這個病。**

#### 案數硬斷言（`EXPECTED_CHECKS`）

結尾會斷言 `PASS + FAIL` 等於一個寫死的常數。**沒有這一條，刪掉任何一個 `Check`
仍會印 `PASS=111 FAIL=0` 並 exit 0**——「少一案」是抓不到的假綠。
這個總數與受測文件**無關**（反向驗證只改變 PASS／FAIL 的分佈，不改變案數），所以是穩定的不變量。
新增或移除案時必須同步更新常數，那是刻意的摩擦。

（POSIX 側的 `run-posix.sh` 目前**沒有**這道斷言，已記進 [`docs/backlog.md`](../../docs/backlog.md)。）

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
3. `[M13c]`：**當時的**注入行 `if (Get-Entry $hook) { Remove-Item -LiteralPath $hook -Force }`
   是產品既有的 `elseif (Get-Entry $hook) { … }` 的**子字串** → 直接數會得到 2 次。
   當時的修法是讓注入行帶一個唯一標記（`# M13C-PRE-SCAN-MUTATION`）再數標記。
   ⚠️ **那個標記式實作已經不存在**：`[M13c]` 後來改成**搬移**既有兩行，
   自我檢查也改成「三串各唯一（`-ceq` 整行精確比對）、兩行相鄰、anchor 是第一個
   `Assert-NoReparseUnder`、來源在 anchor 之後」＋「產出行數不變、各恰一份、
   緊貼 anchor、且**與原檔確實不同**」＋「產出仍可 `[scriptblock]::Create`」。
   本節保留這段是因為**坑的形狀**（未錨定／子字串比對）仍然有效，不是因為實作還長那樣。

4. **2026-08-17 `F2` 收尾時同一個坑又出現一次**（第四次）：control 1 要把
   `Set-Step2Settings` 的寫入行改成 no-op，但那行字面在檔案裡有**兩份**——
   `[C1]` 的行內版（未縮排）與函式內（縮排兩格）。錨點沒帶縮排就會同時改掉兩處，
   自我檢查以「命中 2 次」擋下。修法＝錨點帶上換行與縮排。

錨點失效時**刻意不跳過**後面的案，改用未變異的區塊讓它們自然變紅。
**這一點是實測過的，不是推論**：把受測文件的回滾區塊第一行縮排一格
（縮排不改變 PowerShell 語義，產品仍 fail-closed，只讓 `(?m)^` 失去命中），
harness 印 **109 PASS／3 FAIL**、**總案數仍為 112**（**2026-08-12 的量測，當時案數是 112**；
現行案數見 `run-windows.ps1` 的 `$EXPECTED_CHECKS`），紅的恰好是那三條 `[M13b]`。
⚠️ 注意這只證明「錨點失效不會**少**案」，**不等於**「案數已釘死」——後者要靠上面的
`EXPECTED_CHECKS`（這個區別是合併前 Codex 審查指出的，我原本把兩件事混為一談）。

### Windows 的 `[G]`：步驟 0a 的 Git Bash 前置檢查（2026-10-17，`CC-NOBASH-FAILCLOSED`）

0a 先照 Claude Code 2.1.301 的讀碼找出「它會用的那一個 Git Bash」，再對那一個做實際檢查（是檔案、不是 WSL 的位置、
執行 `-c "/usr/bin/uname -s"` 要成功且回 `MINGW…_NT-`／`MSYS_NT-…`、15 秒逾時）；`where.exe` 找到的 git 或目前目錄
經過 reparse point 時判為無法判定。代號三種：`GIT_BASH_MISSING`（找不到）、`GIT_BASH_INVALID`（找到了但不能用）、
`GIT_BASH_UNDECIDABLE`（無法判定）；成功只印恰好一行 `GIT_BASH_OK path=…`。

**怎麼隔離本機**：寫死的兩個位置用字串替換換成假路徑（第一條自檢它在區塊內恰一處）；`PATH`、
`CLAUDE_CODE_GIT_BASH_PATH` 每案明設或明刪；部分案另外切換目前目錄（子行程繼承它）。所以結果與跑測試的機器
有沒有裝 Git 無關——CI runner 與維護機都有 Git，不隔離的話「找不到」那幾條分支永遠測不到。

**假 bash.exe**：正向案**不再**用內容為 `FAKE` 的檔案（那只能證明「存在」）。測試臺當場用 .NET Framework 內建的
`csc.exe` 編一支小程式：回應旁邊 `<exe>.reply` 的內容（`HANG`＝睡 10 分鐘；`RC1:<文字>`＝印文字並以 1 結束），
並把收到的參數附加到 `<exe>.args`。所以「通過」的案是真的執行了一支回 MINGW 的程式，而且可以斷言「探測恰好執行一次、
參數是 `-c|/usr/bin/uname -s`」，以及 `WindowsApps\bash.exe`「根本沒有被執行」。**產品區塊沒有任何只為測試存在的開關**：
注入全在測試臺這一側（改寫抽出來的區塊文字、環境變數、目前目錄、檔案系統）。編譯或自我執行失敗時那條前置會紅，
後面的正向案自然變紅，不跳過（案數固定）。

**判準**：「停止」＝退出碼非 0、沒有任何一行以 `GIT_BASH_OK path=` 開頭、含預期代號、且**不含另外兩個代號**；
「通過」＝退出碼 0、**恰好一行** `GIT_BASH_OK path=<預期路徑>`（路徑不分大小寫比對）。
8.3 短檔名：GitHub runner 的 `$env:TEMP` 是 `C:\Users\RUNNER~1\…`，而 `where.exe` 回長檔名，所以假目錄的根先換成長檔名。

23 條：3 條前置／自檢（替換錨點恰一處、假 bash 可執行、兩個 junction 建成）＋ 20 個行為案——
什麼都沒有、PATH 上只有 WSL 的 bash、環境變數可用／檔名不對／不存在、兩個寫死位置、`where.exe` 的 git 可用／旁邊沒有 bash／
只看第一個／在目前目錄底下被排除、環境變數指向目錄／文字檔／回 Linux 的 bash／`WindowsApps\bash.exe`／退出碼非 0／卡住
（另釘耗時 < 90 秒，否則「沒有逾時、一直等到假 bash 自己結束」的寫法也會綠）、第一個寫死位置是目錄而第二個可用
（Claude Code 不改試，所以要判不可用）、git 經過 junction、目前目錄經過 junction。

**牙齒（2026-10-17 本機實測）**：
- 修正前文件（`040b344`）：兩個 host 都在抽取時中止，`抽取失敗：'GIT_BASH_OK' 命中 0 個區塊（預期 1）`，exit 1。
- 把 0a 換回設計原型（只檢查「存在」、不執行、不判 reparse）：兩個 host 都是 `151／10` exit 1，紅的**恰好**是 10 條——
  環境變數可用（沒執行探測）、目錄、文字檔、回 Linux、`WindowsApps`、退出碼非 0、卡住、第一個寫死位置是目錄、
  git 經過 junction、目前目錄經過 junction。
- 單點變異（pwsh，各自 `160／1`，紅的恰好是預期那一條）：拿掉 WSL 位置規則 → `WindowsApps`；拿掉退出碼檢查 → 退出碼非 0；
  拿掉 uname 輸出比對 → 回 Linux；拿掉目前目錄的 reparse 判定 → 目前目錄經過 junction；拿掉 git 的 reparse 判定 →
  git 經過 junction；逾時從 15 秒改成 700 秒 → 卡住那條（耗時 655 秒才結束，被「< 90 秒」擋下）。
- 已知的等價變異：拿掉「是目錄」那道檢查不會被殺——目錄餵給 `Process.Start` 一樣啟動失敗、一樣判 `GIT_BASH_INVALID`。
  保留它是為了訊息清楚，不是為了區辨力。

⚠️ Claude Code 2.1.299「沒有 Git Bash 就擋下」本身**沒有 live 重現**（維護者只有一台裝了 Git 的 Windows）；
本節只證明 0a 的判斷邏輯。找法照抄讀碼，上游改版就可能分歧。

### `[M14]`–`[M20]`、`[C4]`（POSIX）與 Windows 的 `[M18]`：掛載點守衛（2026-10-17，F4 `MOUNT-RMRF`）

macOS 區塊的 `scan_no_mount` 以裝置號（st_dev）判斷掛載點，1b、1c 的第一個 mutation 前、回滾的 `rm -rf` 前各一份，
三份逐字相同（`[M17]` 比對）。判定只用 `stat %d`（一個目錄一行），路徑只在偵測到之後另外取，當診斷訊息。

**假 stat**：CI 與 Windows 上建不出 macOS 掛載點，所以 `run-posix.sh` 用 PATH 前置的假 `stat`（`SHIM_ON=1` 的案才經過它，
其餘案的執行環境不變）：路徑本身或任一上層有 `.fake-mount-dev` 就回報那個裝置號（掛載點連同底下都是新裝置號）、
目錄有 `.fake-stat-fail` 就讓該路徑 stat 失敗，其餘原樣交給真的 stat——所以受測區塊的 GNU／BSD 語法偵測看到的是真的。
**這只證明控制流**；「macOS 掛載點的 st_dev 真的與上一層不同」與 macOS 真機行為，2026-10-18 另以 hdiutil 拋棄式
APFS image 在真機驗過（結果見下方「Mac 真機驗證」）。

| 區塊 | 情境 | 條數 |
|---|---|---|
| `[M14]` | 1b 時子樹已有掛載點 → 中止、不印 ts、理由、不建 skill 備份 | 5 |
| `[M15]` | 回滾時 1b 之後才掛上（sub／root）→ 中止、理由、整個 `~/.claude` 不變、掛載內 payload 仍在 | 16 |
| `[M16]` | 回滾時裝置號讀不到（sub 走 `find -exec`、root 走單一 stat）→ fail-closed | 14 |
| `[M17]` | 1b、1c、回滾三份守衛逐字相同 | 1 |
| `[M18]` | 1c 前才掛上（sub＝`references` 本身是掛載點、root＝skill 根目錄）→ 第一個 mutation 前中止、整個 `~/.claude` 與掛載內容都不變 | 12 |
| `[M19]` | 1c 前才出現的 symlink（sub／root）→ 中止、不寫穿（與 Windows 1c 的 reparse 掃描等價） | 10 |
| `[M20]` | 目錄名含換行、同一裝置（真的 stat）→ 1b、1c、回滾照常通過 | 5 |
| `[C4]` | 經過假 stat 但不注入 → 安裝、回滾都成功（假 stat 是透明的） | 4 |

`run-posix.sh` 總案數 95 → 162。Windows 的 `[M18]`（12 條）用 junction 對應：它與 NTFS 掛載資料夾同為
`IO_REPARSE_TAG_MOUNT_POINT`，偵測走同一個 `ReparsePoint` 屬性（真的掛載資料夾要系統管理員權限才建得出來，推論覆蓋）。

**本機（Windows 11 的 Git Bash：bash 5.3 cygwin 版、GNU coreutils 8.32）2026-10-17 實測**：
- 現行文件：`bash  PASS=126  FAIL=36`。36＝原本的 30 條天花板（建不出 symlink、`chmod 000` 無效）＋ `[M19]` 6 條
  （同樣因為建不出 symlink：前置、1c 中止、`~/.claude` 未變各兩條）。既有 95 條的 PASS／FAIL 逐條與改動前相同（只差時間戳與 `[M8]` 的跨秒分支）。
  Mac／Linux 上預期 `162／0`（Linux CI 的 `run-posix-args.test.sh` 會跑到）；2026-10-18 Mac 真機實測 `162／0`。
- 修正前文件（`040b344`）：`99／63`，比現行多紅的**恰好** 27 條：`[M14]` 4、`[M15]` 8、`[M16]` 6、`[M17]` 1、`[M18]` 8。
  （2026-10-18 Mac 真機：`134／28`，比 Git Bash 的 27 條多出 `[M19][sub]`「中止後整個 `~/.claude` 未變」1 條；
  `[M19]` 其餘 5 條在修正前文件也是 PASS。）
- 三份守衛都換回設計原型的判準（`%d %n` 同一行再用 awk 切欄位）：多紅**恰好** 3 條＝`[M20]` 的 1b、1c、回滾
  ——名稱含換行的目錄被拆成兩行，後半行被當成「裝置號不同」而誤擋。這是 Codex 反方 C.2 的牙齒。
- 只刪 1c 的那一行 `scan_no_mount` 呼叫：多紅**恰好** 8 條＝`[M18]`（Codex 反方 C.1 的牙齒）。
- Windows：1c 拿掉重掃 → 兩個 host 都多紅**恰好** 8 條＝`[M18]` 的「1c 中止」「理由」「假家目錄未變」「junction 目標沒有被寫入」×2。

Mac 真機驗證步驟（使用者在自己的 Mac 上請 Claude 照做；全部在拋棄式目錄與拋棄式 dmg 裡，不碰真的 `~/.claude`）：
跑 `run-posix.sh`（預期 162／0）與對 `040b344` 的反向；`hdiutil create -fs APFS` 一個小映像，掛在假 HOME 的
skill 樹內（子樹）與 skill 根目錄本身（root），先記錄 `stat -f '%d %N'` 確認掛載點裝置號與上一層不同（整個修正的前提），
再依序驗 1b 中止、1b 後才掛上時 1c 中止、1c 後才掛上時回滾中止且 payload 保留；有 gnubin 才另跑 GNU stat 變體（不要安裝）；
最後用舊文件的回滾在拋棄式映像上確認「payload 被刪」的舊行為。清理前先確認沒有殘留掛載。

**2026-10-18 Mac 真機結果**（受測 `e250db0`；macOS 27.0.1、arm64、`/bin/bash` 3.2.57、只有 `/usr/bin/stat`、沒有 gnubin）：
- `run-posix.sh` 現行文件 `162／0`；對 `040b344` 反向 `134／28`（逐條見上方）。⚠️ 測試臺用 PATH 上的 `bash` 執行受測區塊，
  這台是 Homebrew 的 bash 5.3，所以這一步是在 bash 5.3 下跑的；下面的真掛載案才是 `/bin/bash` 3.2。
- 前提：skill 根目錄與 `references` 同一個裝置號，掛在 `references/mnt` 的映像是另一個裝置號。
- 1b 時子樹已掛載 → 1b 中止、沒印 ts、沒建 skill 備份；1b 之後才掛上 → 1c 中止；1c 之後才掛上 → 回滾中止；
  skill 根目錄本身是掛載點 → 1c 與回滾都中止。後三案前後快照完全相同，掛載內的 payload 都還在。
- GNU stat 變體：沒有 gnubin，略過（不安裝）。
- 反向：修正前文件的回滾刪光掛載內的 payload，`rm` 對掛載點報 `Resource busy`，回滾停在半刪狀態（rc=1）。
- 附記：macOS 27 的 `hdiutil create／attach／detach` 會印棄用警告（建議改用 `diskutil image`），目前仍可用。

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

### Windows 側對 `4a96698`（B1 之前）的反向驗證實測

⚠️ **下面兩段各是一次帶日期的量測，不是現況總表。** 案數與失敗集合會隨每批加案變動；
現行案數的唯一權威是 `run-windows.ps1` 的 `$EXPECTED_CHECKS`。

#### 最新：2026-08-17（`F2` 批，`[M13c]` 已含 hook／settings 兩目標）

| host | 現行文件 | `4a96698` |
|---|---|---|
| `pwsh` 7.6.3 | **126 PASS／0 FAIL** exit 0 | **112／14** exit 1 |
| Windows PowerShell 5.1.26100 | **126 PASS／0 FAIL** exit 0 | **112／14** exit 1 |

失敗的**恰好**是十四條＝下面 2026-08-12 那份的 M11 四條、M13 四條，
再加 `[M13c]` **六條**（hook／settings 各三：「來源錨點…」「產出…」「窄 oracle…」）。
⚠️ 兩 host 的**逐位置 PASS／FAIL 判定完全相同**；但**斷言字串不是逐行相同**
（字串裡嵌了 `ts`，且 `[M8]` 有一條「同秒／不同秒重跑」是時鐘競態分支）。
不要把它寫成「逐行 `diff` 無差異」。

#### 2026-08-12（`[M13c]` 當時只有 hook 一個目標、且是注入式）

| host | 現行文件 | `4a96698` |
|---|---|---|
| `pwsh` 7.6.3 | **112 PASS／0 FAIL** exit 0 | **101／11** exit 1 |
| Windows PowerShell 5.1.26100 | **112 PASS／0 FAIL** exit 0 | **101／11** exit 1 |

失敗的**恰好**是這十一條，兩個 host 逐條相同：

M11（本來就有，4 條）
- `[備份子樹] 回滾中止`、`[備份子樹] 被拒後 live 未變`
- `[live 子樹] 回滾中止`、`[live 子樹] 被拒後 live 未變`

M13（4 條）
- `[M13][備份子樹] 中止後 live 未變`、`[M13][備份子樹] 中止後整個假家目錄未變（hook／settings 也在內）`
- `[M13][live 子樹] 中止後 live 未變`、`[M13][live 子樹] 中止後整個假家目錄未變（hook／settings 也在內）`

M13c（3 條；⚠️ **這是 2026-08-12 標記式實作時的斷言名稱，現行已不同**——
現行是 `[M13c][hook]`／`[M13c][settings]` 各三條，名稱見上一節）
- `[M13c] 變異錨點唯一（否則本案等於沒測）`、`[M13c] 變異確實注入且只多一行`
- `[M13c] 窄 oracle（只看 skills）看不到這個違規`

M13c 那三條在舊版紅是**預期且正確的**：`4a96698` 根本沒有預掃那一行，所以錨點必然落空，
而未變異的舊區塊會刪掉 live，窄 oracle 也就看得到差異。

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
  （以上「13 個具名區塊」是 2026-08-04 的量測；之後陸續加了 `M11`–`M20`、`C4`，現行區塊以 `run-posix.sh` 為準。）
- **抽取靠關鍵字定位**（`backup ts=`／`install OK`／`Test-Exactly1`／`precheck skill`；Windows 另有 0a 的 `GIT_BASH_OK`）。
  命中數不等於 1 時直接 abort，不會猜。
- **Windows 快照忽略** `AppData\Local\Microsoft\PowerShell\*`——`pwsh` 自己會在被重導的
  家目錄下建 `StartupProfileData-NonInteractive`，那是測試臺雜訊。其餘整個假家目錄都比對。
- **`run-posix.sh` 抽取時做 `tr -d '\r'`**：Windows 工作目錄的檔可能是 CRLF，會讓
  `set -euo pipefail` 假炸成 `pipefail: invalid option name`。committed blob 依
  [`.gitattributes`](../../.gitattributes) 是 LF，所以這等同真實 Unix checkout。
- **測不到的東西**：NTFS symlink（需管理員權限或開發者模式）；真的掛載點——POSIX 側只以假 stat 模擬控制流、
  Windows 側以 junction 覆蓋同一個 `ReparsePoint` 屬性，NTFS 掛載資料夾還沒實測（macOS 真機已於 2026-10-18 以 hdiutil 驗證，見上方
  「掛載點守衛」一節）；同裝置號的掛載（Linux bind mount）偵測不到。Windows 0a 的「沒有 Git Bash 時 Claude Code 擋下 hook」
  本身也沒有 live 重現。殘留風險記在 [`docs/backlog.md`](../../docs/backlog.md)。
