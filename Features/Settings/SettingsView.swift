import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    public let connectionState: TVConnectionState
    public let cachedChannelCount: Int
    public let isSyncing: Bool
    public let credentialsStore: any CredentialsStoring
    public var onRefreshChannels: () async -> Void
    public var onSwitchTV: (() -> Void)?
    public var onClearCache: (() -> Void)?
    public var onRePair: () async -> Void
    public var onForgetTV: () async -> Void

    @State private var macAddress: String = ""
    @State private var wolFeedback: String?
    @State private var isConfirmingClearCache: Bool = false

    public init(
        connectionState: TVConnectionState,
        cachedChannelCount: Int,
        isSyncing: Bool,
        credentialsStore: any CredentialsStoring = KeychainStore.shared,
        onRefreshChannels: @escaping () async -> Void,
        onSwitchTV: (() -> Void)? = nil,
        onClearCache: (() -> Void)? = nil,
        onRePair: @escaping () async -> Void,
        onForgetTV: @escaping () async -> Void
    ) {
        self.connectionState = connectionState
        self.cachedChannelCount = cachedChannelCount
        self.isSyncing = isSyncing
        self.credentialsStore = credentialsStore
        self.onRefreshChannels = onRefreshChannels
        self.onSwitchTV = onSwitchTV
        self.onClearCache = onClearCache
        self.onRePair = onRePair
        self.onForgetTV = onForgetTV
        _macAddress = State(initialValue: credentialsStore.loadTVMACAddress() ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("TV Connection") {
                    LabeledContent("Status", value: connectionState.statusText)
                    if let host = connectionState.connectedHost ?? credentialsStore.loadLastHost() {
                        LabeledContent("TV IP Address", value: host)
                        let hasKey = credentialsStore.loadClientKey(forHost: host) != nil
                        LabeledContent("Pairing Key", value: hasKey ? "Saved in Keychain" : "Not Paired")
                    }
                    if let onSwitchTV {
                        Button {
                            onSwitchTV()
                        } label: {
                            Label("Change TV / IP Address", systemImage: "tv.and.mediabox")
                        }
                    }
                }

                Section("Channel Database") {
                    LabeledContent("Cached Channels", value: "\(cachedChannelCount)")

                    Button {
                        Task { await onRefreshChannels() }
                    } label: {
                        HStack {
                            Label("Sync Channels from TV", systemImage: "arrow.clockwise")
                            if isSyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!connectionState.isReady || isSyncing)

                    if let onClearCache, cachedChannelCount > 0 {
                        Button(role: .destructive) {
                            isConfirmingClearCache = true
                        } label: {
                            Label("Clear Cached Channels", systemImage: "xmark.bin")
                        }
                        .confirmationDialog(
                            "Clear all \(cachedChannelCount) cached channels?",
                            isPresented: $isConfirmingClearCache,
                            titleVisibility: .visible
                        ) {
                            Button("Clear Channel Cache", role: .destructive) {
                                onClearCache()
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    }
                }

                Section("Wake on LAN") {
                    TextField("TV MAC Address (e.g. AA:BB:CC:DD:EE:FF)", text: $macAddress)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Button {
                        credentialsStore.saveTVMACAddress(macAddress)
                        do {
                            try WakeOnLAN.send(macAddress: macAddress)
                            wolFeedback = "Sent Wake-on-LAN packet to \(macAddress)."
                        } catch {
                            wolFeedback = error.localizedDescription
                        }
                    } label: {
                        Label("Wake TV Now", systemImage: "power")
                    }
                    .disabled(macAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let wolFeedback {
                        Text(wolFeedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Pairing & Reset") {
                    Button {
                        Task { await onRePair() }
                    } label: {
                        Label("Re-Pair with TV (Force Prompt)", systemImage: "key.radiowaves.forward")
                    }

                    Button(role: .destructive) {
                        Task {
                            await onForgetTV()
                            dismiss()
                        }
                    } label: {
                        Label("Forget TV & Clear Keychain Key", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
