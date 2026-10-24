#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SELECTION=""
DRY_RUN=no
APP_ONLY=no

usage() {
    echo "Usage: sh scripts/build-local.sh [arm64|x86_64|universal] [--app-only] [--dry-run]"
    echo "Without an architecture, prompts with this Mac's architecture as the default."
    echo "--app-only reuses prepared native frameworks and the architecture's DerivedData."
}

for ARGUMENT in "$@"; do
    case "$ARGUMENT" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=yes ;;
        --app-only) APP_ONLY=yes ;;
        arm64|x86_64|universal)
            if [ -n "$SELECTION" ]; then usage >&2; exit 2; fi
            SELECTION="$ARGUMENT"
            ;;
        *) usage >&2; exit 2 ;;
    esac
done

if [ "$(uname -s)" != Darwin ]; then
    echo "This script requires macOS." >&2
    exit 1
fi

HOST_ARCH="$(uname -m)"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then
    HOST_ARCH=arm64
fi

if [ -z "$SELECTION" ]; then
    printf 'Architecture: arm64 (Apple Silicon), x86_64 (Intel), universal (both) [%s]: ' "$HOST_ARCH"
    if ! IFS= read -r SELECTION; then
        echo "Pass arm64, x86_64 or universal when running without input." >&2
        exit 2
    fi
    SELECTION="${SELECTION:-$HOST_ARCH}"
fi

case "$SELECTION" in
    arm64|x86_64) export TELEGRAM_BUILD_ARCHS="$SELECTION" ;;
    universal) export TELEGRAM_BUILD_ARCHS="arm64 x86_64" ;;
    *) echo "Unsupported architecture: $SELECTION" >&2; exit 2 ;;
esac
. "$SCRIPT_DIR/build-architectures.sh"

LOCAL_CONFIG="$ROOT_DIR/Telegram-Mac/Local.xcconfig"
if [ ! -f "$LOCAL_CONFIG" ]; then
    echo "Copy Telegram-Mac/Local.xcconfig.example to Telegram-Mac/Local.xcconfig and fill in your API credentials, bundle ID and signing team." >&2
    exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export CMAKE_POLICY_VERSION_MINIMUM="${CMAKE_POLICY_VERSION_MINIMUM:-3.5}"
export CARGO_PROFILE_RELEASE_STRIP=none
export CARGO_PROFILE_DEV_STRIP=none
if [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi
XCODE_VERSION="$(xcodebuild -version)"
XCODE_MAJOR="$(printf '%s\n' "$XCODE_VERSION" | awk '/^Xcode / {split($2, version, "."); print version[1]; exit}')"
if ! [[ "$XCODE_MAJOR" =~ ^[0-9]+$ ]]; then
    echo "Select full Xcode with DEVELOPER_DIR before building." >&2
    exit 1
fi

BUILD_SETTINGS=("ARCHS=$TELEGRAM_BUILD_ARCHS" "ONLY_ACTIVE_ARCH=NO")
DESTINATION='generic/platform=macOS'
if [ "$SELECTION" != universal ]; then
    BUILD_SETTINGS[1]="ONLY_ACTIVE_ARCH=YES"
    DESTINATION="platform=macOS,arch=$SELECTION"
fi
if [ "$XCODE_MAJOR" -ge 27 ]; then
    export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
fi
if [ -n "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    BUILD_SETTINGS+=("MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET")
fi

if [ "$DRY_RUN" = no ]; then
    REQUIRED_TOOLS=(python3 git)
    if [ "$APP_ONLY" = no ]; then
        REQUIRED_TOOLS+=(cmake ninja meson nasm yasm autoconf automake pkg-config "${CARGO:-cargo}")
    fi
    for TOOL in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$TOOL" >/dev/null 2>&1; then
            echo "Missing tool: $TOOL. Install the prerequisites in INSTALL.md before retrying." >&2
            exit 1
        fi
    done
    if [ "$XCODE_MAJOR" -ge 27 ] && ! xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q 'Status: installed'; then
        echo "Install the Metal toolchain first: xcodebuild -downloadComponent MetalToolchain" >&2
        exit 1
    fi
fi

OUTPUT_DIR="$ROOT_DIR/.build/local-$SELECTION"
export BUILD_TIMING_LOG="$OUTPUT_DIR/timings.tsv"

run_step() {
    local LABEL="$1"
    shift
    if [ "$DRY_RUN" = yes ]; then
        printf '%s: ' "$LABEL"
        printf '%q ' "$@"
        printf '\n'
    else
        sh "$SCRIPT_DIR/time-step.sh" "$LABEL" "$@" 2>&1 | tee "$OUTPUT_DIR/$LABEL.log"
    fi
}

cd "$ROOT_DIR"
printf 'Local Debug build: %s\nOutput: %s\n' "$TELEGRAM_BUILD_ARCHS" "$OUTPUT_DIR"
if [ "$DRY_RUN" = no ]; then
    mkdir -p "$OUTPUT_DIR"
    : > "$BUILD_TIMING_LOG"
fi
if [ "$XCODE_MAJOR" -ge 27 ]; then
    run_step xcode27 bash "$SCRIPT_DIR/xcode27.sh" apply
fi

if [ "$APP_ONLY" = yes ]; then
    echo "App only: reusing native frameworks already prepared for $TELEGRAM_BUILD_ARCHS."
else
    run_step frameworks sh "$SCRIPT_DIR/configure_frameworks.sh"
fi
run_step app xcodebuild build \
    -workspace "$ROOT_DIR/Telegram-Mac.xcworkspace" \
    -scheme Telegram \
    -configuration Debug \
    -xcconfig "$LOCAL_CONFIG" \
    -destination "$DESTINATION" \
    -derivedDataPath "$OUTPUT_DIR/DerivedData" \
    "${BUILD_SETTINGS[@]}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Apple Development" \
    TELEGRAM_DISABLE_UPDATES=YES \
    PROVISIONING_PROFILE_SPECIFIER= \
    COMPILER_INDEX_STORE_ENABLE=NO

APP_PATH="$OUTPUT_DIR/DerivedData/Build/Products/Debug/Telegram.app"
if [ "$DRY_RUN" = no ]; then
    [ -d "$APP_PATH" ] || { echo "Build did not produce $APP_PATH" >&2; exit 1; }
    printf '\nBuilt: %s\nRun: open %q\nTimings: %s\n' "$APP_PATH" "$APP_PATH" "$BUILD_TIMING_LOG"
fi
