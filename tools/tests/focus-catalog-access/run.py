from pathlib import Path
import fcntl
import os
import platform
import plistlib
import select
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
sources = root / 'packages/FocusFilterCore/Sources/FocusFilterInfrastructure'
compiler = ['xcrun', 'swiftc'] if platform.system() == 'Darwin' else [os.environ.get('SWIFTC', 'swiftc')]

with tempfile.TemporaryDirectory(prefix='telegram-focus-access-') as temporary:
    temporary = Path(temporary)
    binary = temporary / 'fixture'
    subprocess.run(compiler + ['-swift-version', '5', '-parse-as-library',
        '-module-cache-path', str(temporary / 'ModuleCache'),
        str(sources / 'FocusApplicationLocation.swift'),
        str(sources / 'FocusCatalogAccess.swift'),
        str(fixtures / 'Fixture.swift'), '-o', str(binary)] + (
            [str(sources / 'FocusExtensionInstallation.swift')] if platform.system() == 'Darwin' else []
        ), check=True)
    application = temporary / 'A.app'
    (application / 'Contents/MacOS').mkdir(parents=True)
    (application / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'App'}))
    executable = application / 'Contents/MacOS/App'
    shutil.copy2(binary, executable)
    extension = application / 'Contents/Extensions/FocusIntents.appex'
    (extension / 'Contents/MacOS').mkdir(parents=True)
    (extension / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'Extension'}))
    extension_executable = extension / 'Contents/MacOS/Extension'
    shutil.copy2(binary, extension_executable)
    storage = temporary / 'stable'
    processes = []

    def start(kind='owner', app=application, directory=storage, executable_path=binary, environment=None):
        process = subprocess.Popen([str(executable_path), kind, str(directory), str(app)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=environment)
        processes.append(process)
        assert select.select([process.stdout], [], [], 5)[0], 'Session initialization must not block'
        response = process.stdout.readline().strip()
        assert response == 'ready', (response, process.stderr.read() if process.poll() is not None else '')
        return process

    def command(process, value, expected=None):
        process.stdin.write(value + '\n')
        process.stdin.flush()
        if expected is not None:
            assert process.stdout.readline().strip() == expected
        assert process.stdout.readline().strip() == 'done'

    def allowed(expected, app=application, directory=storage):
        result = subprocess.check_output([str(binary), 'read', str(directory), str(app)], text=True, timeout=5).strip()
        assert result == str(expected).lower(), (result, expected)

    def state(expected, app=application, directory=storage):
        result = subprocess.check_output([str(binary), 'state', str(directory), str(app)], text=True, timeout=5).strip()
        assert result == expected, (result, expected)

    def reader_value(process, expected):
        process.stdin.write('read\n')
        process.stdin.flush()
        assert process.stdout.readline().strip() == str(expected).lower()

    def stop(process):
        process.stdin.close()
        assert process.wait(timeout=5) == 0, process.stderr.read()

    try:
        if platform.system() == 'Darwin':
            developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
            checker = developer / 'usr/lib/libMainThreadChecker.dylib'
            assert checker.is_file(), f'Main Thread Checker is required for the injected-image regression: {checker}'
            environment = os.environ.copy()
            environment['DYLD_INSERT_LIBRARIES'] = str(checker)
            injected_storage = temporary / 'injected'
            injected_owner = start(kind='injected-owner', directory=injected_storage,
                                   executable_path=executable, environment=environment)
            injected_reader = start(kind='injected-reader', directory=injected_storage,
                                    executable_path=extension_executable, environment=environment)
            reader_value(injected_reader, False)
            command(injected_owner, 'unlock')
            reader_value(injected_reader, True)
            state('accessible', directory=injected_storage)
            command(injected_owner, 'lock')
            reader_value(injected_reader, False)
            state('locked', directory=injected_storage)
            command(injected_owner, 'unlock')
            reader_value(injected_reader, True)
            injected_owner.kill()
            injected_owner.wait(timeout=5)
            reader_value(injected_reader, False)
            state('locked', directory=injected_storage)
            stop(injected_reader)
            print('PASS: Main Thread Checker is image zero; production owner and extension-bundle reader preserve lock/unlock/crash admission')
        allowed(False)
        state('locked')
        first = start()
        allowed(False)
        command(first, 'unlock')
        state('accessible')
        for _ in range(10):
            allowed(True)
        command(first, 'own-read', 'false')
        allowed(True)
        command(first, 'duplicate', 'duplicate denied')
        allowed(True)
        command(first, 'lock')
        allowed(False)
        state('locked')
        command(first, 'unlock')
        allowed(True)
        second = start()
        allowed(False)
        command(second, 'unlock')
        allowed(True)
        command(second, 'lock')
        allowed(False)
        first.kill()
        first.wait(timeout=5)
        allowed(False)
        command(second, 'unlock')
        allowed(True)
        second.kill()
        second.wait(timeout=5)
        allowed(False)
        third = start()
        command(third, 'unlock')
        allowed(True)
        gate_file, = (storage / 'CatalogAccess').iterdir()
        gate_file.rename(gate_file.with_suffix('.saved'))
        gate_file.mkdir()
        state('unavailable')
        gate_file.rmdir()
        gate_file.with_suffix('.saved').rename(gate_file)
        state('accessible')
        invalid_storage = temporary / 'invalid-presence'
        invalid_file = invalid_storage / 'CatalogAccess' / gate_file.name
        invalid_file.parent.mkdir(parents=True)
        invalid_file.write_bytes(b'\x00')
        with invalid_file.open('r+b') as invalid_presence:
            fcntl.lockf(invalid_presence, fcntl.LOCK_EX | fcntl.LOCK_NB, 1, 0)
            state('unavailable', directory=invalid_storage)
        state('locked', directory=invalid_storage)

        with gate_file.open('r+b') as initialization:
            fcntl.lockf(initialization, fcntl.LOCK_EX | fcntl.LOCK_NB, 1, 2)
            pending = start()
            allowed(False)
            command(pending, 'unlock')
            allowed(False)
            fcntl.lockf(initialization, fcntl.LOCK_UN, 1, 2)
        allowed(False)
        command(pending, 'unlock')
        allowed(True)
        stop(pending)
        allowed(True)
        startup_storage = temporary / 'startup'
        startup_file = startup_storage / 'CatalogAccess' / gate_file.name
        startup_file.parent.mkdir(parents=True)
        startup_file.touch()
        with startup_file.open('r+b') as initialization:
            fcntl.lockf(initialization, fcntl.LOCK_EX | fcntl.LOCK_NB, 1, 2)
            cold_first = start(directory=startup_storage)
            cold_second = start(directory=startup_storage)
            command(cold_first, 'unlock')
            command(cold_second, 'unlock')
            allowed(False, directory=startup_storage)
            fcntl.lockf(initialization, fcntl.LOCK_UN, 1, 2)
        command(cold_first, 'unlock')
        allowed(False, directory=startup_storage)
        command(cold_second, 'unlock')
        allowed(True, directory=startup_storage)
        stop(cold_first)
        allowed(True, directory=startup_storage)
        stop(cold_second)
        allowed(False, directory=startup_storage)
        gate_file.write_bytes(b'\x01')
        allowed(False)
        state('unavailable')
        command(third, 'unlock')
        allowed(False)
        poisoned_peer = start()
        command(poisoned_peer, 'unlock')
        allowed(False)
        stop(third)
        allowed(False)
        stop(poisoned_peer)
        allowed(False)
        third = start()
        command(third, 'unlock')
        allowed(True)
        with gate_file.open('r+b') as conflict:
            fcntl.lockf(conflict, fcntl.LOCK_EX | fcntl.LOCK_NB, 1, 1)
            failed = start()
            allowed(False)
            fcntl.lockf(conflict, fcntl.LOCK_UN, 1, 1)
        allowed(False)
        command(failed, 'attempt-unlock', 'unavailable')
        command(third, 'unlock')
        allowed(False)
        stop(failed)
        stop(third)
        third = start()
        command(third, 'unlock')
        allowed(True)
        other_app = temporary / 'B.app'
        shutil.copytree(application, other_app)
        allowed(False, app=other_app)
        other = start(app=other_app)
        allowed(False, app=other_app)
        allowed(True)
        command(other, 'unlock')
        allowed(True, app=other_app)
        allowed(False, directory=temporary / 'beta')
        old_reader = start(kind='reader')
        reader_value(old_reader, True)
        replacement = extension_executable.with_suffix('.replacement')
        shutil.copy2(binary, replacement)
        replacement.replace(extension_executable)
        allowed(False)
        reader_value(old_reader, False)
        replacement_owner = start()
        command(replacement_owner, 'unlock')
        allowed(True)
        reader_value(old_reader, False)
        command(third, 'unlock')
        allowed(True)
        stop(replacement_owner)
        allowed(False)
        allowed(True, app=other_app)
        app_info = other_app / 'Contents/Info.plist'
        original_info = app_info.read_bytes()
        app_info.unlink()
        allowed(True, app=other_app)
        state('accessible', app=other_app / 'Contents/Extensions/FocusIntents.appex')
        command(other, 'unlock')
        state('locked', app=other_app)
        app_info.write_bytes(original_info)
        command(other, 'unlock')
        state('accessible', app=other_app)
        host_executable = other_app / 'Contents/MacOS/App'
        host_replacement = host_executable.with_suffix('.replacement')
        shutil.copy2(binary, host_replacement)
        host_replacement.replace(host_executable)
        new_host = start(app=other_app)
        state('locked', app=other_app)
        command(new_host, 'unlock')
        state('accessible', app=other_app)
        command(other, 'unlock')
        state('locked', app=other_app)
        stop(other)
        state('accessible', app=other_app)
        stop(new_host)
        allowed(False, app=other_app)
        (other_app / 'Contents/Extensions/FocusIntents.appex/Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': '../App'}))
        allowed(False, app=other_app)
        print('PASS: production Swift gate + persistent failure recovery: nonblocking startup, revocation, crash, readers, duplicate sessions, multiple owners, copies, channels, replacement and invalid installation')
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
