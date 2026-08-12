# macOS 交接：POSIX 側 `[M13]` 窄 oracle 修正（2026-08-12）

> ## 🔴 狀態：**macOS 需要再驗一次（`run-posix.sh` 於 2026-08-13 又改了）**
>
> 2026-08-13 的 macOS 驗證涵蓋的是 blob **`90ddbd10…`**，**全綠**（紀錄保留在下方）。
> 但同日合併前審查在那個版本裡抓到**四個 harness 自身的缺陷**（其中一個是我引進的回歸），
> 修完之後 `run-posix.sh` 變成 blob **`5d8ad453…`** ——
> **依「改到受測檔就把舊驗證標回 pending」的規矩，上一輪的 macOS 結果不再涵蓋現行版本。**
>
> 要重驗的是 §1 的新 blob ＋ §2 的 B-0…**B-8**（新增 B-8：mode 型 mutant）。
> 期望值 `125/0`／`107/18` **沒有變**，改的是 harness 的觀測方式，不是案數。
>
> ### 上一輪（blob `90ddbd10…`）的結果，保留存證
>
> macOS 26.6.1 (25G76) arm64／**系統 `/bin/bash` 3.2.57(1)-release**（`which -a bash` 只有 `/bin/bash`，
> 確認不是 Homebrew 5.x）／`id -u`＝501／git 2.55.0／HEAD `eb5cdd7`／`git status --porcelain` 為空／
> 兩個 `.sh` 的 CR 計數皆為 0。四筆 blob 全符。
>
> | # | 實測 | 期望 | |
> |---|---|---|---|
> | B-0 | 四筆 blob 全符 | 同 | ✅ |
> | B-1 | `PASS=125 FAIL=0` rc=0 | 同 | ✅ |
> | B-2 | `PASS=107 FAIL=18` rc=1，18 條與 §3 逐條相符 | 同 | ✅ |
> | B-3 | `TOTAL 13 PASS 13 FAIL 0` rc=0 | 同 | ✅ |
> | B-4 | `PASS=124 FAIL=0` ＋ `STOP 案數不符：實跑 124、預期 125（uid=501）` rc=1 | 同 | ✅ |
> | B-5 | `PASS=85 FAIL=1` 無 STOP rc=1 | 同 | ✅ |
> | B-6 | `PASS=125 FAIL=0` rc=0 | 同 | ✅ |
> | B-7 | `PASS=125 FAIL=0` rc=0 | 同 | ✅ |
>
> **兩個預測都成立**：
> 1. `[M13][bak]／[live] 列舉失敗 → 回滾中止` **不在** B-2 的 FAIL 清單（兩條都是 PASS）——
>    **macOS 的反向驗證從 89/6 變成 107/18，與 Linux 完全相同**，2026-08-10 的 GNU／BSD 分歧確實消失了。
> 2. B-6／B-7 在 **bash 3.2** 下仍是 125/0。
>
> ⚠️ **驗證者沒有只信綠燈，而是跑了正向對照證明注入真的有觸發**（這正是本測試臺的精神）：
> bash 3.2.57 **確實**會為非互動腳本 source `$BASH_ENV`（對照組寫出了側檔）；
> 在 B-7 的 payload 下裸 `bash -n` **確實**被劫持（rc=77）而 `command bash -n` 不會（rc=0）；
> B-6 的 glob `*/ai-install-harness.??????/*` **確實**命中 harness 佈局
> （`new_home()` 是 `$WORK/<case>`、`WORK=$TMPDIR/ai-install-harness.XXXXXX`）；
> 並在**暫存副本**上做 A／B（repo 未動）——把 `run()` 的 `BASH_ENV= ENV=` 拿掉後
> **`PASS=123 FAIL=2` rc=1**，紅的恰好是 `[M13][bak]`／`[M13][live] 中止後整個假 HOME 未變`。
> **所以 B-6／B-7 的綠是掙來的，不是因為注入沒生效。**
>
> 驗證者另外抓到本文件的四處錯誤，**均已於 2026-08-13 修正**（見文末「文件訂正紀錄」）。

