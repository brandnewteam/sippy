# Sippy

A native macOS SIP client. See [PLAN.md](PLAN.md) for the development plan.

Licensed AGPLv3 (the SIP stack, [liblinphone](https://linphone.org) 5.x, is AGPL).

## Status: M0 spike

Requires only the Xcode Command Line Tools (full Xcode not needed yet) and git.

```sh
make deps           # one-time: builds libhidapi + the G.729 plugin (see below)
make test           # dial-plan engine unit tests
make spike-codecs   # list codecs, verify G.729 is present

# against a real PBX:
make build
SIPPY_DOMAIN=pbx.example.com SIPPY_USER=101 SIPPY_PASSWORD=… \
  ./.build/arm64-apple-macosx/debug/sippy-spike register
SIPPY_DOMAIN=pbx.example.com SIPPY_USER=101 SIPPY_PASSWORD=… \
  ./.build/arm64-apple-macosx/debug/sippy-spike call 124
```

Set `SIPPY_DEBUG=1` for full SIP traces, `SIPPY_TRANSPORT=tcp|tls` as needed.

## Vendored pieces (and why)

- `Vendor/linphone-sdk-swift-macos/` — the official linphone Swift package
  5.5.16, mirrored from download.linphone.org (their GitLab was down at setup
  time). The binary xcframeworks still download from linphone's server on
  first build.
- `Vendor/msbcg729/` — mediastreamer2's `g729.c` filter (AGPL, from the
  mediastreamer2 repo) plus our tiny plugin-init shim. The prebuilt SDK ships
  **without** G.729; `make deps` compiles these together with
  [bcg729](https://github.com/BelledonneCommunications/bcg729) into
  `Vendor/lib/libmsbcg729.so`, which liblinphone loads as a mediastreamer2
  plugin (the spike points `Factory.mspluginsDir` at `Vendor/lib`). The `.so`
  extension is required — mediastreamer2 only scans for `libms*.so`.
- `Vendor/lib/libhidapi.0.dylib` — built by `make deps` from
  [libusb/hidapi](https://github.com/libusb/hidapi); linphone.framework
  references it but the linphone macOS SDK forgets to ship it.
