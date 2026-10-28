from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--configuration', choices=['debug', 'release'], default='debug')
parser.add_argument('--output', type=Path)
args = parser.parse_args()
output = args.output.resolve() if args.output else None
if output:
    output.mkdir(parents=True, exist_ok=True)
sources = {
    'Sources/TelegramUtils/RelativeDateTimeEntity.swift': 'packages/TelegramUtils/Sources/TelegramUtils/RelativeDateTimeEntity.swift',
    'Sources/MessageTextUtils/RelativeDateUpdateTimer.swift': 'packages/MessageTextUtils/Sources/MessageTextUtils/RelativeDateUpdateTimer.swift',
    'Tests/TelegramUtilsTests/RelativeDateTimeEntityTests.swift': 'packages/TelegramUtils/Tests/TelegramUtilsTests/RelativeDateTimeEntityTests.swift',
    'Tests/MessageTextUtilsTests/RelativeDateUpdateTimerTests.swift': 'packages/MessageTextUtils/Tests/MessageTextUtilsTests/RelativeDateUpdateTimerTests.swift',
}
with tempfile.TemporaryDirectory(prefix='telegram-relative-date-timers-') as directory:
    package = Path(directory)
    (package / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RelativeDateTimerTests", platforms: [.macOS(.v12)], targets: [
    .target(name: "TelegramUtils"),
    .target(name: "MessageTextUtils", dependencies: ["TelegramUtils"]),
    .testTarget(name: "TelegramUtilsTests", dependencies: ["TelegramUtils"]),
    .testTarget(name: "MessageTextUtilsTests", dependencies: ["MessageTextUtils"]),
])
''')
    for target, source in sources.items():
        destination = package / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / source, destination)
    result = subprocess.run(['swift', 'test', '--package-path', str(package), '-c', args.configuration, '-j', '4'], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout)
    if output:
        (output / f'{args.configuration}.log').write_text(result.stdout)
        (output / f'{args.configuration}-inputs.json').write_text(json.dumps({source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest() for source in sources.values()}, indent=2) + '\n')
    raise SystemExit(result.returncode)
