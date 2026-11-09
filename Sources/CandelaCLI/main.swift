// candelactl: command line access to the same engine the app uses.
// Useful for diagnostics (attach `candelactl probe -v` output to bug reports) and scripting.

import Foundation
import MonitorCore
import MonitorIO

let usage = """
candelactl \(AppVersion.string): inspect and control external displays over DDC/CI

USAGE
  candelactl <command> [options]

COMMANDS
  list                     List external displays
  info                     Full report: EDID, connection, DDC/CI status and features
  edid [--raw]             Print the EDID as a hex dump (or one hex line with --raw)
  probe                    Check whether the display answers DDC/CI, trying every framing
  caps                     Read and decode the DDC/CI capabilities string
  get <feature>            Read a VCP feature
  set <feature> <value>    Write a VCP feature (value in decimal, or hex with 0x)

  <feature> is a hex VCP code (10, 0x60) or a name: brightness, contrast,
  saturation, volume, picture-mode, preset, input, sharpness, mute, power,
  red, green, blue.

OPTIONS
  -d, --display <n>        Which external display (1 = first, see `list`). Default 1.
  -v, --verbose            Show every raw I2C transaction
  -h, --help               Show this help
      --version            Show the version

EXIT CODES
  0 success, 1 error, 2 usage error, 3 display did not answer DDC/CI
"""

// Keep in sync with the list in `usage`.
let featureNames: [String: UInt8] = [
    "brightness": MCCS.brightness, "contrast": MCCS.contrast, "saturation": MCCS.saturation,
    "volume": MCCS.volume, "picture-mode": MCCS.pictureMode, "preset": MCCS.colorPreset,
    "input": MCCS.inputSource, "sharpness": MCCS.sharpness, "mute": MCCS.mute, "power": MCCS.powerMode,
    "red": MCCS.redGain, "green": MCCS.greenGain, "blue": MCCS.blueGain,
]

