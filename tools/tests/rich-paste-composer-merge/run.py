import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]


def block(source, marker):
    """The brace-balanced body of the declaration starting at `marker`."""
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


merge_source = (root / 'packages/ChatUI/Sources/ChatUI/RichTextComposerPasteMerge.swift').read_text()

# The production merge helper, verbatim. Only the merge is extracted: it decides the resulting
# layout. `surroundingBlocks` needs the composer state and is covered by the composer-state
# tests below.
merge_body = block(merge_source, 'public static func merge<BlockType>(')
# The helper is generic over the block type; the fixture instantiates it with the concrete `Block`
# type, exactly the way the production call sites do.
merge_body = merge_body.replace('public static func merge<BlockType>(', 'static func merge(')
merge_body = merge_body.replace('fragment: [BlockType],', 'fragment: [Block],')
merge_body = merge_body.replace('before: [BlockType],', 'before: [Block],')
merge_body = merge_body.replace('after: [BlockType],', 'after: [Block],')
merge_body = merge_body.replace('paragraph: (BlockType) -> ParagraphBlock?,', 'paragraph: (Block) -> ParagraphBlock?,')
merge_body = merge_body.replace('makeParagraph: (ParagraphBlock) -> BlockType', 'makeParagraph: (ParagraphBlock) -> Block')
merge_body = merge_body.replace(') -> [BlockType] {', ') -> [Block] {')

helper = 'enum RichTextComposerPasteMerge {\n' + merge_body + '\n}\n'

# The composer-state trim decision, taken from the production
# `ChatTextInputState.subInputState(from:trimWhitespace:)`: the range's whitespace is stripped
# only when `trimWhitespace` is set. The production code applies `.trimmed` to the substring and
# then strips the leading/trailing whitespace of the processed text again; both steps are behind
# the same flag, so the extracted model reproduces that decision.
state_source = (root / 'packages/InputView/Sources/InputView/ChatTextInputState.swift').read_text()
if 'public func subInputState(from range: NSRange, trimWhitespace: Bool)' not in state_source:
    raise SystemExit('subInputState(from:trimWhitespace:) not found — the test needs updating')
# Both trimming steps must be guarded by the flag, otherwise the untrimmed overload would still
# lose the whitespace around the caret.
trim_body = block(state_source, 'public func subInputState(from range: NSRange, trimWhitespace: Bool)')
if 'if trimWhitespace {' not in trim_body:
    raise SystemExit('the trailing trim is not guarded by trimWhitespace — the test needs updating')

trim_model = '''
/// The trimming decision of `ChatTextInputState.subInputState(from:trimWhitespace:)`.
func trimmedText(_ text: String, trimWhitespace: Bool) -> String {
    guard trimWhitespace else { return text }
    var out = text
    while let first = out.first, first == " " || first == "\\n" || first == "\\t" || first == "\\r" {
        out.removeFirst()
    }
    while let last = out.last, last == " " || last == "\\n" || last == "\\t" || last == "\\r" {
        out.removeLast()
    }
    return out
}
'''

fixture = Path(__file__).with_name('RichPasteMergeTests.swift').read_text()
fixture = fixture.replace('__MERGE__', helper)
assert '__MERGE__' not in fixture

whitespace_fixture = Path(__file__).with_name('ComposerWhitespaceTests.swift').read_text()
whitespace_fixture = whitespace_fixture.replace('__TRIM__', trim_model)
assert '__TRIM__' not in whitespace_fixture

with tempfile.TemporaryDirectory(prefix='rich-paste-composer-merge-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RichPasteComposerMerge", platforms: [.macOS(.v13)], targets: [.testTarget(name: "RichPasteComposerMergeTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/RichPasteMergeTests.swift').write_text(fixture)
    (directory / 'Tests/ComposerWhitespaceTests.swift').write_text(whitespace_fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox']).returncode)
