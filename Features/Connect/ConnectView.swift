import SwiftUI
import Observation

@MainActor
@Observable
public final class ConnectViewModel {
    public var hostInput: String
    public var macAddressInput: String
    public private(set) var connectionState: TVConnectionState = .disconnected
    public private(set) var wakeStatusMessage: String?
    public private(set) var isScanningSubnet: Bool = false
    public private(set) var discoveredHosts: [String] = []

    private let tvClient: any TVClientProtocol
    private let credentialsStore: any CredentialsStoring
    private var stateObservationTask: Task<Void, Never>?

    public init(
        tvClient: any TVClientProtocol,
        credentialsStore: any CredentialsStoring = KeychainStore.shared,
        defaultHost: String = "",
        defaultMAC: String = ""
    ) {
        self.tvClient = tvClient
        self.credentialsStore = credentialsStore
        self.hostInput = credentialsStore.loadLastHost() ?? defaultHost
        self.macAddressInput = credentialsStore.loadTVMACAddress() ?? defaultMAC
        startObservingState()
    }

    private func startObservingState() {
        stateObservationTask?.cancel()
        stateObservationTask = Task { [weak self, tvClient] in
            let stream = await tvClient.stateStream
            for await newState in stream {
                guard !Task.isCancelled, let self else { return }
                self.connectionState = newState
            }
        }
    }

    public var isBusy: Bool {
        switch connectionState {
        case .connecting, .awaitingApproval:
            return true
        case .disconnected, .ready, .failed:
            return false
        }
    }

    public var isLocalNetworkDenied: Bool {
        if case .failed(let error) = connectionState {
            return error.isLocalNetworkDenied
        }
        return false
    }

    public var hasSavedPairingKey: Bool {
        let trimmed = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return credentialsStore.loadClientKey(forHost: trimmed) != nil
    }

    public func connect(forcePairing: Bool = false) async {
        wakeStatusMessage = nil
        let trimmedHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        credentialsStore.saveLastHost(trimmedHost)
        try? await tvClient.connect(host: trimmedHost, forcePairing: forcePairing)
    }

    public func disconnect() async {
        await tvClient.disconnect()
    }

    public func sendWakeOnLAN() {
        let trimmedMAC = macAddressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        credentialsStore.saveTVMACAddress(trimmedMAC)
        do {
            try WakeOnLAN.send(macAddress: trimmedMAC)
            wakeStatusMessage = "Sent Wake-on-LAN magic packet to \(trimmedMAC). Wait ~10s and tap Connect."
        } catch {
            wakeStatusMessage = error.localizedDescription
        }
    }

    public func scanLocalNetwork() async {
        guard !isScanningSubnet else { return }
        isScanningSubnet = true
        defer { isScanningSubnet = false }

        let found = await SubnetScanner.scanForTVs(hintHost: hostInput)
        discoveredHosts = found
        if let first = found.first {
            hostInput = first
            credentialsStore.saveLastHost(first)
        }
    }
}

public struct ConnectView: View {
    @Bindable var viewModel: ConnectViewModel
    var onContinueOffline: (() -> Void)?
    var onDismiss: (() -> Void)?

    public init(
        viewModel: ConnectViewModel,
        onContinueOffline: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onContinueOffline = onContinueOffline
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    ipEntryCard
                    statusCard
                    if viewModel.isLocalNetworkDenied {
                        localNetworkDeniedCard
                    }
                    wakeOnLANCard
                    if let onContinueOffline {
                        Button {
                            onContinueOffline()
                        } label: {
                            Label("Browse Cached Channels Offline", systemImage: "internaldrive")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("browseOfflineButton")
                    }
                }
                .padding()
            }
            .navigationTitle("Connect to LG TV")
            .toolbar {
                if let onDismiss {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { onDismiss() }
                    }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("LG webOS Satellite Channel Search", systemImage: "tv.and.mediabox")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Enter your LG TV's local IP address. Make sure 'LG Connect Apps' is enabled in Settings → Network on the TV.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var ipEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TV IP Address")
                .font(.subheadline.weight(.semibold))

            TextField("e.g. 192.168.1.50", text: $viewModel.hostInput)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("TV IP Address")
                .accessibilityIdentifier("tvHostTextField")

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.connect(forcePairing: false) }
                } label: {
                    HStack {
                        if viewModel.isBusy {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text(viewModel.isBusy ? "Connecting…" : "Connect")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy || viewModel.hostInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("connectButton")

                if viewModel.isBusy {
                    Button("Cancel", role: .cancel) {
                        Task { await viewModel.disconnect() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.hasSavedPairingKey {
                Label("Paired client-key saved in Keychain", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Divider()

            Button {
                Task { await viewModel.scanLocalNetwork() }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isScanningSubnet {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                    Text(viewModel.isScanningSubnet ? "Scanning subnet (ports 3001/3000)…" : "Auto-Discover TV on Local Subnet")
                        .font(.footnote.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanningSubnet || viewModel.isBusy)

            if !viewModel.discoveredHosts.isEmpty {
                HStack(spacing: 8) {
                    Text("Found:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(viewModel.discoveredHosts, id: \.self) { ip in
                        Button(ip) {
                            viewModel.hostInput = ip
                        }
                        .font(.caption.monospaced())
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                statusIcon
                Text(viewModel.connectionState.statusText)
                    .font(.subheadline)
            }
            if case .awaitingApproval = viewModel.connectionState {
                Text("Use your LG Magic Remote to select 'Accept' or 'Yes' on the TV screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.connectionState {
        case .disconnected:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
        case .connecting:
            Image(systemName: "bolt.horizontal.circle.fill")
                .foregroundStyle(.blue)
        case .awaitingApproval:
            Image(systemName: "hand.raised.circle.fill")
                .foregroundStyle(.orange)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var localNetworkDeniedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Local Network Permission Required", systemImage: "network.slash")
                .font(.headline)
                .foregroundStyle(.red)
            Text("iOS blocked access to your local Wi-Fi network. Enable 'Local Network' for LG Channel Search in iOS Settings, then tap Retry.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                #if canImport(UIKit)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
                #endif

                Button {
                    Task { await viewModel.connect(forcePairing: false) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private var wakeOnLANCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("TV in Standby? (Wake-on-LAN)", systemImage: "power")
                .font(.subheadline.weight(.semibold))
            TextField("TV MAC Address (e.g. AA:BB:CC:DD:EE:FF)", text: $viewModel.macAddressInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.footnote.monospaced())
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("TV MAC Address")

            Button {
                viewModel.sendWakeOnLAN()
            } label: {
                Label("Send Wake-on-LAN Packet", systemImage: "wave.3.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.macAddressInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let msg = viewModel.wakeStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
