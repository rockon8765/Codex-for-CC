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

兩者都在**全部通過時 exit 0**，任何一案失敗即 exit 1。`-Doc`／`DOC=` 可指向別的
文件版本（用途見下方「反向驗證」）。

## 為什麼有變異注入

正常路徑走不到「驗證失敗」那些分支——不注入等於沒驗。所以測試臺會主動製造故障：
把備份換成別的型別、換成 link、竄改安裝結果、用壞掉的 `ts`、讓備份與 `.absent` 並存等。

**每個注入點都有自我檢查**：注入用的錨點字串若因文件改寫而失效，該案會明確 FAIL
（`變異確實注入（否則本案等於沒測）`），不會靜默變成假通過。

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
  ⚠️ **這次 macOS 驗的是 `9491719`（67 案）**。其後 `[M5]` 也補了同型前置檢查（→**68 案**），
  該筆**尚未在 macOS 跑過** —— 目前 tip 的 `run-posix.sh` 已不是 Mac 驗過的那份 blob。
  要宣稱目前 tip 在 macOS 已驗，須複跑一次（應為 68/68）。
- **抽取靠關鍵字定位**（`backup ts=`／`install OK`／`Test-Exactly1`／`precheck skill`）。
  命中數不等於 1 時直接 abort，不會猜。
- **Windows 快照忽略** `AppData\Local\Microsoft\PowerShell\*`——`pwsh` 自己會在被重導的
  家目錄下建 `StartupProfileData-NonInteractive`，那是測試臺雜訊。其餘整個假家目錄都比對。
- **`run-posix.sh` 抽取時做 `tr -d '\r'`**：Windows 工作目錄的檔可能是 CRLF，會讓
  `set -euo pipefail` 假炸成 `pipefail: invalid option name`。committed blob 依
  [`.gitattributes`](../../.gitattributes) 是 LF，所以這等同真實 Unix checkout。
- **測不到的東西**：NTFS symlink（需管理員權限或開發者模式）、掛載點／bind mount（需 root）。
  這兩項的殘留風險記在 [`docs/backlog.md`](../../docs/backlog.md)。
