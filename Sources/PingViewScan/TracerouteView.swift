import SwiftUI

/// Fourth tab: a graphical traceroute tool.
struct TracerouteView: View {
    @EnvironmentObject private var trace: TracerouteController

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            pathSection
            Divider()
            hopTable
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Target").font(.caption).foregroundStyle(.secondary)
                TextField("host name or IP (e.g. 1.1.1.1)", text: $trace.target)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220, maxWidth: 340)
                    .onSubmit { trace.start() }

                picker("Max hops", selection: Binding(
                    get: { Double(trace.maxHops) },
                    set: { trace.maxHops = Int($0) }
                ), options: [16, 24, 30, 32, 48, 64], suffix: "")

                picker("Probes", selection: Binding(
                    get: { Double(trace.queries) },
                    set: { trace.queries = Int($0) }
                ), options: [1, 2, 3, 5], suffix: "")

                picker("Timeout", selection: $trace.timeout, options: [1, 2, 3, 5], suffix: "s")

                Spacer()

                Button(trace.isRunning ? "Stop" : "Trace") { trace.toggle() }
                    .buttonStyle(.borderedProminent)
                    .tint(trace.isRunning ? .red : .green)
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            HStack(spacing: 12) {
                if trace.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(trace.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    trace.exportReportHTML()
                } label: {
                    Label("Report…", systemImage: "map")
                }
                .disabled(trace.hops.isEmpty)
                .help("Save a self-contained HTML report with a hop-path diagram and charts")

                Button("CSV…") { trace.exportCSV() }
                    .disabled(trace.hops.isEmpty)

                Button("Clear") { trace.clear() }
                    .disabled(trace.hops.isEmpty || trace.isRunning)
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
            .frame(width: suffix.isEmpty ? 64 : 78)
        }
    }

    // MARK: - Path

    private var pathSection: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            if trace.hops.isEmpty {
                emptyPath
            } else {
                HStack(alignment: .top, spacing: 0) {
                    sourceNode

                    ForEach(Array(trace.hops.enumerated()), id: \.element.id) { index, hop in
                        connector(color: color(hop.latencyLevel),
                                  animated: trace.isRunning && index == trace.hops.count - 1)
                        hopNode(hop)
                    }

                    if let ip = trace.resolvedIP, trace.reachedTarget, trace.hops.last?.ip != ip {
                        connector(color: Color.secondary.opacity(0.4), animated: false)
                        targetNode(ip)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
        }
        .frame(height: 190)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var emptyPath: some View {
        VStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Enter a target and press Trace to map the route.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
    }

    private func connector(color: Color, animated: Bool) -> some View {
        ZStack {
            Capsule()
                .fill(color.opacity(0.85))
                .frame(width: 30, height: 4)
            if animated {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 30)
        .padding(.top, 18)
    }

    private var sourceNode: some View {
        deviceNode(title: "You", subtitle: "this Mac", detail: "source",
                   fill: .blue, textColor: .white)
    }

    private func targetNode(_ ip: String) -> some View {
        deviceNode(title: "Target", subtitle: ip, detail: "reached",
                   fill: .green, textColor: .white)
    }

    private func hopNode(_ hop: TracerouteHop) -> some View {
        deviceNode(title: "\(hop.ttl)",
                   subtitle: hop.displayHost,
                   detail: hop.minRtt.map { String(format: "%.1f ms", $0) } ?? "—",
                   fill: color(hop.latencyLevel),
                   textColor: hop.isTimeout ? .secondary : .white)
    }

    private func deviceNode(title: String, subtitle: String, detail: String,
                            fill: Color, textColor: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(fill).frame(width: 40, height: 40)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 2)
            }
            Text(subtitle)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 120)
            Text(detail)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 120)
    }

    // MARK: - Table

    private var hopTable: some View {
        Table(trace.hops) {
            TableColumn("#") { hop in
                Text("\(hop.ttl)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(36)

            TableColumn("Host") { hop in
                HStack(spacing: 7) {
                    Circle().fill(color(hop.latencyLevel)).frame(width: 9, height: 9)
                    Text(hop.displayHost)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 160, ideal: 260)

            TableColumn("IP") { hop in
                Text(hop.ip ?? "—").font(.system(.body, design: .monospaced))
            }
            .width(min: 110, ideal: 150)

            TableColumn("Sent / Recv / Lost") { hop in
                Text("\(hop.sent) / \(hop.received) / \(hop.timeouts)")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 120, ideal: 140)

            TableColumn("Loss %") { hop in
                Text(String(format: "%.1f%%", hop.lossPercent))
                    .foregroundStyle(hop.lossPercent > 0 ? .red : .primary)
            }
            .width(64)

            TableColumn("Last / Min / Max") { hop in
                Text("\(formatRTT(hop.lastRtt)) / \(formatRTT(hop.minRtt)) / \(formatRTT(hop.maxRtt))")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 150, ideal: 190)

            TableColumn("Avg") { Text(formatRTT($0.avgRtt)) }.width(70)
        }
    }

    // MARK: - Helpers

    private func color(_ level: LatencyLevel) -> Color {
        switch level {
        case .timedOut: return Color.secondary.opacity(0.45)
        case .fast:     return Color(red: 0.09, green: 0.64, blue: 0.29)
        case .moderate: return Color(red: 0.40, green: 0.64, blue: 0.05)
        case .slow:     return Color(red: 0.85, green: 0.47, blue: 0.02)
        case .verySlow: return Color(red: 0.86, green: 0.15, blue: 0.15)
        }
    }

    private func formatRTT(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }
}
