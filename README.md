# Codex-for-CC — 超級模式 (Super Mode)

A **Claude Code** skill that turns Claude into an **orchestrator** and the **OpenAI Codex CLI** into a **worker**, so heavy implementation work is offloaded to Codex (saving Claude Code usage) while Claude keeps planning, reviewing, and holding the spec as the contract.

A `PreToolUse` **consult-gate** hook enforces the discipline: while super mode is armed, state-changing tool calls (file writes, shell, MCP writes, outbound builtins) are **default-denied** unless Claude has a fresh (≤20 min) "second opinion" credential minted by running a read-only Codex consult first.

---

## Two platform versions

This repo ships the **same skill for two platforms**. They are behavior-equivalent — same findings, same invariants (I1–I8, plus macOS-only I9), same acceptance criteria — but the *implementation mechanism* is translated per platform (PowerShell vs bash, BOM handling, stdin wiring, path rules). Pick the one for your machine:

| | [`windows/`](windows/) | [`macos/`](macos/) |
|---|---|---|
| Hook/script runtime | PowerShell 5.1 + Node | bash/zsh + Node |
| Worker scripts | `*.ps1` | `*.sh` |
| Codex CLI location | `C:\npm\codex.cmd` (hardcoded) | `codex` on `PATH` (Homebrew npm global) |
| Gate deny mechanism | `permissionDecision` / exit 2 | stderr + exit 2 |
| Settings file to wire the hook | `settings.json` | `settings.local.json` |
| Repair record | [`windows/skills/超級模式/FIX-PLAN.md`](windows/skills/超級模式/FIX-PLAN.md) | [`macos/skills/超級模式/FIX-PLAN.md`](macos/skills/超級模式/FIX-PLAN.md) |

> **Status.** An audit of the Windows version found real issues (a gate bypass, silent Codex failures, cost anti-patterns); Phases 1–4 were implemented, verified, and deployed, and Phase 5 evaluated. The macOS version is a validated port of that work — findings and invariants carried over, mechanism translated, verified with a 34-case regression harness + real end-to-end run. Each platform's full step-by-step record lives in its own `FIX-PLAN.md` (linked above).

---

## Claude vs Codex — what runs where (read this first)

A common misconception: *"when I use Claude Code's UltraCode mode, my subagents become Codex."* **They don't.** This project has **two independent mechanisms** that are easy to conflate:

**1. Claude Code UltraCode / Workflow — Anthropic's own multi-agent**
- The subagents it fans out are **always Claude models** — never Codex.
- Their tokens **count fully against your Claude quota** (no discount; you can route individual agents to Haiku to cut cost, but they are still Claude).
- So UltraCode by itself **does not save Claude usage — it spends more** (more Claude agents = more Claude tokens). Its purpose is *quality* (multiple perspectives, adversarial review), not savings.

**2. This skill's Codex offload — where the Claude-usage savings actually come from**
- Codex is **not a subagent type** — UltraCode cannot dispatch a "Codex agent".
- Codex only does work in **one place**: the main Claude (the orchestrator) explicitly shells out to `codex-exec` (`.ps1` on Windows / `.sh` on macOS → `codex exec`). That is a separate external CLI process, billed against your ChatGPT/Codex plan — **not** your Claude quota.
- Handing the heavy implementation work to Codex is what saves Claude usage.

Stacked together (see skill §5):

```text
Main Claude (orchestrator)
├─ UltraCode Workflow ─────► spawns [Claude subagents]: read-only research / planning / review
│                             (Claude — counts against your Claude quota)
└─ Main Claude dispatches ─► shells out to `codex exec` ─► [Codex]: writes the code
                              (Codex — counts against your ChatGPT/Codex plan)
```

**Hard rule (enforced in §5):** Workflow/subagents must **never** call Codex themselves — only the main orchestrator dispatches Codex. Otherwise N parallel Claude subagents would each shell out to Codex, burning Codex quota and fighting over the single shared consult credential.

**Bottom line:** UltraCode → *more* Claude. Saving Claude usage → the Codex offload. They are **different knobs**, and they compose (Claude subagents review; Codex writes) — but opening UltraCode never turns a subagent into Codex.

---

## What's in here

```
windows/                         # PowerShell version (audited, deployed)
  settings.snippet.json
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  FIX-PLAN.md  references/orchestration.md
    scripts/  super-mode.ps1  codex-consult.ps1  codex-exec.ps1  codex-check.ps1
    tests/    run-gate-tests.js  run-gate-tests.ps1  gate-cases.json

macos/                           # bash version (ported, verified)
  settings.snippet.json
  hooks/super-mode-consult-gate.js
  skills/超級模式/
    SKILL.md  FIX-PLAN.md  references/orchestration.md
    scripts/  super-mode.sh  codex-consult.sh  codex-exec.sh  codex-check.sh
    tests/    run-gate-tests.js  run-e2e.sh  gate-cases.json
```

## How it works (one milestone)

