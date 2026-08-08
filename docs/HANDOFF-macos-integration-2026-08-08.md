# HANDOFF — macOS 原生驗證（整合批，2026-08-08）

> ## ✅ 已完成（2026-08-08 同日回報，對 `319299c` 全綠）
>
> macOS 26.6.1 arm64／內建 `bash 3.2.57`／**`awk version 20200816`（BSD，非 GNU）**／Node v26.4.0。
> 9 筆 blob 全符，A-1～A-5 與 B-1～B-3 **每一項都與預期數字完全相符**：
> `run-posix` 85/85、gate 117/117、參數契約 3×exit 2、A-4 反向 `PASS=81 FAIL=4`（恰為 M11 四條）、
> probe 6 case 全符、B-1 `TOTAL 22 FAIL 0`、B-2 `TOTAL 138 FAIL 0`、B-3 `TOTAL 20 FAIL 13`。
>
> 結果與兩份補充診斷已回寫 [`settings-target-followup-2026-08.md`](settings-target-followup-2026-08.md) §4.6。
> **本檔自此僅作過程紀錄保留，不需要再執行。** 下方內文刻意不改寫。
>
> ⚠️ 本檔之後只會有**純文件** commit（回寫紀錄），不會動到上表任何一個 blob；
> 若日後有 commit 改到受測檔，這個「已完成」標記必須改回 pending。

> ## ⛔（歷史）不要安裝這個分支
> 只在 Windows 原生與 WSL2 跨宿主跑過，**macOS 未經真機驗證**。
> 全程在隔離 worktree 內，**不要**把任何檔案複製進 `~/.claude`。

**待驗證的 SHA**：`319299c`（分支 `integration/settings-target-and-codex-check-2026-08-08`）
**基準**：`origin/main` ＝ `1aeb010`

> **這份取代先前兩份**（`HANDOFF-macos-2026-08-08.md`、`HANDOFF-macos-codex-check-2026-08-08.md`）。
> 那兩份各自釘的 SHA 都已過時——Codex 合併前審查之後又改了受測檔。**只跑這一份。**
>
> 你先前已經驗過一次並全綠，感謝。**這次要重驗的原因是實質的**：審查抓到四條本批引進的
> 缺陷，其中一條（F1）是「照文件做會刪掉使用者僅存的 gate」。修正動到
> `AI-INSTALL`、`MIGRATION`、三平台 `matcher-contract`、以及 macOS 的 `codex-check.sh`。
>
> **任務 B（census）不用再做**——上次的結果已經回寫，不需要重跑。

---

## 0. 這次改了什麼（審查後）

| 代號 | 內容 |
|---|---|
| **F1** | `AI-INSTALL` 步驟 2 自抄的路由矩陣把「`settings.json`=0、`local`≥1」導向 B（純減法）→ **會刪掉僅存的 gate**。改成移除重複：只指向 `MIGRATION` §1 的 probe |
| **F2** | probe 與三平台 `matcher-contract` 判「已註冊」時強制 `type === "command"`（先前只比對 `command` substring）|
| **F4** | `codex-check` 的 hooks 盤點改成**單一 parser** 同時產出 items 與 evidence。先前 macOS 的 items 走 `sed`（不吃縮排）、evidence 走 `awk`（吃縮排且當已認得跳過）→ 縮排的 canonical 表頭「抽不到又不報」＝洗白，**且只發生在 macOS**——這是本批最需要你驗的一條 |
| **F5** | `codex-check` 的路徑輸出移到 24h cache gate 之前（Windows 專屬，不在本次範圍）|

---

## 1. 準備

```bash
cd <你的 Codex-for-CC clone>
git fetch origin
git worktree add /tmp/cfc-int 319299c
cd /tmp/cfc-int
git rev-parse --short HEAD          # 應為 319299c

for f in docs/AI-INSTALL.md \
         docs/MIGRATION-hook-settings-target.md \
         tests/ai-install/run-posix.sh \
         "macos/skills/超級模式/tests/matcher-contract.test.js" \
         macos/settings.snippet.json \
         "macos/skills/超級模式/references/orchestration.md" \
         macos/hooks/super-mode-consult-gate.js \
         "macos/skills/超級模式/scripts/codex-check.sh" \
         "macos/skills/超級模式/tests/codex-check.tests.sh"
do printf '%s  %s\n' "$(git rev-parse "HEAD:$f" | cut -c1-12)" "$f"; done
```

