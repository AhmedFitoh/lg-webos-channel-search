import Foundation

public protocol TVClientProtocol: Sendable {
    var state: TVConnectionState { get async }
    var stateStream: AsyncStream<TVConnectionState> { get async }

    func connect(host: String, forcePairing: Bool) async throws
    func disconnect() async
    func fetchChannelList() async throws -> [SSAPChannelDTO]
    func fetchCurrentChannel() async throws -> SSAPCurrentChannelPayload
    func openChannel(channelId: String, fallbackChannelNumber: String?) async throws
    func channelUp() async throws
    func channelDown() async throws
    func fetchExternalInputs() async throws -> [SSAPExternalInputDTO]
    func switchInput(inputId: String) async throws
    func setMute(_ muted: Bool) async throws
    func volumeUp() async throws
    func volumeDown() async throws
    func sendRemoteButton(_ button: TVRemoteButton) async throws
    func turnOff() async throws
}

public actor TVClient: TVClientProtocol {
    public static let maxFrameBytes = 32 * 1024 * 1024 // 32 MB for satellite channel lists

    private let credentialsStore: CredentialsStoring
    private let pingIntervalNanoseconds: UInt64
    private let requestTimeoutNanoseconds: UInt64

    public private(set) var state: TVConnectionState = .disconnected {
        didSet {
            guard state != oldValue else { return }
            broadcastState(state)
        }
    }

    private var stateContinuations: [UUID: AsyncStream<TVConnectionState>.Continuation] = [:]
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var pointerSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private var currentHost: String?
    private var shouldAutoReconnect: Bool = false
    private var reconnectAttempt: Int = 0
    private var nextRequestNumber: Int = 1

    private var pendingRequests: [String: CheckedContinuation<Data, Error>] = [:]
    private var pendingRegistration: CheckedContinuation<String, Error>?

    public init(
        credentialsStore: CredentialsStoring = KeychainStore.shared,
        pingIntervalSeconds: TimeInterval = 20,
        requestTimeoutSeconds: TimeInterval = 20
    ) {
        self.credentialsStore = credentialsStore
        self.pingIntervalNanoseconds = UInt64(pingIntervalSeconds * 1_000_000_000)
        self.requestTimeoutNanoseconds = UInt64(requestTimeoutSeconds * 1_000_000_000)
    }

    public var stateStream: AsyncStream<TVConnectionState> {
        let id = UUID()
        let currentState = self.state
        return AsyncStream { continuation in
            continuation.yield(currentState)
            self.addStateContinuation(id: id, continuation: continuation)
            continuation.onTermination = { _ in
                Task { await self.removeStateContinuation(id: id) }
            }
        }
    }

    private func addStateContinuation(id: UUID, continuation: AsyncStream<TVConnectionState>.Continuation) {
        stateContinuations[id] = continuation
    }

    private func removeStateContinuation(id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }

    private func broadcastState(_ newState: TVConnectionState) {
        for continuation in stateContinuations.values {
            continuation.yield(newState)
        }
    }

    // MARK: - Connection Lifecycle

    public func connect(host: String, forcePairing: Bool = false) async throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidHost(trimmedHost) else {
            let err = TVClientError.invalidHost(trimmedHost)
            state = .failed(err)
            throw err
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        tearDownSocket(cancelAutoReconnect: false)

        currentHost = trimmedHost
        shouldAutoReconnect = true
        state = .connecting(host: trimmedHost)

        let endpoints: [(scheme: String, port: Int)] = [
            ("ws", 3000),
            ("wss", 3001)
        ]

        var lastConnectError: Error?
        var connectedTask: URLSessionWebSocketTask?
        var connectedSession: URLSession?

        for endpoint in endpoints {
            guard let url = URL(string: "\(endpoint.scheme)://\(trimmedHost):\(endpoint.port)") else {
                continue
            }
            let delegate = TrustDelegate(allowedHost: trimmedHost)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.waitsForConnectivity = false

            let candidateSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let candidateTask = candidateSession.webSocketTask(with: url)
            candidateTask.maximumMessageSize = Self.maxFrameBytes
            candidateTask.resume()

            do {
                try await sendOneShotPing(on: candidateTask, timeoutNanoseconds: 1_500_000_000)
                connectedSession = candidateSession
                connectedTask = candidateTask
                debugLog("WebSocket connected via \(url.absoluteString)")
                break
            } catch {
                lastConnectError = error
                candidateTask.cancel(with: .goingAway, reason: nil)
                candidateSession.invalidateAndCancel()
                debugLog("Endpoint \(url.absoluteString) failed: \(error.localizedDescription)")
            }
        }

        guard let activeTask = connectedTask, let activeSession = connectedSession else {
            let mappedError = Self.mapTransportError(lastConnectError)
            state = .failed(mappedError)
            throw mappedError
        }

        self.session = activeSession
        self.webSocketTask = activeTask

        startReceiveLoop(for: activeTask)

        do {
            let savedKey = forcePairing ? nil : credentialsStore.loadClientKey(forHost: trimmedHost)
            let clientKey = try await performRegistration(
                host: trimmedHost,
                savedKey: savedKey,
                forcePairing: forcePairing
            )
            try? credentialsStore.saveClientKey(clientKey, forHost: trimmedHost)
            credentialsStore.saveLastHost(trimmedHost)
            reconnectAttempt = 0
            state = .ready(host: trimmedHost)
            startPingLoop()
        } catch let error as TVClientError {
            tearDownSocket(cancelAutoReconnect: true)
            state = .failed(error)
            throw error
        } catch {
            tearDownSocket(cancelAutoReconnect: true)
            let mapped = Self.mapTransportError(error)
            state = .failed(mapped)
            throw mapped
        }
    }

    public func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        tearDownSocket(cancelAutoReconnect: true)
        state = .disconnected
    }

    private func tearDownSocket(cancelAutoReconnect: Bool) {
        if cancelAutoReconnect {
            shouldAutoReconnect = false
        }
        pingTask?.cancel()
        pingTask = nil
        receiveLoopTask?.cancel()
        receiveLoopTask = nil

        pointerSocketTask?.cancel(with: .normalClosure, reason: nil)
        pointerSocketTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil

        if let regCont = pendingRegistration {
            pendingRegistration = nil
            regCont.resume(throwing: TVClientError.notConnected)
        }
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: TVClientError.notConnected)
        }
    }

    // MARK: - Registration

    private func performRegistration(
        host: String,
        savedKey: String?,
        forcePairing: Bool
    ) async throws -> String {
        let frame = SSAPRegisterFrame(
            id: "register_0",
            clientKey: forcePairing ? nil : savedKey
        )
        if savedKey == nil || forcePairing {
            state = .awaitingApproval(host: host)
        }

        let encoded = try JSONEncoder().encode(frame)
        guard let text = String(data: encoded, encoding: .utf8) else {
            throw TVClientError.decodingFailed("Failed to encode register frame")
        }
        try await sendRawFrame(text)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.pendingRegistration = continuation
        }
    }

    // MARK: - High-Level SSAP Operations

    public func fetchChannelList() async throws -> [SSAPChannelDTO] {
        let data = try await sendRequest(uri: SSAPURI.getChannelList, payload: Optional<SSAPEmptyPayload>.none)
        do {
            let decoded = try JSONDecoder().decode(SSAPResponse<SSAPChannelListPayload>.self, from: data)
            return decoded.payload?.channelList ?? []
        } catch {
            throw TVClientError.decodingFailed(error.localizedDescription)
        }
    }

    public func fetchCurrentChannel() async throws -> SSAPCurrentChannelPayload {
        let data = try await sendRequest(uri: SSAPURI.getCurrentChannel, payload: Optional<SSAPEmptyPayload>.none)
        do {
            let decoded = try JSONDecoder().decode(SSAPResponse<SSAPCurrentChannelPayload>.self, from: data)
            guard let payload = decoded.payload else {
                throw TVClientError.decodingFailed("Missing payload in getCurrentChannel response")
            }
            return payload
        } catch let err as TVClientError {
            throw err
        } catch {
            throw TVClientError.decodingFailed(error.localizedDescription)
        }
    }

    public func openChannel(channelId: String, fallbackChannelNumber: String? = nil) async throws {
        do {
            let payload = SSAPOpenChannelPayload(channelId: channelId, channelNumber: nil)
            _ = try await sendRequest(uri: SSAPURI.openChannel, payload: payload)
        } catch {
            guard let fallbackChannelNumber, !fallbackChannelNumber.isEmpty else {
                throw error
            }
            let fallbackPayload = SSAPOpenChannelPayload(channelId: nil, channelNumber: fallbackChannelNumber)
            _ = try await sendRequest(uri: SSAPURI.openChannel, payload: fallbackPayload)
        }
    }

    public func channelUp() async throws {
        _ = try await sendRequest(uri: SSAPURI.channelUp, payload: Optional<SSAPEmptyPayload>.none)
    }

    public func channelDown() async throws {
        _ = try await sendRequest(uri: SSAPURI.channelDown, payload: Optional<SSAPEmptyPayload>.none)
    }

    public func fetchExternalInputs() async throws -> [SSAPExternalInputDTO] {
        let data = try await sendRequest(uri: SSAPURI.getExternalInputList, payload: Optional<SSAPEmptyPayload>.none)
        let decoded = try JSONDecoder().decode(SSAPResponse<SSAPExternalInputListPayload>.self, from: data)
        return decoded.payload?.devices ?? []
    }

    public func switchInput(inputId: String) async throws {
        struct SwitchInputPayload: Encodable, Sendable { let inputId: String }
        _ = try await sendRequest(uri: SSAPURI.switchInput, payload: SwitchInputPayload(inputId: inputId))
    }

    public func setMute(_ muted: Bool) async throws {
        struct MutePayload: Encodable, Sendable { let mute: Bool }
        _ = try await sendRequest(uri: SSAPURI.setMute, payload: MutePayload(mute: muted))
    }

    public func volumeUp() async throws {
        _ = try await sendRequest(uri: SSAPURI.volumeUp, payload: Optional<SSAPEmptyPayload>.none)
    }

    public func volumeDown() async throws {
        _ = try await sendRequest(uri: SSAPURI.volumeDown, payload: Optional<SSAPEmptyPayload>.none)
    }

    public func sendRemoteButton(_ button: TVRemoteButton) async throws {
        let task = try await ensurePointerSocketTask()
        let frame = "type:button\nname:\(button.rawValue)\n\n"
        do {
            try await task.send(.string(frame))
        } catch {
            pointerSocketTask?.cancel(with: .goingAway, reason: nil)
            pointerSocketTask = nil
            let retryTask = try await ensurePointerSocketTask()
            try await retryTask.send(.string(frame))
        }
    }

    private func ensurePointerSocketTask() async throws -> URLSessionWebSocketTask {
        if let existing = pointerSocketTask {
            return existing
        }
        guard let activeSession = session else {
            throw TVClientError.notConnected
        }
        let data = try await sendRequest(uri: SSAPURI.getPointerInputSocket, payload: Optional<SSAPEmptyPayload>.none)
        let decoded = try JSONDecoder().decode(SSAPResponse<SSAPPointerInputSocketPayload>.self, from: data)
        guard let path = decoded.payload?.socketPath, let url = URL(string: path) else {
            throw TVClientError.decodingFailed("Missing socketPath in getPointerInputSocket response")
        }
        let task = activeSession.webSocketTask(with: url)
        task.resume()
        pointerSocketTask = task
        return task
    }

    public func turnOff() async throws {
        _ = try await sendRequest(uri: SSAPURI.turnOff, payload: Optional<SSAPEmptyPayload>.none)
    }

    // MARK: - Low-Level Request / Response Correlation

    public func sendRequest<Payload: Encodable & Sendable>(
        uri: String,
        payload: Payload?
    ) async throws -> Data {
        guard state.isReady, webSocketTask != nil else {
            throw TVClientError.notConnected
        }

        let requestId = "req_\(nextRequestNumber)"
        nextRequestNumber += 1

        let requestFrame = SSAPRequest(id: requestId, uri: uri, payload: payload)
        let encoded = try JSONEncoder().encode(requestFrame)
        guard let text = String(data: encoded, encoding: .utf8) else {
            throw TVClientError.decodingFailed("Could not encode request for \(uri)")
        }

        try await sendRawFrame(text)

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    Task { await self.storePendingRequest(id: requestId, continuation: continuation) }
                }
            }
            group.addTask { [requestTimeoutNanoseconds] in
                try await Task.sleep(nanoseconds: requestTimeoutNanoseconds)
                await self.failPendingRequest(id: requestId, error: TVClientError.requestTimedOut(uri))
                throw TVClientError.requestTimedOut(uri)
            }
            guard let result = try await group.next() else {
                throw TVClientError.requestTimedOut(uri)
            }
            group.cancelAll()
            return result
        }
    }

    private func storePendingRequest(id: String, continuation: CheckedContinuation<Data, Error>) {
        pendingRequests[id] = continuation
    }

    private func failPendingRequest(id: String, error: Error) {
        if let cont = pendingRequests.removeValue(forKey: id) {
            cont.resume(throwing: error)
        }
    }

    private func sendRawFrame(_ text: String) async throws {
        guard let task = webSocketTask else {
            throw TVClientError.notConnected
        }
        debugLog("TX -> \(SSAPRedactor.redact(text))")
        try await task.send(.string(text))
    }

    // MARK: - Receive & Ping Loops

    private func startReceiveLoop(for task: URLSessionWebSocketTask) {
        receiveLoopTask?.cancel()
        receiveLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self else { return }
                    await self.handleInboundMessage(message)
                } catch {
                    guard let self else { return }
                    await self.handleSocketDisconnect(error: error)
                    return
                }
            }
        }
    }

    private func handleInboundMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s):
            text = s
        case .data(let d):
            guard let s = String(data: d, encoding: .utf8) else { return }
            text = s
        @unknown default:
            return
        }

        debugLog("RX <- \(SSAPRedactor.redact(String(text.prefix(600))))")
        guard let data = text.data(using: .utf8),
              let header = try? JSONDecoder().decode(SSAPEnvelopeHeader.self, from: data) else {
            return
        }

        switch header.type {
        case SSAPFrameType.registered.rawValue:
            if let regResp = try? JSONDecoder().decode(SSAPResponse<SSAPRegistrationPayload>.self, from: data),
               let key = regResp.payload?.clientKey,
               !key.isEmpty {
                let cont = pendingRegistration
                pendingRegistration = nil
                cont?.resume(returning: key)
            } else {
                let cont = pendingRegistration
                pendingRegistration = nil
                cont?.resume(throwing: TVClientError.pairingRejected("Missing client-key in registered frame"))
            }

        case SSAPFrameType.response.rawValue:
            // During pairing, TV sends a response frame with pairingType == "PROMPT"
            if pendingRegistration != nil,
               let regResp = try? JSONDecoder().decode(SSAPResponse<SSAPRegistrationPayload>.self, from: data),
               regResp.payload?.pairingType == "PROMPT",
               let host = currentHost {
                state = .awaitingApproval(host: host)
                return
            }
            if let id = header.id, let cont = pendingRequests.removeValue(forKey: id) {
                cont.resume(returning: data)
            }

        case SSAPFrameType.error.rawValue:
            let errMessage = header.error ?? "Unknown TV error"
            if let regCont = pendingRegistration {
                pendingRegistration = nil
                regCont.resume(throwing: TVClientError.pairingRejected(errMessage))
                return
            }
            if let id = header.id, let cont = pendingRequests.removeValue(forKey: id) {
                cont.resume(throwing: TVClientError.ssapError(uri: id, message: errMessage))
            }

        default:
            break
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self, pingIntervalNanoseconds] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pingIntervalNanoseconds)
                guard !Task.isCancelled, let self else { return }
                await self.performPeriodicPing()
            }
        }
    }

    private func performPeriodicPing() async {
        guard state.isReady, let task = webSocketTask else { return }
        do {
            try await sendOneShotPing(on: task)
        } catch {
            handleSocketDisconnect(error: error)
        }
    }

    private func sendOneShotPing(
        on task: URLSessionWebSocketTask,
        timeoutNanoseconds: UInt64 = 10_000_000_000
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    task.sendPing { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw TVClientError.connectionFailed("WebSocket ping timed out")
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func handleSocketDisconnect(error: Error) {
        guard webSocketTask != nil else { return }
        tearDownSocket(cancelAutoReconnect: false)

        let mapped = Self.mapTransportError(error)
        state = .failed(mapped)

        guard shouldAutoReconnect, let host = currentHost else { return }
        scheduleReconnect(host: host)
    }

    private func scheduleReconnect(host: String) {
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let delaySeconds = min(pow(2.0, Double(reconnectAttempt - 1)), 30.0)
        let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            try? await self.connect(host: host, forcePairing: false)
        }
    }

    // MARK: - Validation & Error Mapping

    public static func isValidHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("/") else {
            return false
        }
        return true
    }

    private static func mapTransportError(_ error: Error?) -> TVClientError {
        guard let error else {
            return .connectionFailed("Unknown transport error")
        }
        if let tvErr = error as? TVClientError {
            return tvErr
        }
        let nsError = error as NSError
        let localNetworkPOSIXCodes: Set<Int> = [Int(EHOSTUNREACH), Int(EPERM), Int(EACCES)]
        // Detect iOS Local Network privacy denial indicators across POSIX and URLSession layers
        if nsError.domain == NSPOSIXErrorDomain && localNetworkPOSIXCodes.contains(nsError.code) {
            return .localNetworkPermissionDenied
        }
        if nsError.domain == NSURLErrorDomain {
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
               underlying.domain == NSPOSIXErrorDomain,
               localNetworkPOSIXCodes.contains(underlying.code) {
                return .localNetworkPermissionDenied
            }
            if let streamDomain = nsError.userInfo["_kCFStreamErrorDomainKey"] as? Int,
               let streamCode = nsError.userInfo["_kCFStreamErrorCodeKey"] as? Int,
               streamDomain == 1, // kCFStreamErrorDomainPOSIX
               localNetworkPOSIXCodes.contains(streamCode) {
                return .localNetworkPermissionDenied
            }
        }
        return .connectionFailed(nsError.localizedDescription)
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[TVClient] \(SSAPRedactor.redact(message()))")
        #endif
    }
}
