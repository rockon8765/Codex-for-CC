#!/usr/bin/env node
// 超級模式 consult-gate 回歸測試臺：讀 gate-cases.json，逐案呼叫 decide(input, fakeBaseDir)。
// 佔位符：__TMP__ → os.tmpdir()（真實系統暫存，不可自造——scratchpad 豁免判定依賴它）、
//         __BASE__ → 每案獨立的假 ~/.claude（mkdtemp，案後即刪）。
const fs = require("fs");
const os = require("os");
const path = require("path");

const casesPath = path.join(__dirname, "gate-cases.json");
const cases = JSON.parse(fs.readFileSync(casesPath, "utf8"));

// hook 單一真相在 ~/.claude/hooks/（部署後）；未部署（如 repo 內 clone）fallback 到
// 相對三層上的 hooks/（tests → 超級模式 → skills → base → hooks，live 與 repo 布局皆成立）
const hookCandidates = [
  path.join(os.homedir(), ".claude", "hooks", "super-mode-consult-gate.js"),
  path.join(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js"),
];
const hookPath = hookCandidates.find((p) => fs.existsSync(p));
if (!hookPath) {
  console.error("hook not found in: " + hookCandidates.join(" | "));
  process.exit(1);
}
const { decide } = require(hookPath);

function replacePlaceholders(value, replacements) {
  if (typeof value === "string") {
    return value.replace(/__TMP__/g, replacements.tmp).replace(/__BASE__/g, replacements.base);
  }
  if (Array.isArray(value)) return value.map((v) => replacePlaceholders(v, replacements));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([k, v]) => [k, replacePlaceholders(v, replacements)])
    );
  }
  return value;
}

const failures = [];

for (const tc of cases) {
  const fakeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), "gate-"));
  const replacements = { tmp: os.tmpdir(), base: fakeBaseDir };

  try {
    if (tc.flagContent !== null && tc.flagContent !== undefined) {
      fs.writeFileSync(
        path.join(fakeBaseDir, ".super-mode-active"),
        replacePlaceholders(String(tc.flagContent), replacements),
        "utf8"
      );
    }

    if (tc.tokenAgeMs !== null && tc.tokenAgeMs !== undefined) {
      const token = path.join(fakeBaseDir, ".super-mode-consult-ok");
      const content = (tc.tokenContent !== undefined && tc.tokenContent !== null)
        ? replacePlaceholders(tc.tokenContent, replacements)
        : new Date().toISOString();
      fs.writeFileSync(token, content, "utf8");
      const t = new Date(Date.now() - Number(tc.tokenAgeMs));
      fs.utimesSync(token, t, t);
    }

    const input = replacePlaceholders(tc.input, replacements);
    const res = decide(input, fakeBaseDir);
    const got = res && res.allow ? "allow" : "deny";
    if (got !== tc.expect) {
      failures.push({
        name: tc.name,
        expect: tc.expect,
        got,
        reason: res && res.reason ? res.reason : ""
      });
    }
  } catch (e) {
    failures.push({ name: tc.name, expect: tc.expect, got: "error", reason: e.stack || String(e) });
  } finally {
    fs.rmSync(fakeBaseDir, { recursive: true, force: true });
  }
}

const passed = cases.length - failures.length;
console.log(`PASS ${passed}/${cases.length}`);

if (failures.length) {
  for (const f of failures) {
    console.error(`FAIL ${f.name}: expected ${f.expect}, got ${f.got}`);
    if (f.reason) console.error(f.reason);
  }
  process.exit(1);
}
