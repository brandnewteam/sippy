# Minimal Asterisk PBX for Sippy's integration test (see run.sh).
# Alpine still packages Asterisk (Debian dropped it after bullseye) and the
# package is multi-arch (arm64 included) with the full pjsip module set.
FROM alpine:3.20

RUN apk add --no-cache asterisk

COPY asterisk.conf modules.conf pjsip.conf.tmpl extensions.conf rtp.conf /etc/asterisk/

EXPOSE 5060/udp 10000-10010/udp

# HOST_IP is baked into the SDP/Contact addresses so media routes back
# through Docker's port mappings to the host-side client.
CMD ["/bin/sh", "-c", "sed \"s/@HOST_IP@/${HOST_IP:?set HOST_IP}/\" /etc/asterisk/pjsip.conf.tmpl > /etc/asterisk/pjsip.conf && exec asterisk -f"]
