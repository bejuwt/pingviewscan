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

/// Per-hop latency aggregated across one or more traceroute passes. In
/// continuous mode a new `TracerouteHop` is merged in on every pass so the
/// min/avg/max reflect the whole session rather than a single trace.
struct HopLatencyStats: Identifiable, Hashable {
    let ttl: Int
    var host: String?
    var ip: String?
    /// Probes that received a response (across all passes).
    private(set) var sampleCount: Int = 0
    private(set) var sumRtt: Double = 0
    private(set) var minRtt: Double?
    private(set) var maxRtt: Double?
    /// Most recent successful probe round-trip time.
    private(set) var lastRtt: Double?
    /// Probes sent to this hop (responded + timed out) across all passes.
    private(set) var sent: Int = 0
    private(set) var timeouts: Int = 0

    init(ttl: Int) { self.ttl = ttl }

    /// Build a single-pass aggregate from a hop (handy for reports).
    init(hop: TracerouteHop) {
        self.init(ttl: hop.ttl)
        merge(hop)
    }

    var id: Int { ttl }
    var received: Int { sampleCount }
    var avgRtt: Double? { sampleCount > 0 ? sumRtt / Double(sampleCount) : nil }
    var lossPercent: Double { sent > 0 ? Double(timeouts) / Double(sent) * 100 : (sampleCount == 0 ? 100 : 0) }

    var displayHost: String {
        if let host, !host.isEmpty, host != ip { return host }
        return ip ?? "*"
    }

    var latencyLevel: LatencyLevel {
        guard let rtt = minRtt else { return .timedOut }
        switch rtt {
        case ..<30: return .fast
        case ..<80: return .moderate
        case ..<150: return .slow
        default: return .verySlow
        }
    }

    /// Fold one pass's hop results into the running aggregate.
    mutating func merge(_ hop: TracerouteHop) {
        if let value = hop.host, !value.isEmpty { host = value }
        if let value = hop.ip { ip = value }
        for rtt in hop.rtts {
            sampleCount += 1
            sumRtt += rtt
            minRtt = min(minRtt ?? rtt, rtt)
            maxRtt = max(maxRtt ?? rtt, rtt)
        }
        if let value = hop.rtts.last { lastRtt = value }
        sent += hop.sent
        timeouts += hop.timeouts
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
    /// Aggregated per-hop latency across all passes of the session.
    var stats: [HopLatencyStats] = []
    /// Number of completed passes (1 for a single trace).
    var rounds: Int = 1

    var respondedHops: [TracerouteHop] { hops.filter { !$0.isTimeout } }
    var timeoutCount: Int { hops.reduce(0) { $0 + $1.timeouts } }
    var probeCount: Int { hops.reduce(0) { $0 + $1.sent } }
    var duration: TimeInterval { (finished ?? Date()).timeIntervalSince(started ?? generated) }

    /// Aggregated stats if present, otherwise a one-pass view of the hops.
    var statsOrHops: [HopLatencyStats] {
        stats.isEmpty ? hops.map(HopLatencyStats.init(hop:)) : stats
    }

    var reachedTarget: Bool {
        guard let ip = resolvedIP else { return false }
        return hops.contains { $0.ip == ip && !$0.isTimeout }
    }
}
