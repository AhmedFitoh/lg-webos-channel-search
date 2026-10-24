import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

public enum ChannelCategoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case tvOnly = "TV"
    case radioOnly = "Radio"
    case hdOnly = "HD"
    case favorites = "Favorites"

    public var id: String { rawValue }
}

@MainActor
@Observable
public final class ChannelListViewModel {
    public var searchQuery: String = "" {
        didSet {
            if searchQuery != oldValue { recomputeDisplayedChannels() }
        }
    }
    public var selectedCategory: ChannelCategoryFilter = .tvOnly {
        didSet {
            if selectedCategory != oldValue { recomputeDisplayedChannels() }
        }
    }
    public var selectedSatellite: String? = nil {
        didSet {
            if selectedSatellite != oldValue { recomputeDisplayedChannels() }
        }
    }

    public private(set) var allChannels: [Channel] = []
    public private(set) var displayedChannels: [Channel] = []
    public private(set) var recentChannels: [Channel] = []
    public private(set) var availableSatellites: [String] = []
    public private(set) var currentChannel: SSAPCurrentChannelPayload?
    public private(set) var connectionState: TVConnectionState = .disconnected
    public private(set) var isSyncing: Bool = false
    public private(set) var isTuning: Bool = false
    public var errorBannerMessage: String?

    private let repository: ChannelRepository
    private let tvClient: any TVClientProtocol
    private var stateTask: Task<Void, Never>?

    public init(repository: ChannelRepository, tvClient: any TVClientProtocol) {
        self.repository = repository
        self.tvClient = tvClient
        reloadFromCache()
        observeConnectionState()
    }

    private func observeConnectionState() {
        stateTask?.cancel()
        stateTask = Task { [weak self, tvClient] in
            let stream = await tvClient.stateStream
            for await state in stream {
                guard !Task.isCancelled, let self else { return }
                let wasReady = self.connectionState.isReady
                self.connectionState = state
                if state.isReady && !wasReady {
                    await self.onBecameReady()
                }
            }
        }
    }

    private func onBecameReady() async {
        await refreshCurrentChannel()
        if allChannels.isEmpty {
            await syncFromTV()
        }
    }

    public func reloadFromCache() {
        do {
            allChannels = try repository.loadCachedChannels()
            recentChannels = try repository.recentChannels(limit: 8)
            let satellites = Set(allChannels.compactMap { ch -> String? in
                guard let sat = ch.satelliteName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !sat.isEmpty,
                      sat != "UNKNOWN" else { return nil }
                return sat
            })
            availableSatellites = satellites.sorted()
            recomputeDisplayedChannels()
        } catch {
            errorBannerMessage = error.localizedDescription
        }
    }

    public func clearCache() {
        do {
            try repository.clearAllChannels()
            reloadFromCache()
        } catch {
            errorBannerMessage = error.localizedDescription
        }
    }

    private func recomputeDisplayedChannels() {
        let base = allChannels.filter { ch in
            switch selectedCategory {
            case .all:
                break
            case .tvOnly:
                if ch.isRadio { return false }
            case .radioOnly:
                if !ch.isRadio { return false }
            case .hdOnly:
                if !ch.isHD { return false }
            case .favorites:
                if !ch.isFavorite { return false }
            }

            if let selectedSatellite {
                if ch.satelliteName != selectedSatellite {
                    return false
                }
            }
            return true
        }

        displayedChannels = SearchEngine.search(base, query: searchQuery)
    }

