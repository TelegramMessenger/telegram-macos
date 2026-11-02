import argparse
import os
from pathlib import Path
import platform
import shlex
import subprocess


root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--derived-data', type=Path, default=root / '.build/Xcode')
parser.add_argument('--build-log', type=Path, required=True)
args = parser.parse_args()
derived = args.derived_data.resolve()
products = derived / 'Build/Products/Debug'
app = products / 'Telegram.app/Contents'
library = app / 'MacOS/Telegram.debug.dylib'
if not library.is_file():
    raise SystemExit('Build the Debug Telegram app before running playback tests')

compiler_flags = None
for line in args.build_log.read_text().splitlines():
    if 'builtin-SwiftDriver' in line and '-module-name TelegramMedia ' in line:
        tokens = shlex.split(line)
        compiler_flags = []
        index = 0
        while index < len(tokens):
            if tokens[index] in {'-I', '-F', '-Xcc'}:
                compiler_flags.extend(tokens[index:index + 2])
                index += 2
            else:
                index += 1
if compiler_flags is None:
    raise SystemExit('The build log must contain a TelegramMedia Swift compilation')

output = root / '.build/video-playback-tests'
output.mkdir(parents=True, exist_ok=True)
executable = output / 'VideoPlaybackTests'
developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
testing_frameworks = developer / 'Platforms/MacOSX.platform/Developer/Library/Frameworks'
testing_libraries = developer / 'Platforms/MacOSX.platform/Developer/usr/lib'
command = [
    'xcrun', 'swiftc', '-swift-version', '5', '-module-name', 'VideoPlaybackTests',
    '-target', platform.machine() + '-apple-macos14.4',
    '-module-cache-path', str(output / 'ModuleCache'),
    *compiler_flags,
    '-F', str(testing_frameworks),
    '-I', str(testing_libraries), '-L', str(testing_libraries),
    str(Path(__file__).with_name('VideoPlaybackTests.swift')), str(library),
    '-Xlinker', '-rpath', '-Xlinker', str(app / 'MacOS'),
    '-Xlinker', '-rpath', '-Xlinker', str(app / 'Frameworks'),
    '-Xlinker', '-rpath', '-Xlinker', str(testing_frameworks),
    '-Xlinker', '-rpath', '-Xlinker', str(testing_libraries),
    '-o', str(executable),
]
result = subprocess.run(command)
if result.returncode:
    raise SystemExit(result.returncode)
environment = dict(os.environ)
environment['VIDEO_PLAYBACK_FIXTURES'] = str(Path(__file__).with_name('fixtures'))
raise SystemExit(subprocess.run([str(executable)], env=environment).returncode)
