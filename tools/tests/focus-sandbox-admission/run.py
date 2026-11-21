from pathlib import Path
import json
import platform
import plistlib
import select
import shutil
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
sources = root / 'packages/FocusFilterCore/Sources/FocusFilterInfrastructure'

if platform.system() != 'Darwin':
    raise SystemExit('This regression requires macOS and the Darwin sandbox.')
if not Path('/usr/bin/sandbox-exec').is_file():
    raise SystemExit('sandbox-exec is required; this regression cannot be skipped.')


def expect(process, expected):
    if not select.select([process.stdout], [], [], 10)[0]:
        raise AssertionError(f'Timed out waiting for {expected!r}')
    actual = process.stdout.readline().strip()
    if actual != expected:
        raise AssertionError(f'Expected {expected!r}, received {actual!r}, exit={process.poll()}')


def command(process, value, expected):
    process.stdin.write(value + '\n')
    process.stdin.flush()
    expect(process, expected)


def bundle(directory, package_type, executable):
    (directory / 'Contents/MacOS').mkdir(parents=True)
    (directory / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': executable,
        'CFBundleIdentifier': 'org.telegram.focus.sandbox-fixture.' + ('app' if package_type == 'APPL' else 'extension'),
        'CFBundlePackageType': package_type,
        'CFBundleVersion': '1',
    }))
    return directory / 'Contents/MacOS' / executable


with tempfile.TemporaryDirectory(prefix='focus-sandbox-admission-') as temporary:
    directory = Path(temporary).resolve()
    binary = directory / 'Fixture'
    subprocess.run([
        'xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-module-cache-path', str(directory / 'ModuleCache'),
        *(str(sources / name) for name in [
            'FocusApplicationLocation.swift', 'FocusCatalogAccess.swift', 'FocusExtensionInstallation.swift',
        ]),
        str(fixtures / 'Fixture.swift'), '-o', str(binary),
    ], check=True, timeout=120)
    application = directory / 'Telegram.app'
    owner_executable = bundle(application, 'APPL', 'FocusFixture')
    extension = application / 'Contents/Extensions/FocusIntents.appex'
    reader_executable = bundle(extension, 'XPC!', 'FocusFixture')
    for executable in [owner_executable, reader_executable]:
        shutil.copy2(binary, executable)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(executable)], check=True, timeout=30)
    storage = directory / 'SharedStorage'
    profile = directory / 'reader.sb'
    denied = [application / 'Contents/Info.plist', owner_executable]
    profile.write_text('(version 1)\n(allow default)\n' + ''.join(
        f'(deny file-read* (literal {json.dumps(str(path))}))\n' for path in denied
    ))
    processes = []
    try:
        owner = subprocess.Popen(
            [str(owner_executable), 'owner', str(storage), str(application)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
        processes.append(owner)
        expect(owner, 'ready')
        reader = subprocess.Popen(
            ['/usr/bin/sandbox-exec', '-f', str(profile), str(reader_executable), 'reader', str(storage), str(application)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
        processes.append(reader)
        expect(reader, 'host-files-denied')
        command(reader, 'state', 'locked')
        command(owner, 'unlock', 'done')
        command(reader, 'state', 'accessible')
        command(owner, 'lock', 'done')
        command(reader, 'state', 'locked')
        command(owner, 'unlock', 'done')
        command(reader, 'state', 'accessible')
        print('PASS: sandbox denies host metadata/executable reads; production extension-bundle admission follows lock/unlock')
        gate, = (storage / 'CatalogAccess').iterdir()
        gate.write_bytes(b'\x01')
        command(reader, 'state', 'unavailable')
        gate.write_bytes(b'\x00')
        command(reader, 'state', 'accessible')
        print('PASS: verification failure stays closed and recovers without replacing the reader')
        owner.kill()
        owner.wait(timeout=10)
        command(reader, 'state', 'locked')
        reader.stdin.close()
        assert reader.wait(timeout=10) == 0
        print('PASS: owner crash revokes the live permit inside the sandbox')
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)
