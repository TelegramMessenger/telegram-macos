#!/bin/sh
set -eu

scripts_dir="$(CDPATH= cd "$(dirname "$0")" && pwd)"
ios="$scripts_dir/../submodules/telegram-ios"
patch="$scripts_dir/telegram-ios-macos.patch"

if [ ! -f "$ios/submodules/TelegramVoip/Package.swift" ]; then
    printf 'Initialize the telegram-ios submodule before preparing the macOS build.\n' >&2
    exit 1
fi

case "$#:${1:-}" in
    0:)
        if git -C "$ios" apply --reverse --check "$patch" 2>/dev/null; then
            exit 0
        fi
        ;;
    1:--reverse)
        if git -C "$ios" apply --check "$patch" 2>/dev/null; then
            exit 0
        fi
        ;;
    *)
        printf 'Usage: %s [--reverse]\n' "$0" >&2
        exit 2
        ;;
esac

git -C "$ios" apply --whitespace=nowarn "$@" "$patch"
