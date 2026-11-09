import AppKit
import MonitorCore
import SwiftUI

/// Display Info: everything Candela knows about one display, shown as a page in the Candela
/// window. Back (or Command-[ or Escape) returns to the main page.
struct InfoPage: View {
    @ObservedObject var controller: DisplayController
    let back: () -> Void

    private var isChecking: Bool {
        if case .probing = controller.status { return true }
        return false
    }

    var body: some View {
        let report = controller.report
        VStack(spacing: 0) {
            Form {
                Section {
                    StatusBanner(status: controller.status)
                }
                if controller.plan.canSendWithoutReplies || controller.sendWithoutReplies {
                    Section("Advanced") {
                        Toggle(isOn: Binding(get: { controller.sendWithoutReplies },
                                             set: { controller.sendWithoutReplies = $0 })) {
                            Text("Send commands without replies")
                            Text("Some monitors accept DDC/CI commands but never answer. Turn this on if the monitor's controls seem to do nothing.")
                        }
                    }
                }
                ForEach(report.sections) { section in
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
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut("[", modifiers: .command)
                Spacer()
                Button(isChecking ? "Checking..." : "Check DDC/CI Again") { controller.probe() }
                    .disabled(isChecking)
                Button("Copy Report") {
                    var text = report.plainText
                    if let advice = controller.status.advice { text += "\n\nNote: " + advice.text }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(12)
        }
        .onExitCommand(perform: back)
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
