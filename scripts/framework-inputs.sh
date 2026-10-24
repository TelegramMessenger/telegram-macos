#!/bin/bash

FRAMEWORK_STAMP_SCHEMA=2

framework_project_dir() {
    MATCH="$(ls "$1/core-xprojects" 2>/dev/null | awk -v n="$2" 'tolower($0) == tolower(n) { print; exit }')"
    if [ -n "$MATCH" ]; then
        echo "$1/core-xprojects/$MATCH"
    else
        echo "$1/core-xprojects/$2"
    fi
}

framework_build_dir() {
    echo "$(framework_project_dir "$1" "$2")/build"
}

framework_source_roots() {
    case "$2" in
        OpenSSL)
            echo "$1/submodules/telegram-ios/submodules/openssl"
            ;;
        mozjpeg)
            echo "$1/submodules/telegram-ios/third-party/mozjpeg/mozjpeg"
            ;;
        dav1d)
            echo "$1/submodules/telegram-ios/third-party/dav1d/dav1d"
            ;;
        ffmpeg)
            echo "$1/submodules/telegram-ios/submodules/ffmpeg/Sources/FFMpeg"
            ;;
        webrtc)
            echo "$1/submodules/tg_owt"
            ;;
        tde2e)
            echo "$1/submodules/telegram-ios/third-party/td/td"
            ;;
        wallet-engine)
            echo "$1/submodules/telegram-ios/third-party/wallet-engine/wallet-engine"
            ;;
        mtproto-engine)
            echo "$1/submodules/telegram-ios/third-party/mtproto-engine"
            ;;
        *)
            ;;
    esac
}

framework_inputs() {
    framework_project_dir "$1" "$2"
    framework_source_roots "$1" "$2"
    echo "$1/scripts/build-architectures.sh"
}

framework_dependencies() {
    case "$1" in
        ffmpeg) echo "libopus libvpx dav1d" ;;
        webrtc) echo "OpenH264 OpenSSL mozjpeg libopus libvpx ffmpeg" ;;
        tde2e) echo "OpenSSL" ;;
        *) echo "" ;;
    esac
}

framework_extra_fingerprint() {
    case "$1" in
        wallet-engine|mtproto-engine)
            CARGO_BIN=""
            if [ -n "${CARGO:-}" ]; then
                CARGO_BIN="$CARGO"
            elif command -v cargo >/dev/null 2>&1; then
                CARGO_BIN="$(command -v cargo)"
            elif [ -x "$HOME/.cargo/bin/cargo" ]; then
                CARGO_BIN="$HOME/.cargo/bin/cargo"
            fi
            if [ -n "$CARGO_BIN" ]; then
                echo "rust=$("$CARGO_BIN" --version 2>/dev/null || echo unavailable)"
            else
                echo "rust=missing"
            fi
            ;;
        *)
            ;;
    esac
}

framework_reset_outputs() {
    case "$2" in
        wallet-engine)
            rm -rf "$1/packages/WalletEngine/wallet_engineFFI.xcframework"
            ;;
        mtproto-engine)
            rm -rf "$1/submodules/telegram-ios/submodules/MTProtoRustEngine/MTProtoEngineFFI.xcframework"
            ;;
        *)
            ;;
    esac
}

framework_outputs_consistent() {
    case "$2" in
        wallet-engine)
            sh "$1/scripts/check-wallet-engine-bindings.sh" "$1"
            ;;
        *)
            ;;
    esac
}

