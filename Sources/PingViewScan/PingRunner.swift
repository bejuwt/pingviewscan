import Foundation

/// Outcome of a single ping attempt.
struct PingOutcome {
    let rtt: Double?
    let ip: String?
    let output: String

    var success: Bool { rtt != nil }
}

/// Wraps the system `/sbin/ping` binary. One process is spawned per probe so
/// behaviour matches the classic PingViewScan (one echo request per interval).
enum PingRunner {

    /// Blocking ping. Always call from a background thread / async context.
    static func ping(host: String, timeout: Double) -> PingOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")

        // macOS ping uses milliseconds for -W (time to wait for a reply).
        let waitMs = max(100, Int((timeout * 1000).rounded()))
        process.arguments = ["-c", "1", "-n", "-W", "\(waitMs)", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return PingOutcome(rtt: nil, ip: nil,
                               output: "Failed to launch ping: \(error.localizedDescription)")
        }

        // Watchdog: kill the process if DNS resolution or the probe hangs.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility)
            .asyncAfter(deadline: .now() + timeout + 4.0, execute: watchdog)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        let output = String(data: data, encoding: .utf8) ?? ""
        return PingOutcome(rtt: parseRTT(output), ip: parseIP(output, host: host), output: output)
    }

    /// Async wrapper that runs the blocking ping off the caller's executor.
    static func pingAsync(host: String, timeout: Double) async -> PingOutcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: ping(host: host, timeout: timeout))
            }
        }
    }

    // MARK: - Parsing

    private static let rttPatterns = [
        #"time=([0-9]+(?:\.[0-9]+)?)\s*ms"#,
        #"time<([0-9]+(?:\.[0-9]+)?)\s*ms"#
    ]

    static func parseRTT(_ output: String) -> Double? {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        for pattern in rttPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            if let match = regex.firstMatch(in: output, range: range),
               match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: output),
               let value = Double(output[valueRange]) {
                return value
            }
        }
        return nil
    }

    static func parseIP(_ output: String, host: String) -> String? {
        // e.g. "PING example.com (93.184.216.34): 56 data bytes"
        if let regex = try? NSRegularExpression(pattern: #"PING\s+.*?\(([0-9a-fA-F:.]+)\)"#) {
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            if let match = regex.firstMatch(in: output, range: range),
               match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: output) {
                return String(output[valueRange])
            }
        }
        // The user may have typed a literal IP address.
        if host.range(of: #"^[0-9a-fA-F:.]+$"#, options: .regularExpression) != nil {
            return host
        }
        return nil
    }
}
