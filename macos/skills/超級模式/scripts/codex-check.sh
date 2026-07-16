#!/usr/bin/env bash
# 超級模式 §3 dispatch preflight: Codex CLI version check + read-only smoke test + 能力面 baseline diff.
# 24h 快取存 ~/.claude/.codex-check-last（-f/--force 強制重查）。
# smoke test 才是可用性權威：smoke 失敗會「刪除快取」，壞掉的 codex 絕不會被舊快取續報 OK。
# 能力面 baseline（~/.claude/.codex-check-baseline）：不自動建立——無 baseline 時警示 NO_BASELINE，
# 以 -u/--update-baseline 建立/更新（唯一支援途徑；先過盤點檢查、等 smoke 通過才落檔）。結果以輸出行
# UPDATE_BASELINE=OK / REFUSED / NOT_APPLIED 為權威訊號（被拒回 exit 2，但 smoke 失敗 passthrough 也可能
# 是 2，automation 勿只看 exit code）。姿態 A：漂移只警示、不影響 exit code；依賴旗標缺失時不寫也不採信
# smoke 快取（不讓 24h 快取蓋掉不相容訊號）。
# Tool timeout: 360000ms — smoke test 走 Codex 推理，常超過 2 分鐘預設。
# ⚠️ 目標 macOS 內建 bash 3.2：不可用關聯陣列/${var,,}；間接展開 ${!v} 與 <() 可用。
set -euo pipefail
force="0"; update_baseline="0"
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force) force="1" ;;
    -u|--update-baseline) update_baseline="1" ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

cache="$HOME/.claude/.codex-check-last"
cache_format="format=2"
baseline_file="$HOME/.claude/.codex-check-baseline"
cache_tmp=""
baseline_tmp=""
lastmsg_file=""
trap 'rm -f "$cache_tmp" "$baseline_tmp" "$lastmsg_file"' EXIT
# --update-baseline 通過盤點檢查後先掛起，等 smoke 通過（或快取命中=近期 smoke OK）才真正落檔。
baseline_pending="0"
# consult/exec 腳本實際依賴的 exec 旗標（升級後若從 help 消失＝相容性斷裂訊號，要大聲講）。
# 短旗標 -C/-c 也是真依賴，但 help 內單字母比對誤報率高，不納入探測——其為 CLI 核心介面，
# 消失時上述長旗標幾乎必同動。
required_flags="--ephemeral --output-last-message --output-schema --sandbox --skip-git-repo-check"
# baseline 段落序（也是檔內行序；captured 不參與比對）
cap_sections="codex_version exec_flags plugins mcp features hooks"

# --- 小工具（bash 3.2 相容）-----------------------------------------------------
join_list() {  # $1=newline 清單 $2=分隔字串 → 單行輸出（空清單輸出空字串）
  printf '%s\n' "$1" | awk -v sep="$2" '$0==""{next} {if(n++)printf "%s",sep; printf "%s",$0} END{print ""}'
}
count_list() {  # newline 清單項數
  if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | grep -c .; fi
}
emit_lines() {  # 空字串不輸出任何行（餵 comm 用，防幻影空行 diff）
  [ -n "$1" ] && printf '%s\n' "$1"
  return 0
}

# --- H1（前移）：版本抽取。能力面 snapshot 要含版本、快取命中要驗版本一致（堵「24h 內升級
#     仍回報舊結果」的盲點），故每次呼叫先讀。錨定行優先 → 退回第一個版本樣 token → 抽不到留空走 UNKNOWN(installed)。
installed_raw="$(codex --version 2>&1 || true)"
inst_ver="$(printf '%s\n' "$installed_raw" | grep -E '^codex(-cli)?[[:space:]]' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
[ -n "$inst_ver" ] || inst_ver="$(printf '%s\n' "$installed_raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1 || true)"
disp_line="$(printf '%s\n' "$installed_raw" | grep -E '^codex(-cli)?[[:space:]]' | head -1 || true)"
[ -n "$disp_line" ] || disp_line="$(printf '%s\n' "$installed_raw" | head -1 || true)"

# --- H2 help（前移、單次抓取）：同時供 (a) skill 依賴旗標探測 (b) smoke 的 --output-last-message
#     能力判定。stderr 以 2>&1 合流（真 codex 會往 stderr 印噪音）；rc 必須 =0 才採信——clap 出錯時
#     usage 文字也含旗標名，rc!=0 的輸出不可拿來當 help。整支腳本 exec --help 恰呼叫一次（測試臺 trace 斷言）。
help_out=""
help_ok="0"
if help_out="$(codex exec --help 2>&1)"; then
  [ -n "$help_out" ] && help_ok="1"
