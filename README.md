# Codex-for-CC — 超級模式 (Super Mode)

A **Claude Code** skill that turns Claude into an **orchestrator** and the **OpenAI Codex CLI** into a **worker**, so heavy implementation work is offloaded to Codex (saving Claude Code usage) while Claude keeps planning, reviewing, and holding the spec as the contract.

A `PreToolUse` **consult-gate** hook enforces the discipline: while super mode is armed, state-changing tool calls (file writes, shell, MCP writes, outbound builtins) are **default-denied** unless Claude has a fresh (≤20 min) "second opinion" credential minted by running a read-only Codex consult first.

> ⚠️ **Work in progress.** This repo is the current snapshot. A prior audit found real issues (a gate bypass, silent Codex failures, cost anti-patterns). The full, verified, step-by-step remediation plan lives in [`skills/超級模式/FIX-PLAN.md`](skills/超級模式/FIX-PLAN.md) — read it before relying on the gate for security.

---

## What's in here

```
skills/超級模式/
  SKILL.md                  # the skill: spec-first → orchestrate Codex → milestone write-back
  FIX-PLAN.md               # phased, weak-AI-followable repair plan (audited & validated)
  references/
    orchestration.md        # templates (AGENTS.md, brief, consult) + full gate semantics
  scripts/
    super-mode.ps1          # arm/disarm the flag:  -On [-Scope <dir>] | -Off | (status)
    codex-consult.ps1       # read-only second opinion; writes the consult credential
    codex-exec.ps1          # dispatch a task to Codex (workspace-write sandbox)
    codex-check.ps1         # verify Codex CLI version + read-only smoke test (24h cache)
hooks/
    super-mode-consult-gate.js   # PreToolUse gate (default-deny while armed; fail-open otherwise)
```

## How it works (one milestone)

1. **Arm** with a project scope: `super-mode.ps1 -On -Scope <repo>` (writes `~/.claude/.super-mode-active`).
2. **Spec-first** — no implementation without an agreed spec/plan md.
3. **Consult before acting** — write a brief to the scratchpad, run `codex-consult.ps1`; on success it writes `~/.claude/.super-mode-consult-ok`, unlocking gated actions for 20 minutes.
4. **Dispatch** — write a self-contained task brief, run `codex-exec.ps1` in the background; Codex writes the code.
5. **Review** — Claude reviews the diff; reject and re-dispatch if it fails.
6. **Milestone write-back** — tick the spec md, then commit (which demotes the credential to 3 min, forcing a fresh consult next milestone).
7. **Disarm** — `super-mode.ps1 -Off` (clears the flag + credential). The hook also self-heals: a flag older than 8h is treated as stale and removed.

**Fail-open by design:** with no flag, or on any hook error/malformed input, the gate allows the call — normal (non-super-mode) sessions are never blocked.

## Install

```powershell
# 1. Skill  -> ~/.claude/skills/
Copy-Item -Recurse ".\skills\超級模式" "$env:USERPROFILE\.claude\skills\"

# 2. Hook   -> ~/.claude/hooks/
Copy-Item ".\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\"
```

3. Wire the hook in `~/.claude/settings.json` under `hooks.PreToolUse` (see [`settings.snippet.json`](settings.snippet.json)):

```json
{
  "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|RemoteTrigger|PushNotification|CronCreate|CronDelete|mcp__.*",
  "hooks": [
    { "type": "command", "command": "node C:/Users/user/.claude/hooks/super-mode-consult-gate.js" }
  ]
}
```

## Environment assumptions (adapt to your machine)

This was built for one specific setup — **paths are hardcoded** and you will need to edit them:

- **Windows 11**, **PowerShell 5.1** is the hook/script runtime.
- **OpenAI Codex CLI** installed at `C:\npm\codex.cmd` (edit `$codexCmd` in the scripts if yours differs).
- User home hardcoded as `C:\Users\user` in the settings matcher command and some docs.
- Auth: the scripts use your saved Codex CLI login (no API key is embedded or required).
- **Codex CLI ships roughly weekly** — flags/behavior drift. Anything that touches Codex flags should be re-verified with `codex exec --help` first (the FIX-PLAN's Phase 5 assumes this).

## Known gotchas (hard-won)

- Claude's file-writer emits UTF-8 **without BOM**; PowerShell 5.1 mangles Chinese `.ps1` files without a BOM. After editing any `.ps1`, re-apply a UTF-8 BOM and re-parse (see FIX-PLAN §0.5).
- Briefs are piped to Codex as raw UTF-8 bytes via `cmd /s /c "... < file"` because PS 5.1's `$OutputEncoding` doesn't affect native pipes (non-ASCII would turn into `?`).

## Status & roadmap

See [`skills/超級模式/FIX-PLAN.md`](skills/超級模式/FIX-PLAN.md) — a phased repair plan (Phase 1 security hardening → Phase 5 adopting newer Codex capabilities), each step with purpose, acceptance criteria, future-proofing, and rollback, plus 8 invariants and a regression test-harness spec. It has itself been adversarially validated.
