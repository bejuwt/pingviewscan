import Foundation

/// Command-line mode used to exercise the real ping engine without the GUI.
///
///   PingViewScan --hosts 10.5.200.1 --interval 1 --timeout 1 --duration 10 \
///                [--report /tmp/out.html] [--csv /tmp/out.csv]
///
/// It uses the same `PingController` and exporters as the app, so it validates
/// the probing loop, statistics, graphs and CSV output end to end.
enum HeadlessTest {

    static func runIfRequested(_ argv: [String]) -> Bool {
        guard let hostsIndex = argv.firstIndex(of: "--hosts"), hostsIndex + 1 < argv.count else {
            return false
        }

        func value(_ flag: String) -> String? {
            guard let index = argv.firstIndex(of: flag), index + 1 < argv.count else { return nil }
            return argv[index + 1]
        }

        let hosts = argv[hostsIndex + 1]
            .split(whereSeparator: { ",; ".contains($0) })
            .map(String.init)
        let interval = value("--interval").flatMap(Double.init) ?? 1.0
        let timeout = value("--timeout").flatMap(Double.init) ?? 1.0
        let duration = value("--duration").flatMap(Double.init) ?? 10.0
        let reportPath = value("--report")
        let csvPath = value("--csv")

        run(hosts: hosts, interval: interval, timeout: timeout,
            duration: duration, reportPath: reportPath, csvPath: csvPath)
        return true
    }

    private static func run(hosts: [String], interval: Double, timeout: Double,
                            duration: Double, reportPath: String?, csvPath: String?) {
        let controller = PingController()
        controller.interval = interval
        controller.timeout = timeout
        controller.addHosts(hosts.joined(separator: ","))

        print("PingViewScan headless test")
        print("  hosts:    \(hosts.joined(separator: ", "))")
        print("  interval: \(interval)s   timeout: \(timeout)s   duration: \(duration)s")
        print("")

        controller.start()

        // Keep the main run loop alive so the controller's main-queue updates run.
        let keepAlive = Timer(timeInterval: 0.05, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .common)

        let deadline = Date().addingTimeInterval(duration)
        var seen: [String: Int] = [:]

        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            for host in controller.makeReport().hosts {
                let count = host.samples.count
                if count != (seen[host.address] ?? 0) {
                    seen[host.address] = count
                    if let last = host.samples.last {
                        let rtt = last.rtt.map { String(format: "%6.1f ms", $0) } ?? "   LOST  "
                        print(String(format: "[%8.3fs] %@  seq=%-4d %@",
                                     Date().timeIntervalSince(deadline - duration),
                                     host.address, last.sequence, rtt))
                    }
                }
            }
        }

        controller.stop()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        keepAlive.invalidate()

        let report = controller.makeReport()
        print("")
        print(row(["Host", "Sent", "Recv", "Lost", "Loss%", "Last", "Min", "Avg", "Max"]))
        print(String(repeating: "-", count: 83))
        for host in report.hosts {
            let s = host.stats
            print(row([
                host.address,
                "\(s.sent)", "\(s.received)", "\(s.lost)",
                String(format: "%.1f", s.lossPercent),
                ms(s.last), ms(s.minRtt), ms(s.avgRtt), ms(s.maxRtt)
            ]))
        }

        print("History samples retained: \(controller.totalSamples)")

        if let reportPath {
            let html = ReportExporter.html(report)
            do {
                try html.write(toFile: reportPath, atomically: true, encoding: .utf8)
                print("\nHTML report written: \(reportPath) (\(html.count) bytes)")
            } catch {
                print("\nFailed to write report: \(error.localizedDescription)")
            }
        }

