import SwiftUI

/// Second tab: discover clients in an IP block using ping + TCP port probes.
struct ScanView: View {
    @EnvironmentObject private var scan: ScanController
    @EnvironmentObject private var monitor: PingController

    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            resultsTable
            Divider()
            footer
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Targets").font(.caption).foregroundStyle(.secondary)
                TextField("10.5.200.0/24  or  10.5.200.1-254  or  10.5.200.*",
                          text: $scan.targets)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { scan.start() }

                Menu {
                    ForEach(PortPreset.all) { preset in
                        Button("\(preset.name) (\(preset.ports.count))") { scan.applyPreset(preset) }
                    }
                } label: {
                    Label("Presets", systemImage: "list.bullet")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Text("Ports").font(.caption).foregroundStyle(.secondary)
                TextField("22,80,443", text: $scan.portsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .help("Comma-separated ports and ranges. Leave empty for a ping-only sweep.")
            }

            HStack(spacing: 14) {
                picker("Ping timeout", selection: $scan.pingTimeout, options: [0.3, 0.5, 1, 2, 3], suffix: "s")
                picker("Port timeout", selection: $scan.portTimeout, options: [0.2, 0.5, 1, 2], suffix: "s")
                picker("Concurrency", selection: Binding(
                    get: { Double(scan.concurrency) },
                    set: { scan.concurrency = Int($0) }
                ), options: [16, 32, 64, 128, 256], suffix: "")

                Toggle("Only discovered", isOn: $scan.showOnlyAlive)
                    .toggleStyle(.checkbox)

                Spacer()

                Button(scan.isScanning ? "Stop" : "Scan") { scan.toggle() }
                    .buttonStyle(.borderedProminent)
                    .tint(scan.isScanning ? .red : .green)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        .padding(10)
    }

    private func picker(_ title: String, selection: Binding<Double>, options: [Double], suffix: String) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { value in
                    if suffix.isEmpty {
                        Text("\(Int(value))").tag(value)
                    } else {
                        Text("\(value, specifier: "%g")\(suffix)").tag(value)
                    }
                }
            }
            .labelsHidden()
            .frame(width: 78)
        }
    }

    // MARK: - Results

    private var resultsTable: some View {
        Table(scan.displayedResults, selection: $selection) {
            TableColumn("") { result in
                Circle().fill(statusColor(result)).frame(width: 9, height: 9)
            }
            .width(22)

            TableColumn("IP") { result in
                Text(result.ip).font(.system(.body, design: .monospaced))
            }
            .width(min: 120, ideal: 140)

            TableColumn("Hostname") { result in
                Text(result.hostname ?? "—")
            }
            .width(min: 140, ideal: 200)

            TableColumn("Ping") { result in
                Text(result.pingMs.map { String(format: "%.1f ms", $0) } ?? "—")
            }
            .width(80)

            TableColumn("Open ports") { result in
                Text(result.openPorts.isEmpty ? "—" : result.openPorts.map(String.init).joined(separator: ", "))
                    .foregroundStyle(result.openPorts.isEmpty ? .secondary : .primary)
            }
            .width(min: 160, ideal: 260)

            TableColumn("#") { result in
                Text(result.openPorts.isEmpty ? "" : "\(result.openPorts.count)")
                    .foregroundStyle(.secondary)
            }
            .width(36)
        }
        .frame(minHeight: 220)
        .overlay {
            if scan.results.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("Enter an IP block above and press Scan to discover clients.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if scan.isScanning {
                ProgressView(value: Double(scan.completed), total: Double(max(1, scan.total)))
                    .frame(width: 220)
                    .progressViewStyle(.linear)
            }

            Text(scan.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("Add to Monitor") { addSelectionToMonitor() }
                .disabled(scan.aliveCount == 0)
                .help("Add the selected (or all discovered) hosts to the Ping Monitor tab")

            Button("Report…") { scan.exportReportHTML() }
                .disabled(scan.results.isEmpty)
                .help("Save a self-contained HTML report with subnet map and charts")

            Button("Export CSV") { scan.exportCSV() }
                .disabled(scan.results.isEmpty)

            Button("Clear") {
                selection.removeAll()
                scan.clear()
            }
            .disabled(scan.results.isEmpty || scan.isScanning)
        }
        .padding(10)
    }

    // MARK: - Helpers

    private func addSelectionToMonitor() {
        let chosen: [String]
        if selection.isEmpty {
            chosen = scan.results.filter(\.isAlive).map(\.ip)
        } else {
            chosen = scan.results.filter { selection.contains($0.id) && $0.isAlive }.map(\.ip)
        }
        guard !chosen.isEmpty else { return }
        monitor.addHosts(chosen.joined(separator: ","))
    }

    private func statusColor(_ result: ScanResult) -> Color {
        if result.isAlive { return .green }
        if !result.scanned { return .orange }
        return .secondary.opacity(0.4)
    }
}
