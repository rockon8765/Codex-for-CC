#!/usr/bin/env node
// CLASS B (Windows/NTFS 8.3 short-name alias) real-filesystem test — SEPARATE from gate-cases.json
// because the gate harness uses an empty fake ~/.claude, which has no 8.3 alias to resolve.
//
// This test creates a REAL ~/.claude with a REAL settings.json (+ scoped .super-mode-active, NO credential),
// derives the NTFS 8.3 short name of settings.json (via `cmd /c dir /x`), then calls decide() with that
// short-name file_path and asserts DENY. The win is that canonicalize()'s realpathSync.native resolves the
// existing 8.3 alias back to the long name settings.json -> isSecurityCriticalPath -> gated, EVEN THOUGH the
// scope-outside shortcut would otherwise fire (fp is not under the repo scope).
//
// SKIPS cleanly (exit 0) when: not win32, junctions/short-names unavailable, or 8dot3 name generation is
// disabled on the volume (no `~` short name produced). A skip is a pass — it just means the alias can't exist.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execSync } = require("child_process");

const hookCandidates = [
  path.join(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js"),
  path.join(os.homedir(), ".claude", "hooks", "super-mode-consult-gate.js"),
];
const hookPath = hookCandidates.find((p) => fs.existsSync(p));
if (!hookPath) {
  console.error("hook not found in: " + hookCandidates.join(" | "));
  process.exit(1);
}
const { decide, canonicalize } = require(hookPath);

function skip(msg) {
  console.log("SKIP (" + msg + ")");
  process.exit(0);
}

if (process.platform !== "win32") skip("not win32");

const base = fs.mkdtempSync(path.join(os.tmpdir(), "class-b-"));
let exitCode = 0;
try {
  // Real security files under a real fake-~/.claude.
  fs.writeFileSync(path.join(base, "settings.json"), "{}");
  fs.writeFileSync(path.join(base, ".super-mode-active"), "C:\\someRepo"); // SCOPED flag, NO credential

  // Derive the 8.3 short name of settings.json from `dir /x`.
  let shortName = null;
  try {
    const out = execSync('cmd /c dir /x /a-d "' + base + '"', { encoding: "utf8", windowsHide: true });
    for (const line of out.split(/\r?\n/)) {
      // `dir /x` line ends with the long name, preceded by the (optional) 8.3 short name column.
      const m = line.match(/\s(\S+)\s+settings\.json\s*$/i);
      if (m && /~/.test(m[1])) { shortName = m[1]; break; }
    }
  } catch (e) {
    skip("dir /x failed: " + (e && e.message));
  }
  if (!shortName) skip("no 8.3 short name produced (8dot3 likely disabled on this volume)");

  const shortFp = path.join(base, shortName); // e.g. <base>\SETTIN~1.JSO

  // Confirm the short name is a genuine alias of settings.json (same file identity).
  let aliasOk = false;
  try {
    aliasOk = path.basename(fs.realpathSync.native(shortFp)).toLowerCase() === "settings.json";
  } catch (e) {}
  if (!aliasOk) skip("short name '" + shortName + "' did not resolve to settings.json");

  const canon = canonicalize(shortFp);
  const res = decide({ tool_name: "Write", tool_input: { file_path: shortFp } }, { baseDir: base });
  const denied = res && !res.allow;

  console.log("8.3 short name:      " + shortName + "  (aliases settings.json: " + aliasOk + ")");
  console.log("canonicalize:        " + JSON.stringify(canon));
  console.log("decide(Write short): " + (denied ? "DENY" : "ALLOW") + "   [expect DENY]");

  if (!denied) {
    console.error("FAIL: 8.3 short-name write to a real settings.json was ALLOWED (realpath did not defeat the alias)");
    exitCode = 1;
  } else if (!/settings\.json$/i.test(String(canon && canon.path))) {
    console.error("FAIL: canonicalize did not resolve the 8.3 alias to settings.json");
    exitCode = 1;
  } else {
    console.log("PASS");
  }
} finally {
  fs.rmSync(base, { recursive: true, force: true });
}
process.exit(exitCode);
