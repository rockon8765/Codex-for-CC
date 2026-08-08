# HANDOFF — macOS 原生驗證：codex-check hooks 三態（2026-08-08）

> ## ⛔ 這份驗證已作廢，需要重跑（2026-08-08 更新）
>
> Mac 端在 `46e02bc` 上跑過一次並全綠，**但那之後 `macos/…/codex-check.sh` 又改了兩輪**
> （`09add04`、`f404eff`，以及 Codex 合併前審查 F4／F4b 的修正）。**blob 已不同，
> 舊結果對現在的 tip 不成立。**
>
> 沒有 macOS CI，這種「後續 commit 沒讓驗證狀態失效」正是會用過期證據放行的路徑。
> 待整批定稿後會重釘 SHA 與 blob 再發一次；**在那之前不要拿下方數字當通過依據**。
>
> 下方保留首次驗證的紀錄，僅供參考：
>
> **環境**：macOS 26.6.1 arm64、內建 `bash 3.2.57`、`awk version 20200816`
> （`/usr/bin/awk`）。**確認是 BSD／one-true-awk，不是 gawk** —— 正是本批要驗的 userland。
> 2 筆 blob 全符（**對 `46e02bc`，已非現行 tip**），`bash -n` 通過。
>
> | 步驟 | 結果 |
> |---|---|
> | 2-1 三個 hooks 案例 | **`TOTAL 10 FAIL 0`**，含 `b_hooks_unp`（舊行為保住）、`b_hooks_empty`、以及最關鍵的 `b_hooks_gone — hooks 消失必須報成漂移` |
> | 2-2 全套回歸 | **`TOTAL 126 FAIL 0`**，`^FAIL` 零行 |
> | 2-3 反向驗證 | **`FAIL 6`**（兩個新案例各 3 條），含 `b_hooks_gone — hooks 消失必須報成漂移`；兩條 PASS 是前置條件，符合「前置成立、判定失效」的預期形狀 |
>
> **我在 WSL2 跨宿主跑時 FAIL 的那 4 個 cache／mtime 案例，在原生 macOS 上全部通過**，
> 且 Mac 端貼了**正面證據**（逐條 `PASS: h4_future_mtime` 等），不是只給「沒有 FAIL」。
> 我先前「那是 `cp -R` 造成的環境問題、非本批回歸」的判定因此得到證實。
>
> `awk` 的 `[[:space:]]`／`next`／多重 `~` 比對在 one-true-awk 與 gawk 行為一致。
>
> **本檔自此僅作過程紀錄保留，不需要再執行。** 下方內文刻意不改寫。

> ## ⛔（歷史）不要安裝這個分支
> 只在 Windows 原生與 WSL2 跨宿主跑過，**macOS 未經真機驗證**。
> 全程在隔離 worktree 內，不要複製任何檔案進 `~/.claude`。

**待驗證的 SHA**：`46e02bc`（分支 `fix/codex-check-hardening-2026-08-08`，已推 origin）
**基準**：`origin/main` ＝ `1aeb010`

> 這份與 [`HANDOFF-macos-2026-08-08.md`](HANDOFF-macos-2026-08-08.md) 是**兩個獨立分支**，
> 可以在同一次 session 依序做完。兩者互不依賴。

---

## 0. 改了什麼

`codex-check` 的 hooks 盤點原本是兩態：「config 文字裡出現 `hooks.state` 且解析 0 筆
→ UNPARSEABLE」。使用者移除唯一提供 hook 的外掛後，config 會留下一張**合法的空表**
`[hooks.state]`，於是被判成格式失真。

後果不只是誤報：**「hooks 從 N 筆變 0 筆」這種真實的能力面變化會被藏進 UNKNOWN 段、
不報成漂移**。維護者機器上實測，修好後才出現 `hooks -: superpowers@openai-curated`。

改成三態（`macos/skills/超級模式/scripts/codex-check.sh`）：

- 有 `[hooks.state.<...>]` 子表頭但解析 0 筆，或裸 `[hooks.state]` 底下有非空非註解內容
  → **UNPARSEABLE**
- 完全沒有 `hooks.state`，或只有一張空的 `[hooks.state]` → **OK 且 0 筆**

**要 Mac 驗的原因**：判定改用 `awk`（`[[:space:]]`、`next`、多重 `~` 比對）。
BSD awk 與 GNU awk 的行為差異正是這裡要驗的——我只在 GNU 上跑過。

> Windows 版有另一項改動（印出實際使用的 codex 路徑）。那是 Windows 專屬
> （mac/linux 的腳本用 PATH 上的裸 `codex`，沒有硬編問題），**不在本次驗證範圍**。

---

## 1. 準備

