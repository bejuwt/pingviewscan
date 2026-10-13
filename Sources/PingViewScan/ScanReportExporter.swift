import Foundation

/// Snapshot of a completed (or in-progress) network scan, used to build reports.
struct ScanReport {
    let generated: Date
    let targets: String
    let started: Date?
    let finished: Date?
    let ports: [UInt16]
    let results: [ScanResult]
    let pingTimeout: Double
    let portTimeout: Double
    let concurrency: Int

    var total: Int { results.count }
    var alive: [ScanResult] { results.filter(\.isAlive) }
    var aliveCount: Int { alive.count }
    var alivePercent: Double { total > 0 ? Double(aliveCount) / Double(total) * 100 : 0 }
    var duration: TimeInterval { (finished ?? Date()).timeIntervalSince(started ?? generated) }
}

/// Builds a self-contained HTML report (with inline SVG visualisations) for an
/// IP-block scan: subnet occupancy map, latency bars, port popularity and a
/// full results table.
enum ScanReportExporter {

    private struct GridCell {
        let ip: String
        let alive: Bool
        let portCount: Int
        let scanned: Bool
    }

    static func html(_ report: ScanReport) -> String {
        let cells = report.results.map {
            GridCell(ip: $0.ip, alive: $0.isAlive, portCount: $0.openPorts.count, scanned: $0.scanned)
        }

        let grid = subnetGrid(cells)
        let latencyChart = latencyBars(report.alive)
        let portChart = portBars(report.alive, scannedPorts: report.ports)

        let resultsRows = report.results.map { result -> String in
            let ping = result.pingMs.map { String(format: "%.1f", $0) } ?? "—"
            let ports = result.openPorts.isEmpty
                ? "—"
                : result.openPorts.map(String.init).joined(separator: ", ")
            let status = result.isAlive
                ? "<span class=\"good\">up</span>"
                : "<span class=\"muted\">no response</span>"
            return """
            <tr>
              <td class="mono">\(SVG.escape(result.ip))</td>
              <td>\(SVG.escape(result.hostname ?? "—"))</td>
              <td>\(status)</td>
              <td class="mono">\(ping)</td>
              <td class="mono">\(SVG.escape(ports))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let openPortCount = report.alive.reduce(0) { $0 + $1.openPorts.count }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>PingViewScan Report</title>
        <style>
          :root { color-scheme: light; }
          * { box-sizing: border-box; }
          body { margin: 0; padding: 32px; background: #f8fafc; color: #111827;
                 font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
          .wrap { max-width: 1120px; margin: 0 auto; }
          h1 { font-size: 26px; margin: 0 0 4px; }
          .sub { color: #6b7280; font-size: 13px; margin-bottom: 24px; }
          .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 24px; }
          .card { background: #fff; border: 1px solid #e5e7eb; border-radius: 12px; padding: 14px 16px; }
          .card .label { font-size: 12px; color: #6b7280; text-transform: uppercase; letter-spacing: .04em; }
          .card .value { font-size: 22px; font-weight: 600; margin-top: 4px; }
          .card .value.good { color: #16a34a; }
          .panel { background: #fff; border: 1px solid #e5e7eb; border-radius: 12px; padding: 18px; margin-bottom: 24px; }
          .panel h2 { font-size: 15px; margin: 0 0 12px; }
          .chart { width: 100%; }
          table { width: 100%; border-collapse: collapse; font-size: 13px; }
          th, td { padding: 8px 10px; text-align: right; border-bottom: 1px solid #f1f3f5; white-space: nowrap; }
          th:first-child, td:first-child, th:nth-child(2), td:nth-child(2) { text-align: left; }
          th { font-size: 11px; text-transform: uppercase; letter-spacing: .04em; color: #6b7280; background: #f9fafb; }
          tbody tr:hover { background: #f9fafb; }
          .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
          .good { color: #16a34a; font-weight: 600; }
          .muted { color: #9ca3af; }
          .legend { display: flex; flex-wrap: wrap; gap: 16px; margin-top: 14px; font-size: 12px; color: #6b7280; }
          .legend span { display: inline-flex; align-items: center; gap: 6px; }
          .dot { width: 12px; height: 12px; border-radius: 3px; display: inline-block; }
          footer { color: #9ca3af; font-size: 12px; text-align: center; margin-top: 8px; }
        </style>
        </head>
        <body>
        <div class="wrap">
          <h1>PingViewScan Report</h1>
          <div class="sub">Targets \(SVG.escape(report.targets.isEmpty ? "—" : report.targets)) · Generated \(ReportExporter.dateTime(report.generated)) · Ping timeout \(String(format: "%g", report.pingTimeout))s · Port timeout \(String(format: "%g", report.portTimeout))s</div>

          <div class="cards">
            <div class="card"><div class="label">Addresses</div><div class="value">\(report.total)</div></div>
            <div class="card"><div class="label">Discovered</div><div class="value good">\(report.aliveCount)</div></div>
            <div class="card"><div class="label">Alive</div><div class="value">\(String(format: "%.0f", report.alivePercent))%</div></div>
            <div class="card"><div class="label">Ports scanned</div><div class="value">\(report.ports.count)</div></div>
            <div class="card"><div class="label">Open ports</div><div class="value">\(openPortCount)</div></div>
            <div class="card"><div class="label">Duration</div><div class="value" style="font-size:15px">\(ReportExporter.durationString(report.duration))</div></div>
            <div class="card"><div class="label">Concurrency</div><div class="value">\(report.concurrency)</div></div>
            <div class="card"><div class="label">Scan start</div><div class="value" style="font-size:15px">\(report.started.map(ReportExporter.dateTime) ?? "—")</div></div>
          </div>

          <div class="panel chart">\(grid)</div>
          <div class="panel chart">\(latencyChart)</div>
          <div class="panel chart">\(portChart)</div>

          <div class="panel">
            <h2>Results (\(report.total) address\(report.total == 1 ? "" : "es"))</h2>
            <table>
              <thead>
                <tr><th>IP address</th><th>Hostname</th><th>Status</th><th>Ping (ms)</th><th>Open ports</th></tr>
              </thead>
              <tbody>
        \(resultsRows)
              </tbody>
            </table>
          </div>

          <footer>PingViewScan for macOS · A host counts as discovered if it answered ICMP or exposed a TCP port.</footer>
        </div>
        </body>
        </html>
        """
    }

    // MARK: - Visualisations

    private static func subnetGrid(_ cells: [GridCell]) -> String {
        guard !cells.isEmpty else {
            return "<svg viewBox=\"0 0 1020 80\"><text x=\"24\" y=\"40\" font-size=\"14\" fill=\"#6b7280\">No addresses scanned.</text></svg>"
        }

        let columns: Int
        if cells.count <= 16 { columns = cells.count }
        else if cells.count <= 256 { columns = 16 }
        else { columns = 32 }

        let cellSize = 26.0
        let gap = 5.0
        let margin = 24.0
        let titleHeight = 34.0
        let rows = Int(ceil(Double(cells.count) / Double(columns)))
        let width = margin * 2 + Double(columns) * (cellSize + gap) - gap
        let height = titleHeight + margin + Double(rows) * (cellSize + gap) - gap + 44

        var svg = "<svg viewBox=\"0 0 \(fmt(width)) \(fmt(height))\" width=\"100%\" preserveAspectRatio=\"xMidYMid meet\" role=\"img\" font-family=\"-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif\">"
        svg += "<rect x=\"0\" y=\"0\" width=\"\(fmt(width))\" height=\"\(fmt(height))\" fill=\"#ffffff\"/>"
        svg += "<text x=\"\(fmt(margin))\" y=\"24\" font-size=\"16\" font-weight=\"600\" fill=\"#111827\">Subnet occupancy</text>"
        svg += "<text x=\"\(fmt(width - margin))\" y=\"24\" font-size=\"12\" fill=\"#6b7280\" text-anchor=\"end\">\(cells.count) address\(cells.count == 1 ? "" : "es")</text>"

        for (index, cell) in cells.enumerated() {
            let row = index / columns
            let column = index % columns
            let x = margin + Double(column) * (cellSize + gap)
            let y = titleHeight + margin + Double(row) * (cellSize + gap)
            let fill = cellFill(cell)
            let tooltip = cell.alive
                ? "\(cell.ip) — \(cell.portCount) open port\(cell.portCount == 1 ? "" : "s")"
                : (cell.scanned ? "\(cell.ip) — no response" : "\(cell.ip) — not scanned")
            svg += "<rect x=\"\(fmt(x))\" y=\"\(fmt(y))\" width=\"\(fmt(cellSize))\" height=\"\(fmt(cellSize))\" rx=\"6\" fill=\"\(fill)\">"
            svg += "<title>\(SVG.escape(tooltip))</title></rect>"
        }

        let legendY = titleHeight + margin + Double(rows) * (cellSize + gap) + 8
        let legend: [(String, String)] = [
            ("#86efac", "up (ICMP only)"),
            ("#22c55e", "up (1–2 ports)"),
            ("#15803d", "up (3+ ports)"),
            ("#e2e8f0", "no response"),
            ("#f1f5f9", "not scanned")
        ]
        var legendX = margin
        svg += "<g font-size=\"11\" fill=\"#6b7280\">"
        for (color, label) in legend {
            svg += "<rect x=\"\(fmt(legendX))\" y=\"\(fmt(legendY - 9))\" width=\"12\" height=\"12\" rx=\"3\" fill=\"\(color)\"/>"
            svg += "<text x=\"\(fmt(legendX + 17))\" y=\"\(fmt(legendY))\">\(SVG.escape(label))</text>"
            legendX += 24 + Double(label.count) * 7
        }
        svg += "</g></svg>"
        return svg
    }

    private static func cellFill(_ cell: GridCell) -> String {
        guard cell.alive else { return cell.scanned ? "#e2e8f0" : "#f1f5f9" }
        if cell.portCount == 0 { return "#86efac" }
        if cell.portCount <= 2 { return "#22c55e" }
        return "#15803d"
    }

    private static func latencyBars(_ alive: [ScanResult]) -> String {
        let responding = alive
            .compactMap { result in result.pingMs.map { (ip: result.ip, ms: $0) } }
            .sorted { ipToInt($0.ip) < ipToInt($1.ip) }
        guard !responding.isEmpty else {
            return SVG.barChart(width: 1020, height: 260, title: "Latency by host",
                                bars: [], yLabel: "Latency (ms)")
        }
        let shown = Array(responding.prefix(80))
        let bars = shown.map { (label: $0.ip, value: $0.ms, color: "#2563eb") }
        let title = responding.count > shown.count
            ? "Latency by host (first \(shown.count) of \(responding.count))"
            : "Latency by host"
        return SVG.barChart(width: 1020, height: 320, title: title,
                            bars: bars, yLabel: "Latency (ms)",
                            rotateLabels: shown.count > 10, valueSuffix: "")
    }

    private static func portBars(_ alive: [ScanResult], scannedPorts: [UInt16]) -> String {
        var counts: [UInt16: Int] = [:]
        for result in alive {
            for port in result.openPorts { counts[port, default: 0] += 1 }
        }
        guard !counts.isEmpty else {
            let note = scannedPorts.isEmpty ? "No ports were scanned." : "No open ports were found."
            return SVG.barChart(width: 1020, height: 240,
                                title: "Open ports by host count (\(note))",
                                bars: [], yLabel: "Hosts")
        }
        let bars = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(24)
            .map { (label: serviceLabel($0.key), value: Double($0.value), color: "#7c3aed") }
        return SVG.barChart(width: 1020, height: 320, title: "Most common open ports",
                            bars: Array(bars), yLabel: "Hosts", rotateLabels: true,
                            integerValues: true)
    }

    private static func serviceLabel(_ port: UInt16) -> String {
        let names: [UInt16: String] = [
            21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS", 80: "HTTP",
            110: "POP3", 123: "NTP", 135: "RPC", 139: "NetBIOS", 143: "IMAP", 161: "SNMP",
            389: "LDAP", 443: "HTTPS", 445: "SMB", 554: "RTSP", 587: "SMTP", 636: "LDAPS",
            993: "IMAPS", 995: "POP3S", 1433: "MSSQL", 1723: "PPTP", 3306: "MySQL",
            3389: "RDP", 5900: "VNC", 5985: "WinRM", 5986: "WinRM", 8080: "HTTP-alt",
            8443: "HTTPS-alt", 9100: "Print"
        ]
        if let name = names[port] { return "\(port) \(name)" }
        return String(port)
    }

    // MARK: - Helpers

    private static func ipToInt(_ ip: String) -> Int {
        var value = 0
        for part in ip.split(separator: ".") {
            value = value * 256 + (Int(part) ?? 0)
        }
        return value
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
