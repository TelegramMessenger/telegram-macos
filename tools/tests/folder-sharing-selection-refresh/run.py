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
    localization = directory / 'localization-source'
    localization.mkdir()
    localization_paths = subprocess.check_output(['git', '-C', str(root), 'ls-tree', '-r', '--name-only', 'HEAD', '--', 'packages/Localization/Sources'], text=True).splitlines()
    localization_sources = []
    for name in localization_paths:
        path = root / name
        data = path.read_bytes() if path.is_file() else subprocess.check_output(['git', '-C', str(root), 'show', 'HEAD:' + name])
        target_path = localization / Path(name).name
        target_path.write_bytes(data)
        localization_sources.append(str(target_path))
    run(directory, 'localization', common + ['-module-name', 'Localization', '-emit-module-path', str(modules / 'Localization.swiftmodule')] + localization_sources)
    common = [common[0], '-I', str(modules)] + common[1:]
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
    block(links, 'public struct ExportedChatFolderLink:'),
    block(links, 'public extension ExportedChatFolderLink {')
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
    edit_source = root / source_dir / 'FolderSharingLinkEdit.swift'
    if revision:
        result = subprocess.run(['git', '-C', str(root), 'show', revision + ':' + str(source_dir / 'FolderSharingLinkEdit.swift')], capture_output=True)
        edit_text = result.stdout.decode() if result.returncode == 0 else None
    else:
        edit_text = edit_source.read_text()
    if edit_text is not None:
        edit_peer_ids = re.search(r'let peerIds = ([^\n]+)', edit_text).group(1).replace('link.peerIds', 'current.peerIds')
        edit_production = '\n'.join(line for line in edit_text.splitlines() if not line.startswith('import '))
        edit_request = 'folderSharingEditLink(context: context, filterId: 10, link: current, selected: selected)'
        hashes[str(source_dir / 'FolderSharingLinkEdit.swift')] = hashlib.sha256(edit_text.encode()).hexdigest()
    else:
        edit_peer_ids = re.search(r'editChatFolderLink\([^\n]+peerIds: (.+?), revoke: false', controller).group(1)
        edit_production = block(edit_source.read_text(), 'enum FolderSharingLinkEditError')
        edit_request = 'context.engine.peers.editChatFolderLink(filterId: 10, link: current, title: current.title, peerIds: editedPeerIds(current: current, selected: selected), revoke: false) |> mapError { _ in FolderSharingLinkEditError.generic }'
    peer_reference = core_source('TelegramCore/Sources/SyncCore/SyncCore_PeerReference.swift')
    api_utils = core_source('TelegramCore/Sources/ApiUtils/ApiUtils.swift')
    updates_utils = core_source('TelegramCore/Sources/State/UpdatesApiUtils.swift')
    request_fixture = Path(__file__).with_name('FolderSharingRequestTests.swift.in').read_text()
    reference_initializer = block(peer_reference, 'public init?(_ peer: Peer)')
    engine_request = '\n\n'.join([block(links, 'public enum EditChatFolderLinkError'), block(links, 'func _internal_editChatFolderLink('), block(api_utils, 'func apiInputPeer(_ peer: Peer)'), block(updates_utils, 'extension Api.Peer {')])
    for marker, value in [('__PEER_REFERENCE_INIT__', reference_initializer), ('__ENGINE_REQUEST__', engine_request), ('__EDIT_PRODUCTION__', edit_production), ('__EDIT_REQUEST__', edit_request)]:
        assert request_fixture.count(marker) == 1
        request_fixture = request_fixture.replace(marker, value)
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
    tests = tests.replace('let suite = XCTestSuite(forTestCaseClass: FolderSharingSelectionRefreshTests.self)', request_fixture + '\n\nlet suite = XCTestSuite(name: "FolderSharingRegressions")\nsuite.addTest(XCTestSuite(forTestCaseClass: FolderSharingSelectionRefreshTests.self))\nsuite.addTest(XCTestSuite(forTestCaseClass: FolderSharingRequestTests.self))')
    harness.write_text('import SwiftSignalKit\n\n' + core + '\n\n' + production + '\n\n' + tests)
    binary = directory / 'selection-tests'
    command = [compiler, '-j1', '-swift-version', '5', '-Onone', '-sdk', sdk, '-target', target, '-module-cache-path', str(directory / 'cache'), '-F', frameworks, '-I', swift_libraries, '-L', swift_libraries, '-Xlinker', '-rpath', '-Xlinker', frameworks, '-Xlinker', '-rpath', '-Xlinker', swift_libraries, str(harness), '-o', str(binary)]
    products = Path(reference[reference.index('-I', reference.index('-sdk')) + 1])
    signal_object = products / 'SwiftSignalKit.o'
    command += ['-I', str(products), str(signal_object)]
    run(directory, 'compile', command)
    result, text = run(directory, 'tests', [str(binary)], allow_failure=bool(revision))
    match = re.search(r'NATIVE_RESULT tests=(\d+) failures=(\d+)', text)
    assert match is not None, text[-6000:]
    count, failures = map(int, match.groups())
    expected_count = len(re.findall(r'    func test\w+\(', fixture.read_text())) + len(re.findall(r'    func test\w+\(', request_fixture))
    assert count == expected_count, (count, expected_count)
    assert (result.returncode != 0 and failures > 0) if revision else (result.returncode == 0 and failures == 0)
    _, linked = run(directory, 'linked-libraries', ['otool', '-L', str(binary)])
    assert not any(name in linked for name in ['Telegram', 'Contacts.framework', 'AppKit.framework'])
    record = {
        'kind': label,
        'revision': revision or 'working-tree',
        'source_sha256': hashes,
        'fixture_sha256': digest(fixture),
        'request_fixture_sha256': digest(Path(__file__).with_name('FolderSharingRequestTests.swift.in')),
        'real_signal_object_sha256': digest(signal_object),
        'request_baseline_adapter': 'Direct existing engine call and generic error mapping; no preflight synthesized' if edit_text is None else None,
        'selection_test_double_sha256': digest(tests_path),
        'harness_sha256': digest(harness),
        'real_core_source_sha256': core_hashes,
        'tests': count,
        'assertion_failures': failures,
        'failed_tests': [line for line in text.splitlines() if line.startswith('Test Case ') and ' failed ' in line],
        'exit': result.returncode,
        'boundary': 'Native XCTest executes extracted initialization, callbacks, row/bulk/footer predicates, discard/save routing, app preflight helper and the pinned Core edit function through captured request construction. PeerId/buffers, ExportedChatFolderLink/slug, PeerReference initializer, apiInputPeer and response peer conversion are extracted production; SwiftSignalKit is the retained real object/module. Peer payloads, Postbox transactions, network request capture/response and API data containers are controlled fixtures, not a live account/database/server. Separate preflight and engine transactions are represented separately and are not claimed atomic. Footer predicate is checked, not an AppKit button; Cocoa error presentation and rapid-submit UI remain separate from native fixture execution.'
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
