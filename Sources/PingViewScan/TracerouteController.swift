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

    @Published private(set) var hops: [TracerouteHop] = []
    @Published private(set) var isRunning = false
    @Published private(set) var resolvedIP: String?
    @Published private(set) var message = "Enter a host or IP address and press Trace."
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?

    private var task: Task<Void, Never>?

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
        resolvedIP = nil
        tracedTarget = host
        isRunning = true
        startedAt = Date()
        finishedAt = nil
        message = "Tracing route to \(host)…"

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
            DispatchQueue.main.async { self.finish(outcome) }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.finishedAt = Date()
            self.message = "Stopped — \(self.hops.count) hop(s) traced."
        }
    }

    func toggle() { isRunning ? stop() : start() }

    func clear() {
        guard !isRunning else { return }
        hops = []
        resolvedIP = nil
        startedAt = nil
        finishedAt = nil
        message = "Cleared."
    }

    // MARK: - Main-thread state updates

    private func append(_ hop: TracerouteHop) {
        // Replace if the same TTL was already published, otherwise append.
        if let index = hops.firstIndex(where: { $0.ttl == hop.ttl }) {
            hops[index] = hop
        } else {
            hops.append(hop)
        }
        message = "Tracing route to \(tracedTarget)… \(hops.count) hop(s) so far."
    }

    private func finish(_ outcome: TracerouteOutcome) {
        isRunning = false
        finishedAt = Date()
        resolvedIP = outcome.resolvedIP ?? resolvedIP

        let responded = hops.filter { !$0.isTimeout }.count
        let result = outcome.reachedTarget
            ? "target reached"
            : "target not reached within \(maxHops) hops"
        message = "Trace complete — \(hops.count) hop(s), \(responded) responding, \(result)."
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
                         hops: hops)
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
