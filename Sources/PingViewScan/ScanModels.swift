import Foundation

/// One address probed by the network scanner.
struct ScanResult: Identifiable {
    let id: UUID
    let ip: String
    var hostname: String?
    var pingMs: Double?
    var openPorts: [UInt16] = []
    var scanned = false

    /// A host counts as discovered if it answered ICMP or exposed a TCP port.
    var isAlive: Bool { pingMs != nil || !openPorts.isEmpty }

    init(ip: String) {
        self.id = UUID()
        self.ip = ip
    }
}

/// Grouped port lists offered in the scanner UI.
struct PortPreset: Identifiable {
    let id = UUID()
    let name: String
    let ports: [UInt16]
    var text: String { ports.map(String.init).joined(separator: ",") }

    static let all: [PortPreset] = [
        PortPreset(name: "Common services",
                   ports: [21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 445, 554,
                           587, 993, 995, 1433, 1723, 3306, 3389, 5900, 5985, 5986,
                           8080, 8443, 9100]),
        PortPreset(name: "Web servers",
                   ports: [80, 443, 3000, 5000, 8000, 8080, 8443, 8888, 9000]),
        PortPreset(name: "Windows / AD",
                   ports: [53, 88, 135, 139, 389, 445, 464, 636, 3268, 3389, 5985, 5986, 5357]),
        PortPreset(name: "Infrastructure",
                   ports: [22, 23, 53, 67, 80, 123, 161, 179, 443, 514, 1723, 5060]),
        PortPreset(name: "Remote access",
                   ports: [22, 23, 3389, 5900, 5901, 5985, 5986])
    ]
}

/// Parses comma-separated ports and ranges, e.g. "22,80,443,8000-8010".
enum PortList {
    static func parse(_ text: String) -> [UInt16] {
        var set = Set<UInt16>()
        for token in text.split(whereSeparator: { ", \n\t".contains($0) }) {
            if let dash = token.firstIndex(of: "-") {
                let startString = String(token[token.startIndex..<dash])
                let endString = String(token[token.index(after: dash)...])
                if let start = UInt16(startString), let end = UInt16(endString), start <= end {
                    var port = start
                    while port <= end { set.insert(port); if port == end { break }; port += 1 }
                }
            } else if let value = UInt16(token) {
                set.insert(value)
            }
        }
        return set.sorted()
    }
}
