# Sippy build helper — works with Command Line Tools only (no Xcode).
#
# Four CLT/SDK quirks are handled here:
#  1. linphone.framework references @rpath/libhidapi.0.dylib but the linphone
#     macOS SDK doesn't ship it (their packaging bug). `make deps` builds it
#     from source; build targets copy it next to the frameworks in .build/.
#  2. The prebuilt SDK has no G.729 codec. `make deps` builds libmsbcg729.so
#     (bcg729 + mediastreamer2's g729.c filter, sources in Vendor/msbcg729/)
#     as a mediastreamer2 plugin. mediastreamer2 only scans for libms*.so, so
#     the plugin must keep the .so extension.
#  3. From the macOS 27 SDK on, SwiftUI's @State is a macro whose compiler
#     plugin (SwiftUIMacros) ships only with Xcode, not the CLT. The views
#     use @ViewState instead (Sources/SippyApp/Views/ViewState.swift), an
#     alias of the same State property wrapper that bypasses the macro.
#  4. SwiftPM 6.4's build system finds the CLT's Testing.framework on its own,
#     but hands the compiler only the macro plugins in the top-level plugins
#     dir; Testing's sits in plugins/testing/, so @Test/@Suite fail with
#     "plugin for module 'TestingMacros' not found". `make test` loads it
#     explicitly. Full Xcode (e.g. on CI) doesn't need this.
#
# Build products aren't at a fixed path: SwiftPM 6.4's default build system
# (swiftbuild) writes them to .build/out/Products/<Config>, the older native
# one to .build/<triple>/<config>, and a tree used by both keeps a stale copy
# of the other. BUILD_DIR/DEPS_BUILD_DIR therefore come from
# `swift build --show-bin-path`, run with the same flags as the build
# (SWIFTPM_FLAGS, e.g. SWIFTPM_FLAGS="--build-system native").

CLT := /Library/Developer/CommandLineTools
TESTING_MACROS := $(CLT)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT))
TEST_FLAGS ?= $(if $(wildcard $(TESTING_MACROS)),-Xswiftc -load-plugin-library -Xswiftc $(TESTING_MACROS))
else
TEST_FLAGS ?=
endif

# CONFIG=release for optimized builds (make app CONFIG=release, make release).
CONFIG ?= debug
# Extra flags for every swift build/test; also used to locate the products.
SWIFTPM_FLAGS ?=

# SwiftPM's bin dir for a config (relative to the repo when inside it).
# Fails loudly rather than letting recipes run with an empty path.
bin_path = $(patsubst $(CURDIR)/%,%,$(or $(shell swift build -c $(1) $(SWIFTPM_FLAGS) \
    --show-bin-path 2>/dev/null),$(error `swift build -c $(1) --show-bin-path` failed)))
