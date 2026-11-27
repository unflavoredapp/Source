# Native install (VPN + idevice)

Source installs signed IPAs over **OTA** by default (`itms-services` via `SigningOTAInstaller` / `LocalInstallServer`).

**Native install** delivers the IPA straight to this device through a local packet-tunnel VPN and idevice pairing — the same approach as AppAssassin / TetherLess ([`unflavoredapp/Random`](https://github.com/unflavoredapp/Random)).

## Status

| Piece | State |
| --- | --- |
| Settings › Install Method (OTA / Native) | Done |
| `SigningInstaller` routes to Native when selected (falls back to OTA if not ready) | Done |
| Pairing Keychain store + Manual `pairingFile.plist` import | Done |
| Built-in / Manual connection mode | Done |
| `LocalDeviceVPN` + `APPDeviceTunnel` appex (embedded) | Done |
| IDeviceKit fetch / integrate / `build_device_native` | Done (`make native-device`) |
| `IDevice` + `IDeviceSwift` linked in `APP.xcodeproj` | Done |
| `DeviceInstallationManager` + real `NativeInstaller` | Done |
| On-device pairing (iOS 27+ via `DevicePairingService`) | Done |

## Build

```bash
make            # fetches IDeviceKit, builds XCFramework (needs rustup), then unsigned IPA
make SKIP_NATIVE=1 ipa   # skip native prep (package resolve will fail without IDeviceKit)
```

CI (`.github/workflows/ios.yml`) caches `.build/device-native` and `IDeviceKit/.build/IDevice.xcframework`, then runs `make` and verifies `APPDeviceTunnel.appex` is inside the IPA.

## Requirements (device)

- App + appex signed with the same team and matching bundle-id prefix.
- Provisioning profile allows **Network Extensions → packet-tunnel-provider**.
- Built-in pairing: iOS 27+, Developer Mode, Local Network permission, one-time PIN.
- Older iOS: Manual Setup — import `pairingFile.plist` in Settings › Install Method.
