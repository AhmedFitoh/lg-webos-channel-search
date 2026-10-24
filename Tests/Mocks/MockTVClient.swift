import Foundation

public actor MockTVClient: TVClientProtocol {
    public private(set) var state: TVConnectionState
    private var stateContinuations: [UUID: AsyncStream<TVConnectionState>.Continuation] = [:]

    public var channels: [SSAPChannelDTO]
    public var currentChannel: SSAPCurrentChannelPayload
    public var simulatedError: TVClientError?
    public private(set) var openedChannelIds: [String] = []
    public private(set) var muteState: Bool = false

    public init(
        initialState: TVConnectionState = .ready(host: "192.168.1.100"),
        channels: [SSAPChannelDTO] = MockTVClient.sampleChannels,
        currentChannel: SSAPCurrentChannelPayload = MockTVClient.defaultCurrentChannel
    ) {
        self.state = initialState
        self.channels = channels
        self.currentChannel = currentChannel
    }

    public var stateStream: AsyncStream<TVConnectionState> {
        let id = UUID()
        let currentState = self.state
        return AsyncStream { continuation in
            continuation.yield(currentState)
            self.addContinuation(id: id, continuation: continuation)
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    private func addContinuation(id: UUID, continuation: AsyncStream<TVConnectionState>.Continuation) {
        stateContinuations[id] = continuation
    }

    private func removeContinuation(id: UUID) {
        stateContinuations.removeValue(forKey: id)
    }

    private func updateState(_ newState: TVConnectionState) {
        state = newState
        for continuation in stateContinuations.values {
            continuation.yield(newState)
        }
    }

    public func setSimulatedError(_ error: TVClientError?) {
        self.simulatedError = error
    }

    public func setChannels(_ newChannels: [SSAPChannelDTO]) {
        self.channels = newChannels
    }

    public func connect(host: String, forcePairing: Bool = false) async throws {
        if let simulatedError {
            updateState(.failed(simulatedError))
            throw simulatedError
        }
        updateState(.connecting(host: host))
        if forcePairing {
            updateState(.awaitingApproval(host: host))
        }
        updateState(.ready(host: host))
    }

    public func disconnect() async {
        updateState(.disconnected)
    }

    public func fetchChannelList() async throws -> [SSAPChannelDTO] {
        if let simulatedError { throw simulatedError }
        guard state.isReady else { throw TVClientError.notConnected }
        return channels
    }

    public func fetchCurrentChannel() async throws -> SSAPCurrentChannelPayload {
        if let simulatedError { throw simulatedError }
        guard state.isReady else { throw TVClientError.notConnected }
        return currentChannel
    }

    public func openChannel(channelId: String, fallbackChannelNumber: String? = nil) async throws {
        if let simulatedError { throw simulatedError }
        guard state.isReady else { throw TVClientError.notConnected }
        openedChannelIds.append(channelId)

        if let match = channels.first(where: { $0.channelId == channelId })
            ?? channels.first(where: { $0.channelNumber == fallbackChannelNumber }) {
            currentChannel = SSAPCurrentChannelPayload(
                returnValue: true,
                channelId: match.channelId,
                channelNumber: match.channelNumber,
                channelName: match.channelName,
                channelModeId: match.channelModeId ?? 2,
                channelModeName: match.channelMode ?? "Satellite",
                channelTypeId: match.channelTypeId ?? 6,
                channelTypeName: match.channelType ?? "Satellite Digital TV",
                physicalNumber: match.physicalNumber,
                isScrambled: match.isScrambled,
                isLocked: match.isLocked,
                signalChannelId: match.signalChannelId
            )
        }
    }

    public func channelUp() async throws {
        if let simulatedError { throw simulatedError }
    }

    public func channelDown() async throws {
        if let simulatedError { throw simulatedError }
    }

    public func fetchExternalInputs() async throws -> [SSAPExternalInputDTO] {
        if let simulatedError { throw simulatedError }
        return [
            SSAPExternalInputDTO(id: "HDMI_1", label: "HDMI 1", appId: "com.webos.app.hdmi1", connected: true),
            SSAPExternalInputDTO(id: "HDMI_2", label: "HDMI 2", appId: "com.webos.app.hdmi2", connected: false)
        ]
    }

    public func switchInput(inputId: String) async throws {
        if let simulatedError { throw simulatedError }
    }

    public func setMute(_ muted: Bool) async throws {
        if let simulatedError { throw simulatedError }
        muteState = muted
    }

    public func volumeUp() async throws {
        if let simulatedError { throw simulatedError }
    }

    public func volumeDown() async throws {
        if let simulatedError { throw simulatedError }
    }

    public func sendRemoteButton(_ button: TVRemoteButton) async throws {
        if let simulatedError { throw simulatedError }
    }

    public func turnOff() async throws {
        if let simulatedError { throw simulatedError }
    }

    // MARK: - Canned Sample Data (Representative LG webOS DVB-S/S2 Satellite Structure)

    public static let defaultCurrentChannel = SSAPCurrentChannelPayload(
        returnValue: true,
        channelId: "7_661_1626_0_50_8_100",
        channelNumber: "1626",
        channelName: "AD Nat Geo HD",
        channelModeId: 2,
        channelModeName: "Satellite",
        channelTypeId: 6,
        channelTypeName: "Satellite Digital TV",
        physicalNumber: 661,
        isScrambled: false,
        isLocked: false,
        isHEVCChannel: false,
        signalChannelId: "50_8_100"
    )

    public static let sampleChannels: [SSAPChannelDTO] = [
        SSAPChannelDTO(
            channelId: "7_260_1_0_500_4740_20480",
            channelNumber: "1",
            channelName: "WAAR HD",
            satelliteName: "NILESAT 7.0W",
            isTV: true,
            isRadio: false,
            isHDTV: true,
            frequency: 10727
        ),
        SSAPChannelDTO(
            channelId: "7_260_6_0_500_5940_20480",
            channelNumber: "6",
            channelName: "France 24 (in Arabic)",
            satelliteName: "NILESAT 7.0W",
            isTV: true,
            isRadio: false,
            isHDTV: false,
            frequency: 10727
        ),
        SSAPChannelDTO(
            channelId: "7_300_10_0_500_1001_20480",
            channelNumber: "10",
            channelName: "القاهرة الإخبارية HD",
            satelliteName: "NILESAT 7.0W",
            isTV: true,
            isRadio: false,
            isHDTV: true,
            frequency: 11747
        ),
        SSAPChannelDTO(
            channelId: "7_300_11_0_500_1002_20480",
            channelNumber: "11",
            channelName: "الجزيرة مباشر",
            satelliteName: "NILESAT 7.0W",
            isTV: true,
            isRadio: false,
            isHDTV: true,
            frequency: 10971
        ),
        SSAPChannelDTO(
            channelId: "7_300_12_0_500_1003_20480",
            channelNumber: "12",
            channelName: "الأولى المصرية",
            satelliteName: "NILESAT 7.0W",
            isTV: true,
            isRadio: false,
            isHDTV: true,
            frequency: 11765
        ),
        SSAPChannelDTO(
            channelId: "7_300_15_0_500_1005_20480",
            channelNumber: "15",
            channelName: "إم بي سي مصر 2",
            satelliteName: "NILESAT 7.0W",
            isTV: true,
            isRadio: false,
            isHDTV: true,
            frequency: 12015
        ),
        SSAPChannelDTO(
            channelId: "7_260_165_0_500_1650_20480",
            channelNumber: "165",
            channelName: "TWR Arabic إذاعة حول العالم",
            channelType: "Satellite Digital Radio",
            channelTypeId: 7,
            satelliteName: "NILESAT 7.0W",
            isTV: false,
            isRadio: true,
            isHDTV: false,
            frequency: 11747
        ),
        SSAPChannelDTO(
            channelId: "7_260_528_0_500_5280_20480",
            channelNumber: "528",
            channelName: "Horus \u{00A0}Drama",
            satelliteName: "NILESAT 7.0W",
            isTV: true,
            isRadio: false,
            isHDTV: false,
            frequency: 11411
        ),
        SSAPChannelDTO(
            channelId: "7_661_1625_0_50_7_100",
            channelNumber: "1625",
            channelName: "YAS Sports HD",
            satelliteName: "EXPRESS AT1 56.0E",
            isTV: true,
            isRadio: false,
            isHDTV: true,
            frequency: 11411
        ),
        SSAPChannelDTO(
            channelId: "7_661_1626_0_50_8_100",
            channelNumber: "1626",
            channelName: "AD Nat Geo HD",
            satelliteName: "EXPRESS AT1 56.0E",
            isTV: true,
            isRadio: false,
            isHDTV: true,
            frequency: 11411
        )
    ]
}
