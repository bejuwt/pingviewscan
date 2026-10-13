import AppKit
import Foundation

// Headless engine test: `PingViewScan --hosts 10.5.200.1 --duration 10 --report out.html`
if HeadlessTest.runIfRequested(CommandLine.arguments) {
    exit(0)
}

// Headless scan test: `PingViewScan --scan 10.5.200.0/24 --ports 22,80,443`
if HeadlessTest.runScanIfRequested(CommandLine.arguments) {
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