> **原始狀態（保留存證）：Linux（WSL2）已驗，macOS PENDING。**
> 本批只動 `tests/ai-install/run-posix.sh`、`tests/ai-install/run-windows.ps1`（兩個測試臺本身）
> 與文件，**沒有動任何產品檔** ——`docs/AI-INSTALL.md`、三平台 payload、hook、snippet 全部未改。
> 你只需要驗 POSIX 側；Windows 側已在本機兩個 host 驗過。
>
> ⚠️ **本文件所有指令一律用 `mktemp` 建立暫存檔／暫存目錄，不使用 `~/xxx` 這種固定路徑。**
> 第一版寫了 `~/fakebin`、`~/before-4a96698.md`、`~/minus1.sh`，會覆蓋／刪除你既有的同名檔案，
> 而且**違反 `run-posix.sh` 自己寫在檔頭的「不要用固定路徑」規則**（合併前 Codex 審查抓到，已修）。

## 0. 這批在修什麼

2026-08-12 Windows 側補 `[M13]` 時，合併前 Codex 審查抓到 **POSIX 側有完全同型的
surviving mutant**：`run-posix.sh` 的 `[M13]` 只 `snap "$H/.claude/skills"`，
但契約說的是「**任何** mutation 之前中止」，而回滾在預掃**之後**還會還原 hook 與 settings。

**這不是推論，是實測**：新增的 `[M13c]` 同時斷言
`窄 oracle（只看 skills）看不到這個違規` 與 `寬 oracle（整個假 HOME）抓到` ——
兩個目標（hook／settings）四條在 Linux 都 PASS，缺口與修法都被證實。

改動：

1. `[M13]` 兩變體各多比一份**整個假 HOME** 的快照。
2. `[M13c]`（新）：把回滾裡**既有的**還原兩行**原樣搬到**第一個 `scan_no_link` 之前。
   **hook 與 settings 兩個目標各跑一次。**
3. `[M13b]`（新）：把 `scan_no_link` 裡「掃描失敗 → 中止」那一行換成把錯誤吞掉，
   斷言 live 確實被動過（證明保護來自那一行）。鎖**備份**子樹而非 live。
4. **`simulate_step2`**：M13／M13c 在快照前模擬安裝步驟 2 改動 settings。
   ⚠️ 沒有這一步，settings 型的違規**看不見** —— `seed` 寫的 settings 與 1b 的備份一模一樣
   （1c 不碰 settings），把 settings 還原搬到預掃前只是 `OLD → OLD`、雜湊不變。
   C1／C2 早就有這個手法（「否則還原斷言恆真」），M13 當初漏了。
5. 注入自我檢查改成 **chmod 前必須掃得動、chmod 後必須掃不動**。
   舊寫法只驗「chmod 後 `find` 非零」——`$ROOT` 算錯時 `find` 一樣非零，那是一條假綠路徑。
6. 被鎖的目錄裡**放進一個檔案**（原本是空目錄）。**這會改變你熟悉的反向驗證數字，見下。**
7. `run()` 清掉 `BASH_ENV`／`ENV`、釘 `HISTFILE=/dev/null`。
   非互動 bash（含 3.2）會 source `$BASH_ENV`，繼承進來的 startup 檔若往假 HOME 寫東西，
   寬 oracle 會誤紅、或被不相干的側檔冒充。**A／B 實測**：修正前在 `BASH_ENV` 下
   兩條寬 oracle 斷言誤紅，修正後 125/0。
   ⚠️ **這裡原本寫「109/2」，那個數字對現行腳本不可復現**（109+2=111，是當時 `aa74cfa` 的案數；
   加了 M13b／M13c 之後是 125）。**對現行腳本做等價 A／B 的正確數字是 `123/2`**
   ——macOS 驗證者在暫存副本上實測到的，紅的恰好是 `[M13][bak]`／`[M13][live] 中止後整個假 HOME 未變`。
   保留「109/2」只會讓後來的人追一個追不到的數字。
8. `snap` 掃不動時回傳**永遠不會相等**的哨兵（原本靜默給殘缺快照 → 兩次都殘缺就「相等」）；
   `make_locked`／`unlock` 失敗一律 `exit 2`。
9. 斷言名稱加 `[M13]`／`[M13b]`／`[M13c]` 前綴。
10. `EXPECTED_CHECKS_NONROOT=125`／`EXPECTED_CHECKS_ROOT=86` 案數硬斷言。
11. **`snap` 失敗改成「回非 0，由呼叫點硬中止」**（第二輪修）。中間版本用含 `$RANDOM` 的哨兵，
    對 `=` 比較有效，但 M13b／M13c 的寬 oracle 是 `!=` —— 後置快照失敗反而**必定 PASS**。
    方向性哨兵在雙向 oracle 下必然有一邊假綠；唯一正解是呼叫點檢查 rc
    （`$( )` 裡的 `exit` 只結束 subshell）。內層 `cksum`／`readlink` 的錯誤也改成往外傳。
