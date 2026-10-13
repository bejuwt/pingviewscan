import Foundation

/// Expands user input into a list of IPv4 addresses.
///
/// Supported forms (comma / space / newline separated):
///   - CIDR:      10.5.200.0/24
///   - Range:     10.5.200.1-254   or   10.5.200.1-10.5.200.50
///   - Wildcard:  10.5.200.*       or   10.5.*.1
///   - Single:    10.5.200.1
///   - Hostname:  switch-01.local  (passed through for direct probing)
enum IPRange {

    static func expand(_ input: String, limit: Int = 65536) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        let tokens = input
            .split(whereSeparator: { ",;\n\t ".contains($0) })
            .map(String.init)

        for token in tokens where !token.isEmpty {
            for ip in expandToken(token, cap: limit) {
                if seen.insert(ip).inserted {
                    output.append(ip)
                    if output.count >= limit { return output }
                }
            }
        }
        return output
    }

    // MARK: - Token handling

    private static func expandToken(_ token: String, cap: Int) -> [String] {
        if token.contains("/") { return cidr(token, cap: cap) ?? [] }
        if token.contains("*") || token.lowercased().contains("x") { return wildcard(token, cap: cap) ?? [] }
        if token.contains("-") { return range(token, cap: cap) ?? [] }
        return [token]
    }

    static func ipToInt(_ string: String) -> UInt32? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let byte = UInt32(part), byte <= 255 else { return nil }
            value = (value << 8) | byte
        }
        return value
    }

    static func intToIP(_ value: UInt32) -> String {
        "\((value >> 24) & 0xFF).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    private static func cidr(_ token: String, cap: Int) -> [String]? {
        let components = token.split(separator: "/")
        guard components.count == 2,
              let base = ipToInt(String(components[0])),
              let prefix = Int(components[1]), prefix >= 0, prefix <= 32 else { return nil }
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << UInt32(32 - prefix)
        let network = base & mask
        let broadcast = network | ~mask

        if prefix == 32 { return [intToIP(network)] }
        if prefix == 31 { return [intToIP(network), intToIP(broadcast)] }

        var result: [String] = []
        var value = network &+ 1
        while value < broadcast && result.count < cap {
            result.append(intToIP(value))
            value &+= 1
        }
        return result
    }

    private static func range(_ token: String, cap: Int) -> [String]? {
        let components = token.split(separator: "-")
        guard components.count == 2 else { return nil }
        let startString = String(components[0])
        let endString = String(components[1])

        var result: [String] = []
        if endString.contains(".") {
            guard let start = ipToInt(startString), let end = ipToInt(endString), start <= end else { return nil }
            var value = start
            while value <= end && result.count < cap {
                result.append(intToIP(value))
                if value == end { break }
                value &+= 1
            }
        } else {
            guard let start = ipToInt(startString),
                  let last = Int(endString),
                  last >= 0, last <= 255,
                  last >= Int(start & 0xFF) else { return nil }
            let base = start & 0xFFFFFF00
            for octet in Int(start & 0xFF)...last where result.count < cap {
                result.append(intToIP(base | UInt32(octet)))
            }
        }
        return result
    }

    private static func wildcard(_ token: String, cap: Int) -> [String]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 else { return nil }

        var octets: [[UInt32]] = []
        for part in parts {
            if part == "*" || part.lowercased() == "x" {
                octets.append(Array(0...255))
            } else if let value = UInt32(part), value <= 255 {
                octets.append([value])
            } else {
                return nil
            }
        }

        var result: [String] = []
        outer: for a in octets[0] {
            for b in octets[1] {
                for c in octets[2] {
                    for d in octets[3] {
                        result.append("\(a).\(b).\(c).\(d)")
                        if result.count >= cap { break outer }
                    }
                }
            }
        }
        return result
    }
}
