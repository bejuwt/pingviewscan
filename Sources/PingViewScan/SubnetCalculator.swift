import Foundation

/// Result of computing an IPv4 subnet from an address and prefix length.
struct SubnetInfo {
    let address: String
    let prefix: Int
    let network: String
    let broadcast: String
    let mask: String
    let wildcard: String
    let firstUsable: String?
    let lastUsable: String?
    let usableHosts: UInt64
    let totalAddresses: UInt64
    let ipClass: String
    let scope: String

    var cidr: String { "\(network)/\(prefix)" }
    var addressBinary: String { SubnetCalculator.binary(address) }
    var maskBinary: String { SubnetCalculator.binary(mask) }

    /// Plain-text summary suitable for the clipboard.
    var summary: String {
        var lines = [
            "Address:        \(address)",
            "Network:        \(cidr)",
            "Subnet mask:    \(mask)",
            "Wildcard mask:  \(wildcard)",
            "Network addr:   \(network)",
            "Broadcast:      \(broadcast)"
        ]
        if let first = firstUsable, let last = lastUsable {
            lines.append("Usable range:   \(first) - \(last)")
        }
        lines.append("Usable hosts:   \(usableHosts)")
        lines.append("Total addrs:    \(totalAddresses)")
        lines.append("IP class:       \(ipClass)")
        lines.append("Scope:          \(scope)")
        return lines.joined(separator: "\n")
    }
}

/// Pure IPv4 subnet math, exposed for the Subnet Calculator tab.
enum SubnetCalculator {

    static func compute(address: String, prefix: Int) -> SubnetInfo? {
        guard let ip = IPRange.ipToInt(address), (0...32).contains(prefix) else { return nil }

        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix)
        let wildcard = ~mask
        let network = ip & mask
        let broadcast = network | wildcard
        let total = UInt64(1) << UInt64(32 - prefix)

        let firstUsable: UInt32?
        let lastUsable: UInt32?
        let usable: UInt64
        switch prefix {
        case 32:
            firstUsable = network
            lastUsable = network
            usable = 1
        case 31:
            firstUsable = network
            lastUsable = broadcast
            usable = 2
        default:
            firstUsable = network &+ 1
            lastUsable = broadcast &- 1
            usable = total &- 2
        }

        return SubnetInfo(
            address: IPRange.intToIP(ip),
            prefix: prefix,
            network: IPRange.intToIP(network),
            broadcast: IPRange.intToIP(broadcast),
            mask: IPRange.intToIP(mask),
            wildcard: IPRange.intToIP(wildcard),
            firstUsable: firstUsable.map(IPRange.intToIP),
            lastUsable: lastUsable.map(IPRange.intToIP),
            usableHosts: usable,
            totalAddresses: total,
            ipClass: ipClass(ip),
            scope: scope(ip)
        )
    }

    // MARK: - Helpers

    static func binary(_ dotted: String) -> String {
        guard let value = IPRange.ipToInt(dotted) else { return "" }
        let bits = String(value, radix: 2)
        let padded = String(repeating: "0", count: 32 - bits.count) + bits
        return stride(from: 0, to: 32, by: 8)
            .map { offset -> String in
                let start = padded.index(padded.startIndex, offsetBy: offset)
                let end = padded.index(start, offsetBy: 8)
                return String(padded[start..<end])
            }
            .joined(separator: ".")
    }

    private static func ipClass(_ ip: UInt32) -> String {
        let first = (ip >> 24) & 0xFF
        switch first {
        case 0...127: return "A"
        case 128...191: return "B"
        case 192...223: return "C"
        case 224...239: return "D (multicast)"
        default: return "E (reserved)"
        }
    }

    private static func scope(_ ip: UInt32) -> String {
        let a = (ip >> 24) & 0xFF
        let b = (ip >> 16) & 0xFF
        switch true {
        case a == 0: return "This network"
        case a == 10: return "Private (RFC 1918)"
        case a == 100 && (64...127).contains(b): return "Shared / CGNAT (RFC 6598)"
        case a == 127: return "Loopback"
        case a == 169 && b == 254: return "Link-local (APIPA)"
        case a == 172 && (16...31).contains(b): return "Private (RFC 1918)"
        case a == 192 && b == 168: return "Private (RFC 1918)"
        case a == 192 && b == 0 && (ip >> 8 & 0xFF) == 2: return "Documentation (TEST-NET-1)"
        case a == 198 && b == 51 && (ip >> 8 & 0xFF) == 100: return "Documentation (TEST-NET-2)"
        case a == 203 && b == 0 && (ip >> 8 & 0xFF) == 113: return "Documentation (TEST-NET-3)"
        case (224...239).contains(a): return "Multicast"
        case a >= 240: return "Reserved"
        default: return "Public"
        }
    }
}
