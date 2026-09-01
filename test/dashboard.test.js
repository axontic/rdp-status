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
  assert.match(html, /function detailsButton\(info\)/);
  assert.match(html, /type="button" class="details-button"/);
  assert.match(html, /aria-expanded=/);
  assert.match(html, /aria-label=/);
  assert.match(html, /data-vm=/);
  assert.match(html, /white-space:\s*pre-wrap/);
  assert.doesNotMatch(html, /class="[^"$]*machine-disclosure/);
});

test("table and card templates render machine details", () => {
  assert.match(html, /function hasMachineDetails\(info\)/);
  assert.match(html, /function renderMachineDetails\(info\)/);
  assert.match(html, /escapeHtml\(info\.description\)/);
  assert.match(html, /inventory\.ramGb/);
  assert.match(html, /inventory\.gpus/);
  assert.match(html, /inventory\.outlook/);
  assert.match(html, /parts\.map\(escapeHtml\)/);
  assert.match(html, /renderMachineDetails\(info\)/);
});
