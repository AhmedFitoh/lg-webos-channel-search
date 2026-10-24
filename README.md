# LG Channel Search for iOS

![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
![Platform iOS 17+](https://img.shields.io/badge/Platform-iOS%2017%2B-007AFF?logo=apple&logoColor=white)
![Dependencies Zero](https://img.shields.io/badge/Dependencies-Zero-brightgreen)
![License MIT](https://img.shields.io/badge/License-MIT-blue)

A fast, zero-dependency **iOS 17+ SwiftUI** app that connects to **LG webOS TVs** over your local Wi-Fi network (SSAP WebSockets), caches built-in satellite (`DVB-S/S2`), cable, and terrestrial channels in **SwiftData**, and lets you **search thousands of Arabic & English channels by name or number** and tap to tune instantaneously.

Built specifically to solve how slow and cumbersome it is to navigate 2,500+ satellite channels using a traditional TV remote.

---

## Features

- **Instant Arabic & English Search**:
  - Strips Arabic *tashkeel* (diacritics) and *tatweel* (`ـ`).
  - Unifies *Alef* variants (`أ إ آ ٱ → ا`), *Alef Maqsura* / *Ya* (`ى ی ئ → ي`), *Ta Marbuta* (`ة → ه`), and *Waw* (`ؤ → و`).
  - Converts Arabic-Indic (`٠-٩`) and Eastern Arabic-Indic (`۰-۹`) digits to ASCII (`0-9`) so searching `١٦٢٦` or `1626` works identically.
  - Collapses non-breaking transponder spaces (`U+00A0`) and ranks matches deterministically: **Exact Number → Exact Name → Prefix → Token Prefix → Substring** (with Favorites tie-breaking).
- **Offline-First SwiftData Cache**:
  - Syncs 3,000+ channels in seconds and caches them locally.
  - Preserves your **Favorites** and **Recently Watched** history across channel list re-syncs while pruning dead transponder entries.
- **Category & Multi-Satellite Filters**:
  - One-tap filter chips for `All`, `TV`, `Radio`, `HD`, `Favorites`, and individual satellites (e.g., `NILESAT 7.0W`, `HOTBIRD 13.0E`, `BADR 26.0E`).
- **Built-In TV Remote**:
  - Full D-Pad navigation (`UP`, `DOWN`, `LEFT`, `RIGHT`, `OK`, `BACK`, `HOME`, `GUIDE`, `INFO`, `EXIT`) via LG's pointer input socket, plus Volume `+/-`, Mute, Channel `+/-`, HDMI/External Input switcher, and Power Off.
- **Zero-Entitlement Local Subnet Auto-Discovery & Wake-on-LAN**:
  - Scans your active `/24` LAN for LG webOS SSAP ports (`3001` / `3000`) without requiring Apple's restricted multicast entitlement.
  - Sends standard 102-byte UDP Wake-on-LAN magic packets to wake the TV from standby.
- **Siri Shortcuts (`AppIntents`) & WidgetKit Views**:
  - Includes `TuneChannelIntent` (*"Tune to a channel in LG Channel Search"*) and `FavoriteChannelsWidget` views.

---

## TV Setup (One-Time)

1. On your LG TV remote, open **Settings** → **General / Network** → **LG Connect Apps** (called *Connect to Mobile Device* on some webOS versions) and turn it **ON**.
2. *(Optional)* Enable **Turn on via Wi-Fi** so Wake-on-LAN can power on the TV from standby.
3. Connect your iPhone and LG TV to the **same local Wi-Fi / LAN subnet**.
4. Open the app, tap **Auto-Discover TV on Local Subnet** (or enter the TV's IP address), and tap **Connect**.
5. Accept the pairing prompt on your TV screen using your LG remote. The pairing `client-key` is stored securely in the **iOS Keychain** and reused silently on future launches.

---

## Getting Started

### Run on iPhone or Simulator (Xcode)

1. Clone the repository and open `LGChannelSearch.xcodeproj` in **Xcode 15.4 / 16+**.
2. In **Signing & Capabilities**, select your personal Apple ID / Development Team (and customize `Bundle Identifier` if deploying to a physical iPhone).
3. Build and run (`⌘R`).

> **Mock Mode (No LG TV Required)**: In Xcode, go to **Product → Scheme → Edit Scheme → Run → Arguments** and enable `--mock-tv` to explore the UI, search engine, filters, and remote with sample Arabic & English satellite channels.

### Regenerate Xcode Project (Optional)

If you add or move source directories, regenerate `LGChannelSearch.xcodeproj` from [`project.yml`](./project.yml) using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
```

### Run Unit Tests via CLI

Core protocol, Keychain, SwiftData repository, and Arabic/English search engine layers are packaged in [`Package.swift`](./Package.swift) for fast headless testing:

```bash
swift test
```

---

## Architecture

```text
App/
  LGChannelSearchApp.swift          # App entry point, SwiftData container, sheet coordinator
  Info.plist                        # NSLocalNetworkUsageDescription & local networking ATS config
Core/
  TVClient.swift                    # Actor: ws:3000 / wss:3001 connect, pair, id-correlated requests, pointer socket
  SSAPMessage.swift                 # Codable SSAP envelopes, DTOs, remote buttons, and client-key redactor
  TVConnectionState.swift           # Connection state machine & iOS Local Network permission error mapping
  TrustDelegate.swift               # Host-scoped URLSessionDelegate for the TV's self-signed TLS certificate
  KeychainStore.swift               # iOS Keychain storage for client-key + UserDefaults for last TV IP / MAC
  SubnetScanner.swift               # Non-blocking TCP port 3001/3000 /24 subnet scanner
  WakeOnLAN.swift                   # 102-byte UDP broadcast magic packet builder and sender
Data/
  Channel.swift                     # SwiftData @Model with satellite metadata, favorites, and recents
  ChannelRepository.swift           # TV sync, non-destructive upsert, stale-channel pruning, tune & verify
Search/
  ArabicNormalizer.swift            # Tashkeel/tatweel stripping, Arabic letter unification, digit folding
  SearchEngine.swift                # Deterministic ranked search across channel numbers and names
Features/
  Connect/ConnectView.swift         # IP entry, subnet discovery, pairing status, Local Network recovery, WoL
  Channels/ChannelListView.swift    # Instant search, TV/Radio/HD/Favorites/Satellite filters, Recents, context menu
  NowPlaying/NowPlayingBar.swift    # Persistent bottom bar showing live tuned channel
  Remote/RemoteControlView.swift    # D-Pad, Guide/Info/Exit, Volume, Mute, Channel +/-, External Inputs, Power Off
  Shortcuts/TuneChannelIntent.swift # AppIntent for Siri & Shortcuts integration
  Widgets/FavoriteChannelsWidget.swift # WidgetKit views & TimelineProvider (add a Widget Extension + App Group to deploy)
  Settings/SettingsView.swift       # Sync channels, switch TV, clear cache, Wake-on-LAN, re-pair, forget TV
Tests/
  ArabicNormalizerTests.swift
  SearchEngineTests.swift
  SSAPMessageTests.swift
  ChannelRepositoryTests.swift
  Mocks/MockTVClient.swift          # Actor mock for unit tests & --mock-tv preview mode
  Fixtures/                         # Sanitized SSAP JSON responses captured from real LG webOS hardware
```

---

## Security & Privacy

- **Zero Cloud / Zero Telemetry**: All communication occurs strictly over your local LAN directly between your iPhone and your LG TV.
- **Keychain Credential Storage**: Pairing `client-key` tokens are stored in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **Host-Scoped TLS Trust**: LG webOS TVs serve a self-signed certificate on `wss://<tv-ip>:3001`. `TrustDelegate` scopes certificate acceptance strictly to the user-configured TV host and defers all other hosts to standard system TLS evaluation.
- **Log Redaction**: Debug frame logging is compiled only in `#if DEBUG` builds and passes every frame through `SSAPRedactor` so `client-key` values are never printed.

---

## LG webOS SSAP Protocol Notes

Verified against real LG webOS hardware (`webOS 6.x+`):
1. **32 MB WebSocket Frame Limit**: A full satellite channel list (`ssap://tv/getChannelList`) with ~2,800 channels is ~2.3 MB of compact JSON over the wire. Apple's `URLSessionWebSocketTask.maximumMessageSize` defaults to **1 MB** and fails with `POSIXError 40 (EMSGSIZE)` unless raised (`TVClient` configures `32 MB`).
2. **Dual Endpoint Fallback (`ws:3000` / `wss:3001`)**: Older webOS releases accept cleartext `ws://:3000` immediately, while newer webOS firmware (`webOS 23+`) enforces `wss://:3001` with a self-signed certificate. `TVClient` probes both automatically.
3. **Unique `channelId` vs. Duplicate `channelNumber`**: Satellite TV and Satellite Radio lineups frequently reuse channel numbers (e.g., TV `1` and Radio `1`). Always key persistence and `ssap://tv/openChannel` requests by `channelId`, using `channelNumber` only as a fallback.
4. **Payload Key Differences**: `getChannelList` returns `channelMode` / `channelType`, whereas `getCurrentChannel` returns `channelModeName` / `channelTypeName`.

---

## License

Released under the [MIT License](./LICENSE).
