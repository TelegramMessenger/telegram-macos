import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--macos-revision')
args = parser.parse_args()
macos_path = 'packages/InAppSettings/Sources/InAppSettings/ChatListFilterPreferences.swift'
if args.macos_revision:
    macos = subprocess.check_output(['git', 'show', f'{args.macos_revision}:{macos_path}'], cwd=root, text=True)
else:
    macos = (root / macos_path).read_text()
postbox = (root / 'submodules/telegram-ios/submodules/Postbox/Sources/UnreadMessageCountsView.swift').read_text()
postbox = '\n'.join(line for line in postbox.splitlines() if not line.startswith('import ')).replace('public ', '')
models = macos[macos.index('public struct ChatListFilterBadge :'):macos.index('private final class SharedChatListFilterItemsContext')].replace('public ', '')
calculation = macos[macos.index('private func makeChatListFilterItems('):]
fixture = Path(__file__).with_name('Checks.swift').read_text().replace('__POSTBOX__', postbox).replace('__BADGE_MODELS__', models).replace('__CALCULATION__', calculation)
with tempfile.TemporaryDirectory(prefix='folder-topic-badges-') as directory:
    directory = Path(directory)
    source = directory / 'main.swift'
    source.write_text(fixture)
    subprocess.run(['swiftc', str(source), '-o', str(directory / 'checks')], check=True)
    raise SystemExit(subprocess.run([str(directory / 'checks')]).returncode)
