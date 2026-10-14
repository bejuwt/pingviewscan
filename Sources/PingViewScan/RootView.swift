import SwiftUI

/// Three-tab shell: continuous ping monitoring, IP-block discovery and subnet math.
struct RootView: View {
    var body: some View {
        TabView {
            MonitorView()
                .tabItem { Label("Ping Monitor", systemImage: "waveform.path.ecg") }

            ScanView()
                .tabItem { Label("Network Scan", systemImage: "dot.radiowaves.left.and.right") }

            SubnetView()
                .tabItem { Label("Subnet Calculator", systemImage: "number.square") }
        }
        .padding(.top, 4)
        .frame(minWidth: 980, minHeight: 640)
    }
}
