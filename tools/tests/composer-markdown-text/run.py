import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def source(path):
    return (root / path).read_text()


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def pattern(text, name):
    return section(text, f'private let {name} = ', '\n').split(' = ', 1)[1]


state = source('packages/InputView/Sources/InputView/ChatTextInputState.swift')
attribute = source('packages/InputView/Sources/InputView/ChatTextInputAttribute.swift')
share = source('TelegramShare/SEUIInputView.swift')
extensions = source('packages/TGUIKit/Sources/Extensions.swift')

assert pattern(state, 'markdownRegexFormat') == pattern(attribute, 'markdownRegexFormat') == pattern(share, 'se_markdownRegexFormat')

blocks = {
    '__TRIMMED__': section(extensions, '    var trimmed: NSAttributedString {', '    var trimNewLines: NSAttributedString {'),
    '__ATTRIBUTE_WEIGHT__': section(state, '    public var weight: Int {', '    public static func <(lhs').replace('public var', 'var'),
    '__ATTRIBUTE_RANGES__': section(state, '    func isSameAttribute(_ rhs', '\n}\n'),
    '__MARKDOWN__': section(state, 'private func concatAttributes', 'public enum ChatTextInputAttribute'),
    '__SUB_INPUT_STATE__': section(state, '    public func subInputState(from range: NSRange)', '    public func messageTextEntities(').replace('public func', 'func'),
}
fixture = Path(__file__).with_name('ComposerMarkdownTests.swift.in').read_text()
for key, value in blocks.items():
    fixture = fixture.replace(key, value)

with tempfile.TemporaryDirectory(prefix='composer-markdown-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
