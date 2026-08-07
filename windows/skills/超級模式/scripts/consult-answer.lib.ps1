# consult-answer.lib.ps1 -- 憑證鑄造條件的純函式（被 codex-consult.ps1 dot-source）
#
# 為什麼要獨立成一支：憑證鑄造條件只能用「真的叫一次 Codex」來驗，等於沒有自動化測試
# （要額度、要網路、CI 跑不了）。把判斷抽成無副作用的純函式後，tests/consult-answer.tests.ps1
# 可以直接餵各種假回覆做分支測試與變異注入，不必啟動 codex。
#
# 判準（回傳 @{ Ok=bool; Code=int; Reason=string; Verdict=string }）：
#   - 一般模式：回覆去除零寬/控制字元後 >= MinChars，且首行**大小寫敏感**符合 ^(ALLOW|BLOCK):
#   - -SchemaFile 模式：輸出應為 JSON → 改驗「能 parse 成 JSON」，不套字元數門檻
#     （合法的短 JSON 例如 {"ok":true} 不該因為字數不足被判失敗）
#   - 討論模式(-NoCredential)：只驗非空（全域規則的日常諮詢沒有強制裁決格式）

function Get-ConsultAnswerText {
  param([string[]]$Lines)
  if (-not $Lines) { return '' }
  $text = ($Lines -join "`n")
  # 零寬與雙向控制字元不算「內容」：否則 "ALLOW:" 後面貼 34 個 U+200B 就能湊過字數門檻。
  # \p{Cf} = format 字元(含 U+200B..U+200F/U+202A..U+202E/U+FEFF)；\p{Cc} = 控制字元(保留 \n\t 由 Trim 處理)。
  $cleaned = [regex]::Replace($text, '[\p{Cf}]', '')
  $cleaned = [regex]::Replace($cleaned, '[\p{Cc}-[\r\n\t]]', '')
  return $cleaned.Trim()
}

function Get-ConsultFirstLine {
  param([string[]]$Lines)
  if (-not $Lines) { return '' }
  foreach ($l in $Lines) {
    $c = [regex]::Replace([string]$l, '[\p{Cf}]', '').Trim()
    if ($c) { return $c }
  }
  return ''
}

function Test-ConsultAnswer {
  param(
    [string[]]$Lines,
    [switch]$NoCredential,
    [string]$SchemaFile,
    [int]$MinChars = 40
  )
  $text = Get-ConsultAnswerText -Lines $Lines
  $first = Get-ConsultFirstLine -Lines $Lines
  $schemaMode = [bool]$SchemaFile

  if (-not $text) {
    return @{ Ok = $false; Code = 43; Verdict = ''
      Reason = "CONSULT_UNUSABLE_ANSWER: codex exit 0 但回覆是空的，未鑄造憑證。這通常代表諮詢實際上沒發生(額度、認證、或 prompt 沒送到)。" }
  }

  if ($schemaMode) {
    # schema 模式：exit 0 不足以證明輸出真的符合 schema(上游有過 --output-schema 在某些路徑被忽略、
    # 仍產出 malformed 輸出的回報)。這裡至少確認「是合法 JSON」——本地不做完整 schema 驗證，
    # 但要擋掉「拿 -SchemaFile 當免驗金牌」。
    try { $null = $text | ConvertFrom-Json -ErrorAction Stop }
    catch {
      return @{ Ok = $false; Code = 43; Verdict = ''
        Reason = "CONSULT_SCHEMA_NOT_JSON: 指定了 -SchemaFile 但 codex 的最終輸出不是合法 JSON，未鑄造憑證。" }
    }
    return @{ Ok = $true; Code = 0; Verdict = 'SCHEMA'; Reason = '' }
  }

  if ($text.Length -lt $MinChars) {
    return @{ Ok = $false; Code = 43; Verdict = ''
      Reason = ("CONSULT_UNUSABLE_ANSWER: codex exit 0 但回覆過短(" + $text.Length + " 有效字元 < " + $MinChars +
                "，零寬/控制字元不計)，未鑄造憑證。這通常代表諮詢實際上沒發生(額度、認證、或 prompt 沒送到)。") }
  }

  if ($NoCredential) { return @{ Ok = $true; Code = 0; Verdict = 'DISCUSSION'; Reason = '' } }

  # -cmatch = 大小寫敏感。PowerShell 的 -match 預設不分大小寫，會讓 'allow:' 通過，
  # 與 SKILL §3.5 宣告的 uppercase 契約不符（也讓「首行剛好以 allow 開頭的散文」意外過關）。
  if ($first -cmatch '^(ALLOW|BLOCK)\s*:') {
    return @{ Ok = $true; Code = 0; Verdict = $Matches[1]; Reason = '' }
  }

  return @{ Ok = $false; Code = 43; Verdict = ''
    Reason = ("CONSULT_NO_VERDICT: 首行不是 ^(ALLOW|BLOCK): 格式(大小寫敏感)，依 SKILL §3.5 視為 BLOCK，未鑄造憑證。" +
              "首行實際內容: '" + $first + "'。請在簡報結尾明確要求首行裁決後重問一次。") }
}
