import argparse
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
setup = section(source, '    let draft = ChatTextInputState(', '    let configTones') if 'let draft = ChatTextInputState(' in source else ''
fixture = (Path(__file__).with_name('AIEditorOriginalTests.swift.in').read_text()
           .replace('__APPLIED_TEXT__', applied)
           .replace('__APPLY__', apply)
           .replace('__SETUP__', setup))

with tempfile.TemporaryDirectory(prefix='ai-editor-original-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