        if let csvPath {
            do {
                try ReportExporter.csv(report).write(toFile: csvPath, atomically: true, encoding: .utf8)
                print("CSV written:         \(csvPath)")
            } catch {
                print("Failed to write CSV: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Scan mode

    static func runScanIfRequested(_ argv: [String]) -> Bool {
        guard let scanIndex = argv.firstIndex(of: "--scan"), scanIndex + 1 < argv.count else {
            return false
        }

        func value(_ flag: String) -> String? {
            guard let index = argv.firstIndex(of: flag), index + 1 < argv.count else { return nil }
            return argv[index + 1]
        }

        runScan(target: argv[scanIndex + 1],
                ports: value("--ports"),
                pingTimeout: value("--ping-timeout").flatMap(Double.init) ?? 1.0,
                portTimeout: value("--port-timeout").flatMap(Double.init) ?? 0.5,
                concurrency: value("--concurrency").flatMap(Int.init) ?? 64,
                reportPath: value("--report"),
                csvPath: value("--csv"))
        return true
    }

    private static func runScan(target: String, ports: String?, pingTimeout: Double,
                                portTimeout: Double, concurrency: Int,
                                reportPath: String?, csvPath: String?) {
        let controller = ScanController()
        controller.targets = target
        if let ports { controller.portsText = ports }
        controller.pingTimeout = pingTimeout
        controller.portTimeout = portTimeout
        controller.concurrency = concurrency

        print("PingViewScan headless scan")
        print("  targets:     \(target)")
        print("  ports:       \(controller.portsText.isEmpty ? "(ping only)" : controller.portsText)")
        print("  concurrency: \(concurrency)")
        print("")

        controller.start()

        let keepAlive = Timer(timeInterval: 0.05, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .common)

        var lastReported = 0
        while controller.isScanning {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            if controller.completed != lastReported {
                lastReported = controller.completed
                print(String(format: "  scanned %d/%d …", controller.completed, controller.total))
            }
        }
        keepAlive.invalidate()

        print("")
        print(scanRow(["IP", "Hostname", "Ping", "Open ports"]))
        print(String(repeating: "-", count: 72))
        for result in controller.results where result.isAlive {
            let ping = result.pingMs.map { String(format: "%.1f", $0) } ?? "-"
            let open = result.openPorts.map(String.init).joined(separator: ",")
            print(scanRow([result.ip, result.hostname ?? "-", ping, open]))
        }
        print("")
        print(controller.message)

        if let reportPath {
            let html = ScanReportExporter.html(controller.makeScanReport())
            do {
                try html.write(toFile: reportPath, atomically: true, encoding: .utf8)
                print("HTML report written: \(reportPath) (\(html.count) bytes)")
            } catch {
                print("Failed to write report: \(error.localizedDescription)")
            }
        }

        if let csvPath {
            do {
                try controller.csvString().write(toFile: csvPath, atomically: true, encoding: .utf8)
                print("CSV written: \(csvPath)")
            } catch {
                print("Failed to write CSV: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Traceroute mode

    static func runTraceIfRequested(_ argv: [String]) -> Bool {
        guard let index = argv.firstIndex(of: "--trace"), index + 1 < argv.count else {
            return false
        }

        func value(_ flag: String) -> String? {
            guard let i = argv.firstIndex(of: flag), i + 1 < argv.count else { return nil }
            return argv[i + 1]
        }

        runTrace(target: argv[index + 1],
                 maxHops: value("--max-hops").flatMap(Int.init) ?? 30,
                 queries: value("--queries").flatMap(Int.init) ?? 3,
                 timeout: value("--trace-timeout").flatMap(Double.init) ?? 2,
                 rounds: value("--rounds").flatMap(Int.init) ?? 1,
                 interval: value("--interval").flatMap(Double.init) ?? 2,
                 reportPath: value("--report"),
                 csvPath: value("--csv"))
        return true
    }

    private static func runTrace(target: String, maxHops: Int, queries: Int,
                                 timeout: Double, rounds: Int, interval: Double,
                                 reportPath: String?, csvPath: String?) {
        let controller = TracerouteController()
        controller.target = target
        controller.maxHops = maxHops
        controller.queries = queries
        controller.timeout = timeout
        controller.interval = interval

        print("PingViewScan headless traceroute")
        print("  target:  \(target)")
        print("  max:     \(maxHops) hops   probes: \(queries)   timeout: \(timeout)s")
        if rounds > 1 { print("  mode:    continuous, \(rounds) rounds (every \(interval)s)") }
        print("")

        if rounds > 1 {
            controller.setContinuous(true)
        } else {
            controller.start()
        }

        let keepAlive = Timer(timeInterval: 0.05, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .common)

        let targetRounds = max(1, rounds)
        var lastRounds = 0
        while controller.isRunning && controller.rounds < targetRounds {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            if controller.rounds != lastRounds {
                lastRounds = controller.rounds
                let responded = controller.hops.filter { !$0.isTimeout }.count
                print("  round \(lastRounds): \(controller.hops.count) hop(s), \(responded) responding")
            }
        }
        if controller.isRunning { controller.stop() }
        keepAlive.invalidate()

        print("")
        print("Aggregated per-hop latency (\(controller.rounds) pass(es)):")
        let widths = [3, 38, 5, 5, 6, 8, 8, 8, 8]
        func line(_ cells: [String]) -> String {
            var out = ""
            for (index, cell) in cells.enumerated() {
                let width = index < widths.count ? widths[index] : 8
                out += index == 0 ? pad(cell, width) : " " + pad(cell, width, right: index >= 2)
            }
            return out
        }
        print(line(["#", "Host", "Sent", "Recv", "Loss%", "Min", "Avg", "Max", "Last"]))
        print(String(repeating: "-", count: 2 + widths.reduce(0, +) + widths.count))
        for stat in controller.stats {
            let raw = stat.displayHost
            let host = raw.count > 38 ? String(raw.prefix(37)) + "\u{2026}" : raw
            print(line(["\(stat.ttl)", host, "\(stat.sent)", "\(stat.received)",
                        String(format: "%.1f", stat.lossPercent),
                        ms(stat.minRtt), ms(stat.avgRtt), ms(stat.maxRtt), ms(stat.lastRtt)]))
        }
        print("")
        print(controller.message)

        let report = controller.makeReport()
        if let reportPath {
            do {
                try TracerouteReportExporter.html(report).write(toFile: reportPath, atomically: true, encoding: .utf8)
                print("HTML report written: \(reportPath)")
            } catch {
                print("Failed to write report: \(error.localizedDescription)")
            }
        }
        if let csvPath {
            do {
                try TracerouteReportExporter.csv(report).write(toFile: csvPath, atomically: true, encoding: .utf8)
                print("CSV written: \(csvPath)")
            } catch {
                print("Failed to write CSV: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Formatting

    private static func scanRow(_ cells: [String]) -> String {
        let widths = [16, 26, 9, 40]
        var out = ""
        for (index, cell) in cells.enumerated() {
            let width = index < widths.count ? widths[index] : 20
            out += index == 0 ? pad(cell, width) : pad(cell, width, right: index == 2) + " "
        }
        return out
    }

    private static func ms(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "-"
    }

    private static func row(_ cells: [String]) -> String {
        let widths = [28, 6, 6, 6, 7, 8, 8, 8, 8]
        var out = ""
        for (index, cell) in cells.enumerated() {
            let width = index < widths.count ? widths[index] : 8
            out += index == 0 ? pad(cell, width) : pad(cell, width, right: true) + " "
        }
        return out
    }

    private static func pad(_ string: String, _ width: Int, right: Bool = false) -> String {
        guard string.count < width else { return string }
        let spaces = String(repeating: " ", count: width - string.count)
        return right ? spaces + string : string + spaces
    }
}
