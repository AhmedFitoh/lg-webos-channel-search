import Foundation

public enum WakeOnLANError: Error, LocalizedError, Sendable {
    case invalidMACAddress(String)
    case socketFailure(Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidMACAddress(let mac):
            return "Invalid MAC address format: \(mac). Expected 6 hex pairs (e.g. AA:BB:CC:DD:EE:FF)."
        case .socketFailure(let err):
            return "Failed to send Wake-on-LAN packet (errno \(err))."
        }
    }
}

public enum WakeOnLAN {
    /// Builds the 102-byte Wake-on-LAN magic packet (`6x 0xFF` followed by `16x MAC`).
    public static func buildMagicPacket(macAddress: String) throws -> Data {
        let cleaned = macAddress
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count == 12 else {
            throw WakeOnLANError.invalidMACAddress(macAddress)
        }

        var macBytes: [UInt8] = []
        macBytes.reserveCapacity(6)
        var index = cleaned.startIndex
        for _ in 0..<6 {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let pair = cleaned[index..<nextIndex]
            guard let byte = UInt8(pair, radix: 16) else {
                throw WakeOnLANError.invalidMACAddress(macAddress)
            }
            macBytes.append(byte)
            index = nextIndex
        }

        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }

    /// Sends the Wake-on-LAN magic packet via UDP broadcast to port 9 (and optionally a directed subnet broadcast).
    public static func send(
        macAddress: String,
        broadcastAddress: String = "255.255.255.255",
        port: UInt16 = 9
    ) throws {
        let packet = try buildMagicPacket(macAddress: macAddress)

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else {
            throw WakeOnLANError.socketFailure(errno)
        }
        defer { close(sock) }

        var broadcastEnable: Int32 = 1
        _ = setsockopt(
            sock,
            SOL_SOCKET,
            SO_BROADCAST,
            &broadcastEnable,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, broadcastAddress, &addr.sin_addr) == 1 else {
            throw WakeOnLANError.socketFailure(EINVAL)
        }

        let sent = packet.withUnsafeBytes { rawBuf -> Int in
            guard let base = rawBuf.baseAddress else { return -1 }
            return withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(sock, base, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else {
            throw WakeOnLANError.socketFailure(errno)
        }
    }
}