# Evaluated once, on first use (most targets never need them).
BUILD_DIR = $(eval BUILD_DIR := $(call bin_path,$(CONFIG)))$(BUILD_DIR)
# Expand after the build so the bundled frameworks match the executable's slices.
app_archs = $(or $(shell lipo -archs "$(BUILD_DIR)/Sippy"),$(error Could not read Sippy's architectures))
# deps artifacts are config-independent; always built against the debug
# frameworks (which `swift build` fetches first).
DEPS_BUILD_DIR = $(eval DEPS_BUILD_DIR := $(call bin_path,debug))$(DEPS_BUILD_DIR)
CHECKOUTS := .build/checkouts-manual
HIDAPI := Vendor/lib/libhidapi.0.dylib
MSBCG729 := Vendor/lib/libmsbcg729.so

APP := dist/Sippy.app
# Sippy.icon is the editable source. AppIcon.png is the full-bleed raster
# master used to generate the ICNS with Command Line Tools.
ICON_MASTER := Support/AppIcon.png
ICONSET := .build/Sippy.iconset
ICON := .build/AppIcon.icns

# Release signing. Default is ad-hoc; pass IDENTITY="Developer ID
# Application: …" for distribution. The hardened runtime enables library
# validation, which needs every framework signed by the same Team ID — ad-hoc
# signatures have none, so hardening only goes with a real identity (where
# our inside-out re-sign puts one team on everything, our dlopen'd G.729
# plugin included).
IDENTITY ?= -
ifeq ($(IDENTITY),-)
SIGN_FLAGS :=
else
SIGN_FLAGS := --options runtime --timestamp
endif
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)
ZIP := dist/Sippy-$(VERSION).zip
NOTARY_PROFILE ?= sippy

.PHONY: build test spike-codecs deps app run-app release notarize clean

build: deps
	swift build -c $(CONFIG) $(SWIFTPM_FLAGS)
	cp -f $(HIDAPI) $(BUILD_DIR)/

test:
	swift test --filter SippyCoreTests $(SWIFTPM_FLAGS) $(TEST_FLAGS)

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

# Needs the SDK frameworks (headers) in $(DEPS_BUILD_DIR) — `swift build`
# fetches them, hence the bootstrap build without the plugin present.
$(MSBCG729):
	mkdir -p Vendor/lib $(CHECKOUTS)
	test -d $(DEPS_BUILD_DIR)/mediastreamer2.framework || swift build $(SWIFTPM_FLAGS)
	test -d $(CHECKOUTS)/bcg729 || git clone --depth 1 \
	    https://github.com/BelledonneCommunications/bcg729.git $(CHECKOUTS)/bcg729
	clang -dynamiclib -O2 \
	    -I$(CHECKOUTS)/bcg729/include -I$(CHECKOUTS)/bcg729/src \
	    $(CHECKOUTS)/bcg729/src/*.c \
	    Vendor/msbcg729/g729.c Vendor/msbcg729/msbcg729_plugin_init.c \
	    -F$(DEPS_BUILD_DIR) -framework mediastreamer2 -framework ortp -framework bctoolbox \
	    -install_name @rpath/libmsbcg729.so \
	    -o $(MSBCG729)

# Assembles a runnable Sippy.app without Xcode: SPM binary + SDK frameworks +
# our plugin dylibs + Info.plist, ad-hoc signed. The extra rpath makes the
# bundle self-contained; SwiftPM's own rpaths (@loader_path, and with
# swiftbuild an absolute $(BUILD_DIR)/PackageFrameworks that stays empty for
# this package) stay for running the bare binary from $(BUILD_DIR).
# macOS 26 masks app icons into its squircle itself, but only fully opaque
# full-bleed artwork qualifies. Zoom-crop any rounded master to full bleed
# so the system can apply its own rounding.
FULLBLEED := .build/AppIcon-fullbleed.png

$(FULLBLEED): $(ICON_MASTER) Tools/make_fullbleed_icon.swift
	mkdir -p .build
	swift Tools/make_fullbleed_icon.swift $(ICON_MASTER) $(FULLBLEED)

$(ICON): $(FULLBLEED)
	rm -rf $(ICONSET)
	mkdir -p $(ICONSET)
	sips -z 16 16 $(FULLBLEED) --out $(ICONSET)/icon_16x16.png
	sips -z 32 32 $(FULLBLEED) --out $(ICONSET)/icon_16x16@2x.png
	sips -z 32 32 $(FULLBLEED) --out $(ICONSET)/icon_32x32.png
	sips -z 64 64 $(FULLBLEED) --out $(ICONSET)/icon_32x32@2x.png
	sips -z 128 128 $(FULLBLEED) --out $(ICONSET)/icon_128x128.png
	sips -z 256 256 $(FULLBLEED) --out $(ICONSET)/icon_128x128@2x.png
	sips -z 256 256 $(FULLBLEED) --out $(ICONSET)/icon_256x256.png
	sips -z 512 512 $(FULLBLEED) --out $(ICONSET)/icon_256x256@2x.png
	sips -z 512 512 $(FULLBLEED) --out $(ICONSET)/icon_512x512.png
	cp $(FULLBLEED) $(ICONSET)/icon_512x512@2x.png
	iconutil -c icns $(ICONSET) -o $(ICON)
	rm -rf $(ICONSET)

app: build $(ICON)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Frameworks $(APP)/Contents/Resources
	cp $(BUILD_DIR)/Sippy $(APP)/Contents/MacOS/
	@# Sparkle is a binary SPM artifact; SwiftPM leaves it under .build/artifacts.
	set -e; \
	sparkle_fw=$$(find .build/artifacts -type d -name Sparkle.framework -path '*macos*' 2>/dev/null | head -1); \
	for framework in "$(BUILD_DIR)"/*.framework "$$sparkle_fw"; do \
	    [ -n "$$framework" ] || continue; \
	    ditto $(foreach arch,$(app_archs),--arch $(arch)) "$$framework" "$(APP)/Contents/Frameworks/$${framework##*/}"; \
	done
	cp Vendor/lib/libhidapi.0.dylib Vendor/lib/libmsbcg729.so $(APP)/Contents/Frameworks/
	@# The linphone frameworks ship a Modules -> Versions/Current/Modules
	@# link with no Modules directory behind it (only compiling against a
	@# framework needs one). Links to nothing are dead weight, and
	@# `xattr -r` and friends trip over them, so drop any in the bundle.
	find $(APP)/Contents/Frameworks -type l ! -exec test -e {} \; -print -delete
	cp Support/Info.plist $(APP)/Contents/
	cp $(ICON) $(APP)/Contents/Resources/
	cp -R Support/Ringtones $(APP)/Contents/Resources/Ringtones
	install_name_tool -add_rpath @executable_path/../Frameworks $(APP)/Contents/MacOS/Sippy
	@# ditto zips store names as UTF-8 without the zip "UTF-8" flag; unzip
	@# tools other than Apple's then guess the encoding, and a mangled name
	@# breaks the code signature ("Sippy is damaged"). Keep names ASCII.
	@bad=$$(cd $(APP) && find . | LC_ALL=C grep '[^ -~]'); \
	if [ -n "$$bad" ]; then \
	    echo "Non-ASCII file names in $(APP) (rename them):"; echo "$$bad"; exit 1; \
	fi
	@# Sign inside-out (nested code first) — required for the hardened runtime;
	@# --deep is deprecated and signs nested code with no flags.
	@# Code nested inside the frameworks goes first: loose plugins some SDK
	@# frameworks carry (mediastreamer2's Libraries/libmswebrtc.so ships
	@# unsigned) and Sparkle's helper processes, which come ad-hoc signed and
	@# are signed the way Sparkle's docs prescribe (Downloader keeps its
	@# entitlements). Notarization rejects any binary left unsigned or ad-hoc.
	find $(APP)/Contents/Frameworks -mindepth 2 -type f \
	    \( -name '*.so' -o -name '*.dylib' \) | \
	    while read -r item; do \
	        codesign --force $(SIGN_FLAGS) --sign "$(IDENTITY)" "$$item" || exit 1; \
	    done
	sparkle=$(APP)/Contents/Frameworks/Sparkle.framework/Versions/Current; \
	if [ -d "$$sparkle" ]; then \
	    codesign --force $(SIGN_FLAGS) --sign "$(IDENTITY)" "$$sparkle/XPCServices/Installer.xpc" && \
	    codesign --force $(SIGN_FLAGS) --preserve-metadata=entitlements \
	        --sign "$(IDENTITY)" "$$sparkle/XPCServices/Downloader.xpc" && \
	    codesign --force $(SIGN_FLAGS) --sign "$(IDENTITY)" "$$sparkle/Autoupdate" && \
	    codesign --force $(SIGN_FLAGS) --sign "$(IDENTITY)" "$$sparkle/Updater.app" || exit 1; \
	fi
	find $(APP)/Contents/Frameworks -maxdepth 1 \
	    \( -name '*.framework' -o -name '*.dylib' -o -name '*.so' \) | \
	    while read -r item; do \
	        codesign --force $(SIGN_FLAGS) --sign "$(IDENTITY)" "$$item" || exit 1; \
	    done
	codesign --force $(SIGN_FLAGS) --entitlements Support/Sippy.entitlements \
	    --sign "$(IDENTITY)" $(APP)
	codesign --verify --deep --strict $(APP)
	@codesign --display --entitlements - --xml $(APP) | \
	    plutil -extract 'com\.apple\.security\.personal-information\.addressbook' raw -expect bool -o - - | \
	    grep -qx true || { echo "Missing Contacts entitlement in $(APP)"; exit 1; }
	@echo "Built $(APP) ($(CONFIG), identity: $(IDENTITY))"

