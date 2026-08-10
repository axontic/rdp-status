# Machine Information Design

## Goal

Allow administrators to document installed software, hardware, and other notes for each monitored machine. The dashboard exposes this information with the live status so separate documentation does not drift out of date.

## Configuration

Add an optional `machine-info.json` file in the application root. It maps the exact `vm` identifier reported by the Windows client to a plain-text description:

```json
{
  "VM-NAME": "Hardware: 16 GB RAM, RTX 4060\nSoftware: CAD 2026"
}
```

Keys use exact, case-sensitive matching because `vm` is already the stable identity key in server state. Values must be strings. Empty strings are treated as absent.

The server loads this file once during startup, following the existing `emoji-map.json` pattern. A missing file is valid. Invalid JSON or invalid entries produce a warning and leave those descriptions unavailable without preventing startup.

An example file, `machine-info.example.json`, documents the format. Deployment documentation explains how to mount or provide `machine-info.json`.

## Server And API

Client status reports and `POST /api/status` remain unchanged. Machine information is administrator-owned and must not be overwritten by reporting clients.

When serving `GET /api/status`, the server looks up each state's `vm` key and adds a `description` string when a non-empty configured value exists. Machines without configured information have no description field.

Configuration is not persisted or editable through the API. Changes take effect after a server restart, consistent with the current emoji configuration.

## Dashboard Interaction

Both table rows and cards with a description act as disclosure controls. Clicking one expands a detail area directly beneath its summary; clicking again collapses it. Entries without descriptions remain non-interactive and have no empty detail area.

Descriptions render as plain text. HTML-sensitive characters are escaped and newline characters are preserved. The browser never interprets description content as HTML or Markdown.

Table details appear as an additional row spanning all columns immediately after the machine row. Card details appear inside the selected card below the existing status content. Expanding one machine does not automatically collapse another.

Interactive entries expose their state with `aria-expanded`, are keyboard-focusable, and toggle with Enter or Space. Focus styling makes keyboard position visible. Controls use a concise visual affordance so expandable and static entries are distinguishable.

Polling must preserve expanded state by `vm` identifier while the machine remains in the response. This prevents the five-second refresh from closing details while they are being read.

## Error Handling

- A missing configuration file is silently accepted.
- Invalid JSON logs one startup warning and uses no machine information.
- Non-string values log a warning and are ignored individually.
- Empty and whitespace-only values are ignored.
- Description rendering always escapes untrusted text.

## Testing

Introduce automated server tests using Node's built-in test runner, avoiding a new test dependency. Refactor startup only as needed to let tests instantiate the Express application without opening a production listener.

Tests cover:

- Valid configuration adds the matching description to `GET /api/status`.
- Matching is exact and case-sensitive.
- Missing, empty, and invalid values do not add a description.
- Client payloads cannot supply or override configured descriptions.
- Existing status calculation and offline behavior remain unchanged.

Dashboard verification covers escaping, multiline rendering, mouse toggling, keyboard toggling, accessibility attributes, and expansion persistence across polling renders. Where full browser automation is unavailable, these checks are performed manually and documented with the verification results.

## Out Of Scope

- Automatic hardware or software inventory collection
- Editing descriptions in the dashboard
- Markdown or HTML formatting
- Live configuration reload
- Matching by hostname, FQDN, IP address, or patterns
