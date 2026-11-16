import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

assert sys.flags.isolated
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--baseline', required=True)
parser.add_argument('--typecheck-command', required=True, type=Path)
parser.add_argument('--core-root', required=True, type=Path)
parser.add_argument('--lock', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
package = Path('packages/FolderSharingUI')
source_dir = package / 'Sources/FolderSharingUI'
fixture = Path(__file__).with_name('FolderSharingSelectionRefreshTests.swift')
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
reference = json.loads(args.typecheck_command.read_text())['command']
compiler = reference[0]
sdk = reference[reference.index('-sdk') + 1]
target = reference[reference.index('-target') + 1]
frameworks = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks'
swift_libraries = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib'
env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
records = []


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def block(text, marker):
    start = text.index(marker)
    brace = text.index('{', start)
    end = brace + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def run(directory, name, command, allow_failure=False):
    save(directory / (name + '-command.json'), command)
    local_env = dict(env)
    temporary = directory / 'tmp'
    temporary.mkdir(exist_ok=True)
    local_env['TMPDIR'] = str(temporary) + '/'
    result = subprocess.run(command, cwd=root, env=local_env, capture_output=True, text=True)
    text = result.stdout + result.stderr
    (directory / (name + '.log')).write_text(text)
    save(directory / (name + '-result.json'), {'exit': result.returncode, 'at': datetime.datetime.now().astimezone().isoformat()})
    if result.returncode and not allow_failure:
        print(text[-12000:], flush=True)
        raise SystemExit(result.returncode)
    return result, text


def typecheck_flags():
    result = [compiler]
    index = 1
    while index < len(reference):
        arg = reference[index]
        if arg in ['-emit-module-path', '-module-cache-path', '-module-name']:
            index += 2
        elif arg == '-I' and 'pr-review-fixes-' in reference[index + 1]:
            index += 2
        elif arg == '-Xcc' and 'PollResultsUI.build/' in reference[index + 1]:
            index += 2
        elif arg.endswith('.swift'):
            index += 1
        else:
            result.append(arg)
            index += 1
    return result


def typecheck():
    directory = output / 'typecheck-real-modules'
    directory.mkdir()
    modules = directory / 'modules'
    modules.mkdir()
    production = sorted((root / source_dir).glob('*.swift'))
    tests = sorted((root / package / 'Tests/FolderSharingUITests').glob('*.swift'))
    common = typecheck_flags() + ['-module-cache-path', str(directory / 'cache')]
    run(directory, 'production', common + ['-module-name', 'FolderSharingUI', '-emit-module-path', str(modules / 'FolderSharingUI.swiftmodule')] + list(map(str, production)))
    run(directory, 'tests', [compiler, '-I', str(modules)] + common[1:] + ['-module-name', 'FolderSharingUITests', '-emit-module-path', str(modules / 'FolderSharingUITests.swiftmodule')] + list(map(str, tests)))
    record = {
        'kind': 'complete-package-and-tests-module-emission',
        'production_files': {str(path): digest(path) for path in production},
        'test_files': {str(path): digest(path) for path in tests},
        'test_methods_typechecked': sum(len(re.findall(r'    func test\w+\(', path.read_text())) for path in tests),
        'reference_command': str(args.typecheck_command),
        'reference_sha256': digest(args.typecheck_command),
        'exit': 0,
        'boundary': 'All FolderSharingUI production files and XCTest sources compiled against retained real dependency modules. No package linking, app build, execution, or shared build writes.'
    }
    save(directory / 'verification.json', record)
    records.append(record)
    print('Full FolderSharingUI and package tests module emission passed', flush=True)


def core_source(relative):
    path = args.core_root / relative
    core_hashes[str(path)] = digest(path)
    return path.read_text()


core_hashes = {}
peer_source = core_source('Postbox/Sources/Peer.swift')
coding = core_source('Postbox/Sources/Coding.swift')
comparison = core_source('Postbox/Sources/ValueBoxKey.swift')
links = core_source('TelegramCore/Sources/TelegramEngine/Peers/ChatFolders.swift')
core = '\n\n'.join([
    'import Foundation',
    block(peer_source, 'public struct PeerId:'),
    'private let emptyMemory = malloc(1)!',
    block(coding, 'public class MemoryBuffer:'),
    block(coding, 'public final class WriteBuffer:'),
    block(coding, 'public final class ReadBuffer:'),
    block(comparison, 'func mdb_cmp_memn('),
    block(links, 'public struct ExportedChatFolderLink:')
])


def native(label, revision):
    directory = output / ('native-' + label)
    directory.mkdir()
    hashes = {}

    def read(name):
        path = source_dir / name
        if revision:
            data = subprocess.check_output(['git', '-C', str(root), 'show', revision + ':' + str(path)])
        else:
            data = (root / path).read_bytes()
        hashes[str(path)] = hashlib.sha256(data).hexdigest()
        (directory / name).write_bytes(data)
        return data.decode()

    controller = read('ShareCloudFolderController.swift')
    behavior = read('FolderSharingBehavior.swift')
    models = read('FolderSharingModels.swift')
    environment = read('FolderSharingUIEnvironment.swift')
    tests_path = root / package / 'Tests/FolderSharingUITests/FolderSharingUITests.swift'
    selection = block(tests_path.read_text(), 'private final class Selection:').replace('private final class', 'final class', 1)
    helper = behavior[behavior.index('func folderSharingInitializeSelection('):behavior.index('func folderSharingJoinedChannelIds(')]
    callback = block(controller, '{ [weak selected] peers, participantCount in')
    row_callback = block(controller, '{ [weak selected] peerId, _ in')
    local = re.search(r'^    var (?:initialSelected|linkSelection)[^\n]*', controller, re.MULTILINE)
    assert local is not None
    initial = re.search(r'^    let initialState = FolderSharingLinkState[^\n]*', controller, re.MULTILINE).group(0).strip()
    merge = block(controller, '}, merge: {').removeprefix('}, merge: ')
    transaction = block(controller, 'controller.afterTransaction =')
    done = re.search(r'title\.set\(text: (stateValue\.with \{[^}]+\}) \?', transaction).group(1)
    assert done in re.search(r'title\.set\(background:[^\n]+', transaction).group(0)
    discard = re.search(r'if (state\.needsDiscardConfirmation\([^\n]+\)) \{', controller).group(1)
    row_enabled = re.search(r'makePeerRow\(initialSize, peer: item\.peer\.peer, enabled: (.+?), status:', controller).group(1)
    bulk_peers = re.search(r'folderSharingToggleAll\((items\.filter.+?), selected: state\.selected, selection:', controller).group(1)
    bulk_visible = re.search(r'if items\.count > 1, (.+?) \{', controller).group(1)
    edit_peer_ids = re.search(r'editChatFolderLink\([^\n]+peerIds: (.+?), revoke: false', controller).group(1)
    production = '\n\n'.join([
        block(environment, 'public protocol FolderSharingPeerSelection:'),
        block(models, 'struct FolderSharingPeer:'),
        block(controller, 'struct FolderSharingLinkState :'),
        helper,
        block(behavior, 'func folderSharingSaveLink('),
        selection
    ])
    tests = fixture.read_text()
    for marker, value in [('__INITIAL_STATE__', initial), ('__SELECTION_LOCAL__', local.group(0).strip()), ('__PEER_CALLBACK__', callback), ('__ROW_CALLBACK__', row_callback), ('__MERGE_CALLBACK__', merge), ('__DONE_EXPRESSION__', done), ('__DISCARD_EXPRESSION__', discard), ('__ROW_ENABLED__', row_enabled), ('__BULK_PEERS__', bulk_peers), ('__BULK_VISIBLE__', bulk_visible), ('__EDIT_PEER_IDS__', edit_peer_ids)]:
        assert tests.count(marker) == 1
        tests = tests.replace(marker, value)
    harness = directory / 'main.swift'
    harness.write_text(core + '\n\n' + production + '\n\n' + tests)
    binary = directory / 'selection-tests'
    command = [compiler, '-j1', '-swift-version', '5', '-Onone', '-sdk', sdk, '-target', target, '-module-cache-path', str(directory / 'cache'), '-F', frameworks, '-I', swift_libraries, '-L', swift_libraries, '-Xlinker', '-rpath', '-Xlinker', frameworks, '-Xlinker', '-rpath', '-Xlinker', swift_libraries, str(harness), '-o', str(binary)]
    run(directory, 'compile', command)
    result, text = run(directory, 'tests', [str(binary)], allow_failure=bool(revision))
    match = re.search(r'NATIVE_RESULT tests=(\d+) failures=(\d+)', text)
    assert match is not None, text[-6000:]
    count, failures = map(int, match.groups())
    expected_count = len(re.findall(r'    func test\w+\(', fixture.read_text()))
    assert count == expected_count, (count, expected_count)
    assert (result.returncode != 0 and failures > 0) if revision else (result.returncode == 0 and failures == 0)
    _, linked = run(directory, 'linked-libraries', ['otool', '-L', str(binary)])
    assert not any(name in linked for name in ['Telegram', 'Contacts.framework', 'AppKit.framework'])
    record = {
        'kind': label,
        'revision': revision or 'working-tree',
        'source_sha256': hashes,
        'fixture_sha256': digest(fixture),
        'selection_test_double_sha256': digest(tests_path),
        'harness_sha256': digest(harness),
        'real_core_source_sha256': core_hashes,
        'tests': count,
        'assertion_failures': failures,
        'failed_tests': [line for line in text.splitlines() if line.startswith('Test Case ') and ' failed ' in line],
        'exit': result.returncode,
        'boundary': 'Native XCTest executable runs verbatim extracted initial state, peer callback, row callback, bulk-selection merge callback, Done/Delete predicate, discard expression, state, selection helpers and save routing. Real PeerId/buffers and ExportedChatFolderLink source; peer payload, eligibility predicate, filter and state container are in-memory test doubles. Footer predicate is checked, not an AppKit button. Foundation/XCTest only; no account, Postbox instance, database, Contacts, network or GUI.'
    }
    save(directory / 'verification.json', record)
    records.append(record)
    print(label, count, 'tests,', failures, 'assertion failures', flush=True)


save(output / 'invocation.json', {'argv': sys.argv, 'cwd': str(root), 'baseline': args.baseline, 'runner_sha256': digest(Path(__file__)), 'lock': str(args.lock), 'swift_jobs': 1})
with args.lock.open('a') as lock:
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    typecheck()
    native('baseline', args.baseline)
    native('fixed', None)
save(output / 'verification.json', {'at': datetime.datetime.now().astimezone().isoformat(), 'records': records})
