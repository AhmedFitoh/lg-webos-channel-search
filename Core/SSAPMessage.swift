import Foundation

// MARK: - Outbound SSAP Frames

public enum SSAPFrameType: String, Codable, Sendable {
    case register
    case registered
    case request
    case response
    case error
    case subscribe
}

public struct SSAPRegisterFrame: Codable, Sendable {
    public let type: String
    public let id: String
    public let payload: SSAPRegisterPayload

    public init(id: String = "register_0", clientKey: String?) {
        self.type = SSAPFrameType.register.rawValue
        self.id = id
        self.payload = SSAPRegisterPayload(clientKey: clientKey)
    }
}

public struct SSAPRegisterPayload: Codable, Sendable {
    public let forcePairing: Bool
    public let pairingType: String
    public let clientKey: String?
    public let manifest: SSAPManifest

    enum CodingKeys: String, CodingKey {
        case forcePairing
        case pairingType
        case clientKey = "client-key"
        case manifest
    }

    public init(
        forcePairing: Bool = false,
        pairingType: String = "PROMPT",
        clientKey: String?,
        manifest: SSAPManifest = .defaultManifest
    ) {
        self.forcePairing = forcePairing
        self.pairingType = pairingType
        self.clientKey = (clientKey?.isEmpty == false) ? clientKey : nil
        self.manifest = manifest
    }
}

public struct SSAPManifest: Codable, Sendable {
    public let manifestVersion: Int
    public let permissions: [String]

    public init(manifestVersion: Int = 1, permissions: [String]) {
        self.manifestVersion = manifestVersion
        self.permissions = permissions
    }

    public static let defaultPermissions: [String] = [
        "LAUNCH",
        "LAUNCH_WEBAPP",
        "APP_TO_APP",
        "CLOSE",
        "TEST_OPEN",
        "TEST_PROTECTED",
        "CONTROL_AUDIO",
        "CONTROL_DISPLAY",
        "CONTROL_INPUT_JOYSTICK",
        "CONTROL_INPUT_MEDIA_RECORDING",
        "CONTROL_INPUT_MEDIA_PLAYBACK",
        "CONTROL_INPUT_TV",
        "CONTROL_POWER",
        "READ_APP_STATUS",
        "READ_CURRENT_CHANNEL",
        "READ_INPUT_DEVICE_LIST",
        "READ_NETWORK_STATE",
        "READ_RUNNING_APPS",
        "READ_TV_CHANNEL_LIST",
        "WRITE_NOTIFICATION_TOAST",
        "READ_POWER_STATE",
        "READ_COUNTRY_INFO",
        "READ_SETTINGS",
        "CONTROL_TV_SCREEN",
        "CONTROL_TV_STANBY",
        "CONTROL_FAVORITE_GROUP",
        "CONTROL_USER_INFO",
        "CHECK_BLUETOOTH_DEVICE",
        "CONTROL_BLUETOOTH",
        "CONTROL_TIMER_INFO",
        "STB_INTERNAL_CONNECTION",
        "CONTROL_RECORDING",
        "READ_RECORDING_STATE",
        "WRITE_RECORDING_LIST",
        "READ_RECORDING_LIST",
        "READ_RECORDING_SCHEDULE",
        "WRITE_RECORDING_SCHEDULE",
        "READ_STORAGE_DEVICE_LIST",
        "READ_TV_PROGRAM_INFO",
        "CONTROL_BOX_CHANNEL",
        "READ_TV_ACR_AUTH_TOKEN",
        "READ_TV_CONTENT_STATE",
        "READ_TV_CURRENT_TIME",
        "ADD_LAUNCHER_CHANNEL",
        "SET_CHANNEL_SKIP",
        "RELEASE_CHANNEL_SKIP",
        "CONTROL_CHANNEL_BLOCK",
        "DELETE_SELECT_CHANNEL",
        "CONTROL_CHANNEL_GROUP",
        "SCAN_TV_CHANNELS",
        "CONTROL_TV_POWER",
        "CONTROL_WOL"
    ]

    public static let defaultManifest = SSAPManifest(permissions: defaultPermissions)
}

public struct SSAPRequest<Payload: Encodable & Sendable>: Encodable, Sendable {
    public let type: String
    public let id: String
    public let uri: String
    public let payload: Payload?

