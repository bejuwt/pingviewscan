import SwiftUI

/// Four-tab shell: ping monitoring, IP-block discovery, subnet math and traceroute.
struct RootView: View {
    var body: some View {
        TabView {
            MonitorView()
                .tabItem { Label("Ping Monitor", systemImage: "waveform.path.ecg") }

            ScanView()
                .tabItem { Label("Network Scan", systemImage: "dot.radiowaves.left.and.right") }

            SubnetView()
                .tabItem { Label("Subnet Calculator", systemImage: "number.square") }

            TracerouteView()
                .tabItem { Label("Traceroute", systemImage: "point.3.connected.trianglepath.dotted") }
        }
        .padding(.top, 4)
        .frame(minWidth: 980, minHeight: 640)
    }
}
