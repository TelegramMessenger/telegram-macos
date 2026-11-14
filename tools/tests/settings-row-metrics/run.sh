#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
metrics_build_dir=$(mktemp -d)
trap 'rm -rf "$metrics_build_dir"' EXIT
xcrun swiftc ../../../packages/GeneralRows/Sources/GeneralRows/SettingsRowMetrics.swift main.swift -o "$metrics_build_dir/check"
"$metrics_build_dir/check"
