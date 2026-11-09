# Contributing

Thanks for helping. The most valuable contributions are hardware reports and focused fixes.

## Reporting a display that misbehaves

Open an issue using the bug report template and include the output of:

```sh
candelactl info
candelactl probe --verbose
```

Say whether `candelactl set brightness 20` visibly changes the display. Add what you learn to
[docs/HARDWARE-NOTES.md](docs/HARDWARE-NOTES.md).

## Development setup

- Apple Silicon Mac, macOS 13 or later
- Xcode 16, or only the Command Line Tools (`xcode-select --install`)

```sh
./scripts/test.sh          # run before every commit
./scripts/build-app.sh     # builds dist/Candela.app
open dist/Candela.app
```

You can also open `Package.swift` in Xcode.

## Guidelines

- Keep protocol logic in `MonitorCore` (no IOKit, no AppKit) and cover it with tests in
  `Tests/MonitorCoreTests`. Hardware access belongs in `MonitorIO`, UI in `CandelaApp`.
- Never treat a DDC reply as data unless it passes `DDCPacket.parseVCPReply`.
- Which controls each display offers is decided only in `ControlPlan` and pinned by
  `ControlPlanTests`. Adding a control means changing those tests on purpose.
- DDC/CI session logic (retries, probing, capabilities) lives in `DDCChannel` and is tested
  against `SimulatedMonitor`; extend the simulator rather than testing only on hardware.
- Tests must not use real device data such as serial numbers; build synthetic EDIDs with
  `EDIDBuilder` instead.
- Update `CHANGELOG.md` under "Unreleased" for user-visible changes.
- No new dependencies without discussion; the project builds with the Swift toolchain alone.

## Pull request checklist

- [ ] `./scripts/test.sh` passes
- [ ] `./scripts/build-app.sh` builds without warnings
- [ ] Tested on real hardware when touching `MonitorIO` (say which display and connection)
- [ ] CHANGELOG updated
