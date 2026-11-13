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
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def between(text, start, end, after=None):
    begin = text.index(start, text.index(after) if after else 0)
    return text[begin:text.index(end, begin)]


def member(text, start):
    begin = text.index(start)
    end = re.compile(r'\n    \}[ \t]*\n').search(text, begin)
    return text[begin:end.end()]


def require(part, *markers):
    for marker in markers:
        if marker not in part:
            raise SystemExit(f'the source changed: {marker!r} is not where the test expects it')
    return part


preview = code('packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift')
sender = code('packages/ChatHistoryModel/Sources/ChatHistoryModel/SenderController.swift')
predicates = code('packages/TelegramMediaUtils/Sources/TelegramMediaUtils/MediaPredicates.swift')
resources = code('packages/TelegramMediaUtils/Sources/TelegramMediaUtils/CoreMediaResourceExtensions.swift')
extensions = code('packages/TGUIKit/Sources/Extensions.swift')

parts = {
    '__SENDING_STATE__': require(between(preview, 'fileprivate struct PreviewSendingState', 'private final class PreviewContextState'), 'var sortValue: Sort'),
    '__SPLIT__': require(between(preview, 'var input:ChatTextInputState = inputState.textInputState()', 'if additionalMessage != nil, let text = permissionText('), 'var additionalMessage: ChatTextInputState? = nil'),
    '__MAKE_MEDIA__': require(between(preview, 'let amount = state.payAmount', 'let effect = self.contextChatInteraction.presentation.messageEffect'), 'let makeMedia:'),
    '__SEND__': require(between(preview, 'if state.isCollage && medias.count > 1 {', 'self.emoji.popover?.hide()'), 'chunks(', 'self.chatInteraction.sendMediasObserved('),
    '__ENQUEUE__': require(between(sender, 'let parsingUrlType: ParsingType', 'let expectedCount = messages.count', after='public static func enqueue(media:[Media], caption: ChatTextInputState'), 'let localGroupingKey = isCollage', 'caption.swap(', 'if let input = additionText {'),
    '__IS_INTERACTIVE__': require(member(predicates, 'var isInteractiveMedia: Bool {'), 'TelegramMediaPaidContent'),
    '__CAN_HAVE_CAPTION__': require(member(resources, 'var canHaveCaption: Bool {'), 'isInstantVideo'),
    '__CHUNKS__': require(member(extensions, 'func chunks(_ chunkSize: Int) -> [[Element]] {'), 'stride('),
    '__TRIMMED__': require(member(extensions, 'var trimmed:String {'), 'whitespacesAndNewlines'),
}

fixture = Path(__file__).with_name('AlbumCaptionOnceTests.swift.in').read_text()
for marker, part in parts.items():
    fixture = fixture.replace(marker, part)

with tempfile.TemporaryDirectory(prefix='album-caption-once-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
