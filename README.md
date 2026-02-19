# RDP Status Dashboard

A real-time dashboard showing which Windows VMs are currently in use via RDP sessions.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Node](https://img.shields.io/badge/node-%3E%3D18-green.svg)

## Features

- **Real-time monitoring** - See which VMs are BUSY, IDLE, FREE, or OFFLINE at a glance
- **Session details** - Track active RDP connections, disconnected sessions, and console users
- **Beautiful UI** - Dark/Light theme support (Rose Pine themed)
- **Multiple views** - Switch between table and card layouts
- **Heartbeat system** - Automatic offline detection when VMs stop reporting
- **Event tracking** - See last activity (connect, disconnect, logon, logoff)
- **Kubernetes ready** - Includes Helm chart for easy deployment

## Status Indicators

| Status      | Meaning                                          |
| ----------- | ------------------------------------------------ |
| **BUSY**    | Active RDP or console session                    |
| **IDLE**    | Disconnected session(s) present, no active users |
| **FREE**    | No sessions at all                               |
| **OFFLINE** | VM hasn't reported in >2.5 minutes               |

## Architecture

```
┌─────────────────┐     HTTP POST      ┌─────────────────┐
│  Windows VM     │  ───────────────►  │  Node.js Server │
│  (client.ps1)   │   /api/status      │  (server.js)    │
└─────────────────┘                    └────────┬────────┘
                                                │
┌─────────────────┐     HTTP GET               │
│  Web Browser    │  ◄─────────────────────────┘
│  (Dashboard)    │   /api/status + UI
└─────────────────┘
```

## Quick Start

### Using Docker Compose (Recommended)

```bash
# Clone the repository
git clone https://github.com/axontic/rdp-status.git
cd rdp-status

# Start the server
docker-compose up -d

# Open http://localhost:3000
```

### Manual Installation

```bash
# Install dependencies
npm install

# Start the server
npm start

# Or with auto-reload for development
npm run dev
```

## Configuration

### Server Environment Variables

| Variable               | Default  | Description                       |
| ---------------------- | -------- | --------------------------------- |
| `PORT`                 | `3000`   | HTTP port                         |
| `HEARTBEAT_MS`         | `60000`  | Expected heartbeat interval (ms)  |
| `OFFLINE_MS`           | `150000` | Time until VM marked offline (ms) |
| `CONSOLE_BUSY`         | `false`  | Count console sessions as BUSY    |
| `USE_CLIENT_OCCUPANCY` | `true`   | Trust client's status calculation |

### Windows Client Configuration

Set the environment variable before running the client:

```powershell
# Set server URL (required)
$env:RDP_STATUS_SERVER_URL = "http://your-server:3000/api/status"

# Run the client
.\win-client\client.ps1
```

Or edit `client.ps1` directly to change the default fallback URL.

## API Reference

### POST /api/status

Report VM status from a client.

**Request Body:**

```json
{
  "vm": "VM-NAME",
  "ip": "192.168.1.100",
  "sessions": [
    {
      "user": "DOMAIN\\username",
      "sessionId": 2,
      "type": "rdp",
      "state": "active"
    }
  ],
  "occupancy": {
    "status": "in_use",
    "rdp_active_count": 1,
    "rdp_disconnected_count": 0,
    "console_active_count": 0
  },
  "event": "rdp_connect",
  "user": "DOMAIN\\username",
  "ts": "2025-02-19T10:30:00.000Z"
}
```

### GET /api/status

Retrieve status of all VMs.

**Response:**

```json
{
  "VM-NAME": {
    "vm": "VM-NAME",
    "hostname": "vm-name.local",
    "status": "BUSY",
    "effectiveStatus": "BUSY",
    "rdp_active_count": 1,
    "rdp_disconnected_count": 0,
    "console_active_count": 0,
    "lastSeen": 1708340000000,
    "sessions": [...],
    "lastEvent": {
      "event": "rdp_connect",
      "user": "DOMAIN\\username"
    }
  }
}
```

## Windows Client Setup

The PowerShell client monitors RDP sessions using Windows Terminal Services API (WTS).

### Requirements

- Windows 7+ / Server 2008 R2+
- PowerShell 5.1+
- Run as Administrator (for WMI event subscription)

### Installation as Scheduled Task

```powershell
# Create a scheduled task to run at startup
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-ExecutionPolicy Bypass -File C:\path\to\client.ps1"

$trigger = New-ScheduledTaskTrigger -AtStartup

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "RDP-Status-Client" `
  -Action $action -Trigger $trigger -Principal $principal
```

### Client Behavior

- Sends `vm_online` event on startup
- Sends `heartbeat` every 60 seconds
- Sends events on session changes (connect, disconnect, logon, logoff, lock, unlock)
- Falls back to polling if WMI events unavailable

## Kubernetes Deployment

```bash
# Install with Helm
helm install rdp-status ./

# Or with custom values
helm install rdp-status ./ -f values.local.yaml
```

See `values.yaml` for configuration options.

## Screenshots

_Screenshots coming soon_

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE) - Copyright (c) 2026 Axontic