    public init(id: String, uri: String, payload: Payload? = nil) {
        self.type = SSAPFrameType.request.rawValue
        self.id = id
        self.uri = uri
        self.payload = payload
    }
}

public struct SSAPEmptyPayload: Codable, Sendable {
    public init() {}
}

public struct SSAPOpenChannelPayload: Codable, Sendable, Equatable {
    public let channelId: String?
    public let channelNumber: String?

    public init(channelId: String? = nil, channelNumber: String? = nil) {
        self.channelId = channelId
        self.channelNumber = channelNumber
    }
}

// MARK: - Inbound SSAP Envelopes & Payloads

public struct SSAPEnvelopeHeader: Decodable, Sendable {
    public let id: String?
    public let type: String
    public let error: String?
}

public struct SSAPResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    public let id: String?
    public let type: String
    public let error: String?
    public let payload: Payload?
}

public struct SSAPRegistrationPayload: Decodable, Sendable {
    public let clientKey: String?
    public let pairingType: String?
    public let returnValue: Bool?

    enum CodingKeys: String, CodingKey {
        case clientKey = "client-key"
        case pairingType
        case returnValue
    }
}

public struct SSAPReturnValuePayload: Codable, Sendable, Equatable {
    public let returnValue: Bool?

    public init(returnValue: Bool? = true) {
        self.returnValue = returnValue
    }
}

// MARK: - Channel Payloads (Verified on LG 55UP7760PVB webOS 6.5.3-47)

public struct SSAPChannelListPayload: Codable, Sendable {
    public let returnValue: Bool?
    public let channelListCount: Int?
    public let channelList: [SSAPChannelDTO]

    public init(returnValue: Bool? = true, channelListCount: Int? = nil, channelList: [SSAPChannelDTO]) {
        self.returnValue = returnValue
        self.channelListCount = channelListCount ?? channelList.count
        self.channelList = channelList
    }
}

public struct SSAPChannelDTO: Codable, Sendable, Equatable {
    public let channelId: String
    public let channelNumber: String
    public let channelName: String
    public let channelMode: String?
    public let channelModeId: Int?
    public let channelType: String?
    public let channelTypeId: Int?
    public let satelliteName: String?
    public let isTV: Bool?
    public let isRadio: Bool?
    public let isHDTV: Bool?
    public let isScrambled: Bool?
    public let isSkipped: Bool?
    public let isLocked: Bool?
    public let isInvisible: Bool?
    public let frequency: Int?
    public let physicalNumber: Int?
    public let serviceType: Int?
    public let signalChannelId: String?

    enum CodingKeys: String, CodingKey {
        case channelId
        case channelNumber
        case channelName
        case channelMode
        case channelModeId
        case channelType
        case channelTypeId
        case satelliteName
        case isTV = "TV"
        case isRadio = "Radio"
        case isHDTV = "HDTV"
        case isScrambled = "scrambled"
        case isSkipped = "skipped"
        case isLocked = "locked"
        case isInvisible = "Invisible"
        case frequency = "Frequency"
        case physicalNumber
        case serviceType
        case signalChannelId
    }

    public init(
        channelId: String,
        channelNumber: String,
        channelName: String,
        channelMode: String? = "Satellite",
        channelModeId: Int? = 2,
        channelType: String? = "Satellite Digital TV",
        channelTypeId: Int? = 6,
        satelliteName: String? = "NILESAT 7.0W",
        isTV: Bool? = true,
        isRadio: Bool? = false,
        isHDTV: Bool? = false,
        isScrambled: Bool? = false,
        isSkipped: Bool? = false,
        isLocked: Bool? = false,
        isInvisible: Bool? = false,
        frequency: Int? = nil,
        physicalNumber: Int? = nil,
        serviceType: Int? = nil,
        signalChannelId: String? = nil
    ) {
        self.channelId = channelId
        self.channelNumber = channelNumber
        self.channelName = channelName
        self.channelMode = channelMode
        self.channelModeId = channelModeId
        self.channelType = channelType
        self.channelTypeId = channelTypeId
        self.satelliteName = satelliteName
        self.isTV = isTV
        self.isRadio = isRadio
        self.isHDTV = isHDTV
        self.isScrambled = isScrambled
        self.isSkipped = isSkipped
        self.isLocked = isLocked
        self.isInvisible = isInvisible
        self.frequency = frequency
        self.physicalNumber = physicalNumber
        self.serviceType = serviceType
        self.signalChannelId = signalChannelId
    }
}