fi
# ⚠️ 大 help（>64KB）時 printf | grep -q 會因 grep 提前退出 → printf SIGPIPE → pipefail 誤判 false
#    （t_h2_large_help 抓到）——改用 case 純 shell substring 比對，零管線（鏡像 PS -match 語義）。
use_lastmsg=0
if [ "$help_ok" = "1" ]; then
  case "$help_out" in *--output-last-message*) use_lastmsg=1 ;; esac
fi

# --- 能力面 snapshot：每段 items（排序正規化、newline 清單）+ status 四態（OK/EMPTY/UNPARSEABLE/FAILED）。
# FAILED      = 查詢 rc!=0 或讀取失敗（查不到 ≠ 能力消失，絕不當成「無能力」）；
# UNPARSEABLE = rc=0、有輸出但解析 0 筆（或 mcp state 全 '?'）—— 疑升級改了輸出格式，禁止寫進 baseline
#               （堵「parser 壞掉 → EMPTY → --update-baseline 一鍵洗白」的門，Codex 諮詢 2026-07-16）；
# EMPTY       = rc=0 且原始輸出為空 —— 大概率真的沒有（與非空 baseline 比對時仍走歧義警示）。
# features 例外：只要解析到表（含全 false）即 OK，items=enabled=true 清單 → true→false 翻轉呈現為真漂移。
collect_capability_snapshot() {
  local raw rc raw_n unk rf cfg cfg_raw

  cap_plugins_items=""; cap_plugins_status="FAILED"
  raw="$(codex plugin list 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    # rawN 排除已知 boilerplate（零外掛訊息 'No ...'、Marketplace 前導/路徑行、表頭）：
    # 乾淨機器零外掛屬 EMPTY 而非 UNPARSEABLE，否則新機永遠建不了 baseline（2026-07-16 真 codex 實測）。
    raw_n="$(printf '%s\n' "$raw" | awk '
      /^[[:space:]]*$/ {next}
      /^[[:space:]]*No([[:space:]]|$)/ {next}
      tolower($0) ~ /marketplace/ {next}
      /^[[:space:]]*PLUGIN([[:space:]]|$)/ {next}
      {n++} END{print n+0}')"
    # 保留完整 name@marketplace 識別：@ 尾綴是 marketplace 限定詞（VERSION 是獨立欄），
    # 剝掉會讓「同名外掛換 marketplace」在 diff 隱形（供應鏈識別變更正是 baseline 要抓的）。
    cap_plugins_items="$(printf '%s\n' "$raw" | awk '
      { n = split($0, cols, /[[:space:]][[:space:]]+/)
        if (n >= 2 && cols[2] ~ /enabled/) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", cols[1])
          if (cols[1] != "") print cols[1] } }' | LC_ALL=C sort -u)"
    if [ -n "$cap_plugins_items" ]; then cap_plugins_status="OK"
    elif [ "$raw_n" -gt 0 ]; then cap_plugins_status="UNPARSEABLE"
    else cap_plugins_status="EMPTY"; fi
  fi

  cap_mcp_items=""; cap_mcp_status="FAILED"
  raw="$(codex mcp list 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    # 'No MCP servers configured...' 屬零項 boilerplate → 排除於解析與 rawN（乾淨機器走 EMPTY）
    raw_n="$(printf '%s\n' "$raw" | awk '
      /^[[:space:]]*$/ {next}
      /^[[:space:]]*Name[[:space:]]/ {next}
      /^[[:space:]]*No([[:space:]]|$)/ {next}
      {n++} END{print n+0}')"
    cap_mcp_items="$(printf '%s\n' "$raw" | awk '
      /^[[:space:]]*$/ {next}
      /^[[:space:]]*Name[[:space:]]/ {next}
      /^[[:space:]]*No([[:space:]]|$)/ {next}
      { st = "?"
        if ($0 ~ /(^|[^[:alnum:]_])disabled([^[:alnum:]_]|$)/) st = "disabled"
        else if ($0 ~ /(^|[^[:alnum:]_])enabled([^[:alnum:]_]|$)/) st = "enabled"
        if ($1 != "") print $1 "[" st "]" }' | LC_ALL=C sort -u)"
    unk="$(printf '%s\n' "$cap_mcp_items" | grep -c '\[?\]$' || true)"
    # state 全部判不出（全 '?'）＝疑格式失真，不是可接受的新能力面 → UNPARSEABLE
    if [ -n "$cap_mcp_items" ] && [ "$unk" -eq "$(count_list "$cap_mcp_items")" ]; then cap_mcp_status="UNPARSEABLE"
    elif [ -n "$cap_mcp_items" ]; then cap_mcp_status="OK"
    elif [ "$raw_n" -gt 0 ]; then cap_mcp_status="UNPARSEABLE"
    else cap_mcp_status="EMPTY"; fi
  fi

  cap_features_items=""; cap_features_status="FAILED"; cap_features_flags=""
  raw="$(codex features list 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    raw_n="$(printf '%s\n' "$raw" | awk '
      /^[[:space:]]*$/ {next}
      /^[[:space:]]*No([[:space:]]|$)/ {next}
      {n++} END{print n+0}')"
    # 每列 = "name  stage  state"，只取首(name)尾(enabled)；同名重複時後者覆蓋（鏡像 hashtable 語義）
    cap_features_flags="$(printf '%s\n' "$raw" | awk 'NF >= 2 { v[$1] = $NF } END { for (k in v) print k, v[k] }' | LC_ALL=C sort)"
    # items 由 raw true 列收集（any-true membership，鏡像 PS「見 true 即 append」）；flags 仍 last-wins ——
    # 重複 feature 列時兩平台 baseline 才一致（Codex 反方檢核 2026-07-16）
    cap_features_items="$(printf '%s\n' "$raw" | awk 'NF >= 2 && $NF == "true" {print $1}' | LC_ALL=C sort -u)"
    if [ -n "$cap_features_flags" ]; then cap_features_status="OK"
    elif [ "$raw_n" -gt 0 ]; then cap_features_status="UNPARSEABLE"
    else cap_features_status="EMPTY"; fi
  fi

  # hooks 盤點：config 的 [hooks.state."<id>"] 段＝「受信任、會在 codex exec(含唯讀 consult)時執行」
  # 的 hook——read-only 沙箱心智模型之外的執行面。本地檔自控格式：檔不存在＝真的無 hooks
  # （OK 空、非 EMPTY 歧義）。唯讀讀 config.toml，不改任何檔。
  cap_hooks_items=""; cap_hooks_status="OK"
  cfg="$HOME/.codex/config.toml"
  if [ -f "$cfg" ]; then
    if cfg_raw="$(cat "$cfg" 2>/dev/null)"; then
      # hooks ID 截斷：vendor:suffix 取 [0]（suffix 疑為 volatile hash，保留截斷防常態漂移）
      cap_hooks_items="$(printf '%s\n' "$cfg_raw" | tr -d '\r' | sed -nE 's/^\[hooks\.state\."([^"]+)"\].*$/\1/p' | cut -d: -f1 | LC_ALL=C sort -u)"
      # config 內有 hooks.state 段但一筆都解析不到（如 TOML 改用單引號/裸鍵序列化）→ UNPARSEABLE，
      # 不可當成「無 hooks」寫進 baseline（hooks 是 read-only 心智模型外的執行面，洗白代價最高）。
      if [ -z "$cap_hooks_items" ]; then
        case "$cfg_raw" in *"hooks.state"*) cap_hooks_status="UNPARSEABLE" ;; esac
      fi
    else
      cap_hooks_status="FAILED"
    fi
  fi

  cap_exec_flags_items=""; cap_exec_flags_status="FAILED"; cap_flags_missing=""
  if [ "$help_ok" = "1" ]; then
    for rf in $required_flags; do
      # 旗標邊界比對：--sandbox 不得被 --sandbox-policy 之類的近似旗標滿足（前後須為空白/,/=/</行界）。
      # grep -c（非 -q）：讀完整輸入才退出，防大 help 下 printf SIGPIPE 噪音（exit code 語義同 -q）。
      if printf '%s\n' "$help_out" | grep -cE "(^|[[:space:],])${rf}([[:space:]=<,]|$)" >/dev/null; then
        cap_exec_flags_items="${cap_exec_flags_items}${cap_exec_flags_items:+
}${rf}"
      else
        cap_flags_missing="${cap_flags_missing}${cap_flags_missing:+
}${rf}"
      fi
    done
    if [ -n "$cap_exec_flags_items" ]; then cap_exec_flags_status="OK"; else cap_exec_flags_status="UNPARSEABLE"; fi
    cap_exec_flags_items="$(printf '%s\n' "$cap_exec_flags_items" | LC_ALL=C sort -u)"
  fi

  cap_codex_version_items=""; cap_codex_version_status="FAILED"
  if [ -n "$inst_ver" ]; then cap_codex_version_items="$inst_ver"; cap_codex_version_status="OK"; fi
}

