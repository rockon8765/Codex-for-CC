# P0-16 live 驗收 —— Windows 側（2026-08-28）

> 狀態：**Windows 側通過**；macOS 側**未做**（見文末「未涵蓋」）。
> 規格：[`exit-code-contract-plan-2026-08-19.md`](exit-code-contract-plan-2026-08-19.md) 的 **P0-16
> 「部署到 live（`docs/AI-INSTALL.md`）並跑 live suite」**，判準寫著「repo 改好 ≠ 生效；本輪就是被這個咬過」。
> 為什麼需要本檔：2026-08-28 的驗收材料原本只有 `matcher-contract --repo`，
> 而 `3b9dcb1` 已經證明過「live 標籤不等於 live 樹」——所以 `--repo` **不得**冒充 live。

## 1. Attestation（先講「驗的到底是哪一份」）

| 項目 | 值 |
|---|---|
| 分支 | `fix/exit-code-contract-closure-2026-08-28` |
| commit（受驗 tip） | `8b39f0b3c72ad1c065b3f0c0c625469fb9ae1cd4` |
| live 樹 | `C:\Users\user\.claude\skills\超級模式` |
| **live 樹 vs 分支 tip** | **19 個檔逐位元全數相符，0 不符；live 無多餘檔**（`.bak-*` 除外） |
| suite 自報 runner-root | `C:\Users\user\.claude\skills\超級模式\tests` ← 確認跑的是 live 樹 |
| suite 自報 sut-digest | `b0c254c066ea8589`（所有受測檔內容的 SHA-256 前 16 碼） |
| hook | 與 repo 相同，**未變更**、未重新部署 |

**「exact-tip」的意思**：不是「我複製了幾個檔」，而是**整棵 windows skill 樹逐檔比對過**。
只驗「我改的那幾個檔相符」不足以支撐 exact-tip 宣稱——其餘檔案可能早已漂移。

## 2. 部署內容與回滾

實際覆蓋 5 個檔（其餘 14 檔本來就相同）：

| 檔 | 動作 | 備份 |
|---|---|---|
| `scripts/codex-consult.ps1` | 覆蓋 | `.bak-20260828b` |
| `scripts/codex-exec.ps1` | 覆蓋 | `.bak-20260828b` |
| `SKILL.md` | 覆蓋 | `.bak-20260828b` |
| `tests/exit-code-contract.tests.ps1` | 新增 | —（原本不存在） |
| `tests/run-windows-suite.ps1` | 新增 | —（原本不存在） |

**回滾**：把三個 `.bak-20260828b` 覆蓋回原名，並刪除兩個新增檔。
⚠️ 尾碼刻意用 `b`：同日稍早的 `codex-check` 部署已用掉 `.bak-20260828`，不可覆蓋。

⚠️ **live 目前跑的是尚未 promote 的分支程式碼。** 這是 P0-16 的要求（先部署才驗得到），
但在 promote 前它就是這個狀態；不接受的話依上面回滾。

## 3. 結果

部署後先驗實體檔（四支 `.ps1`）：**語法錯誤數皆 0、BOM 皆 `EF BB BF`**。

| # | live 檢查 | 結果 |
|---|---|---|
| 1 | `run-gate-tests.js` | `PASS 109/109` |
| 2 | `matcher-contract.test.js --live` | `PASS` ＋ `RESULT_CODE=OK`；module sha256 `acbaeacf81c4f006` |
| 3 | `run-windows-suite.ps1 -Mode live` | `entries=10 ran=9 skipped=1 fail=0` ＋ **`SUITE_RESULT=OK`**、exit 0 |

第 3 項的逐項（皆 OK）：`gate-cases`、`matcher-contract`、`class-b-8dot3`、`consult-schema`、
`consult-credential-7`(pwsh 7.x)、`consult-credential-51`(WinPS 5.1)、`exit-contract-7`、
`exit-contract-51`、`codex-check`。
skipped 1 ＝ `no-multibyte-varref`（設計上只在 `-Mode repo` 跑，**不是**被靜靜略過——
suite 有印「因 mode 而未執行」）。

## 4. 判讀上的注意

- **`run-gate-tests` 在 Windows 是 109、在 macOS 是 117**，這是**平台樹本來就不同**，
  不是回歸。別把兩個數字並排比較後當成缺案。
- `SUITE_RESULT=OK` 只涵蓋 suite manifest 內的項目。**它不是「本批全部驗過」的同義詞**——
  本檔只結掉 P0-16 的 Windows 那一半。

## 5. 未涵蓋（不得誤讀為已驗）

1. **macOS 側的 live 驗收未做。** 需在原生 macOS 部署後跑該平台的 live 清單
   （含 `run-e2e.sh`、`exit-code-contract.smoke.sh`、`fault-injection.smoke.sh`）。
2. **Linux 側未做。**
3. 本檔不涵蓋 `325065c` 的 cleanup／暫存寫入行為之外的其他 exact-tip 動態證據——
   那由 [`fault-injection.smoke.sh`](../macos/skills/超級模式/tests/fault-injection.smoke.sh) 負責，
   而該支是 POSIX，**不在 Windows live 清單內**。
