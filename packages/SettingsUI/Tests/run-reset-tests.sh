#!/bin/bash
set -euo pipefail
package_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/developer-reset-tests.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun swiftc -module-cache-path "$test_directory/module-cache" \
    "$package_root/../FoundationUtils/Sources/FoundationUtils/AppRelaunch.swift" \
    "$package_root/Sources/SettingsUI/DeveloperAppReset.swift" \
    "$package_root/Tests/DeveloperAppResetTests.swift" \
    -o "$test_directory/DeveloperAppResetTests"
"$test_directory/DeveloperAppResetTests"
