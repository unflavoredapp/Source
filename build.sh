#!/usr/bin/env bash
#
# build.sh — produce an UNSIGNED .ipa from the APP Xcode project.
# Same shape as unflavoredapp/Random (TetherLess): archive with signing
# disabled, lift the .app out of the archive, ad-hoc entitlement-stamp the
# VPN appex so re-signers keep packet-tunnel-provider, zip Payload/.
#
set -uo pipefail   # NOT -e: failures are caught and explained below

APP_NAME="${APP_NAME:-UNlicense}"
SCHEME="${SCHEME:-APP}"
CONFIG="${CONFIG:-Release}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

PROJECT="$(ls -d ./*.xcodeproj 2>/dev/null | head -n1)"
if [ -z "$PROJECT" ]; then
  FOUND="$(find "$ROOT" -maxdepth 4 -type d -name '*.xcodeproj' -not -path '*/build/*' -not -path '*/.git/*' 2>/dev/null | head -n1)"
  if [ -n "$FOUND" ]; then ROOT="$(cd "$(dirname "$FOUND")" && pwd)"; cd "$ROOT"; PROJECT="./$(basename "$FOUND")"; fi
fi
if [ -z "$PROJECT" ]; then
  echo "ERROR: no .xcodeproj found under $ROOT."
  echo "Repo contents:"; ls -la "$ROOT"; find "$ROOT" -maxdepth 2 -not -path '*/.git/*' | head -80
  exit 1
fi

BUILD_DIR="build"
DERIVED="$BUILD_DIR/DerivedData"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
OUT="$BUILD_DIR/ipa"
LOG="$BUILD_DIR/xcodebuild.log"
# Keep /tmp/app_build.log for the existing CI "Upload build log" step.
cp_log() { cp -f "$LOG" /tmp/app_build.log 2>/dev/null || true; }

mkdir -p "$BUILD_DIR" "$OUT"
: > "$LOG"

hr() { printf '%s\n' "------------------------------------------------------------"; }

dump_errors() {
  echo ""; hr
  echo "BUILD FAILED (exit $1) — extracted errors:"; hr
  grep -nE "error:|fatal error:|\*\* .*FAILED \*\*|Undefined symbols?|linker command failed|No such module|cannot find |does not conform|Command .* failed|ambiguous|redeclaration" "$LOG" \
    | grep -v "^.*warning:" | tail -n 120 || echo "(no matching error lines — see full log below)"
  echo ""; echo "----- last 60 lines of $LOG -----"; tail -n 60 "$LOG"
  echo ""; echo "Full log saved at: $LOG"
  cp_log
}

run() {
  echo ""; echo "==> $*"
  ( "$@" ) 2>&1 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] || { dump_errors "$rc"; exit "$rc"; }
}

run_soft() {
  echo ""; echo "==> (soft) $*"
  ( "$@" ) 2>&1 | tee -a "$LOG"
  local rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] || echo "   (non-fatal: exited $rc, continuing)"
}

echo "==> Environment"
echo "    root    : $ROOT"
echo "    project : $PROJECT"
echo "    scheme  : $SCHEME ($CONFIG)"
xcodebuild -version 2>&1 | tee -a "$LOG" || true
echo "    swift   : $(swift --version 2>/dev/null | head -n1)"
echo "    sources : $(find APP APPDeviceTunnel -name '*.swift' 2>/dev/null | wc -l | tr -d ' ') swift"

# Quick brace sanity — catches pasted-tail junk before xcodebuild does.
while IFS= read -r f; do
  o=$(tr -cd '{' < "$f" | wc -c); c=$(tr -cd '}' < "$f" | wc -c)
  [ "$o" -eq "$c" ] || echo "    WARN brace mismatch in $f ({ $o vs } $c)"
done < <(find APP APPDeviceTunnel -name '*.swift' 2>/dev/null)

# Native device installer: fetch pinned IDeviceKit, apply overlays, build XCFramework.
if [ "${SKIP_NATIVE:-0}" != "1" ]; then
  echo ""; hr; echo "==> Native device library"; hr
  TOOLCHAIN="$(python3 -c 'import json;print(json.load(open("Native/Device/source.json"))["rust_toolchain"])')"
  if command -v rustup >/dev/null 2>&1; then
    run rustup toolchain install "$TOOLCHAIN" --profile minimal
  fi
  run python3 .github/scripts/fetch_devicekit.py
  run python3 .github/scripts/integrate_devicekit.py
  run python3 .github/scripts/build_device_native.py
