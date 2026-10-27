import argparse
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--app-bundle', required=True, type=Path)
parser.add_argument('--build-log', required=True, type=Path)
parser.add_argument('--revision')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
profile_path = 'packages/PeerInfoUI/Sources/PeerInfoUI/PeerInfoController.swift'
if args.revision:
    source = subprocess.check_output(['git', '-C', str(root), 'show', f'{args.revision}:{profile_path}'], text=True)
else:
    source = (root / profile_path).read_text()
initializer = re.search(r'private let windowControlsGlass = ([^\n]+)', source).group(1)
flags = None
for line in args.build_log.read_text(errors='replace').splitlines():
    if 'builtin-SwiftDriver --' in line and '-module-name ComponentsUI ' in line:
        words = shlex.split(line)
        flags = []
        for index, word in enumerate(words):
            if word in ['-I', '-F', '-Xcc']:
                flags.extend([word, words[index + 1]])
        break
if flags is None:
    raise SystemExit('Build log must include a ComponentsUI Swift compiler invocation')
app = args.app_bundle.resolve()
library = app / 'Contents/MacOS/Telegram.debug.dylib'
if not library.is_file():
    raise SystemExit('An unsigned Debug app with Telegram.debug.dylib is required')
fixture = '''import AppKit
import TGUIKit
let application = NSApplication.shared
for _ in 0..<3 {
    autoreleasepool {
        let glass = __INITIALIZER__
        for width: CGFloat in [380, 500, 800] {
            let size = NSSize(width: width, height: 64)
            glass.updateLayout(size: size, transition: .immediate)
            precondition(glass.frame.size == size)
        }
    }
}
print("PASS: production profile glass construction and resizing against built TGUIKit")
'''.replace('__INITIALIZER__', initializer)
with tempfile.TemporaryDirectory(prefix='profile-glass-construction-') as directory:
    directory = Path(directory)
    swift = directory / 'main.swift'
    swift.write_text(fixture)
    executable = directory / 'profile-glass-construction'
    command = ['xcrun', 'swiftc', '-module-cache-path', str(directory / 'ModuleCache'), *flags, str(swift), str(library)]
    for path in [app / 'Contents/MacOS', app / 'Contents/Frameworks']:
        command.extend(['-Xlinker', '-rpath', '-Xlinker', str(path)])
    command.extend(['-o', str(executable)])
    compiled = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if compiled.returncode:
        print(compiled.stdout)
        raise SystemExit(compiled.returncode)
    result = subprocess.run([str(executable)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(result.stdout[:5000], end='')
    if result.returncode:
        print(f'Profile glass construction failed with exit {result.returncode}')
    raise SystemExit(0 if result.returncode == 0 else 1)
