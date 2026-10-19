import SwiftUI
import Charts

enum ChartMode: String, CaseIterable, Identifiable {
    case latency = "Latency"
    case loss = "Packet Loss"
    var id: String { rawValue }
}

/// Selectable time window for the live session graphs.
enum ChartTimeframe: String, CaseIterable, Identifiable {
    case fiveMinutes = "5 min"
    case tenMinutes = "10 min"
    case thirtyMinutes = "30 min"
    case sixtyMinutes = "60 min"
    case all = "All"

    var id: String { rawValue }

    /// Window length in seconds, or `nil` for the whole session.
    var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes:   return 5 * 60
        case .tenMinutes:    return 10 * 60
        case .thirtyMinutes: return 30 * 60
        case .sixtyMinutes:  return 60 * 60
        case .all:           return nil
        }
    }

    /// Earliest sample time to display, given the most recent sample time.
    func cutoff(latest: Date) -> Date? {
        seconds.map { latest.addingTimeInterval(-$0) }
    }
}

/// Caps how many points a single series draws, and how many points all series
/// draw together. Long sessions are evenly decimated so the whole window stays
/// visible without overwhelming Charts. The per-series limit shrinks as the
/// host count grows so the total mark count stays bounded — Swift Charts slows
/// down sharply once a chart holds tens of thousands of marks.
private let maxPointsPerSeries = 1500
private let totalPointBudget = 3000

private func perSeriesLimit(hostCount: Int) -> Int {
    max(100, min(maxPointsPerSeries, totalPointBudget / max(1, hostCount)))
}

private func downsample<T>(_ items: [T], limit: Int) -> [T] {
    guard items.count > limit, limit > 2 else { return items }
    let stride = Double(items.count - 1) / Double(limit - 1)
    var result: [T] = []
    result.reserveCapacity(limit)
    var position = 0.0
    for _ in 0..<limit {
        result.append(items[Int(position.rounded())])
        position += stride
    }
    return result
}

/// Windows a host's full history down to the samples inside the timeframe.
private func visibleSamples(_ samples: [PingSample], window: ChartTimeframe, latest: Date, limit: Int) -> [PingSample] {
    guard let cutoff = window.cutoff(latest: latest) else {
        return downsample(samples, limit: limit)
    }
    // Samples are appended in time order, so binary-search the first one in range.
    var low = 0
    var high = samples.count
    while low < high {
        let mid = (low + high) / 2
        if samples[mid].timestamp < cutoff { low = mid + 1 } else { high = mid }
    }
    return downsample(Array(samples[low...]), limit: limit)
}

/// Live latency graph: one line per host, drawn from the session history.
struct LatencyChartView: View {
    let hosts: [Host]
    let history: [UUID: [PingSample]]
    let timeframe: ChartTimeframe

    private struct Point: Identifiable {
        let time: Date
        let rtt: Double
        let host: String
        var id: String { "\(host)@\(time.timeIntervalSinceReferenceDate)" }
    }

    private var latest: Date {
        var newest = Date.distantPast
        for host in hosts {
            if let last = history[host.id]?.last?.timestamp, last > newest { newest = last }
        }
        return newest == .distantPast ? Date() : newest
    }

    private var series: (points: [Point], lost: [Point]) {
        let reference = latest
        let limit = perSeriesLimit(hostCount: hosts.count)
        var points: [Point] = []
        var lost: [Point] = []
        for host in hosts {
            let samples = visibleSamples(history[host.id] ?? [], window: timeframe, latest: reference, limit: limit)
            for sample in samples {
                if let rtt = sample.rtt {
                    points.append(Point(time: sample.timestamp, rtt: rtt, host: host.address))
                } else {
                    lost.append(Point(time: sample.timestamp, rtt: 0, host: host.address))
                }
            }
        }
        return (points, lost)
    }

    var body: some View {
        let data = series
        if data.points.isEmpty && data.lost.isEmpty {
            PlaceholderChart(message: "No latency data yet — press Start.")
        } else {
            Chart {
                ForEach(data.lost) { point in
                    PointMark(x: .value("Time", point.time), y: .value("Latency", 0))
                        .foregroundStyle(.red)
                        .symbolSize(18)
                }
                ForEach(data.points) { point in
                    LineMark(x: .value("Time", point.time), y: .value("Latency", point.rtt))
                        .foregroundStyle(by: .value("Host", point.host))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYAxisLabel("Latency (ms)")
            .chartLegend(position: .bottom, spacing: 12)
            .padding(.top, 4)
        }
    }
}

/// Live cumulative packet-loss graph, one line per host. The cumulative
/// percentage is computed from the start of the session, then sliced to the
/// visible timeframe so the line remains continuous when zooming in.
struct LossChartView: View {
    let hosts: [Host]
    let history: [UUID: [PingSample]]
    let timeframe: ChartTimeframe

    private struct Point: Identifiable {
        let time: Date
        let percent: Double
        let host: String
        var id: String { "\(host)@\(time.timeIntervalSinceReferenceDate)" }
    }

    private var latest: Date {
        var newest = Date.distantPast
        for host in hosts {
            if let last = history[host.id]?.last?.timestamp, last > newest { newest = last }
        }
        return newest == .distantPast ? Date() : newest
    }

    private var points: [Point] {
        let reference = latest
        let cutoff = timeframe.cutoff(latest: reference)
        let limit = perSeriesLimit(hostCount: hosts.count)
        var result: [Point] = []
        for host in hosts {
            let samples = history[host.id] ?? []
            var sent = 0
            var lost = 0
            var hostPoints: [Point] = []
            for sample in samples {
                sent += 1
                if sample.isLost { lost += 1 }
                // Only emit points inside the window, but keep counting from the
                // true session start so the value stays cumulative.
                if let cutoff, sample.timestamp < cutoff { continue }
                let percent = Double(lost) / Double(sent) * 100.0
                hostPoints.append(Point(time: sample.timestamp, percent: percent, host: host.address))
            }
            result.append(contentsOf: downsample(hostPoints, limit: limit))
        }
        return result
    }

    var body: some View {
        let data = points
        if data.isEmpty {
            PlaceholderChart(message: "No packet-loss data yet — press Start.")
        } else {
            Chart(data) { point in
                LineMark(x: .value("Time", point.time), y: .value("Loss", point.percent))
                    .foregroundStyle(by: .value("Host", point.host))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("Packet loss (%)")
            .chartLegend(position: .bottom, spacing: 12)
            .padding(.top, 4)
        }
    }
}

struct PlaceholderChart: View {
    let message: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
            Text(message).foregroundStyle(.secondary).font(.callout)
        }
    }
}