Commands below use the macOS (`.sh`) names; the Windows equivalents are the `.ps1` scripts with `-On/-Off/-Scope`-style flags (see [`windows/`](windows/)).

1. **Arm** with a project scope: `super-mode.sh on --scope <repo>` (writes `~/.claude/.super-mode-active`).
2. **Spec-first** — no implementation without an agreed spec/plan md.
3. **Consult before acting** — write a brief to the scratchpad, run `codex-consult.sh`; on success it writes `~/.claude/.super-mode-consult-ok`, unlocking gated actions for 20 minutes.
4. **Dispatch** — write a self-contained task brief, run `codex-exec.sh -q` in the background; Codex writes the code.
5. **Review** — Claude reviews `_last.txt` + `git diff`; reject and re-dispatch if it fails.
6. **Milestone write-back** — tick the spec md, then commit (which demotes the credential to 3 min, forcing a fresh consult next milestone).
7. **Disarm** — `super-mode.sh off` (clears the flag + credential, purges >14-day logs). The hook also self-heals: a flag older than 8h is treated as stale and removed.

**Fail-open by design:** with no flag, or on any hook error/malformed input, the gate allows the call — normal (non-super-mode) sessions are never blocked.

## Install

**macOS**
```bash
# 1. Skill -> ~/.claude/skills/    2. Hook -> ~/.claude/hooks/
cp -R "macos/skills/超級模式" ~/.claude/skills/
cp    "macos/hooks/super-mode-consult-gate.js" ~/.claude/hooks/
# 3. Wire the hook into ~/.claude/settings.local.json (see macos/settings.snippet.json),
#    editing the absolute path to match your home directory.
# 4. Verify:
node ~/.claude/skills/超級模式/tests/run-gate-tests.js   # PASS 34/34
bash ~/.claude/skills/超級模式/tests/run-e2e.sh          # 11 passed
```

**Windows**
```powershell
Copy-Item -Recurse ".\windows\skills\超級模式" "$env:USERPROFILE\.claude\skills\"
Copy-Item ".\windows\hooks\super-mode-consult-gate.js" "$env:USERPROFILE\.claude\hooks\"
# Then wire the hook in ~/.claude/settings.json (see windows/settings.snippet.json).
```

The hook is **fail-open and disabled until armed** — installing it does not affect normal sessions; it only acts after `super-mode.{sh,ps1} on`.

## Environment assumptions (adapt to your machine)

**macOS**
- **bash/zsh** runtime; **Node** for the hook; `codex` on `PATH` (Homebrew npm global at `/opt/homebrew/lib/node_modules/@openai/codex`). No path is hardcoded in the scripts (they use `$HOME`) or the hook (`os.homedir()`); only the `settings.local.json` hook command needs your absolute home path.
- Path equivalence is handled: the gate normalizes `/private/tmp` ↔ `/tmp` and `/private/var` ↔ `/var` so the Claude Code scratchpad (`/private/tmp/claude-*`) is correctly treated as an exempt temp path.

**Windows**
- **Windows 11**, **PowerShell 5.1** runtime. **Codex CLI** at `C:\npm\codex.cmd` (edit `$codexCmd` if yours differs). User home hardcoded as `C:\Users\user` in the settings matcher command and some docs.

**Both**
- Auth: the scripts use your saved Codex CLI login (no API key is embedded or required).
- **Codex CLI ships roughly weekly** — flags/behavior drift. Anything touching Codex flags should be re-verified with `codex exec --help` first (each FIX-PLAN's Phase 0/5 assumes this).

## Known gotchas (hard-won)

**Windows-only** — do **not** port these to macOS:
- Claude's file-writer emits UTF-8 **without BOM**; PowerShell 5.1 mangles Chinese `.ps1` without a BOM. After editing any `.ps1`, re-apply a UTF-8 BOM and re-parse (see `windows/.../FIX-PLAN.md` §0.5).
- Briefs are piped to Codex via `cmd /s /c "... < file"` because PS 5.1's `$OutputEncoding` doesn't affect native pipes (non-ASCII would turn into `?`).

**macOS**
- No BOM problem exists — those steps are deliberately removed. Briefs go to Codex over ordinary stdin redirection (`< file`); stderr is captured to a separate file and merged into the log (never `2>&1`, which would echo Codex noise back into Claude's context).
- `set -e` + pipelines can swallow Codex's exit code — the scripts use a fixed `set +e … ${PIPESTATUS[0]} … set -e` shape (FIX-PLAN §0.5).

## Status & roadmap

Each platform has a phased, weak-AI-followable repair plan (purpose / acceptance / future-proofing / rollback per step, plus the invariant list and a regression test-harness spec), itself adversarially validated:

- Windows: [`windows/skills/超級模式/FIX-PLAN.md`](windows/skills/超級模式/FIX-PLAN.md)
- macOS: [`macos/skills/超級模式/FIX-PLAN.md`](macos/skills/超級模式/FIX-PLAN.md)
