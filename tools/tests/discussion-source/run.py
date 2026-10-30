import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--revision')
args = parser.parse_args()
def read(path):
    return subprocess.check_output(['git', 'show', args.revision + ':' + path], cwd=root, text=True) if args.revision else (root / path).read_text()
try:
    source = read('packages/ChatUI/Sources/ChatUI/ChatDiscussionSource.swift')
except (subprocess.CalledProcessError, FileNotFoundError):
    source = 'func chatDiscussionSourceMessageId(mode: ChatMode, location: ChatLocation) -> MessageId? { nil }' 
source = '\n'.join(line for line in source.splitlines() if not line.startswith('import '))
fixture = Path(__file__).with_name('SourceTests.swift').read_text()
title = read('packages/ChatUI/Sources/ChatUI/ChatTitleBarView.swift')
start = title.index('        let openInfo:(ChatInteraction)->Void = { chatInteraction in')
end = title.index('\n        if hasBackButton {', start)
controller = read('packages/ChatUI/Sources/ChatUI/ChatController.swift')
marker = '    fileprivate func openPeerInfoFromHeader() {'
offset = controller.index(marker) + len(marker)
depth = 1
last = offset
while depth:
    depth += (controller[last] == '{') - (controller[last] == '}')
    last += 1
modern = controller[offset:last - 1].replace('        let chatInteraction = self.chatInteraction', '')
fixture = fixture.replace('__SOURCE__', source).replace('__HEADER_ACTION__', title[start:end]).replace('__MODERN_ACTION__', modern)
with tempfile.TemporaryDirectory(prefix='discussion-source-') as directory:
    directory = Path(directory)
    (directory / 'main.swift').write_text(fixture)
    subprocess.run(['swiftc', str(directory / 'main.swift'), '-o', str(directory / 'tests')], check=True)
    raise SystemExit(subprocess.run([str(directory / 'tests')]).returncode)
