# Handoff：能力面 baseline diff 移植（macOS / Linux）

**狀態**：Windows 已實作；合成測試臺全綠（codex-check 47 案＋gate-cases 90/90，數字以 repo 測試檔為準），
並經 Workflow 三鏡頭對抗審查（17 發現/14 confirmed 全數修復或裁決）＋一次真 codex live `-Force` E2E。
**Windows 原生 7 項 promote gate 尚未跑**（分支名 `-windows-pending-native`；promote 前須照
`handoff-codex-check-windows-native-gate.md` 慣例補跑）。mac/linux 的 `codex-check.sh` **尚未**移植本功能——
在移植完成前，三平台 codex-check 不宣稱語義等價（Windows 領先：能力面 baseline diff、四態盤點、
快取版本鍵、依賴旗標探測）。

## 背景與定案（2026-07-16，Codex 諮詢兩輪）

版本提醒重定位：BEHIND＝中性情報、非更新指令；「更新後 AI 重新檢查」從口頭慣例升級為機器可驗的
baseline diff。Codex 第二輪對初版設計 BLOCK（46/100），以下設計點是採納其攻擊後的定形，移植時**不可回退**：

1. **不自動建立 baseline**：無 baseline 只印 `NO_BASELINE` 警示。否則「刪檔重跑」成為第二條更新途徑。
   `-UpdateBaseline` 是唯一建立/更新途徑（語義＝「你接受過的能力面」，非「上次看到的」）。
2. **盤點四態**：`OK / EMPTY / UNPARSEABLE / FAILED`。
   - FAILED＝exception 或 rc≠0（查不到≠能力消失）；
   - UNPARSEABLE＝rc=0、有輸出但解析 0 筆（或 mcp state 全 `?`）——堵「parser 壞掉→EMPTY→一鍵洗白」；
   - EMPTY＝rc=0 且原始輸出為空；與非空 baseline 比對時走歧義警示（不當 removed-all 漂移）。
   - features 例外：解析到表（含全 false）即 OK。
3. **`-UpdateBaseline` 被拒回 exit 2、且延後寫入**：盤點含 FAILED/UNPARSEABLE 段→拒絕（exit 2）；通過盤點
   也**不立即落檔**，等 smoke 通過（或快取命中=近期 smoke OK）才寫——否則「先寫檔、smoke 才失敗 exit 2」
   會偽裝成「被拒、舊 baseline 還在」而實際已被替換。結果以輸出行 **`UPDATE_BASELINE=OK / REFUSED /
   NOT_APPLIED`** 為權威訊號（smoke 失敗 passthrough 也可能 exit 2，automation 勿只看 exit code）。
   一般漂移仍只警示、exit code 不變（姿態 A）。
4. **快取版本鍵＋對稱守衛**：cache 命中需「當前版本非空 且 與 cache 行 installed 完全相等」（空==空也不許
   命中），且**本次依賴旗標相容性未確立時不採信舊綠快取**（寫入側與命中側對稱）。
5. **依賴旗標探測**：`codex exec --help` 單次抓取（同時供 smoke 的 lastmsg 判定），**rc=0 才採信**（clap 出錯
   時 usage 文字也含旗標名），比對 `--ephemeral --output-last-message --output-schema --sandbox
   --skip-git-repo-check`，**旗標邊界比對**（`--sandbox-policy` 不得滿足 `--sandbox`）。旗標相容性未確立→
   smoke 成功也**不寫 24h 快取**。
6. **外掛識別保留完整 `name@marketplace`**：實測真 codex 的 `@` 尾綴是 **marketplace 限定詞**（VERSION 是獨立
   欄），**不得剝除**——同名外掛換 marketplace（供應鏈識別變更）必須呈現為漂移。（初版「剝版本尾綴」假設
   已被對抗審查以真輸出推翻。）
7. **stderr 下沉 shell 子層**：help 與 plugin/mcp/features 四個探測的 stderr 合流/丟棄必須做在 cmd 層
   （`2>&1`/`2>NUL`），不可在 PS 層重導——PS 5.1 EAP=Stop 下一行 native stderr 就把整段炸成 FAILED
   （4c3d477 smoke 同型地雷；POSIX 無此失敗模式，但 rc 檢查仍須做）。
8. **零項 boilerplate 計為 EMPTY**：`No marketplace plugins found.` / `No MCP servers configured...` 等零項訊息
   與 Marketplace 前導/表頭行，排除於 rawN——否則乾淨機器永遠 UNPARSEABLE、建不了 baseline（真 codex 實測）。
