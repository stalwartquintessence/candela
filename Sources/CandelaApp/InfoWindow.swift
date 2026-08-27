import AppKit
import MonitorCore
import SwiftUI

final class InfoModel: ObservableObject {
    @Published var report: DisplayReport
    @Published var advice: String?
    @Published var isChecking = false
    /// The advanced "send DDC/CI without replies" option is offered only for a silent DDC channel.
    @Published var canSendWithoutReplies = false
    @Published var sendWithoutReplies = false

    init(report: DisplayReport, advice: String?) {
        self.report = report
        self.advice = advice
    }
}

struct InfoView: View {
    @ObservedObject var model: InfoModel
    let onRecheck: () -> Void
    var onSendWithoutReplies: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let advice = model.advice {
                        GroupBox {
                            Label(advice, systemImage: "info.circle")
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if model.canSendWithoutReplies || model.sendWithoutReplies {
                        GroupBox("Advanced") {
                            Toggle(isOn: Binding(get: { model.sendWithoutReplies }, set: { onSendWithoutReplies($0) })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Send DDC/CI commands even though the monitor does not answer")
                                    Text("For monitors that accept commands without replying. It has no effect when the connection itself blocks DDC/CI, as HDMI converters do.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                    }
                    ForEach(model.report.sections) { section in
                        GroupBox(section.title) {
                            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 6) {
                                ForEach(section.rows) { row in
                                    GridRow {
                                        Text(row.label)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 150, alignment: .leading)
                                        Text(row.value)
                                            .textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button(model.isChecking ? "Checking..." : "Check DDC/CI Again", action: onRecheck)
                    .disabled(model.isChecking)
                Spacer()
                Button("Copy Report") {
                    var text = model.report.plainText
                    if let advice = model.advice { text += "\n\nNote: " + advice }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(12)
        }
        .frame(minWidth: 540, idealWidth: 560, minHeight: 460, idealHeight: 620)
    }
}

/// One window per display, reused when reopened.
final class InfoWindowController: NSWindowController, NSWindowDelegate {
    let model: InfoModel
    private let controller: DisplayController

    init(controller: DisplayController) {
        self.controller = controller
        model = InfoModel(report: controller.report, advice: controller.status.advice)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "\(controller.name) Info"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: InfoView(
            model: model,
            onRecheck: { [weak self] in self?.recheck() },
            onSendWithoutReplies: { [weak self] on in
                guard let self else { return }
                self.controller.sendWithoutReplies = on
                self.refresh()
            }))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refresh() {
        model.report = controller.report
        model.advice = controller.status.advice
        model.canSendWithoutReplies = controller.plan.canSendWithoutReplies
        model.sendWithoutReplies = controller.sendWithoutReplies
        if case .probing = controller.status { model.isChecking = true } else { model.isChecking = false }
    }

    private func recheck() {
        controller.probe()
        refresh()
    }

    func present() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