12. **`unlock_tree`**：事後把**整個假 HOME** 的權限拉回可讀再快照。
    只解鎖自己建的那一個目錄不夠 —— 回滾若真的走到 mutation（M13b 的 fail-open、
    或反向驗證時的舊版），`cp -R` 會把 mode-000 子樹**一起複製進 live**，事後就掃不動。
    ⚠️ **這個問題是新的 fail-closed `snap` 真的抓到的**（`bash run-posix.sh` 當場 `exit 2` 停在 M13b），
    舊版只是靜默給了一份殘缺快照。
13. **`bash -n` 改成 `BASH_ENV= ENV= command bash -n`**：`run()` 清的是 child 的環境，
    管不到 harness 自己這一行；caller 的 startup 檔若定義了 `bash` 函式就會劫持它。
    **A／B 實測**：修正前在劫持用的 `BASH_ENV` 下是 `123/2`（兩條 `bash -n` 誤紅），修正後 `125/0`。
14. M13c 自我檢查再加兩條條件：**來源本來就在 anchor 之後**（否則產品若已經有缺陷，
    「搬移」會變成不搬而照樣綠）、**產出確實與原檔不同**（位置條件可能在什麼都沒搬時碰巧成立）。

### 2026-08-13 第四輪（合併前審查抓到四項，其中一項是我引進的回歸）

15. **`snap` 現在記錄 mode，並把「讀不到」記成觀測值**（`UNREADABLE`／`UNREADABLE-DIR`），
    而不是當成錯誤。**刪掉了 `unlock_tree`** —— 那個 helper 在後置快照前
    `chmod -R u+rwX` 整個假 HOME，在「快照不記 mode」的前提下等於**主動銷毀證據**。
    ⚠️ 我當時的論證是「snap 不記 mode，所以正規化不影響比對內容」，**正好講反了**。
    A／B 實測：舊版對 mode mutant 是 `125/0`（存活），新版 `123/2`（抓到）。
    權限正規化改到 `cleanup` trap 裡（所有斷言之後）。
    ⚠️ 連帶：**BEFORE 快照改到 `chmod 000` 之後取**（我們自己的注入也會改 mode，
    在 chmod 前取會把它算成違規 —— 實測 3 條假紅）。
16. **`die_snap` 接到全部 16 個呼叫點**（原本只有 M13 家族 3 處）。
    界線寫成「那些樹從不 chmod」不成立：snap 也會因 `readlink`／`cksum`／IO 失敗。
    A／B：讓 `readlink` 一律 exit 9 → 舊版 `125/0`（M11 前後快照都變空字串、`""=""` 通過），
    新版 rc 2 並印 `snap 失敗`。
17. **`cksum` 的錯誤真的往外傳了**：改成先 `line=$(cksum < "$p") || exit 1` 再切欄。
    舊寫法 `ck=$(cksum < f | cut …) || exit 1` 在內層 `sh -c` 只看得到 `cut` 的狀態。
    A／B：讓 `cksum` 一律 exit 9 → 舊版 `125/0`，新版 rc 2。
18. **`run()` 改用 `command bash`**：只清 `BASH_ENV`／`ENV` 而仍以**名稱**呼叫 `bash`，
    父 shell 已載入的 `bash()` 函式照樣攔得到（函式解析優先於 PATH）。
    A／B（父層定義攔截所有 `bash` 的函式）：舊版 **`82/43`、被攔截 29 次**；
    新版 `125/0`、攔截 **0 次**。

### ⚠️ 第 6 點會改變你熟悉的反向驗證數字（這是刻意的）

2026-08-10 你回報過「Linux 88/7、macOS 89/6，差的那條是 `[M13][live] 列舉失敗 → 回滾中止`」，
成因是**空的 mode-000 目錄**在 GNU 被 `rmdir` 移除得掉（exit 0）、BSD 則拒絕進入（exit 1）。
**現在目錄裡有檔案，兩邊的 `rm -rf` 都會失敗**，那條在兩個平台都 PASS。

→ **預測：Linux 與 macOS 的反向驗證結果現在完全相同（107/18）。**
若你在 macOS 量到別的數字，那是新資訊，請照實回報**不要**去湊。

## 1. blob 釘死（本 repo macOS 無 CI，一律釘 blob 不釘 SHA）