    public var shouldShowRecentsSection: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCategory != .favorites
            && !recentChannels.isEmpty
    }

    public func syncFromTV() async {
        guard !isSyncing else { return }
        isSyncing = true
        errorBannerMessage = nil
        defer { isSyncing = false }

        do {
            _ = try await repository.refreshChannelsFromTV()
            reloadFromCache()
            await refreshCurrentChannel()
        } catch {
            errorBannerMessage = error.localizedDescription
        }
    }

    public func refreshCurrentChannel() async {
        guard connectionState.isReady else { return }
        if let current = try? await tvClient.fetchCurrentChannel() {
            self.currentChannel = current
        }
    }

    public func tune(to channel: Channel) async {
        guard !isTuning else { return }
        isTuning = true
        errorBannerMessage = nil
        defer { isTuning = false }

        do {
            let tuned = try await repository.tune(to: channel)
            currentChannel = tuned
            recentChannels = (try? repository.recentChannels(limit: 8)) ?? recentChannels
        } catch {
            errorBannerMessage = error.localizedDescription
        }
    }

    public func toggleFavorite(_ channel: Channel) {
        do {
            try repository.toggleFavorite(channel)
            reloadFromCache()
        } catch {
            errorBannerMessage = error.localizedDescription
        }
    }
}

public struct ChannelListView: View {
    @Bindable var viewModel: ChannelListViewModel
    var onOpenConnectSheet: () -> Void
    var onOpenRemote: (() -> Void)?
    var onOpenSettings: () -> Void

    public init(
        viewModel: ChannelListViewModel,
        onOpenConnectSheet: @escaping () -> Void,
        onOpenRemote: (() -> Void)? = nil,
        onOpenSettings: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onOpenConnectSheet = onOpenConnectSheet
        self.onOpenRemote = onOpenRemote
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                if let errorMsg = viewModel.errorBannerMessage {
                    errorBanner(errorMsg)
                }

                channelListContent
            }
            .safeAreaInset(edge: .bottom) {
                NowPlayingBar(
                    currentChannel: viewModel.currentChannel,
                    isConnected: viewModel.connectionState.isReady,
                    isTuning: viewModel.isTuning,
                    onRefreshCurrent: {
                        Task { await viewModel.refreshCurrentChannel() }
                    }
                )
            }
            .navigationTitle("Channels (\(viewModel.displayedChannels.count))")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search channel name or number (Arabic / English)…"
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onOpenConnectSheet()
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.connectionState.isReady ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(viewModel.connectionState.isReady ? "TV Connected" : "Connect TV")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .accessibilityLabel(viewModel.connectionState.statusText)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if let onOpenRemote {
                            Button {
                                onOpenRemote()
                            } label: {
                                Image(systemName: "av.remote")
                            }
                            .accessibilityLabel("TV Remote")
                            .accessibilityIdentifier("remoteButton")
                        }

                        Button {
                            onOpenSettings()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsButton")
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChannelCategoryFilter.allCases) { category in
                    FilterChip(
                        title: category.rawValue,
                        systemImage: iconForCategory(category),
                        isSelected: viewModel.selectedCategory == category
                    ) {
                        viewModel.selectedCategory = category
                    }
                }

                if !viewModel.availableSatellites.isEmpty {
                    Divider()
                        .frame(height: 20)

                    FilterChip(
                        title: "All Satellites",
                        systemImage: "antenna.radiowaves.left.and.right",
                        isSelected: viewModel.selectedSatellite == nil
                    ) {
                        viewModel.selectedSatellite = nil
                    }

                    ForEach(viewModel.availableSatellites, id: \.self) { sat in
                        FilterChip(
                            title: sat,
                            systemImage: nil,
                            isSelected: viewModel.selectedSatellite == sat
                        ) {
                            viewModel.selectedSatellite = (viewModel.selectedSatellite == sat) ? nil : sat
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.secondary.opacity(0.06))
    }

    private func iconForCategory(_ category: ChannelCategoryFilter) -> String? {
        switch category {
        case .all: return nil
        case .tvOnly: return "tv"
        case .radioOnly: return "radio"
        case .hdOnly: return "sparkles.tv"
        case .favorites: return "star.fill"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.errorBannerMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.14))
    }

