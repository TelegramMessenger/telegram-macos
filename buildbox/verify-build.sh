#!/bin/sh
set -e

BUILD_DIR="$1"
SOURCE_DIR="$2"
APP="$BUILD_DIR/Telegram.app"
SIZE_RECORD="$BUILD_DIR.app-size"
MAX_GROWTH_PERCENT=30

fail() {
    echo "error: $1" >&2
    exit 1
}

[ -d "$APP" ] || fail "$APP was not built"

python3 "$SOURCE_DIR/buildbox/verify-no-labs.py" "$APP"
python3 "$SOURCE_DIR/buildbox/verify-share-extension-signing.py" "$APP"

expected_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SOURCE_DIR/Telegram-Mac/Info.plist")
built_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
[ "$built_version" = "$expected_version" ] || fail "the built app is $built_version but this commit is $expected_version, so another build wrote into $BUILD_DIR"

share_plist="$APP/Contents/PlugIns/TelegramShare.appex/Contents/Info.plist"
if [ -f "$share_plist" ]; then
    share_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$share_plist")
    [ "$share_version" = "$expected_version" ] || fail "the share extension is $share_version but this commit is $expected_version"
fi

root_items=$(ls -A "$APP")
[ "$root_items" = "Contents" ] || fail "unexpected items at the root of Telegram.app: $(echo $root_items)"

nested_apps=$(find "$APP" -mindepth 1 -name "Telegram.app")
[ -z "$nested_apps" ] || fail "Telegram.app contains another copy of itself: $nested_apps"

main_binaries=$(find "$APP" -type f -path "*/MacOS/Telegram" | wc -l | tr -d ' ')
[ "$main_binaries" = "1" ] || fail "Telegram.app contains $main_binaries main executables instead of 1"

size=$(du -sk "$APP" | cut -f1)
if [ -f "$SIZE_RECORD" ]; then
    previous=$(cat "$SIZE_RECORD")
    limit=$((previous * (100 + MAX_GROWTH_PERCENT) / 100))
    if [ "$size" -gt "$limit" ] && [ "$ALLOW_SIZE_JUMP" != "1" ]; then
        fail "Telegram.app is $((size / 1024)) MB, more than $MAX_GROWTH_PERCENT% above the last deployed build ($((previous / 1024)) MB). Set the CI variable ALLOW_SIZE_JUMP=1 to deploy it anyway."
    fi
fi
echo "$size" > "$SIZE_RECORD.pending"

echo "Telegram.app $built_version verified: $((size / 1024)) MB"
