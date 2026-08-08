# macOS 原生驗證交接：A2（MIGRATION probe 抽成 repo 腳本）

> ## 第一趟：✅ 已完成（2026-08-09 回報，受驗 `f530cd6`，A-1～A-7 七項全綠）
>
> **環境**：macOS 26.6.1 arm64／內建 `bash 3.2.57(1)-release`／Node **v26.4.0**／
> Claude Code 2.1.222／執行帳號 `uid=501` 非 root。9 筆 blob 全符。
>
> probe **42/42**、gate-cases **117/117**、`matcher-contract` exit 0、`run-posix.sh` **68/68**、
> 反向驗證 **6 PASS／36 FAIL**（PASS 清單經程式化比對恰為那 6 個對照組，不是靠總數推斷）、
> 三份 snippet JSON、`backup-settings --strict` **8/8 SKIP 0**。
>
> §4 診斷：**BSD 的 `e.code` ＝ `EISDIR`**，與 Linux 相同；`halt-exec-form` 確認是
> **因為偵測到 exec form** 而 exit 3；假 `HOME` 機制在 macOS 有效（驗證者真實的
> `~/.claude/settings.json` 有註冊 gate，而 probe 印「檔案不存在」——有效的正向對照）。
> `top-null`／`pretooluse-object` 的失敗原因**只有「缺少字串」、沒有退出碼不符**，
> 證實舊版對它們湊巧也 exit 1，只有字串斷言抓得到。
>
> **驗證者另外找出一個 macOS 專屬缺陷並給了可攜修法**（已採用，見 §3）：BSD `mktemp`
> 不接受尾綴，`...XXXXXX.js` 會建出**字面**檔名。他們的診斷比原本的更精確——`mkstemp`
> 帶 `O_EXCL`，所以那個失效模式是**拒絕**而不是「覆寫或跟隨 symlink」；真正的害處是
> A-5 在 macOS 不可重跑，以及 `TMPDIR` 未設時 fallback 到 world-writable 的 `/tmp`，
> 別人預先建那個固定路徑就能永久擋掉這項驗證。

> ## 第二趟：⏳ 待跑（delta 重驗）
>
> 第一趟之後，合併前審查第五輪的修正**動了受測程式碼的行為**，所以那三個數字已經過時：
>
> | 動到什麼 | 影響哪些項目 |
> |---|---|
> | probe：`process.exit()` → `process.exitCode` **自然結束**（`process.exit()` 依 Node 官方文件會截斷尚未完成的 stdout）；範圍輸出改成正面列出「驗什麼」 | **A-1、A-5** |
> | `backup-settings`：回收改成**先登記再動手**、`sha()` 移進 `try`、拿掉守不住的 all-or-nothing 宣稱改為 best-effort；中止改走 `BAIL` 不呼叫 `process.exit()` | **A-7** |
> | 新增 `tests/helpers/fixed-clock.js`：撞名案改用**固定時鐘**確定性觸發，不再賭時鐘 | **A-7** |
>
> **仍然成立、不必重跑**：A-2（gate-cases 117）、A-3（`matcher-contract`）、A-4（`run-posix.sh` 68）、
> A-6（三份 snippet JSON）、以及 §4 的三項診斷——那些檔的 blob 完全沒動，
> 下面的 blob 表可以自行核對（`macos/settings.snippet.json`、`docs/linux-platform-notes.md`
> 與第一趟相同）。
>
> **第二趟只要跑 A-1、A-5、A-7 三項。**

## 1. 受驗版本與 blob

**受驗版本＝分支 `fix/a2-migration-probe-2026-08-08` 的尖端。**
**釘子是下面這 10 筆 blob，不是 SHA**——這樣「之後又補了一個只改 README 的 commit」
不會讓你以為版本不對。任何一筆不符就停手回報。