| 檔案 | `git hash-object` | 備註 |
|---|---|---|
| `tests/ai-install/run-posix.sh` | `5d8ad453e1ba24d8761a8d38111089515acad56a` | 🔴 **你要驗的就是這個**（`637a9935…`／`a1041030…`／`0ca6fa03…`／**`90ddbd10…`** 皆作廢）|
| `tests/ai-install/run-windows.ps1` | `bfec1fafaf48e7108c81a50d2ed73fb0ff6b9227` | 🔴 本批同步修，但**不需要你驗**（Windows 兩 host 已驗）|
| `tests/ai-install/run-posix-args.test.sh` | `ee8da03c7f29d16061026622220843a95523cfeb` | 未改動 |
| `docs/AI-INSTALL.md` | `a2b3d69f676112f138e2d48deb459c80afadafc8` | **未改動** |

> ⚠️ **請用 `git clone` 取得乾淨 checkout，不要複製 Windows 工作目錄**——後者在
> `core.autocrlf=true` 下會拿到 CRLF 的 `.sh`，`set -euo pipefail` 會炸成
> `pipefail: invalid option name`，看起來像程式壞掉，其實是行尾假陽性。
>
> ⚠️ **必須以非 root 執行**（`id -u` 不得為 0）。root 會忽略 `chmod`，注入無效；
> 測試臺在 root 之下會**硬失敗**而不是 SKIP，那是設計。

## 2. 要跑的項目與期望值

全部在 checkout 根目錄執行。

| # | 指令 | 期望 |
|---|---|---|
| B-0 | 逐筆 `git hash-object` 核對 §1 | 四筆全符 |
| B-1 | `bash tests/ai-install/run-posix.sh` | `bash  PASS=125  FAIL=0`，**exit 0**，「受測文件：」指向 repo 內的 `docs/AI-INSTALL.md`、「文件 hash：」為 `a2b3d69f…` |
| B-2 | 反向驗證（見下）| `bash  PASS=107  FAIL=18`，**exit 1**，失敗的**恰好**是 §3 那 18 條 |
| B-3 | `bash tests/ai-install/run-posix-args.test.sh` | `TOTAL 13  PASS 13  FAIL 0`，exit 0 |
| B-4 | 案數硬斷言的牙齒（見下）| 印 `PASS=124 FAIL=0` **但**多一行 `STOP 案數不符：實跑 124、預期 125`，**exit 1** |
| B-5 | root 分支的案數（見下）| `PASS=85 FAIL=1`（合計 86）、**沒有** `STOP 案數不符`、exit 1 |
| B-6 | `BASH_ENV` 隔離（見下）| 仍為 `PASS=125 FAIL=0`、exit 0 |
| B-7 | `bash -n` 不被劫持（見下）| 仍為 `PASS=125 FAIL=0`、exit 0 |
| B-8 | **mode 型 mutant 必須被抓到**（見下）| `PASS=123 FAIL=2`、exit 1，紅的**恰好**是 `[M13][bak]` 與 `[M13][live] 中止後整個假 HOME 未變（hook／settings 也在內）` |

### B-8 mode 型 mutant（2026-08-13 新增）

這是本輪最重要的一項：**快照現在會記錄 mode**，所以「產品在中止前偷改權限」抓得到。
在舊版（blob `90ddbd10…`）這個 mutant 會**存活為 `125/0`** —— 因為當時有個 `unlock_tree`
在後置快照前把整個假 HOME 的權限正規化，等於主動銷毀證據。

```bash
D=$(mktemp -d "${TMPDIR:-/tmp}/m13-mode.XXXXXX") || exit 1
trap 'chmod -R u+rwX "$D" 2>/dev/null; rm -rf "$D"' EXIT
A='    echo "掃描 $1（$2）失敗，狀態不明，中止（live 未變更）"; exit 1'
[ "$(grep -cxF "$A" docs/AI-INSTALL.md)" -eq 1 ] || { echo "錨點過期，本項等於沒測"; exit 1; }
awk -v a="$A" '$0 == a { print "    chmod 000 \"$setf\" # MODE-MUTATION-BEFORE-ABORT" } { print }' \
  docs/AI-INSTALL.md > "$D/mutant.md"
bash tests/ai-install/run-posix.sh --doc "$D/mutant.md"; echo "rc=$?"
```

