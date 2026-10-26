import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--postbox-source', type=Path, default=root / 'submodules/telegram-ios/submodules/Postbox/Sources/ChatListView.swift')
args = parser.parse_args()
postbox = args.postbox_source.read_text()
peer_group = args.postbox_source.with_name('PeerGroup.swift').read_text().replace('import Foundation', '')
predicate = postbox[postbox.index('public struct ChatListFilterPredicate {'):postbox.index('\nstruct MutableChatListAdditionalItemEntry:')]
adapter = (root / 'packages/ChatListUI/Sources/ChatListUI/ChatListFocusFiltering.swift').read_text()
composition = adapter[adapter.index('private func focusIncludesPeer('):adapter.index('\nprivate struct ChatListFocusQuery:')]
fixture = Path(__file__).with_name('FocusChatListTests.swift').read_text().replace('__POSTBOX_PREDICATE__', predicate).replace('__FOCUS_COMPOSITION__', composition).replace('__POSTBOX_PEER_GROUP_ID__', peer_group)
core = root / 'packages/FocusFilterCore/Sources/FocusFilterCore/FocusFilterPolicy.swift'
with tempfile.TemporaryDirectory(prefix='telegram-focus-chat-list-') as directory:
    directory = Path(directory)
    source = directory / 'Tests.swift'
    source.write_text(fixture)
    executable = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(directory / 'ModuleCache'), str(core), str(source), '-o', str(executable)], check=True)
    raise SystemExit(subprocess.run([str(executable)]).returncode)
