# Sippy

A native macOS SIP softphone, in the spirit of [Telephone](https://github.com/64characters/Telephone) plus the things it lacks: an internal contact store for PBX extensions, origin-aware dial prefixes, a live traffic/codec inspector with SIP/SDP tracing, G.729, and bundled ringtones.

Built with Swift 6 / SwiftUI on [liblinphone](https://linphone.org) 5.x. See [PLAN.md](PLAN.md) for the development plan and per-milestone findings.

## Features

- **Calling** — dialpad, mute/hold, DTMF, audio device selection, and call history with redial. In Settings → General → Incoming Calls, choose a themed floating window (the default) or a macOS notification to answer or decline while working in another app. Missed calls appear in Notification Center when notifications are enabled.
- **Media during incoming calls** — Sippy lowers other audio on the Mac’s default output while ringing and pauses the active macOS Now Playing session when you answer. Declining or missing the call restores the normal level as playback continues. After an answered call, you can resume playback in your player. One toggle in Settings → General → Incoming Calls controls both behaviors and is on by default.
- **Contacts** — Sippy's own store for PBX extensions (favorites, multiple numbers) merged with the system address book; caller-ID resolution checks both.
- **Origin-aware dial plan** — numbers arriving from outside the app (`tel:`/`callto:`/`sip:` links, the "Call with Sippy" Services menu entry, paste-and-dial ⇧⌘V) and from system contacts get your outside-line prefix (`0`, `0*4`, …); the dialpad and Sippy contacts dial verbatim.
- **Codecs** — reorderable per-codec priority list, defaults Opus → G.722 → G.711 → G.729. G.729 works even though the prebuilt linphone SDK omits it (see Vendored pieces).
- **Inspector** — per-call live stats (codec, encryption, ICE, RTT, jitter, loss, bandwidth sparklines) and a SIP Log window (⇧⌘L) with message capture, filtering, offered-vs-answered SDP codec view, and export.
- **Ringtones** — Notes of the Optimistic is the default, with Old Phone as its fallback. Settings also offers Entropy, Time Not Lost, custom imports and separate output selection for ringing. [Ringtone credits](Support/Ringtones/CREDITS.md)
- **Hold music** — pressing Hold during a call lets Linphone send *Don't Wait Too Long* to the other party. A PBX can supply its own hold music.
- **At home on macOS** — menu bar icon (click to open or close the main window, right-click for quick answer/hang-up, favorites speed-dial and Check for Updates), start at login, Dock/menu-bar presence choice, Window › Float on Top, re-registration on network change and wake.
- **Themes** — the main window is a single coloured pane taken from the app icon: three schemes (Enamel, Night Signal, Vivid), each dark or light or following the system, with the Dialpad / Contacts / History tabs in the title bar or as a bottom tab bar (Settings › General).
- **NAT traversal** — received/rport IP rewrite toggle, optional STUN/ICE.
- **VPN-aware registration** (opt-in) — when the route to the PBX disappears, Sippy stops SIP polling as soon as any current call has finished. It watches macOS network changes and registers again when the route returns. Private server addresses need a specific VPN or LAN route.

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

`make release` produces `dist/Sippy-<version>.zip` from an optimized build, signing every nested binary (frameworks, plugins, Sparkle's helpers) and then the app, with the hardened runtime and `Support/Sippy.entitlements` when the identity is real. Ad-hoc signatures (the default) are fine locally; distribution needs a Developer ID certificate and notarization:

1. Install a "Developer ID Application" certificate in the keychain.
2. Store notary credentials once: `xcrun notarytool store-credentials sippy --apple-id you@example.com --team-id TEAMID --password <app-specific-password>` (or pass an App Store Connect API key with `NOTARY_AUTH="--key … --key-id … --issuer …"`).
3. `make release IDENTITY="Developer ID Application: Your Name (TEAMID)" && make notarize NOTARY_PROFILE=sippy`.

`make notarize` fails (and prints Apple's log) unless the submission is accepted, then staples the ticket, re-zips the app and checks it with `spctl`.

The version comes from `CFBundleShortVersionString` in `Support/Info.plist`.

### CI

`.github/workflows/build.yml` runs on a GitHub macOS runner with full Xcode. On every pull request it runs `make test` and `make release`, then uploads the ad-hoc signed zip as a workflow artifact (kept 14 days) so the PR can be tried without a local toolchain. Publishing a GitHub release builds the same way but signs with the Developer ID certificate, notarizes and staples, then attaches `Sippy-<version>.zip` and the Sparkle `appcast.xml` to the release; the tag (`v0.1.0` or `0.1.0`) must match the Info.plist version. It can also be started by hand from the Actions tab, ticking "sign" for a signed and notarized build without a release.

PR builds are ad-hoc signed, so macOS quarantines them after download: after unzipping, clear the flag with `xattr -dr com.apple.quarantine Sippy.app` (or right-click → Open). Release builds open normally.

#### Signing on CI

The signing secrets live in a GitHub environment named `release` (Settings → Environments), limited to the `main` branch and release tags (`v*` and `[0-9]*`) so pull requests can't reach them:

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | The Developer ID Application certificate with its private key, exported as .p12, base64-encoded (`base64 -i cert.p12`) |
| `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the .p12 |
| `NOTARY_API_KEY` | Contents of the App Store Connect API key file (`AuthKey_XXXXXXXXXX.p8`) |
| `NOTARY_API_KEY_ID` | That key's Key ID |
| `NOTARY_API_ISSUER_ID` | The Issuer ID shown above the keys list in App Store Connect |
| `SPARKLE_ED_PRIVATE_KEY` | The Sparkle update signing key, see [Sparkle updates](#sparkle-updates) |

The job imports the certificate into a throwaway keychain, picks the Developer ID identity from it, and deletes the keychain at the end.

### Sparkle updates

The app updates itself with [Sparkle](https://sparkle-project.org). `SUFeedURL` in `Support/Info.plist` points at `releases/latest/download/appcast.xml`, which GitHub redirects to the `appcast.xml` attached to the newest release; every published release attaches one, written by `Tools/make_appcast.sh` on CI. It holds a single item (the release's zip, its EdDSA signature, the release notes rendered to HTML), since installed copies only need the newest version.

Updates never take focus on their own: when a daily check finds a new version, Sippy posts a notification instead of opening Sparkle's window, and clicking the notification (or Check for Updates… in the app menu or the menu bar icon's menu) opens it. Relaunching into an installed update waits until no call is in progress. See `Sources/SippyApp/UpdateController.swift`.

Updates are signed with an EdDSA key: the public half is `SUPublicEDKey` in `Support/Info.plist`, the private half the `SPARKLE_ED_PRIVATE_KEY` secret in the `release` environment (kept in the maintainer's login keychain under the `sippy` account and in the team password manager). `make_appcast.sh` refuses to sign with a private key that doesn't match `SUPublicEDKey`. Losing the private key means installed copies can't be updated any more, short of reinstalling by hand. To set it up again:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account sippy        # prints the public key
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account sippy -x key # exports the private key
gh secret set SPARKLE_ED_PRIVATE_KEY --env release < key && rm key
```

A build without `SUFeedURL` (or with it empty) runs without the updater.

## PBX test matrix

`Tools/pbx-test/run.sh` spins up an Asterisk container (Docker required), registers the spike against it, places a call to an echo extension, and verifies the negotiated codec — see the script for the config it uses. Tested against Asterisk (container) and KalliopePBX 4.x (real hardware, UDP + VPN).

## Vendored pieces (and why)

- `Vendor/linphone-sdk-swift-macos/` — the official linphone Swift package 5.5.16, mirrored from download.linphone.org (their GitLab was down at setup time). Sippy’s manifest omits the OpenH264 stub and the SDK’s test framework. The binary xcframeworks still download from linphone's server on first build.
- `Vendor/msbcg729/` — mediastreamer2's `g729.c` filter (AGPL, from the mediastreamer2 repo) plus our tiny plugin-init shim. The prebuilt SDK ships **without** G.729; `make deps` compiles these together with [bcg729](https://github.com/BelledonneCommunications/bcg729) into `Vendor/lib/libmsbcg729.so`, which liblinphone loads as a mediastreamer2 plugin. The `.so` extension is required — mediastreamer2 only scans for `libms*.so`.
- `Vendor/lib/libhidapi.0.dylib` — built by `make deps` from [libusb/hidapi](https://github.com/libusb/hidapi); linphone.framework references it but the linphone macOS SDK forgets to ship it.

## License

[AGPLv3](LICENSE) — required by liblinphone 5.x (AGPL) and the vendored mediastreamer2 G.729 filter.