```bash
cd <你的 Codex-for-CC clone>
git fetch origin
git worktree add /tmp/cfc-cc46 46e02bc
cd /tmp/cfc-cc46
git rev-parse --short HEAD          # 應為 46e02bc

for f in "macos/skills/超級模式/scripts/codex-check.sh" \
         "macos/skills/超級模式/tests/codex-check.tests.sh"
do printf '%s  %s\n' "$(git rev-parse "HEAD:$f" | cut -c1-12)" "$f"; done
```

預期：

| blob | 檔案 |
|---|---|
| `6784bfef7df2` | `macos/skills/超級模式/scripts/codex-check.sh` |
| `3a32a2bb1b30` | `macos/skills/超級模式/tests/codex-check.tests.sh` |

```bash
sw_vers -productVersion; uname -m
bash --version | head -1
awk --version 2>/dev/null | head -1 || echo "BSD awk（無 --version，正常）"
bash -n "macos/skills/超級模式/scripts/codex-check.sh" && echo "bash -n OK"
```

---

## 2. 測試

### 2-1 三個 hooks 案例（本批核心）

```bash
cd /tmp/cfc-cc46
bash "macos/skills/超級模式/tests/codex-check.tests.sh" \
  t_b_hooks_unparseable t_b_hooks_empty_table_is_zero t_b_hooks_removed_after_baseline
echo "exit=$?"
```

**預期 `TOTAL 10 FAIL 0`**，且必須包含這三條：

```
PASS: b_hooks_unp — hooks 報 UNPARSEABLE          ← 舊行為要保住，不能被改壞
PASS: b_hooks_empty — hooks 報 0 筆而非 UNPARSEABLE
PASS: b_hooks_gone — hooks 消失必須報成漂移        ← 本批最關鍵的一條
```

### 2-2 全套回歸

```bash
bash "macos/skills/超級模式/tests/codex-check.tests.sh" > /tmp/cc-mac.txt 2>&1; echo "exit=$?"
grep -E "^FAIL" /tmp/cc-mac.txt
tail -1 /tmp/cc-mac.txt
```

**預期 `TOTAL 126 FAIL 0`。**

> ⚠️ 誠實交代：我在 WSL2 跨宿主跑時有 **4 個 cache／mtime 案例 FAIL**
> （`h4_future_mtime`、`h4_newformat_cache` ×2、`b_cache_vermiss`）。
> 同環境下 **main 也是同樣 4 個**，所以我判定為環境造成（`cp -R` 產生的 mtime），
> 不是本批回歸。**在真 Mac 上它們應該要過。**
> 若這 4 個在 Mac 上也 FAIL，請照貼回報——那是新資訊，不要當成已知問題略過。

### 2-3 反向驗證（證明新案例不是裝飾）

```bash
cd /tmp/cfc-cc46
git checkout 1aeb010 -- "macos/skills/超級模式/scripts/codex-check.sh"
bash "macos/skills/超級模式/tests/codex-check.tests.sh" \
  t_b_hooks_empty_table_is_zero t_b_hooks_removed_after_baseline > /tmp/cc-red.txt 2>&1
echo "exit=$?"; grep -E "^(PASS|FAIL)" /tmp/cc-red.txt; tail -1 /tmp/cc-red.txt
git checkout HEAD -- "macos/skills/超級模式/scripts/codex-check.sh"
git status --porcelain          # 應為空
```

**預期 `FAIL 6`**——兩個新案例各 3 條，其中必須包含
`FAIL: b_hooks_gone — hooks 消失必須報成漂移`。

> ⚠️ 還原**一定要用 `git checkout HEAD -- <檔案>`**，不要 `cp` 備份蓋回去：
> `git checkout <sha> -- <檔案>` 會連 index 一起改，只還原工作目錄的話
> `git status` 仍會顯示 `M`。

---

## 3. 請貼回來

1. `sw_vers -productVersion`、`uname -m`、`bash --version` 首行、awk 那行
2. 2 筆 blob 核對
3. **2-1** 的完整輸出（10 行 PASS/FAIL ＋ TOTAL ＋ exit）
4. **2-2** 的 `TOTAL` 行、所有 `^FAIL` 行、exit
5. **2-3** 的 PASS/FAIL 列表、`TOTAL` 行、還原後 `git status --porcelain`

**原始輸出照貼，不要摘要。** 不符預期就停下回報，不要自己修。

## 4. 不要做

- 不要複製任何檔案進 `~/.claude`
- 不要 push／merge／開 PR／刪分支或 tag
- 2-3 跑完務必還原並確認 `git status --porcelain` 為空

## 5. 收工

```bash
cd <你的 clone>
git worktree remove /tmp/cfc-cc46 --force
git worktree prune
```
