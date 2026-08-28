# Shared settings for the build scripts. Source this file; do not run it.
#
# To rename the app, change APP_NAME here and the two product names in Package.swift.
# Change BUNDLE_ID to something you own (for example io.github.<your-username>.candela) before
# your first public release; macOS keys preferences and permissions to it.

APP_NAME="Candela"
BUNDLE_ID="io.github.candela-display.Candela"
CLI_NAME="candelactl"
APP_PRODUCT="Candela"       # executable product in Package.swift
CLI_PRODUCT="candelactl"    # executable product in Package.swift
COPYRIGHT="Copyright © 2026 Candela contributors. MIT License."

# Local self-signed signing identity created by scripts/create-signing-identity.sh.
SIGNING_NAME="$APP_NAME Local Signing"
SIGNING_DIR="$HOME/Library/Application Support/$APP_NAME Signing"
SIGNING_KEYCHAIN="$SIGNING_DIR/signing.keychain-db"

# The version lives in one place: Sources/MonitorCore/Version.swift (AppVersion.string).
VERSION=$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/MonitorCore/Version.swift)
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)

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
