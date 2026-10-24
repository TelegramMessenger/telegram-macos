#!/bin/sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../../scripts/build-architectures.sh"

SOURCE_DIR="$1"
BUILD_DIR="$2"

if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ]; then
    echo "Usage: $0 SOURCE_DIR BUILD_DIR"
    echo "Example: $0 /path/to/dav1d/source /path/to/build/directory"
    exit 1
fi

MESON_OPTIONS="--buildtype=release --default-library=static -Denable_tools=false -Denable_tests=false"

# Ensure build directory exists
mkdir -p "$BUILD_DIR"

LIBRARIES=()
for ARCH in $TELEGRAM_BUILD_ARCHS; do
    echo "Building for $ARCH..."
    mkdir -p "$BUILD_DIR/$ARCH"
    pushd "$BUILD_DIR/$ARCH"
    meson setup "$SOURCE_DIR" --cross-file="$SCRIPT_DIR/../dav1d-$ARCH.meson" $MESON_OPTIONS
    ninja
    popd
    LIBRARIES+=("$BUILD_DIR/$ARCH/src/libdav1d.a")
done

mkdir -p "$BUILD_DIR/dav1d/lib"
lipo -create "${LIBRARIES[@]}" -output "$BUILD_DIR/dav1d/lib/libdav1d.a"

# Copy include files from the source directory
echo "Copying include files from source directory..."
mkdir -p "$BUILD_DIR/dav1d/include"
cp -R "$SOURCE_DIR/include/dav1d" "$BUILD_DIR/dav1d/include/"

echo "Built $TELEGRAM_BUILD_ARCHS at $BUILD_DIR/dav1d/lib/libdav1d.a"
echo "Headers copied to $BUILD_DIR/dav1d/include/"
