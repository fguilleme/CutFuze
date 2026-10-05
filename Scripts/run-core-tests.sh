#!/bin/bash
set -euo pipefail
# A native XCTest harness for the Foundation/CryptoKit core; no simulator or package resolution.
SOURCE_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HARNESS_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cutfuze-core.XXXXXX")
TEST_PLATFORM=$(xcrun --sdk macosx --show-sdk-platform-path)
trap 'rm -rf -- "$HARNESS_ROOT"' EXIT
xcrun swiftc -emit-library -emit-module -enable-testing -swift-version 6 \
    -module-name CutFuze -module-cache-path "$HARNESS_ROOT/module-cache" \
    "$SOURCE_ROOT"/CutFuze/Core/*.swift \
    -emit-module-path "$HARNESS_ROOT/CutFuze.swiftmodule" -o "$HARNESS_ROOT/libCutFuze.dylib"
cat > "$HARNESS_ROOT/main.swift" <<'RUNNER'
import XCTest
import Darwin
@testable import CutFuze
let suite = XCTestSuite(forTestCaseClass: CoreTests.self)
suite.run()
exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
RUNNER
xcrun swiftc -swift-version 5 -module-cache-path "$HARNESS_ROOT/module-cache" \
    -I "$HARNESS_ROOT" -L "$HARNESS_ROOT" -lCutFuze \
    -F "$TEST_PLATFORM/Developer/Library/Frameworks" \
    -I "$TEST_PLATFORM/Developer/usr/lib" -L "$TEST_PLATFORM/Developer/usr/lib" \
    -Xlinker -rpath -Xlinker "$HARNESS_ROOT" \
    -Xlinker -rpath -Xlinker "$TEST_PLATFORM/Developer/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$TEST_PLATFORM/Developer/usr/lib" \
    "$SOURCE_ROOT/CutFuzeTests/CoreTests.swift" "$HARNESS_ROOT/main.swift" \
    -o "$HARNESS_ROOT/CoreTests"
"$HARNESS_ROOT/CoreTests"
