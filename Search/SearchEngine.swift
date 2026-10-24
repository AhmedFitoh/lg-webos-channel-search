import Foundation

public protocol SearchableChannel {
    var id: String { get }
    var number: String { get }
    var numericNumber: Int { get }
    var name: String { get }
    var nameNormalized: String { get }
    var isFavorite: Bool { get }
}

public extension SearchableChannel {
    var numericNumber: Int {
        Int(ArabicNormalizer.normalizeChannelNumber(number)) ?? Int.max
    }
}

public enum SearchMatchRank: Int, Comparable, Sendable {
    case exactNumber = 0
    case exactName = 1
    case prefix = 2
    case tokenPrefix = 3
    case substring = 4

    public static func < (lhs: SearchMatchRank, rhs: SearchMatchRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ScoredChannel<Item: SearchableChannel> {
    public let item: Item
    public let rank: SearchMatchRank
}

public enum SearchEngine {
    private static let tokenSeparatorSet = CharacterSet.alphanumerics.inverted

    /// Searches and ranks channels using `ArabicNormalizer` rules:
    /// Ranking: `.exactNumber` > `.exactName` > `.prefix` > `.tokenPrefix` > `.substring`.
    public static func search<Item: SearchableChannel>(
        _ channels: [Item],
        query: String
    ) -> [Item] {
        let normalizedQuery = ArabicNormalizer.normalize(query)
        let normalizedNumberQuery = ArabicNormalizer.normalizeChannelNumber(query)

        guard !normalizedQuery.isEmpty else {
            return channels.sorted(by: defaultChannelOrder)
        }

        let queryTokens = tokenize(normalizedQuery)
        var matches: [ScoredChannel<Item>] = []
        matches.reserveCapacity(min(channels.count, 128))

        for channel in channels {
            if let rank = evaluateMatch(
                channel: channel,
                normalizedQuery: normalizedQuery,
                normalizedNumberQuery: normalizedNumberQuery,
                queryTokens: queryTokens
            ) {
                matches.append(ScoredChannel(item: channel, rank: rank))
            }
        }

        matches.sort { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            if lhs.item.isFavorite != rhs.item.isFavorite {
                return lhs.item.isFavorite && !rhs.item.isFavorite
            }
            return defaultChannelOrder(lhs.item, rhs.item)
        }

        return matches.map(\.item)
    }

    public static func evaluateMatch<Item: SearchableChannel>(
        channel: Item,
        normalizedQuery: String,
        normalizedNumberQuery: String,
        queryTokens: [String]
    ) -> SearchMatchRank? {
        let channelNumberNorm = ArabicNormalizer.normalizeChannelNumber(channel.number)
        let channelNameNorm = channel.nameNormalized.isEmpty
            ? ArabicNormalizer.normalize(channel.name)
            : channel.nameNormalized

        // 1. Exact channel number match (e.g. "1626" or "١٦٢٦")
        if !normalizedNumberQuery.isEmpty && channelNumberNorm == normalizedNumberQuery {
            return .exactNumber
        }

        // 2. Exact normalized channel name match
        if channelNameNorm == normalizedQuery {
            return .exactName
        }

        // 3. Name prefix or number prefix match
        if channelNameNorm.hasPrefix(normalizedQuery) {
            return .prefix
        }
        if !normalizedNumberQuery.isEmpty,
           normalizedNumberQuery.allSatisfy(\.isNumber),
           channelNumberNorm.hasPrefix(normalizedNumberQuery) {
            return .prefix
        }

        // 4. Token-prefix match (all query tokens match prefixes of tokens in the channel name)
        let nameTokens = tokenize(channelNameNorm)
        if !queryTokens.isEmpty && !nameTokens.isEmpty {
            let allTokensMatchPrefix = queryTokens.allSatisfy { qToken in
                nameTokens.contains { nToken in nToken.hasPrefix(qToken) }
            }
            if allTokensMatchPrefix {
                return .tokenPrefix
            }
        }

        // 5. Substring match (all query tokens appear anywhere in the normalized name or number)
        if channelNameNorm.contains(normalizedQuery) {
            return .substring
        }
        if queryTokens.count > 1 {
            let allTokensContained = queryTokens.allSatisfy { qToken in
                channelNameNorm.contains(qToken) || channelNumberNorm.contains(qToken)
            }
            if allTokensContained {
                return .substring
            }
        }

        return nil
    }

    public static func tokenize(_ normalizedText: String) -> [String] {
        normalizedText
            .components(separatedBy: tokenSeparatorSet)
            .filter { !$0.isEmpty }
    }

    public static func defaultChannelOrder<Item: SearchableChannel>(_ a: Item, _ b: Item) -> Bool {
        let numA = a.numericNumber
        let numB = b.numericNumber
        if numA != numB {
            return numA < numB
        }
        if a.nameNormalized != b.nameNormalized {
            return a.nameNormalized < b.nameNormalized
        }
        return a.id < b.id
    }
}
