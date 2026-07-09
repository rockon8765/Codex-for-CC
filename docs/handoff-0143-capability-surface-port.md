# Handoff：把 0.143.0 的能力面盤點移植到 macos/ 與 linux/

> 對象：維護 `macos/` 與 `linux/` 的人（或其 Claude Code）。
> 來源：`windows/` 已於 commit `a90b127` 落地兩處改動；本文件說明哪一處要移植、哪一處**不要**移植，以及精準落點與驗收。
> 背景：Codex CLI 升到 **0.143.0**，其中 `remote_plugin` 旗標改為**預設 ON**（遠端外掛預設啟用）。這讓「worker 繼承全域 config 的一大包能力面」更值得每次派工前看得見。

---

## TL;DR（兩件事，一做一不做）

| 改動 | Windows 做了什麼 | macos/linux 要不要移植 |
|---|---|---|
| **① 能力面盤點** `Show-CapabilitySurface` | `codex-check.ps1` 於 24h 快取檢查前唯讀盤點啟用外掛 / MCP / 關鍵旗標 | **要移植**（跨平台、行為等價）。見 §1 |
| **② 注入守衛** `Assert-CmdSafePath` | `codex-exec.ps1` 補上 `-Dir`/`-SchemaFile` 進 `cmd /s /c` 前擋 `%!"&\|<>^` | **不要移植**。bash 無此注入面。見 §2 |

---

## §1 能力面盤點 —— 要移植

### 為什麼
`codex exec` 會繼承全域 `~/.codex/config.toml`：worker 其實握著設定檔裡啟用的所有外掛（可能含 computer-use、browser）、MCP server、與全域 reasoning effort。0.143.0 又把 `remote_plugin` 設為預設 ON。把「這台機器上 worker 實際帶著哪些能力」每次派工前印出來，就能一眼抓到升級造成的能力面漂移。這是**純唯讀觀測、不改任何行為**。

### 落點（macos 與 linux 相同）
`skills/超級模式/scripts/codex-check.sh`，插在 `cache=...` 與 cache 的 `if` 之間：

```bash
cache="$HOME/.claude/.codex-check-last"

# <<<< 在這裡插入 show_capability_surface 定義 + 呼叫 >>>>

if [ "$force" != "1" ] && [ -f "$cache" ]; then
```

放在 cache 檢查**之前**是刻意的：盤點無模型推理、成本極低，要「每次呼叫都印」（即使命中 24h smoke 快取才抓得到漂移）；貴的 smoke test 仍照舊走快取。

### 可直接貼上的實作（macOS/Linux 共用，無 BSD/GNU 差異）

```bash
# --- 能力面盤點（唯讀，跨平台）------------------------------------------------
# 盤點 worker 每次派工實際帶著的能力面（啟用外掛 / MCP / 關鍵旗標）。
# 全走本地 snapshot、無模型推理 → 放在 24h smoke 快取之前、每次呼叫都印。
show_capability_surface() {
  echo "=== Codex worker 能力面（唯讀盤點）==="
  # ⚠️ 腳本頂層是 set -euo pipefail；本段大量用 codex 子指令 + grep(無匹配回 1)，
  #    必須先關 -e/pipefail，否則任一非零退出會中止整支 codex-check。
  set +e; set +o pipefail

  local plugins pcount mcp mcount flags parts f state
  # 啟用外掛：只留 'installed, enabled'，取 @ 前短名
  plugins="$(codex plugin list 2>/dev/null | grep -E 'installed, enabled' | awk '{print $1}' | cut -d@ -f1 | paste -sd', ' -)"
  pcount="$(codex plugin list 2>/dev/null | grep -cE 'installed, enabled')"
  echo "啟用外掛 (${pcount:-0}): ${plugins:-(無)}"

  # MCP servers：跳表頭(第 1 列 Name)，取第一欄名稱 + enabled/disabled
  mcp="$(codex mcp list 2>/dev/null | awk 'NR>1 && NF>0 { st="?"; if ($0 ~ /disabled/) st="disabled"; else if ($0 ~ /enabled/) st="enabled"; printf "%s[%s] ", $1, st }')"
  mcount="$(printf '%s' "$mcp" | wc -w | tr -d ' ')"
  echo "MCP servers (${mcount:-0}): ${mcp:-(無)}"

  # 關鍵旗標：codex features list 每列 = "name  stage  state"，name 在 $1、state 在 $NF
  flags="$(codex features list 2>/dev/null)"
  parts=""
  for f in remote_plugin plugins computer_use browser_use in_app_browser multi_agent network_proxy respect_system_proxy; do
    state="$(printf '%s\n' "$flags" | awk -v k="$f" '$1==k {print $NF; exit}')"
    [ -z "$state" ] && continue
    if [ "$state" = "true" ]; then parts="${parts}${f}=ON  "; else parts="${parts}${f}=off  "; fi
  done
  [ -n "$parts" ] && echo "關鍵旗標: ${parts}"

  echo "提示: worker 繼承上述全域能力面（>『只改檔』所需）。如需收緊，可於派工時加 --disable <feature> 單次覆寫（例：--disable remote_plugin / --disable plugins）；目前未預設收緊，屬待評估選項。"
  echo
  set -e; set -o pipefail   # 還原腳本頂層 set -euo pipefail 基線
}

show_capability_surface
```

