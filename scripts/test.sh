#!/bin/bash
# Runs the unit test suite. Extra arguments go to `swift test` (for example --filter EDID).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

swift test ${SWIFT_BUILD_FLAGS[@]+"${SWIFT_BUILD_FLAGS[@]}"} ${SWIFT_TEST_FLAGS[@]+"${SWIFT_TEST_FLAGS[@]}"} "$@"
