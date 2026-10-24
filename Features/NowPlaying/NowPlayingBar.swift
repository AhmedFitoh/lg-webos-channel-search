import SwiftUI

public struct NowPlayingBar: View {
    public let currentChannel: SSAPCurrentChannelPayload?
    public let isConnected: Bool
    public let isTuning: Bool
    public var onRefreshCurrent: (() -> Void)?

    public init(
        currentChannel: SSAPCurrentChannelPayload?,
        isConnected: Bool,
        isTuning: Bool = false,
        onRefreshCurrent: (() -> Void)? = nil
    ) {
        self.currentChannel = currentChannel
        self.isConnected = isConnected
        self.isTuning = isTuning
        self.onRefreshCurrent = onRefreshCurrent
    }

    public var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            if let currentChannel {
                Text(currentChannel.channelNumber)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentChannel.channelName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(currentChannel.channelTypeName ?? currentChannel.channelModeName ?? "Satellite")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isConnected ? "Connected to TV" : "Offline (Cached Channels)")
                        .font(.subheadline.weight(.medium))
                    Text(isConnected ? "Tap any channel to tune" : "Reconnect to tune channels on TV")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if isTuning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Tuning channel")
            } else if let onRefreshCurrent, isConnected {
                Button {
                    onRefreshCurrent()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh now playing channel")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if let currentChannel {
            return "Now playing channel \(currentChannel.channelNumber), \(currentChannel.channelName)"
        }
        return isConnected ? "Connected to TV, no active channel loaded" : "Offline mode, browsing cached channels"
    }
}
