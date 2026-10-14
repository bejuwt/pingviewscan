import Foundation

/// Builds a self-contained HTML report (with an inline SVG hop-path diagram and
/// latency charts) and a CSV export from a `TracerouteReport`.
enum TracerouteReportExporter {

    // MARK: - HTML report

    static func html(_ report: TracerouteReport) -> String {
        let path = hopPathSVG(report)
        let latencyChart = latencyBars(report)
        let hopRows = report.hops.map { hop -> String in
            let status = hop.isTimeout
                ? "<span class=\"muted\">no response</span>"
                : "<span class=\"good\">\(SVG.escape(hostLabel(hop)))</span>"
            return """
            <tr>
              <td class="mono">\(hop.ttl)</td>
              <td>\(status)</td>
              <td class="mono">\(SVG.escape(hop.ip ?? "—"))</td>
              <td>\(hop.sent)</td>
              <td>\(hop.received)</td>
              <td>\(hop.timeouts)</td>
              <td class="\(hop.lossPercent > 0 ? "bad" : "")">\(ms(hop.lossPercent))%</td>
              <td class="mono">\(ms(hop.lastRtt))</td>
              <td class="mono">\(ms(hop.minRtt))</td>
              <td class="mono">\(ms(hop.avgRtt))</td>
              <td class="mono">\(ms(hop.maxRtt))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let reachedBadge = report.reachedTarget
            ? "<span class=\"good\">reached</span>"
            : "<span class=\"muted\">not reached within \(report.maxHops) hops</span>"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>PingViewScan Traceroute Report</title>
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
          .card .value { font-size: 22px; font-weight: 600; margin-top: 4px; overflow-wrap: anywhere; }
          .card .value.good { color: #16a34a; }
          .card .value.bad { color: #dc2626; }
          .panel { background: #fff; border: 1px solid #e5e7eb; border-radius: 12px; padding: 18px; margin-bottom: 24px; }
          .panel h2 { font-size: 15px; margin: 0 0 12px; }
          .chart { width: 100%; }
          table { width: 100%; border-collapse: collapse; font-size: 13px; }
          th, td { padding: 8px 10px; text-align: right; border-bottom: 1px solid #f1f3f5; white-space: nowrap; }
          th:nth-child(2), td:nth-child(2) { text-align: left; }
          th:nth-child(3), td:nth-child(3) { text-align: left; }
          th { font-size: 11px; text-transform: uppercase; letter-spacing: .04em; color: #6b7280; background: #f9fafb; }
          tbody tr:hover { background: #f9fafb; }
          .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
          .good { color: #16a34a; font-weight: 600; }
          .bad { color: #dc2626; font-weight: 600; }
          .muted { color: #9ca3af; }
          .dt { color: #6b7280; }
          footer { color: #9ca3af; font-size: 12px; text-align: center; margin-top: 8px; }
        </style>
        </head>
        <body>
        <div class="wrap">
          <h1>PingViewScan Traceroute Report</h1>
          <div class="sub">Target \(SVG.escape(report.target.isEmpty ? "—" : report.target))\(report.resolvedIP.map { " (\(SVG.escape($0)))" } ?? "") · Generated \(ReportExporter.dateTime(report.generated)) · Max hops \(report.maxHops) · Probes/hop \(report.queries) · Timeout \(String(format: "%g", report.timeout))s</div>

          <div class="cards">
            <div class="card"><div class="label">Hops</div><div class="value">\(report.hops.count)</div></div>
            <div class="card"><div class="label">Responded</div><div class="value good">\(report.respondedHops.count)</div></div>
            <div class="card"><div class="label">Result</div><div class="value" style="font-size:15px">\(reachedBadge)</div></div>
            <div class="card"><div class="label">Probes</div><div class="value">\(report.probeCount)</div></div>
            <div class="card"><div class="label">Timeouts</div><div class="value \(report.timeoutCount > 0 ? "bad" : "")">\(report.timeoutCount)</div></div>
            <div class="card"><div class="label">Duration</div><div class="value" style="font-size:15px">\(ReportExporter.durationString(report.duration))</div></div>
            <div class="card"><div class="label">Resolved IP</div><div class="value" style="font-size:15px">\(report.resolvedIP.map(SVG.escape) ?? "—")</div></div>
            <div class="card"><div class="label">Started</div><div class="value" style="font-size:15px">\(report.started.map(ReportExporter.dateTime) ?? "—")</div></div>
          </div>

          <div class="panel chart">\(path)</div>
          <div class="panel chart">\(latencyChart)</div>

          <div class="panel">
            <h2>Hops (\(report.hops.count))</h2>
            <table>
              <thead>
                <tr><th>#</th><th>Host</th><th>IP</th><th>Sent</th><th>Recv</th><th>Lost</th><th>Loss %</th><th>Last</th><th>Min</th><th>Avg</th><th>Max</th></tr>
              </thead>
              <tbody>
        \(hopRows)
              </tbody>
            </table>
          </div>

          <footer>PingViewScan for macOS · Node colours indicate round-trip latency; grey means no response.</footer>
        </div>
        </body>
        </html>
        """
    }

    // MARK: - CSV export

    static func csv(_ report: TracerouteReport) -> String {
        var lines = ["Hop,Host,IP,Sent,Received,Lost,Loss_percent,Last_ms,Min_ms,Avg_ms,Max_ms"]
        for hop in report.hops {
            lines.append([
                "\(hop.ttl)",
                csvField(hop.host ?? ""),
                csvField(hop.ip ?? ""),
                "\(hop.sent)",
                "\(hop.received)",
                "\(hop.timeouts)",
                num(hop.lossPercent),
                hop.lastRtt.map { String(format: "%.3f", $0) } ?? "",
                hop.minRtt.map { String(format: "%.3f", $0) } ?? "",
                hop.avgRtt.map { String(format: "%.3f", $0) } ?? "",
                hop.maxRtt.map { String(format: "%.3f", $0) } ?? ""
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Visualisations

    /// Horizontal node-and-connector diagram: source → each hop → target.
    private static func hopPathSVG(_ report: TracerouteReport) -> String {
        let steps = report.hops
        guard !steps.isEmpty else {
            return "<svg viewBox=\"0 0 1020 90\"><text x=\"24\" y=\"46\" font-size=\"14\" fill=\"#6b7280\">No hops recorded.</text></svg>"
        }

        let margin = 46.0
        let step = 150.0
        let nodeY = 66.0
        let radius = 17.0
        let width = margin * 2 + step * Double(steps.count + 1)
        let height = 200.0

        func x(_ index: Int) -> Double { margin + step * Double(index) + radius }

        var svg = "<svg viewBox=\"0 0 \(fmt(width)) \(fmt(height))\" width=\"100%\" preserveAspectRatio=\"xMidYMid meet\" role=\"img\" font-family=\"-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif\">"
        svg += "<rect x=\"0\" y=\"0\" width=\"\(fmt(width))\" height=\"\(fmt(height))\" fill=\"#ffffff\"/>"
        svg += "<text x=\"\(fmt(margin))\" y=\"24\" font-size=\"16\" font-weight=\"600\" fill=\"#111827\">Path to \(SVG.escape(report.resolvedIP ?? report.target))</text>"

        // Source node.
        let sourceX = x(0)
        svg += "<circle cx=\"\(fmt(sourceX))\" cy=\"\(fmt(nodeY))\" r=\"\(fmt(radius))\" fill=\"#2563eb\"/>"
        svg += "<text x=\"\(fmt(sourceX))\" y=\"\(fmt(nodeY + 4))\" font-size=\"11\" font-weight=\"600\" fill=\"#ffffff\" text-anchor=\"middle\">You</text>"
        svg += "<text x=\"\(fmt(sourceX))\" y=\"\(fmt(nodeY + 34))\" font-size=\"10\" fill=\"#6b7280\" text-anchor=\"middle\">this Mac</text>"

        var previousX = sourceX
        for (index, hop) in steps.enumerated() {
            let nodeX = x(index + 1)
            let color = hop.latencyLevel.hex

            // Connector from the previous node to this one.
            svg += "<line x1=\"\(fmt(previousX + radius))\" y1=\"\(fmt(nodeY))\" x2=\"\(fmt(nodeX - radius))\" y2=\"\(fmt(nodeY))\" stroke=\"\(color)\" stroke-width=\"4\" stroke-linecap=\"round\"/>"

            svg += "<circle cx=\"\(fmt(nodeX))\" cy=\"\(fmt(nodeY))\" r=\"\(fmt(radius))\" fill=\"\(color)\"/>"
            let numberColor = hop.isTimeout ? "#64748b" : "#ffffff"
            svg += "<text x=\"\(fmt(nodeX))\" y=\"\(fmt(nodeY + 4))\" font-size=\"11\" font-weight=\"600\" fill=\"\(numberColor)\" text-anchor=\"middle\">\(hop.ttl)</text>"

            // Labels under the node.
            svg += "<text x=\"\(fmt(nodeX))\" y=\"\(fmt(nodeY + 34))\" font-size=\"10\" fill=\"#374151\" text-anchor=\"middle\">\(SVG.escape(truncate(shortHost(hop), 20)))</text>"
            if let ip = hop.ip {
                svg += "<text x=\"\(fmt(nodeX))\" y=\"\(fmt(nodeY + 48))\" font-size=\"9\" fill=\"#9ca3af\" text-anchor=\"middle\">\(SVG.escape(ip))</text>"
            }
            let rttText = hop.minRtt.map { String(format: "%.1f ms", $0) } ?? "—"
            svg += "<text x=\"\(fmt(nodeX))\" y=\"\(fmt(nodeY + 64))\" font-size=\"10\" fill=\"#6b7280\" text-anchor=\"middle\">\(rttText)</text>"

            previousX = nodeX
        }

        // Legend.
        let legendY = height - 20
        var legendX = margin
        svg += "<g font-size=\"11\" fill=\"#6b7280\">"
        for level in [LatencyLevel.fast, .moderate, .slow, .verySlow, .timedOut] {
            svg += "<rect x=\"\(fmt(legendX))\" y=\"\(fmt(legendY - 10))\" width=\"12\" height=\"12\" rx=\"3\" fill=\"\(level.hex)\"/>"
            svg += "<text x=\"\(fmt(legendX + 17))\" y=\"\(fmt(legendY))\"\(level == .timedOut ? " font-style=\"italic\"" : "")>\(SVG.escape(level.label))</text>"
            legendX += 24 + Double(level.label.count) * 7
        }
        svg += "</g>"

        svg += "</svg>"
        return svg
    }

    private static func latencyBars(_ report: TracerouteReport) -> String {
        let responding = report.hops.filter { !$0.isTimeout }
        guard !responding.isEmpty else {
            return SVG.barChart(width: 1020, height: 240, title: "Latency by hop",
                                bars: [], yLabel: "Latency (ms)")
        }
        let bars = responding.map { hop -> (label: String, value: Double, color: String) in
            let label = hop.ip.map { "\(hop.ttl). \($0)" } ?? "\(hop.ttl)"
            return (label: label, value: hop.minRtt ?? 0, color: hop.latencyLevel.hex)
        }
        return SVG.barChart(width: 1020, height: 320, title: "Latency by hop (best probe)",
                            bars: bars, yLabel: "Latency (ms)",
                            rotateLabels: bars.count > 6, valueSuffix: "")
    }

    // MARK: - Helpers

    private static func shortHost(_ hop: TracerouteHop) -> String {
        hop.host ?? hop.ip ?? "*"
    }

    private static func hostLabel(_ hop: TracerouteHop) -> String {
        guard let host = hop.host, host != hop.ip else { return hop.ip ?? "*" }
        return host
    }

    private static func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    private static func ms(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func num(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func csvField(_ value: String) -> String {
        var field = value
        if let first = field.first, "=+-@\t\r".contains(first) {
            field = "'" + field
        }
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func truncate(_ string: String, _ maxLength: Int) -> String {
        string.count > maxLength ? String(string.prefix(maxLength - 1)) + "\u{2026}" : string
    }
}
