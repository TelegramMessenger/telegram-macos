import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=root)
parser.add_argument('--dependency-root', type=Path, default=root)
args = parser.parse_args()
source = args.source_root / 'packages/ChatUI/Sources/ChatUI'
with tempfile.TemporaryDirectory(prefix='save-photos-') as temp:
    temp = Path(temp)
    sources = temp / 'Sources'
    sources.mkdir()
    action = (source / 'ChatPhotoSaveAction.swift').read_text()
    action = '\n'.join(line for line in action.splitlines() if not line.startswith('import ') or line in ['import Cocoa', 'import SwiftSignalKit'])
    (sources / 'ChatPhotoSaveAction.swift').write_text(action)
    (sources / 'ChatPhotoBatchWriter.swift').write_bytes((source / 'ChatPhotoBatchWriter.swift').read_bytes())
    row = (source / 'ChatRowView.swift').read_text()
    start = row.index('    public override func rightMouseDown(with event: NSEvent) {')
    end = row.index('\n    }', start) + len('\n    }')
    fixtures = Path(__file__).with_name('Fixtures.swift').read_text().replace('__RIGHT_MOUSE_DOWN__', row[start:end])
    (sources / 'Fixtures.swift').write_text(fixtures)
    menu_candidates = next(line.strip() for line in (source / 'ChatMessageMenuItems.swift').read_text().splitlines() if 'let photoMessages =' in line)
    tests = Path(__file__).with_name('Tests.swift').read_text().replace('__PHOTO_MESSAGES__', menu_candidates)
    (sources / 'main.swift').write_text(tests)
    dependency = json.dumps(str(args.dependency_root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (temp / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "SavePhotos", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ' + dependency + ')], targets: [.executableTarget(name: "SavePhotos", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Sources")])\n')
    raise SystemExit(subprocess.run(['swift', 'run', '--package-path', str(temp), '--disable-sandbox', '--jobs', '2', 'SavePhotos']).returncode)
