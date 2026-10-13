import Foundation
import Network

/// TCP connect helpers used by the network scanner to detect live services.
enum PortScanner {

    private static let queue = DispatchQueue(label: "pingviewscan.portscan", attributes: .concurrent)

    /// Attempts a TCP connection. Returns `true` only if the port accepted a
    /// connection before the timeout / before the peer refused it.
    static func tcpConnect(host: String, port: UInt16, timeout: Double) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let probe = TCPProbe(connection: connection, continuation: continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    probe.finish(true)
                case .failed, .cancelled, .waiting:
                    probe.finish(false)
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + max(0.05, timeout)) { probe.finish(false) }
        }
    }

    /// Resolves the single continuation exactly once, from either the state
    /// handler or the timeout watchdog.
    private final class TCPProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private let connection: NWConnection
        private let continuation: CheckedContinuation<Bool, Never>

        init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
            self.connection = connection
            self.continuation = continuation
        }

        func finish(_ result: Bool) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            lock.unlock()
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(returning: result)
        }
    }
}

/// Reverse DNS lookup for discovered hosts.
enum ReverseDNS {
    static func lookup(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_addr.s_addr = inet_addr(ip)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                let result = withUnsafePointer(to: &addr) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        getnameinfo(sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                    }
                }

                if result == 0 {
                    continuation.resume(returning: String(cString: host))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Runs an async operation over every item while keeping at most
/// `maxConcurrent` operations in flight.
func forEachConcurrent<T: Sendable>(_ items: [T],
                                    maxConcurrent: Int,
                                    _ operation: @escaping @Sendable (T) async -> Void) async {
    guard !items.isEmpty else { return }
    let limit = max(1, min(maxConcurrent, items.count))

    await withTaskGroup(of: Void.self) { group in
        var next = 0
        for _ in 0..<limit {
            let item = items[next]; next += 1
            group.addTask { await operation(item) }
        }
        while await group.next() != nil {
            if next < items.count {
                let item = items[next]; next += 1
                group.addTask { await operation(item) }
            }
        }
    }
}
