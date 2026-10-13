import Foundation
import AppKit
import UniformTypeIdentifiers

/// Drives the ping loops for every host, accumulates statistics and keeps the
/// full sample history used to build reports.
///
/// UI-facing methods are expected to be called on the main thread; the ping
/// loops run on a background executor and publish their results back to main.
final class PingController: ObservableObject, @unchecked Sendable {

    @Published private(set) var hosts: [Host] = []
    /// Capped, most-recent samples per host used to drive the live charts.
    @Published private(set) var recentSamples: [UUID: [PingSample]] = [:]

    @Published var isRunning = false
    @Published var interval: Double = 1.0
    @Published var timeout: Double = 1.0
    @Published var statusMessage = "Ready. Add a host and press Start."

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var fullHistory: [UUID: [PingSample]] = [:]
    private var sequences: [UUID: Int] = [:]
    private var sessionStart: Date?
    private var sessionEnd: Date?

    private let recentLimit = 300

    // MARK: - Host management

    func addHosts(_ raw: String) {
        let parts = raw
            .split(whereSeparator: { ",;\n\t ".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var added = 0
        for part in parts {
            if hosts.contains(where: { $0.address.caseInsensitiveCompare(part) == .orderedSame }) {
                continue
            }
            hosts.append(Host(address: part))
            added += 1
        }

        if added > 0, isRunning {
            for host in hosts where tasks[host.id] == nil && host.enabled {
                startPinging(host)
            }
        }
        statusMessage = added > 0 ? "Added \(added) host\(added == 1 ? "" : "s")."
                                  : "No new hosts added."
    }

    func removeHosts(ids: Set<UUID>) {
        for id in ids {
            tasks[id]?.cancel()
            tasks[id] = nil
            fullHistory[id] = nil
            recentSamples[id] = nil
            sequences[id] = nil
        }
        hosts.removeAll { ids.contains($0.id) }
        statusMessage = "Removed \(ids.count) host\(ids.count == 1 ? "" : "s")."
    }

    func removeAllHosts() {
        stop()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        hosts.removeAll()
        fullHistory.removeAll()
        recentSamples.removeAll()
        sequences.removeAll()
        sessionStart = nil
        sessionEnd = nil
        statusMessage = "All hosts removed."
    }

    /// Reset counters and history but keep the host list.
    func clearStatistics() {
        for index in hosts.indices { hosts[index].stats.reset() }
        fullHistory.removeAll()
        recentSamples.removeAll()
        sequences.removeAll()
        sessionStart = isRunning ? Date() : nil
        statusMessage = "Statistics cleared."
    }

    // MARK: - Start / stop

    func start() {
        guard !isRunning else { return }
        guard !hosts.isEmpty else {
            statusMessage = "Add at least one host first."
            return
        }
        isRunning = true
        sessionStart = Date()
        sessionEnd = nil
        for host in hosts where host.enabled {
            startPinging(host)
        }
        statusMessage = "Pinging \(hosts.count) host\(hosts.count == 1 ? "" : "s") every \(String(format: "%g", interval))s."
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sessionEnd = Date()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        statusMessage = "Stopped. \(totalSamples) sample\(totalSamples == 1 ? "" : "s") collected."
    }

    func toggle() { isRunning ? stop() : start() }

    var totalSamples: Int { hosts.reduce(0) { $0 + (fullHistory[$1.id]?.count ?? 0) } }

    // MARK: - Ping loop

    private func startPinging(_ host: Host) {
        let id = host.id
        let address = host.address

        tasks[id] = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.interval
                let outcome = await PingRunner.pingAsync(host: address, timeout: self.timeout)
                DispatchQueue.main.async { self.record(hostID: id, outcome: outcome) }

                let nanos = UInt64(max(0.05, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    private func record(hostID: UUID, outcome: PingOutcome) {
        guard let index = hosts.firstIndex(where: { $0.id == hostID }) else { return }

        let sequence = (sequences[hostID] ?? 0) + 1
        sequences[hostID] = sequence

        let sample = PingSample(id: UUID(), sequence: sequence, timestamp: Date(), rtt: outcome.rtt)

        var host = hosts[index]
        if host.ip == nil, let ip = outcome.ip { host.ip = ip }
        host.stats.add(rtt: outcome.rtt)
        hosts[index] = host

        var history = fullHistory[hostID] ?? []
        history.append(sample)
        fullHistory[hostID] = history

        var recent = recentSamples[hostID] ?? []
        recent.append(sample)
        if recent.count > recentLimit { recent.removeFirst(recent.count - recentLimit) }
        recentSamples[hostID] = recent
    }

    // MARK: - Reports

    func makeReport() -> SessionReport {
        let hostReports = hosts.map { host in
            HostReport(address: host.address,
                       ip: host.ip,
                       stats: host.stats,
                       samples: fullHistory[host.id] ?? [])
        }
        return SessionReport(generated: Date(),
                             started: sessionStart,
                             ended: sessionEnd ?? (isRunning ? Date() : nil),
                             interval: interval,
                             timeout: timeout,
                             hosts: hostReports)
    }

    func exportReportHTML() {
        let report = makeReport()
        guard report.hosts.contains(where: { !$0.samples.isEmpty }) else {
            statusMessage = "No session data to export yet."
            return
        }
        let html = ReportExporter.html(report)
        save(data: Data(html.utf8),
             suggestedName: "PingViewScan-Report-\(Self.fileTimestamp()).html",
             contentType: .html,
             openAfterSaving: true)
    }

    func exportCSV() {
        let report = makeReport()
        guard report.hosts.contains(where: { !$0.samples.isEmpty }) else {
            statusMessage = "No session data to export yet."
            return
        }
        let csv = ReportExporter.csv(report)
        save(data: Data(csv.utf8),
             suggestedName: "PingViewScan-\(Self.fileTimestamp()).csv",
             contentType: .commaSeparatedText,
             openAfterSaving: false)
    }

    private func save(data: Data, suggestedName: String, contentType: UTType, openAfterSaving: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [contentType]
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url)
            statusMessage = "Saved \(url.lastPathComponent)"
            if openAfterSaving {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
