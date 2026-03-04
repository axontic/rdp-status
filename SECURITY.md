# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability in this project, please report it responsibly.

### How to Report

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Email your findings to: security@axontic.com
3. Include as much detail as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to Expect

- **Acknowledgment**: We will acknowledge receipt within 48 hours
- **Assessment**: We will assess the vulnerability and determine its severity
- **Updates**: We will keep you informed of our progress
- **Resolution**: We aim to resolve critical issues within 7 days
- **Credit**: We will credit you in the release notes (unless you prefer anonymity)

### Scope

This security policy applies to:

- The Node.js server (`server.js`)
- The PowerShell client (`win-client/client.ps1`)
- The web dashboard (`public/index.html`)
- Docker and Kubernetes deployment configurations

### Out of Scope

- Vulnerabilities in third-party dependencies (report these upstream)
- Issues in development/test environments
- Social engineering attacks

## Security Best Practices

When deploying this application:

1. **Network Security**: Run the server behind a reverse proxy with TLS
2. **Access Control**: Restrict API access to trusted networks/VMs
3. **Environment Variables**: Never commit secrets or credentials
4. **Updates**: Keep dependencies up to date with `npm audit`

Thank you for helping keep this project secure!
