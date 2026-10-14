import Foundation

/// Final result of a traceroute invocation.
struct TracerouteOutcome {
    let hops: [TracerouteHop]
    let resolvedIP: String?
    let reachedTarget: Bool
    let output: String
}

/// Drives the system `/usr/sbin/traceroute` binary and parses its output into
/// hops as they arrive, so the UI can update live.
enum TracerouteRunner {

    /// Blocking traceroute. `onHeader` fires once the resolved target IP is
    /// known; `onHop` fires as each hop is completed. Always call off the main
    /// thread.
    static func trace(target rawTarget: String,
                      queries: Int = 3,
                      maxHops: Int = 30,
                      timeout: Double = 2,
                      onHeader: @escaping (String?) -> Void = { _ in },
                      onHop: @escaping (TracerouteHop) -> Void = { _ in }) -> TracerouteOutcome {

        // Guard against argument injection: a leading "-" would be parsed by
        // traceroute's getopt as an option.
        let target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !target.hasPrefix("-") else {
            onHeader(nil)
            return TracerouteOutcome(hops: [], resolvedIP: nil, reachedTarget: false,
                                     output: "Refused invalid target: \(rawTarget)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/traceroute")

        // BSD traceroute: -m max_ttl, -w waittime (seconds), -q nqueries.
        let waitSeconds = max(1, Int(timeout.rounded()))
        process.arguments = ["-m", "\(max(1, maxHops))",
                             "-w", "\(waitSeconds)",
                             "-q", "\(max(1, queries))",
                             target]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            onHeader(nil)
            return TracerouteOutcome(hops: [], resolvedIP: nil, reachedTarget: false,
                                     output: "Failed to launch traceroute: \(error.localizedDescription)")
        }

        // Watchdog: traceroute bounds its own runtime, but guard against a hang.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        let budget = Double(waitSeconds + 1) * Double(max(1, maxHops)) + 10
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + budget, execute: watchdog)

        let parser = TracerouteParser()
        var rawOutput = ""
        let handle = pipe.fileHandleForReading
        var buffer = Data()

        func processLine(_ line: String) {
            rawOutput += line + "\n"
            let headerBefore = parser.resolvedIP
            if let completed = parser.consume(line) { onHop(completed) }
            if parser.resolvedIP != headerBefore { onHeader(parser.resolvedIP) }
        }

        func drain(_ data: Data, flush: Bool) {
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                processLine(String(decoding: lineData, as: UTF8.self))
            }
            if flush, !buffer.isEmpty {
                let line = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll()
                processLine(line)
            }
        }

        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            drain(chunk, flush: false)
        }
        drain(Data(), flush: true)
        process.waitUntilExit()
        watchdog.cancel()

        if let final = parser.finish() { onHop(final) }
        onHeader(parser.resolvedIP)

        let reached = parser.resolvedIP.map { ip in
            parser.hops.contains { $0.ip == ip && !$0.isTimeout }
        } ?? false

        return TracerouteOutcome(hops: parser.hops,
                                 resolvedIP: parser.resolvedIP,
                                 reachedTarget: reached,
                                 output: rawOutput)
    }

    /// Async wrapper that runs the blocking traceroute off the caller's executor.
    static func traceAsync(target: String,
                           queries: Int = 3,
                           maxHops: Int = 30,
                           timeout: Double = 2,
                           onHeader: @escaping @Sendable (String?) -> Void = { _ in },
                           onHop: @escaping @Sendable (TracerouteHop) -> Void = { _ in }) async -> TracerouteOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let outcome = trace(target: target, queries: queries, maxHops: maxHops,
                                    timeout: timeout, onHeader: onHeader, onHop: onHop)
                continuation.resume(returning: outcome)
            }
        }
    }
}

/// Incremental parser for BSD `traceroute` output. Feed it one line at a time;
/// it returns a completed hop whenever a new hop begins.
final class TracerouteParser {
    private(set) var resolvedIP: String?
    private(set) var hops: [TracerouteHop] = []

    /// Consume one line of traceroute output. Returns the hop that just became
    /// complete (i.e. when the next hop's number appears), otherwise `nil`.
    @discardableResult
    func consume(_ line: String) -> TracerouteHop? {
        let text = line.hasSuffix("\r") ? String(line.dropLast()) : line

        if resolvedIP == nil, let ip = Self.parseHeader(text) {
            resolvedIP = ip
            return nil
        }

        if let (ttl, content) = Self.splitHop(text), ttl == (hops.last?.ttl ?? 0) + 1 {
            // A new hop begins: the previous one is now complete.
            let completed = hops.last
            var hop = TracerouteHop(ttl: ttl)
            Self.absorb(content, into: &hop)
            hops.append(hop)
            return completed
        } else if !hops.isEmpty {
            Self.absorb(text, into: &hops[hops.count - 1])
        }
        return nil
    }

    /// Finalise the trailing in-progress hop after the process exits.
    func finish() -> TracerouteHop? {
        hops.last
    }

    // MARK: - Parsing helpers

    private static func parseHeader(_ line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"traceroute6? to \S+ \(([0-9a-fA-F:.]+)\)"#) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[valueRange])
    }

    /// Matches "<spaces><ttl><spaces><content>" at the start of a hop line.
    private static func splitHop(_ line: String) -> (Int, String)? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)\s+(.+)$"#) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 2,
              let ttlRange = Range(match.range(at: 1), in: line),
              let contentRange = Range(match.range(at: 2), in: line),
              let ttl = Int(line[ttlRange]) else { return nil }
        return (ttl, String(line[contentRange]))
    }

    /// Parse a hop's content into probe results. Handles the variants:
    ///   "*"                                   → timeout
    ///   "name (1.2.3.4)  12.3 ms  11.1 ms"    → named router, several probes
    ///   "1.2.3.4  12.3 ms"                    → unnamed router
    ///   "name (1.2.3.4)  12.3 ms"             → continuation of the same hop
    private static func absorb(_ content: String, into hop: inout TracerouteHop) {
        let tokens = content.split(separator: " ").map(String.init)
        var pendingName: String?
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if token == "*" {
                hop.sent += 1
                hop.timeouts += 1
                index += 1
                continue
            }

            // Parenthesised IP that follows a name: "name (1.2.3.4)".
            if token.hasPrefix("(") && token.hasSuffix(")") {
                let ip = String(token.dropFirst().dropLast())
                if hop.ip == nil { hop.ip = ip }
                if hop.host == nil, let name = pendingName { hop.host = name }
                pendingName = nil
                index += 1
                continue
            }

            // "<number> ms" → a probe round-trip time.
            if index + 1 < tokens.count, tokens[index + 1] == "ms", let rtt = Double(token) {
                hop.sent += 1
                hop.rtts.append(rtt)
                if let name = pendingName {
                    if hop.ip == nil, isIPAddress(name) { hop.ip = name }
                    if hop.host == nil { hop.host = name }
                }
                pendingName = nil
                index += 2
                continue
            }

            // Anything else is an identity token (hostname or bare IP).
            pendingName = token
            index += 1
        }
    }

    private static func isIPAddress(_ value: String) -> Bool {
        value.contains(".") &&
            value.range(of: #"^[0-9a-fA-F:.]+$"#, options: .regularExpression) != nil
    }
}
