# review-output.schema.json 授權告示

同目錄的 `review-output.schema.json` 改寫自 OpenAI codex-plugin-cc v1.0.5–v1.0.6 的 `plugins/codex/schemas/review-output.schema.json`（Apache-2.0，Copyright 2026 OpenAI）。Codex-for-CC 做了以下修改：`$schema` 由 2020-12 改為 draft-07、刪除 5 處 `minLength: 1`、改為緊湊排版。欄位、enum 與鍵的順序與上游相同。

JSON 檔本身不放註記：這份 schema 會原樣傳給 `codex exec --output-schema`，在 JSON 內加註記會不會被接受，還沒有實測；未經實測前不在 JSON 內加註記。

見 Codex-for-CC repo 根目錄（https://github.com/rockon8765/Codex-for-CC）的 LICENSE、NOTICE 與 THIRD_PARTY_NOTICES.md。