public struct SSAPCurrentChannelPayload: Codable, Sendable, Equatable {
    public let returnValue: Bool?
    public let channelId: String
    public let channelNumber: String
    public let channelName: String
    public let channelModeId: Int?
    public let channelModeName: String?
    public let channelTypeId: Int?
    public let channelTypeName: String?
    public let physicalNumber: Int?
    public let isScrambled: Bool?
    public let isLocked: Bool?
    public let isHEVCChannel: Bool?
    public let signalChannelId: String?

    public init(
        returnValue: Bool? = true,
        channelId: String,
        channelNumber: String,
        channelName: String,
        channelModeId: Int? = 2,
        channelModeName: String? = "Satellite",
        channelTypeId: Int? = 6,
        channelTypeName: String? = "Satellite Digital TV",
        physicalNumber: Int? = nil,
        isScrambled: Bool? = false,
        isLocked: Bool? = false,
        isHEVCChannel: Bool? = false,
        signalChannelId: String? = nil
    ) {
        self.returnValue = returnValue
        self.channelId = channelId
        self.channelNumber = channelNumber
        self.channelName = channelName
        self.channelModeId = channelModeId
        self.channelModeName = channelModeName
        self.channelTypeId = channelTypeId
        self.channelTypeName = channelTypeName
        self.physicalNumber = physicalNumber
        self.isScrambled = isScrambled
        self.isLocked = isLocked
        self.isHEVCChannel = isHEVCChannel
        self.signalChannelId = signalChannelId
    }
}

public struct SSAPExternalInputDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let appId: String?
    public let connected: Bool?

    public init(id: String, label: String, appId: String? = nil, connected: Bool? = true) {
        self.id = id
        self.label = label
        self.appId = appId
        self.connected = connected
    }
}

public struct SSAPExternalInputListPayload: Codable, Sendable {
    public let returnValue: Bool?
    public let devices: [SSAPExternalInputDTO]

    public init(returnValue: Bool? = true, devices: [SSAPExternalInputDTO]) {
        self.returnValue = returnValue
        self.devices = devices
    }
}

public enum TVRemoteButton: String, Codable, Sendable, CaseIterable {
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
    case enter = "ENTER"
    case back = "BACK"
    case home = "HOME"
    case exit = "EXIT"
    case info = "INFO"
    case guide = "GUIDE"
}

public struct SSAPPointerInputSocketPayload: Codable, Sendable {
    public let returnValue: Bool?
    public let socketPath: String?
}

// MARK: - SSAP URIs & Redaction

public enum SSAPURI {
    public static let getChannelList = "ssap://tv/getChannelList"
    public static let getCurrentChannel = "ssap://tv/getCurrentChannel"
    public static let openChannel = "ssap://tv/openChannel"
    public static let channelUp = "ssap://tv/channelUp"
    public static let channelDown = "ssap://tv/channelDown"
    public static let getExternalInputList = "ssap://tv/getExternalInputList"
    public static let switchInput = "ssap://tv/switchInput"
    public static let getPointerInputSocket = "ssap://com.webos.service.networkinput/getPointerInputSocket"
    public static let setMute = "ssap://audio/setMute"
    public static let volumeUp = "ssap://audio/volumeUp"
    public static let volumeDown = "ssap://audio/volumeDown"
    public static let turnOff = "ssap://system/turnOff"
}

public enum SSAPRedactor {
    /// Redacts any `"client-key":"..."` value from raw JSON frames before debug logging.
    public static func redact(_ rawJSON: String) -> String {
        guard rawJSON.contains("client-key") else { return rawJSON }
        let pattern = #"("client-key"\s*:\s*")([^"]*)(")"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return "[REDACTED SSAP FRAME]"
        }
        let range = NSRange(rawJSON.startIndex..<rawJSON.endIndex, in: rawJSON)
        return regex.stringByReplacingMatches(in: rawJSON, range: range, withTemplate: "$1<REDACTED>$3")
    }
}
