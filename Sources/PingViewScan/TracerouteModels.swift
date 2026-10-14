import Foundation

/// One TTL "ring" of a traceroute: the router(s) that answered for this hop.
struct TracerouteHop: Identifiable, Hashable {
    let id: UUID
    let ttl: Int
    var host: String?
    var ip: String?
    /// Successful probe round-trip times, in milliseconds.
    var rtts: [Double] = []
    /// Probes sent to this hop (responded + timed out).
    var sent: Int = 0
    /// Probes that received no answer.
    var timeouts: Int = 0

    init(ttl: Int) {
        self.id = UUID()
        self.ttl = ttl
    }

    var isTimeout: Bool { rtts.isEmpty }
    var received: Int { rtts.count }
    var minRtt: Double? { rtts.min() }
    var maxRtt: Double? { rtts.max() }
    var lastRtt: Double? { rtts.last }
    var avgRtt: Double? { rtts.isEmpty ? nil : rtts.reduce(0, +) / Double(rtts.count) }
    var lossPercent: Double { sent > 0 ? Double(timeouts) / Double(sent) * 100 : (isTimeout ? 100 : 0) }

    /// Best available label for the hop.
    var displayHost: String {
        if let host, !host.isEmpty, host != ip { return host }
        return ip ?? "*"
    }

    /// Colour bucket used by the UI and the report to visualise the hop's speed.
    var latencyLevel: LatencyLevel {
        guard let rtt = minRtt else { return .timedOut }
        switch rtt {
        case ..<30: return .fast
        case ..<80: return .moderate
        case ..<150: return .slow
        default: return .verySlow
        }
    }
}

/// Speed buckets shared between the on-screen path and the HTML report.
enum LatencyLevel {
    case timedOut, fast, moderate, slow, verySlow

    var hex: String {
        switch self {
        case .timedOut: return "#cbd5e1"
        case .fast:     return "#16a34a"
        case .moderate: return "#65a30d"
        case .slow:     return "#d97706"
        case .verySlow: return "#dc2626"
        }
    }

    var label: String {
        switch self {
        case .timedOut: return "no response"
        case .fast:     return "< 30 ms"
        case .moderate: return "30–80 ms"
        case .slow:     return "80–150 ms"
        case .verySlow: return "≥ 150 ms"
        }
    }
}

/// Snapshot of a traceroute run, used by the report exporter and CSV export.
struct TracerouteReport {
    let target: String
    let resolvedIP: String?
    let generated: Date
    let started: Date?
    let finished: Date?
    let maxHops: Int
    let queries: Int
    let timeout: Double
    let hops: [TracerouteHop]

    var respondedHops: [TracerouteHop] { hops.filter { !$0.isTimeout } }
    var timeoutCount: Int { hops.reduce(0) { $0 + $1.timeouts } }
    var probeCount: Int { hops.reduce(0) { $0 + $1.sent } }
    var duration: TimeInterval { (finished ?? Date()).timeIntervalSince(started ?? generated) }

    var reachedTarget: Bool {
        guard let ip = resolvedIP else { return false }
        return hops.contains { $0.ip == ip && !$0.isTimeout }
    }
}
