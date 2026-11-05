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


def read(path):
    text = (root / path).read_text()
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


def body(text, start):
    begin = text.index('{', start) + 1
    depth = 1
    for index in range(begin, len(text)):
        if text[index] == '{':
            depth += 1
        elif text[index] == '}':
            depth -= 1
            if depth == 0:
                return text[begin:index], index
    raise ValueError('unbalanced braces')


admin = read('packages/ChannelAdminUI/Sources/ChannelAdminUI/ChannelBotAdminController.swift')
top = admin[admin.index('public func addBotAsMember('):admin.index('public struct ResolvedBotAdminRights')].replace('public ', '')

validate = admin[admin.index('controller.validateData'):]
_, admin_branch_end = body(validate, validate.index('if isAdmin {'))
member_branch, _ = body(validate, admin_branch_end + 1)
progress = validate.index('_ = showModalProgress(signal: signal')
window_error, _ = body(validate, validate.index('}, error: { error in', progress) + 2)

profile_source = read('packages/PeerInfoUI/Sources/PeerInfoUI/UserInfoEntries.swift')
profile_function = profile_source.index('func botAddToGroup()')
profile, _ = body(profile_source, profile_source.index('_ = result.start(next:', profile_function))

links = read('Telegram-Mac/utils/InAppLinks.swift')
invite = links.index('case let .inviteBotToGroup(')
link, _ = body(links, links.index('_ = result.start(next:', invite))

fixture = (Path(__file__).with_name('BotAddAsMemberTests.swift.in').read_text()
           .replace('__TOP__', top)
           .replace('__WINDOW_MEMBER__', member_branch)
           .replace('__WINDOW_ERROR__', window_error)
           .replace('__PROFILE__', profile)
           .replace('__LINK__', link))

with tempfile.TemporaryDirectory(prefix='bot-add-as-member-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    compiled = subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)])
    if compiled.returncode != 0:
        raise SystemExit(2)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