```bash
cd <你的 Codex-for-CC checkout>
git fetch && git checkout fix/a2-migration-probe-2026-08-08
for f in tools/probe-gate-registration.js tools/backup-settings.js \
         tests/probe-gate-registration.test.js tests/backup-settings.test.js \
         tests/helpers/fixed-clock.js \
         docs/MIGRATION-hook-settings-target.md docs/AI-INSTALL.md \
         macos/settings.snippet.json "macos/skills/超級模式/references/orchestration.md" \
         docs/linux-platform-notes.md; do
  printf '%-58s %s\n' "$f" "$(git rev-parse "HEAD:$f" | cut -c1-12)"
done
```

| 檔 | 期望 blob（前 12 碼）|
|---|---|
| `tools/probe-gate-registration.js` | `4ac2afb5ca1d` |
| `tools/backup-settings.js` | `9e2b7505c37f` |
| `tests/probe-gate-registration.test.js` | `ae13d74cbf89` |
| `tests/backup-settings.test.js` | `947ee667233c` |
| `tests/helpers/fixed-clock.js` | `4559343935e3` |
| `docs/MIGRATION-hook-settings-target.md` | `9d58639038b4` |
| `docs/AI-INSTALL.md` | `bfab2749379f` |
| `macos/settings.snippet.json` | `a903d6aac575` |
| `macos/skills/超級模式/references/orchestration.md` | `92ce1cfb3bfe` |
| `docs/linux-platform-notes.md` | `afa9cafd5d3e` |

> `README.md` 與本檔**刻意不列入**：它們是敘述性文件、不影響任何一項驗證，
> 而且補釘 SHA 時還會再動一次。把它們放進釘子只會製造假的「版本不符」。

## 2. 要跑的項目（第二趟只有這三項）

**不會動你的 `~/.claude`。** 測試臺一律用假 `HOME` 在 temp 目錄操作、跑完自己清掉；
A-5 抽出來的舊 probe 用 `mktemp -d` ＋ `trap` 清理。
（A-1／A-5 受測的 probe 本身唯讀；A-7 受測的 `backup-settings` 會寫檔，
但只寫在測試臺開的假 `HOME` 裡。）

| # | 指令 | 期望 |
|---|---|---|
| **A-1** | `node tests/probe-gate-registration.test.js` | `TOTAL 44  PASS 44  FAIL 0`，exit 0 |
| **A-5** | 反向驗證，見 §3 | `TOTAL 44  PASS 7  FAIL 37`（該指令本身 exit 1，那是預期的）|
| **A-7** | `node tests/backup-settings.test.js --strict` | `TOTAL 9  PASS 9  FAIL 0  SKIP 0`，**exit 0** |

> ⚠️ **A-7 一定要帶 `--strict`**（有任何 SKIP 就回非 0），不要靠人眼去看 SKIP 數。
> 兩個變異注入案在 Windows 上因權限做不到而會 SKIP，**macOS 兩者都做得到，所以必須 `SKIP 0`**：
>
> - `symlink-refused-and-no-partial` —— 驗「來源是 symlink 時拒絕備份，且不留半套」
> - `copy-phase-failure-rolls-back` —— 用 `chmod 000` 注入，驗「複製階段失敗會盡力回收本次登記的備份」
>
> 若你以 **root** 執行，`chmod 000` 擋不住讀取、注入會失效並自動標 SKIP（那是刻意的自我檢查）
> ——請改用一般帳號重跑，不要當成通過。
>
> `node` 若不在 PATH（可攜式安裝）請用絕對路徑；回報時附 `node -v`。

## 3. A-5 反向驗證（**這一項最重要**）

新回歸案必須對**修正前**版本 FAIL，否則只是裝飾。把 `5cc50e0` 那版內嵌的 heredoc probe
抽出來，用 `--probe` 指向它：