⚠️ **B-2/B-6/B-7 的「綠」也要用同樣的懷疑態度看**：綠有可能是「注入根本沒觸發」。
上一輪你就是這樣排除的，這一輪的 B-8 是把同一個懷疑做成常設案。

### B-2 反向驗證

```bash
D=$(mktemp -d "${TMPDIR:-/tmp}/m13-handoff.XXXXXX") || exit 1
trap 'rm -rf "$D"' EXIT
git show 4a96698:docs/AI-INSTALL.md > "$D/before.md"
git hash-object "$D/before.md"    # 必須是 46c3cb010182b7ad7911e2b6d842254f8a860635
bash tests/ai-install/run-posix.sh --doc "$D/before.md"; echo "rc=$?"
```

⚠️ 跑完**務必看輸出開頭的「受測文件：」與「文件 hash：」兩行** ——
那是「目標到底有沒有換掉」的唯一證據，只比 `PASS=`／`FAIL=` 數字看不出問題。

### B-4 案數硬斷言的牙齒

```bash
D=$(mktemp -d "${TMPDIR:-/tmp}/m13-teeth.XXXXXX") || exit 1
trap 'rm -rf "$D"' EXIT
T="run_rollback \"\$TS\" \"\$H\"; check '正確 ts 的回滾必須成功（否則上面全是假通過）' \$? \"\$LAST_OUT\""
grep -cxF "$T" tests/ai-install/run-posix.sh          # 必須是 1，否則錨點過期、本項等於沒測
grep -vxF "$T" tests/ai-install/run-posix.sh > "$D/minus1.sh"
[ "$(( $(wc -l < tests/ai-install/run-posix.sh) - $(wc -l < "$D/minus1.sh") ))" -eq 1 ] && echo "注入生效"
REPO="$PWD" bash "$D/minus1.sh"; echo "rc=$?"   # REPO 要顯式帶入：副本不在 repo 內，dirname 推不出來
```

沒有這道斷言的話，少一案會印 `PASS=124 FAIL=0` 並 **exit 0** —— 那正是要消滅的假綠。

### B-5 root 分支的案數

無 sudo 也能驗，因為要確認的是**案數常數**，不是 root 對 `chmod` 的真實語義：

```bash
D=$(mktemp -d "${TMPDIR:-/tmp}/m13-fakeid.XXXXXX") || exit 1
trap 'rm -rf "$D"' EXIT
printf '#!/bin/bash\nif [ "${1:-}" = "-u" ]; then echo 0; else exec /usr/bin/id "$@"; fi\n' > "$D/id"
chmod 755 "$D/id"
PATH="$D:$PATH" id -u                                  # 需印 0
PATH="$D:$PATH" bash tests/ai-install/run-posix.sh; echo "rc=$?"
```

### B-6 `BASH_ENV` 隔離

```bash
D=$(mktemp -d "${TMPDIR:-/tmp}/m13-bashenv.XXXXXX") || exit 1
trap 'rm -rf "$D"' EXIT
printf '%s\n' 'case "$HOME" in */ai-install-harness.??????/*) printf x >>"$HOME/.bash-env-side";; esac' > "$D/env.sh"
BASH_ENV="$D/env.sh" bash tests/ai-install/run-posix.sh; echo "rc=$?"
```

⚠️ **bash 3.2 特別值得看這一項**：`$BASH_ENV` 的載入時機在舊版可能不同。
若它在 macOS 出現 FAIL，請貼完整清單——那代表隔離在 BSD/舊 bash 下不成立，是新資訊。

### B-7 `bash -n` 不會被 `BASH_ENV` 定義的函式劫持

```bash
D=$(mktemp -d "${TMPDIR:-/tmp}/m13-hijack.XXXXXX") || exit 1
trap 'rm -rf "$D"' EXIT
printf '%s\n' 'bash(){ if [ "${1-}" = -n ]; then return 77; else command bash "$@"; fi; }' > "$D/env.sh"
BASH_ENV="$D/env.sh" bash tests/ai-install/run-posix.sh; echo "rc=$?"
```

期望 **`PASS=125 FAIL=0`、exit 0**。（Linux 上修正前是 `123/2`，兩條
`[M13c][*] 產出的區塊語法正確（bash -n）` 誤紅。）

## 3. B-2 的 18 條（釘**斷言名稱**，不要釘總數）

M11（本來就有，4 條）
- `[bak] 回滾中止`、`[bak] 被拒後 live 未變`
- `[live] 回滾中止`、`[live] 被拒後 live 未變`

