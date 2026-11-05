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


def uncommented(text):
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def block(text, header):
    begin = text.index(header) + len(header)
    depth = 1
    for index in range(begin, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index]
    raise ValueError(header)


head = uncommented((root / 'packages/PeerInfoUI/Sources/PeerInfoUI/PeerInfoHeadItem.swift').read_text())
entries = uncommented((root / 'packages/PeerInfoUI/Sources/PeerInfoUI/UserInfoEntries.swift').read_text())

try:
    start = head.index('private func actionItems')
    actions = head[start:head.index('class PeerInfoHeadItem', start)]
    bot_branch = block(actions, '} else if let botInfo = peer.botInfo {')
    more = block(actions, 'if items.count > rowItemsCount {')
    report = block(entries, 'func reportBot() {')
except ValueError as error:
    print(f'source not found: {error}')
    raise SystemExit(2)
reports_peer = re.search(r'reportComplicated\(context: context, subject: \.peer\(peerId\),', report) is not None

animations = sorted(set(re.findall(r'\.(menu_\w+)', bot_branch + more)) | {'menu_show_message', 'menu_mute', 'menu_report'})

ios_path = root / 'submodules/telegram-ios/submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoProfileItems.swift'
if ios_path.exists():
    found = re.search(r'\bif ([^{]*)\{\s*items\[[^\]]*\]!\.append\(PeerInfoScreenActionItem\(id: ItemBotReport\b', uncommented(ios_path.read_text()))
    condition = ' '.join(found.group(1).split()) if found else ''
    ios_rule = {
        'let botInfo = user.botInfo, !botInfo.flags.contains(.canEdit)': 'notOwned',
        'let botInfo = user.botInfo, botInfo.flags.contains(.canEdit)': 'owned',
    }.get(condition, 'unknown')
else:
    ios_rule = 'missing'

fixture = (Path(__file__).with_name('ReportBotTests.swift.in').read_text()
           .replace('__ANIMATIONS__', '\n'.join(f'    case {name}' for name in animations))
           .replace('__BOT_BRANCH__', bot_branch)
           .replace('__MORE__', more)
           .replace('__REPORTS_PEER__', 'true' if reports_peer else 'false')
           .replace('__IOS_RULE__', ios_rule))

with tempfile.TemporaryDirectory(prefix='report-bot-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
