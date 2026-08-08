# HANDOFF — macOS 原生驗證 ＋ 三台 census（2026-08-08 批）

> ## 🔀 已被取代（2026-08-08）
>
> **請改用 [`HANDOFF-macos-integration-2026-08-08.md`](HANDOFF-macos-integration-2026-08-08.md)**（釘 `319299c`）。
> 那份把兩批合成一次驗證，並已納入 Codex 合併前審查後的修正。本檔僅作過程紀錄保留。


> ## ⛔ 這份驗證已作廢，需要重跑（2026-08-08 更新）
>
> Mac 端在 `224ad8e` 上跑過一次並全綠，**但那之後 Codex 合併前審查（F1／F2）又改了
> `docs/AI-INSTALL.md`、`docs/MIGRATION-hook-settings-target.md` 與三平台
> `matcher-contract.test.js`**——其中 F1 是「照文件做會刪掉使用者僅存的 gate」的 P0。
> **blob 已不同，舊結果對現在的 tip 不成立。**
>
> 沒有 macOS CI，「後續 commit 沒讓驗證狀態失效」正是會用過期證據放行的路徑。
> 待整批定稿後會重釘 SHA 與 blob 再發一次；**在那之前不要拿下方數字當通過依據**。
>
> 下方保留首次驗證的紀錄（對 `224ad8e`，已非現行 tip），僅供參考：
>
> ## （首次驗證）2026-08-08 同日回報
>
> macOS 26.6.1 (25G76) arm64／內建 `bash 3.2.57`／Node v26.4.0／Claude Code 2.1.220。
> **7 筆 blob 全符，A-1～A-5 與任務 B 八項全數符合預期**：
> `run-posix.sh` **85/85**、gate **117/117**、`matcher-contract --repo` exit 0、
> 參數契約 3×`exit 2`、反向驗證 **PASS=81 FAIL=4** 且恰為 M11 那四條、probe 4 輸入全符。
>
> 結果與 census 已回寫 [`settings-target-followup-2026-08.md`](settings-target-followup-2026-08.md) §4.4。
> **本檔自此僅作過程紀錄保留，不需要再執行。** 下方內文刻意不改寫。

> ## ⛔（歷史）不要安裝這個分支
>
> 本批的改動**只在 Windows 與 WSL2 上跑過**，macOS 未經真機驗證。
> **不要**把這個分支的檔案複製進 `~/.claude/`，**不要**照 `docs/AI-INSTALL.md` 安裝它。
> 這份 handoff 要做的是：在**隔離的 worktree 裡**跑測試、外加一組**唯讀**的環境盤點，
> 把**原始輸出**貼回來。驗證通過後由 Windows 端 promote，那時才輪到部署。

**待驗證的 SHA**：`224ad8e`（分支 `fix/settings-target-successor-2026-08-08`，已推 origin）
**基準**：`origin/main` ＝ `1aeb010`

> ⚠️ **任務 B（census）會讀 `~/.claude`。** 依 [`AGENTS.md`](../AGENTS.md) 的 worker guard，
> 那一段**只能由你本人執行**，不可以派給一般 coding worker。任務 A 全程在 worktree 內，不受此限。

---

## 0. 這批改了什麼（讀懂再驗，別只照指令跑）

| 代號 | 內容 | 為什麼需要 macOS 驗 |
|---|---|---|
| **B1** | 回滾**前**遞迴掃「備份子樹」與「live 子樹」的內嵌 link；舊版預檢只驗頂層，於是先刪 live、再從錯誤拓撲還原 | 改的是 `AI-INSTALL.md` 裡 **BSD `bash 3.2` 會實際執行**的 code block。GNU 專屬語義在 WSL2 會全綠、在 Mac 直接爆——這個 repo 有前例 |
| **A2** | `MIGRATION` 第 1 節 probe 逐層驗形狀、異形 `exit 1`；第 2 節改 handler 粒度並拆 A／B 兩支 | probe 是 `node`，跨平台；但 10 處註冊入口含 macOS snippet 與 orchestration |
| **A1** | `matcher-contract.test.js` 加 `--repo`／`--live`／`--settings`＋`--hook`，並印出實際受驗的兩條路徑 | 三平台同一支檔（同一 blob），macOS 版要確認在 BSD 環境行為一致 |
| **C／D** | ECC 具名斷言撤下並泛化；公開狀態一致性 | 純文件 |

**三個真 bug 都有反向驗證**（Windows／Linux 已做，見 `docs/settings-target-followup-2026-08.md` §4.1–4.3）。

---

## 1. 準備（隔離，不碰你的 `~/.claude`）

