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

test("table template renders machine details", () => {
  assert.match(html, /function hasMachineDetails\(info\)/);
  assert.match(html, /function renderMachineDetails\(info\)/);
  assert.match(html, /escapeHtml\(info\.description\)/);
  assert.match(html, /inventory\.ramGb/);
  assert.match(html, /inventory\.os/);
  assert.match(html, /<dt>Windows<\/dt>/);
  assert.match(html, /<dt>Last update<\/dt>/);
  assert.match(html, /inventory\.outlook/);
  assert.match(html, /parts\.map\(escapeHtml\)/);
  assert.match(html, /renderMachineDetails\(info\)/);
});

test("card view always hides machine details", () => {
  const cardsStart = html.indexOf("function renderCards(data)");
  const loadStart = html.indexOf("// --- Load + Poll ---", cardsStart);
  const cardsRenderer = html.slice(cardsStart, loadStart);

  assert.ok(cardsStart >= 0);
  assert.ok(loadStart > cardsStart);
  assert.doesNotMatch(cardsRenderer, /detailsButton\(info\)/);
  assert.doesNotMatch(cardsRenderer, /renderMachineDetails\(info\)/);
  assert.doesNotMatch(cardsRenderer, /\$\{details\}/);
});

test("card info button opens details in table view", () => {
  assert.match(html, /function cardInfoButton\(info\)/);
  assert.match(html, /class="card-info-button"/);
  assert.match(html, /function showCardDetails\(target\)/);
  assert.match(html, /expandedMachines\.add\(vm\)/);
  assert.match(html, /viewMode = "table"/);
  assert.match(html, /applyViewMode\(\)/);
  assert.match(html, /scrollIntoView/);
  assert.match(html, /tableButton\.focus\(\)/);
});
