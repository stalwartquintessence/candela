# Hardware notes

Findings from real devices, kept so nobody has to repeat the investigation. Add your own setups
at the end, ideally with `candelactl probe --verbose` output.

## Background: how DDC/CI works on Apple Silicon

- Each external display has a `DCPAVServiceProxy` in the IOService plane with
  `Location = External`. `IOAVServiceCreateWithService` turns it into an I2C channel.
- In registry order, every framebuffer (`AppleCLCD2` or `IOMobileFramebufferShim`) is followed
  by its `DCPAVServiceProxy`. The framebuffer carries `EDID UUID`, `DisplayAttributes`
  (product name, IDs, serial) and `Transport` (`Upstream`, `Downstream`).
- The raw 256 byte EDID is published on `IOPortTransportState*` entries, which are not adjacent
  to the framebuffer, so Candela pairs them with displays by vendor, product and serial.
- DDC/CI lives at 7-bit I2C address `0x37`. The I2C call sends `0x51` (the host address) as its
  data address, so request buffers start at the length byte. Replies are read from offset 0 and
  start at the display's source byte `0x6E`; their checksum is seeded with `0x50`.

## MacBook Pro (M1 Pro), macOS 27.2, HP Z27 4K (2018) on the built-in HDMI port

`Transport = {Upstream = DP, Downstream = HDMI}`: the built-in HDMI port is a DisplayPort to
HDMI converter. DDC/CI was enabled in the monitor's menu.

| Test | Result |
| --- | --- |
| EDID read at I2C `0x50` | Correct (`00 FF FF FF FF FF FF 00 22 0E 38 35 ...`), so the bus works |
| Get VCP brightness, spec checksum (`82 01 10 AC`), read offset `0x51` | Null message `6E 80 BE` |
| Same with read offset `0x00`, 1 or 2 writes, 50 to 400 ms reply delay | Null message every time |
| MonitorControl framing (`82 01 10 FD`, 2 writes, offset `0x00`) | Null message |
| MonitorControl checksum with read offset `0x51` | `6E 85 C2 00 00 03 51 71 6E 10 AC 00 00 32 9A 51` |
| Contrast (`0x12`), input (`0x60`), color preset (`0x14`), volume (`0x62`), capabilities (`0xF3`) | Null message |
| Set VCP brightness, MonitorControl framing, alternating 15 and 85 every 1.5 s for 45 s | I2C reports success; the monitor did not change |

The one non-null reply is not a monitor response. Its opcode `C2` is invalid, its checksum is
wrong, and it contains fragments of packets written earlier (`10 AC` is the tail of a Get VCP
request, `00 32 9A` the tail of a Set VCP brightness 50), so it is a buffer echo. The unit test
`rejectsObservedHDMIBufferEcho` keeps the parser from ever accepting it.

**Conclusion:** this HDMI path does not pass DDC/CI in either direction. This matches BenQ's
statement that M1 Pro/Max MacBook Pros do not support DDC/CI over HDMI, and MonitorControl's
list of ports without DDC support. MonitorControl appeared to work on this setup because its
default "combined brightness" uses software dimming for the lower half of the slider.

Software dimming verified on the same setup: at 80% the display's gamma table reads back
`0.816` (`0.08 + 0.92 * 0.8`), and after killing the app with SIGTERM it reads `1.0` again,
confirming Quartz restores gamma when the process exits.

## Template for new reports

```
Mac / chip / macOS:
Monitor:
Connection (port, cable, adapter, dock):
DDC/CI enabled in monitor menu:
candelactl probe --verbose output:
Did `candelactl set brightness 20` visibly change the display?
```
