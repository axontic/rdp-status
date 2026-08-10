# Machine Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add administrator-maintained plain-text machine descriptions that users can expand in both dashboard views.

**Architecture:** Load and validate an optional `machine-info.json` at server startup, then enrich only the GET response by exact `vm` key. Keep disclosure state in browser memory keyed by `vm`, and render escaped multiline text through the existing table and card renderers.

**Tech Stack:** Node.js 18+, CommonJS, Express 5, Node built-in test runner, vanilla HTML/CSS/JavaScript

## Global Constraints

- `machine-info.json` is optional and loaded once at startup.
- Machine keys match `vm` exactly and case-sensitively.
- Descriptions are non-empty plain-text strings; HTML and Markdown are never interpreted.
- `POST /api/status` remains backward compatible and cannot set descriptions.
- Do not add runtime or test dependencies.
- Expanded state survives polling while the matching machine remains present.

---

### Task 1: Configuration Loading And API Enrichment

**Files:**
- Create: `test/server.test.js`
- Modify: `server.js:22-34,127-222`
- Modify: `package.json:6-10`

**Interfaces:**
- Produces: `loadMachineInfo(filePath, logger) -> Record<string, string>`
- Produces: `createApp(options) -> Express.Application`, where `options.machineInfo` defaults to startup configuration and `options.offlineMs` defaults to `OFFLINE_MS`
- Produces: `startServer() -> http.Server`
- Produces: GET response property `description?: string`

- [ ] **Step 1: Add failing tests for configuration validation**

Create `test/server.test.js` with temporary-file tests that assert valid strings are returned, whitespace-only and non-string entries are omitted with warnings, a missing file returns `{}`, and malformed JSON returns `{}` with a warning. Import the planned API:

```js
const { loadMachineInfo } = require("../server");
```

Use `node:test`, `node:assert/strict`, `fs`, `os`, and `path`; create each temporary directory with `fs.mkdtempSync(path.join(os.tmpdir(), "rdp-status-"))` and remove it in `t.after()`.

- [ ] **Step 2: Run the focused tests and confirm failure**

Run: `node --test test/server.test.js`

Expected: FAIL because `loadMachineInfo` is not exported.

- [ ] **Step 3: Implement the minimal loader**

Add a loader near the emoji configuration:

```js
function loadMachineInfo(filePath, logger = console) {
  if (!fs.existsSync(filePath)) return {};
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
    const result = {};
    for (const [vm, description] of Object.entries(parsed)) {
      if (typeof description !== "string" || !description.trim()) {
        logger.warn(`Ignoring invalid machine information for ${vm}`);
        continue;
      }
      result[vm] = description;
    }
    return result;
  } catch (err) {
    logger.warn(`Failed to load machine-info.json: ${err.message}`);
    return {};
  }
}

const machineInfo = loadMachineInfo(path.join(__dirname, "machine-info.json"));
```

Export the function at the end of the module. Keep missing-file behavior silent.

- [ ] **Step 4: Run configuration tests and confirm they pass**

Run: `node --test test/server.test.js`

Expected: all loader tests PASS.

- [ ] **Step 5: Add failing HTTP tests for enrichment and isolation**

Extend `test/server.test.js` to start `createApp({ machineInfo, offlineMs })` on an ephemeral port in each test. POST status data using global `fetch`, then GET it and assert:

```js
assert.equal(body["VM-ONE"].description, "Hardware\nSoftware");
assert.equal(body["vm-one"].description, undefined);
```

Also POST a body containing `description: "client controlled"` and assert the configured value wins, then test an unconfigured VM has no own `description` property. Add an offline test with `offlineMs: 0` and retain one status assertion such as an active RDP session producing `BUSY`.

- [ ] **Step 6: Run HTTP tests and confirm failure**

Run: `node --test test/server.test.js`

Expected: FAIL because `createApp` is not exported and the GET response is not enriched.

- [ ] **Step 7: Refactor app creation without changing status behavior**

Move middleware and routes into:

```js
function createApp({ machineInfo: descriptions = machineInfo, offlineMs = OFFLINE_MS } = {}) {
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: "256kb" }));
  app.use(express.static(path.join(__dirname, "public")));
  // Register the existing POST, GET, and root routes here.
  // In GET, use offlineMs and append only configured descriptions:
  // ...(descriptions[vm] ? { description: descriptions[vm] } : {})
  return app;
}
```

Keep `state` private to each app instance by moving its declaration into `createApp`. Add:

```js
function startServer() {
  const app = createApp();
  const port = process.env.PORT || 3000;
  return app.listen(port, () => console.log(/* retain current startup message */));
}

if (require.main === module) startServer();
module.exports = { createApp, loadMachineInfo, startServer };
```

- [ ] **Step 8: Enable and run the automated test suite**

Change the package script to:

```json
"test": "node --test"
```

Run: `npm test`

Expected: all tests PASS and the process exits without leaving a listener open.

- [ ] **Step 9: Commit the server deliverable**

```bash
git add server.js package.json test/server.test.js
git commit -m "Add machine information API support"
```

---

### Task 2: Accessible Expandable Dashboard Details

**Files:**
- Modify: `public/index.html:198-203,258-291,440-550,623-936`
- Create: `test/dashboard.test.js`

**Interfaces:**
- Consumes: API property `description?: string` from Task 1
- Produces: `expandedMachines: Set<string>` and disclosure elements carrying `data-vm`, `role="button"`, `tabindex="0"`, and `aria-expanded`

- [ ] **Step 1: Add failing static UI contract tests**

Create `test/dashboard.test.js`, read `public/index.html`, and assert the source includes all required contracts:

