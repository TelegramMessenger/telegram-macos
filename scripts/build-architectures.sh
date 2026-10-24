#!/bin/bash

case "${TELEGRAM_BUILD_ARCHS:-${ARCHS:-arm64 x86_64}}" in
    arm64) TELEGRAM_BUILD_ARCHS=arm64 ;;
    x86_64) TELEGRAM_BUILD_ARCHS=x86_64 ;;
    "arm64 x86_64"|"x86_64 arm64") TELEGRAM_BUILD_ARCHS="arm64 x86_64" ;;
    *)
        echo "Unsupported architectures: ${TELEGRAM_BUILD_ARCHS:-${ARCHS:-}}" >&2
        return 1
        ;;
esac
export TELEGRAM_BUILD_ARCHS

telegram_rust_target() {
    case "$1" in
        arm64) echo aarch64-apple-darwin ;;
        x86_64) echo x86_64-apple-darwin ;;
        *) return 1 ;;
    esac
}
