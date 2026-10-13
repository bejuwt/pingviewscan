import Foundation

/// Builds a self-contained HTML report (with inline SVG graphs) and a raw CSV
/// export from a `SessionReport`.
enum ReportExporter {

    static let palette = [
        "#2563eb", "#dc2626", "#16a34a", "#d97706", "#7c3aed", "#0891b2",
        "#db2777", "#65a30d", "#0d9488", "#9333ea", "#ea580c", "#4f46e5"
    ]

    // MARK: - HTML report

    static func html(_ report: SessionReport) -> String {
        let allSamples = report.hosts.flatMap { $0.samples }
        let start = report.started ?? allSamples.map(\.timestamp).min() ?? report.generated
        let rawEnd = report.ended ?? allSamples.map(\.timestamp).max() ?? report.generated
        let end = rawEnd > start ? rawEnd : start.addingTimeInterval(1)

        var latencySeries: [SVG.Series] = []
        var lossSeries: [SVG.Series] = []
        var lostMarkers: [Date] = []
        var maxRtt: Double = 0

        for (index, host) in report.hosts.enumerated() {
            let color = palette[index % palette.count]

            let points = host.samples.compactMap { sample -> (Date, Double)? in
                guard let rtt = sample.rtt else { return nil }
                return (sample.timestamp, rtt)
            }
            maxRtt = max(maxRtt, points.map { $0.1 }.max() ?? 0)
            latencySeries.append(SVG.Series(name: host.address, color: color, points: points))
            lostMarkers.append(contentsOf: host.samples.filter(\.isLost).map(\.timestamp))

            var sent = 0
            var lost = 0
            var lossPoints: [(Date, Double)] = []
            for sample in host.samples {
                sent += 1
                if sample.isLost { lost += 1 }
                lossPoints.append((sample.timestamp, Double(lost) / Double(sent) * 100.0))
            }
            lossSeries.append(SVG.Series(name: host.address, color: color, points: lossPoints))
        }

        let latencyYMax = SVG.niceMax(max(maxRtt * 1.15, 1))
        let latencyChart = SVG.lineChart(width: 1020, height: 360,
                                         title: "Latency over time",
                                         series: latencySeries,
                                         yMin: 0, yMax: latencyYMax,
                                         yLabel: "Latency (ms)",
                                         start: start, end: end,
                                         lostMarkers: lostMarkers)
        let lossChart = SVG.lineChart(width: 1020, height: 320,
                                      title: "Packet loss over time (cumulative)",
                                      series: lossSeries,
                                      yMin: 0, yMax: 100,
                                      yLabel: "Packet loss (%)",
                                      start: start, end: end)

        let summaryRows = report.hosts.enumerated().map { index, host -> String in
            let color = palette[index % palette.count]
            let s = host.stats
            let lossClass = s.lossPercent > 0 ? "bad" : "good"
            return """
            <tr>
              <td class="host"><span class="swatch" style="background:\(color)"></span>\(SVG.escape(host.address))</td>
              <td class="mono">\(SVG.escape(host.ip ?? "—"))</td>
              <td>\(s.sent)</td>
              <td>\(s.received)</td>
              <td>\(s.lost)</td>
              <td class="\(lossClass)">\(ms(s.lossPercent))%</td>
              <td class="mono">\(ms(s.last))</td>
              <td class="mono">\(ms(s.minRtt))</td>
              <td class="mono">\(ms(s.avgRtt))</td>
              <td class="mono">\(ms(s.maxRtt))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let totalSent = report.hosts.reduce(0) { $0 + $1.stats.sent }
        let totalLost = report.hosts.reduce(0) { $0 + $1.stats.lost }
        let overallLoss = totalSent > 0 ? Double(totalLost) / Double(totalSent) * 100 : 0
        let duration = (report.ended ?? end).timeIntervalSince(report.started ?? start)

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
          .card .value.bad { color: #dc2626; }
          .panel { background: #fff; border: 1px solid #e5e7eb; border-radius: 12px; padding: 18px; margin-bottom: 24px; }
          .panel h2 { font-size: 15px; margin: 0 0 12px; }
          table { width: 100%; border-collapse: collapse; font-size: 13px; }
          th, td { padding: 8px 10px; text-align: right; border-bottom: 1px solid #f1f3f5; white-space: nowrap; }
          th:first-child, td:first-child, th:nth-child(2), td:nth-child(2) { text-align: left; }
          th { font-size: 11px; text-transform: uppercase; letter-spacing: .04em; color: #6b7280; background: #f9fafb; }
          tbody tr:hover { background: #f9fafb; }
          .host { font-weight: 600; display: flex; align-items: center; }
          .swatch { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin-right: 8px; }
          .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
          .good { color: #16a34a; }
          .bad { color: #dc2626; font-weight: 600; }
          .chart { width: 100%; }
          footer { color: #9ca3af; font-size: 12px; text-align: center; margin-top: 8px; }
        </style>
        </head>
        <body>
        <div class="wrap">
          <h1>PingViewScan Report</h1>
          <div class="sub">Generated \(dateTime(report.generated)) · Interval \(String(format: "%g", report.interval))s · Timeout \(String(format: "%g", report.timeout))s</div>

          <div class="cards">
            <div class="card"><div class="label">Hosts</div><div class="value">\(report.hosts.count)</div></div>
            <div class="card"><div class="label">Duration</div><div class="value">\(durationString(duration))</div></div>
            <div class="card"><div class="label">Probes sent</div><div class="value">\(totalSent)</div></div>
            <div class="card"><div class="label">Packets lost</div><div class="value \(totalLost > 0 ? "bad" : "")">\(totalLost)</div></div>
            <div class="card"><div class="label">Overall loss</div><div class="value \(overallLoss > 0 ? "bad" : "")">\(ms(overallLoss))%</div></div>
            <div class="card"><div class="label">Session start</div><div class="value" style="font-size:15px">\(report.started.map(dateTime) ?? "—")</div></div>
          </div>

          <div class="panel">
            <h2>Summary</h2>
            <table>
              <thead>
                <tr>
                  <th>Host</th><th>IP</th><th>Sent</th><th>Recv</th><th>Lost</th><th>Loss %</th>
                  <th>Last</th><th>Min</th><th>Avg</th><th>Max</th>
                </tr>
              </thead>
              <tbody>
        \(summaryRows)
              </tbody>
            </table>
          </div>

          <div class="panel chart">\(latencyChart)</div>
          <div class="panel chart">\(lossChart)</div>

          <footer>PingViewScan for macOS · Red ticks on the latency chart mark lost packets.</footer>
        </div>
        </body>
        </html>
        """
    }

    // MARK: - CSV export

    static func csv(_ report: SessionReport) -> String {
        var lines = ["Host,IP,Sequence,Timestamp,RTT_ms,Lost"]
        for host in report.hosts {
            for sample in host.samples {
                let timestamp = isoFormatter.string(from: sample.timestamp)
                let rtt = sample.rtt.map { String(format: "%.3f", $0) } ?? ""
                lines.append("\(csvField(host.address)),\(csvField(host.ip ?? "")),\(sample.sequence),\(timestamp),\(rtt),\(sample.isLost ? "1" : "0")")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", value)
    }

    private static func ms(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func durationString(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, seconds)) ?? "0s"
    }

    private static func csvField(_ value: String) -> String {
        var field = value
        // Neutralise spreadsheet formula injection (cells starting with = + - @).
        if let first = field.first, "=+-@\t\r".contains(first) {
            field = "'" + field
        }
        if field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
