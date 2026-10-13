import Foundation

/// Normalises pasted host lists, including a range copied straight from Excel,
/// Numbers or Google Sheets. Spreadsheets separate columns with tabs, rows with
/// CRLF, may wrap cells in quotes and usually append a trailing newline.
enum HostImport {

    /// Separators between individual entries: spreadsheet tabs, rows, the CSV
    /// characters, and plain spaces/host lists.
    private static let separators: Set<Character> = ["\t", "\n", ",", ";", " "]

    /// Splits raw clipboard text into individual host entries. When
    /// `filterInvalid` is true, values that are neither a valid IP address nor a
    /// plausible host name (for example spreadsheet headers such as "IP" or
    /// "Address") are dropped.
    static func parse(_ raw: String, filterInvalid: Bool = false) -> [String] {
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var seen = Set<String>()
        var hosts: [String] = []

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            for rawField in line.split(whereSeparator: { separators.contains($0) }) {
                let field = stripQuotes(String(rawField))
                guard !field.isEmpty else { continue }
                if filterInvalid && !isValidHost(field) { continue }
                if seen.insert(field.lowercased()).inserted {
                    hosts.append(field)
                }
            }
        }
        return hosts
    }

    /// A value is accepted if it is a valid IPv4/IPv6 address, or a plausible
    /// host name. A host name must contain a dot or a digit so that bare header
    /// words ("IP", "Address", "Hostname") are rejected while "router.local",
    /// "web-01", "srv2.corp" pass.
    static func isValidHost(_ value: String) -> Bool {
        isIPAddress(value) || isPlausibleHostname(value)
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 { return true }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, value, &ipv6) == 1 { return true }
        return false
    }

    private static func isPlausibleHostname(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 253 else { return false }
        // Digits-and-dots only means it was meant to be an IP; a valid one would
        // already have matched above, so reject malformed ones like "256.1.1.1".
        if value.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        guard value.contains(".") || value.contains(where: { $0.isNumber }) else { return false }

        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

        for label in value.split(separator: ".", omittingEmptySubsequences: false) {
            if label.isEmpty { continue }
            if label.count > 63 { return false }
            if label.hasPrefix("-") || label.hasSuffix("-") { return false }
        }
        return true
    }

    private static func stripQuotes(_ value: String) -> String {
        var field = value.trimmingCharacters(in: .whitespaces)
        while field.count >= 2 {
            let first = field.first!
            let last = field.last!
            guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else { break }
            field = String(field.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return field
    }
}
