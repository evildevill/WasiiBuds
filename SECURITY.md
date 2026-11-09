# Security policy

WasiiBuds has no account or network backend. Its main trust boundary is the Bluetooth control connection, including packet parsing, device replies, and write confirmation.

## Reporting a vulnerability

Please use a [private GitHub security advisory](https://github.com/evildevill/WasiiBuds/security/advisories/new) if that option is available. Include the affected version or commit, reproduction steps, and the impact. Do not post an exploit or unredacted Bluetooth identifiers in a public issue.

## Supported versions

There is no public release series yet. Security fixes target the current `main` branch until releases are published.

## Diagnostic privacy

Recent activity can contain command bytes and device identifiers. Redact identifiers before sharing screenshots or logs. Hearing profile records stay on the iPhone; they are not sent to a service by this app.
