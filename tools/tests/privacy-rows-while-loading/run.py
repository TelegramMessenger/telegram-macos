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


def code(text):
    return '\n'.join(re.sub(r'(^|\s)//.*$', '', line) for line in text.splitlines())


source = code((root / 'packages/SettingsUI/Sources/SettingsUI/PrivacyAndSecurityViewController.swift').read_text())
handlers = ('openLastSeenPrivacy', 'openGroupsPrivacy', 'openVoiceCallPrivacy', 'openBioPrivacy', 'openBirthdayPrivacy', 'openProfilePhotoPrivacy', 'openForwardPrivacy', 'openPhoneNumberPrivacy', 'openVoicePrivacy', 'openMessagesPrivacy', 'openGiftsPrivacy', 'openSavedMusicPrivacy', 'setupGlobalAutoremove')


def handler(name):
    offset = source.index(f'}}, {name}:')
    following = source.index('\n        }, ', offset + 10)
    return source[offset:following]


old_signal = '''privacySettingsPromise.get()
    |> take(1)
    |> deliverOnMainQueue'''
if 'let loadedPrivacySettings =' in source:
    body = source[source.index('let loadedPrivacySettings ='):source.index('let arguments = PrivacyAndSecurityControllerArguments')]
    signal = body.split('=', 1)[1].strip()
else:
    signal = old_signal
detach = source[source.index('    open override func readyToDetach() {'):source.index('    private let twoStepAccessConfiguration')] if 'func readyToDetach()' in source else ''
waits = all('let signal = loadedPrivacySettings' in handler(name) and 'currentInfoDisposable.set(signal.start(' in handler(name) for name in handlers)
main_queue_first = '|> deliverOnMainQueue' in signal and signal.index('|> deliverOnMainQueue') < signal.rindex('|> filter') if 'filter' in signal else False
menu = handler('setupAccountAutoremove')
menu_unchanged = 'let signal = privacySettingsPromise.get()' in menu and 'updateAccountTimeoutDisposable.set(signal.start(' in menu
fixture = (Path(__file__).with_name('PrivacyRowsWhileLoadingTests.swift.in').read_text()
           .replace('__SIGNAL__', signal)
           .replace('__DETACH__', detach.replace('open override func', 'override func'))
           .replace('__ALL_HANDLERS__', 'true' if waits else 'false')
           .replace('__MAIN_QUEUE_FIRST__', 'true' if main_queue_first else 'false')
           .replace('__MENU_UNCHANGED__', 'true' if menu_unchanged else 'false'))

with tempfile.TemporaryDirectory(prefix='privacy-rows-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-suppress-warnings', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
