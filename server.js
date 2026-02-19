"use strict";

const express = require("express");
const cors = require("cors");
const path = require("path");
const dns = require("dns").promises;

const app = express();
app.use(cors());
app.use(express.json({ limit: "256kb" }));
app.use(express.static(path.join(__dirname, "public")));

const HEARTBEAT_MS = Number(process.env.HEARTBEAT_MS) || 60_000;
const OFFLINE_MS = Number(process.env.OFFLINE_MS) || 150_000;
const CONSOLE_COUNTS_AS_BUSY = (process.env.CONSOLE_BUSY || "false").toLowerCase() === "true";
const USE_CLIENT_OCCUPANCY = (process.env.USE_CLIENT_OCCUPANCY || "true").toLowerCase() === "true";

const state = Object.create(null);

const toLower = v => (v ?? "").toString().toLowerCase().trim();

function normalizeSession(session) {
  const typeStr = toLower(session?.type || session?.session || "");
  const stateStrRaw = toLower(session?.state || "");
  let type = "other";
  if (typeStr.includes("console")) type = "console";
  else if (typeStr.includes("rdp")) type = "rdp";

  let stateStr = stateStrRaw;
  if (stateStrRaw.startsWith("act") || stateStrRaw.startsWith("aktiv")) stateStr = "active";
  else if (stateStrRaw.startsWith("conn") || stateStrRaw.startsWith("verb")) stateStr = "connected";
  else if (stateStrRaw.startsWith("disc") || stateStrRaw.startsWith("getrennt")) stateStr = "disconnected";

  const sessionId = Number.isInteger(session?.sessionId)
    ? session.sessionId
    : (Number.isFinite(+session?.sessionId) ? +session.sessionId : null);

  return { user: session?.user ?? "", sessionId, type, state: stateStr };
}

function deriveCountsAndStatus(sessions = []) {
  const norm = Array.isArray(sessions) ? sessions.map(normalizeSession) : [];
  let rdp_active = 0, rdp_disc = 0, console_active = 0;
  for (const s of norm) {
    if (s.type === "rdp" && s.state === "active") rdp_active++;
    if (s.type === "rdp" && s.state === "disconnected") rdp_disc++;
    if (s.type === "console" && s.state === "active") console_active++;
  }
  const busyByRdp = rdp_active > 0;
  const busyByConsole = CONSOLE_COUNTS_AS_BUSY && console_active > 0;

  let status = "FREE";
  if (busyByRdp || busyByConsole) status = "BUSY";
  else if (rdp_disc > 0) status = "IDLE";

  return {
    normSessions: norm,
    counts: {
      rdp_active_count: rdp_active,
      rdp_disconnected_count: rdp_disc,
      console_active_count: console_active
    },
    status
  };
}

function statusFromClientOccupancy(occ) {
  if (!USE_CLIENT_OCCUPANCY || !occ?.status) return null;
  const s = toLower(occ.status);
  if (s === "in_use") return "BUSY";
  if (s === "idle_with_disconnected") return "IDLE";
  if (s === "free") return "FREE";
  return null;
}

function chooseEmoji(host) {
  const h = toLower(host);
  if (h.includes("banane") || h.includes("banana")) return "🍌";
  if (h.includes("local-vm-bier")) return "🍺";
  if (h.includes("kirsche") || h.includes("cherry")) return "🍒";
  if (h.includes("traube") || h.includes("grape")) return "🍇";
  if (h.includes("zitrone") || h.includes("lemon")) return "🍋";
  if (h.includes("melone") || h.includes("watermelon")) return "🍉";
  if (h.includes("kiwi")) return "🥝";
  if (h.includes("ananas") || h.includes("pineapple")) return "🍍";
  if (h.includes("erdbeere") || h.includes("strawberry")) return "🍓";
  if (h.includes("pfirsich") || h.includes("peach")) return "🍑";
  if (h.includes("kaktus") || h.includes("cactus")) return "🌵";
  if (h.includes("karotte") || h.includes("carrot")) return "🥕";
  if (h.includes("apfel") || h.includes("apple")) return "🍎";
  if (h.includes("birne") || h.includes("pear")) return "🍐";
  if (h.includes("dev")) return "👨‍💻";
  return "💻";
}

app.post("/api/status", async (req, res) => {
  const { vm, ip, rdns, fqdn, sessions, occupancy, event, user, sessionId, ts } = req.body || {};
  if (!vm) return res.status(400).json({ error: "Missing field: vm" });

  const { normSessions, counts, status: statusFromSess } = deriveCountsAndStatus(sessions);
  const occStatus = statusFromClientOccupancy(occupancy);
  const status = (statusFromSess === "BUSY") ? "BUSY" : (occStatus ?? statusFromSess);

  let resolvedRdns = rdns || null;
  let hostname = rdns || fqdn || vm;

  if (!resolvedRdns && ip) {
    try {
      const names = await dns.reverse(ip);
      if (names?.length) {
        resolvedRdns = names[0];
        if (!fqdn) hostname = resolvedRdns;
      }
    } catch { /* ignore DNS errors */ }
  }

  const emoji = chooseEmoji(hostname);

  state[vm] = {
    vm,
    ip: ip || null,
    rdns: resolvedRdns,
    fqdn: fqdn || null,
    hostname,
    emoji,
    sessions: normSessions,
    occupancy: occupancy || null,
    status,
    lastSeen: Date.now(),
    lastEvent: {
      event: event || "-",
      user: user || "",
      sessionId: Number.isInteger(sessionId) ? sessionId : null,
      ts: ts || Date.now()
    },
    ...counts
  };

  const t = new Date().toLocaleTimeString();
  const sessLog = normSessions.map(s => `${s.type}#${s.sessionId ?? "-"} ${s.user || "-"} [${s.state}]`).join(" | ");
  console.log(`[${t}] ${vm} (${hostname}${ip ? " - " + ip : ""}) -> ${state[vm].lastEvent.event} | status=${status} | rdpAct=${counts.rdp_active_count} rdpDisc=${counts.rdp_disconnected_count} consAct=${counts.console_active_count}`);
  if (normSessions.length) console.log(`   sessions: ${sessLog}`);

  res.sendStatus(200);
});

app.get("/api/status", (_req, res) => {
  const now = Date.now();
  const result = {};
  for (const [vm, info] of Object.entries(state)) {
    const offline = (now - info.lastSeen) > OFFLINE_MS;
    result[vm] = {
      ...info,
      effectiveStatus: offline ? "OFFLINE" : info.status
    };
  }
  res.json(result);
});

app.get("/", (_req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

const port = process.env.PORT || 3000;
app.listen(port, () =>
  console.log(`RDP Status Server running on :${port} (HB=${HEARTBEAT_MS}ms, OFF=${OFFLINE_MS}ms, CONSOLE_BUSY=${CONSOLE_COUNTS_AS_BUSY}, USE_CLIENT_OCCUPANCY=${USE_CLIENT_OCCUPANCY})`)
);
