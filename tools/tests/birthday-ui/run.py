import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/SettingsUI/Sources/SettingsUI/EditAccountInfoController.swift')
args = parser.parse_args()
s = args.source.read_text()
def block(source, marker):
    a = source.index(marker)
    b = source.index('{', a) + 1
    depth = 1
    while depth:
        depth += (source[b] == '{') - (source[b] == '}')
        b += 1
    return source[a:b]
fixture = Path(__file__).with_name('BirthdayUITests.swift').read_text()
helper = (root / 'packages/SettingsUI/Sources/SettingsUI/EditAccountProfileSaveAction.swift').read_text()
helper = '\n'.join(line for line in helper.splitlines() if not line.startswith('import '))
fixture = fixture.replace('__HELPER__', helper)
fixture = fixture.replace('__GLOBAL__', block(s, 'public func editAccountUpdateBirthday').replace('public ', '').replace('any AccountContextProtocol', 'Context'))
fixture = fixture.replace('__UPDATE__', block(s, '    let updateBirthday:') if '    let updateBirthday:' in s else '')
calendar = s[s.index('    }, birthday: {'):]
calendar = block(calendar, '            let controller = SettingsNavigationHooks.shared.makeBirthdayCalendarController') + ')'
fixture = fixture.replace('__CALENDAR__', calendar)
fixture = fixture.replace('__REMOVE__', block(s, '}, removeBirthday:').split('removeBirthday: ', 1)[1])
fixture = fixture.replace('__HOOKS__', '\n'.join(block(s, '    controller.' + name + ' =') for name in ['willDisappear', 'willAppear', 'onDeinit']))
with tempfile.TemporaryDirectory(prefix='birthday-ui-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BirthdayUI", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "BirthdayUITests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/BirthdayUITests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
