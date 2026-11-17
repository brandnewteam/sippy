# Sippy

A native macOS SIP softphone, in the spirit of [Telephone](https://github.com/64characters/Telephone) plus the things it lacks: an internal contact store for PBX extensions, origin-aware dial prefixes, a live traffic/codec inspector with SIP/SDP tracing, G.729, and bundled ringtones.

Built with Swift 6 / SwiftUI on [liblinphone](https://linphone.org) 5.x. See [PLAN.md](PLAN.md) for the development plan and per-milestone findings.

## Features

- **Calling** — dialpad, mute/hold, DTMF, audio device selection, call history with redial, incoming/outgoing call UI.
- **Contacts** — Sippy's own store for PBX extensions (favorites, multiple numbers) merged with the system address book; caller-ID resolution checks both.
- **Origin-aware dial plan** — numbers arriving from outside the app (`tel:`/`callto:`/`sip:` links, the "Call with Sippy" Services menu entry, paste-and-dial ⇧⌘V) and from system contacts get your outside-line prefix (`0`, `0*4`, …); the dialpad and Sippy contacts dial verbatim.
- **Codecs** — reorderable per-codec priority list, defaults Opus → G.722 → G.711 → G.729. G.729 works even though the prebuilt linphone SDK omits it (see Vendored pieces).
- **Inspector** — per-call live stats (codec, encryption, ICE, RTT, jitter, loss, bandwidth sparklines) and a SIP Log window (⇧⌘L) with message capture, filtering, offered-vs-answered SDP codec view, and export.
- **Ringtones** — six bundled synthesized ringtones (public domain, regenerable via `Tools/make_ringtones.py`), custom import, and ring-device routing (ring on speakers, talk on headset).
- **At home on macOS** — menu bar extra with quick answer/hang-up and favorites speed-dial, start at login, Dock/menu-bar presence choice, re-registration on network change and wake.
- **NAT traversal** — received/rport IP rewrite toggle, optional STUN/ICE.
- **VPN-aware registration** (opt-in) — register only while a route to the server exists. For PBXes reached over a VPN: no timeout noise while the tunnel is down, instant re-register when it comes up. Private server addresses need a specific (VPN-pushed or LAN) route; the catch-all default route doesn't count.

## Building

Requires only the Xcode **Command Line Tools** (full Xcode not needed) and git. In SwiftUI views write `@ViewState` instead of `@State`: from the macOS 27 SDK on, `@State` is a macro whose compiler plugin only ships with full Xcode (see `Sources/SippyApp/Views/ViewState.swift`).

```sh
make deps      # one-time: builds libhidapi + the G.729 plugin (see below)
make test      # unit tests (dial plan, SDP/SIP parsing, codec prefs, …)
make app       # assemble dist/Sippy.app (debug, ad-hoc signed)
make run-app
```

### CLI spike (diagnostics)

`sippy-spike` is a throwaway CLI that talks to a PBX directly — useful for debugging:

```sh
make build
bin=$(swift build --show-bin-path)   # where SwiftPM put the products
$bin/sippy-spike codecs              # list codecs
$bin/sippy-spike register
$bin/sippy-spike call 124
$bin/sippy-spike receive             # wait for calls
```

The products directory depends on the SwiftPM build system: `.build/out/Products/Debug` with SwiftPM 6.4's default (swiftbuild), `.build/arm64-apple-macosx/debug` with the older native one. The Makefile asks `swift build --show-bin-path` rather than assuming either; pass `SWIFTPM_FLAGS` (e.g. `SWIFTPM_FLAGS="--build-system native"`) to build and locate products with different SwiftPM flags.

Credentials come from `SIPPY_DOMAIN`, `SIPPY_USER`, `SIPPY_PASSWORD` (or a local `.env`, see `.env.example`; real environment wins). Useful extras: `SIPPY_DEBUG=1` full SIP traces, `SIPPY_TRANSPORT=tcp|tls`, `SIPPY_CODECS=G729` to restrict offered codecs, `SIPPY_AUTOANSWER=<secs>` for `receive`.

## Release builds

```sh
make release                                   # optimized, ad-hoc signed zip
make release IDENTITY="Developer ID Application: …"   # properly signed
make notarize NOTARY_PROFILE=sippy             # submit to Apple + staple
```

`make release` produces `dist/Sippy-<version>.zip` from an optimized build, signing every nested framework/dylib and the app with the hardened runtime and `Support/Sippy.entitlements`. Ad-hoc signatures (the default) are fine locally; distribution needs a Developer ID certificate and notarization:

1. Install a "Developer ID Application" certificate in the keychain.
2. Store notary credentials once: `xcrun notarytool store-credentials sippy --apple-id you@example.com --team-id TEAMID --password <app-specific-password>`.
3. `make release IDENTITY="Developer ID Application: Your Name (TEAMID)" && make notarize NOTARY_PROFILE=sippy`.

The version comes from `CFBundleShortVersionString` in `Support/Info.plist`.

### CI

`.github/workflows/build.yml` runs on a GitHub macOS runner with full Xcode. On every pull request it runs `make test` and `make release`, then uploads the ad-hoc signed zip as a workflow artifact (kept 14 days) so the PR can be tried without a local toolchain. Publishing a GitHub release does the same and attaches `Sippy-<version>.zip` to the release; the tag (`v0.1.0` or `0.1.0`) must match the Info.plist version. It can also be started by hand from the Actions tab.

CI builds are ad-hoc signed, so macOS quarantines them after download: after unzipping, clear the flag with `xattr -dr com.apple.quarantine Sippy.app` (or right-click → Open).

### Sparkle updates

The app bundles [Sparkle](https://sparkle-project.org) and shows "Check for Updates…" in the app menu once a feed is configured. To enable updates: generate EdDSA keys with Sparkle's `generate_keys`, put the public key in `SUPublicEDKey` and the appcast URL in `SUFeedURL` (both in `Support/Info.plist`), and publish release zips plus an `appcast.xml` (GitHub Releases works well). With `SUFeedURL` empty the updater stays dormant.

## PBX test matrix

`Tools/pbx-test/run.sh` spins up an Asterisk container (Docker required), registers the spike against it, places a call to an echo extension, and verifies the negotiated codec — see the script for the config it uses. Tested against Asterisk (container) and KalliopePBX 4.x (real hardware, UDP + VPN).

## Vendored pieces (and why)

- `Vendor/linphone-sdk-swift-macos/` — the official linphone Swift package 5.5.16, mirrored from download.linphone.org (their GitLab was down at setup time). The binary xcframeworks still download from linphone's server on first build.
- `Vendor/msbcg729/` — mediastreamer2's `g729.c` filter (AGPL, from the mediastreamer2 repo) plus our tiny plugin-init shim. The prebuilt SDK ships **without** G.729; `make deps` compiles these together with [bcg729](https://github.com/BelledonneCommunications/bcg729) into `Vendor/lib/libmsbcg729.so`, which liblinphone loads as a mediastreamer2 plugin. The `.so` extension is required — mediastreamer2 only scans for `libms*.so`.
- `Vendor/lib/libhidapi.0.dylib` — built by `make deps` from [libusb/hidapi](https://github.com/libusb/hidapi); linphone.framework references it but the linphone macOS SDK forgets to ship it.

## License

[AGPLv3](LICENSE) — required by liblinphone 5.x (AGPL) and the vendored mediastreamer2 G.729 filter.
