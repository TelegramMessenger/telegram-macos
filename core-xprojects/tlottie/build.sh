#!/bin/sh

set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$ROOT_DIR/scripts/build-architectures.sh"
SOURCE_DIR="$ROOT_DIR/submodules/tlottie"
ENGINE_TOOLCHAIN_FILE="$ROOT_DIR/submodules/telegram-ios/third-party/mtproto-engine/rust-toolchain.toml"
BUILD_DIR="$SCRIPT_DIR/build"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.13}"

if [ ! -f "$SOURCE_DIR/Cargo.toml" ]; then
    echo "tlottie sources are missing at $SOURCE_DIR"
    echo "Check out the submodule first:"
    echo "  git submodule update --init submodules/tlottie"
    exit 1
fi

if [ ! -f "$ENGINE_TOOLCHAIN_FILE" ]; then
    echo "$ENGINE_TOOLCHAIN_FILE is missing."
    echo "tlottie is linked next to mtproto-engine and wallet-engine and must use the same Rust toolchain."
    exit 1
fi

TOOLCHAIN="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "$ENGINE_TOOLCHAIN_FILE")"

if [ -n "${CARGO:-}" ]; then
    CARGO_BIN="$CARGO"
elif command -v cargo >/dev/null 2>&1; then
    CARGO_BIN="$(command -v cargo)"
elif [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO_BIN="$HOME/.cargo/bin/cargo"
else
    echo "cargo was not found. tlottie is a Rust library; install the toolchain with:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal"
    exit 1
fi

RUSTUP_BIN="$(dirname "$CARGO_BIN")/rustup"

if [ -x "$RUSTUP_BIN" ] && ! "$RUSTUP_BIN" run "$TOOLCHAIN" rustc --version >/dev/null 2>&1; then
    "$RUSTUP_BIN" toolchain install "$TOOLCHAIN" --profile minimal >/dev/null 2>&1
fi

mkdir -p "$BUILD_DIR"

INSTALLED_TARGETS=""
if [ -x "$RUSTUP_BIN" ]; then
    INSTALLED_TARGETS="$("$RUSTUP_BIN" target list --installed --toolchain "$TOOLCHAIN")"
fi

RUST_LIBRARIES=()
for ARCH in $TELEGRAM_BUILD_ARCHS; do
    RUST_TARGET="$(telegram_rust_target "$ARCH")"
    if [ -x "$RUSTUP_BIN" ] && ! printf '%s\n' "$INSTALLED_TARGETS" | grep -qx "$RUST_TARGET"; then
        "$RUSTUP_BIN" target add --toolchain "$TOOLCHAIN" "$RUST_TARGET" >/dev/null 2>&1
    fi
    RUSTUP_TOOLCHAIN="$TOOLCHAIN" MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" CARGO_TARGET_DIR="$BUILD_DIR/lib" "$CARGO_BIN" rustc \
        --manifest-path "$SOURCE_DIR/Cargo.toml" \
        --lib \
        --release \
        --locked \
        --features c-api \
        --crate-type staticlib \
        --target "$RUST_TARGET" \
        --config 'profile.release.lto=false'
    RUST_LIBRARIES+=("$BUILD_DIR/lib/$RUST_TARGET/release/libtlottie.a")
done

MERGED_LIBRARY="$(mktemp "$BUILD_DIR/libtlottie.XXXXXX")"
trap 'rm -f "$MERGED_LIBRARY"' EXIT
lipo -create "${RUST_LIBRARIES[@]}" -output "$MERGED_LIBRARY"

if ! cmp -s "$MERGED_LIBRARY" "$BUILD_DIR/libtlottie.a"; then
    mv "$MERGED_LIBRARY" "$BUILD_DIR/libtlottie.a"
fi

lipo -info "$BUILD_DIR/libtlottie.a"
