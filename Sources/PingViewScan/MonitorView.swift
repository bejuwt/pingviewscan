import SwiftUI

struct MonitorView: View {
    @EnvironmentObject private var controller: PingController

    @State private var newHost = ""
    @State private var selection: Set<UUID> = []
    @State private var chartMode: ChartMode = .latency
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

            TableColumn("Sent") { Text("\($0.stats.sent)") }.width(56)
            TableColumn("Recv") { Text("\($0.stats.received)") }.width(56)
            TableColumn("Lost") { Text("\($0.stats.lost)") }.width(56)

            TableColumn("Loss %") { host in
                Text(String(format: "%.1f%%", host.stats.lossPercent))
                    .foregroundStyle(host.stats.lossPercent > 0 ? .red : .primary)
            }
            .width(64)

            TableColumn("Last") { Text(formatRTT($0.stats.last)) }.width(70)
            TableColumn("Min") { Text(formatRTT($0.stats.minRtt)) }.width(70)
            TableColumn("Avg") { Text(formatRTT($0.stats.avgRtt)) }.width(70)
            TableColumn("Max") { Text(formatRTT($0.stats.maxRtt)) }.width(70)
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

                Spacer()

                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Group {
                switch chartMode {
                case .latency:
                    LatencyChartView(hosts: controller.hosts, recent: controller.recentSamples)
                case .loss:
                    LossChartView(hosts: controller.hosts, recent: controller.recentSamples)
                }
            }
            .frame(height: 210)
        }
        .padding(12)
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
