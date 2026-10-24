import XCTest
import SwiftData
@testable import LGChannelSearch

@MainActor
final class ChannelRepositoryTests: XCTestCase {
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Channel.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testRefreshChannelsAndPreserveFavoritesAndRecentsOnUpsert() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let mockClient = MockTVClient()
        let repo = ChannelRepository(modelContext: context, tvClient: mockClient)

        let initial = try await repo.refreshChannelsFromTV()
        XCTAssertEqual(initial.count, MockTVClient.sampleChannels.count)

        let cairoNews = try XCTUnwrap(initial.first { $0.number == "10" })
        try repo.setFavorite(cairoNews, isFavorite: true)
        let watchedDate = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try await repo.tune(to: cairoNews, now: watchedDate)

        // Simulate TV returning an updated channel name and removing one old transponder channel
        var updatedDTOs = Array(MockTVClient.sampleChannels.dropLast())
        if let idx = updatedDTOs.firstIndex(where: { $0.channelId == cairoNews.id }) {
            updatedDTOs[idx] = SSAPChannelDTO(
                channelId: cairoNews.id,
                channelNumber: "10",
                channelName: "القاهرة الإخبارية مباشر HD",
                satelliteName: "NILESAT 7.0W",
                isTV: true,
                isRadio: false,
                isHDTV: true
            )
        }
        await mockClient.setChannels(updatedDTOs)

        let afterRefresh = try await repo.refreshChannelsFromTV()
        XCTAssertEqual(afterRefresh.count, MockTVClient.sampleChannels.count - 1, "Removed TV channels must be pruned on sync")

        let refreshedCairo = try XCTUnwrap(afterRefresh.first { $0.id == cairoNews.id })
        XCTAssertEqual(refreshedCairo.name, "القاهرة الإخبارية مباشر HD")
        XCTAssertTrue(refreshedCairo.isFavorite, "Favorite status must survive channel refresh")
        XCTAssertEqual(refreshedCairo.lastWatchedAt, watchedDate, "lastWatchedAt must survive channel refresh")
    }

    func testOfflineSearchFromCache() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let mockClient = MockTVClient()
        let repo = ChannelRepository(modelContext: context, tvClient: mockClient)

        _ = try await repo.refreshChannelsFromTV()
        await mockClient.disconnect()

        // Search works while TVClient is disconnected
        let arabicMatches = try repo.searchCachedChannels(query: "القاهره")
        XCTAssertEqual(arabicMatches.map(\.number), ["10"])

        let numberMatches = try repo.searchCachedChannels(query: "١٦٢٦")
        XCTAssertEqual(numberMatches.first?.number, "1626")
    }

    func testTuneUpdatesCurrentChannelAndRecents() async throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let mockClient = MockTVClient()
        let repo = ChannelRepository(modelContext: context, tvClient: mockClient)

        let channels = try await repo.refreshChannelsFromTV()
        let yasSports = try XCTUnwrap(channels.first { $0.number == "1625" })

        let current = try await repo.tune(to: yasSports)
        XCTAssertEqual(current.channelId, yasSports.id)
        XCTAssertEqual(current.channelName, "YAS Sports HD")

        let recents = try repo.recentChannels()
        XCTAssertEqual(recents.first?.id, yasSports.id)

        try repo.clearAllChannels()
        XCTAssertTrue(try repo.loadCachedChannels().isEmpty)
    }
}
