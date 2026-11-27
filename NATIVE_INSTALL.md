# Native install (VPN + idevice)

Source already installs signed IPAs over **OTA** (`itms-services` via `SigningOTAInstaller` / `LocalInstallServer`).

**Native install** delivers the IPA straight to this device through a local packet-tunnel VPN and idevice pairing — the same approach as AppAssassin ([`unflavoredapp/Random`](https://github.com/unflavoredapp/Random)).

## Status

| Piece | State |
| --- | --- |
| Settings › Install Method (OTA / Native) | Done |
| `SigningInstaller` routes to Native when selected (falls back to OTA if not ready) | Done |
| Pairing Keychain store | Done |
| Local VPN controller | Done |
| `APPDeviceTunnel` packet-tunnel sources | Done |
| `APPDeviceTunnel` Xcode target + embed in APP | Done |
| IDeviceKit fetch / patch / build scripts | Done under `.github/scripts/` |
| `Native/Device` idevice overlays | Vendored from Random |
| Link IDeviceKit / IDeviceSwift into `APP.xcodeproj` | **Next** |
| On-device pairing UX (iOS 27+) / Manual pairing file import | **Next** |
| Full `DeviceInstallationManager` install/uninstall | **Next** |

The tunnel appex now embeds with APP. Native install still needs IDeviceKit linked before `NativeInstaller.isStackReady` becomes true; until then installs fall back to OTA.

## What to wire next (from Random)

1. Run `python3 .github/scripts/fetch_devicekit.py` then patch/integrate/build (`build_device_native.py`) to produce `IDeviceKit` + `IDevice.xcframework`.
2. Add an `APPDeviceTunnel` Network Extension target (sources in `APPDeviceTunnel/`, entitlements `APPDeviceTunnel.entitlements`).
3. Embed the appex in the APP target; link local packages `IDeviceSwift` + `IDevice`.
4. Port `DeviceInstallationManager` / `NativeInstaller` install path from Random’s `Sources/Device/*` (adapt AirShare types to Source’s `SigningIPAInfo`).
5. Sign app + appex with a profile that allows **Network Extensions → packet-tunnel-provider**.

## Requirements (device)

- App + appex signed with the same team and matching bundle-id prefix.
- Built-in pairing: iOS 27+, Developer Mode, Local Network permission, one-time PIN.
- Older iOS: Manual Setup with an imported `pairingFile.plist`.

## Build notes

Unsigned `make` / CI IPA builds stay OTA-only until the extension target is added. Ad-hoc signing can preserve the NE entitlement request for later re-sign (same pattern as Random’s `build-unsigned-ipa.yml`).
