#!/usr/bin/env node
const fs = require("fs");
const os = require("os");
const path = require("path");

const casesPath = path.join(__dirname, "gate-cases.json");
const cases = JSON.parse(fs.readFileSync(casesPath, "utf8").replace(/^﻿/, ""));
const { decide } = require(path.join(__dirname, "..", "..", "..", "hooks", "super-mode-consult-gate.js"));

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
      fs.writeFileSync(token, new Date().toISOString(), "utf8");
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
