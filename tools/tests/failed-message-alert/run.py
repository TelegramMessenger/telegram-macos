import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
parser.add_argument('--core-root', type=Path, default=None)
args = parser.parse_args()
root = args.root
core_root = args.core_root or root


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


row = (root / 'packages/ChatUI/Sources/ChatUI/ChatRowItem.swift').read_text()
alert = section(row, '    public func resendMessage(_ ids: [MessageId]) {', '    public func makeContentSize(').replace('public func', 'func')
delete = section(row, '    public func deleteMessage() {', '    public func openTopic() {').replace('public func', 'func')
failure_source = (root / 'packages/ChatUI/Sources/ChatUI/ChatSendFailure.swift').read_text()
failure = failure_source[failure_source.index('struct ChatSendFailure {'):]
pending = (core_root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/State/PendingMessageManager.swift').read_text()
reason = section(pending, 'public enum PendingMessageFailureReason {', 'public struct PeerPendingMessageDelivered {')

fixture = Path(__file__).with_name('FailedMessageAlertTests.swift.in').read_text()
fixture = fixture.replace('__RESEND_FAILED__', alert).replace('__DELETE_MESSAGE__', delete)
fixture = fixture.replace('__SEND_FAILURE__', failure).replace('__FAILURE_REASON__', reason)

with tempfile.TemporaryDirectory(prefix='failed-message-alert-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
