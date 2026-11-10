# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Check for Updates...** in the Candela window asks GitHub for the latest release and offers
  to open its page when it is newer. **Check for Updates Automatically** does this at most once
  a day and announces each new version once; it is off by default. This is the only network
  request Candela makes, and the README describes exactly what it sends.

### Changed
- Releases are signed with a stable self-signed certificate instead of ad-hoc, so macOS keeps
  the brightness key (Accessibility) permission across updates. Updating from 0.1.0 asks for it
  once more.

## [0.1.0] - 2026-11-09

First release.

### Added
- Controls per external display, taken from the monitor itself over DDC/CI:
  brightness, contrast, saturation, picture modes, color presets, and volume on monitors with
  speakers. Each control appears only when the monitor reports it.
- Brightness keeps working on connections that block DDC/CI by dimming the picture; the
  window explains that 100% then equals the monitor's own brightness setting.
- Advanced option in Display Info to send DDC/CI to monitors that never reply.
- Brightness keys for the display under the pointer (Option+Shift for fine steps), with an
  indicator in the style of macOS 26 at the top right of that display.
- No menu bar or Dock icon: Candela runs in the background, and opening it shows its window.
  It starts quietly when launched at login.
- Display Info page: EDID details (vendor, model, serial, manufacture date, size, native
  mode, refresh range), connection type, DDC/CI status, capabilities and current values,
  with Copy Report.
- `candelactl` command line tool: `list`, `info`, `edid`, `probe`, `caps`, `get`, `set`, with
  feature names such as `brightness`, `saturation` and `picture-mode`.
- Launch at Login, which opens System Settings when macOS asks for approval.
- DDC/CI probing across three framings, with clear advice when a connection blocks DDC/CI
  (for example the built-in HDMI port of Apple Silicon Macs).
- Settings remembered per monitor. After wake and display changes, software dimming is
  restored and the DDC/CI connection to the monitor is re-established.
- Every DDC/CI reply is checked for length, opcode and checksum before it is used, so a
  corrupted or echoed reply can never set a wrong value.
- For builds from source, `scripts/create-signing-identity.sh` sets up a free, stable local
  signature, so the Accessibility permission survives rebuilds.

### Known limitations
- The monitor's own controls over DDC/CI (contrast, saturation, picture modes, color presets
  and volume) have not been verified on real hardware yet. Brightness by dimming, the
  brightness keys and Display Info have been. Reports with `candelactl probe --verbose` output
  are very welcome.
- Builds are not notarized. On first launch, open **System Settings > Privacy & Security**
  and click **Open Anyway**. After each update, macOS asks for the Accessibility permission
  again.
