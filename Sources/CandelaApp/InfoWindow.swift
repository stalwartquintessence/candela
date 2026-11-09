import AppKit
import MonitorCore
import SwiftUI

final class InfoModel: ObservableObject {
    @Published var report: DisplayReport
    @Published var status: DDCStatus
    /// The advanced "send DDC/CI without replies" option is offered only where it can help.
    @Published var canSendWithoutReplies = false
    @Published var sendWithoutReplies = false

    init(report: DisplayReport, status: DDCStatus) {
        self.report = report
        self.status = status
    }

    var isChecking: Bool {
        if case .probing = status { return true }
        return false
    }
}

struct InfoView: View {
    @ObservedObject var model: InfoModel
    let onRecheck: () -> Void
    var onSendWithoutReplies: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    StatusBanner(status: model.status)
                }
                if model.canSendWithoutReplies || model.sendWithoutReplies {
                    Section("Advanced") {
                        Toggle(isOn: Binding(get: { model.sendWithoutReplies }, set: onSendWithoutReplies)) {
                            Text("Send commands without replies")
                            Text("Some monitors accept DDC/CI commands but never answer. Turn this on if the monitor's controls seem to do nothing.")
                        }
                    }
                }
                ForEach(model.report.sections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            LabeledContent(row.label) {
                                Text(row.value)
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button(model.isChecking ? "Checking..." : "Check DDC/CI Again", action: onRecheck)
                    .disabled(model.isChecking)
                Spacer()
                Button("Copy Report") {
                    var text = model.report.plainText
                    if let advice = model.status.advice { text += "\n\nNote: " + advice.text }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(12)
        }
        .frame(minWidth: 520, idealWidth: 540, minHeight: 460, idealHeight: 620)
    }
}

/// The display's DDC/CI state in a few words, with what to do about it.
private struct StatusBanner: View {
    let status: DDCStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .font(.title2)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.headline)
                    .font(.headline)
                if let detail = status.advice?.detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch status {
        case .working:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .probing:
            ProgressView().controlSize(.small)
        case .noReply, .noService:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
    }
}

/// One window per display, reused when reopened.
final class InfoWindowController: NSWindowController, NSWindowDelegate {
    let model: InfoModel
    private let controller: DisplayController

    init(controller: DisplayController) {
        self.controller = controller
        model = InfoModel(report: controller.report, status: controller.status)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
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
        model.status = controller.status
        model.canSendWithoutReplies = controller.plan.canSendWithoutReplies
        model.sendWithoutReplies = controller.sendWithoutReplies
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