show_capability_surface() {
  # 唯讀盤點 worker 每次派工實際帶著的能力面（啟用外掛 / MCP / 關鍵旗標）。
  # 全走本地 snapshot、無模型推理，故每次呼叫都印（即使命中 24h smoke 快取），好抓升級造成的能力面漂移。
  local n items hot hot_on f v
  echo "=== Codex worker 能力面（唯讀盤點）==="

  if [ "$cap_plugins_status" = "FAILED" ]; then echo "啟用外掛: (查詢失敗)"
  elif [ "$cap_plugins_status" = "UNPARSEABLE" ]; then echo "啟用外掛: (UNPARSEABLE -- 有輸出但解析 0 筆，疑升級改了輸出格式，請人工確認)"
  else
    n="$(count_list "$cap_plugins_items")"; items="$(join_list "$cap_plugins_items" ', ')"
    echo "啟用外掛 (${n}): ${items:-(無)}"
  fi

  if [ "$cap_mcp_status" = "FAILED" ]; then echo "MCP servers: (查詢失敗)"
  elif [ "$cap_mcp_status" = "UNPARSEABLE" ]; then echo "MCP servers: (UNPARSEABLE -- 有輸出但無法解析/state 全 '?'，疑格式失真，請人工確認)"
  else
    n="$(count_list "$cap_mcp_items")"; items="$(join_list "$cap_mcp_items" ', ')"
    echo "MCP servers (${n}): ${items:-(無)}"
  fi

  if [ "$cap_features_status" = "FAILED" ]; then echo "features: (查詢失敗)"
  elif [ "$cap_features_status" = "UNPARSEABLE" ]; then echo "features: (UNPARSEABLE -- 有輸出但解析 0 筆，疑升級改了輸出格式，請人工確認)"
  else
    # 「列出所有 enabled=true 的 feature」而非比對固定白名單：升級新增的 stable/true 能力面
    # 會自動被盤到，白名單會漏報漂移(2026-07-10 教訓：hooks/memories/browser_use_full_cdp_access 都不在舊白名單)。
    n="$(count_list "$cap_features_items")"; items="$(join_list "$cap_features_items" ', ')"
    echo "啟用 features (${n}): ${items:-(無)}"
    # 高風險子集：這些若 ON 代表 worker 能力面超出「只讀/只改檔」，升級後尤其要盯。
    hot="hooks memories remote_plugin plugins skill_mcp_dependency_install computer_use browser_use browser_use_external browser_use_full_cdp_access in_app_browser multi_agent apps guardian_approval network_proxy respect_system_proxy"
    hot_on=""
    for f in $hot; do
      v="$(printf '%s\n' "$cap_features_flags" | awk -v k="$f" '$1==k {print $2; exit}')"
      [ "$v" = "true" ] && hot_on="${hot_on}${hot_on:+
}${f}"
    done
    hot_on="$(printf '%s\n' "$hot_on" | LC_ALL=C sort)"
    [ -n "$hot_on" ] && echo "  * 高風險能力面 ON: $(join_list "$hot_on" ', ')"
  fi

  if [ "$cap_hooks_status" = "FAILED" ]; then echo "受信任 hooks: (解析失敗)"
  elif [ "$cap_hooks_status" = "UNPARSEABLE" ]; then echo "受信任 hooks: (UNPARSEABLE -- config 有 hooks.state 段但解析 0 筆，疑序列化格式變更，請人工確認)"
  elif [ -n "$cap_hooks_items" ]; then
    n="$(count_list "$cap_hooks_items")"
    echo "受信任 hooks (${n}): $(join_list "$cap_hooks_items" ', ')"
  fi

  # skill 依賴旗標探測：升級後旗標從 exec --help 消失＝consult/exec 腳本可能已不相容，要大聲講。
  if [ "$cap_exec_flags_status" = "FAILED" ]; then echo "skill 依賴旗標: (exec --help 查詢失敗，無法探測)"
  elif [ "$cap_exec_flags_status" = "UNPARSEABLE" ]; then echo "skill 依賴旗標: (UNPARSEABLE -- help 有輸出但一個依賴旗標都比對不到，疑 help 格式大改，請人工確認)"
  elif [ -n "$cap_flags_missing" ]; then
    echo "  * 警告: skill 依賴旗標不在 exec --help: $(join_list "$cap_flags_missing" ', ') -- consult/exec 腳本可能已不相容，升級後請重驗"
  fi

  v="$(printf '%s\n' "$cap_features_flags" | awk '$1=="remote_plugin" {print $2; exit}')"
  if { [ "$cap_features_status" != "FAILED" ] && [ "$v" = "true" ]; } || [ -n "$cap_plugins_items" ]; then
    echo "提示: worker 繼承上述全域能力面（>『只改檔』所需）。如需收緊，可於派工時加 --disable <feature> 單次覆寫（例：--disable remote_plugin / --disable plugins）；目前未預設收緊，屬待評估選項。"
  fi
  echo
}

