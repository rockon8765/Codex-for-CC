#!/usr/bin/env bash
# 超級模式 §3 dispatch preflight: Codex CLI version check + read-only smoke test.
# 24h 快取存 ~/.claude/.codex-check-last（-f/--force 強制重查）。
# smoke test 才是可用性權威：smoke 失敗會「刪除快取」，壞掉的 codex 絕不會被舊快取續報 OK。
# Tool timeout: 360000ms — smoke test 走 Codex 推理，常超過 2 分鐘預設。
set -euo pipefail
force="0"
case "${1:-}" in -f|--force) force="1" ;; "") : ;; *) echo "unknown arg: $1" >&2; exit 2 ;; esac

cache="$HOME/.claude/.codex-check-last"

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

if [ "$force" != "1" ] && [ -f "$cache" ]; then
  age_h=$(( ( $(date +%s) - $(stat -f %m "$cache") ) / 3600 ))   # BSD stat（macOS）
  if [ "$age_h" -lt 24 ]; then
    echo "codex-check: ${age_h}h 前查過，跳過（-f 強制重查）。上次結果："
    cat "$cache"
    exit 0
  fi
fi

echo "=== installed ==="
installed_raw="$(codex --version 2>&1 || true)"
printf '%s\n' "$installed_raw" | head -1
# H1: 優先從 codex 錨定行抽版本；錨定行沒有才退回全輸出第一個版本樣 token（banner 誤中風險見規劃書 D5）
inst_ver="$(printf '%s\n' "$installed_raw" | grep -E '^codex(-cli)?[[:space:]]' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
[ -n "$inst_ver" ] || inst_ver="$(printf '%s\n' "$installed_raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
echo "=== latest on npm ==="
# C3: npm view 離線/失敗留空（不可拿去跟 installed 比，否則離線就誤報 OUTDATED；smoke 才是權威判定）
latest_raw="$(npm view '@openai/codex' version 2>/dev/null || true)"
# H5: 恰一行（單次 awk，避 head 的 SIGPIPE）＋ 版本 token 文法全匹配；否則一律當查不到（→ UNKNOWN）
latest_line="$(printf '%s' "$latest_raw" | awk 'NR==1{l=$0} END{if(NR==1) print l}')"
latest=""
if [ -n "$latest_line" ] && printf '%s' "$latest_line" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z]+(\.[0-9A-Za-z-]+)*)?$'; then
  latest="$latest_line"
fi
latest_disp="${latest:-(unknown - offline)}"
echo "$latest_disp"
# C3: 版本狀態機 CURRENT/BEHIND/AHEAD/UNKNOWN。可攜比較用 POSIX awk 拆 major.minor.patch，避開 BSD 不支援的 sort -V。
if [ -z "$inst_ver" ]; then
  verdict="UNKNOWN (installed 版本解析不到) -- 無法判定新舊，改看下方 smoke test 認定可用性"
elif [ -z "$latest" ]; then
  verdict="UNKNOWN (latest 查不到，可能離線) -- 無法判定新舊，改看下方 smoke test 認定可用性"
elif [ "$inst_ver" = "$latest" ]; then
  verdict="UP-TO-DATE"
else
  cmp="$(awk -v a="$inst_ver" -v b="$latest" 'BEGIN{
    na=split(a,x,"[.]"); nb=split(b,y,"[.]");
    for(i=1;i<=3;i++){ xi=(i<=na?x[i]+0:0); yi=(i<=nb?y[i]+0:0);
      if(xi<yi){print -1; exit} if(xi>yi){print 1; exit} }
    print 0 }' || true)"
  case "$cmp" in
    -1) verdict="BEHIND ($inst_ver -> $latest) -- 更新屬系統變更，先問使用者再跑 npm install -g @openai/codex@latest" ;;
    1)  verdict="AHEAD ($inst_ver > $latest) -- 本機比 registry 新（prerelease/私建），非落後" ;;
    0)  verdict="CURRENT ($inst_ver vs $latest) -- base 版本相同（多半 prerelease 尾綴差異）" ;;
    *)  verdict="UNKNOWN (版本比較失敗) -- 無法判定新舊，改看下方 smoke test 認定可用性" ;;
  esac
fi
echo "$verdict"

echo "=== read-only smoke test ==="
# codex exec 必須餵空 stdin + --skip-git-repo-check，否則卡讀 stdin / 報不受信任目錄
# C2: 捕捉輸出並回顯，驗真回了 CODEX_OK（光看 exit code 會把「壞掉但 exit 0」誤判成可用）。
set +e
smoke_out="$(printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Reply with exactly: CODEX_OK" 2>&1)"
smoke=$?
set -e
printf '%s\n' "$smoke_out"
# user prompt echo 也含 CODEX_OK，只看有沒有出現會假通過；要 "codex" marker 之後的回覆段才算數。先剝 ANSI（literal ESC，避 BSD sed 不支援 \x1b）。
esc="$(printf '\033')"
clean="$(printf '%s' "$smoke_out" | sed "s/${esc}\[[0-9;]*m//g")"
reply="$(printf '%s\n' "$clean" | awk 'f{print} /^[[:space:]]*codex[[:space:]]*$/{f=1}')"

if [ "$smoke" -eq 0 ] && printf '%s' "$reply" | grep -q 'CODEX_OK'; then
  printf 'installed=%s latest=%s verdict=%s smoke=OK at %s\n' \
    "$inst_ver" "$latest_disp" "$verdict" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$cache"
else
  if [ "$smoke" -eq 0 ]; then
    echo "codex-check: smoke exit 0 但輸出無 CODEX_OK 回覆 sentinel（codex 可能壞了）-- 刪快取，下次強制重查" >&2
  else
    echo "codex-check: smoke test failed (exit $smoke) -- 刪除快取，下次呼叫強制重查" >&2
  fi
  rm -f "$cache"
  [ "$smoke" -ne 0 ] || smoke=1
fi
exit "$smoke"
