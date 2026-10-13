import SwiftUI
import Charts

enum ChartMode: String, CaseIterable, Identifiable {
    case latency = "Latency"
    case loss = "Packet Loss"
    var id: String { rawValue }
}

/// Live latency graph: one line per host, drawn from the recent sample buffer.
struct LatencyChartView: View {
    let hosts: [Host]
    let recent: [UUID: [PingSample]]

    private struct Point: Identifiable {
        let id = UUID()
        let time: Date
        let rtt: Double
        let host: String
    }

    private var points: [Point] {
        var result: [Point] = []
        for host in hosts {
            for sample in recent[host.id] ?? [] {
                if let rtt = sample.rtt {
                    result.append(Point(time: sample.timestamp, rtt: rtt, host: host.address))
                }
            }
        }
        return result
    }

    private var lostPoints: [Point] {
        var result: [Point] = []
        for host in hosts {
            for sample in recent[host.id] ?? [] where sample.isLost {
                result.append(Point(time: sample.timestamp, rtt: 0, host: host.address))
            }
        }
        return result
    }

    var body: some View {
        if points.isEmpty {
            PlaceholderChart(message: "No latency data yet — press Start.")
        } else {
            Chart {
                ForEach(lostPoints) { point in
                    PointMark(x: .value("Time", point.time), y: .value("Latency", 0))
                        .foregroundStyle(.red)
                        .symbolSize(18)
                }
                ForEach(points) { point in
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

/// Live cumulative packet-loss graph, one line per host.
struct LossChartView: View {
    let hosts: [Host]
    let recent: [UUID: [PingSample]]

    private struct Point: Identifiable {
        let id = UUID()
        let time: Date
        let percent: Double
        let host: String
    }

    private var points: [Point] {
        var result: [Point] = []
        for host in hosts {
            var sent = 0
            var lost = 0
            for sample in recent[host.id] ?? [] {
                sent += 1
                if sample.isLost { lost += 1 }
                let percent = sent > 0 ? Double(lost) / Double(sent) * 100.0 : 0
                result.append(Point(time: sample.timestamp, percent: percent, host: host.address))
            }
        }
        return result
    }

    var body: some View {
        if points.isEmpty {
            PlaceholderChart(message: "No packet-loss data yet — press Start.")
        } else {
            Chart(points) { point in
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

private struct PlaceholderChart: View {
    let message: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
            Text(message).foregroundStyle(.secondary).font(.callout)
        }
    }
}