# --- 能力面 baseline：機器 diff 取代「印出來靠人眼比」（2026-07-16，Codex 諮詢定案）。 ---
# 姿態 A：只警示、不改 exit code、不擋派工。唯一更新途徑 = --update-baseline（人為/AI 檢視後的明確動作），
# 絕不因偵測到漂移而自動改寫——否則 baseline 淪為「上次看到什麼」而非「上次接受什麼」。
read_baseline_file() {
  # 結果經全域 bl_state（none/corrupt/ok）與 bl_<段名> 回傳。嚴格 parser：key 只認 ^[a-z_]+=、
  # 只切第一個 =、重複 key＝corrupt、缺任一段 key＝corrupt；corrupt 不自動覆寫（防誤蓋真 baseline）。
  # Windows 寫檔 UTF-8 BOM＋CRLF（使用者可能跨平台同步 home）→ 本 parser 容忍 BOM 與 CRLF。
  bl_state="none"
  bl_format=""; bl_captured=""; bl_codex_version=""; bl_exec_flags=""; bl_plugins=""; bl_mcp=""; bl_features=""; bl_hooks=""
  [ -f "$baseline_file" ] || return 0
  bl_state="corrupt"
  local line key val k seen=" " first=1 bom=$'\xef\xbb\xbf' key_re='^[a-z_]+$'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" = "1" ]; then line="${line#"$bom"}"; first=0; fi
    line="${line%$'\r'}"
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    [[ "$key" =~ $key_re ]] || continue
    case "$seen" in *" $key "*) return 0 ;; esac   # 重複 key 拒收（嚴格 parser）→ corrupt
    seen="${seen}${key} "
    case "$key" in
      format) bl_format="$val" ;;
      captured) bl_captured="$val" ;;
      codex_version) bl_codex_version="$val" ;;
      exec_flags) bl_exec_flags="$val" ;;
      plugins) bl_plugins="$val" ;;
      mcp) bl_mcp="$val" ;;
      features) bl_features="$val" ;;
      hooks) bl_hooks="$val" ;;
    esac
  done < "$baseline_file"
  [ "$bl_format" = "1" ] || return 0
  for k in $cap_sections; do
    case "$seen" in *" $k "*) ;; *) return 0 ;; esac
  done
  bl_state="ok"
}