```js
assert.match(html, /const expandedMachines = new Set\(\)/);
assert.match(html, /function escapeHtml\(s\)/);
assert.match(html, /aria-expanded=/);
assert.match(html, /data-vm=/);
assert.match(html, /white-space:\s*pre-wrap/);
assert.match(html, /event\.key === "Enter"/);
assert.match(html, /event\.key === " "/);
```

Also assert both table and card templates include a `machine-description` element. These source-contract tests supplement, but do not replace, the manual browser verification in Step 7.

- [ ] **Step 2: Run the UI tests and confirm failure**

Run: `node --test test/dashboard.test.js`

Expected: FAIL because disclosure support is absent.

- [ ] **Step 3: Add state and safe rendering helpers**

Add browser state and helpers:

```js
const expandedMachines = new Set();

function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function disclosureAttrs(info) {
  if (!info.description) return "";
  const expanded = expandedMachines.has(info.vm);
  return `class="machine-disclosure" role="button" tabindex="0" data-vm="${escapeAttr(info.vm)}" aria-expanded="${expanded}"`;
}
```

Use `escapeHtml` for every newly rendered description and for dynamic machine names/event text touched by the disclosure templates; do not interpolate description text unescaped.

- [ ] **Step 4: Render table and card details**

For described machines, apply `disclosureAttrs(info)` to the summary row/card and render only when expanded:

```js
const details = expandedMachines.has(info.vm)
  ? `<div class="machine-description">${escapeHtml(info.description)}</div>`
  : "";
```

In table mode, place `details` in a following `<tr class="machine-details"><td colspan="4">...</td></tr>`. In card mode, place it below counts and above the footer. Include a visible text chevron or `Details` affordance only for described entries.

- [ ] **Step 5: Add delegated mouse and keyboard interaction**

Add one delegated handler shared by `vmBody` and `gridEl`:

```js
function toggleMachine(target) {
  const disclosure = target.closest(".machine-disclosure");
  if (!disclosure) return;
  const vm = disclosure.dataset.vm;
  if (expandedMachines.has(vm)) expandedMachines.delete(vm);
  else expandedMachines.add(vm);
  load();
}

for (const container of [vmBody, gridEl]) {
  container.addEventListener("click", (event) => toggleMachine(event.target));
  container.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      toggleMachine(event.target);
    }
  });
}
```

After each successful fetch, remove keys absent from the response before rendering:

```js
const present = new Set(Object.values(json).map((info) => info.vm));
for (const vm of expandedMachines) {
  if (!present.has(vm)) expandedMachines.delete(vm);
}
```

- [ ] **Step 6: Add disclosure styling**

Add CSS for pointer cursor, a visible `:focus-visible` outline, table detail-row continuity, and multiline text:

```css
.machine-disclosure { cursor: pointer; }
.machine-disclosure:focus-visible { outline: 2px solid var(--text); outline-offset: 3px; }
.machine-description {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  color: var(--text);
  padding: 10px 12px;
  border-top: 1px solid var(--border);
}
.machine-details td { padding-top: 0; }
```

Ensure existing offline opacity and status borders continue to apply to summaries and details remain readable in both themes.

- [ ] **Step 7: Verify tests and behavior**

Run: `npm test`

Expected: all server and dashboard tests PASS.

Run: `npm start`, POST one described VM and one undescribed VM with `curl`, then verify in a browser at `http://localhost:3000`:

- Mouse and Enter/Space toggle details in table and card views.
- `aria-expanded` changes between `false` and `true`.
- Newlines remain visible and `<script>alert(1)</script>` appears literally without executing.
- Details remain expanded after at least one polling refresh.
- Undescribed entries have no pointer/disclosure behavior.
- Dark/light themes and narrow mobile width remain usable.

- [ ] **Step 8: Commit the dashboard deliverable**

```bash
git add public/index.html test/dashboard.test.js
git commit -m "Add expandable machine details"
```

---

### Task 3: Example Configuration And Deployment Documentation

**Files:**
- Create: `machine-info.example.json`
- Modify: `README.md:12-20,73-99,131-155`

**Interfaces:**
- Consumes: application-root file `/app/machine-info.json` and GET property `description` from Task 1

- [ ] **Step 1: Add the example configuration**

Create:

```json
{
  "VM-CAD-01": "Hardware: 16 GB RAM, NVIDIA RTX 4060\nSoftware: CAD 2026, rendering tools",
  "VM-OFFICE-01": "Hardware: 8 GB RAM\nSoftware: Microsoft 365"
}
```

- [ ] **Step 2: Document local and API usage**

Update `README.md` to list machine information as a feature, explain copying/mounting `machine-info.example.json` to `machine-info.json`, state exact case-sensitive `vm` matching and restart requirements, and add `description` to the GET response example.

Include this Docker Compose mount example:

```yaml
volumes:
  - ./machine-info.json:/app/machine-info.json:ro
```

- [ ] **Step 3: Verify configuration and documentation**

Run: `npm test`

Expected: all tests PASS.

- [ ] **Step 4: Commit documentation**

```bash
git add machine-info.example.json README.md
git commit -m "Document machine information configuration"
```

---

### Task 4: Final Regression Verification

**Files:**
- Verify only; modify files only if a verification failure identifies a defect

**Interfaces:**
- Consumes: all deliverables from Tasks 1-3

- [ ] **Step 1: Run all automated checks**

Run: `npm test && docker compose config && helm lint . && helm template rdp-status .`

Expected: every command exits 0.

- [ ] **Step 2: Check formatting and worktree scope**

Run: `git diff --check && git status --short`

Expected: no whitespace errors; status contains only intentional changes, or is clean after task commits.

- [ ] **Step 3: Review the complete feature diff**

Run: `git diff c654b43..HEAD -- server.js public/index.html test README.md machine-info.example.json package.json`

Expected: no client-side acceptance of descriptions, no unescaped description interpolation, and no unrelated changes.
