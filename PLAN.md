# Sippy — Development Plan

A native macOS SIP client in the spirit of [Telephone](https://github.com/64characters/Telephone), plus the features it lacks: internal contacts, configurable dial prefixes for externally-composed numbers, a traffic/codec inspector, G.729, and bundled ringtones.

## 1. Technology choices

### Language & UI: Swift 6 + SwiftUI (AppKit where needed)

Modern, first-class on macOS, and the SIP stack options below both have Swift-friendly integration paths. AppKit escape hatches (`NSViewRepresentable`, window management, menu bar extra) cover what SwiftUI can't do yet.

### SIP stack: liblinphone SDK (recommended), PJSIP as fallback

| | liblinphone SDK | PJSIP (pjsua2) |
|---|---|---|
| Swift integration | Official Swift Package for macOS ([linphone-sdk-swift-macos](https://gitlab.linphone.org/BC/public/linphone-sdk-swift-macos)), generated Swift API | C++ API; requires building an xcframework yourself + writing an Obj-C++ wrapper (this is what Telephone does) |
| API level | High-level: `Core`, `Account`, `Call`, `CallStats`, `AudioDevice` | Lower-level, more control, more code |
| G.729 | Built by the same company as bcg729; G.729 available in the SDK | Supports bcg729 as a G.729 backend (`PJMEDIA_HAS_BCG729`), but you compile/link it yourself |
| Call statistics | `CallStats` exposes codec, bandwidth, jitter, RTT, loss out of the box | RTCP stats available, more plumbing |
| License | GPLv3 (commercial license purchasable) | GPLv2+ (commercial license purchasable) |

**Recommendation:** liblinphone. It removes the two hardest chores (building the native stack, bridging C/C++ to Swift) and its `CallStats` API maps directly onto the traffic-inspector feature. Keep the SIP layer behind a protocol (`SIPEngine`) so a later swap to PJSIP is contained.

**Licensing consequence:** both viable stacks are copyleft — liblinphone 5.x is AGPLv3, PJSIP GPLv2+. Sippy is open source under AGPLv3. If a closed-source version ever matters, both vendors sell commercial licenses.

### Codec set & defaults

G.729's patents expired in 2017, so it is royalty-free — [bcg729](https://github.com/BelledonneCommunications/bcg729) is the open implementation.

Default enabled priority: **Opus → G.722 → G.711 (PCMU/PCMA) → G.729**. Rationale: Opus for quality when both ends support it, G.722 for HD on PBXs that have it, G.711 as the universal fallback, G.729 for low bandwidth. Everything else off by default; codec list reorderable/toggleable per account in settings.

## 2. Feature specs (the deltas vs. Telephone)

### 2.1 Internal contacts
- Own contact store (SwiftData): name, company, multiple numbers with labels — including bare PBX extensions like `204` — notes, favorite flag.
- System Contacts (Contacts.framework) shown alongside, read-only, merged in search/matching. Optional "import to Sippy" per contact.
- Caller-ID resolution on incoming calls checks internal store first, then system contacts.

### 2.2 Dial-plan / prefix rules
- The prefix applies based on where the number comes from, no length/pattern conditions needed:
  - **Prefixed:** numbers from outside the app (tel:/callto:/sip: URLs, Services menu "Call with Sippy", paste-and-dial) and numbers dialed from **system contacts** — both are by definition outside lines.
  - **Verbatim:** numbers typed on the in-app dialpad and Sippy's internal contacts (that's what the internal store is for — PBX extensions).
- Configurable prefix string per account — arbitrary, e.g. `0`, `9`, `0*4` — not hard-coded to a single digit.
- Normalization step (strip spaces, dashes, parentheses; optional `+` → international-prefix rewrite).
- This engine is pure Swift, no SIP dependency → the most unit-tested module in the app.

### 2.3 Traffic / codec inspector
- Per-call live panel: negotiated codec (and clock rate/channels), payload type, upload/download bandwidth, jitter, RTT, packet loss, ICE state, encryption (SRTP/ZRTP) — sourced from `CallStats` on a ~1 s tick.
- Sparkline graphs for bandwidth/jitter/loss over the call.
- Debug mode (toggle in settings): capture SIP messages and SDP offer/answer, presented as a filterable log with a dedicated "codec negotiation" view showing offered vs. answered codec lists. Export to file for bug reports.

### 2.4 Ringtones
- Bundle 4–6 CC0/public-domain ringtones (sources: freesound.org CC0 filter, or commission/generate).
- Settings pane: preview, select per-account ringtone, output device for ringing (so it can ring on speakers while calls go to a headset), import custom files (copied into `~/Library/Application Support/Sippy/Ringtones`, accept caf/wav/mp3/m4a).

### 2.5 Table-stakes (parity with Telephone)
Multiple accounts, registration status, dialpad with DTMF, mute/hold/transfer, call history, audio device selection with hot-plug handling, macOS notifications with Answer/Decline actions, optional menu bar extra.

### 2.6 NAT / IP rewrite (per-account setting)
Like Telephone's "Update IP Address" / MicroSIP's "allow IP rewrite": rewrite Contact/Via using the public address learned from responses (`received`/`rport`), for PBXs that don't fix it server-side (Kalliope can, but not every PBX will). liblinphone already ships the machinery — its Sal NAT helper plus `NatPolicy` (STUN/TURN/ICE) — so this is mostly exposing a toggle + optional STUN server field in account settings. Scheduled with M5 hardening (network-change handling lives there anyway).

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│ SwiftUI App                                 │
│  Dialpad · CallWindow · Contacts · History  │
│  Settings · TrafficInspector · MenuBarExtra │
├─────────────────────────────────────────────┤
│ App services (Swift, observable)            │
│  CallController   AccountManager            │
│  ContactStore(SwiftData) + SystemContacts   │
│  DialPlanEngine   RingtoneManager           │
│  CallHistoryStore StatsCollector  URLHandler│
├─────────────────────────────────────────────┤
│ SIPEngine protocol                          │
│   └─ LinphoneEngine (actor wrapping Core)   │
└─────────────────────────────────────────────┘
```

- `LinphoneEngine`: single actor owning the linphone `Core`, its iterate loop, and delegate callbacks; translates everything into Swift async streams/events so the rest of the app never touches the SDK directly.
- `DialPlanEngine` and `StatsCollector` are pure and platform-free — trivially reusable for a future iOS target.

## 4. Milestones

**M0 — Spike (validate the stack before committing).** SPM project, integrate linphone-sdk-swift-macos, register against a test PBX, place and receive one call from a throwaway UI. Verify G.729 is present and negotiable in the SDK build (fallback: build linphone-sdk from source with `-DENABLE_G729=ON`, or pivot to PJSIP+bcg729). *This milestone is the go/no-go on the stack choice.*

*M0 findings (2026-08-27):* the stack works with Command Line Tools only — no Xcode needed until app packaging. SDK 5.5.16 vendored in `Vendor/` (linphone GitLab was down; mirrored from download.linphone.org). Two SDK defects found and worked around via `make deps`: the SDK forgets to ship `libhidapi.0.dylib` (we build it from source), and the prebuilt binaries contain **no G.729** — solved by compiling bcg729 + mediastreamer2's `g729.c` into `libmsbcg729.so`, loaded as a mediastreamer2 plugin; the spike confirms `G729/8000` enabled and the dial-plan engine passes 11 unit tests. Licensing correction: liblinphone 5.x is **AGPLv3** (not plain GPL), so Sippy is AGPLv3. Registration against the real PBX (UDP, LAN) confirmed working 2026-08-27. **M0 passed — the stack choice is validated; proceed with liblinphone.**

**M1 — Calling MVP.** Account settings + keychain-stored credentials, registration lifecycle, dialpad, incoming/outgoing call UI, DTMF, mute/hold, audio device selection, notifications.

**M2 — Contacts & history.** SwiftData store, system-contacts merge, search, favorites, call history with redial, caller-ID resolution.

**M3 — Dial plan & OS integration.** Prefix/rules engine + settings UI, tel:/callto:/sip: URL handler, Services menu entry, paste-and-dial.

**M4 — Codecs & inspector.** Codec preference UI with the defaults above, live traffic panel, SIP/SDP debug log with codec-negotiation view, log export.

**M5 — Ringtones & polish.** Bundled ringtones, custom import, per-account selection, ring-device routing; menu bar extra; NAT/IP-rewrite account setting (§2.6); then hardening: hot-plug audio, sleep/wake re-registration, network-change handling (Wi-Fi ↔ Ethernet ↔ VPN).

**M6 — Release engineering.** Direct distribution first: Developer ID signing, notarization, Sparkle updates, GPLv3 repo hygiene (the GPL makes Mac App Store distribution awkward anyway). Test matrix against Asterisk and FreeSWITCH in Docker.

## 5. Multi-platform stance

- **iOS/iPadOS: cheap later.** linphone-sdk has an iOS Swift package; SwiftUI views and all pure modules carry over. Main added work: CallKit + PushKit (SIP needs push on iOS) — a real but bounded project after M6.
- **Windows/Linux: don't.** No shared-UI path from Swift worth the cost; a cross-platform framework (Flutter/Tauri/KMP) would sacrifice the native-macOS goal that motivated the project. Revisit only if it becomes a hard requirement.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Prebuilt linphone SPM package lacks G.729 or lags behind | M0 verifies; build SDK from source, or PJSIP fallback behind `SIPEngine` |
| GPL constrains distribution | Accept (open-source app), or buy commercial license later |
| NAT traversal flakiness | Expose STUN/TURN/ICE per account; test from behind NAT early (M1, not M6) |
| Audio device edge cases (AirPods, hot-plug, sample-rate) | Dedicated test pass in M5; SDK handles most via its audio layer |
| SwiftUI gaps for call windows/always-on-top | AppKit window controller for the call window if needed |

## 7. Test infrastructure

- Unit tests: DialPlanEngine (heaviest coverage), stats parsing, contact matching.
- Local PBX in Docker (Asterisk or FreeSWITCH) with scripted extensions for integration tests: registration, call in/out, DTMF, codec negotiation per codec, hold/transfer.
- A second softphone (Zoiper/linphone desktop) as the far end for manual testing.
