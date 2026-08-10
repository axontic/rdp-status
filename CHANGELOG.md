# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-05-15

### Added

- Added `.helmignore` to exclude non-chart files from Helm packages
- Added `.prettierignore` to prevent Prettier from corrupting Go template syntax (`{{ }}`) in `templates/`
- Added `templates/_helpers.tpl` with standard Helm helper templates (`fullname`, `name`, `chart`, `labels`, `selectorLabels`)
- Added `templates/NOTES.txt` with post-install instructions
- Added `IP_HOSTNAME_MAP` in `server.js` for static IP → hostname overrides (takes priority over DNS reverse lookup)
- Added IP and FQDN collection at startup in `win-client/client.ps1`

### Changed

- `server.js`: reverted emoji selection to inline `chooseEmoji` function; improved hostname resolution to prefer `fqdn` over `rdns`; removed unused `fs` import
- `win-client/client.ps1`: reverted C# namespace from `Axontic.Net` back to `Mbb.Net`
- `public/index.html`: translated all German CSS and JS comments to English; simplified emoji fallback to always use `chooseEmojiFallback`

### Removed

- `server.js`: removed external `emoji-map.json` loading in favour of hardcoded inline mapping

## [1.1.0] - 2025-03-04

### Changed

- Renamed C# namespace from `Mbb.Net` to `Axontic.Net` in PowerShell client
- Translated all German comments and output messages to English
- Externalized emoji mapping to `emoji-map.json` (gitignored) with example template
- Updated Helm chart description and version alignment

### Improved

- Added SECURITY.md for vulnerability reporting guidelines
- Added CODE_OF_CONDUCT.md (Contributor Covenant)
- Added GitHub issue and pull request templates

## [1.0.0] - 2025-02-19

### Added

- Initial open source release
- Real-time RDP session monitoring dashboard
- Node.js/Express API server
- PowerShell client for Windows VMs (WMI-based session detection)
- Web dashboard with table and card views
- Status indicators: BUSY, IDLE, FREE, OFFLINE
- Heartbeat mechanism for VM availability tracking
- Docker and Kubernetes deployment support
- Configurable server URL via environment variable

### Features

- Real-time status updates via polling
- Support for multiple concurrent VMs
- Disconnected session detection
- Console vs RDP session differentiation
