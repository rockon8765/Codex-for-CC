# macOS 原生驗證交接 —— 憑證鑄造判準（2026-08-18）

**這批在 macOS 原生綠之前不得併入 `main`。** Windows 與 Linux 綠**不能**代替：
本批動到 `bash 3.2`、`mktemp`、`uuidgen`、`node` 的 PATH 解析、pipeline 的 `PIPESTATUS`、
以及 `os.replace` 換檔，這五件事全都是平台語義。

---

## 0. 要驗的是哪一版

⚠️ **釘 blob 不釘 SHA。** 補釘 SHA 的 commit 自己會讓尖端前進，回頭看就對不上。
下表七個 blob 是本批的受測面；跑之前先核對，**有任何一筆不符就停下來回報，不要硬跑**。

在 checkout 根目錄執行：

```bash
for f in \
  macos/skills/超級模式/lib/consult-answer.js \
  macos/skills/超級模式/scripts/codex-consult.sh \
  macos/skills/超級模式/tests/consult-credential.tests.sh \
  macos/skills/超級模式/SKILL.md \
  tests/consult-answer.test.js \
  tests/consult-answer-teeth.test.js \
  tests/gate-registration.test.js \
; do printf '%s  %s\n' "$(git hash-object "$f")" "$f"; done
```

⚠️ **本文刻意不列預期 blob 值。** 先前版本只填了一筆、其餘六筆寫「請交接者補上」——
那等於要求對照一份不存在的表，六筆根本無從判斷「相符」。改成**自我一致的檢查**：

```bash
# 1) 你在正確的分支上
git rev-parse --abbrev-ref HEAD     # 應為 feat/consult-answer-validity-2026-08-18-pending-native-macos
git log --oneline -1

# 2) 三平台的 validator 必須逐位元相同（這是本批最重要的不變量）
for p in windows macos linux; do git hash-object "$p/skills/超級模式/lib/consult-answer.js"; done | sort -u | wc -l
#    → 必須輸出 1

# 3) 工作樹乾淨（沒有人手改過受測檔）
git status --porcelain
#    → 必須沒有輸出
```

三項都成立就可以往下跑。**不成立就停下來回報**，不要硬跑。

---

## 1. 環境資料（請一併回報，不是選填）

```bash
sw_vers
uname -m
/bin/bash --version | head -1        # 預期 3.2.x —— 這是本批最主要的相容性風險
command -v node && node --version
command -v uuidgen || echo "no uuidgen"
command -v python3 && python3 --version
echo "TMPDIR=${TMPDIR:-<unset>}"
```

⚠️ 若 `/bin/bash` **不是** 3.2（例如你把 bash 5 放到前面），請額外用 `/bin/bash` 明確再跑一次
第 3 節：這批的 macOS 價值有一半在「bash 3.2 也成立」。

---

## 2. 先跑三支 node 測試（平台無關，應與其他平台同數字）

```bash
node tests/consult-answer.test.js
```
預期尾行 `CONSULT-ANSWER 31/31`，`echo $?` = 0。

```bash
node tests/consult-answer-teeth.test.js
```
預期尾行 `CONSULT-ANSWER-TEETH 21/21`，`echo $?` = 0。
（這支會**暫時覆寫**
`windows/skills/超級模式/lib/consult-answer.js` 再還原，最後一案就是「還原後仍全綠」。
跑完請 `git status --short` 確認工作樹乾淨。）

```bash
node tests/gate-registration.test.js
```
預期尾行 `TOTAL 171  PASS 171  FAIL 0  SKIP 0`。

---

## 3. 主戲：caller 整合測試（假 codex ＋ 假 HOME，不碰你真的 `~/.claude`）

```bash
bash macos/skills/超級模式/tests/consult-credential.tests.sh
```

預期尾行 `CONSULT-CREDENTIAL 19/19`，`echo $?` = 0。

**逐案在驗什麼**（不是只看總數——請把有 FAIL 的具名案例貼回來）：

