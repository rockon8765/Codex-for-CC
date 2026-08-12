# macOS 交接：POSIX 側 `[M13]` 窄 oracle 修正（2026-08-12）

> **狀態：Linux（WSL2）已驗，macOS PENDING。**
> 本批只動 `tests/ai-install/run-posix.sh`（測試臺本身）與文件，**沒有動任何產品檔**
> ——`docs/AI-INSTALL.md`、三平台 payload、hook、snippet 全部未改。

## 0. 這批在修什麼

2026-08-12 Windows 側補 `[M13]` 時，合併前 Codex 審查抓到 **POSIX 側有完全同型的
surviving mutant**：`run-posix.sh` 的 `[M13]` 只 `snap "$H/.claude/skills"`，
但契約說的是「**任何** mutation 之前中止」，而回滾在預掃**之後**還會還原 hook 與 settings。
於是「把 hook 還原搬到第一個 `scan_no_link` 之前」這個違規，舊 oracle 會**全綠放行**。

**這不是推論，是實測**：新增的 `[M13c]` 同時斷言
`窄 oracle（只看 skills）看不到這個違規` 與 `寬 oracle（整個假 HOME）抓到` ——
兩條在 Linux 都 PASS，也就是缺口與修法都被證實。

本批的改動：

1. `[M13]` 兩變體各多比一份**整個假 HOME** 的快照。
2. 新增 `[M13b]`：把 `scan_no_link` 裡「掃描失敗 → 中止」那一行換成把錯誤吞掉，
   斷言 live 確實被動過（證明保護來自那一行）。鎖**備份**子樹而非 live。
3. 新增 `[M13c]`：把回滾裡**既有的** hook 還原兩行**原樣搬到**第一個 `scan_no_link` 之前
   （搬移而非另外注入，產物就是產品自己的程式碼、只是順序錯了）。
4. 注入自我檢查改成 **chmod 前必須掃得動、chmod 後必須掃不動**。
   舊寫法只驗「chmod 後 find 非零」——`$ROOT` 算錯時 find 一樣非零，那是一條假綠路徑。
5. 被鎖的目錄裡**放進一個檔案**（原本是空目錄）。
6. 斷言名稱加 `[M13]`／`[M13b]`／`[M13c]` 前綴（原本與 M11 的 `[bak]`／`[live]` 撞名）。
7. 新增 `EXPECTED_CHECKS_NONROOT` / `EXPECTED_CHECKS_ROOT` 案數硬斷言。

### ⚠️ 第 5 點會改變你熟悉的反向驗證數字（這是刻意的）

2026-08-10 你回報過「Linux 88/7、macOS 89/6，差的那條是 `[M13][live] 列舉失敗 → 回滾中止`」，
成因是**空的 mode-000 目錄**在 GNU 被 `rmdir` 移除得掉（exit 0）、BSD 則拒絕進入（exit 1）。
**現在目錄裡有檔案，兩邊的 `rm -rf` 都會失敗**，那條在兩個平台都 PASS。

→ **預測：Linux 與 macOS 的反向驗證結果現在完全相同（98/13）。**
如果你在 macOS 量到別的數字，那是新資訊，請照實回報**不要**去湊。

## 1. blob 釘死（本 repo macOS 無 CI，一律釘 blob 不釘 SHA）

| 檔案 | `git hash-object` | 備註 |
|---|---|---|
| `tests/ai-install/run-posix.sh` | `a1041030039e08c5dea7f8dfbd0ed8a7e7e95881` | 🔴 **本批唯一改動的可執行檔**（舊值 `637a9935…` 作廢）|
| `tests/ai-install/run-posix-args.test.sh` | `ee8da03c7f29d16061026622220843a95523cfeb` | 未改動 |
| `docs/AI-INSTALL.md` | `a2b3d69f676112f138e2d48deb459c80afadafc8` | **未改動**（與上一批相同）|

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
| B-0 | 逐筆 `git hash-object` 核對 §1 | 三筆全符 |
| B-1 | `bash tests/ai-install/run-posix.sh` | `bash  PASS=111  FAIL=0`，**exit 0**，且開頭「受測文件：」指向 repo 內的 `docs/AI-INSTALL.md`、「文件 hash：」為 `a2b3d69f…` |
| B-2 | 反向驗證（見下方指令）| `bash  PASS=98  FAIL=13`，**exit 1**，失敗的**恰好**是 §3 那 13 條 |
| B-3 | `bash tests/ai-install/run-posix-args.test.sh` | `TOTAL 13  PASS 13  FAIL 0`，exit 0 |
| B-4 | 案數硬斷言的牙齒（見下方）| 印 `PASS=110 FAIL=0` **但**多一行 `STOP 案數不符：實跑 110、預期 111`，**exit 1** |
| B-5 | root 分支的案數（見下方）| `PASS=85 FAIL=1`（合計 86）、**沒有** `STOP 案數不符` 那一行、exit 1 |

