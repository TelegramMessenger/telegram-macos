#!/bin/bash
set -euo pipefail
SCHEME=SettingsUISearchTests exec "$(dirname "$0")/run-account-reset-tests.sh" "$@"