| 節 | 驗的東西 | 為什麼 macOS 特別要驗 |
|---|---|---|
| §1 | ALLOW 合格 → exit 0、憑證存在、內容綁 repo | `os.replace` 換檔在 APFS 上 |
| §2 | **BLOCK 一樣鑄造**，但 stdout 要講「裁決為 BLOCK」 | 憑證是收據不是授權（見 SKILL §3.5） |
| §3 | 不合格 → 43，且**既有憑證的內容與 mtime 都不變** | `stat -f %m`（BSD）vs `ls --time-style`（GNU）的分支在這裡 |
| §4 | 空回覆、無裁決首行 → 43 | — |
| §5 | 討論模式短回覆放行但**不鑄造**、空的仍 43 | — |
| §6 | codex 自己失敗 → 沿用退出碼、不鑄造 | `PIPESTATUS` 在 bash 3.2 |
| §7 | `SUPER_MODE_NODE` 無效 → **45**、不鑄造 | fail-closed 不靜默退回 PATH |

⚠️ §3 的 mtime 檢查在 macOS 走 `stat -f %m` 分支（Linux 走 `ls --time-style=+%s`）。
**若 §3d 失敗，先確認不是 `stat` 的用法問題再判定是產品 bug** —— 把
`stat -f %m <token>` 的實際輸出貼回來。

---

## 4. 既有回歸（確認沒弄壞別的）

```bash
bash macos/skills/超級模式/tests/consult-schema.tests.sh
node macos/skills/超級模式/tests/run-gate-tests.js
node macos/skills/超級模式/tests/matcher-contract.test.js
bash macos/skills/超級模式/tests/run-e2e.sh
bash tests/ai-install/run-posix.sh
```

⚠️ **這五支不是同一類，別一句話帶過**（先前版本寫「四支」卻列了五支，還宣稱本批沒動
它們涵蓋的檔——那是錯的）：

- `consult-schema.tests.sh` **直接涵蓋本批改過的 `codex-consult.sh`**（schema 參數處理那段
  我改了：JSON 檢查從 `node -e` 內嵌腳本換成 validator 的 `--check-json`）。
  ⇒ **它的數字有可能合理變動**，請把實際輸出貼回來，不要當成「應該不變」。
- 其餘四支（`run-gate-tests.js`、`matcher-contract.test.js`、`run-e2e.sh`、
  `tests/ai-install/run-posix.sh`）本批**沒有動**它們涵蓋的檔，數字應該與你這台上一次的
  紀錄相同（`docs/` 內既有 handoff 有歷史值）。**若有變動，那才是要回報的訊號。**

---

## 5. 一個手動的真實檢查（可選，但很有價值）

前面全部用假 codex。若你願意燒一次真的諮詢：

```bash
# 隨便寫一份簡報
printf '首行請回 ALLOW: 然後隨便說幾句。\n' > /tmp/brief.md
bash macos/skills/超級模式/scripts/codex-consult.sh -d "$PWD" -n -f /tmp/brief.md
echo "rc=$?"
```

`-n` 是討論模式，**不會鑄造憑證**，所以不影響你機器上的 gate 狀態。
預期：正常回答 → rc=0；若 codex 回空的 → rc=43 並印 `CONSULT_UNUSABLE_ANSWER`。

---

## 6. 回報格式

請貼回：

1. 第 1 節的環境資料原文。
2. 第 0 節 blob 比對結果（相符／哪一筆不符）。
3. 第 2、3、4 節每一支的**尾行**與 `echo $?`。
4. 任何 FAIL 的**具名案例全文**（測試會印 `FAILED-CASE: <名稱>` 行，直接貼那些行）。
5. 第 5 節若有跑，貼 rc 與訊息。

⚠️ **不要只回報「都過了」**——請貼實際輸出。本 repo 反覆吃過「綠燈但其實沒跑到」的虧。

---

## 7. 已知的、預期會不同的地方

- `uuidgen` 在 macOS 一定存在，所以不會走到 `/dev/urandom` 的 fallback 分支。
  **那條 fallback 是為精簡 Linux 映像加的，macOS 驗不到它，這是預期的。**
- `TMPDIR` 在 macOS 是 `/var/folders/...` 而非 `/tmp`。測試全部用 `${TMPDIR:-/tmp}`，
  路徑會長得不一樣，但不影響判定。
- 第 3 節的 §7 會印一段 `CONSULT_VALIDATOR_UNAVAILABLE` 到 stderr，**那是預期的**
  （測試在故意把 `SUPER_MODE_NODE` 指到不存在的路徑）。