struct Options {
    var command: String?
    var positional: [String] = []
    var display = 1
    var verbose = false
    var raw = false
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func parseOptions(_ args: [String]) -> Options {
    var o = Options()
    var i = 0
    while i < args.count {
        let a = args[i]
        switch a {
        case "-h", "--help", "help": print(usage); exit(0)
        case "--version": print(AppVersion.string); exit(0)
        case "-v", "--verbose": o.verbose = true
        case "--raw": o.raw = true
        case "-d", "--display":
            i += 1
            guard i < args.count, let n = Int(args[i]), n >= 1 else { fail("--display needs a number from `candelactl list`", code: 2) }
            o.display = n
        default:
            if a.hasPrefix("-"), Int(a) == nil { fail("Unknown option \(a). See --help.", code: 2) }
            if o.command == nil { o.command = a } else { o.positional.append(a) }
        }
        i += 1
    }
    return o
}

func feature(_ text: String) -> UInt8 {
    if let code = featureNames[text.lowercased()] ?? Hex.parseCode(text) { return code }
    fail("Unknown feature \"\(text)\". Use a hex VCP code like 10 or a name like brightness.", code: 2)
}

func value(_ text: String) -> UInt16 {
    let parsed = text.lowercased().hasPrefix("0x") ? UInt16(text.dropFirst(2), radix: 16) : UInt16(text)
    guard let v = parsed else { fail("Value must be a number from 0 to 65535 (or hex like 0x11).", code: 2) }
    return v
}

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
guard let command = options.command else { print(usage); exit(2) }

let displays = DisplayDiscovery.externalDisplays()

if command == "list" {
    if displays.isEmpty { print("No external displays found."); exit(0) }
    for (i, d) in displays.enumerated() {
        let transport = DisplayReport.transportDescription(up: d.avService?.transportUpstream, down: d.avService?.transportDownstream)
        let ddc = d.hasDDCService ? "I2C channel available" : "no I2C channel"
        print("\(i + 1). \(d.name)  [id \(d.displayID)\(d.isMain ? ", main" : "")]  \(transport), \(ddc)")
    }
    exit(0)
}

guard !displays.isEmpty else { fail("No external displays found.") }
guard options.display <= displays.count else { fail("There are only \(displays.count) external display(s). See `candelactl list`.", code: 2) }
let display = displays[options.display - 1]

if command == "edid" {
    guard let edid = display.edid else { fail("No EDID found for \(display.name).") }
    if options.raw {
        print(Hex.bytes(edid.bytes, separator: ""))
    } else {
        for start in stride(from: 0, to: edid.bytes.count, by: 16) {
            let line = Array(edid.bytes[start ..< min(start + 16, edid.bytes.count)])
            print(String(format: "%04X  ", start) + Hex.bytes(line))
        }
    }
    exit(0)
}

func makeChannel() -> DDCChannel {
    guard let service = display.avService?.service else {
        fail("\(display.name) has no DDC/CI channel (\(DDCStatus.noService.advice ?? "")).", code: 3)
    }
    let channel = DDCChannel(service: service)
    if options.verbose { channel.trace = { print("  i2c " + $0) } }
    return channel
}

func probeStatus(_ channel: DDCChannel) -> (DDCStatus, DDCChannel.ProbeResult) {
    let result = channel.probe()
    if let profile = result.working { return (.working(profile: profile.description), result) }
    let advice = DDCStatus.noReplyAdvice(transportUpstream: display.avService?.transportUpstream,
                                         transportDownstream: display.avService?.transportDownstream)
    return (.noReply(advice: advice), result)
}

switch command {
case "probe":
    let channel = makeChannel()
    print("Probing \(display.name)...")
    let (status, result) = probeStatus(channel)
    for attempt in result.attempts {
        print("  \(attempt.profile): \(attempt.reply.summary)")
    }
    print(status.summary)
    if let advice = status.advice { print(advice) }
    exit(status.isWorking ? 0 : 3)

case "info":
    var status = DDCStatus.noService
    var caps: Capabilities?
    var values: [UInt8: VCPValue] = [:]
    var profile: DDCProfile?
    if display.hasDDCService {
        let channel = makeChannel()
        let probed = probeStatus(channel)
        status = probed.0
        if status.isWorking {
            profile = channel.profile
            (caps, values) = channel.readCapabilitiesAndValues()
        }
    }
    // Same wording as Display Info. The CLI never uses the app's "send without replies" option.
    let plan = ControlPlan(hasChannel: display.hasDDCService, status: status, capabilities: caps,
                           knownFeatures: Set(values.keys))
    let input = display.reportInput(ddcStatus: status, controlMethod: plan.methodDescription,
                                    profile: profile, capabilities: caps, values: values)
    print(DisplayReport.build(input).plainText)
    if let advice = status.advice { print("\nNote: " + advice) }

case "caps":
    let channel = makeChannel()
    let (status, _) = probeStatus(channel)
    guard status.isWorking else { fail(status.summary + ". " + (status.advice ?? ""), code: 3) }
    guard let caps = channel.readCapabilities() else { fail("The display answered DDC/CI but returned no capabilities string.", code: 3) }
    print(caps.raw)
    print("")
    for code in caps.vcpCodes {
        let allowed = caps.vcp[code] ?? []
        let values = allowed.isEmpty ? "" : "  [" + allowed.map { MCCS.valueName(code: code, value: $0) }.joined(separator: ", ") + "]"
        print("  \(Hex.byte(code))  \(MCCS.name(of: code))\(values)")
    }

case "get":
    guard let name = options.positional.first else { fail("Usage: candelactl get <feature>", code: 2) }
    let code = feature(name)
    let channel = makeChannel()
    let (status, _) = probeStatus(channel)
    guard status.isWorking else { fail(status.summary + ". " + (status.advice ?? ""), code: 3) }
    let reply = channel.getVCP(code)
    switch reply {
    case .value(let v):
        let text = MCCS.kind(of: code) == .nonContinuous ? MCCS.valueName(code: code, value: v.current) : "\(v.current) of \(v.maximum)"
        print("\(MCCS.name(of: code)) (\(Hex.byte(code))): \(text)")
    default:
        fail("\(MCCS.name(of: code)): \(reply.summary)", code: 3)
    }

case "set":
    guard options.positional.count == 2 else { fail("Usage: candelactl set <feature> <value>", code: 2) }
    let code = feature(options.positional[0])
    let v = value(options.positional[1])
    let channel = makeChannel()
    guard channel.setVCP(code, value: v) else { fail("The I2C write failed.") }
    print("Sent \(MCCS.name(of: code)) (\(Hex.byte(code))) = \(v).")
    print("DDC/CI has no acknowledgement; check the display. `candelactl probe` tells you whether it answers at all.")

default:
    fail("Unknown command \"\(command)\". See --help.", code: 2)
}
