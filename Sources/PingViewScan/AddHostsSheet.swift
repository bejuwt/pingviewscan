import SwiftUI
import AppKit

/// Modal sheet for entering many hosts at once, one per line. Pastes from
/// spreadsheets (tabs/CRLF) are handled by `HostImport`.
struct AddHostsSheet: View {
    @ObservedObject var controller: PingController
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var onlyValid = true

    private var entries: [String] { HostImport.parse(text, filterInvalid: onlyValid) }
    private var totalFields: Int { HostImport.parse(text, filterInvalid: false).count }

    private var existingCount: Int {
        entries.filter { entry in
            controller.hosts.contains { $0.address.caseInsensitiveCompare(entry) == .orderedSame }
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add Hosts")
                    .font(.headline)
                Text("Enter one host name or IP address per line, or paste a column straight from Excel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor))
                    )
                    .frame(minWidth: 440, minHeight: 230)

                if text.isEmpty {
                    Text("10.5.200.1\n10.5.200.16\n10.5.200.30\nrouter.local")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Toggle("Only valid IP / hostnames", isOn: $onlyValid)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
                .disabled(!pasteboardHasText)

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(addTitle) {
                    controller.addHosts(entries)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 500)
    }

    private var pasteboardHasText: Bool {
        NSPasteboard.general.string(forType: .string)?.isEmpty == false
    }

    private func pasteFromClipboard() {
        guard let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty else { return }
        if text.isEmpty || text.hasSuffix("\n") {
            text += clip
        } else {
            text += "\n" + clip
        }
    }

    private var statusText: String {
        let count = entries.count
        guard count > 0 else { return "No hosts entered" }
        var parts = ["\(count) host\(count == 1 ? "" : "s") entered"]
        if existingCount > 0 {
            parts.append("\(existingCount) already added")
        }
        if onlyValid {
            let skipped = totalFields - count
            if skipped > 0 { parts.append("\(skipped) filtered out") }
        }
        return parts.joined(separator: " · ")
    }

    private var addTitle: String {
        entries.isEmpty ? "Add" : "Add \(entries.count) Host\(entries.count == 1 ? "" : "s")"
    }
}