framework_required_outputs() {
    local BUILD_DIR="$(framework_build_dir "$1" "$2")"
    local ARCHITECTURES="${TELEGRAM_BUILD_ARCHS:-arm64 x86_64}"
    local XCFRAMEWORK_SLICE="macos-${ARCHITECTURES// /_}"
    case "$2" in
        OpenH264)
            printf '%s\n' "$BUILD_DIR/output/lib/libopenh264.a" "$BUILD_DIR/output/include/include/wels/codec_api.h"
            ;;
        OpenSSL)
            printf '%s\n' "$BUILD_DIR/openssl/lib/libcrypto.a" "$BUILD_DIR/openssl/lib/libssl.a" "$BUILD_DIR/openssl/include/openssl/ssl.h"
            ;;
        libopus)
            printf '%s\n' "$BUILD_DIR/libopus/lib/libopus.a" "$BUILD_DIR/libopus/include/opus/opus.h"
            ;;
        libvpx)
            printf '%s\n' "$BUILD_DIR/libvpx/lib/libvpx.a" "$BUILD_DIR/libvpx/include/vpx/vpx_codec.h"
            ;;
        mozjpeg)
            printf '%s\n' "$BUILD_DIR/libjpeg.a" "$BUILD_DIR/jconfig.h" "$BUILD_DIR/jconfigint.h" "$BUILD_DIR/jpeglib.h"
            ;;
        libwebp)
            printf '%s\n' "$BUILD_DIR/libwebp/lib/"{libwebp,libwebpdecoder,libwebpdemux,libsharpyuv}.a "$BUILD_DIR/libwebp/include/"{decode,encode,types,demux,mux,mux_types}.h
            ;;
        dav1d)
            printf '%s\n' "$BUILD_DIR/dav1d/lib/libdav1d.a" "$BUILD_DIR/dav1d/include/dav1d/dav1d.h"
            ;;
        ffmpeg)
            printf '%s\n' "$BUILD_DIR/ffmpeg/lib/"{libavcodec,libavformat,libavutil,libswresample}.a "$BUILD_DIR/ffmpeg/include/libavcodec/avcodec.h"
            ;;
        webrtc)
            printf '%s\n' "$BUILD_DIR/webrtc/libmac_framework_objc_static.a" "$BUILD_DIR/src/api/peer_connection_interface.h"
            ;;
        tde2e)
            printf '%s\n' "$BUILD_DIR/tde2e/lib/"{libtde2e,libtdutils}.a
            ;;
        wallet-engine)
            local XCFRAMEWORK="$1/packages/WalletEngine/wallet_engineFFI.xcframework"
            printf '%s\n' "$BUILD_DIR/libwallet_engine.a" "$BUILD_DIR/WalletEngineFFI.swift" \
                "$XCFRAMEWORK/Info.plist" "$XCFRAMEWORK/$XCFRAMEWORK_SLICE/libwallet_engine.a" \
                "$XCFRAMEWORK/$XCFRAMEWORK_SLICE/Headers/"{wallet_engineFFI.h,module.modulemap}
            ;;
        mtproto-engine)
            local XCFRAMEWORK="$1/submodules/telegram-ios/submodules/MTProtoRustEngine/MTProtoEngineFFI.xcframework"
            printf '%s\n' "$BUILD_DIR/libmtproto_engine_ffi.a" "$XCFRAMEWORK/Info.plist" \
                "$XCFRAMEWORK/$XCFRAMEWORK_SLICE/libmtproto_engine_ffi.a" \
                "$XCFRAMEWORK/$XCFRAMEWORK_SLICE/Headers/MTProtoEngineFFI/"{mtproto_engine.h,module.modulemap}
            ;;
        *) return 1 ;;
    esac
}

framework_outputs_present() {
    local OUTPUT
    local OUTPUTS
    OUTPUTS="$(framework_required_outputs "$1" "$2")" || return 1
    [ -n "$OUTPUTS" ] || return 1
    while IFS= read -r OUTPUT; do
        [ -s "$OUTPUT" ] || return 1
    done <<< "$OUTPUTS"
}

framework_path_fingerprint() {
    TARGET="$1"
    if [ ! -e "$TARGET" ]; then
        echo "missing"
        return
    fi
    if [ -f "$TARGET" ]; then
        shasum -a 256 "$TARGET" | cut -d' ' -f1
        return
    fi
    if git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1; then
        TREE="$(git -C "$TARGET" rev-parse 'HEAD:./' 2>/dev/null || echo untracked)"
        DIRTY="$(git -C "$TARGET" status --porcelain -- . 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"
        if [ "$DIRTY" != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then
            DIRTY="$(python3 - "$TARGET" <<'PY'
import hashlib
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
digest = hashlib.sha256(subprocess.check_output(["git", "diff", "HEAD", "--binary", "--", "."], cwd=root))
untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z", "--", "."], cwd=root)
for name in sorted(untracked.split(b"\0")):
    if not name:
        continue
    path = root / os.fsdecode(name)
    digest.update(name + b"\0")
    digest.update(os.fsencode(os.readlink(path)) if path.is_symlink() else path.read_bytes())
    digest.update(b"\0")
print(digest.hexdigest())
PY
)" || return 1
        fi
        echo "$TREE.${DIRTY:0:12}"
        return
    fi
    find "$TARGET" -type f -exec shasum -a 256 {} + 2>/dev/null | sort | shasum -a 256 | cut -d' ' -f1
}

framework_stamp() {
    ROOT="$1"
    LIB="$2"
    CACHE_DIR="$3"
    echo "schema=$FRAMEWORK_STAMP_SCHEMA"
    echo "lib=$LIB"
    echo "architectures=${TELEGRAM_BUILD_ARCHS:-arm64 x86_64}"
    echo "xcode=${FRAMEWORK_XCODE_VERSION:-$(xcodebuild -version 2>/dev/null | tr '\n' ' ')}"
    echo "deployment=${MACOSX_DEPLOYMENT_TARGET:-default}"
    framework_extra_fingerprint "$LIB"
    while IFS= read -r INPUT; do
        [ -n "$INPUT" ] || continue
        echo "input:${INPUT#$ROOT/}=$(framework_path_fingerprint "$INPUT")"
    done <<< "$(framework_inputs "$ROOT" "$LIB")"
    for DEP in $(framework_dependencies "$LIB"); do
        DEP_STAMP="$CACHE_DIR/$DEP"
        if [ -f "$DEP_STAMP" ]; then
            echo "dependency:$DEP=$(shasum -a 256 "$DEP_STAMP" | cut -d' ' -f1)"
        else
            echo "dependency:$DEP=uncomputed"
        fi
    done
}
