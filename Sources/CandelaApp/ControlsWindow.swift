import AppKit
import MonitorCore
import SwiftUI

/// App-wide state shown in the Candela window.
final class AppModel: ObservableObject {
    @Published var controllers: [DisplayController] = []
    @Published var brightnessKeysEnabled = false
    @Published var launchAtLogin = false
}

/// What the window asks the app to do.
struct ControlsActions {
    var showInfo: (DisplayController) -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var enableBrightnessKeys: () -> Void
    var redetect: () -> Void
    var about: () -> Void
}

/// Candela has no menu bar icon. This window is where its controls live; opening Candela again
/// (from Spotlight, Finder or Launchpad) brings it back.
struct ControlsView: View {
    @ObservedObject var model: AppModel
    let actions: ControlsActions

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if model.controllers.isEmpty {
                    Section {
                        Text("No external displays connected.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.controllers) { controller in
                    DisplaySection(controller: controller) { actions.showInfo(controller) }
                }
                Section {
                    Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: actions.setLaunchAtLogin))
                    LabeledContent("Brightness keys") {
                        if model.brightnessKeysEnabled {
                            Text("On for the display under the pointer")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Allow in System Settings...", action: actions.enableBrightnessKeys)
                        }
                    }
                } footer: {
                    Text("Closing this window keeps Candela running in the background. Open Candela again from Spotlight or Finder to come back here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Re-detect Displays", action: actions.redetect)
                Spacer()
                Button("About Candela", action: actions.about)
            }
            .padding(12)
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 380, idealHeight: 460)
    }
}

/// One display: its status, Brightness, and whatever else the monitor reports.
private struct DisplaySection: View {
    @ObservedObject var controller: DisplayController
    let showInfo: () -> Void

    var body: some View {
        let plan = controller.plan
        Section {
            LevelRow(title: "Brightness", symbol: "sun.max",
                     value: Binding(get: { controller.brightness }, set: { controller.setBrightness($0) }))
            ForEach(plan.sliders, id: \.self) { code in
                LevelRow(title: MCCS.name(of: code), symbol: Self.symbol(for: code),
                         value: Binding(get: { controller.percent(of: code) }, set: { controller.set(code: code, percent: $0) }))
            }
            // The monitor's own preset modes, exactly as it lists them.
            ForEach(plan.pickers, id: \.code) { picker in
                Picker(MCCS.name(of: picker.code), selection: selection(for: picker)) {
                    if selection(for: picker).wrappedValue == nil {
                        Text("Unknown").tag(UInt16?.none)
                    }
                    ForEach(picker.values, id: \.self) { value in
                        Text(MCCS.valueName(code: picker.code, value: value)).tag(UInt16?.some(value))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Display Info...", action: showInfo)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(plan.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .help(controller.status.advice?.text ?? "")
        }
    }

    private func selection(for picker: ControlPlan.Picker) -> Binding<UInt16?> {
        Binding(
            get: { picker.values.first { MCCS.isSameChoice(controller.currentValue(of: picker.code), $0) } },
            set: { value in
                if let value { controller.set(code: picker.code, value: value) }
            })
    }

    private static func symbol(for code: UInt8) -> String {
        switch code {
        case MCCS.contrast: return "circle.lefthalf.filled"
        case MCCS.saturation: return "drop.halffull"
        case MCCS.volume: return "speaker.wave.2"
        default: return "slider.horizontal.3"
        }
    }
}

/// Icon, title, a 0 to 100 slider and its value.
private struct LevelRow: View {
    let title: String
    let symbol: String
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: $value, in: 0 ... 100)
                    .labelsHidden()
                    .accessibilityLabel(title)
                Text("\(Int(value.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .frame(minWidth: 220)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

final class ControlsWindowController: NSWindowController {
    init(model: AppModel, actions: ControlsActions) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Candela"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ControlsView(model: model, actions: actions))
        window.center()
        window.setFrameAutosaveName("Candela")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
