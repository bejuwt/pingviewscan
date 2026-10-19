import SwiftUI

/// Which hosts are drawn in the live graph.
enum HostFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case selected = "Selected"
    var id: String { rawValue }
}

struct MonitorView: View {
    @EnvironmentObject private var controller: PingController

    @State private var newHost = ""
    @State private var selection: Set<UUID> = []
    @State private var chartMode: ChartMode = .latency
    @State private var timeframe: ChartTimeframe = .all
    @State private var hostFilter: HostFilter = .all
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            hostTable
            Divider()
            chartSection
        }
        .frame(minWidth: 940, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAddSheet) {
            AddHostsSheet(controller: controller)
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            TextField("Host name or IP (comma separated)", text: $newHost)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220, maxWidth: 340)
                .onSubmit(addHosts)

            Button("Add", action: addHosts)
                .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                showingAddSheet = true
            } label: {
                Label("Bulk Add…", systemImage: "list.bullet.rectangle")
            }
            .help("Add many hosts at once, one per line")

            Divider().frame(height: 20)

            Button(controller.isRunning ? "Stop" : "Start") {
                controller.toggle()
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isRunning ? .red : .green)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Start or stop pinging (⌘↩)")

            labeledPicker("Interval", selection: $controller.interval, options: [0.5, 1, 2, 5, 10, 30])
            labeledPicker("Timeout", selection: $controller.timeout, options: [0.5, 1, 2, 3, 5])

            Spacer()

            Button {
                controller.exportReportHTML()
            } label: {
                Label("Report…", systemImage: "chart.xyaxis.line")
            }
            .help("Export an HTML report with latency and packet-loss graphs")

            Button("CSV…") { controller.exportCSV() }
                .help("Export raw session history as CSV")

            Menu {
                Button("Remove Selected") {
                    controller.removeHosts(ids: selection)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
                Button("Clear Statistics") { controller.clearStatistics() }
                Divider()
                Button("Remove All Hosts") {
                    controller.removeAllHosts()
                    selection.removeAll()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions")
        }
        .padding(10)
    }

    private func labeledPicker(_ title: String, selection: Binding<Double>, options: [Double]) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { value in
                    Text("\(value, specifier: "%g")s").tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 76)
        }
    }

    // MARK: - Table

    private var hostTable: some View {
        Table(controller.hosts, selection: $selection) {
            TableColumn("Host") { host in
                HStack(spacing: 7) {
                    Circle().fill(statusColor(host)).frame(width: 9, height: 9)
                    Text(host.address)
                }
            }
            .width(min: 170, ideal: 230)

            TableColumn("IP") { host in
                Text(host.ip ?? "—").font(.system(.body, design: .monospaced))
            }
            .width(min: 110, ideal: 150)

            TableColumn("Hostname") { host in
                Text(host.hostname ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 140, ideal: 200)

            TableColumn("Sent / Recv / Lost") { host in
                Text("\(host.stats.sent) / \(host.stats.received) / \(host.stats.lost)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 120, ideal: 140)

            TableColumn("Loss %") { host in
                Text(String(format: "%.1f%%", host.stats.lossPercent))
                    .foregroundStyle(host.stats.lossPercent > 0 ? .red : .primary)
            }
            .width(64)

            TableColumn("Last / Min / Max") { host in
                Text("\(formatRTT(host.stats.last)) / \(formatRTT(host.stats.minRtt)) / \(formatRTT(host.stats.maxRtt))")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 150, ideal: 180)

            TableColumn("Avg") { Text(formatRTT($0.stats.avgRtt)) }.width(70)
        }
        .frame(minHeight: 220)
        .overlay {
            if controller.hosts.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("Add a host name or IP address to begin.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Charts

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live session graph").font(.headline)
                Picker("", selection: $chartMode) {
                    ForEach(ChartMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                HStack(spacing: 6) {
                    Text("Range").font(.caption).foregroundStyle(.secondary)
                    Picker("Range", selection: $timeframe) {
                        ForEach(ChartTimeframe.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 96)
                    .help("Adjust the visible time range of the graph")
                }

                HStack(spacing: 6) {
                    Text("Hosts").font(.caption).foregroundStyle(.secondary)
                    Picker("Hosts", selection: $hostFilter) {
                        ForEach(HostFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                    .help("Show every host, or only the rows selected in the table")
                }

                Spacer()

                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Group {
                if hostFilter == .selected && chartHosts.isEmpty {
                    PlaceholderChart(message: "No hosts selected — select rows in the table to chart them.")
                } else {
                    switch chartMode {
                    case .latency:
                        LatencyChartView(hosts: chartHosts, history: controller.history, timeframe: timeframe)
                    case .loss:
                        LossChartView(hosts: chartHosts, history: controller.history, timeframe: timeframe)
                    }
                }
            }
            .frame(height: 210)
        }
        .padding(12)
    }

    /// Hosts to draw in the graph, honouring the "Selected" view filter.
    private var chartHosts: [Host] {
        guard hostFilter == .selected else { return controller.hosts }
        return controller.hosts.filter { selection.contains($0.id) }
    }

    // MARK: - Helpers

    private func addHosts() {
        let value = newHost
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        controller.addHosts(value)
        newHost = ""
    }

    private func statusColor(_ host: Host) -> Color {
        guard controller.isRunning else { return .secondary.opacity(0.45) }
        guard let last = host.stats.last else {
            return host.stats.sent > 0 ? .red : .secondary.opacity(0.45)
        }
        switch last {
        case ..<100: return .green
        case ..<300: return .yellow
        default: return .orange
        }
    }

    private func formatRTT(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }
}
