# Sippy build helper — works with Command Line Tools only (no Xcode).
#
# Three CLT/SDK quirks are handled here:
#  1. linphone.framework references @rpath/libhidapi.0.dylib but the linphone
#     macOS SDK doesn't ship it (their packaging bug). `make deps` builds it
#     from source; build targets copy it next to the frameworks in .build/.
#  2. The prebuilt SDK has no G.729 codec. `make deps` builds libmsbcg729.so
#     (bcg729 + mediastreamer2's g729.c filter, sources in Vendor/msbcg729/)
#     as a mediastreamer2 plugin. mediastreamer2 only scans for libms*.so, so
#     the plugin must keep the .so extension.
#  3. CLT ships Testing.framework off the default search paths, and its
#     interop dylib in yet another directory, so `swift test` needs explicit
#     -F/-rpath flags.

CLT := /Library/Developer/CommandLineTools
TESTING_FW := $(CLT)/Library/Developer/Frameworks
TESTING_LIB := $(CLT)/Library/Developer/usr/lib
TEST_FLAGS := -Xswiftc -F$(TESTING_FW) -Xlinker -F$(TESTING_FW) \
              -Xlinker -rpath -Xlinker $(TESTING_FW) \
              -Xlinker -rpath -Xlinker $(TESTING_LIB)

BUILD_DIR := .build/arm64-apple-macosx/debug
CHECKOUTS := .build/checkouts-manual
HIDAPI := Vendor/lib/libhidapi.0.dylib
MSBCG729 := Vendor/lib/libmsbcg729.so

APP := dist/Sippy.app
ICON_MASTER := Support/AppIcon.png
ICONSET := .build/Sippy.iconset
ICON := .build/AppIcon.icns

.PHONY: build test spike-codecs deps app run-app clean

build: deps
	swift build
	cp -f $(HIDAPI) $(BUILD_DIR)/

test:
	swift test --filter SippyCoreTests $(TEST_FLAGS)

spike-codecs: build
	$(BUILD_DIR)/sippy-spike codecs

deps: $(HIDAPI) $(MSBCG729)

$(HIDAPI):
	mkdir -p Vendor/lib $(CHECKOUTS)
	test -d $(CHECKOUTS)/hidapi || git clone --depth 1 --branch hidapi-0.15.0 \
	    https://github.com/libusb/hidapi.git $(CHECKOUTS)/hidapi
	clang -dynamiclib -O2 \
	    -I$(CHECKOUTS)/hidapi/hidapi $(CHECKOUTS)/hidapi/mac/hid.c \
	    -framework IOKit -framework CoreFoundation \
	    -install_name @rpath/libhidapi.0.dylib \
	    -compatibility_version 0 -current_version 0.15.0 \
	    -o $(HIDAPI)

# Needs the SDK frameworks (headers) in $(BUILD_DIR) — `swift build` fetches
# them, hence the bootstrap build without the plugin present.
$(MSBCG729):
	mkdir -p Vendor/lib $(CHECKOUTS)
	test -d $(BUILD_DIR)/mediastreamer2.framework || swift build
	test -d $(CHECKOUTS)/bcg729 || git clone --depth 1 \
	    https://github.com/BelledonneCommunications/bcg729.git $(CHECKOUTS)/bcg729
	clang -dynamiclib -O2 \
	    -I$(CHECKOUTS)/bcg729/include -I$(CHECKOUTS)/bcg729/src \
	    $(CHECKOUTS)/bcg729/src/*.c \
	    Vendor/msbcg729/g729.c Vendor/msbcg729/msbcg729_plugin_init.c \
	    -F$(BUILD_DIR) -framework mediastreamer2 -framework ortp -framework bctoolbox \
	    -install_name @rpath/libmsbcg729.so \
	    -o $(MSBCG729)

# Assembles a runnable Sippy.app without Xcode: SPM binary + SDK frameworks +
# our plugin dylibs + Info.plist, ad-hoc signed. The extra rpath makes the
# bundle self-contained; the SPM build-dir rpath stays for dev convenience.
$(ICON): $(ICON_MASTER)
	rm -rf $(ICONSET)
	mkdir -p $(ICONSET)
	sips -z 16 16 $(ICON_MASTER) --out $(ICONSET)/icon_16x16.png
	sips -z 32 32 $(ICON_MASTER) --out $(ICONSET)/icon_16x16@2x.png
	sips -z 32 32 $(ICON_MASTER) --out $(ICONSET)/icon_32x32.png
	sips -z 64 64 $(ICON_MASTER) --out $(ICONSET)/icon_32x32@2x.png
	sips -z 128 128 $(ICON_MASTER) --out $(ICONSET)/icon_128x128.png
	sips -z 256 256 $(ICON_MASTER) --out $(ICONSET)/icon_128x128@2x.png
	sips -z 256 256 $(ICON_MASTER) --out $(ICONSET)/icon_256x256.png
	sips -z 512 512 $(ICON_MASTER) --out $(ICONSET)/icon_256x256@2x.png
	sips -z 512 512 $(ICON_MASTER) --out $(ICONSET)/icon_512x512.png
	cp $(ICON_MASTER) $(ICONSET)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET) -o $(ICON)
	rm -rf $(ICONSET)

app: build $(ICON)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Frameworks $(APP)/Contents/Resources
	cp .build/arm64-apple-macosx/debug/Sippy $(APP)/Contents/MacOS/
	cp -R .build/arm64-apple-macosx/debug/*.framework $(APP)/Contents/Frameworks/
	cp Vendor/lib/libhidapi.0.dylib Vendor/lib/libmsbcg729.so $(APP)/Contents/Frameworks/
	cp Support/Info.plist $(APP)/Contents/
	cp $(ICON) $(APP)/Contents/Resources/
	install_name_tool -add_rpath @executable_path/../Frameworks $(APP)/Contents/MacOS/Sippy
	codesign --force --deep --sign - $(APP)
	@echo "Built $(APP)"

run-app: app
	open $(APP)

clean:
	swift package clean
	rm -rf dist
