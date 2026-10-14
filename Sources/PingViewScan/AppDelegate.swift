import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let controller = PingController()
    private let scanController = ScanController()
    private let tracerouteController = TracerouteController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()

        let root = RootView()
            .environmentObject(controller)
            .environmentObject(scanController)
            .environmentObject(tracerouteController)

        let hosting = NSHostingView(rootView: root)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PingViewScan"
        window.contentView = hosting
        window.setFrameAutosaveName("MainWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Actions

    @objc private func togglePinging() { controller.toggle() }
    @objc private func exportReport() { controller.exportReportHTML() }
    @objc private func exportCSV() { controller.exportCSV() }
    @objc private func toggleScan() { scanController.toggle() }
    @objc private func exportScanReport() { scanController.exportReportHTML() }
    @objc private func exportScanCSV() { scanController.exportCSV() }
    @objc private func toggleTraceroute() { tracerouteController.toggle() }
    @objc private func exportTracerouteReport() { tracerouteController.exportReportHTML() }
    @objc private func exportTracerouteCSV() { tracerouteController.exportCSV() }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About PingViewScan",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PingViewScan",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit PingViewScan",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Export Report…",
                         action: #selector(exportReport), keyEquivalent: "e").target = self
        fileMenu.addItem(withTitle: "Export CSV…",
                         action: #selector(exportCSV), keyEquivalent: "").target = self
        fileItem.submenu = fileMenu

        let sessionItem = NSMenuItem()
        mainMenu.addItem(sessionItem)
        let sessionMenu = NSMenu(title: "Session")
        sessionMenu.addItem(withTitle: "Start / Stop",
                            action: #selector(togglePinging), keyEquivalent: "r").target = self
        sessionItem.submenu = sessionMenu

        let scanItem = NSMenuItem()
        mainMenu.addItem(scanItem)
        let scanMenu = NSMenu(title: "Scan")
        scanMenu.addItem(withTitle: "Start / Stop Scan",
                         action: #selector(toggleScan), keyEquivalent: "").target = self
        scanMenu.addItem(withTitle: "Export Scan Report…",
                         action: #selector(exportScanReport), keyEquivalent: "").target = self
        scanMenu.addItem(withTitle: "Export Scan CSV…",
                         action: #selector(exportScanCSV), keyEquivalent: "").target = self
        scanItem.submenu = scanMenu

        let traceItem = NSMenuItem()
        mainMenu.addItem(traceItem)
        let traceMenu = NSMenu(title: "Traceroute")
        traceMenu.addItem(withTitle: "Start / Stop Trace",
                          action: #selector(toggleTraceroute), keyEquivalent: "").target = self
        traceMenu.addItem(withTitle: "Export Trace Report…",
                          action: #selector(exportTracerouteReport), keyEquivalent: "").target = self
        traceMenu.addItem(withTitle: "Export Trace CSV…",
                          action: #selector(exportTracerouteCSV), keyEquivalent: "").target = self
        traceItem.submenu = traceMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}
