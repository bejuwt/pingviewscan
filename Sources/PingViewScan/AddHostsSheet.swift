import SwiftUI

/// Modal sheet for entering many hosts at once, one per line.
struct AddHostsSheet: View {
    @ObservedObject var controller: PingController
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    private var entries: [String] {
        text.split(whereSeparator: { ",;\n\t ".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

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
                Text("Enter one host name or IP address per line.")
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
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(addTitle) {
                    controller.addHosts(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 500)
    }

    private var statusText: String {
        let count = entries.count
        guard count > 0 else { return "No hosts entered" }
        var parts = ["\(count) host\(count == 1 ? "" : "s") entered"]
        if existingCount > 0 {
            parts.append("\(existingCount) already added")
        }
        return parts.joined(separator: " · ")
    }

    private var addTitle: String {
        entries.isEmpty ? "Add" : "Add \(entries.count) Host\(entries.count == 1 ? "" : "s")"
    }
}
