import argparse
from contextlib import nullcontext
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


repository = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description='Run extracted slow-mode attachment caption logic. Missing sparse files fall back to HEAD in the harness repository.')
parser.add_argument('--source-root', type=Path, default=repository, help='Read materialized sources here; missing paths fall back to harness-repository HEAD.')
parser.add_argument('--source-revision', help='Read all production sources at this revision in the harness repository, ignoring --source-root files.')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--compiler-lock', type=Path, help='Optional flock path; omit when the caller already holds the compiler lock.')
args = parser.parse_args()
root = args.source_root.resolve()
output = args.output.resolve()
if output == root or root in output.parents:
    parser.error('--output must be outside --source-root')
output.mkdir(parents=True, exist_ok=False)
environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
source_records = {}


def read(path):
    local = root / path
    if args.source_revision or not local.is_file():
        revision = args.source_revision or 'HEAD'
        source = subprocess.check_output(['git', '-C', str(repository), 'show', revision + ':' + path], text=True, env=environment)
        origin = revision
    else:
        source = local.read_text()
        origin = 'working-tree'
    source_records[path] = {'origin': origin, 'sha256': hashlib.sha256(source.encode()).hexdigest()}
    return source


def section(source, start, end):
    assert source.count(start) == 1, start
    offset = source.index(start)
    return source[offset:source.index(end, offset)]


def block(source, marker):
    assert source.count(marker) == 1, marker
    start = source.index(marker)
    offset = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[offset] == '{') - (source[offset] == '}')
        offset += 1
    return source[start:offset]


controller_path = 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift'
controller = read(controller_path)
sender = read('packages/ChatHistoryModel/Sources/ChatHistoryModel/SenderController.swift')
media = read('packages/TelegramMediaUtils/Sources/TelegramMediaUtils/CoreMediaResourceExtensions.swift')
predicates = read('packages/TelegramMediaUtils/Sources/TelegramMediaUtils/MediaPredicates.swift')
extensions = read('packages/TGUIKit/Sources/Extensions.swift')
text_state = read('packages/InputView/Sources/InputView/ChatTextInputState.swift')
updated_text_state = read('packages/InputView/Sources/InputView/UpdatedChatTextInputState.swift')
slow_mode = read('packages/TelegramUtils/Sources/TelegramUtils/SlowMode.swift')
pending = read('packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderPendingActions.swift')
can_collage = read('packages/PreviewSenderUI/Sources/PreviewSenderUI/CanCollage.swift')
fixture_path = Path(__file__).with_name('Tests.swift.in')
fixture = fixture_path.read_text()
send_prefix = section(controller, '        self.sendCurrentMedia = { [weak self] silent, atDate, asSpoiler, via in', '                let amount = state.payAmount')
send_media = section(controller, '                let amount = state.payAmount', '                let submissionAction = self.capturePendingSendAction()')
dispatch = section(controller, '                    if state.isCollage && medias.count > 1 {', '                    self.emoji.popover?.hide()')
parts = {
    '__SENDING_STATE__': block(controller, 'fileprivate struct PreviewSendingState'),
    '__ENTRY_CASES__': section(controller, '    case section(Int)\n    case media(index:', '    var stableId: PreviewEntryId'),
    '__PREVIEW_ENTRIES__': block(controller, 'private func previewMediaEntries('),
    '__INPUT_PLACEHOLDER__': block(controller, '    private var inputPlaceholder: String'),
    '__SEND_PREFIX__': send_prefix,
    '__MAKE_MEDIA__': send_media,
    '__DISPATCH__': dispatch,
    '__CAN_HAVE_CAPTION__': block(media, '    var canHaveCaption: Bool'),
    '__SUPPOSE_TO_BE_STICKER__': block(media, '    var supposeToBeSticker:Bool'),
    '__INTERACTIVE_MEDIA__': block(predicates, '    var isInteractiveMedia: Bool'),
    '__CHUNKS__': block(extensions, '    func chunks('),
    '__STRING_TRIMMED__': block(extensions, '    var trimmed:String'),
    '__ATTRIBUTED_TRIMMED__': block(extensions, '    var trimmed: NSAttributedString'),
    '__UPDATED_INPUT__': block(updated_text_state, 'public struct Updated_ChatTextInputState'),
    '__INPUT_CONVERSION__': block(text_state, '    public func textInputState() -> ChatTextInputState'),
    '__SLOW_MODE__': block(slow_mode, 'public struct SlowMode'),
    '__PENDING_ACTIONS__': pending,
    '__CAN_COLLAGE__': block(can_collage, 'public func canCollagesFromUrl('),
    '__SENDER_CAPTION__': section(sender, '        let localGroupingKey = isCollage ? arc4random64() : nil', '        if let input = additionText'),
}
for marker, source in parts.items():
    assert fixture.count(marker) == 1, marker
    fixture = fixture.replace(marker, source)