9. **hooks 段也有 UNPARSEABLE**：config.toml 存在且含 `hooks.state` 字樣但解析 0 筆（如 TOML 改單引號鍵
   序列化）→ UNPARSEABLE、拒更新——hooks 是 read-only 心智模型外的執行面，洗白代價最高。
10. **hook 保護**：`~/.claude/.codex-check-baseline` 已加入 `isSecurityCriticalPath`（windows hook + 2 gate
    cases），mac/linux hook 需同步。

## baseline 檔格式（format=1，行式）

```
format=1
captured=2026-07-16T16:30:00+08:00
codex_version=0.144.3
exec_flags=--ephemeral,--output-last-message,--output-schema,--sandbox,--skip-git-repo-check
plugins=alpha@some-marketplace,beta@some-marketplace
mcp=srv1[enabled],srv2[disabled]
features=hooks,remote_plugin
hooks=some-hook
```

- 各段 sorted、comma-join；`captured` 不參與比對。
- 嚴格 parser：key 只認 `^[a-z_]+=`、**只切第一個 `=`**、重複 key＝corrupt、缺任一段 key＝corrupt；
  corrupt 只警示「格式不符，視為無 baseline」、**不自動覆寫**。
- Windows 寫檔 UTF-8 with BOM＋CRLF（PS 5.1 慣例）；**POSIX parser 必須容忍 BOM 與 CRLF**（使用者可能跨平台同步 home）。
- 已知取捨：名稱含逗號會破壞 set-split（外掛/feature/MCP 名慣例上不含逗號，接受此殘餘風險並記錄於此）。

## 測試移植清單（bash runner 需鏡像 19 案）

`t_b_no_autocreate_then_update / t_b_no_drift / t_b_drift_warns_no_rewrite / t_b_update_baseline /
t_b_empty_ambiguous_unknown / t_b_query_fail_unknown_update_refused / t_b_unparseable_blocks_update /
t_b_corrupt_baseline / t_b_flag_missing_no_cache / t_b_near_flag_not_matched /
t_b_version_empty_no_cache_hit / t_b_cache_version_mismatch_miss（含 hit 與 full-check 兩路徑各「exec --help
恰呼叫一次」的 trace 斷言）/ t_b_probe_stderr_immune / t_b_boilerplate_zero_is_empty / t_b_mcp_drift_and_fail /
t_b_mcp_all_unknown_unparseable / t_b_marketplace_identity_drift / t_b_hooks_unparseable /
t_b_flag_incompat_cache_not_trusted`。另 `t_h4_newformat_cache_hit` 加了「cache-hit run 仍印能力面＋baseline
狀態」斷言（mutation 測試證明沒有它，把盤點搬到 exit 0 之後仍全綠）。
stub 需新增：`CODEX_STUB_PLUGINS / CODEX_STUB_MCP / CODEX_STUB_FEATURES / CODEX_STUB_CAP_FAIL /
CODEX_STUB_HELP_DROP_FLAG / CODEX_STUB_PLUGINS_GARBAGE / CODEX_STUB_HELP_NEARFLAG /
CODEX_STUB_LIST_STDERR / CODEX_STUB_HELP_STDERR / CODEX_STUB_LIST_BOILERPLATE`，
help 預設補印 `--sandbox / --ephemeral / --output-schema / --skip-git-repo-check`。

注意：linux `codex-check.sh` 連 0.143 的能力面盤點段都尚未移植（見
`handoff-codex-check-windows-native-gate.md`）——移植本功能前需先補齊該段。

## 明確擱置項（Codex 提出、Claude 裁決不做/緩做，翻案需新諮詢）

- **probe deadline**（--version / exec --help / plugin / mcp / features 無逾時）：既有 backlog 項，
  本次未擴大處理；cache-hit 路徑新增 2 個 probe 與既有 3 個同失敗類別。
- **torn snapshot**（盤點中途升級）：不做前後雙版本探測；單人桌機、秒級窗口，接受殘餘風險。
- **hooks ID 截斷**（`vendor:suffix` 取 [0]）：沿用既有行為（suffix 疑為 volatile hash，保留截斷防常態漂移）；
  若證實 suffix 穩定再改存全 ID。
- **短旗標 -C / -c 探測**：單字母 help 比對誤報率高，不納入；其為 CLI 核心介面，消失時長旗標幾乎必同動。
- **每段 -AcceptEmpty 粒度**：UNPARSEABLE 分離後，EMPTY 已大概率真空，普通 `-UpdateBaseline` 允許接受
  EMPTY（附醒目註記）；不另加開關。
- **一項一列＋percent-encoding 格式**（Codex rank-2 提案）：以嚴格 parser＋名稱慣例約束替代；
  若未來真的出現含逗號名稱再升級 format=2。
