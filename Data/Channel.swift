import Foundation
import SwiftData

@Model
public final class Channel: SearchableChannel {
    @Attribute(.unique) public var id: String
    public var number: String
    public var numericNumber: Int
    public var name: String
    public var nameNormalized: String
    public var source: String
    public var type: String
    public var satelliteName: String?
    public var isRadio: Bool
    public var isHD: Bool
    public var isScrambled: Bool
    public var frequency: Int?
    public var isFavorite: Bool
    public var lastWatchedAt: Date?

    public init(
        id: String,
        number: String,
        name: String,
        source: String = "Satellite",
        type: String = "Satellite Digital TV",
        satelliteName: String? = nil,
        isRadio: Bool = false,
        isHD: Bool = false,
        isScrambled: Bool = false,
        frequency: Int? = nil,
        isFavorite: Bool = false,
        lastWatchedAt: Date? = nil
    ) {
        self.id = id
        self.number = number
        self.numericNumber = Int(ArabicNormalizer.normalizeChannelNumber(number)) ?? Int.max
        self.name = name
        self.nameNormalized = ArabicNormalizer.normalize(name)
        self.source = source
        self.type = type
        self.satelliteName = satelliteName
        self.isRadio = isRadio
        self.isHD = isHD
        self.isScrambled = isScrambled
        self.frequency = frequency
        self.isFavorite = isFavorite
        self.lastWatchedAt = lastWatchedAt
    }

    /// Updates mutable TV-sourced metadata while preserving `isFavorite` and `lastWatchedAt`.
    public func applyDTO(_ dto: SSAPChannelDTO) {
        self.number = dto.channelNumber
        self.numericNumber = Int(ArabicNormalizer.normalizeChannelNumber(dto.channelNumber)) ?? Int.max
        self.name = dto.channelName
        self.nameNormalized = ArabicNormalizer.normalize(dto.channelName)
        self.source = dto.channelMode ?? "Satellite"
        self.type = dto.channelType ?? ((dto.isRadio == true) ? "Satellite Digital Radio" : "Satellite Digital TV")
        self.satelliteName = dto.satelliteName
        self.isRadio = dto.isRadio ?? (dto.channelTypeId == 7)
        self.isHD = dto.isHDTV ?? false
        self.isScrambled = dto.isScrambled ?? false
        self.frequency = dto.frequency
    }

    public static func fromDTO(_ dto: SSAPChannelDTO) -> Channel {
        Channel(
            id: dto.channelId,
            number: dto.channelNumber,
            name: dto.channelName,
            source: dto.channelMode ?? "Satellite",
            type: dto.channelType ?? ((dto.isRadio == true) ? "Satellite Digital Radio" : "Satellite Digital TV"),
            satelliteName: dto.satelliteName,
            isRadio: dto.isRadio ?? (dto.channelTypeId == 7),
            isHD: dto.isHDTV ?? false,
            isScrambled: dto.isScrambled ?? false,
            frequency: dto.frequency
        )
    }
}
