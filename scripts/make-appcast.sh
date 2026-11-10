#!/bin/bash
# Prints the Sparkle update feed (appcast.xml) for the version in Sources/MonitorCore/Version.swift.
# The release workflow attaches it to the GitHub release, so
# https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml always describes the
# newest version.
#
# Usage: scripts/make-appcast.sh <download-url> <signature> <release-notes.md> > appcast.xml
#   download-url  where the zip of this version can be downloaded
#   signature     what Sparkle's sign_update printed for that zip:
#                 sparkle:edSignature="..." length="..."
#   release notes Markdown, for example from scripts/release-notes.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if [ $# -ne 3 ]; then
    echo "usage: $0 <download-url> <signature> <release-notes.md>" >&2
    exit 2
fi
URL=$1
SIGNATURE=$2
NOTES=$3

# Only accept exactly what sign_update prints, so nothing else can end up in the feed.
if ! [[ "$SIGNATURE" =~ ^sparkle:edSignature=\"[A-Za-z0-9+/=]+\"\ length=\"[0-9]+\"$ ]]; then
    echo "error: unexpected signature: $SIGNATURE" >&2
    exit 1
fi
if ! [[ "$URL" =~ ^https?://[A-Za-z0-9._~:/%+-]+$ ]]; then
    echo "error: unexpected download URL: $URL" >&2
    exit 1
fi
if grep -q ']]>' "$NOTES"; then
    echo "error: the release notes contain ']]>', which would end the CDATA section" >&2
    exit 1
fi

MINIMUM_SYSTEM=$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist)
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <item>
      <title>$APP_NAME $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[
$(cat "$NOTES")
]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
EOF
