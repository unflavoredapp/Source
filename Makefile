BASEDIR = $(shell pwd)

.PHONY: all ipa native-device clean

all: ipa

# Same entry point as Random: ./build.sh (native kit + archive + ad-hoc NE entitlements).
ipa:
	@chmod +x ./build.sh
	./build.sh

# Fetch/build IDeviceKit only (also runs inside build.sh unless SKIP_NATIVE=1).
native-device:
	@toolchain=$$(python3 -c 'import json;print(json.load(open("Native/Device/source.json"))["rust_toolchain"])'); \
	  if command -v rustup >/dev/null 2>&1; then \
	    rustup toolchain install "$$toolchain" --profile minimal; \
	  fi
	python3 .github/scripts/fetch_devicekit.py
	python3 .github/scripts/integrate_devicekit.py
	python3 .github/scripts/build_device_native.py

clean:
	rm -rf build UNlicense.ipa