```bash
cd <你的 Codex-for-CC clone>
git fetch origin
git worktree add /tmp/cfc-0808 224ad8e
cd /tmp/cfc-0808
git rev-parse HEAD            # 應為 224ad8e… 的完整 SHA
```

**先核對 blob**（確認你手上的檔案就是我驗過的那份）：

```bash
for f in \
  docs/AI-INSTALL.md \
  docs/MIGRATION-hook-settings-target.md \
  tests/ai-install/run-posix.sh \
  "macos/skills/超級模式/tests/matcher-contract.test.js" \
  macos/settings.snippet.json \
  "macos/skills/超級模式/references/orchestration.md" \
  macos/hooks/super-mode-consult-gate.js
do printf '%s  %s\n' "$(git rev-parse "HEAD:$f" | cut -c1-12)" "$f"; done
```

預期：

| blob | 檔案 |
|---|---|
| `d0781cbd4b48` | `docs/AI-INSTALL.md` |
| `9166203df00e` | `docs/MIGRATION-hook-settings-target.md` |
| `9014e96d3f7c` | `tests/ai-install/run-posix.sh` |
| `f43319511a0e` | `macos/skills/超級模式/tests/matcher-contract.test.js` |
| `bcaf60b6c022` | `macos/settings.snippet.json` |
| `63c9de27b380` | `macos/skills/超級模式/references/orchestration.md` |
| `f1781d6e59a0` | `macos/hooks/super-mode-consult-gate.js` |

**環境資訊也請一併回報**（不同 userland 是這份 handoff 存在的理由）：

```bash
sw_vers
bash --version | head -1
which -a bash          # 確認用的是內建 /bin/bash 3.2，不是 Homebrew 5.x
node --version
```

---

## 2. 任務 A — 測試（全在 worktree 內）

### A-1 主回歸

```bash
cd /tmp/cfc-0808
bash tests/ai-install/run-posix.sh; echo "exit=$?"
```

**預期：`PASS=85  FAIL=0`、`exit=0`。**

> ⚠️ 這一項最關鍵。新增的 `[M11]`／`[M12]` 用 `ln -s`、`find -type l` 與 `cp -R`，
> 這些在 BSD 與 GNU 的行為差異正是本次要驗的東西。

### A-2 gate 與 matcher-contract

```bash
node "macos/skills/超級模式/tests/run-gate-tests.js" | tail -1; echo "exit=${PIPESTATUS[0]}"
node "macos/skills/超級模式/tests/matcher-contract.test.js" --repo; echo "exit=$?"
```

**預期：gate `PASS 117/117`；`matcher-contract --repo` exit 0，且印出的兩條路徑都在 `/tmp/cfc-0808/macos/…` 底下。**

### A-3 A1 的參數契約

```bash
M="macos/skills/超級模式/tests/matcher-contract.test.js"
node "$M" --settings x; echo "缺 --hook → exit=$?"
node "$M" --repo --live; echo "併用 → exit=$?"
node "$M" --bogus;       echo "未知旗標 → exit=$?"
node "$M" 2>&1 >/dev/null | head -1; echo "無旗標的 stderr 首行（應含 deprecated）"
node "$M" >/dev/null 2>&1; echo "無旗標 → exit=$?"
```

**預期：前三個都 `exit=2`；無旗標 stderr 首行含 `deprecated`、`exit=0`。**

### A-4 反向驗證（證明新案例不是裝飾）

```bash
cd /tmp/cfc-0808
git checkout 1aeb010 -- docs/AI-INSTALL.md         # 換成修正前的版本
bash tests/ai-install/run-posix.sh > /tmp/red.txt 2>&1; echo "exit=$?"
grep "  FAIL" /tmp/red.txt
tail -1 /tmp/red.txt
git checkout HEAD -- docs/AI-INSTALL.md            # 還原
git status --porcelain                             # 應為空
git hash-object docs/AI-INSTALL.md | cut -c1-12    # 應為 d0781cbd4b48
```

> ⚠️ 還原**一定要用 `git checkout HEAD -- <檔案>`，不要用 `cp` 備份再蓋回去**。
> `git checkout <sha> -- <檔案>` 會**連 index 一起改**，只把工作目錄檔案 `cp` 回來的話
> `git status` 仍會顯示 `M docs/AI-INSTALL.md`——會讓你誤以為自己弄壞了什麼。
> （2026-08-08 在 WSL2 實測過這個陷阱，所以這裡寫死正確做法。）

**預期：`PASS=81  FAIL=4`，且四條 FAIL 恰為**

```
  FAIL  [bak] 回滾中止
  FAIL  [bak] 被拒後 live 未變
  FAIL  [live] 回滾中止
  FAIL  [live] 被拒後 live 未變
```

> 若 FAIL 數不是 4、或出現上面四條以外的項目，**停下來回報**，不要自行判斷。

