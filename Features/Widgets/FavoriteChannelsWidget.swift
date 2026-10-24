import SwiftUI
import WidgetKit
import SwiftData
import AppIntents

public struct FavoriteChannelEntry: TimelineEntry, Sendable {
    public let date: Date
    public let channels: [FavoriteChannelItem]

    public init(date: Date = Date(), channels: [FavoriteChannelItem]) {
        self.date = date
        self.channels = channels
    }
}

public struct FavoriteChannelItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let number: String
    public let name: String

    public init(id: String, number: String, name: String) {
        self.id = id
        self.number = number
        self.name = name
    }
}

public struct FavoriteChannelsTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> FavoriteChannelEntry {
        FavoriteChannelEntry(channels: Self.sampleFavorites)
    }

    public func getSnapshot(in context: Context, completion: @escaping (FavoriteChannelEntry) -> Void) {
        completion(FavoriteChannelEntry(channels: loadFavoritesOrSample()))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<FavoriteChannelEntry>) -> Void) {
        let entry = FavoriteChannelEntry(channels: loadFavoritesOrSample())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func loadFavoritesOrSample() -> [FavoriteChannelItem] {
        guard let container = try? ModelContainer(for: Channel.self) else {
            return Self.sampleFavorites
        }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Channel>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.numericNumber, order: .forward)]
        )
        guard let fetched = try? context.fetch(descriptor), !fetched.isEmpty else {
            return Self.sampleFavorites
        }
        return fetched.prefix(4).map {
            FavoriteChannelItem(id: $0.id, number: $0.number, name: $0.name)
        }
    }

    public static let sampleFavorites: [FavoriteChannelItem] = [
        FavoriteChannelItem(id: "7_661_1626_0_50_8_100", number: "1626", name: "AD Nat Geo HD"),
        FavoriteChannelItem(id: "7_661_1625_0_50_7_100", number: "1625", name: "YAS Sports HD"),
        FavoriteChannelItem(id: "7_260_1_0_500_4740_20480", number: "1", name: "WAAR HD"),
        FavoriteChannelItem(id: "7_260_6_0_500_5940_20480", number: "6", name: "France 24")
    ]
}

public struct FavoriteChannelsWidgetEntryView: View {
    public var entry: FavoriteChannelEntry

    public init(entry: FavoriteChannelEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text("LG TV Favorites")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(entry.channels.prefix(4)) { ch in
                    Button(intent: TuneChannelIntent(channelQuery: ch.id)) {
                        HStack(spacing: 6) {
                            Text(ch.number)
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            Text(ch.name)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

public struct FavoriteChannelsWidget: Widget {
    public let kind: String = "FavoriteChannelsWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FavoriteChannelsTimelineProvider()) { entry in
            FavoriteChannelsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("LG TV Favorite Channels")
        .description("Tap a favorite satellite channel to tune your LG webOS TV immediately.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
