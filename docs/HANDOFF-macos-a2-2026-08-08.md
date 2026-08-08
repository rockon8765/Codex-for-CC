# macOS 原生驗證交接：A2（MIGRATION probe 抽成 repo 腳本）

> **狀態：pending。** 本批在 Windows 與 Linux(WSL2/ext4) 皆綠，**macOS 未原生驗證**。
> 在收到回報之前，不要把本批當成三平台等價驗證過。

## 0. 為什麼需要 macOS 這一趟

本批把 `docs/MIGRATION-hook-settings-target.md` 第 1 節內嵌的 bash heredoc probe
抽成 **repo 內的 Node 腳本**，並補上跨平台的 committed 回歸案。
新增的四個 `.js`（`tools/` 兩支、`tests/` 兩支）都是純 Node（理論上平台無關），但：

- `os.homedir()` 在各平台的解析來源不同（POSIX 讀 `HOME`、Windows 讀 `USERPROFILE`），
  測試臺**兩個都設**，需要在 BSD userland 實證這個做法成立。
- 非 ENOENT 讀取錯誤的 `e.code`（案例 `read-error-directory` 用「settings.json 是目錄」觸發）
  在 BSD 上未必與 Linux 相同。斷言刻意只比前綴「讀取失敗：」，需要實證這個放寬是夠的。
- 三份 `settings.snippet.json` 的 `_comment` 與兩份 `orchestration.md` 有改動，
  其中 macOS 那兩份屬 macOS payload。

**沒有**新增任何 shell 腳本，也沒有動 `tests/ai-install/run-posix.sh`／`codex-check`／
`matcher-contract`（後者與 `main` 同 blob）。所以 BSD vs GNU 的 `sed`／`awk`／`find`／`cp`
語義差異**不在本批的暴險面**。

## 1. 受驗 SHA 與 blob

**受驗版本＝分支 `fix/a2-migration-probe-2026-08-08` 的尖端。**
**釘子是下面這 9 筆 blob，不是 SHA**——這樣「之後又補了一個只改 README 的 commit」
不會讓你以為版本不對。任何一筆不符就停手回報。

```bash
cd <你的 Codex-for-CC checkout>
git fetch && git checkout fix/a2-migration-probe-2026-08-08
for f in tools/probe-gate-registration.js tools/backup-settings.js \
         tests/probe-gate-registration.test.js tests/backup-settings.test.js \
         docs/MIGRATION-hook-settings-target.md docs/AI-INSTALL.md \
         macos/settings.snippet.json "macos/skills/超級模式/references/orchestration.md" \
         docs/linux-platform-notes.md; do
  printf '%-58s %s\n' "$f" "$(git rev-parse "HEAD:$f" | cut -c1-12)"
done
```

| 檔 | 期望 blob（前 12 碼）|
|---|---|
| `tools/probe-gate-registration.js` | `28bd25ac4a15` |
| `tools/backup-settings.js` | `081a6f384a84` |
| `tests/probe-gate-registration.test.js` | `ff844feaa381` |
| `tests/backup-settings.test.js` | `8b4a8f259243` |
| `docs/MIGRATION-hook-settings-target.md` | `eecac6aa8f09` |
| `docs/AI-INSTALL.md` | `bfab2749379f` |
| `macos/settings.snippet.json` | `a903d6aac575` |
| `macos/skills/超級模式/references/orchestration.md` | `a4dd320b3285` |
| `docs/linux-platform-notes.md` | `afa9cafd5d3e` |

> `README.md` 與本檔**刻意不列入**：它們是敘述性文件、不影響任何一項驗證，
> 而且補釘 SHA 時還會再動一次。把它們放進釘子只會製造假的「版本不符」。

## 2. 要跑的項目

**不會動你的 `~/.claude`。** 測試臺一律用假 `HOME` 在 temp 目錄操作、跑完自己清掉；
A-5 抽出來的舊 probe 用 `mktemp` ＋ `trap` 清理。
（A-1／A-5 受測的 probe 本身是唯讀的；A-7 受測的 `backup-settings` 會寫檔，
但只寫在測試臺開的假 `HOME` 裡。）