### 驗收（macos 與 linux 各跑一次）
1. `bash skills/超級模式/scripts/codex-check.sh`（不帶 `-f`，走快取）→ 應先印能力面盤點，再印快取行；中文不亂碼。
2. 三段解析對：啟用外掛數與 `codex plugin list | grep 'installed, enabled'` 一致；MCP 與 `codex mcp list` 一致；`關鍵旗標` 的 `remote_plugin` 與 `codex features list` 該列的 `$NF` 一致。
3. 確認**沒有**因為某個 codex 子指令非零退出而中止腳本（`set -e` 陷阱）——這是本移植唯一容易踩的雷。
4. `codex-check.sh -f` 仍能跑完整版本檢查 + smoke，不受影響。

> 注意：各機器的 `~/.codex/config.toml` 不同，印出的清單本來就會不一樣（那正是重點——顯示**這台**機器 worker 的實際能力面）。`remote_plugin=ON` 需 codex ≥ 0.143.0；舊版 `features list` 旗標集不同，但函式版本無關（照印當地 codex 回報的內容）。

---

## §2 注入守衛 —— **不要移植**（重要）

Windows 版在 `codex-exec.ps1` 補了 `Assert-CmdSafePath`，擋 `-Dir`/`-SchemaFile` 含 `%!"&|<>^`。**這是 Windows 專屬的坑，bash 沒有對應的注入面**：

- Windows 的漏洞來自 PowerShell 建了 `cmd /s /c "<內含 $Dir 的一整條字串>"`，而 **cmd 會在雙引號內重新解析** `%VAR%`、`& | < > ^` 等運算子。
- bash 版 `codex-exec.sh` / `codex-consult.sh` 是 `codex exec ... -C "$dir" --output-schema "$schema" < brief`，把 `$dir`、`$schema` 當**正常 argv 引數**傳給 codex，**不經 `cmd`/`eval`/`sh -c` 二次解析**。不論路徑含什麼字元都是單一引數，天生安全。
- 因此 Windows 那個「consult 有守衛、exec 沒有」的不對稱，在 bash **兩支都用 argv、兩支都已安全**——已是等價的最終狀態。

**請勿**在 bash 加等價路徑字元黑名單：那會誤傷含 `&` 等合法字元的 repo 路徑（例如 `遠雄債券評價&風險值`），卻換不到任何 bash 上的安全好處。

若真的想加防禦，唯一合理且 bash 慣用的是**保持現狀的 argv 傳法**（永不 `eval`、永不把路徑拼進 `sh -c` 字串）；頂多加一個可用性檢查 `[ -d "$dir" ] || { echo "dir not found"; exit 2; }`（那是使用性、不是資安）。

---

## 附註：平台同步慣例
本 repo `CLAUDE.md` 要求三平台行為等價、機制依平台翻譯。本次結論：
- **① 能力面盤點** = 行為要等價 → 移植（§1）。
- **② 注入守衛** = 行為目標（防路徑注入）在 bash 已由 argv 模型達成 → 無需新增程式碼即等價（§2）。

移植完成後，建議在各平台 commit 訊息點名對應 Windows commit `a90b127`，並在 README「已知的坑」或 sync-matrix 記一筆「注入守衛為 Windows 專屬、bash 以 argv 達成等價」，避免日後有人再誤加。
