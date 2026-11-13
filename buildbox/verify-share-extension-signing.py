#!/usr/bin/env python3

import plistlib
import subprocess
import sys
from pathlib import Path


def verify_entitlements(share_extension, entitlements):
    profile = share_extension / "Contents" / "embedded.provisionprofile"
    keychain_groups = entitlements.get("keychain-access-groups")
    if keychain_groups and not profile.is_file():
        raise ValueError(
            "TelegramShare.appex has keychain-access-groups but no embedded.provisionprofile"
        )


def read_entitlements(executable, codesign):
    result = subprocess.run(
        [codesign, "--display", "--entitlements", ":-", str(executable)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    plist_start = result.stdout.find(b"<?xml")
    if plist_start < 0:
        raise ValueError(f"could not read signed entitlements from {executable}")
    try:
        return plistlib.loads(result.stdout[plist_start:])
    except Exception as error:
        raise ValueError(f"could not parse signed entitlements from {executable}") from error


def verify(app, codesign="codesign"):
    share_extension = app / "Contents" / "PlugIns" / "TelegramShare.appex"
    if not share_extension.is_dir():
        return

    executable = share_extension / "Contents" / "MacOS" / "TelegramShare"
    entitlements = read_entitlements(executable, codesign)
    verify_entitlements(share_extension, entitlements)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("usage: verify-share-extension-signing.py <app bundle>")
        verify(Path(sys.argv[1]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"error: {error}")
