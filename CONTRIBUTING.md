# Contributing to WasiiBuds

Thanks for helping make the app more reliable. Please keep changes grounded in a real device reply or a reproducible UI problem.

## Before opening an issue

Search existing issues, then include:

- Earbud model and model ID, if known.
- Firmware versions from **Settings → Device details**.
- iPhone model and iOS version.
- Steps to reproduce, expected result, and actual result.
- A screenshot of **Connection → Recent activity** when a command fails. Remove Bluetooth identifiers and any other personal information before posting.

For a new model, please also provide the advertised GATT services and characteristics, capability reply, and a sanitized capture for each proposed control. A similar product name or service UUID is not enough to mark a device supported.

## Development checks

Run the portable domain tests:

```sh
scripts/test-domain.sh
```

Build the iPhone target with xtool:

```sh
xtool dev build
```

If you change a device command, add a test covering the packet and its reply. Check both success and refusal or timeout behavior on a physical device where possible. Describe what was verified on hardware in your pull request; a successful build alone is not device verification.

## Pull requests

- Keep each change focused and explain user-visible behavior.
- Preserve unknown fields and gesture slots when writing a device table.
- Gate controls by the connected device's advertised capabilities and read back changes before reporting success.
- Respect the existing white, black, and warm accent visual language, Dynamic Type, and Reduce Motion.
- Do not add telemetry, network requests, or background Bluetooth behavior without documenting the reason and privacy impact.
- Do not add third-party images, fonts, or code without a redistribution license and required notices. Review [Third-party notices](THIRD_PARTY_NOTICES.md).

Contributions are submitted under this repository's [MIT License](LICENSE). If your contribution includes code adapted from a differently licensed project, disclose it before submitting so the licensing can be reviewed.