| blob | 檔案 |
|---|---|
| `051236b56da7` | `docs/AI-INSTALL.md` |
| `39dfad29b76f` | `docs/MIGRATION-hook-settings-target.md` |
| `9014e96d3f7c` | `tests/ai-install/run-posix.sh` |
| `9b5bf9607225` | `macos/skills/超級模式/tests/matcher-contract.test.js` |
| `408bd7320f74` | `macos/settings.snippet.json` |
| `63c9de27b380` | `macos/skills/超級模式/references/orchestration.md` |
| `f1781d6e59a0` | `macos/hooks/super-mode-consult-gate.js` |
| `a5d55154320d` | `macos/skills/超級模式/scripts/codex-check.sh` |
| `a6c3422ab99f` | `macos/skills/超級模式/tests/codex-check.tests.sh` |

```bash
sw_vers -productVersion; uname -m; bash --version | head -1
awk --version 2>/dev/null | head -1 || awk -W version 2>&1 | head -1
node --version
```

---

## 2. A 批 — settings-target

### A-1 主回歸

```bash
cd /tmp/cfc-int
bash tests/ai-install/run-posix.sh; echo "exit=$?"
```
**預期 `PASS=85 FAIL=0`、exit 0。**

### A-2 gate ＋ matcher-contract

```bash
node "macos/skills/超級模式/tests/run-gate-tests.js" | tail -1
node "macos/skills/超級模式/tests/matcher-contract.test.js" --repo; echo "exit=$?"
```
**預期 gate `PASS 117/117`；`--repo` exit 0，兩條受驗路徑都在 `/tmp/cfc-int/macos/…` 底下。**

> ℹ️ macOS 的 `/tmp` 是 symlink，會印成 `/private/tmp/cfc-int/…`。同一位置，不是問題。

### A-3 A1 參數契約

```bash
M="macos/skills/超級模式/tests/matcher-contract.test.js"
node "$M" --settings x >/dev/null 2>&1; echo "缺 --hook → exit=$?"
node "$M" --repo --live >/dev/null 2>&1; echo "併用 → exit=$?"
node "$M" --bogus >/dev/null 2>&1;      echo "未知旗標 → exit=$?"
node "$M" 2>&1 >/dev/null | head -1
node "$M" >/dev/null 2>&1; echo "無旗標 → exit=$?"
```
**預期：前三個 `exit=2`；第四行含 `deprecated`；最後 `exit=0`。**

### A-4 反向驗證

```bash
cd /tmp/cfc-int
git checkout 1aeb010 -- docs/AI-INSTALL.md
bash tests/ai-install/run-posix.sh > /tmp/rvA.txt 2>&1; echo "exit=$?"
grep "  FAIL" /tmp/rvA.txt; tail -1 /tmp/rvA.txt
git checkout HEAD -- docs/AI-INSTALL.md
git status --porcelain          # 應為空
```
**預期 `PASS=81 FAIL=4`，四條**恰為**：`[bak] 回滾中止`／`[bak] 被拒後 live 未變`／
`[live] 回滾中止`／`[live] 被拒後 live 未變`。

> ⚠️ 還原**一定要用 `git checkout HEAD -- <檔案>`**，不要 `cp` 備份蓋回去
> （`git checkout <sha> --` 會連 index 一起改，只還原工作目錄的話 `git status` 會殘留 `M`）。

### A-5 probe（**本次新增 type 判別，重點看這裡**）

把 `docs/MIGRATION-hook-settings-target.md` 第 1 節 `node - <<'PROBE'` … `PROBE`
中間那段存成 `/tmp/probe.js`，然後：

