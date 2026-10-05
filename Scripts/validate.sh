#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIMULATOR_ID="${1:?Usage: Scripts/validate.sh SIMULATOR_UDID}"
RESULT_DIR="build/validation-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULT_DIR"
xcodebuild -project CutFuze.xcodeproj -scheme CutFuze -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO clean build > "$RESULT_DIR/build.log" 2>&1
xcodebuild -project CutFuze.xcodeproj -scheme CutFuze -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -resultBundlePath "$RESULT_DIR/tests.xcresult" test > "$RESULT_DIR/tests.log" 2>&1
xcrun xcresulttool get test-results summary --path "$RESULT_DIR/tests.xcresult" --format json > "$RESULT_DIR/summary.json"
xcrun xcresulttool export attachments --path "$RESULT_DIR/tests.xcresult" --output-path "$RESULT_DIR/attachments"
echo "Résultats : $RESULT_DIR"
