import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def code(path):
    if not (root / path).is_file():
        raise SystemExit(2)
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def function(text, signature):
    if signature not in text:
        raise SystemExit(2)
    start = text.index(signature)
    depth = 0
    for index in range(text.index('{', start), len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise SystemExit(2)


gallery = code('packages/GalleryUI/Sources/GalleryUI/GalleryViewer.swift')
permissions = code('packages/MessageUtils/Sources/MessageUtils/MessagePermissions.swift')

delete = function(gallery, 'private func deleteMessages(_ messages:[Message])').replace('private func', 'func', 1)
helpers = '\n\n'.join(function(permissions, f'public func {name}(').replace('public func', 'func', 1)
                      for name in ('canDeleteMessage', 'canDeleteForEveryoneMessage', 'mustDeleteForEveryoneMessage'))

fixture = (Path(__file__).with_name('GalleryDeleteConfirmTests.swift.in').read_text()
           .replace('__HELPERS__', helpers)
           .replace('__DELETE_MESSAGES__', delete))

with tempfile.TemporaryDirectory(prefix='gallery-delete-confirm-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
