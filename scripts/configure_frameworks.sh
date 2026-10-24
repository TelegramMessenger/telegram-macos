#!/bin/sh
set -e


declare -a libs=("OpenH264" "OpenSSL" "libopus" "libvpx" "mozjpeg" "libwebp" "dav1d" "ffmpeg" "webrtc" "tde2e" "wallet-engine" "mtproto-engine")
declare -a libname=("OpenH264" "OpenSSLEncryption" "libopus" "libvpx" "Mozjpeg" "libwebp" "dav1d" "ffmpeg" "webrtc" "tde2e" "WalletEngine" "MTProtoEngine")

arraylength=${#libs[@]}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." >/dev/null && pwd )"

. "$SCRIPT_DIR/build-architectures.sh"
FRAMEWORK_BUILD_SETTINGS=("ARCHS=$TELEGRAM_BUILD_ARCHS" "ONLY_ACTIVE_ARCH=NO")
if [ -n "${MACOSX_DEPLOYMENT_TARGET:-}" ]; then
    FRAMEWORK_BUILD_SETTINGS+=("MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET")
fi

python3 "$SCRIPT_DIR/prepare-telegram-api.py"

. "$SCRIPT_DIR/framework-inputs.sh"


python3 "$SCRIPT_DIR/prepare-flat-serialization.py"


RebuildFile="${SCRIPT_DIR}/rebuild"

FORCE_REBUILD="no"
if grep -q yes "$RebuildFile"; then
    FORCE_REBUILD="yes"
fi

STAMP_CACHE="$( mktemp -d )"
trap 'rm -rf "$STAMP_CACHE"' EXIT
FRAMEWORK_XCODE_VERSION="$(xcodebuild -version | tr '\n' ' ')"

for (( i=0; i<${arraylength}; i++ ));
do
    LIB=${libs[$i]}
    FWNAME=${libname[$i]}
    BUILD_DIR="$(framework_build_dir "$ROOT_DIR" "$LIB")"
    STAMP_FILE="$BUILD_DIR/.framework-stamp"
    framework_stamp "$ROOT_DIR" "$LIB" "$STAMP_CACHE" > "$STAMP_CACHE/$LIB"

    if [ "$FORCE_REBUILD" != "yes" ] && cmp -s "$STAMP_CACHE/$LIB" "$STAMP_FILE" && \
        framework_outputs_present "$ROOT_DIR" "$LIB" && framework_outputs_consistent "$ROOT_DIR" "$LIB"; then
        echo "framework-stamp: $LIB is up to date, skipping xcodebuild"
        continue
    fi

    if [ "$FORCE_REBUILD" = "yes" ] || ! cmp -s "$STAMP_CACHE/$LIB" "$STAMP_FILE"; then
        echo "framework-stamp: $LIB requires a rebuild"
        if [ -f "$STAMP_FILE" ]; then
            diff "$STAMP_FILE" "$STAMP_CACHE/$LIB" | sed 's/^/framework-stamp:   /' || true
        fi
        rm -rf "$BUILD_DIR"
        framework_reset_outputs "$ROOT_DIR" "$LIB"
    else
        echo "framework-stamp: $LIB outputs are missing or inconsistent, repairing"
        case "$LIB" in
            wallet-engine|mtproto-engine) framework_reset_outputs "$ROOT_DIR" "$LIB" ;;
            *) rm -rf "$BUILD_DIR" ;;
        esac
    fi
    rm -f "$STAMP_FILE"

    PROJECT_DIR="$(framework_project_dir "$ROOT_DIR" "$LIB")"
    sh "$ROOT_DIR/scripts/time-step.sh" "framework-$LIB" \
        xcrun xcodebuild build \
        -project "$PROJECT_DIR/$FWNAME.xcodeproj" \
        -configuration Release BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        -scheme "$FWNAME" \
        -derivedDataPath "$STAMP_CACHE/DerivedData-$LIB" \
        -destination 'generic/platform=macOS' \
        "${FRAMEWORK_BUILD_SETTINGS[@]}"

    if ! framework_outputs_present "$ROOT_DIR" "$LIB" || ! framework_outputs_consistent "$ROOT_DIR" "$LIB"; then
        echo "error: $LIB did not produce complete, consistent outputs" >&2
        exit 1
    fi
    cp "$STAMP_CACHE/$LIB" "$STAMP_FILE"
done

DIRECTORY_PAIRS=(
    "${SCRIPT_DIR}/../core-xprojects/libopus/build/libopus/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpusBinding/SharedHeaders/libopus/include"
    "${SCRIPT_DIR}/../core-xprojects/ffmpeg/build/ffmpeg/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/FFMpegBinding/SharedHeaders/ffmpeg/include"
    "${SCRIPT_DIR}/../core-xprojects/webrtc/build/src,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/webrtc"
    "${SCRIPT_DIR}/../core-xprojects/openssl/build/openssl/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/openssl/include"
    "${SCRIPT_DIR}/../core-xprojects/libopus/build/libopus/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/libopus/include"
    "${SCRIPT_DIR}/../core-xprojects/ffmpeg/build/ffmpeg/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/ffmpeg/include"
    "${SCRIPT_DIR}/../submodules/telegram-ios/third-party/rnnoise/PublicHeaders,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/rnoise"
    "${SCRIPT_DIR}/../core-xprojects/libwebp/build/libwebp/include,${SCRIPT_DIR}/../submodules/libwebp/SharedHeaders/libwebp/include"
    "${SCRIPT_DIR}/../core-xprojects/openssl/build/openssl/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpenSSLEncryptionProvider/SharedHeaders/openssl/include"
    "${SCRIPT_DIR}/../submodules/telegram-ios/submodules/EncryptionProvider/PublicHeaders,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpenSSLEncryptionProvider/SharedHeaders/EncryptionProvider"
    "${SCRIPT_DIR}/../core-xprojects/Mozjpeg/build,${SCRIPT_DIR}/../submodules/Mozjpeg/SharedHeaders/libmozjpeg"
    "${SCRIPT_DIR}/../submodules/telegram-ios/third-party/mozjpeg/mozjpeg,${SCRIPT_DIR}/../submodules/Mozjpeg/SharedHeaders/ios-mozjpeg"
)


for pair in "${DIRECTORY_PAIRS[@]}"; do
    IFS=',' read -r SOURCE_DIR DEST_DIR <<< "$pair"
    sh "$SCRIPT_DIR/sync-headers.sh" "$SOURCE_DIR" "$DEST_DIR"
done

sh "$SCRIPT_DIR/sync-headers.sh" \
    "$ROOT_DIR/submodules/telegram-ios/third-party/td/td" \
    "$ROOT_DIR/submodules/telegram-ios/third-party/td/TdBinding/SharedHeaders/td"

sh "$ROOT_DIR/scripts/time-step.sh" tlottie sh "$ROOT_DIR/core-xprojects/tlottie/build.sh"
