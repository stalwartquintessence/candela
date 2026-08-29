# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

First release, replacing the earlier prototype.

### Added
- Menu bar controls per external display, taken from the monitor itself over DDC/CI:
  brightness, contrast, saturation, picture modes, color presets, and volume on monitors with
  speakers. Each control appears only when the monitor reports it.
- Brightness keeps working on connections that block DDC/CI by dimming the picture; the menu
  explains that 100% then equals the monitor's own brightness setting.
- Advanced option in Display Info to send DDC/CI to monitors that never reply.
- Brightness keys for the display under the pointer (Option+Shift for fine steps), with an
  on-screen indicator.
- Display Info window: EDID details (vendor, model, serial, manufacture date, size, native
  mode, refresh range), connection type, DDC/CI status, capabilities and current values,
  with Copy Report.
- `candelactl` command line tool: `list`, `info`, `edid`, `probe`, `caps`, `get`, `set`, with
  feature names such as `brightness`, `saturation` and `picture-mode`.
- Launch at Login, which opens System Settings when macOS asks for approval.
- DDC/CI probing across three framings, with clear advice when a connection blocks DDC/CI
  (for example the built-in HDMI port of Apple Silicon Macs).
- Settings remembered per monitor. After wake and display changes, software dimming is
  restored and the DDC/CI connection to the monitor is re-established.

### Fixed (compared with the prototype)
- Replies are validated by length, opcode and checksum, so a corrupted or echoed reply can
  no longer set a wrong brightness.
- Debug logging is no longer redacted as `<private>`.
- The brightness key permission no longer breaks after each rebuild:
  `scripts/create-signing-identity.sh` sets up a free, stable local signature.
- macOS is asked for the Accessibility permission only once, not at every launch.
