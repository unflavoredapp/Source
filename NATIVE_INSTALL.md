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

Same flow as [`unflavoredapp/Random`](https://github.com/unflavoredapp/Random) `build.sh`:

```bash
./build.sh          # fetch/integrate IDeviceKit → rust XCFramework → xcodebuild archive
                    # → ad-hoc entitlement stamp on UNlicense + APPDeviceTunnel → UNlicense.ipa
make                # wraps ./build.sh
SKIP_NATIVE=1 ./build.sh          # skip kit rebuild (needs a prior IDeviceKit)
ADHOC_ENTITLEMENTS=0 ./build.sh   # omit ad-hoc codesign (re-signers won't see NE entitlement)
```

CI (`.github/workflows/ios.yml`) mirrors Random: macos-15, idevice + cargo + DerivedData caches, `./build.sh`, verifies `APPDeviceTunnel.appex` and no `embedded.mobileprovision`.

## Requirements (device)

- App + appex signed with the same team and matching bundle-id prefix.
- Provisioning profile allows **Network Extensions → packet-tunnel-provider**.
- Built-in pairing: iOS 27+, Developer Mode, Local Network permission, one-time PIN.
- Older iOS: Manual Setup — import `pairingFile.plist` in Settings › Install Method.
