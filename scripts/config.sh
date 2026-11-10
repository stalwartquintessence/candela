# Shared settings for the build scripts. Source this file; do not run it.
#
# To rename the app, change APP_NAME here and the two product names in Package.swift.
# Forks: change BUNDLE_ID to an identifier you own (for example io.github.<your-username>.Candela)
# before publishing. macOS keys preferences and permissions to it, so changing it later resets them.

APP_NAME="Candela"
BUNDLE_ID="io.github.stalwartquintessence.Candela"
CLI_NAME="candelactl"
APP_PRODUCT="Candela"       # executable product in Package.swift
CLI_PRODUCT="candelactl"    # executable product in Package.swift
COPYRIGHT="Copyright © 2026 stalwartquintessence. MIT License."

# Local self-signed signing identity created by scripts/create-signing-identity.sh.
SIGNING_NAME="$APP_NAME Local Signing"
SIGNING_DIR="$HOME/Library/Application Support/$APP_NAME Signing"
SIGNING_KEYCHAIN="$SIGNING_DIR/signing.keychain-db"

# In-app updates (Sparkle). Every GitHub release carries appcast.xml, and this address always
# serves the newest one. SPARKLE_PUBLIC_KEY is printed by scripts/create-update-key.sh; without
# it the app is built with in-app updates switched off (for example in forks).
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/stalwartquintessence/candela/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"

# The version lives in one place: Sources/MonitorCore/Version.swift (AppVersion.string).
VERSION=$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/MonitorCore/Version.swift)
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}" # override only to test updates

# With only the Command Line Tools installed (no Xcode), SwiftPM's default build system fails to
# start ("Unknown error parsing property list") and the Swift Testing framework is not on the
# default search paths. Detect that and use the classic build system with explicit paths.
SWIFT_BUILD_FLAGS=()
SWIFT_TEST_FLAGS=()
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
    SWIFT_BUILD_FLAGS=(--build-system native)
    _FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    _LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
    SWIFT_TEST_FLAGS=(-Xswiftc "-F$_FW" -Xlinker "-F$_FW" -Xlinker -rpath -Xlinker "$_FW" -Xlinker -rpath -Xlinker "$_LIB")
fi
