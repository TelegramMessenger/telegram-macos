#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
flags=(-lbz2 -liconv)
for directory in \
    libvpx/build/libvpx/lib ffmpeg/build/ffmpeg/lib libopus/build/libopus/lib \
    libwebp/build/libwebp/lib Mozjpeg/build openssl/build/openssl/lib \
    webrtc/build/webrtc OpenH264/build/output/lib dav1d/build/dav1d/lib tde2e/build/tde2e/lib
do
    for library in "$repo_root/core-xprojects/$directory"/*.a; do
        [[ -f "$library" ]] || { echo "Missing native libraries: $directory" >&2; exit 1; }
        flags+=("$library")
    done
done
cd "$repo_root"
exec xcodebuild test -workspace Telegram-Mac.xcworkspace -scheme SettingsUIAccountResetTests -derivedDataPath "$repo_root/.build/Xcode" -destination 'platform=macOS,arch=arm64' "OTHER_LDFLAGS=\$(inherited) ${flags[*]}" "$@"
