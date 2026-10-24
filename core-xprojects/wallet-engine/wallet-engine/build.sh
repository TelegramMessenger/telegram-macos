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
    echo "Example: $0 /path/to/wallet-engine /path/to/build /path/to/packages/WalletEngine"
    exit 1
fi

DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
case "$DEPLOYMENT_TARGET" in
    10.[0-9]|10.1[0-4]) DEPLOYMENT_TARGET=10.15 ;;
esac

if [ ! -f "$SOURCE_DIR/Cargo.toml" ]; then
    echo "wallet-engine sources are missing at $SOURCE_DIR"
    echo "Check out the submodule first:"
    echo "  git -C submodules/telegram-ios submodule update --init third-party/wallet-engine/wallet-engine"
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
    echo "cargo was not found. wallet-engine is a Rust library; install the toolchain pinned in"
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
        --package wallet-engine \
        --release \
        --locked \
        --target "$RUST_TARGET"
    RUST_LIBRARIES+=("$BUILD_DIR/lib/$RUST_TARGET/release/libwallet_engine.a")
done

lipo -create "${RUST_LIBRARIES[@]}" -output "$BUILD_DIR/libwallet_engine.a"

CARGO="$CARGO_BIN" CARGO_TARGET_DIR="$BUILD_DIR/xtask" "$CARGO_BIN" run \
    --manifest-path xtask/Cargo.toml \
    --target-dir "$BUILD_DIR/xtask" \
    --locked \
    -- bindings swift

mkdir -p "$PACKAGE_DIR/Sources/WalletEngineFFI"
cp "$SOURCE_DIR/bindings/swift/Sources/WalletEngineFFI/WalletEngineFFI.swift" "$PACKAGE_DIR/Sources/WalletEngineFFI/"

python3 "$SCRIPT_DIR/apply-ffi-availability.py" \
    "$SCRIPT_DIR/ffi-availability.txt" \
    "$PACKAGE_DIR/Sources/WalletEngineFFI/WalletEngineFFI.swift"

HEADERS_DIR="$BUILD_DIR/headers"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"
cp "$SOURCE_DIR/bindings/swift/Sources/wallet_engineFFI/wallet_engineFFI.h" "$HEADERS_DIR/"
cp "$SOURCE_DIR/bindings/swift/Sources/wallet_engineFFI/module.modulemap" "$HEADERS_DIR/"

rm -rf "$PACKAGE_DIR/wallet_engineFFI.xcframework"
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/libwallet_engine.a" \
    -headers "$HEADERS_DIR" \
    -output "$PACKAGE_DIR/wallet_engineFFI.xcframework"

lipo -info "$BUILD_DIR/libwallet_engine.a"
cp "$PACKAGE_DIR/Sources/WalletEngineFFI/WalletEngineFFI.swift" "$BUILD_DIR/WalletEngineFFI.swift"
echo "wallet-engine artifacts updated in $PACKAGE_DIR"