write_baseline_file() {
  # atomic：唯一 tmp → mv -f（同快取寫入模式）。行式格式（format=1）＋ LF；各段 sorted、comma-join。
  local k v
  baseline_tmp="$(mktemp "${baseline_file}.tmp.XXXXXX")"
  {
    echo "format=1"
    echo "captured=$(date +%Y-%m-%dT%H:%M:%S%z)"
    for k in $cap_sections; do
      v="cap_${k}_items"
      echo "${k}=$(join_list "${!v}" ',')"
    done
  } > "$baseline_tmp" && mv -f "$baseline_tmp" "$baseline_file"
  baseline_tmp=""
}

invoke_baseline_check() {
  local k sv st iv old_csv old_lines new_items added removed rc_a rc_r n bad_sections=""
  for k in $cap_sections; do
    sv="cap_${k}_status"; st="${!sv}"
    if [ "$st" = "FAILED" ] || [ "$st" = "UNPARSEABLE" ]; then
      bad_sections="${bad_sections}${bad_sections:+
}${k}"
    fi
  done
  read_baseline_file

  if [ "$update_baseline" = "1" ]; then
    if [ -n "$bad_sections" ]; then
      # 使用者明確要求 mutation 卻被拒 → exit 2（誠實命令契約：exit 0 會讓 automation 誤以為已接受）。
      # marker 行是權威訊號：smoke 失敗 passthrough 也可能 exit 2，單看 exit code 有歧義。
      echo "codex-check: 盤點含查詢失敗/解析失真段（$(join_list "$bad_sections" ', ')）→ 拒絕更新 baseline（查不到/解析不了 ≠ 能力消失，不能寫進 baseline）" >&2
      echo "UPDATE_BASELINE=REFUSED"
      exit 2
    fi
    if [ "$bl_state" = "ok" ]; then
      for k in $cap_sections; do
        sv="cap_${k}_status"; st="${!sv}"; iv="bl_${k}"
        if [ "$st" = "EMPTY" ] && [ -n "${!iv}" ]; then
          echo "  * 注意: ${k} 段現為空、原 baseline 非空 -- 若非刻意移除，請先人工確認再信任新 baseline"
        fi
      done
    fi
    # 延後寫入：等 smoke 通過才落檔。否則「先寫檔、smoke 才失敗 exit 2」會讓 automation 誤讀成
    # 「被拒、舊 baseline 還在」，實際上已被無聲替換且無備份可回（2026-07-16 對抗審查證實）。
    baseline_pending="1"
    echo "codex-check: 盤點通過 -- baseline 將於 smoke 通過（或快取命中）後寫入"
    return 0
  fi

  if [ "$bl_state" = "none" ]; then
    # 不自動建立（Codex 諮詢 2026-07-16 裁決）：自動建立會讓「刪檔重跑」成為第二條更新途徑；
    # baseline 的語義必須是「你接受過的能力面」，不是「上次看到的能力面」。
    echo "codex-check: NO_BASELINE -- 尚無能力面 baseline；檢視上方盤點後執行 codex-check.sh --update-baseline 建立" >&2
    return 0
  fi
  if [ "$bl_state" = "corrupt" ]; then
    echo "codex-check: baseline 檔格式不符 → 視為無 baseline（不自動覆寫）；請檢視後用 --update-baseline 重建: $baseline_file" >&2
    return 0
  fi

  local drift_lines="" unknown_lines=""
  for k in $cap_sections; do
    sv="cap_${k}_status"; st="${!sv}"
    iv="bl_${k}"; old_csv="${!iv}"
    if [ "$st" = "FAILED" ]; then
      unknown_lines="${unknown_lines}  ${k}: 查詢失敗（查不到 ≠ 能力消失，不視為漂移）
