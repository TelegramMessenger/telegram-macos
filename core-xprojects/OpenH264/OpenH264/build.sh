#!/bin/bash

# Enable error handling and verbose output
set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../../scripts/build-architectures.sh"

# Define the source directory and build directory from script arguments
SOURCE_DIR=$1

# Determine the absolute path for the build directory
BUILD_DIR=$(echo "$(cd "$(dirname "$3")"; pwd -P)/$(basename "$3")")
BUILD_DIR="${BUILD_DIR}build"

# Create the build directory if it does not exist
mkdir -p ${BUILD_DIR}

# Clone OpenH264 into the build directory if not already cloned
if [ ! -d "${BUILD_DIR}/openh264" ]; then
    git clone -b v2.4.1 https://github.com/cisco/openh264.git ${BUILD_DIR}/openh264
fi

# Define the output prefix for the final universal binary
USED_PREFIX=${BUILD_DIR}/output
mkdir -p ${USED_PREFIX}/lib
mkdir -p ${USED_PREFIX}/include

# Function to build for a specific architecture using make
buildOneArch() {
    arch=$1
    folder=${BUILD_DIR}/${arch}

    # Clean previous build artifacts if any exist
    make -C ${BUILD_DIR}/openh264 clean

    # Set appropriate compiler flags for each architecture
    if [ "$arch" = "arm64" ]; then
        export CFLAGS="-arch arm64"
    elif [ "$arch" = "x86_64" ]; then
        export CFLAGS="-arch x86_64"
    fi

    # Build the library for the specified architecture using make
    make -C ${BUILD_DIR}/openh264 ARCH=${arch} PREFIX=${folder} install-static

    # Manually copy the include files to the appropriate location
    mkdir -p ${folder}/include
    #cp -R ${BUILD_DIR}/openh264/include/* ${folder}/include/

    # Move the built static library to a temporary location for merging
    mv ${folder}/lib/libopenh264.a ${folder}/libopenh264.a
}

LIBRARIES=()
for ARCH in $TELEGRAM_BUILD_ARCHS; do
    buildOneArch "$ARCH"
    LIBRARIES+=("$BUILD_DIR/$ARCH/libopenh264.a")
done

# Ensure the output include directory exists and copy headers from one architecture
HEADER_ARCH="${TELEGRAM_BUILD_ARCHS%% *}"
cp -R "$BUILD_DIR/$HEADER_ARCH/include" "$USED_PREFIX/include"

# Ensure the output directory exists before creating the universal binary
mkdir -p ${USED_PREFIX}/lib

lipo -create "${LIBRARIES[@]}" -output "$USED_PREFIX/lib/libopenh264.a"

echo "Built $TELEGRAM_BUILD_ARCHS at: ${USED_PREFIX}/lib/libopenh264.a"
echo "Headers are available at: ${USED_PREFIX}/include"
