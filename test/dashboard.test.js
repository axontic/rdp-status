"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(
  path.join(__dirname, "..", "public", "index.html"),
  "utf8",
);

test("dashboard includes accessible machine disclosures", () => {
  assert.match(html, /const expandedMachines = new Set\(\)/);
  assert.match(html, /function escapeHtml\(s\)/);
  assert.match(html, /aria-expanded=/);
  assert.match(html, /data-vm=/);
  assert.match(html, /white-space:\s*pre-wrap/);
  assert.match(html, /event\.key === "Enter"/);
  assert.match(html, /event\.key === " "/);
});

test("table and card templates render machine descriptions", () => {
  const occurrences = html.match(/class="machine-description"/g) || [];
  assert.equal(occurrences.length, 2);
  assert.match(html, /escapeHtml\(info\.description\)/);
});