### B-2 反向驗證

```bash
git show 4a96698:docs/AI-INSTALL.md > ~/before-4a96698.md
# 自我檢查：抽出來的必須是舊版，不是現行版
git hash-object ~/before-4a96698.md    # 必須是 46c3cb010182b7ad7911e2b6d842254f8a860635
bash tests/ai-install/run-posix.sh --doc ~/before-4a96698.md; echo "rc=$?"
```

⚠️ 跑完**務必看輸出開頭的「受測文件：」與「文件 hash：」兩行**，
那是「目標到底有沒有換掉」的唯一證據，只比 `PASS=`／`FAIL=` 數字看不出問題。

### B-4 案數硬斷言的牙齒

```bash
T="run_rollback \"\$TS\" \"\$H\"; check '正確 ts 的回滾必須成功（否則上面全是假通過）' \$? \"\$LAST_OUT\""
grep -cxF "$T" tests/ai-install/run-posix.sh        # 必須是 1，否則錨點已過期、本項等於沒測
grep -vxF "$T" tests/ai-install/run-posix.sh > ~/minus1.sh
[ "$(( $(wc -l < tests/ai-install/run-posix.sh) - $(wc -l < ~/minus1.sh) ))" -eq 1 ] && echo "注入生效"
REPO="$PWD" bash ~/minus1.sh; echo "rc=$?"   # REPO 必須顯式帶入：副本不在 repo 內，dirname 推不出來
```

沒有這道斷言的話，少一案會印 `PASS=110 FAIL=0` 並 **exit 0** —— 那正是要消滅的假綠。

### B-5 root 分支的案數

無 sudo 也能驗，因為要確認的是**案數常數**而不是 root 對 `chmod` 的真實行為：

```bash
mkdir -p ~/fakebin
printf '#!/bin/bash\nif [ "${1:-}" = "-u" ]; then echo 0; else exec /usr/bin/id "$@"; fi\n' > ~/fakebin/id
chmod 755 ~/fakebin/id
PATH="$HOME/fakebin:$PATH" bash tests/ai-install/run-posix.sh; echo "rc=$?"
rm -rf ~/fakebin
```

## 3. B-2 的 13 條（釘**斷言名稱**，不要釘總數）

M11（本來就有，4 條）
- `[bak] 回滾中止`、`[bak] 被拒後 live 未變`
- `[live] 回滾中止`、`[live] 被拒後 live 未變`

M13（4 條）
- `[M13][bak] 中止後 live 未變`、`[M13][bak] 中止後整個假 HOME 未變（hook／settings 也在內）`
- `[M13][live] 中止後 live 未變`、`[M13][live] 中止後整個假 HOME 未變（hook／settings 也在內）`

M13b（2 條）
- `[M13b] 變異錨點唯一（否則本案等於沒測）`
- `[M13b] 變異確實注入且只動一行`

M13c（3 條）
- `[M13c] 三個錨點各自唯一（否則本案等於沒測）`
- `[M13c] 確實是「搬移」：行數不變、仍恰一份、且位置早於首個掃描`
- `[M13c] 窄 oracle（只看 skills）看不到這個違規`

M13b／M13c 的錨點在舊版落空是**預期且正確的**：`4a96698` 根本沒有 `scan_no_link`，
所以那些整行錨點命中 0 次。落空之後變異檔等同未變異的舊區塊，於是
`窄 oracle 看不到` 也跟著紅（舊版把 live 刪了）。

⚠️ **`[M13][bak]／[live] 列舉失敗 → 回滾中止` 在舊版是 PASS**（不列入判準）：
舊版沒有預掃，`rm`／`cp` 自己撞權限一樣非零。**區辨力全在快照那幾條，不在退出碼。**

## 4. 回報什麼

- macOS 版本、arch、`bash --version`（系統 bash 3.2.57 或 Homebrew 5.x 都請註明）、`id -u`
- B-0…B-5 的實際輸出（`PASS=`／`FAIL=`／`rc=`），B-2 請貼**完整的 FAIL 清單**逐條核對
- 特別確認 §0 的預測：`[M13][live] 列舉失敗 → 回滾中止` 是否**不再**出現在 FAIL 清單裡
- 任何與本文件不符的地方，照實回報，**不要**去湊數字

驗完請把結果回寫進本檔與 [`../README.md`](../README.md)，並把 `run-posix.sh` 的
blob `a1041030…` 標為 macOS 已驗。