```bash
G='{"type":"command","command":"node ~/.claude/hooks/super-mode-consult-gate.js"}'
NT='{"command":"node ~/.claude/hooks/super-mode-consult-gate.js"}'
PT='{"type":"prompt","command":"node ~/.claude/hooks/super-mode-consult-gate.js"}'
i=0
for c in 'null' \
         '{"hooks":{"PreToolUse":{"m":1}}}' \
         '{"hooks":{"PreToolUse":"super-mode-consult-gate"}}' \
         "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Write\",\"hooks\":[$NT]}]}}" \
         "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Write\",\"hooks\":[$PT]}]}}" \
         "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Write\",\"hooks\":[$G]}]}}"
do
  i=$((i+1)); H=$(mktemp -d); mkdir -p "$H/.claude"; printf '%s' "$c" > "$H/.claude/settings.json"
  HOME="$H" node /tmp/probe.js >/dev/null 2>&1; echo "case $i → exit=$?"
done
```
**預期：case 1–5 皆 `exit=1`（第 4 是缺 `type`、第 5 是 `type:"prompt"`）；case 6（對照組）`exit=0`。**

---

## 3. B 批 — codex-check hooks（**BSD awk 是重點**）

### B-1 三組 hooks 案例

```bash
cd /tmp/cfc-int
bash "macos/skills/超級模式/tests/codex-check.tests.sh" \
  t_b_hooks_unparseable t_b_hooks_empty_table_is_zero \
  t_b_hooks_removed_after_baseline t_b_hooks_alt_serializations
echo "exit=$?"
```
**預期 `FAIL 0`。** 其中這幾條務必出現且 PASS：

```
b_hooks_gone — hooks 消失必須報成漂移
b_hooks_alt — [trailing-comment] 必須 UNPARSEABLE
b_hooks_alt — [mixed-good-and-bad] 必須 UNPARSEABLE（不可因 items>0 而略過形跡）
b_hooks_alt — 縮排 canonical 表頭仍抽成 1 筆        ← macOS 專屬，先前只有這個平台會洗白
b_hooks_alt — 對照組：空表+註解仍是 0 筆            ← 證明上面不是「一律 UNPARSEABLE」
```

### B-2 全套回歸

```bash
bash "macos/skills/超級模式/tests/codex-check.tests.sh" > /tmp/ccB.txt 2>&1; echo "exit=$?"
grep -E "^FAIL" /tmp/ccB.txt; tail -1 /tmp/ccB.txt
```
**預期 `TOTAL 138 FAIL 0`。**

> ⚠️ 我在 WSL2 跨宿主跑時有 4 個 cache／mtime 案例 FAIL
> （`h4_future_mtime`、`h4_newformat_cache` ×2、`b_cache_vermiss`）。
> 你上次在原生 Mac 上證實它們會過。**若這次仍 FAIL，請照貼回報**——那是新資訊。

### B-3 反向驗證

```bash
cd /tmp/cfc-int
git checkout 1aeb010 -- "macos/skills/超級模式/scripts/codex-check.sh"
bash "macos/skills/超級模式/tests/codex-check.tests.sh" \
  t_b_hooks_empty_table_is_zero t_b_hooks_removed_after_baseline t_b_hooks_alt_serializations \
  > /tmp/rvB.txt 2>&1; echo "exit=$?"
grep -cE "^FAIL" /tmp/rvB.txt; tail -1 /tmp/rvB.txt
git checkout HEAD -- "macos/skills/超級模式/scripts/codex-check.sh"
git status --porcelain          # 應為空
```
**預期 `TOTAL 20 FAIL 13`。**

---

## 4. 請貼回來

1. 環境四行（`sw_vers`、`uname -m`、`bash --version`、`awk` 版本、`node --version`）
2. 9 筆 blob 核對
3. **A-1**～**A-5** 各自的數字／exit code；A-4 要附四條 FAIL 原文與還原後的 `git status --porcelain`
4. **B-1** 完整輸出、**B-2** 的 `TOTAL` 行與所有 `^FAIL` 行、**B-3** 的 FAIL 數與 `TOTAL` 行
5. B-3 還原後的 `git status --porcelain`

**原始輸出照貼，不要摘要。** 不符預期就停下回報，不要自己修。

## 5. 不要做

- 不要複製任何檔案進 `~/.claude`；不要照 `AI-INSTALL.md` 安裝
- 不要 push／merge／開 PR／刪任何分支或 tag
- 反向驗證跑完務必 `git checkout HEAD -- <檔案>` 還原並確認 `git status --porcelain` 為空

## 6. 收工

```bash
cd <你的 clone>
git worktree remove /tmp/cfc-int --force
git worktree prune
```
