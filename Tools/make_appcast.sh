#!/bin/sh
# Writes dist/appcast.xml, the Sparkle feed for one release: a single item
# for the zip that release attaches, EdDSA-signed. Installed copies read it
# from releases/latest/download/appcast.xml (SUFeedURL), so the feed only
# ever needs the newest version.
#
#   Tools/make_appcast.sh <zip> <tag> <release-notes.html>
#
# SPARKLE_ED_PRIVATE_KEY must hold the private key exported with
# `generate_keys -x` (see README "Sparkle updates"). It is checked against
# SUPublicEDKey first: a feed signed with another key would make every
# installed copy reject the update.
set -eu

zip=$1
tag=$2
notes=$3
repo=${GITHUB_REPOSITORY:-brandnewteam/sippy}
plist=Support/Info.plist
out=dist/appcast.xml

: "${SPARKLE_ED_PRIVATE_KEY:?set it to the key exported by generate_keys -x}"

plist_value() { /usr/libexec/PlistBuddy -c "Print $1" "$plist"; }
version=$(plist_value CFBundleVersion)
short_version=$(plist_value CFBundleShortVersionString)
minimum_system=$(plist_value LSMinimumSystemVersion)
public_key=$(plist_value SUPublicEDKey)

# The exported key is the base64 32-byte Ed25519 seed; wrap it in PKCS#8
# DER to let openssl derive the public half. macOS's own openssl is
# LibreSSL, which can't; Homebrew's OpenSSL can.
openssl=openssl
case $(openssl version) in
    OpenSSL*) ;;
    *) openssl="$(brew --prefix openssl 2>/dev/null)/bin/openssl" ;;
esac
derived=$( { printf '\060\056\002\001\000\060\005\006\003\053\145\160\004\042\004\040';
             printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | base64 -D; } |
           "$openssl" pkey -inform DER -pubout -outform DER | tail -c 32 | base64)
if [ -z "$derived" ]; then
    echo "Couldn't derive the public key (needs OpenSSL 3+, e.g. brew install openssl)" >&2
    exit 1
elif [ "$derived" != "$public_key" ]; then
    echo "SPARKLE_ED_PRIVATE_KEY doesn't match SUPublicEDKey in $plist" >&2
    exit 1
fi

sign_update=$(find .build/artifacts -type f -path '*Sparkle/bin/sign_update' | head -1)
[ -n "$sign_update" ] || { echo "Sparkle's sign_update not found under .build/artifacts" >&2; exit 1; }
# Prints: sparkle:edSignature="…" length="…"
signature=$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$zip")

url="https://github.com/$repo/releases/download/$tag/$(basename "$zip")"
pub_date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
# "]]>" would end the CDATA section early.
description=$(sed 's/]]>/]]]]><![CDATA[>/g' "$notes")

mkdir -p "$(dirname "$out")"
cat > "$out" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sippy</title>
    <item>
      <title>Sippy $short_version</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$short_version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_system</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$repo/releases/tag/$tag</sparkle:fullReleaseNotesLink>
      <description><![CDATA[$description]]></description>
      <enclosure url="$url" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$out"
echo "Wrote $out for $short_version ($version): $url"