assert not re.search(r'__[A-Z_]+__', fixture)
main = output / 'main.swift'
main.write_text(fixture)
manifest = {
    'source_root': str(root),
    'source_repository': str(repository),
    'source_revision': args.source_revision,
    'missing_source_policy': 'Read missing sparse paths from harness-repository HEAD; every source records its origin.',
    'head': subprocess.check_output(['git', '-C', str(repository), 'rev-parse', 'HEAD'], text=True, env=environment).strip(),
    'sources': source_records,
    'extractions': {marker: {'sha256': hashlib.sha256(source.encode()).hexdigest(), 'lines': len(source.splitlines())} for marker, source in parts.items()},
    'fixture_sha256': hashlib.sha256(fixture_path.read_bytes()).hexdigest(),
    'generated_sha256': hashlib.sha256(main.read_bytes()).hexdigest(),
    'unchanged_regions': {
        'caption_limit': hashlib.sha256(section(controller, '        let text = self.genericView.textView.string().trimmed', '        switch chatInteraction.mode').encode()).hexdigest(),
        'initial_grouping': hashlib.sha256(section(controller, '        var canCollage: Bool = canCollagesFromUrl(self.urls)', '        self.genericView.stateValueInteractiveUpdate').encode()).hexdigest(),
        'dispatch': hashlib.sha256(dispatch.encode()).hexdigest(),
        'placeholder': hashlib.sha256(parts['__INPUT_PLACEHOLDER__'].encode()).hexdigest(),
        'sender_caption': hashlib.sha256(parts['__SENDER_CAPTION__'].encode()).hexdigest(),
    },
    'compiler_lock': str(args.compiler_lock) if args.compiler_lock else None,
}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
command = ['xcrun', 'swiftc', '-j1', '-module-cache-path', str(output / 'module-cache'), str(main), '-o', str(output / 'tests')]
with args.compiler_lock.open('a') if args.compiler_lock else nullcontext() as lock:
    if lock is not None:
        fcntl.flock(lock, fcntl.LOCK_EX)
    compiled = subprocess.run(command, capture_output=True, text=True, env=environment)
(output / 'compile.log').write_text(compiled.stdout + compiled.stderr)
print(compiled.stdout + compiled.stderr, end='', flush=True)
results = {'compile_command': command, 'compile_exit': compiled.returncode, 'output': str(output)}
if compiled.returncode == 0:
    tested = subprocess.run([str(output / 'tests')], capture_output=True, text=True, env=environment)
    log = tested.stdout + tested.stderr
    (output / 'tests.log').write_text(log)
    print(log, end='', flush=True)
    results['test_exit'] = tested.returncode
    summary = re.search(r'SUMMARY: (\d+) checks, (\d+) failures', log)
    if summary:
        results.update(checks=int(summary[1]), failures=int(summary[2]))
    results['failed_assertions'] = [line for line in log.splitlines() if line.startswith('FAIL ')]
(output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
raise SystemExit(results.get('test_exit', compiled.returncode))
