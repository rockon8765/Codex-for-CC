# macOS 原生驗證交接單（退出碼契約批次，2026-08-19）

分支：`fix/exit-code-contract-2026-08-19-pending-native-macos`
規畫書：[`exit-code-contract-plan-2026-08-19.md`](exit-code-contract-plan-2026-08-19.md)（§9 是目前的未決清單）

## 為什麼需要原生驗證

開發機是 Windows，POSIX 那半只在 **Git Bash（bash 5.3 / Cygwin）** 跑過。
這批改動**大量依賴 shell 與 userland 的細節**，而那正是 Git Bash 與 macOS 不同的地方：

- macOS 的 `/bin/bash` 是 **3.2**（2007 年的版本），Git Bash 是 5.3。
- `tee`／`chmod`／`grep`／`tr`／`head` 是 **BSD** 而非 GNU。
- 本批用到 here-string、`PIPESTATUS` 整包複製、`grep -E` 的字元類、
  子 shell 重導向的退出碼語意 —— 每一項都可能在 3.2 / BSD 下不同。

開發過程中已經有**兩個**缺陷是「`bash -n` 語法檢查完全看不出來、實跑才抓到」的
（`PIPESTATUS` 被賦值重設、`{ } >> file` 重導向失敗仍回 0）。所以請**實跑**，不要只看語法。

## 安全性（先講，免得你擔心）

下面的測試：

- **不會碰到真的 codex**。POSIX 版呼叫的是 PATH 上的裸 `codex`，測試用 stub 目錄攔截。
- **不會碰到你的 `~/.claude`**。每個案子都把 `HOME` 換成 `mktemp -d` 出來的假家目錄。
- **不會改到 repo**。只讀。

## 請執行

```bash
git clone https://github.com/rockon8765/Codex-for-CC.git /tmp/cfc-verify 2>/dev/null || true
cd /tmp/cfc-verify && git fetch origin && git checkout fix/exit-code-contract-2026-08-19-pending-native-macos && git pull

echo "===== 環境 attestation ====="
uname -a
echo "PATH bash : $(command -v bash) -> $(bash --version | head -1)"
echo "/bin/bash : $(/bin/bash --version | head -1)"
echo "node      : $(node --version 2>/dev/null || echo '缺 node（gate 測試會跑不了）')"
echo "grep      : $(grep --version 2>&1 | head -1)"

echo
echo "===== A. 退出碼契約 smoke（用 /bin/bash 3.2 跑，這是重點）====="
/bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh

echo
echo "===== B. 同一支，用 PATH 上的 bash 再跑一次 ====="
bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh

echo
echo "===== C. 既有 gate 測試（確認沒被弄壞）====="
node macos/skills/超級模式/tests/run-gate-tests.js
node macos/skills/超級模式/tests/matcher-contract.test.js --repo

echo
echo "===== D. 安裝流程測試臺（Windows 上因為建不了 symlink 有 30 個假 FAIL，Mac 上應該要能跑）====="
bash tests/ai-install/run-posix.sh 2>&1 | tail -5
```

## 期望結果

| 區塊 | 期望 |
|---|---|
| A（/bin/bash 3.2） | `exit-code-contract.smoke: pass=19 fail=0` |
| B（PATH bash） | 同上 |
| C | `PASS 117/117`（或更高）＋ `RESULT_CODE=OK` |
| D | 以 Mac 上的實際數字為準；**重點是 symlink 那幾案不再是環境性失敗** |

## 然後請跑兩個「變異注入」——證明測試真的有牙齒

綠燈本身不是證據。這兩個 mutant 對應本批修掉的兩個**靜默**缺陷，
如果它們在 Mac 上**沒有變紅**，代表守衛在 3.2/BSD 下是空的，那比全綠更需要知道。

```bash
cd /tmp/cfc-verify

echo "===== M1: 把 SIGPIPE 修法退回管線寫法（期望：4h/4i 變紅）====="
cp macos/skills/超級模式/scripts/codex-consult.sh /tmp/m1.bak
perl -0pi -e 's/if grep -qiE "\$quota_re" <<< "\$err_lines"; then/if printf \x27%s\\n\x27 "\$err_lines" | grep -qiE "\$quota_re"; then/' \
  macos/skills/超級模式/scripts/codex-consult.sh
/bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh | tail -6
cp /tmp/m1.bak macos/skills/超級模式/scripts/codex-consult.sh

echo
echo "===== M2: 把子 shell 重導向守衛退回複合命令（期望：4b 變紅）====="
cp macos/skills/超級模式/scripts/codex-consult.sh /tmp/m2.bak
perl -0pi -e 's/if ! \( \{ echo "===== STDERR ====="; printf \x27%s\\n\x27 "\$stderr_text"; \} >> "\$log" \) 2>\/dev\/null; then/if ! { echo "===== STDERR ====="; printf \x27%s\\n\x27 "\$stderr_text"; } >> "\$log" 2>\/dev\/null; then/' \
  macos/skills/超級模式/scripts/codex-consult.sh
/bin/bash macos/skills/超級模式/tests/exit-code-contract.smoke.sh | tail -6
cp /tmp/m2.bak macos/skills/超級模式/scripts/codex-consult.sh

git status --short   # 應該是乾淨的；不乾淨代表還原失敗，請 git checkout -- .
```

**M1 期望**：`4h 大量 quota ERROR 仍要判成 42` 與 `4i` 變紅。
**M2 期望**：`4b 訊息附上逐字稿不完整診斷` 變紅。

> ⚠️ 若某個 mutant 在 Mac 上**沒有**變紅，請照實回報 —— 那代表該守衛在 3.2/BSD 下沒有作用，
> 是比「全綠」更重要的發現。**不要**因為它沒紅就當作沒事。

## 回報什麼

把上面每一區塊的**尾行**貼回來就好，另外請特別說明：

1. `/bin/bash` 的版本（應該是 3.2.x）
2. A 和 B 的結果**是否一致**（不一致代表有 bash 版本相依）
3. 兩個 mutant **有沒有**照預期變紅
4. D 區塊在 Mac 上的實際數字

## 本批還沒做的事（不在你這輪的驗證範圍）

見規畫書 §9.2。摘要：分類器對「含 quota 字樣但與配額無關的錯誤行」仍會誤判
（缺真配額樣本，無法校準）、log 目錄建立仍在 exit 46 契約之外、
POSIX `codex-exec.sh` 的 `-q` 分支 transport 未修、Linux CI 只跑 `bash -n`。