| # | 指令 | 期望 |
|---|---|---|
| **A-1** | `node tests/probe-gate-registration.test.js` | `TOTAL 42  PASS 42  FAIL 0`，exit 0 |
| **A-2** | `node "macos/skills/超級模式/tests/run-gate-tests.js"` | `PASS 117/117` |
| **A-3** | `node "macos/skills/超級模式/tests/matcher-contract.test.js"; echo "exit=$?"` | `exit=0`（此檔與 `main` 同 blob，跑它是為了確認改過的 `_comment` 沒破壞 JSON）|
| **A-4** | `bash tests/ai-install/run-posix.sh` | `PASS=68 FAIL=0`（**基準值，本批不該改變它**）|
| **A-5** | 反向驗證，見下方 §3 | `TOTAL 42  PASS 6  FAIL 36` |
| **A-6** | `node -e 'for (const p of ["windows","macos","linux"]) JSON.parse(require("fs").readFileSync(p+"/settings.snippet.json","utf8"))'` | 無輸出、exit 0 |
| **A-7** | `node tests/backup-settings.test.js` | `TOTAL 8  PASS 8  FAIL 0  SKIP 0`，exit 0 |

> ⚠️ **A-7 的 SKIP 數是重點，這一趟必須是 `SKIP 0`。**
> 有兩個案子在 Windows 上會標 SKIP，也就是那兩條守衛在該平台**沒有被驗到**：
>
> - `symlink-refused-and-no-partial` —— Windows 非管理員建不出 symlink
> - `copy-phase-failure-rolls-back` —— 靠 `chmod 000` 做變異注入，Windows 上擋不住讀取
>
> macOS 兩者都做得到（WSL2 上實測 `8 PASS / SKIP 0`），**所以你看到任何 SKIP 都要回報原因**，
> 不要當成通過。特別是第二條：它驗的是「複製階段失敗時會把本次建立的備份回收掉」，
> 也就是「全部成功，或什麼都沒留下」這個不變量。
> 若你是以 root 執行，`chmod 000` 擋不住讀取、注入會失效並自動標 SKIP —— 請改用一般帳號重跑。

> `node` 在你的機器上若不在 PATH（可攜式安裝），請用絕對路徑。回報時附 `node -v`。

## 3. A-5 反向驗證（**這一項最重要**）

新回歸案必須對**修正前**版本 FAIL，否則只是裝飾。把 `5cc50e0` 那版內嵌的 heredoc probe
抽出來，用 `--probe` 指向它：

```bash
set -euo pipefail
# 用 mktemp，**不要**寫死 /tmp/legacy-probe.js：固定路徑會覆寫既有檔、
# 會跟隨別人預先放好的 symlink，而且跑完不清理。
legacy=$(mktemp "${TMPDIR:-/tmp}/legacy-probe.XXXXXX.js")
trap 'rm -f "$legacy"' EXIT

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

**期望 `PASS 6  FAIL 36`**，而且通過的 6 個必須**恰為**這幾個對照組
（它們是行為刻意未改變的案子）：

```
ok-normal, ok-none-nongate-handler, ok-bom, ok-entry-without-hooks-key,
ok-gate-plus-unrelated-entry, ok-unrelated-exec-form
```

> ⚠️ **只核對 `FAIL 36` 這個數字不夠。** 請把完整的 FAIL 清單貼回來——
> 2026-08-08 就是因為只看總數，差點漏掉「失敗的不是該失敗的那幾條」。
> 特別留意 `top-null` 與 `pretooluse-object`：舊版對它們的**退出碼湊巧也是 1**
> （未捕捉的 TypeError），只有字串斷言抓得到差別。

## 4. 額外的唯讀診斷（做得到就做，會把「數字對」升級成「因為對的理由而對」）

1. **A-1 裡跟平台最相關的兩個案子**，印出實際訊息確認是因為預期的原因通過：
   - `read-error-directory` —— 在 BSD 上 `e.code` 實際是什麼？（斷言只比前綴，請回報實際值）
   - `halt-exec-form` —— 確認它是因為「偵測到 exec form」而 exit 3，不是碰巧被別的檢查攔到
2. **`os.homedir()` 的假 HOME 是否真的生效**：跑一次
   `HOME=/tmp/nonexistent-xyz node tools/probe-gate-registration.js`，
   應印「檔案不存在」兩行 ＋「兩邊都沒有 gate」，exit 0。
   若它讀到你**真正的**家目錄，那是測試臺的假 HOME 機制在 macOS 失效，**請立刻回報**。

## 5. 回報格式

```
環境：macOS <版本> <arch>／bash <版本>／node <版本>／Claude Code <版本>
blob：9 筆 全符 / 不符（列出）
A-1 ... A-7：實際輸出（數字 ＋ exit code）
A-5 的 FAIL 清單：完整貼上
A-7 的 SKIP 數（必須是 0）
§4 的兩項診斷：實際訊息
```

回報後我會把結果回寫到 README「本次 delta 的驗證分布」的 macOS 那一列，並把本檔標為已完成。
**在那之前，README 那一列會維持「撰寫當下未原生驗證」。**
