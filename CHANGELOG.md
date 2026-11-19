# Changelog

All notable changes are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-11-18

### Added
- While the Candela window is open, Candela shows in the Dock and the Command-Tab switcher, with
  its menu in the menu bar (About Candela, Check for Updates, Hide, Quit). Closing the window
  takes it back to the background (#32).
- While a MacBook's lid is closed, Candela shows a sun in the menu bar. It opens a panel like
  the one under Sound, with each external display's controls, the same as in the window (#22,
  #27), since the brightness keys on the MacBook's keyboard are out of reach. **Show in Menu
  Bar** in the window chooses Always, While the Lid Is Closed (the default) or Never; removing
  the icon from the menu bar chooses Never (#15, #23).
- Shake the pointer to find it on a dark display: a display dimmed to 20% or lower comes back
  to 50%, with the brightness indicator. **Shake Pointer to Brighten** in the window turns it
  off; it is on by default and needs no permission (#16).

### Fixed
- A dimmed display no longer flashes at full brightness for a second or so when the lid closes
  or the displays change: dimming now returns as soon as macOS has reset the display.
- The brightness keys of an external Apple keyboard, and F14 and F15 on a full-size one, now
  change the display under the pointer instead of always the built-in display (#24).

### Changed
- The Candela window opens taller, so its rows fit without scrolling. A window resized before
  opens at the new size once.
- The monitor's own controls over DDC/CI are now verified on real hardware: brightness,
  contrast, Color Preset and Picture Mode on a Dell P2725DE over USB-C (#1).

### Upgrading from 0.2.0
- Choose **Check for Updates...** in the Candela window, or wait for the daily check if it is
  on. The update keeps your settings and the brightness key permission.

### Known limitations
- Saturation and volume over DDC/CI are not yet verified on a monitor that offers them. Reports
  with `candelactl info` output are welcome.
- Software dimming with HDR turned on is not yet checked (#6), and two identical monitors
  without a text serial may share settings (#7).
- Builds are not notarized: the first launch needs **Open Anyway**. Updates installed from
  inside Candela do not.

## [0.2.0] - 2026-11-09

### Added
- **Check for Updates...** in the Candela window finds a newer version, shows what changed, and
  installs it from inside the app: download, signature check, replace and relaunch, with the
  brightness key permission kept and no Open Anyway prompt. **Check for Updates Automatically**
  looks once a day; it is off by default. Updates use Sparkle 2.10.1 and are signed with an
  Ed25519 key. The README describes exactly what is sent.
- Homebrew: `brew install --cask stalwartquintessence/tap/candela`, from a tap that follows new
  releases on its own. See the README's Install section.

### Fixed
- Changing a display's color profile while Candela dims it no longer brings the old profile back
  at 100%: dimming continues on top of the new profile, and the slider and screen stay in step.
- Candela no longer resets the colors of every display at launch, after wake and when quitting,
  which could undo other apps' changes. It only touches displays it dims.

### Changed
- Releases are signed with a stable self-signed certificate instead of ad-hoc, so macOS keeps
  the brightness key (Accessibility) permission across updates.

### Upgrading from 0.1.0
- 0.1.0 cannot update itself, so install 0.2.0 by hand once: download it (or use Homebrew),
  replace Candela in Applications, click **Open Anyway** on first launch, and allow Candela again
  in **System Settings > Privacy & Security > Accessibility**. From 0.2.0 on, updates install
  from inside the app and keep the permission.

### Known limitations
- The monitor's own controls over DDC/CI (contrast, saturation, picture modes, color presets and
  volume) are still not verified on real hardware. Reports with `candelactl probe --verbose`
  output are very welcome (#1).
- Builds are not notarized: the first launch needs **Open Anyway**. Updates installed from
  inside Candela do not.

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
