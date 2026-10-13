import Foundation
import AppKit
import UniformTypeIdentifiers

/// Drives IP-block discovery: an ICMP sweep followed by a TCP port scan of the
/// common services list, then reverse DNS on everything that responded.
final class ScanController: ObservableObject, @unchecked Sendable {

    @Published var targets = ""
    @Published var portsText = PortPreset.all[0].text
    @Published var pingTimeout: Double = 1.0
    @Published var portTimeout: Double = 0.5
    @Published var concurrency: Int = 64
    @Published var showOnlyAlive = false

    @Published private(set) var results: [ScanResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var message = "Enter an IP block (e.g. 10.5.200.0/24) and press Scan."
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var startedAt: Date?
    @Published private(set) var finishedAt: Date?

    private(set) var scanTargets = ""
    private(set) var scanPorts: [UInt16] = []

    private var scanTask: Task<Void, Never>?

    var aliveCount: Int { results.filter(\.isAlive).count }
    var displayedResults: [ScanResult] { showOnlyAlive ? results.filter(\.isAlive) : results }

    func applyPreset(_ preset: PortPreset) { portsText = preset.text }

    // MARK: - Scan control

    func start() {
        guard !isScanning else { return }

        let addresses = IPRange.expand(targets)
        guard !addresses.isEmpty else {
            message = "No valid addresses found in the target field."
            return
        }
        let ports = PortList.parse(portsText)

        results = addresses.map { ScanResult(ip: $0) }
        completed = 0
        total = addresses.count
        isScanning = true
        startedAt = Date()
        finishedAt = nil
        scanTargets = targets
        scanPorts = ports
        message = ports.isEmpty
            ? "Pinging \(addresses.count) addresses…"
            : "Scanning \(addresses.count) addresses × \(ports.count) ports…"

        let pingTimeout = self.pingTimeout
        let portTimeout = self.portTimeout
        let concurrency = self.concurrency

        scanTask = Task.detached { [weak self] in
            guard let self else { return }

            await forEachConcurrent(addresses, maxConcurrent: concurrency) { ip in
                if Task.isCancelled { return }
                let outcome = await PingRunner.pingAsync(host: ip, timeout: pingTimeout)
                self.setPing(ip: ip, ms: outcome.rtt)
            }

            if ports.isEmpty {
                for ip in addresses { self.markScanned(ip: ip) }
            } else {
                await forEachConcurrent(addresses, maxConcurrent: concurrency) { ip in
                    if Task.isCancelled { return }
                    for port in ports {
                        if Task.isCancelled { return }
                        if await PortScanner.tcpConnect(host: ip, port: port, timeout: portTimeout) {
                            self.addPort(ip: ip, port: port)
                        }
                    }
                    self.markScanned(ip: ip)
                }
            }

            let alive = await self.currentAliveIPs()
            await forEachConcurrent(alive, maxConcurrent: 16) { ip in
                if Task.isCancelled { return }
                if let name = await ReverseDNS.lookup(ip) { self.setHostname(ip: ip, name: name) }
            }

            self.finish()
        }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        DispatchQueue.main.async {
            self.isScanning = false
            self.message = "Scan stopped — \(self.aliveCount) host(s) discovered so far."
        }
    }

    func toggle() { isScanning ? stop() : start() }

    func clear() {
        guard !isScanning else { return }
        results = []
        completed = 0
        total = 0
        startedAt = nil
        message = "Cleared."
    }

    // MARK: - Main-thread state updates

    private func setPing(ip: String, ms: Double?) {
        DispatchQueue.main.async {
            guard let index = self.results.firstIndex(where: { $0.ip == ip }) else { return }
            self.results[index].pingMs = ms
        }
    }

    private func addPort(ip: String, port: UInt16) {
        DispatchQueue.main.async {
            guard let index = self.results.firstIndex(where: { $0.ip == ip }) else { return }
            if !self.results[index].openPorts.contains(port) {
                self.results[index].openPorts.append(port)
                self.results[index].openPorts.sort()
            }
        }
    }

    private func setHostname(ip: String, name: String) {
        DispatchQueue.main.async {
            guard let index = self.results.firstIndex(where: { $0.ip == ip }) else { return }
            self.results[index].hostname = name
        }
    }

    private func markScanned(ip: String) {
        DispatchQueue.main.async {
            if let index = self.results.firstIndex(where: { $0.ip == ip }) {
                self.results[index].scanned = true
            }
            self.completed = min(self.total, self.completed + 1)
        }
    }

    private func currentAliveIPs() async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: self.results.filter(\.isAlive).map(\.ip))
            }
        }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.isScanning = false
            self.finishedAt = Date()
            let elapsed = Date().timeIntervalSince(self.startedAt ?? Date())
            self.message = String(format: "Scan complete in %.1fs — %d host(s) discovered of %d.",
                                  elapsed, self.aliveCount, self.results.count)
        }
    }

    // MARK: - Reports

    func makeScanReport() -> ScanReport {
        ScanReport(generated: Date(),
                   targets: scanTargets,
                   started: startedAt,
                   finished: finishedAt,
                   ports: scanPorts,
                   results: results,
                   pingTimeout: pingTimeout,
                   portTimeout: portTimeout,
                   concurrency: concurrency)
    }

    func exportReportHTML() {
        guard !results.isEmpty else { message = "Nothing to report yet."; return }
        let html = ScanReportExporter.html(makeScanReport())

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PingViewScan-Report-\(Self.timestamp()).html"
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

    // MARK: - Export

    func csvString() -> String {
        var lines = ["IP,Hostname,Alive,Ping_ms,Open_Ports"]
        for result in results {
            let ping = result.pingMs.map { String(format: "%.1f", $0) } ?? ""
            let ports = result.openPorts.map(String.init).joined(separator: " ")
            lines.append("\(result.ip),\(csvField(result.hostname ?? "")),\(result.isAlive ? "1" : "0"),\(ping),\(ports)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func exportCSV() {
        guard !results.isEmpty else { message = "Nothing to export."; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "PingViewScan-\(Self.timestamp()).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csvString().write(to: url, atomically: true, encoding: .utf8)
            message = "Saved \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func csvField(_ value: String) -> String {
        value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : value
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
