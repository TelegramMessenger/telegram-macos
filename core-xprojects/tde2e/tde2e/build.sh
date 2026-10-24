#!/bin/sh

set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../../scripts/build-architectures.sh"

SOURCE_DIR="$1"
BUILD_DIR="$2"
OPENSSL_DIR="$3"

if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ] || [ -z "$OPENSSL_DIR" ]; then
    echo "Usage: $0 SOURCE_DIR BUILD_DIR OPENSSL_DIR"
    echo "Example: $0 /path/to/td /path/to/build /path/to/openssl"
    exit 1
fi

openssl_crypto_library="${OPENSSL_DIR}/lib/libcrypto.a"
options=""
options="$options -DOPENSSL_FOUND=1"
#options="$options -DOPENSSL_CRYPTO_LIBRARY=${openssl_crypto_library}"
options="$options -DOPENSSL_INCLUDE_DIR=${OPENSSL_DIR}/include"
options="$options -DCMAKE_BUILD_TYPE=Release"

# Step 1: Generate TDLib source files once
GEN_DIR="$BUILD_DIR/native-gen"
mkdir -p "$GEN_DIR"
pushd "$GEN_DIR"
cmake -DTD_GENERATE_SOURCE_FILES=ON "$SOURCE_DIR"
cmake --build . -- -j$(sysctl -n hw.ncpu)
popd

TDE2E_LIBRARIES=()
TDUTILS_LIBRARIES=()
for ARCH in $TELEGRAM_BUILD_ARCHS; do
    echo "Building for $ARCH..."
    mkdir -p "$BUILD_DIR/$ARCH"
    pushd "$BUILD_DIR/$ARCH"
    cmake "$SOURCE_DIR" -DCMAKE_OSX_ARCHITECTURES="$ARCH" $options
    cmake --build . --target tde2e -j$(sysctl -n hw.ncpu)
    popd
    TDE2E_LIBRARIES+=("$BUILD_DIR/$ARCH/tde2e/libtde2e.a")
    TDUTILS_LIBRARIES+=("$BUILD_DIR/$ARCH/tdutils/libtdutils.a")
done

UNIVERSAL_DIR="$BUILD_DIR/tde2e"
mkdir -p "$UNIVERSAL_DIR/lib"

lipo -create "${TDE2E_LIBRARIES[@]}" -output "$UNIVERSAL_DIR/lib/libtde2e.a"
lipo -create "${TDUTILS_LIBRARIES[@]}" -output "$UNIVERSAL_DIR/lib/libtdutils.a"
echo "Built $TELEGRAM_BUILD_ARCHS libraries in $UNIVERSAL_DIR/lib"
