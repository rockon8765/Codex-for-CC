#!/usr/bin/env node
// 超級模式 consult-gate 回歸測試臺：讀 gate-cases.json，逐案呼叫 decide(input, fakeBaseDir)。
// 佔位符：__TMP__ → os.tmpdir()（真實系統暫存，不可自造——scratchpad 豁免判定依賴它）、
//         __BASE__ → 每案獨立的假 ~/.claude（mkdtemp，案後即刪）。
const fs = require("fs");
const os = require("os");
const path = require("path");

const casesPath = path.join(__dirname, "gate-cases.json");
const cases = JSON.parse(fs.readFileSync(casesPath, "utf8").replace(/^﻿/, ""));

// hook 載入：同目錄樹 repo 內 hooks/ 優先（tests → 超級模式 → skills → base → hooks，
// repo 與部署 ~/.claude 布局皆成立），確保 repo 測試驗證 repo 內 hook、不被安裝版污染；
// 相對路徑找不到(非標準部署/只同步 tests)才 fallback 到 ~/.claude/hooks/ 現役 hook。
const hookCandidates = [
  path.join(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js"),
  path.join(os.homedir(), ".claude", "hooks", "super-mode-consult-gate.js"),
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
    // MCP policy 注入走第二參數(物件形式)；一般案例維持傳字串 baseDir(向後相容)。
    const testOpts = (tc.mcpPolicy !== undefined && tc.mcpPolicy !== null)
      ? { baseDir: fakeBaseDir, mcpPolicy: replacePlaceholders(tc.mcpPolicy, replacements) }
      : fakeBaseDir;
    const res = decide(input, testOpts);
    const got = res && res.allow ? "allow" : "deny";
    if (got !== tc.expect) {
      failures.push({
        name: tc.name,
        expect: tc.expect,
        got,
        reason: res && res.reason ? res.reason : ""
      });
    } else if (tc.expectReasonIncludes) {
      const reason = res && res.reason ? res.reason : "";
      if (!reason.includes(tc.expectReasonIncludes)) {
        failures.push({
          name: tc.name,
          expect: 'reason~="' + tc.expectReasonIncludes + '"',
          got: reason || "(no reason)",
          reason: "reason substring missing"
        });
      }
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
