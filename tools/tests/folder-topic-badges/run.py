import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--macos-revision')
parser.add_argument('--postbox-revision')
args = parser.parse_args()
macos_path = 'packages/InAppSettings/Sources/InAppSettings/ChatListFilterPreferences.swift'
badge_path = 'packages/InAppSettings/Sources/InAppSettings/ChatListFilterBadgeCounts.swift'
postbox_root = root / 'submodules/telegram-ios'
postbox_path = 'submodules/Postbox/Sources/UnreadMessageCountsView.swift'

def read_source(repo, path, revision):
    if revision:
        return subprocess.check_output(['git', 'show', f'{revision}:{path}'], cwd=repo, text=True)
    return (repo / path).read_text()

def without_imports(source):
    return '\n'.join(line for line in source.splitlines() if not line.startswith('import '))

macos = read_source(root, macos_path, args.macos_revision)
badges = without_imports(read_source(root, badge_path, args.macos_revision))
postbox = without_imports(read_source(postbox_root, postbox_path, args.postbox_revision)).replace('public ', '')
models = macos[macos.index('public struct ChatListFilterBadge :'):macos.index('private final class SharedChatListFilterItemsContext')].replace('public ', '')
calculation = macos[macos.index('private func makeChatListFilterItems('):]
fixture = Path(__file__).with_name('Checks.swift').read_text().replace('__POSTBOX__', postbox).replace('__BADGE_MODELS__', models).replace('__CALCULATION__', calculation).replace('__BADGE_CALCULATION__', badges)
with tempfile.TemporaryDirectory(prefix='folder-topic-badges-') as directory:
    directory = Path(directory)
    source = directory / 'main.swift'
    source.write_text(fixture)
    subprocess.run(['swiftc', str(source), '-o', str(directory / 'checks')], check=True)
    raise SystemExit(subprocess.run([str(directory / 'checks')]).returncode)