    @ViewBuilder
    private var channelListContent: some View {
        if viewModel.isSyncing && viewModel.allChannels.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading satellite channel list from LG TV…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.allChannels.isEmpty {
            ContentUnavailableView {
                Label("No Channels Cached", systemImage: "tv.slash")
            } description: {
                Text("Connect to your LG TV and pull to refresh to load your satellite channels.")
            } actions: {
                Button("Sync Channels Now") {
                    Task { await viewModel.syncFromTV() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if viewModel.displayedChannels.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchQuery)
        } else {
            List {
                if viewModel.shouldShowRecentsSection {
                    Section("Recently Watched") {
                        ForEach(viewModel.recentChannels, id: \.id) { channel in
                            ChannelRowView(
                                channel: channel,
                                isPlaying: viewModel.currentChannel?.channelId == channel.id,
                                onTune: { Task { await viewModel.tune(to: channel) } },
                                onToggleFavorite: { viewModel.toggleFavorite(channel) }
                            )
                        }
                    }
                }

                Section(viewModel.searchQuery.isEmpty ? "All Matching Channels" : "Search Results") {
                    ForEach(viewModel.displayedChannels, id: \.id) { channel in
                        ChannelRowView(
                            channel: channel,
                            isPlaying: viewModel.currentChannel?.channelId == channel.id,
                            onTune: { Task { await viewModel.tune(to: channel) } },
                            onToggleFavorite: { viewModel.toggleFavorite(channel) }
                        )
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.syncFromTV()
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ChannelRowView: View {
    let channel: Channel
    let isPlaying: Bool
    let onTune: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTune) {
                HStack(spacing: 12) {
                    Text(channel.number)
                        .font(.callout.monospacedDigit().weight(.bold))
                        .frame(minWidth: 48, alignment: .center)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                        .background(
                            isPlaying ? Color.accentColor : Color.secondary.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(isPlaying ? Color.white : Color.primary)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(channel.name)
                                .font(.body.weight(isPlaying ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if isPlaying {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }

                        HStack(spacing: 6) {
                            if let sat = channel.satelliteName, !sat.isEmpty, sat != "UNKNOWN" {
                                Text(sat)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(channel.source)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if let freq = channel.frequency, freq > 0 {
                                Text("· \(freq) MHz")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            if channel.isHD {
                                BadgeLabel(text: "HD")
                            }
                            if channel.isRadio {
                                BadgeLabel(text: "RADIO")
                            }
                            if channel.isScrambled {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint("Double-tap to tune the TV to this channel")

            Button(action: onToggleFavorite) {
                Image(systemName: channel.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(channel.isFavorite ? Color.yellow : Color.secondary.opacity(0.5))
                    .font(.body)
                    .padding(6)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(channel.isFavorite ? "Remove \(channel.name) from favorites" : "Add \(channel.name) to favorites")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(action: onTune) {
                Label("Tune to Channel", systemImage: "tv")
            }
            Button(action: onToggleFavorite) {
                Label(
                    channel.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: channel.isFavorite ? "star.slash" : "star"
                )
            }
            #if canImport(UIKit)
            Button {
                UIPasteboard.general.string = "[\(channel.number)] \(channel.name)"
            } label: {
                Label("Copy Channel Info", systemImage: "doc.on.doc")
            }
            #endif
        }
        .swipeActions(edge: .trailing) {
            Button {
                onToggleFavorite()
            } label: {
                Label(
                    channel.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: channel.isFavorite ? "star.slash" : "star.fill"
                )
            }
            .tint(.yellow)
        }
    }

    private var accessibilityLabelText: String {
        var parts = ["Channel \(channel.number)", channel.name]
        if channel.isHD { parts.append("HD") }
        if channel.isRadio { parts.append("Radio") }
        if let sat = channel.satelliteName, !sat.isEmpty { parts.append(sat) }
        if isPlaying { parts.append("Currently playing") }
        return parts.joined(separator: ", ")
    }
}

private struct BadgeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Color.accentColor)
    }
}
