import Foundation

public enum SubnetScanner {
    /// Discovers LG webOS TVs on the local /24 subnet by probing TCP ports 3001 (wss) and 3000 (ws).
    /// Requires no multicast entitlement (`com.apple.developer.networking.multicast`).
    public static func scanForTVs(
        hintHost: String? = nil,
        timeoutMs: Int32 = 350
    ) async -> [String] {
        let prefixes = candidateSubnetPrefixes(hintHost: hintHost)
        var discovered: [String] = []

        for prefix in prefixes {
            let foundInSubnet = await scanSubnet(prefix: prefix, timeoutMs: timeoutMs)
            for ip in foundInSubnet where !discovered.contains(ip) {
                discovered.append(ip)
            }
            if !discovered.isEmpty {
                break
            }
        }
        return discovered
    }

    private static func scanSubnet(prefix: String, timeoutMs: Int32) async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for hostOctet in 2...254 {
                let ip = "\(prefix).\(hostOctet)"
                group.addTask {
                    if probeTCP(host: ip, port: 3001, timeoutMs: timeoutMs)
                        || probeTCP(host: ip, port: 3000, timeoutMs: timeoutMs) {
                        return ip
                    }
                    return nil
                }
            }

            var matches: [String] = []
            for await result in group {
                if let ip = result {
                    matches.append(ip)
                }
            }
            return matches.sorted()
        }
    }

    public static func candidateSubnetPrefixes(hintHost: String?) -> [String] {
        var prefixes: [String] = []

        if let hintHost {
            let parts = hintHost.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
            if parts.count == 4 {
                let prefix = parts[0..<3].joined(separator: ".")
                prefixes.append(prefix)
            }
        }

        for ip in localIPv4Addresses() {
            let parts = ip.split(separator: ".")
            if parts.count == 4 {
                let prefix = parts[0..<3].joined(separator: ".")
                if !prefixes.contains(prefix) {
                    prefixes.append(prefix)
                }
            }
        }

        if prefixes.isEmpty {
            prefixes = ["192.168.1", "192.168.0", "192.168.100", "10.0.0"]
        }
        return prefixes
    }

    private static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return addresses
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let interface = current.pointee
            if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("bridge") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        addr,
                        socklen_t(addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: hostname)
                        if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                            addresses.append(ip)
                        }
                    }
                }
            }
            ptr = interface.ifa_next
        }
        return addresses
    }

    public static func probeTCP(host: String, port: UInt16, timeoutMs: Int32) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if res == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollRes = poll(&pfd, 1, timeoutMs)
        guard pollRes > 0 else { return false }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &soError, &len)
        return soError == 0
    }
}
