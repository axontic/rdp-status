# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
