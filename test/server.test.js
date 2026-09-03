"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { createApp, loadMachineInfo } = require("../server");

function temporaryDirectory(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "rdp-status-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test("loads valid machine descriptions", (t) => {
  const directory = temporaryDirectory(t);
  const filePath = path.join(directory, "machine-info.json");
  fs.writeFileSync(
    filePath,
    JSON.stringify({ "VM-ONE": "Hardware\nSoftware", "vm-one": "Other" }),
  );

  assert.deepEqual(loadMachineInfo(filePath), {
    "VM-ONE": "Hardware\nSoftware",
    "vm-one": "Other",
  });
});

test("ignores invalid machine descriptions and warns", (t) => {
  const directory = temporaryDirectory(t);
  const filePath = path.join(directory, "machine-info.json");
  fs.writeFileSync(
    filePath,
    JSON.stringify({ valid: "Description", empty: "  ", number: 42 }),
  );
  const warnings = [];

  assert.deepEqual(
    loadMachineInfo(filePath, { warn: (text) => warnings.push(text) }),
    {
      valid: "Description",
    },
  );
  assert.equal(warnings.length, 2);
});

test("silently accepts a missing machine information file", (t) => {
  const directory = temporaryDirectory(t);
  const warnings = [];

  assert.deepEqual(
    loadMachineInfo(path.join(directory, "missing.json"), {
      warn: (text) => warnings.push(text),
    }),
    {},
  );
  assert.deepEqual(warnings, []);
});

test("warns and returns no descriptions for malformed JSON", (t) => {
  const directory = temporaryDirectory(t);
  const filePath = path.join(directory, "machine-info.json");
  fs.writeFileSync(filePath, "{");
  const warnings = [];

  assert.deepEqual(
    loadMachineInfo(filePath, { warn: (text) => warnings.push(text) }),
    {},
  );
  assert.equal(warnings.length, 1);
});

async function withServer(t, options = {}) {
  const server = createApp(options).listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  return `http://127.0.0.1:${server.address().port}`;
}

async function postStatus(baseUrl, body) {
  const response = await fetch(`${baseUrl}/api/status`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  assert.equal(response.status, 200);
}

test("enriches matching VMs without accepting client descriptions", async (t) => {
  const baseUrl = await withServer(t, {
    machineInfo: { "VM-ONE": "Hardware\nSoftware" },
  });
  await postStatus(baseUrl, {
    vm: "VM-ONE",
    description: "client controlled",
    sessions: [{ type: "rdp", state: "active" }],
  });
  await postStatus(baseUrl, { vm: "vm-one" });

  const body = await fetch(`${baseUrl}/api/status`).then((response) =>
    response.json(),
  );
  assert.equal(body["VM-ONE"].description, "Hardware\nSoftware");
  assert.equal(body["VM-ONE"].status, "BUSY");
  assert.equal(body["vm-one"].description, undefined);
  assert.equal(
    Object.prototype.hasOwnProperty.call(body["vm-one"], "description"),
    false,
  );
});

test("uses the injected offline threshold", async (t) => {
  const baseUrl = await withServer(t, { offlineMs: -1 });
  await postStatus(baseUrl, { vm: "VM-OFFLINE" });

  const body = await fetch(`${baseUrl}/api/status`).then((response) =>
    response.json(),
  );
  assert.equal(body["VM-OFFLINE"].effectiveStatus, "OFFLINE");
});

test("validates and exposes inventory reported by a client", async (t) => {
  const baseUrl = await withServer(t);
  await postStatus(baseUrl, {
    vm: "VM-INVENTORY",
    inventory: {
      ramGb: 16,
      os: {
        productName: "Microsoft Windows 11 Enterprise",
        displayVersion: "24H2",
        build: "26100.4946",
        lastUpdateId: "KB5063878",
        lastUpdateDate: "2026-08-28",
        lastUpdateDetails: "Security Update",
        untrustedField: "ignored",
      },
      outlook: {
        displayName: "Outlook 24",
        release: "2408",
        build: "17932.20910",
        fullVersion: "16.0.17932.20910",
        untrustedField: "ignored",
      },
      untrustedField: "ignored",
    },
  });

  const body = await fetch(`${baseUrl}/api/status`).then((response) =>
    response.json(),
  );
  assert.deepEqual(body["VM-INVENTORY"].inventory, {
    ramGb: 16,
    os: {
      productName: "Microsoft Windows 11 Enterprise",
      displayVersion: "24H2",
      build: "26100.4946",
      lastUpdateId: "KB5063878",
      lastUpdateDate: "2026-08-28",
      lastUpdateDetails: "Security Update",
    },
    outlook: {
      displayName: "Outlook 24",
      release: "2408",
      build: "17932.20910",
      fullVersion: "16.0.17932.20910",
    },
  });
});

test("ignores invalid inventory and retains the last valid report", async (t) => {
  const baseUrl = await withServer(t);
  await postStatus(baseUrl, {
    vm: "VM-INVENTORY",
    inventory: { ramGb: 8, outlook: { displayName: "Outlook 24" } },
  });
  await postStatus(baseUrl, {
    vm: "VM-INVENTORY",
    inventory: { ramGb: -1, outlook: [] },
  });

  const body = await fetch(`${baseUrl}/api/status`).then((response) =>
    response.json(),
  );
  assert.deepEqual(body["VM-INVENTORY"].inventory, {
    ramGb: 8,
    outlook: { displayName: "Outlook 24" },
  });
});
