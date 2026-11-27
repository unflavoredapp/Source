BASEDIR = $(shell pwd)

ifeq ($(CI),)
    RESOLVE_FLAGS = -disableAutomaticPackageResolution
endif

all: native-device ipa

# Fetch IDeviceKit overlays and build the idevice XCFramework (macOS + rustup).
# Skip with: make SKIP_NATIVE=1 ipa
.PHONY: native-device
native-device:
ifeq ($(SKIP_NATIVE),1)
	@echo "SKIP_NATIVE=1 — leaving IDeviceKit alone"
else
	@toolchain=$$(python3 -c 'import json;print(json.load(open("Native/Device/source.json"))["rust_toolchain"])'); \
	  if command -v rustup >/dev/null 2>&1; then \
	    rustup toolchain install "$$toolchain" --profile minimal; \
	  fi
	python3 .github/scripts/fetch_devicekit.py
	python3 .github/scripts/integrate_devicekit.py
	python3 .github/scripts/build_device_native.py
endif

ipa:
	@/bin/zsh -o pipefail -c 'xcodebuild -project APP.xcodeproj -scheme APP -configuration Release -sdk iphoneos -derivedDataPath build $(RESOLVE_FLAGS) CODE_SIGNING_ALLOWED=NO 2>&1 | tee /tmp/app_build.log'
	rm -rf build/Payload APP.ipa
	mkdir -p build/Payload
	ditto build/Build/Products/Release-iphoneos/APP.app build/Payload/APP.app
	cd build && zip -qry APP.ipa Payload
	mv build/APP.ipa ./

clean:
	rm -rf build APP.ipa
