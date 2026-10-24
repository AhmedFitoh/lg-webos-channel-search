import Foundation
import AppIntents
import SwiftData

public struct TuneChannelIntent: AppIntent {
    public static let title: LocalizedStringResource = "Tune LG TV Channel"
    public static let description = IntentDescription(
        "Searches your LG webOS TV channels by Arabic/English name or number and tunes the TV."
    )
    public static let openAppWhenRun: Bool = false

    @Parameter(title: "Channel Name or Number")
    public var channelQuery: String

    public init() {}

    public init(channelQuery: String) {
        self.channelQuery = channelQuery
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedQuery = channelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return .result(dialog: "Please specify a channel name or number.")
        }

        guard let host = KeychainStore.shared.loadLastHost(), !host.isEmpty else {
            return .result(dialog: "Open LG Channel Search first to connect and pair your LG TV.")
        }

        let client = TVClient()
        try await client.connect(host: host, forcePairing: false)
        defer {
            Task { await client.disconnect() }
        }

        let schema = Schema([Channel.self])
        let container = try ModelContainer(for: schema)
        let repository = ChannelRepository(modelContext: container.mainContext, tvClient: client)

        var channels = try repository.loadCachedChannels()
        if channels.isEmpty {
            channels = try await repository.refreshChannelsFromTV()
        }

        let bestMatch = channels.first(where: { $0.id == trimmedQuery })
            ?? SearchEngine.search(channels, query: trimmedQuery).first
        guard let bestMatch else {
            return .result(dialog: "Could not find a channel matching '\(trimmedQuery)'.")
        }

        _ = try await repository.tune(to: bestMatch)
        return .result(dialog: "Tuning LG TV to [\(bestMatch.number)] \(bestMatch.name).")
    }
}

public struct LGChannelShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TuneChannelIntent(),
            phrases: [
                "Tune to a channel in \(.applicationName)",
                "Switch TV channel with \(.applicationName)"
            ],
            shortTitle: "Tune TV Channel",
            systemImageName: "tv.and.mediabox"
        )
    }
}
