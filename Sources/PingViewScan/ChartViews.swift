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
/// draw together. Long sessions are decimated so the whole window stays visible
/// without overwhelming Charts, and the per-series limit shrinks as the host
/// count grows so the total mark count stays bounded — Swift Charts slows down
/// sharply once a chart holds tens of thousands of marks.
private let maxPointsPerSeries = 1500
private let totalPointBudget = 3000

/// The smallest time bucket a series is decimated into. Buckets are aligned to
/// absolute time, so this only bounds how fine the decimation can get.
private let minBucketSeconds: TimeInterval = 0.5

private func perSeriesLimit(hostCount: Int) -> Int {
    max(100, min(maxPointsPerSeries, totalPointBudget / max(1, hostCount)))
}

/// Width of the time buckets used to decimate one series, chosen so a visible
/// window holds roughly `limit` buckets.
///
/// A fixed window has a constant width, so the bucket grid never moves. The
/// "All" range has no fixed length, so its ideal width would grow with the
/// session and drag the whole grid along with it every update — reintroducing
/// the churn. Quantizing to a coarse ladder keeps the width (and grid) put for
/// long stretches, so the selection stays stable.
private func bucketWidth(window: ChartTimeframe, span: TimeInterval, limit: Int) -> TimeInterval {
    let target = max(minBucketSeconds, (window.seconds ?? span) / Double(max(1, limit)))
    guard window.seconds == nil else { return target }
    return ladderWidth(atLeast: target)
}

/// Smallest "nice" bucket width that is at least `target`.
private func ladderWidth(atLeast target: TimeInterval) -> TimeInterval {
    let ladder: [TimeInterval] = [1, 2, 5, 10, 20, 30, 60, 120, 300, 600,
                                  1800, 3600, 7200, 21600, 43200, 86400]
    for width in ladder where width >= target { return width }
    return ladder[ladder.count - 1]
}

/// Decimates a time-ordered series to at most roughly `limit` points by keeping
/// the newest sample in each fixed-width, absolutely-aligned time bucket.
///
/// This must stay *stable* across renders: an index-based decimation shifts the
/// whole selection every time the sample count changes, so Charts rebuilds (and
/// visibly flickers) every line on each refresh — most noticeable once a window
/// is long enough to trigger decimation. Because the bucket edges never move as
/// the visible window slides, existing points keep their identity and Charts
/// only adds the newest points and drops the oldest.
private func decimate<T>(_ items: [T], time: (T) -> Date, bucketSeconds: TimeInterval, limit: Int) -> [T] {
    guard items.count > limit, bucketSeconds > 0 else { return items }
    var result: [T] = []
    result.reserveCapacity(limit + 2)
    var currentBucket = Int(floor(time(items[0]).timeIntervalSinceReferenceDate / bucketSeconds))
    var newestInBucket = items[0]
    for item in items.dropFirst() {
        let bucket = Int(floor(time(item).timeIntervalSinceReferenceDate / bucketSeconds))
        if bucket == currentBucket {
            newestInBucket = item
        } else {
            result.append(newestInBucket)
            currentBucket = bucket
            newestInBucket = item
        }
    }
    result.append(newestInBucket)
    return result
}

/// Windows a host's full history down to the samples inside the timeframe.
private func visibleSamples(_ samples: [PingSample], window: ChartTimeframe, latest: Date, limit: Int) -> [PingSample] {
    let scoped: ArraySlice<PingSample>
    if let cutoff = window.cutoff(latest: latest) {
        // Samples are appended in time order, so binary-search the first one in range.
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].timestamp < cutoff { low = mid + 1 } else { high = mid }
        }
        scoped = samples[low...]
    } else {
        scoped = samples[...]
    }
    guard let first = scoped.first, let last = scoped.last else { return [] }
    let width = bucketWidth(window: window, span: last.timestamp.timeIntervalSince(first.timestamp), limit: limit)
    return decimate(Array(scoped), time: { $0.timestamp }, bucketSeconds: width, limit: limit)
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
            guard let first = hostPoints.first, let last = hostPoints.last else { continue }
            let width = bucketWidth(window: timeframe, span: last.time.timeIntervalSince(first.time), limit: limit)
            result.append(contentsOf: decimate(hostPoints, time: { $0.time }, bucketSeconds: width, limit: limit))
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
