#!/usr/bin/env python3

import re
import subprocess
import sys
import tempfile
from pathlib import Path


LAB_MARKERS = re.compile(
    r"PerfLab|NetworkLab|EmojiPanelLab|GifPanelLab|ScreenCaptureLab|"
    r"CallVideoLab|PeerCallLab|VideoPlayerLab|ChatNavigationLab|PeerMediaLab|"
    r"UniqueGiftLab|StoryMorphLab|ChatListStoriesLab"
)
MACH_O_MAGICS = {
    bytes.fromhex(value)
    for value in ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")
}


def verify(app):
    if not app.is_dir():
        raise ValueError(f"app bundle does not exist: {app}")
    count = 0
    for path in sorted(app.rglob("*")):
        if path.is_symlink():
            continue
        if LAB_MARKERS.search(path.name):
            raise ValueError(f"lab artifact in app bundle: {path}")
        if not path.is_file():
            continue
        with path.open("rb") as source:
            if source.read(4) not in MACH_O_MAGICS:
                continue
        count += 1
        with tempfile.TemporaryDirectory(prefix="telegram-lab-check-") as directory:
            binary = Path(directory) / "binary"
            subprocess.run(["xcrun", "strip", "-S", "-o", str(binary), str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
            for command in (["xcrun", "nm", "-a", "-arch", "all", str(binary)], ["/usr/bin/strings", "-a", str(binary)]):
                with tempfile.TemporaryFile(mode="w+t") as output:
                    subprocess.run(command, stdout=output, stderr=subprocess.PIPE, text=True, check=True)
                    output.seek(0)
                    for line in output:
                        match = LAB_MARKERS.search(line)
                        if match:
                            raise ValueError(f"lab code in {path}: {match.group()}")
    if count == 0:
        raise ValueError(f"no Mach-O binaries found in {app}")
    print(f"Lab exclusion verified: {count} Mach-O binaries contain no lab symbols or launch markers")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("usage: verify-no-labs.py <app bundle>")
        verify(Path(sys.argv[1]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"error: {error}")