"; continue
    fi
    if [ "$st" = "UNPARSEABLE" ]; then
      unknown_lines="${unknown_lines}  ${k}: 有輸出但解析失敗（UNPARSEABLE）-- 疑升級改了輸出格式，請人工確認；不視為漂移
"; continue
    fi
    if [ "$st" = "EMPTY" ] && [ -n "$old_csv" ]; then
      n="$(printf '%s' "$old_csv" | awk -F, '{print NF}')"
      unknown_lines="${unknown_lines}  ${k}: 盤點為空但 baseline 有 ${n} 項 -- 可能升級改了輸出格式、也可能能力真的全移除，請人工確認
"; continue
    fi
    iv="cap_${k}_items"; new_items="${!iv}"
    old_lines=""
    [ -n "$old_csv" ] && old_lines="$(printf '%s' "$old_csv" | tr ',' '\n' | LC_ALL=C sort -u)"
    # diff 引擎失敗（comm rc!=0）不得靜默成「無漂移」——本函式跑在 set +e 傘下，四態只包住 probe/parser、
    # 包不住這裡，必須顯式驗 rc（Codex 反方檢核 2026-07-16）。失敗歸 UNKNOWN 段（會壓掉「無漂移」行）。
    added="$(LC_ALL=C comm -13 <(emit_lines "$old_lines") <(emit_lines "$new_items"))"; rc_a=$?
    removed="$(LC_ALL=C comm -23 <(emit_lines "$old_lines") <(emit_lines "$new_items"))"; rc_r=$?
    if [ "$rc_a" -ne 0 ] || [ "$rc_r" -ne 0 ]; then
      unknown_lines="${unknown_lines}  ${k}: 集合比對失敗（comm rc!=0，diff 引擎異常）-- 不視為漂移、也不得當成無漂移，請人工確認
"; continue
    fi
    if [ "$k" = "codex_version" ]; then
      if [ -n "$added" ] || [ -n "$removed" ]; then
        drift_lines="${drift_lines}  codex_version: ${old_csv} -> $(join_list "$new_items" ',')
"
      fi
    else
      [ -n "$added" ] && drift_lines="${drift_lines}  ${k} +: $(join_list "$added" ', ')
"
      [ -n "$removed" ] && drift_lines="${drift_lines}  ${k} -: $(join_list "$removed" ', ')
"
    fi
  done
  if [ -n "$unknown_lines" ]; then
    echo "*** 能力面 UNKNOWN 段（無法與 baseline 比對）***"
    printf '%s' "$unknown_lines"
  fi
  if [ -n "$drift_lines" ]; then
    echo "*** 能力面漂移 vs baseline (captured ${bl_captured}) ***"
    printf '%s' "$drift_lines"
    echo "檢視上述變更；確認符合預期後執行 codex-check.sh --update-baseline 接受為新 baseline。（提醒非閘門，不影響 exit code）"
  elif [ -z "$unknown_lines" ]; then
    echo "能力面 vs baseline (captured ${bl_captured})：無漂移"
  fi
  echo
}

