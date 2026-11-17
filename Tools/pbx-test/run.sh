#!/bin/sh
# Sippy PBX integration test: boots a containerized Asterisk, registers the
# spike against it, calls the echo extension, and checks that media
# negotiates. Requires Docker and a built spike (make build).
#
#   Tools/pbx-test/run.sh
#
# Built with extra SwiftPM flags (make build SWIFTPM_FLAGS=…)? Pass the same
# SWIFTPM_FLAGS here so the spike is looked up where that build put it.
#
# Exits non-zero on any failed step.

set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
# The products dir depends on SwiftPM's build system; ask it with the same
# flags as the build (see Makefile). SWIFTPM_FLAGS is split into words on
# purpose, like make does.
# shellcheck disable=SC2086
SPIKE="$(cd "$REPO" && swift build ${SWIFTPM_FLAGS:-} --show-bin-path 2>/dev/null || true)/sippy-spike"
IMAGE=sippy-pbx-test
CONTAINER=sippy-pbx-test
LOG="${TMPDIR:-/tmp}/sippy-pbx-test.log"

[ -x "$SPIKE" ] || { echo "spike not built — run 'make build' first" >&2; exit 2; }

# Everything rides loopback: the container advertises 127.0.0.1 (see
# pjsip.conf.tmpl) and the port mappings bind to it. Return paths that the
# SDP can't describe (client media behind Docker's NAT) work because the
# endpoint config is symmetric (rtp_symmetric/force_rport). Using the LAN IP
# instead breaks when a VPN rewrites Docker's NATed UDP source addresses.
HOST_IP=127.0.0.1

echo "==> building PBX image"
docker build -q -t "$IMAGE" "$DIR"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "==> starting Asterisk (advertising $HOST_IP)"
docker run -d --rm --name "$CONTAINER" -e HOST_IP="$HOST_IP" \
    -p 127.0.0.1:5060:5060/udp -p 127.0.0.1:10000-10010:10000-10010/udp "$IMAGE" >/dev/null

echo "==> waiting for Asterisk"
i=0
until docker exec "$CONTAINER" asterisk -rx 'core show version' >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt 30 ] || { echo "Asterisk did not come up" >&2; docker logs "$CONTAINER" >&2; exit 1; }
    sleep 1
done
docker exec "$CONTAINER" asterisk -rx 'core show version'

export SIPPY_DOMAIN="$HOST_IP" SIPPY_USER=6001 SIPPY_PASSWORD=test6001

echo "==> test 1: registration"
"$SPIKE" register > "$LOG" 2>&1 || { cat "$LOG" >&2; exit 1; }
grep -q 'registration: Ok' "$LOG"
echo "    OK"

echo "==> test 2: call the echo extension, verify media"
# The echo app answers instantly; give the streams a few seconds, then hang up.
"$SPIKE" call 600 > "$LOG" 2>&1 &
SPIKE_PID=$!
sleep 6
kill -INT "$SPIKE_PID" 2>/dev/null || true
wait "$SPIKE_PID" 2>/dev/null || true
grep -q 'call: StreamsRunning' "$LOG" || { cat "$LOG" >&2; exit 1; }
CODEC=$(grep 'negotiated codec' "$LOG" | head -1)
[ -n "$CODEC" ] || { cat "$LOG" >&2; exit 1; }
echo "    OK — $CODEC"

echo "==> test 3: codec preference honored (offer G.722 only)"
SIPPY_CODECS=G722 "$SPIKE" call 600 > "$LOG" 2>&1 &
SPIKE_PID=$!
sleep 6
kill -INT "$SPIKE_PID" 2>/dev/null || true
wait "$SPIKE_PID" 2>/dev/null || true
grep -q 'negotiated codec: G722/8000' "$LOG" || { cat "$LOG" >&2; exit 1; }
echo "    OK — G722/8000"

echo "==> all PBX tests passed (Asterisk $(docker image inspect "$IMAGE" --format '{{.Architecture}}' 2>/dev/null || true))"
