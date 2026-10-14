import Foundation
import AppKit
import UniformTypeIdentifiers

/// Drives a traceroute and publishes the discovered hops live for the UI.
///
/// UI-facing methods are expected to be called on the main thread; the trace
/// runs on a background executor and publishes results back to main.
final class TracerouteController: ObservableObject, @unchecked Sendable {

    @Published var target = ""
    @Published var maxHops: Int = 30
    @Published var queries: Int = 3
    @Published var timeout: Double = 2

    /// When on, the trace restarts automatically after each pass.
    @Published var continuous = false
    /// Seconds to wait between passes in continuous mode.
    @Published var interval: Double = 5

    @Published private(set) var hops: [TracerouteHop] = []
    @Published private(set) var isRunning = false
    @Published private(set) var resolvedIP: String?
    @Published private(set) var message = "Enter a host or IP address and press Trace."
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?
    /// Number of completed passes (grows in continuous mode).
    @Published private(set) var rounds = 0
    /// Per-hop min/avg/max aggregated across all passes so far.
    @Published private(set) var stats: [HopLatencyStats] = []

    private var task: Task<Void, Never>?
    private var pauseItem: DispatchWorkItem?
    private var statsStore: [Int: HopLatencyStats] = [:]
    private var runToken = UUID()

    private(set) var tracedTarget = ""

    var reachedTarget: Bool {
        guard let resolvedIP else { return false }
        return hops.contains { $0.ip == resolvedIP && !$0.isTimeout }
    }

    // MARK: - Control

    func start() {
        guard !isRunning else { return }
        let host = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !host.hasPrefix("-") else {
            message = "Enter a valid host name or IP address."
            return
        }

        hops = []
        stats = []
        statsStore = [:]
        rounds = 0
        resolvedIP = nil
        tracedTarget = host
        startedAt = Date()
        finishedAt = nil
        runToken = UUID()
        message = "Tracing route to \(host)…"

        launchPass(host: host, token: runToken)
    }

    /// Turn continuous mode on/off. Enabling it starts a session if idle;
    /// disabling it lets an in-flight pass finish, or stops immediately if the
    /// loop is between passes.
    func setContinuous(_ on: Bool) {
        continuous = on
        if on {
            if !isRunning { start() }
        } else if task == nil {
            // We're in the pause between passes — stop right away.
            pauseItem?.cancel()
            pauseItem = nil
            isRunning = false
            finishedAt = Date()
            message = "Continuous tracing stopped after \(rounds) round(s)."
        }
    }

    func stop() {
        runToken = UUID()
        task?.cancel()
        task = nil
        pauseItem?.cancel()
        pauseItem = nil
        continuous = false
        isRunning = false
        finishedAt = Date()
        message = "Stopped — \(rounds) round(s), \(hops.count) hop(s) traced."
    }

    func toggle() { isRunning ? stop() : start() }

    func clear() {
        guard !isRunning else { return }
        hops = []
        stats = []
        statsStore = [:]
        rounds = 0
        resolvedIP = nil
        startedAt = nil
        finishedAt = nil
        message = "Cleared."
    }

    // MARK: - Pass lifecycle

    private func launchPass(host: String, token: UUID) {
        guard token == runToken else { return }
        isRunning = true
        let maxHops = self.maxHops
        let queries = self.queries
        let timeout = self.timeout

        task = Task.detached { [weak self] in
            guard let self else { return }
            let outcome = await TracerouteRunner.traceAsync(
                target: host,
                queries: queries,
                maxHops: maxHops,
                timeout: timeout,
                onHeader: { ip in
                    DispatchQueue.main.async { self.resolvedIP = ip }
                },
                onHop: { hop in
                    DispatchQueue.main.async { self.append(hop) }
                }
            )
            DispatchQueue.main.async { self.completePass(outcome, host: host, token: token) }
        }
    }

    private func completePass(_ outcome: TracerouteOutcome, host: String, token: UUID) {
        guard token == runToken else { return }
        task = nil
        rounds += 1
        resolvedIP = outcome.resolvedIP ?? resolvedIP

        if continuous {
            message = "Round \(rounds) complete — next pass in \(Int(interval))s…"
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.runToken == token else { return }
                self.pauseItem = nil
                if self.continuous {
                    self.hops = []
                    self.message = "Round \(self.rounds + 1) — tracing \(host)…"
                    self.launchPass(host: host, token: token)
                } else {
                    self.isRunning = false
                    self.finishedAt = Date()
                    self.message = "Continuous tracing stopped after \(self.rounds) round(s)."
                }
            }
            pauseItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
        } else {
            isRunning = false
            finishedAt = Date()
            let responded = hops.filter { !$0.isTimeout }.count
            let result = outcome.reachedTarget
                ? "target reached"
                : "target not reached within \(maxHops) hops"
            message = "Trace complete — \(hops.count) hop(s), \(responded) responding, \(result)."
        }
    }

    // MARK: - Main-thread state updates

    private func append(_ hop: TracerouteHop) {
        // Replace if the same TTL was already published, otherwise append.
        if let index = hops.firstIndex(where: { $0.ttl == hop.ttl }) {
            hops[index] = hop
        } else {
            hops.append(hop)
        }

        var aggregate = statsStore[hop.ttl] ?? HopLatencyStats(ttl: hop.ttl)
        aggregate.merge(hop)
        statsStore[hop.ttl] = aggregate
        stats = statsStore.values.sorted { $0.ttl < $1.ttl }

        message = "Tracing route to \(tracedTarget)… \(hops.count) hop(s) so far."
    }

    // MARK: - Reports

    func makeReport() -> TracerouteReport {
        TracerouteReport(target: tracedTarget.isEmpty ? target : tracedTarget,
                         resolvedIP: resolvedIP,
                         generated: Date(),
                         started: startedAt,
                         finished: finishedAt,
                         maxHops: maxHops,
                         queries: queries,
                         timeout: timeout,
                         hops: hops,
                         stats: stats,
                         rounds: max(1, rounds))
    }

    func exportReportHTML() {
        guard !hops.isEmpty else { message = "Nothing to report yet."; return }
        let html = TracerouteReportExporter.html(makeReport())

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PingViewScan-Trace-\(Self.timestamp()).html"
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            message = "Saved \(url.lastPathComponent)"
            NSWorkspace.shared.open(url)
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportCSV() {
        guard !hops.isEmpty else { message = "Nothing to export."; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PingViewScan-Trace-\(Self.timestamp()).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try TracerouteReportExporter.csv(makeReport()).write(to: url, atomically: true, encoding: .utf8)
            message = "Saved \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