### A-5 A2 probe（可選但很快）

把 `docs/MIGRATION-hook-settings-target.md` 第 1 節的 `node - <<'PROBE'` … `PROBE`
中間那段存成 `/tmp/probe.js`，然後用**假 HOME** 餵四種輸入：

```bash
for c in 'null' '{"hooks":{"PreToolUse":{"m":1}}}' '{"hooks":{"PreToolUse":"super-mode-consult-gate"}}' \
         '{"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"command":"node ~/.claude/hooks/super-mode-consult-gate.js"}]}]}}'
do
  H=$(mktemp -d); mkdir -p "$H/.claude"; printf '%s' "$c" > "$H/.claude/settings.json"
  HOME="$H" node /tmp/probe.js >/dev/null 2>&1; echo "exit=$?  <- $c"
done
```

**預期：前三個 `exit=1`，最後一個（對照組）`exit=0`。**

---

## 3. 任務 B — census（**唯讀**，只能你本人跑）

目的：確認「2026-07-28 以前安裝、手上 verifier 是會假綠的舊版」這種情況在我們三台裡實際存不存在。
**這只是三個具名樣本，不能外推到所有使用者**——但它決定 A1 要不要保留「舊 installed verifier fixture」。

```bash
# 全部唯讀，不會改任何東西
sw_vers -productVersion; uname -m
claude --version 2>/dev/null || echo "claude 不在 PATH"

# 1) 已安裝的 verifier 是哪一版
ls -l ~/.claude/skills/超級模式/tests/matcher-contract.test.js 2>/dev/null \
  && git hash-object ~/.claude/skills/超級模式/tests/matcher-contract.test.js

# 2) 它是不是「含 settings.local 候選」的舊版（會假綠的那種）
grep -c 'settings\.local\.json' ~/.claude/skills/超級模式/tests/matcher-contract.test.js 2>/dev/null

# 3) 兩個 settings 各有幾筆 gate handler —— 用 worktree 裡的**新** probe，不要用已安裝那份
#    （把 MIGRATION 第 1 節的 probe 存成 /tmp/probe.js，同任務 A-5）
node /tmp/probe.js; echo "exit=$?"

# 4) hook 本體
ls -l ~/.claude/hooks/super-mode-consult-gate.js 2>/dev/null \
  && git hash-object ~/.claude/hooks/super-mode-consult-gate.js
```

**Windows 端（維護者本機）已完成，貼在這裡當範例與對照：**

| 欄位 | 值 |
|---|---|
| OS | Windows 11 專業版 10.0.26200.0 |
| Claude Code | 2.1.220 |
| installed `matcher-contract` blob | `5edaa7efe4fd3e5ebac79442c4b01d106463d4df` |
| 是否為含 `settings.local` 候選的舊版 | **否**（已是移除 local 候選後的版本）|
| `settings.json` gate handler | **1** |
| `settings.local.json` | **不存在** |
| probe 判定／exit | 「正常，不用修。」／`0` |

---

## 4. 請貼回來的東西

1. `sw_vers`、`bash --version` 首行、`which -a bash`、`node --version`
2. blob 核對表（7 筆，符不符）
3. **A-1** 最後一行（含數字）＋ `exit=`
4. **A-2** gate 最後一行、`matcher-contract --repo` 的**完整輸出**（含它印的兩條路徑）＋ exit
5. **A-3** 五個 exit code
6. **A-4** `PASS=/FAIL=` 那行 ＋ 四條 FAIL 的原文 ＋ 還原後 `git status --porcelain`（應空）與 `git hash-object` 的值
7. **A-5**（若有跑）四個 exit code
8. **任務 B** 的六項輸出

**原始輸出照貼，不要摘要**。任何一項與預期不符，先貼回來再說，不要自己「修一下讓它過」。

---

## 5. 明確不要做

- 不要 `cp -R` 任何東西到 `~/.claude/`
- 不要照 `AI-INSTALL.md` 安裝這個 worktree
- 不要改 `~/.claude/settings.json` 或 `settings.local.json`（任務 B 全程唯讀）
- 不要 push、不要 merge、不要刪任何分支或 tag
- A-4 跑完務必用 `git checkout HEAD -- docs/AI-INSTALL.md` 還原，並確認 `git status --porcelain` 為空

## 6. 收工

```bash
cd <你的 clone>
git worktree remove /tmp/cfc-0808 --force
git worktree prune
```

驗證結果由 Windows 端回寫進 [`settings-target-followup-2026-08.md`](settings-target-followup-2026-08.md)，
再走 Codex 合併前審查 → `git fetch` 復驗 → 徵得維護者同意 → 併入 `main`。
