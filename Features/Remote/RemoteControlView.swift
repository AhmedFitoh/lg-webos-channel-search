import SwiftUI

public struct RemoteControlView: View {
    @Environment(\.dismiss) private var dismiss

    public let tvClient: any TVClientProtocol
    public var onChannelStepped: (() async -> Void)?

    @State private var isMuted: Bool = false
    @State private var inputs: [SSAPExternalInputDTO] = []
    @State private var statusMessage: String?

    public init(
        tvClient: any TVClientProtocol,
        onChannelStepped: (() async -> Void)? = nil
    ) {
        self.tvClient = tvClient
        self.onChannelStepped = onChannelStepped
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    dPadSection
                    volumeAndChannelSection
                    inputPickerSection
                    powerSection

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("TV Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let loaded = try? await tvClient.fetchExternalInputs() {
                    inputs = loaded
                }
            }
        }
    }

    private var dPadSection: some View {
        VStack(spacing: 12) {
            Text("NAVIGATION (D-PAD)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Button {
                Task { await sendButton(.up) }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.title3.weight(.bold))
                    .frame(width: 56, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Up")

            HStack(spacing: 16) {
                Button {
                    Task { await sendButton(.left) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.bold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Left")

                Button {
                    Task { await sendButton(.enter) }
                } label: {
                    Text("OK")
                        .font(.headline.weight(.bold))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .accessibilityLabel("OK Enter")

                Button {
                    Task { await sendButton(.right) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.bold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Right")
            }

            Button {
                Task { await sendButton(.down) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.bold))
                    .frame(width: 56, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Down")

            HStack(spacing: 12) {
                Button {
                    Task { await sendButton(.back) }
                } label: {
                    Label("Back", systemImage: "arrow.uturn.backward")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await sendButton(.home) }
                } label: {
                    Label("Home", systemImage: "house.fill")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await sendButton(.guide) }
                } label: {
                    Label("Guide", systemImage: "list.bullet.rectangle")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)

            HStack(spacing: 12) {
                Button {
                    Task { await sendButton(.info) }
                } label: {
                    Label("Info", systemImage: "info.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await sendButton(.exit) }
                } label: {
                    Label("Exit", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sendButton(_ button: TVRemoteButton) async {
        await runCommand("Sent \(button.rawValue)") {
            try await tvClient.sendRemoteButton(button)
        }
    }

    private var volumeAndChannelSection: some View {
        HStack(spacing: 24) {
            // Volume Rocker
            VStack(spacing: 14) {
                Text("VOLUME")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Button {
                    Task { await runCommand("Volume +") { try await tvClient.volumeUp() } }
                } label: {
                    Image(systemName: "speaker.plus.fill")
                        .font(.title2)
                        .frame(width: 72, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Volume Up")

                Button {
                    Task {
                        let nextMute = !isMuted
                        await runCommand(nextMute ? "Muted" : "Unmuted") {
                            try await tvClient.setMute(nextMute)
                            isMuted = nextMute
                        }
                    }
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                        .frame(width: 72, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(isMuted ? .orange : .primary)
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")

                Button {
                    Task { await runCommand("Volume -") { try await tvClient.volumeDown() } }
                } label: {
                    Image(systemName: "speaker.minus.fill")
                        .font(.title2)
                        .frame(width: 72, height: 52)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Volume Down")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

            // Channel Rocker
            VStack(spacing: 14) {
                Text("CHANNEL")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await runCommand("Channel Up") {
                            try await tvClient.channelUp()
                            await onChannelStepped?()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.title2.weight(.bold))
                        .frame(width: 72, height: 68)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Channel Up")

                Button {
                    Task {
                        await runCommand("Channel Down") {
                            try await tvClient.channelDown()
                            await onChannelStepped?()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title2.weight(.bold))
                        .frame(width: 72, height: 68)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Channel Down")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var inputPickerSection: some View {
        if !inputs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("External Inputs", systemImage: "cable.connector.horizontal")
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(inputs) { input in
                        Button {
                            Task {
                                await runCommand("Switched to \(input.label)") {
                                    try await tvClient.switchInput(inputId: input.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill((input.connected == true) ? Color.green : Color.secondary.opacity(0.4))
                                    .frame(width: 7, height: 7)
                                Text(input.label)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var powerSection: some View {
        Button(role: .destructive) {
            Task {
                await runCommand("Sent Turn Off to TV") {
                    try await tvClient.turnOff()
                }
            }
        } label: {
            Label("Turn Off TV", systemImage: "power")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func runCommand(_ description: String, action: () async throws -> Void) async {
        do {
            try await action()
            statusMessage = description
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