# 能力面盤點＋baseline 比對無模型推理、成本低 → 放在 24h 快取檢查之前，每次呼叫都跑（貴的 smoke test 仍走快取）。
# ⚠️ 頂層是 set -euo pipefail；盤點大量用 codex 子指令 + grep(無匹配回 1)，先關 -e/pipefail 再還原。
set +e; set +o pipefail
collect_capability_snapshot
show_capability_surface
invoke_baseline_check
set -e; set -o pipefail

# 依賴旗標相容性：全數命中才算確立。未確立（缺旗標/help 失真/抓取失敗）→ 本次 smoke 成功也不寫 24h 快取，
# 不讓快取把「可能不相容」蓋成綠燈——下次呼叫仍全檢、再警示一次。
flags_compatible="0"
if [ "$cap_exec_flags_status" = "OK" ] && [ -z "$cap_flags_missing" ]; then flags_compatible="1"; fi

# H4：命中需「恰一行 + 全行格式（format=2 前綴 + installed/latest/verdict 全欄位 + ISO-ish 時戳）+ 0<=age<86400s」；
# 快取版本鍵＋對稱守衛：另需「當前版本非空 且 與 cache 行 installed 完全相等」（空==空也不許命中——身分未知
# 不可拿快取背書）、且本次依賴旗標相容性已確立（不讓「本次盤點已示警」被舊綠快取蓋掉）；否則落回全檢。
if [ "$force" != "1" ] && [ -f "$cache" ] && \
   awk 'NR==1 && $0 ~ /^format=2 installed=[^ ]* latest=.+ verdict=.+ smoke=OK at [0-9]+-[0-9]+-[0-9]+T[0-9:]+[+-][0-9]+$/ {ok=1}
        END{exit (ok && NR==1)?0:1}' "$cache" 2>/dev/null; then
  cached_ver="$(sed -nE 's/^format=2 installed=([^ ]*) latest=.*$/\1/p' "$cache" | head -1)"
  if [ -z "$inst_ver" ]; then
    echo "codex-check: 當前版本解析不到 → 不採信快取、當 miss 全檢"
  elif [ "$cached_ver" != "$inst_ver" ]; then
    echo "codex-check: 快取版本 ${cached_ver} 與當前 ${inst_ver} 不符 → 當 miss 全檢（升級/降級後首跑）"
  elif [ "$flags_compatible" != "1" ]; then
    echo "codex-check: 依賴旗標相容性未確立 → 不採信快取、當 miss 全檢"
  else
    age_s=$(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))   # BSD stat（macOS）；stat 失敗→0→age 超界→當 miss；linux 版用 stat -c %Y
    if [ "$age_s" -ge 0 ] && [ "$age_s" -lt 86400 ]; then
      if [ "$baseline_pending" = "1" ]; then
        # 快取命中＝近期 smoke OK，等同放行條件 → 落檔
        write_baseline_file
        echo "能力面 baseline 已更新: $baseline_file"
        echo "UPDATE_BASELINE=OK"
      fi
      echo "codex-check: $(( age_s / 3600 ))h 前查過，跳過（-f 強制重查）。上次結果："
      cat "$cache"
      exit 0
    fi
  fi
fi

echo "=== installed ==="
printf '%s\n' "$disp_line"
echo "=== latest on npm ==="
# C3: npm view 離線/失敗留空（不可拿去跟 installed 比，否則離線就誤報 OUTDATED；smoke 才是權威判定）
# H3: env 收緊 + perl alarm watchdog（單一行程契約：SIGALRM 殺 npm 主行程=單一 node 行程）。
#     rc != 0（含 timeout 142）一律丟棄 stdout——部分輸出不得進 H5（否則 timeout 誤報 BEHIND/AHEAD）。
latest_raw=""
if latest_candidate="$(npm_config_fetch_retries=0 npm_config_fetch_timeout=15000 \
      perl -e 'alarm 20; exec @ARGV' -- npm view '@openai/codex' version 2>/dev/null)"; then
  latest_raw="$latest_candidate"
fi
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
    -1) verdict="BEHIND ($inst_ver -> $latest) -- 中性情報非更新指令：更新屬選擇性系統變更、可能造成參數/外掛/行為漂移；要更新先問使用者（npm install -g @openai/codex@latest），更新後跑 -f 重驗並檢視漂移" ;;
    1)  verdict="AHEAD ($inst_ver > $latest) -- 本機比 registry 新（prerelease/私建），非落後" ;;
    0)  verdict="CURRENT ($inst_ver vs $latest) -- base 版本相同（多半 prerelease 尾綴差異）" ;;
    *)  verdict="UNKNOWN (版本比較失敗) -- 無法判定新舊，改看下方 smoke test 認定可用性" ;;
  esac
