import Foundation

public enum TVClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidHost(String)
    case localNetworkPermissionDenied
    case connectionFailed(String)
    case pairingRejected(String)
    case notConnected
    case requestTimedOut(String)
    case ssapError(uri: String, message: String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            return "Invalid TV IP address: \(host)"
        case .localNetworkPermissionDenied:
            return "Local Network access is denied. Please allow Local Network access in iOS Settings."
        case .connectionFailed(let reason):
            return "Could not connect to the TV (\(reason)). Check that the TV is on and on the same Wi-Fi network."
        case .pairingRejected(let reason):
            return "Pairing was rejected by the TV (\(reason))."
        case .notConnected:
            return "Not connected to the TV."
        case .requestTimedOut(let uri):
            return "Request to TV timed out (\(uri))."
        case .ssapError(let uri, let message):
            return "TV returned an error for \(uri): \(message)"
        case .decodingFailed(let detail):
            return "Failed to decode TV response: \(detail)"
        }
    }

    public var isLocalNetworkDenied: Bool {
        if case .localNetworkPermissionDenied = self { return true }
        return false
    }
}

public enum TVConnectionState: Equatable, Sendable {
    case disconnected
    case connecting(host: String)
    case awaitingApproval(host: String)
    case ready(host: String)
    case failed(TVClientError)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var connectedHost: String? {
        switch self {
        case .connecting(let host), .awaitingApproval(let host), .ready(let host):
            return host
        case .disconnected, .failed:
            return nil
        }
    }

    public var statusText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting(let host):
            return "Connecting to \(host)…"
        case .awaitingApproval(let host):
            return "Check your TV (\(host)) and accept the pairing prompt…"
        case .ready(let host):
            return "Connected to \(host)"
        case .failed(let error):
            return error.localizedDescription
        }
    }
}
