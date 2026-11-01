import argparse
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--repo', type=Path, required=True)
parser.add_argument('--derived-data', type=Path, required=True)
parser.add_argument('--build-log', type=Path, required=True)
parser.add_argument('--rnoise', type=Path)
args = parser.parse_args()
repo = args.repo.resolve()
source = Path(__file__).resolve().parents[3]
for relative in ['packages/StarsUI/Sources/StarsUI/StarTransactionTabsRowItem.swift', 'packages/TGUIKit/Sources/GlassSegmentView.swift']:
    if (repo / relative).read_bytes() != (source / relative).read_bytes():
        raise SystemExit(f'Build the changed source before testing: {relative}')

lines = args.build_log.read_text().splitlines()
compile_line = next((line for line in lines if 'builtin-SwiftDriver --' in line and '-module-name ChatUITests ' in line), None)
if compile_line is None:
    raise SystemExit('Provide a successful ChatUITests build log containing its SwiftDriver command')
original = shlex.split(compile_line.split(' -- ', 1)[1])
flags = []
index = 1
while index < len(original):
    argument = original[index]
    if argument in {'-target', '-sdk', '-I', '-Isystem', '-F', '-Fsystem', '-Xcc', '-swift-version', '-D'}:
        flags.extend(original[index:index + 2])
        index += 2
    elif argument.startswith(('-I', '-F', '-D')):
        flags.append(argument)
        index += 1
    else:
        index += 1

filelist = args.derived_data / 'Build/Intermediates.noindex/ChatUI.build/Debug/ChatUITests-p.build/Objects-normal/arm64/ChatUITests.LinkFileList'
objects = [path for path in shlex.split(filelist.read_text()) if '/ChatUITests-p.build/' not in path]
if not objects or any(not Path(path).is_file() for path in objects):
    raise SystemExit('Build ChatUITests in the supplied DerivedData directory first')
libraries = ['-lbz2', '-liconv', '-lc++', '-lz']
if args.rnoise:
    libraries.append(str(args.rnoise.resolve()))
for relative in ['libvpx/build/libvpx/lib', 'ffmpeg/build/ffmpeg/lib', 'libopus/build/libopus/lib', 'libwebp/build/libwebp/lib', 'Mozjpeg/build', 'openssl/build/openssl/lib', 'webrtc/build/webrtc', 'OpenH264/build/output/lib', 'dav1d/build/dav1d/lib', 'tde2e/build/tde2e/lib']:
    libraries.extend(str(path) for path in sorted((repo / 'core-xprojects' / relative).glob('*.a')))
developer = subprocess.check_output(['xcode-select', '-p'], text=True).strip()
frameworks = developer + '/Platforms/MacOSX.platform/Developer/Library/Frameworks'
libraries.append('-L' + developer + '/Platforms/MacOSX.platform/Developer/usr/lib')
bootstrap = repo / 'packages/ChatUI/Tests/ChatUITests/UITestBootstrap.swift'
fixture = Path(__file__).with_name('StarTransactionTabsTests.swift')
with tempfile.TemporaryDirectory(prefix='stars-pill-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text('import XCTest\nimport Darwin\nlet suite = StarTransactionTabsTests.defaultTestSuite\nsuite.run()\nexit(suite.testRun?.hasSucceeded == true ? 0 : 1)\n')
    response = directory / 'objects.resp'
    response.write_text('\n'.join(shlex.quote(path) for path in objects))
    executable = directory / 'tests'
    subprocess.run([original[0], '-module-name', 'StarsPillReviewTests', '-module-cache-path', str(directory / 'ModuleCache'), *flags, str(fixture), str(bootstrap), str(main), '@' + str(response), *libraries, '-framework', 'Speech', '-framework', 'XCTest', '-Xlinker', '-rpath', '-Xlinker', frameworks, '-o', str(executable)], check=True)
    environment = dict(os.environ, DYLD_LIBRARY_PATH=developer + '/Platforms/MacOSX.platform/Developer/usr/lib')
    raise SystemExit(subprocess.run([str(executable)], env=environment).returncode)
