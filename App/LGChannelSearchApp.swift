import SwiftUI
import SwiftData

@main
struct LGChannelSearchApp: App {
    private let modelContainer: ModelContainer
    @State private var appCoordinator: AppCoordinator

    init() {
        #if DEBUG
        let isMockMode = ProcessInfo.processInfo.arguments.contains("--mock-tv")
        #else
        let isMockMode = false
        #endif
        let schema = Schema([Channel.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isMockMode)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContainer = container
            #if DEBUG
            let client: any TVClientProtocol = isMockMode ? MockTVClient() : TVClient()
            let store: any CredentialsStoring = isMockMode
                ? InMemoryCredentialsStore(lastHost: "192.168.1.100", macAddress: "AA:BB:CC:DD:EE:FF")
                : KeychainStore.shared
            #else
            let client: any TVClientProtocol = TVClient()
            let store: any CredentialsStoring = KeychainStore.shared
            #endif
            _appCoordinator = State(
                initialValue: AppCoordinator(
                    modelContext: container.mainContext,
                    tvClient: client,
                    credentialsStore: store,
                    isMockMode: isMockMode
                )
            )
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView(coordinator: appCoordinator)
                .modelContainer(modelContainer)
        }
    }
}

@MainActor
@Observable
final class AppCoordinator {
    let tvClient: any TVClientProtocol
    let credentialsStore: any CredentialsStoring
    let repository: ChannelRepository
    let connectViewModel: ConnectViewModel
    let channelListViewModel: ChannelListViewModel

    var isShowingConnectSheet: Bool = false
    var isShowingRemoteSheet: Bool = false
    var isShowingSettingsSheet: Bool = false
    var hasDismissedInitialOnboarding: Bool = false

    init(
        modelContext: ModelContext,
        tvClient: any TVClientProtocol,
        credentialsStore: any CredentialsStoring,
        isMockMode: Bool
    ) {
        self.tvClient = tvClient
        self.credentialsStore = credentialsStore
        let repo = ChannelRepository(modelContext: modelContext, tvClient: tvClient)
        self.repository = repo
        self.connectViewModel = ConnectViewModel(tvClient: tvClient, credentialsStore: credentialsStore)
        self.channelListViewModel = ChannelListViewModel(repository: repo, tvClient: tvClient)

        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if channelListViewModel.allChannels.isEmpty && !isMockMode,
           let idx = args.firstIndex(of: "--fixture-path"), idx + 1 < args.count,
           let seedData = FileManager.default.contents(atPath: args[idx + 1]),
           let decoded = try? JSONDecoder().decode(SSAPResponse<SSAPChannelListPayload>.self, from: seedData),
           let dtos = decoded.payload?.channelList {
            _ = try? repo.upsertChannels(from: dtos)
            channelListViewModel.reloadFromCache()
        }
        #endif

        if isMockMode {
            hasDismissedInitialOnboarding = true
            Task {
                await self.channelListViewModel.syncFromTV()
            }
        } else if let savedHost = credentialsStore.loadLastHost(), !savedHost.isEmpty {
            hasDismissedInitialOnboarding = true
            Task {
                try? await tvClient.connect(host: savedHost, forcePairing: false)
            }
        } else {
            hasDismissedInitialOnboarding = !channelListViewModel.allChannels.isEmpty
        }
    }

    var shouldShowMainChannelView: Bool {
        channelListViewModel.connectionState.isReady
            || !channelListViewModel.allChannels.isEmpty
            || hasDismissedInitialOnboarding
    }

    func rePairCurrentHost() async {
        let host = connectViewModel.hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        isShowingSettingsSheet = false
        isShowingConnectSheet = true
        await connectViewModel.connect(forcePairing: true)
    }

    func forgetCurrentTV() async {
        let host = connectViewModel.hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        try? credentialsStore.deleteClientKey(forHost: host)
        credentialsStore.saveLastHost(nil)
        await tvClient.disconnect()
        hasDismissedInitialOnboarding = false
    }
}

struct RootContainerView: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        Group {
            if coordinator.shouldShowMainChannelView {
                ChannelListView(
                    viewModel: coordinator.channelListViewModel,
                    onOpenConnectSheet: { coordinator.isShowingConnectSheet = true },
                    onOpenRemote: { coordinator.isShowingRemoteSheet = true },
                    onOpenSettings: { coordinator.isShowingSettingsSheet = true }
                )
            } else {
                ConnectView(
                    viewModel: coordinator.connectViewModel,
                    onContinueOffline: { coordinator.hasDismissedInitialOnboarding = true }
                )
            }
        }
        .sheet(isPresented: $coordinator.isShowingConnectSheet) {
            ConnectView(
                viewModel: coordinator.connectViewModel,
                onContinueOffline: { coordinator.isShowingConnectSheet = false },
                onDismiss: { coordinator.isShowingConnectSheet = false }
            )
        }
        .sheet(isPresented: $coordinator.isShowingRemoteSheet) {
            RemoteControlView(
                tvClient: coordinator.tvClient,
                onChannelStepped: {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await coordinator.channelListViewModel.refreshCurrentChannel()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $coordinator.isShowingSettingsSheet) {
            SettingsView(
                connectionState: coordinator.channelListViewModel.connectionState,
                cachedChannelCount: coordinator.channelListViewModel.allChannels.count,
                isSyncing: coordinator.channelListViewModel.isSyncing,
                credentialsStore: coordinator.credentialsStore,
                onRefreshChannels: { await coordinator.channelListViewModel.syncFromTV() },
                onSwitchTV: {
                    coordinator.isShowingSettingsSheet = false
                    coordinator.isShowingConnectSheet = true
                },
                onClearCache: { coordinator.channelListViewModel.clearCache() },
                onRePair: { await coordinator.rePairCurrentHost() },
                onForgetTV: { await coordinator.forgetCurrentTV() }
            )
        }
        .onChange(of: coordinator.channelListViewModel.connectionState) { _, newState in
            if newState.isReady {
                coordinator.isShowingConnectSheet = false
                coordinator.hasDismissedInitialOnboarding = true
            }
        }
    }
}
