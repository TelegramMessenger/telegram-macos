from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def declaration(source, marker):
    assert source.count(marker) == 1, marker
    start = source.index(marker)
    masked = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', lambda m: ' ' * len(m.group()), source, flags=re.S)
    opening = masked.index('{', start)
    depth = 1
    for index in range(opening + 1, len(masked)):
        depth += (masked[index] == '{') - (masked[index] == '}')
        if depth == 0:
            return source[start:index + 1]
    raise AssertionError(marker)


model = (ROOT / 'packages/InAppSettings/Sources/InAppSettings/BaseApplicationSettings.swift').read_text()
model = model[:model.index('public func baseAppSettings(')]
model = re.sub(r'^import (Cocoa|Postbox|SwiftSignalKit|TelegramCore)\n', '', model, flags=re.M)
main = (ROOT / 'Telegram-Mac/app/MainViewController.swift').read_text()
settings = (ROOT / 'packages/SettingsUI/Sources/SettingsUI/GeneralSettingsViewController.swift').read_text()
methods = '\n'.join(declaration(main, marker).replace('private func', 'func') for marker in ['private func showContactsTab()', 'private func hideContactsTab()', 'private func showCallsTab()', 'private func hideCallsTab()', 'var chatIndex: Int', 'var settingsIndex: Int'])
start = main.index('            if settings.showCallsTab != self.showCallTabs')
end = main.index('        }))', start)
update = main[start:end]
fixture = Path(__file__).with_name('ContactsTabTests.swift.in').read_text().replace('__MODEL__', model).replace('__METHODS__', methods).replace('__UPDATE__', update)
assert '__MODEL__' not in fixture and '__METHODS__' not in fixture and '__UPDATE__' not in fixture
with tempfile.TemporaryDirectory(prefix='contacts-only-tests-') as temporary:
    temp = Path(temporary)
    (temp / 'main.swift').write_text(fixture)
    subprocess.run(['swiftc', str(temp / 'main.swift'), '-o', str(temp / 'tests')], check=True)
    subprocess.run([str(temp / 'tests')], check=True)

assert 'case showContactsTab(' in settings
assert 'name: "Show Contacts Tab"' in settings and '//TODOLANG' in settings
assert 'arguments.toggleContactsTab(!enabled)' in settings
assert 'return settings.withUpdatedShowContactsTab(enable)' in settings
assert 'enabled: baseSettings.showContactsTab' in settings
ids = declaration(settings, 'public var stableId: Int')
pairs = re.findall(r'case \.(\w+):\s*return (\d+)', ids)
assert len({int(value) for _, value in pairs}) == len(pairs)
order = dict(pairs)
assert int(order['showCallsTab']) < int(order['showContactsTab']) < int(order['statusBar'])
assert 'if showContactTabs {\n                tabController.replace' in main
assert 'self.tabController.select(index: showContactTabs ? 1 : 0)' in main
for path in ['packages/TGUIKit/Sources/TabBarController.swift', 'packages/TGUIKit/Sources/TabBarView.swift', 'packages/TGUIKit/Sources/TabItem.swift', 'packages/TGUIKit/Tests/TGUIKitTests/TabBarViewTreeTests.swift', 'Telegram-Mac/en.lproj/Localizable.strings', 'packages/Localization/Sources/Localization/Localizable.swift']:
    assert (ROOT / path).read_bytes() == subprocess.check_output(['git', '-C', str(ROOT), 'show', 'HEAD:' + path]), path
print('PASS: Contacts settings wiring/order, Calls shortcut/theme indexing, unchanged TGUIKit/localization')
print('Scope: actual settings Codable/mutators and extracted controller update/methods; tab operations use a model adapter, not live AppKit or full application build.')