fi

echo ""; echo "==> Schemes"
run_soft xcodebuild -list -project "$PROJECT"

if [ "${CLEAN_DERIVED:-0}" = "1" ]; then
  echo "==> CLEAN_DERIVED=1 — wiping $DERIVED"
  rm -rf "$DERIVED" 2>/dev/null || true
fi
mkdir -p "$DERIVED"
run_soft xcodebuild -project "$PROJECT" -scheme "$SCHEME" -resolvePackageDependencies \
  -derivedDataPath "$DERIVED" -skipPackagePluginValidation

ARCHIVE_ACTION="archive"
if [ "${CLEAN_DERIVED:-0}" = "1" ] || [ "${FORCE_XCODE_CLEAN:-0}" = "1" ]; then
  ARCHIVE_ACTION="clean archive"
fi
run xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED" \
  -skipMacroValidation -skipPackagePluginValidation \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" DEVELOPMENT_TEAM="" \
  $ARCHIVE_ACTION

APP_PATH="$(ls -d "$ARCHIVE"/Products/Applications/*.app 2>/dev/null | head -n1)"
[ -n "$APP_PATH" ] || { echo "ERROR: no .app inside $ARCHIVE"; dump_errors 1; exit 1; }
echo ""; echo "==> Built: $APP_PATH"

# Package: Payload/<App>.app → .ipa (no exportArchive — that needs a signing identity).
rm -rf "$OUT"; mkdir -p "$OUT/Payload"
cp -R "$APP_PATH" "$OUT/Payload/"
# Re-signers (zsign) need write access to every Mach-O (Xcode ships some mode 0555).
chmod -R u+rwX "$OUT/Payload"
find "$OUT/Payload" -name "_CodeSignature" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$OUT/Payload" -name "embedded.mobileprovision" -delete 2>/dev/null || true

# Native installer VPN needs packet-tunnel-provider on BOTH the app and the appex.
# Ad-hoc stamp entitlement files so re-signers can see and preserve the request.
APPEX="$(ls -d "$OUT"/Payload/*.app/PlugIns/APPDeviceTunnel.appex 2>/dev/null | head -n1)"
APP_ENTS="$ROOT/APP/Resources/APP.entitlements"
TUNNEL_ENTS="$ROOT/APPDeviceTunnel/APPDeviceTunnel.entitlements"
if [ -n "$APPEX" ]; then
  echo "==> Embedded tunnel extension: $APPEX"
  if [ "${ADHOC_ENTITLEMENTS:-1}" = "1" ]; then
    APPDIR="$(ls -d "$OUT"/Payload/*.app | head -n1)"
    while IFS= read -r b; do
      codesign --force --sign - --timestamp=none "$b" 2>&1 | tee -a "$LOG" || true
    done < <(find "$APPDIR" -depth \( -name '*.framework' -o -name '*.dylib' \) -not -path "$APPEX/*" 2>/dev/null)
    codesign --force --sign - --timestamp=none --entitlements "$TUNNEL_ENTS" "$APPEX" 2>&1 | tee -a "$LOG" || true
    codesign --force --sign - --timestamp=none --entitlements "$APP_ENTS" "$APPDIR" 2>&1 | tee -a "$LOG" || true
  fi
else
  echo "ERROR: APPDeviceTunnel.appex is not embedded — native install will not work."
  dump_errors 1
  exit 1
fi

( cd "$OUT" && zip -qry "$APP_NAME.ipa" Payload && rm -rf Payload )
cp -f "$OUT/$APP_NAME.ipa" "$ROOT/$APP_NAME.ipa"

if ! unzip -tq "$OUT/$APP_NAME.ipa" >/dev/null 2>&1; then echo "ERROR: IPA is not a valid zip"; exit 1; fi
unzip -l "$OUT/$APP_NAME.ipa" | grep -q "Payload/.*\.app/Info.plist" || { echo "ERROR: no Info.plist in IPA"; exit 1; }

cp_log
echo ""; hr
echo "SUCCESS — $OUT/$APP_NAME.ipa (also $ROOT/$APP_NAME.ipa)"
ls -lh "$OUT/$APP_NAME.ipa"
hr