run-app: app
	open $(APP)

# Optimized, signed, zipped for distribution. Ad-hoc unless IDENTITY is a
# Developer ID; see README "Release builds".
release:
	$(MAKE) app CONFIG=release IDENTITY="$(IDENTITY)"
	ditto -c -k --keepParent $(APP) $(ZIP)
	@echo "Release archive: $(ZIP)"

# Requires stored credentials:
#   xcrun notarytool store-credentials sippy --apple-id … --team-id … --password …
# or NOTARY_AUTH with an App Store Connect API key (what CI does):
#   make notarize NOTARY_AUTH="--key AuthKey_X.p8 --key-id X --issuer <uuid>"
# The status is checked explicitly, and Apple's log printed on rejection
# (it names the offending binary).
NOTARY_AUTH ?= --keychain-profile $(NOTARY_PROFILE)

notarize:
	@out=$$(xcrun notarytool submit $(ZIP) $(NOTARY_AUTH) --wait --output-format json) || \
	    { echo "$$out"; exit 1; }; \
	echo "$$out"; \
	status=$$(echo "$$out" | plutil -extract status raw -o - -); \
	if [ "$$status" != Accepted ]; then \
	    id=$$(echo "$$out" | plutil -extract id raw -o - -); \
	    xcrun notarytool log "$$id" $(NOTARY_AUTH); \
	    echo "Notarization status: $$status"; exit 1; \
	fi
	xcrun stapler staple $(APP)
	xcrun stapler validate $(APP)
	spctl --assess --type execute --verbose=2 $(APP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	@echo "Notarized and stapled: $(ZIP)"

clean:
	swift package clean
	rm -rf dist
