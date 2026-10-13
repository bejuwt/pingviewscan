import Foundation

/// One ICMP echo attempt against a host.
struct PingSample: Identifiable, Hashable {
    let id: UUID
    let sequence: Int
    let timestamp: Date
    /// Round-trip time in milliseconds, or `nil` when the packet was lost / timed out.
    let rtt: Double?

    var isLost: Bool { rtt == nil }
}

/// Aggregate counters for a host for the current session.
struct HostStats {
    var sent: Int = 0
    var received: Int = 0
    var last: Double?
    var minRtt: Double?
    var maxRtt: Double?
    var totalRtt: Double = 0

    var lost: Int { sent - received }
    var lossPercent: Double { sent > 0 ? Double(lost) / Double(sent) * 100.0 : 0 }
    var avgRtt: Double? { received > 0 ? totalRtt / Double(received) : nil }

    mutating func add(rtt: Double?) {
        sent += 1
        if let rtt {
            received += 1
            last = rtt
            totalRtt += rtt
            minRtt = min(minRtt ?? rtt, rtt)
            maxRtt = max(maxRtt ?? rtt, rtt)
        } else {
            last = nil
        }
    }

    mutating func reset() { self = HostStats() }
}

/// A monitored host shown in the table.
struct Host: Identifiable {
    let id: UUID
    var address: String
    var ip: String?
    var stats = HostStats()
    var enabled = true

    init(id: UUID = UUID(), address: String) {
        self.id = id
        self.address = address
    }
}

/// Snapshot of a finished / in-progress session, used by the report exporter.
struct SessionReport {
    let generated: Date
    let started: Date?
    let ended: Date?
    let interval: Double
    let timeout: Double
    let hosts: [HostReport]
}

struct HostReport {
    let address: String
    let ip: String?
    let stats: HostStats
    let samples: [PingSample]
}
