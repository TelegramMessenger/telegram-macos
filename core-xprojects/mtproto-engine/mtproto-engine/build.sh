#!/bin/sh

set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../../scripts/build-architectures.sh"

SOURCE_DIR="$1"
BUILD_DIR="$2"
PACKAGE_DIR="$3"

if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ] || [ -z "$PACKAGE_DIR" ]; then
    echo "Usage: $0 SOURCE_DIR BUILD_DIR PACKAGE_DIR"
    echo "Example: $0 /path/to/third-party/mtproto-engine /path/to/build /path/to/submodules/MTProtoRustEngine"
    exit 1
fi

DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.13}"

if [ ! -f "$SOURCE_DIR/Cargo.toml" ]; then
    echo "mtproto-engine sources are missing at $SOURCE_DIR"
    echo "Check out the telegram-ios submodule first:"
    echo "  git submodule update --init submodules/telegram-ios"
    exit 1
fi

mkdir -p "$BUILD_DIR" "$PACKAGE_DIR"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
PACKAGE_DIR="$(cd "$PACKAGE_DIR" && pwd)"

if [ -n "${CARGO:-}" ]; then
    CARGO_BIN="$CARGO"
elif command -v cargo >/dev/null 2>&1; then
    CARGO_BIN="$(command -v cargo)"
elif [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO_BIN="$HOME/.cargo/bin/cargo"
else
    echo "cargo was not found. mtproto-engine is a Rust library; install the toolchain pinned in"
    echo "$SOURCE_DIR/rust-toolchain.toml with:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal"
    echo "then re-run this script (rustup installs the pinned toolchain automatically)."
    exit 1
fi

RUSTUP_BIN="$(dirname "$CARGO_BIN")/rustup"

mkdir -p "$BUILD_DIR"

cd "$SOURCE_DIR"

RUST_LIBRARIES=()
for ARCH in $TELEGRAM_BUILD_ARCHS; do
    RUST_TARGET="$(telegram_rust_target "$ARCH")"
    if [ -x "$RUSTUP_BIN" ]; then
        "$RUSTUP_BIN" target add "$RUST_TARGET" >/dev/null 2>&1 || true
    fi
    MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" CARGO_TARGET_DIR="$BUILD_DIR/lib" "$CARGO_BIN" build \
        --package mtproto-ffi \
        --release \
        --locked \
        --target "$RUST_TARGET"
    RUST_LIBRARIES+=("$BUILD_DIR/lib/$RUST_TARGET/release/libmtproto_engine_ffi.a")
done

lipo -create "${RUST_LIBRARIES[@]}" -output "$BUILD_DIR/libmtproto_engine_ffi.a"

HEADERS_DIR="$BUILD_DIR/headers"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR/MTProtoEngineFFI"
cp "$SOURCE_DIR/crates/mtproto-ffi/include/mtproto_engine.h" "$HEADERS_DIR/MTProtoEngineFFI/"
cat > "$HEADERS_DIR/MTProtoEngineFFI/module.modulemap" <<EOF
module MTProtoEngineFFI {
    header "mtproto_engine.h"
    export *
}
EOF

rm -rf "$PACKAGE_DIR/MTProtoEngineFFI.xcframework"
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/libmtproto_engine_ffi.a" \
    -headers "$HEADERS_DIR" \
    -output "$PACKAGE_DIR/MTProtoEngineFFI.xcframework"

lipo -info "$BUILD_DIR/libmtproto_engine_ffi.a"
echo "mtproto-engine artifacts updated in $PACKAGE_DIR"
