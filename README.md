# SendLyra

**Share freely on your local network.** A serverless, encrypted,
cross-platform app for sharing files, folders, and messages.

SendLyra automatically discovers devices on the same local network and lets
you transfer files, folders, and text without using the internet. It runs on
its own LyraLink protocol and includes identity verification, PIN protection,
trusted-device controls, and transfer integrity checks. The code and protocol
are designed specifically for this project.

## Features

- **Automatic discovery** — devices on the same network appear within seconds
  using UDP multicast.
- **End-to-end encryption** — X25519 key exchange with ChaCha20-Poly1305;
  network observers cannot read transfer contents.
- **Multiple transfers** — concurrent jobs with progress, speed, and
  estimated remaining time.
- **Folder and multi-recipient transfers** — folder structure is preserved and
  files can be sent to multiple devices at once.
- **Resume support** — interrupted transfers continue from where they stopped.
- **Text sharing** — send plain-text messages alongside files.
- **PIN, approval, and trusted devices** — you control incoming transfers, with
  selectable quick-save approval modes.
- **QR pairing** — show your connection QR code so the other side can connect
  using your IP address.
- **Drag and drop** — drop files and folders directly into the desktop window.
- **TR / EN interface** — light and dark themes with four accent colors.
- **Fully local** — no data is sent to a server and no account is required.

## Architecture

```text
lib/
├── core/
│   ├── protocol/        # LyraLink protocol (discovery, channel, transfer)
│   ├── services/        # identity, settings, discovery, history, transfer
│   ├── models/          # device, selection, and transfer job models
│   └── utils/           # formatting, hashing, multicast, and path safety
└── ui/                  # theme, screens, and widgets (Material 3)
```

Protocol details: [docs/PROTOCOL.md](docs/PROTOCOL.md)

## Development

Requirements: [Flutter](https://docs.flutter.dev/get-started/install) 3.27+
(Dart 3.4+).

```bash
flutter pub get
flutter run            # connected device/emulator
flutter test           # unit and integration tests
flutter analyze        # static analysis
```

### Platform builds

| Platform | Command | Notes |
|---|---|---|
| Android | `flutter build apk --release` | Network permissions are defined in the manifest |
| iOS | `flutter build ios --release` | Requires a local-network access description |
| Windows | `flutter build windows --release` | Windows 10+ |
| macOS | `flutter build macos --release` | Requires local-network permission |
| Linux | `flutter build linux --release` | Requires GTK 3 development packages |

> **Firewall note:** allow UDP `47801` (discovery) and TCP `47802` (transfer)
> when prompted on first launch.

## Testing

```bash
flutter test
```

The unit and integration tests cover the HKDF test vector (RFC 5869), session
key agreement, frame sealing and opening, malformed-frame rejection, protocol
message JSON round trips, formatting helpers, PIN and fingerprint
verification, TOFU/trusted-device checks, and Windows path-safety vectors.

For a real two-device network test, run `flutter run` on both machines and
connect them to the same Wi-Fi/LAN network. The devices should discover each
other within a few seconds.

## License

All code in this project was written specifically for SendLyra. Add a
`LICENSE` file and choose a license (for example, Apache-2.0 or MIT) before
redistributing the project.
