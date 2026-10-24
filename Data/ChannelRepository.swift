import Foundation
import SwiftData

@MainActor
public final class ChannelRepository {
    private let modelContext: ModelContext
    private let tvClient: any TVClientProtocol

    public init(modelContext: ModelContext, tvClient: any TVClientProtocol) {
        self.modelContext = modelContext
        self.tvClient = tvClient
    }

    // MARK: - Fetch & Upsert

    /// Fetches the channel list from the TV and upserts into SwiftData while preserving `isFavorite` and `lastWatchedAt`.
    @discardableResult
    public func refreshChannelsFromTV() async throws -> [Channel] {
        let dtos = try await tvClient.fetchChannelList()
        return try upsertChannels(from: dtos)
    }

    /// Upserts a batch of `SSAPChannelDTO` into SwiftData, preserving user state (`isFavorite`, `lastWatchedAt`)
    /// and pruning stale channels removed from the TV's channel lineup.
    @discardableResult
    public func upsertChannels(from dtos: [SSAPChannelDTO]) throws -> [Channel] {
        let existingChannels = try loadCachedChannels()
        var existingById: [String: Channel] = [:]
        existingById.reserveCapacity(existingChannels.count)
        for ch in existingChannels {
            existingById[ch.id] = ch
        }

        var visibleIncomingIds = Set<String>()
        visibleIncomingIds.reserveCapacity(dtos.count)

        for dto in dtos where dto.isInvisible != true {
            visibleIncomingIds.insert(dto.channelId)
            if let existing = existingById[dto.channelId] {
                existing.applyDTO(dto)
            } else {
                let created = Channel.fromDTO(dto)
                modelContext.insert(created)
                existingById[dto.channelId] = created
            }
        }

        if !visibleIncomingIds.isEmpty {
            for existing in existingChannels where !visibleIncomingIds.contains(existing.id) {
                modelContext.delete(existing)
            }
        }

        try modelContext.save()
        return try loadCachedChannels()
    }

    public func clearAllChannels() throws {
        let existingChannels = try loadCachedChannels()
        for channel in existingChannels {
            modelContext.delete(channel)
        }
        try modelContext.save()
    }

    // MARK: - Offline Cache & Search

    public func loadCachedChannels() throws -> [Channel] {
        let descriptor = FetchDescriptor<Channel>(
            sortBy: [
                SortDescriptor(\.numericNumber, order: .forward),
                SortDescriptor(\.nameNormalized, order: .forward)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    public func searchCachedChannels(query: String) throws -> [Channel] {
        let all = try loadCachedChannels()
        return SearchEngine.search(all, query: query)
    }

    // MARK: - Favorites & Recents

    public func toggleFavorite(_ channel: Channel) throws {
        channel.isFavorite.toggle()
        try modelContext.save()
    }

    public func setFavorite(_ channel: Channel, isFavorite: Bool) throws {
        channel.isFavorite = isFavorite
        try modelContext.save()
    }

    public func recentChannels(limit: Int = 10) throws -> [Channel] {
        let all = try loadCachedChannels()
        return all
            .filter { $0.lastWatchedAt != nil }
            .sorted { ($0.lastWatchedAt ?? .distantPast) > ($1.lastWatchedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Tune & Verify

    /// Tunes the TV to `channel`, verifies via `getCurrentChannel`, and updates `lastWatchedAt`.
    @discardableResult
    public func tune(to channel: Channel, now: Date = Date()) async throws -> SSAPCurrentChannelPayload {
        try await tvClient.openChannel(channelId: channel.id, fallbackChannelNumber: channel.number)
        let current = try await tvClient.fetchCurrentChannel()

        channel.lastWatchedAt = now
        if current.channelId != channel.id,
           let tunedMatch = try? loadCachedChannels().first(where: { $0.id == current.channelId }) {
            tunedMatch.lastWatchedAt = now
        }
        try modelContext.save()
        return current
    }
}
