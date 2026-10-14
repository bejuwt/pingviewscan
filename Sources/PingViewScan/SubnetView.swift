import AppKit
import SwiftUI

/// Third tab: compute subnet details from an IPv4 address and prefix length.
struct SubnetView: View {
    @State private var input = "192.168.1.10/24"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            Divider()
            results
        }
    }

    // MARK: - Derived

    private var parsedAddress: String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let head = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
        return head.trimmingCharacters(in: .whitespaces)
    }

    private var parsedPrefix: Int? {
        let parts = input.trimmingCharacters(in: .whitespaces).split(separator: "/")
        guard parts.count == 2, let value = Int(parts[1]) else { return nil }
        return min(32, max(0, value))
    }

    private var effectivePrefix: Int { parsedPrefix ?? 24 }

    private var info: SubnetInfo? {
        guard !parsedAddress.isEmpty else { return nil }
        return SubnetCalculator.compute(address: parsedAddress, prefix: effectivePrefix)
    }

    private var prefixBinding: Binding<Int> {
        Binding(
            get: { effectivePrefix },
            set: { newValue in
                let address = parsedAddress.isEmpty ? "192.168.1.10" : parsedAddress
                input = "\(address)/\(newValue)"
            }
        )
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Address").font(.caption).foregroundStyle(.secondary)
                TextField("192.168.1.10  or  192.168.1.0/24", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .font(.system(.body, design: .monospaced))

                Text("Prefix").font(.caption).foregroundStyle(.secondary)
                TextField("", value: prefixBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .font(.system(.body, design: .monospaced))
                Stepper("", value: prefixBinding, in: 0...32)
                    .labelsHidden()

                Text("/\(effectivePrefix)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Enter an IPv4 address, optionally with a CIDR prefix (e.g. 10.5.200.10/22). Results update as you type.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if let info {
            ScrollView {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 10) {
                    row("Address", info.address, emphasis: true)
                    row("Network (CIDR)", info.cidr, emphasis: true)
                    row("Subnet mask", info.mask)
                    row("Wildcard mask", info.wildcard)
                    row("Network address", info.network)
                    row("Broadcast address", info.broadcast)

                    if let first = info.firstUsable, let last = info.lastUsable {
                        row("Usable range", "\(first) – \(last)")
                    } else {
                        row("Usable range", "—")
                    }

                    row("Usable hosts", "\(info.usableHosts)")
                    row("Total addresses", "\(info.totalAddresses)")
                    row("IP class", info.ipClass)
                    row("Scope", info.scope)
                    row("Address (binary)", info.addressBinary, emphasis: false, monospaced: true)
                    row("Mask (binary)", info.maskBinary, emphasis: false, monospaced: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    copy(info)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .padding(12)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "number.square")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                Text("Enter a valid IPv4 address to calculate its subnet.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ label: String, _ value: String,
                     emphasis: Bool = false, monospaced: Bool = true) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .fontWeight(emphasis ? .semibold : .regular)
                .textSelection(.enabled)
        }
    }

    private func copy(_ info: SubnetInfo) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(info.summary, forType: .string)
    }
}