fi
echo "$verdict"

echo "=== read-only smoke test ==="
# H2: 能力探測（非版本閘門）——help 已於檔頭單次抓取，use_lastmsg 已就緒：
#     有 --output-last-message 才用精確 sentinel 路徑；沒有 → legacy marker 路徑（已知 substring 弱點，見規劃書）。
lastmsg_file="$(mktemp "${TMPDIR:-/tmp}/codex-check-lastmsg.XXXXXX" 2>/dev/null || echo "${TMPDIR:-/tmp}/codex-check-lastmsg.$$")"
rm -f "$lastmsg_file"
set +e
if [ "$use_lastmsg" = "1" ]; then
  smoke_out="$(printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" \
    --output-last-message "$lastmsg_file" "Reply with exactly: CODEX_OK" 2>&1)"
else
  smoke_out="$(printf '' | codex exec --sandbox read-only --skip-git-repo-check -C "${TMPDIR:-/tmp}" \
    "Reply with exactly: CODEX_OK" 2>&1)"
fi
smoke=$?
set -e
printf '%s\n' "$smoke_out"
sentinel_ok=0
if [ "$use_lastmsg" = "1" ]; then
  # 精確比對：剝 CR、逐行 trim（兩次 sub，避 anchored-gsub-alternation 歷史相容疑慮）、略空白行後「恰一非空行 == CODEX_OK」
  if [ "$smoke" -eq 0 ] && [ -f "$lastmsg_file" ] && \
     awk '{ sub(/\r$/, ""); sub(/^[[:blank:]]+/, ""); sub(/[[:blank:]]+$/, "") }
          /^$/ { next }
          { n++; if ($0 != "CODEX_OK") bad=1 }
          END { exit (n == 1 && !bad) ? 0 : 1 }' "$lastmsg_file"; then
    sentinel_ok=1
  fi
else
  # legacy：剝 ANSI 後取「最後一個 codex marker 之後」段、substring 搜尋。
  # 每遇 marker 重置緩衝＝鏡像 PS -split parts[-1] 語義——取第一段會把「回覆後又印 marker+雜訊」
  # 的 transcript 誤判為通過（2026-07-16 對抗審查抓到的跨平台分歧）。
  esc="$(printf '\033')"
  clean="$(printf '%s' "$smoke_out" | sed "s/${esc}\[[0-9;]*m//g")"
  reply="$(printf '%s\n' "$clean" | awk '/^[[:space:]]*codex[[:space:]]*$/{buf=""; f=1; next} f{buf=buf $0 "\n"} END{printf "%s", buf}')"
  # case substring（零管線）：printf | grep -q 在 >64KB reply 時 SIGPIPE + pipefail 誤判失敗（同 help 探測地雷）
  if [ "$smoke" -eq 0 ]; then
    case "$reply" in *CODEX_OK*) sentinel_ok=1 ;; esac
  fi
fi
rm -f "$lastmsg_file"

if [ "$sentinel_ok" = "1" ] && [ "$flags_compatible" != "1" ]; then
  # smoke 過但依賴旗標相容性未確立 → 不寫快取（exit 仍以 smoke 為準；快取只是 optimization，不能背書相容性）
  echo "codex-check: smoke OK 但依賴旗標相容性未確立 → 不寫 24h 快取（下次呼叫仍全檢）"
elif [ "$sentinel_ok" = "1" ]; then
  cache_tmp="$(mktemp "${cache}.tmp.XXXXXX")"
  printf '%s installed=%s latest=%s verdict=%s smoke=OK at %s\n' \
    "$cache_format" "$inst_ver" "$latest_disp" "$verdict" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$cache_tmp" \
    && mv -f "$cache_tmp" "$cache"
else
  if [ "$smoke" -eq 0 ]; then
    echo "codex-check: smoke exit 0 但無精確 CODEX_OK sentinel（codex 可能壞了）-- 刪快取，下次強制重查" >&2
  else
    echo "codex-check: smoke test failed (exit $smoke) -- 刪除快取，下次呼叫強制重查" >&2
  fi
  rm -f "$cache"
  [ "$smoke" -ne 0 ] || smoke=1
fi
if [ "$baseline_pending" = "1" ]; then
  if [ "$sentinel_ok" = "1" ]; then
    write_baseline_file
    echo "能力面 baseline 已更新: $baseline_file"
    echo "UPDATE_BASELINE=OK"
  else
    echo "UPDATE_BASELINE=NOT_APPLIED（smoke 失敗，baseline 未動）"
  fi
fi
exit "$smoke"
