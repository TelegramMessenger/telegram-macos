import argparse
import re
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


source = (root / 'packages/TranslateUI/Sources/TranslateUI/TranslateModalController.swift').read_text()
applied = section(source, '    let appliedText: () -> NSAttributedString? = {', '    let modalInteractions: ModalInteractions') if 'let appliedText' in source else ''
apply = section(source, '        modalInteractions = ModalInteractions(acceptTitle: strings().translateApply', '    } else if dismissOnly {')
start = next((marker for marker in ('    let draft = ChatTextInputState(', '    let entities = onUse == nil') if marker in source), None)
setup = section(source, start, '    let configTones') if start else ''
fixture = (Path(__file__).with_name('AIEditorOriginalTests.swift.in').read_text()
           .replace('__APPLIED_TEXT__', applied)
           .replace('__APPLY__', apply)
           .replace('__SETUP__', setup))

def code(path):
    text = (root / path).read_text()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


modal = code('packages/TranslateUI/Sources/TranslateUI/TranslateModalController.swift')
attach = code('packages/ChatUI/Sources/ChatUI/ChatInputAttachView.swift')
selection = code('packages/InputTextView/Sources/InputTextView/UIInputView.swift')
installs = code('Telegram-Mac/packages-integration/hooks/ChatInputUIHooksInstall.swift') + code('Telegram-Mac/packages-integration/hooks/InputTextViewHooksInstall.swift')
passes_draft = re.findall(r'TranslateModalController\([^\n]*text: draft\.inputText, entities: draft\.messageTextEntities\(\), draft: draft,', installs)
source_checks = {
    'the-editor-does-not-rebuild-the-draft-from-entities': not re.search(r'let draft = ChatTextInputState\(', modal) and bool(re.search(r'draft: ChatTextInputState\? = nil', modal)),
    'the-input-button-passes-the-input-state': bool(re.search(r'let draft = presentation\.effectiveInput[ \t]*\n', attach)) and bool(re.search(r'makeTranslateModalObserved\([^\n]*, draft, onUse:', attach)),
    'the-input-button-keeps-the-attributes-of-the-result': bool(re.search(r'ChatTextInputState\(attributedText: translated,', attach)),
    'the-selection-passes-its-own-attributes': bool(re.search(r'let selectedDraft = ChatTextInputState\(attributedText: selected,', selection)) and bool(re.search(r'showTranslateObserved\([^\n]*, selectedDraft, onUse:', selection)),
    'every-input-hook-passes-the-draft-and-its-entities': len(passes_draft) == 4,
}
source_failures = 0
for name, passed in source_checks.items():
    print(f"{'PASS' if passed else 'FAIL'} {name}")
    source_failures += 0 if passed else 1

with tempfile.TemporaryDirectory(prefix='ai-editor-original-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    built = subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], capture_output=True, text=True)
    if built.returncode != 0:
        print('FAIL the extracted code does not compile')
        print(built.stderr[-2000:])
        raise SystemExit(1)
    status = subprocess.run([str(binary)]).returncode
    print(f"source checks: {len(source_checks) - source_failures} passed; {source_failures} failed")
    raise SystemExit(1 if status or source_failures else 0)