```bash
set -euo pipefail
# 不要寫死 /tmp/legacy-probe.js：固定路徑可以被別人預先佔住。
# ⚠️ **BSD 的 mktemp 不接受尾綴**：`X` 不在模板結尾就完全不展開。
# `...XXXXXX.js` 在 macOS 會建出**字面**檔名（零隨機化），連跑兩次第二次直接
# `mkstemp failed: File exists`；GNU 的 mktemp 反而會過，所以在 WSL 上驗不出來。
# 可攜寫法是建暫存**目錄**、檔名放在裡面。（2026-08-09 macOS 26.6.1 實測過。）
d=$(mktemp -d "${TMPDIR:-/tmp}/legacy-probe.XXXXXX")
trap 'rm -r "$d"' EXIT
legacy="$d/probe.js"

git show 5cc50e0:docs/MIGRATION-hook-settings-target.md \
  | awk "/^node - <<'PROBE'$/{f=1;next} /^PROBE$/{f=0} f" > "$legacy"

# 牙齒檢查：抽出來的必須真的是舊版，否則等於拿新版對新版比。
# ⚠️ 檢查失敗要**真的中止**（exit 1），只印一行「停手」但繼續跑等於沒有守衛。
grep -q 'for (const entry of (j.hooks && j.hooks.PreToolUse) || \[\])' "$legacy" \
  || { echo '抽取失敗：不含舊版特徵行'; exit 1; }
! grep -q '形狀不合' "$legacy" \
  || { echo '抽到新版了，停手'; exit 1; }
echo '牙齒檢查通過'

node tests/probe-gate-registration.test.js --probe "$legacy"
```

**期望 `PASS 7  FAIL 37`**，而且通過的 7 個必須**恰為**這幾個對照組
（它們是行為刻意未改變的案子）：

```
ok-normal, ok-none-nongate-handler, ok-bom, ok-entry-without-hooks-key,
ok-gate-plus-unrelated-entry, ok-unrelated-exec-form,
scope-command-type-without-command-passes
```

> ⚠️ **只核對 `FAIL 37` 這個數字不夠。** 請把完整的 FAIL 清單貼回來——
> 2026-08-08 就是因為只看總數，差點漏掉「失敗的不是該失敗的那幾條」。

## 4. 這一趟新增的兩項唯讀診斷

第一趟的三項診斷（BSD `e.code`、假 `HOME`、`halt-exec-form` 的停手理由）**不必重做**。
這一趟請改看下面兩項，它們針對的正是這次改掉的東西：

1. **範圍輸出在每條退出路徑都要出現**（先前只在「有找到 gate」時印，而最需要它的是
   「找到 0 筆 → 接著會叫人新增一筆」那條）。請各跑一次並確認**輸出結尾都有那段
   「本工具只數…範圍刻意很窄」**：
   - `HOME=$(mktemp -d) node tools/probe-gate-registration.js` → exit 0、判「兩邊都沒有 gate」
   - 隨便造一個壞 JSON 的假 HOME → exit 1
   （`A-1` 裡的 `invalid-json`／`ok-none-both-missing`／`halt-exec-form`／`halt-shared-entry`
   已經在斷言這件事，這裡只是人眼複核一次。）
2. **`fixed-clock` 注入是否真的生效**：`A-7` 的 `collision-aborts-without-partial` 現在靠
   固定時鐘確定性觸發。請確認它**沒有**出現在 SKIP 清單裡（`--strict` 會幫你把關），
   並回報 `fixed-clock-control-group` 也通過——那是它的正向對照，用來排除
   「注入把工具弄壞了所以才失敗」。

## 5. 回報格式

```
環境：macOS <版本> <arch>／bash <版本>／node <版本>／Claude Code <版本>／uid
blob：10 筆 全符 / 不符（列出）
A-1／A-5／A-7：實際輸出（數字 ＋ exit code）
A-5 的 FAIL 清單：完整貼上
A-7 的 SKIP 數（必須是 0）
§4 的兩項診斷：實際觀察
```

回報後我會把結果回寫到 README「本次 delta 的驗證分布」的 macOS 那一列。
**在那之前，README 那一列會標明「第一趟已完成、delta 待重驗」。**
