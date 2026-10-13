import SwiftUI

/// Two-tab shell: continuous ping monitoring and IP-block discovery.
struct RootView: View {
    var body: some View {
        TabView {
            MonitorView()
                .tabItem { Label("Ping Monitor", systemImage: "waveform.path.ecg") }

            ScanView()
                .tabItem { Label("Network Scan", systemImage: "dot.radiowaves.left.and.right") }
        }
        .padding(.top, 4)
        .frame(minWidth: 980, minHeight: 640)
    }
}