M13（4 條）
- `[M13][bak] 中止後 live 未變`、`[M13][bak] 中止後整個假 HOME 未變（hook／settings 也在內）`
- `[M13][live] 中止後 live 未變`、`[M13][live] 中止後整個假 HOME 未變（hook／settings 也在內）`

M13b（2 條）
- `[M13b] 變異錨點唯一（否則本案等於沒測）`
- `[M13b] 變異確實注入且只動一行`

M13c（8 條，hook／settings 各 4）——**斷言名稱是完整字串，不要截斷**
- `[M13c][hook] 來源錨點：三串各唯一、兩行相鄰、anchor 是第一個 scan_no_link、且來源在 anchor 之後`
- `[M13c][hook] 產出：行數不變、各恰一份、兩行相鄰且緊貼 anchor、且確實與原檔不同`
- `[M13c][hook] 回滾仍中止，且中止原因是掃描失敗`
- `[M13c][hook] 窄 oracle（只看 skills）看不到這個違規`
- 以上四條的 `[M13c][settings]` 版本

> ⚠️ 前兩條原本寫成截斷版（少了 `、且來源在 anchor 之後` 與 `、且確實與原檔不同`）——
> §0 第 14 點加了那兩個條件，但這裡忘了同步。**macOS 驗證者比對輸出時抓到，已修正。**
> 一份以「釘斷言名稱而非總數」為判準的文件，名稱寫錯就等於沒有判準。

M13b／M13c 的錨點在舊版落空是**預期且正確的**：`4a96698` 根本沒有 `scan_no_link`。

⚠️ **`[M13][bak]／[live] 列舉失敗 → 回滾中止` 在舊版是 PASS**（不列入判準）：
舊版沒有預掃，`rm`／`cp` 自己撞權限一樣非零。**區辨力全在快照那幾條，不在退出碼。**

## 4. 回報什麼

- macOS 版本、arch、`bash --version`（系統 bash 3.2.57 或 Homebrew 5.x 都請註明）、`id -u`
- **B-0…B-7** 的實際輸出（`PASS=`／`FAIL=`／`rc=`），B-2 請貼**完整 FAIL 清單**逐條核對
- 特別確認兩個預測：
  1. `[M13][live] 列舉失敗 → 回滾中止` **不再**出現在 FAIL 清單
  2. B-6／B-7 在 bash 3.2 下仍是 125/0
- 任何與本文件不符的地方，照實回報，**不要**去湊數字

## 5. 文件訂正紀錄（2026-08-13，macOS 驗證者抓到）

驗證者回報四處文件錯誤，全部屬實、全部已修。**前兩處是驗收單自己失真**——
一份以「釘 blob、釘斷言名稱」為判準的文件出現這種錯，比數字不對更嚴重：

| # | 問題 | 處置 |
|---|---|---|
| 1 | §4 結尾要求把 blob **`0ca6fa03…`** 標為 macOS 已驗，但 §1 明列該 blob **已作廢**、釘的是 `90ddbd10…`。**同一份文件內自相矛盾。** | 已改為記錄實際驗證的 `90ddbd10…` |
| 2 | §3 的 M13c 前兩條斷言名稱是**截斷版**（少了 `、且來源在 anchor 之後`／`、且確實與原檔不同`）——§0 第 14 點加了條件卻沒同步 §3 | 已補完整字串並加註 |
| 3 | §0 第 7 點的 `109/2` **對現行腳本不可復現**（111 案是 `aa74cfa` 的舊案數）；等價 A／B 的正確數字是 `123/2` | 已訂正並說明來源 |
| 4 | §4 寫「回報 B-0…B-6」，§2 的表卻定義到 B-7 | 已改為 B-0…B-7 |

**驗證結果不受這四處影響**：驗證者是照 §1／§2 的 blob 與期望值跑的，四處都只影響可讀性與後續動作，
不影響已執行的驗證本身。

~~驗完請把結果回寫進本檔與 README，並把 `run-posix.sh` 的 blob `0ca6fa03…` 標為 macOS 已驗。~~
⚠️ **這一行原本釘錯 blob**（`0ca6fa03…` 在 §1 已列為作廢，實際要驗的是 `90ddbd10…`）——
macOS 驗證者抓到，見 §5。**已於 2026-08-13 完成**：`run-posix.sh` blob
`90ddbd109df6f8ca52f00b4c962e295b820251a6` **macOS 已驗**（結果見文件開頭）。
