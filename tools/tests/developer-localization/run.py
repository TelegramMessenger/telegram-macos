import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
LOCALIZATION = 'packages/Localization/Sources/Localization/LocalizableExtension.swift'
CONTROLLER = 'packages/SettingsUI/Sources/SettingsUI/DeveloperViewController.swift'


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        if source[cursor] == '{':
            depth += 1
        elif source[cursor] == '}':
            depth -= 1
        cursor += 1
    return source[start:cursor]


def catalog(path):
    result = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)], text=True)
    return json.loads(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    source = subprocess.check_output(['git', 'show', f'origin/master:{LOCALIZATION}'], cwd=ROOT, text=True) if args.baseline else (ROOT / LOCALIZATION).read_text()
    baseline_controller = subprocess.check_output(['git', 'show', f'origin/master:{CONTROLLER}'], cwd=ROOT, text=True)
    controller = (ROOT / CONTROLLER).read_text()
    english = catalog(ROOT / 'Telegram-Mac/en.lproj/Localizable.strings')
    russian = catalog(ROOT / 'Telegram-Mac/ru.lproj/Localizable.strings')
    for code, values in [('en', english), ('ru', russian)]:
        raw = (ROOT / f'Telegram-Mac/{code}.lproj/Localizable.strings').read_text(encoding='utf-16')
        keys = re.findall(r'^"([^"\n]+)"\s*=', raw, re.M)
        assert all(keys.count(key) == 1 for key in keys if key.startswith('Developer.')), f'Duplicate developer keys in {code}'
        for key, value in values.items():
            if key.startswith('Developer.'):
                base = re.sub(r'_(one|few|many|other)$', '_other', key)
                assert base in english, key
                assert sorted(re.findall(r'%\d+\$[@df]', value)) == sorted(re.findall(r'%\d+\$[@df]', english[base])), key
    selectors = re.findall(r'(?:\.plain\(|name: )(strings\(\)\.\w+)', controller)
    assert len(selectors) == 22, len(selectors)
    before = re.findall(r'(?:\.plain\(|name: )"([^"\n]+)"', baseline_controller)
    assert len(before) == len(selectors), (len(before), len(selectors))
    assert 'combineLatest(statePromise.get(), languageSignal)' in controller
    assert 'controller.getTitle = { strings().developerTitle }' in controller
    assert not re.search(r'(?:name: |header: |title: |information: |\.plain\()"[A-Za-z]', controller)
    output = args.output.resolve() if args.output else None
    if output:
        output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='telegram-developer-localization-') as temporary:
        temp = Path(temporary)
        app = temp / 'DeveloperLocalizationHarness.app'
        binary_dir = app / 'Contents/MacOS'
        resources = app / 'Contents/Resources'
        binary_dir.mkdir(parents=True)
        resources.mkdir(parents=True)
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.telegram.tests.developer-localization', 'CFBundleExecutable': 'DeveloperLocalizationHarness', 'CFBundleDevelopmentRegion': 'en', 'CFBundlePackageType': 'APPL', 'CFBundleName': 'DeveloperLocalizationHarness'}))
        for code in ['en', 'ru', 'uk']:
            destination = resources / f'{code}.lproj'
            destination.mkdir()
            shutil.copy2(ROOT / f'Telegram-Mac/{code}.lproj/Localizable.strings', destination / 'Localizable.strings')
        bridge_source = (ROOT / 'packages/Strings/Sources/Strings/Strings.swift').read_text()
        bridge = block(bridge_source, 'public extension String {')
        markers = ['public class Language : Equatable {', 'public func ==(lhs:Language, rhs:Language) -> Bool {', 'public final class TelegramLocalization : Equatable {', 'public func translate(key: String, _ args: [CVarArg]) -> String {', '@inline(__always)\nprivate func resolveFormat', 'internal func extractArgumentRanges', 'private let _englishFallbackBundle', 'internal func _LocalizedStringFor', 'public func _NSLocalizedString', 'public func NativeLocalization', 'public func strings()']
        if not args.baseline:
            markers += ['private let _localizedFallbackBundles', 'private func bundledLocalizationFallbacks', 'private func bundledLocalizedString']
        pieces = []
        for marker in markers:
            part = block(source, marker)
            if marker.startswith('private let '):
                part += '()'
            pieces.append(part)
        constants = source[source.index('private let ZeroValueHolder'):source.index('public func translate(')]
        argument_regex = next(line for line in source.splitlines() if line.startswith('private let argumentRegex = '))
        pluralization = (ROOT / 'packages/Localization/Sources/Localization/StringPluralization.swift').read_text().replace('import NumberPluralization', '')
        language_state = '''var appCurrentLanguage = TelegramLocalization(primaryLanguage: Language(languageCode: "en", customPluralizationCode: nil, strings: [:]), secondaryLanguage: nil, localizedName: "English")\n'''
        production = 'import AppKit\nimport Foundation\n' + bridge + '\n' + constants + '\n' + argument_regex + '\n' + pluralization + '\n' + '\n\n'.join(pieces) + '\n' + language_state
        (temp / 'Production.swift').write_text(production)
        shutil.copy2(ROOT / 'packages/Localization/Sources/Localization/Localizable.swift', temp / 'Localizable.swift')
        rows = []
        for accessor in selectors:
            is_header = accessor in re.findall(r'\.plain\((strings\(\)\.\w+)', controller)
            rows.append(f'({accessor}, {str(is_header).lower()})')
        before_rows = []
        for label in before:
            before_rows.append(f'({json.dumps(label)}, {str(label.isupper()).lower()})')
        preview = 'func previewRows() -> [(String, Bool)] { [' + ', '.join(rows) + '] }\nfunc beforeRows() -> [(String, Bool)] { [' + ', '.join(before_rows) + '] }\n'
        (temp / 'PreviewRows.swift').write_text(preview)
        shutil.copy2(HERE / 'Harness.swift', temp / 'main.swift')
        native = ROOT / 'packages/NumberPluralization/Sources/NumberPluralization'
        subprocess.run(['clang', '-c', str(native / 'NumberPluralizationForm.m'), '-o', str(temp / 'Pluralization.o')], check=True)
        binary = binary_dir / 'DeveloperLocalizationHarness'
        subprocess.run(['swiftc', '-swift-version', '5', '-O', '-import-objc-header', str(native / 'NumberPluralizationForm.h'), str(temp / 'Production.swift'), str(temp / 'Localizable.swift'), str(temp / 'PreviewRows.swift'), str(temp / 'main.swift'), str(temp / 'Pluralization.o'), '-o', str(binary)], check=True)
        hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in [LOCALIZATION, CONTROLLER, 'packages/Localization/Sources/Localization/Localizable.swift', 'Telegram-Mac/en.lproj/Localizable.strings', 'Telegram-Mac/ru.lproj/Localizable.strings']}
        print(json.dumps({'baseline': args.baseline, 'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'inputs': hashes}), flush=True)
        command = [str(binary), '-AppleLanguages', '(en)']
        if output:
            command += ['--output', str(output)]
        result = subprocess.run(command)
        if result.returncode == 0:
            result = subprocess.run([str(binary), '-AppleLanguages', '(ru)'])
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
