from pathlib import Path
import platform
import plistlib
import selectors
import subprocess
import tempfile
import time
import uuid


class FixtureProcess:
    def __init__(self, executable):
        self.process = subprocess.Popen(
            [str(executable)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        self.lines = []
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)

    def read_until(self, marker=None, timeout=65):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            events = self.selector.select(timeout=min(0.5, deadline - time.monotonic()))
            if events:
                line = self.process.stdout.readline()
                if line:
                    line = line.rstrip()
                    self.lines.append(line)
                    print(line, flush=True)
                    if marker is not None and line.startswith(marker + ' '):
                        return
                    continue
                self.process.wait(timeout=5)
                if marker is not None:
                    raise AssertionError(f'Fixture exited before {marker}')
                return
        raise AssertionError(f'Fixture timed out waiting for {marker or "exit"}')

    def marker_time(self, marker):
        matches = [line for line in self.lines if line.startswith(marker + ' ')]
        if len(matches) != 1:
            raise AssertionError(f'Expected exactly one {marker}, got {matches}')
        return float(matches[0].split()[-1])

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.selector.close()
        self.process.stdout.close()


def compile_modules(directory, sources, shared):
    for module in ['FocusFilterCore', 'FocusFilterInfrastructure']:
        files = sorted((sources / module).glob('*.swift'))
        if not files:
            raise AssertionError(f'Missing sources for {module}')
        command = shared + [
            '-emit-module', '-emit-library', '-module-name', module,
            '-I', str(directory), '-L', str(directory),
        ]
        if module == 'FocusFilterInfrastructure':
            command += ['-lFocusFilterCore']
        command += [str(file) for file in files]
        command += [
            '-emit-module-path', str(directory / f'{module}.swiftmodule'),
            '-o', str(directory / f'lib{module}.dylib'),
        ]
        subprocess.run(command, check=True)


def make_application(path, build, directory, fixture, shared, identity):
    extension = path / 'Contents/Extensions/FocusIntents.appex'
    executable_name = 'Telegram Focus Filters'
    executable = extension / 'Contents/MacOS' / executable_name
    executable.parent.mkdir(parents=True)
    host = path / 'Contents/MacOS/Telegram'
    host.parent.mkdir()
    host.write_text(f'Lifecycle fixture host {build}\n')
    for bundle, name, bundle_identifier in [
        (path, 'Telegram', identity),
        (extension, executable_name, identity + '.FocusIntents'),
    ]:
        info = {
            'CFBundleExecutable': name,
            'CFBundleIdentifier': bundle_identifier,
            'CFBundleName': name,
            'CFBundlePackageType': 'APPL' if bundle == path else 'XPC!',
            'CFBundleShortVersionString': '1.0',
            'CFBundleVersion': '1',
            'FocusAppGroup': 'group.' + identity,
            'SOURCE': 'STABLE',
        }
        with (bundle / 'Contents/Info.plist').open('wb') as output:
            plistlib.dump(info, output)
    command = shared + [
        '-parse-as-library', '-I', str(directory), '-L', str(directory),
        '-lFocusFilterCore', '-lFocusFilterInfrastructure',
        '-Xlinker', '-rpath', '-Xlinker', str(directory),
    ]
    if build == 'A':
        command += ['-D', 'BUILD_A']
    subprocess.run(command + [str(fixture), '-o', str(executable)], check=True)
    legacy_executable = executable.with_name('FocusIntents')
    if legacy_executable.exists() or legacy_executable.is_symlink():
        raise AssertionError('Legacy executable path must be absent, including dangling symlinks')
    return executable


def run():
    if platform.system() != 'Darwin':
        raise SystemExit('This test requires macOS and Xcode command-line tools.')
    fixtures = Path(__file__).resolve().parent
    root = fixtures.parents[2]
    sources = root / 'packages/FocusFilterCore/Sources'
    with tempfile.TemporaryDirectory(prefix='telegram-focus-lifecycle-') as temporary:
        directory = Path(temporary)
        shared = [
            'xcrun', 'swiftc', '-swift-version', '5',
            '-target', f'{platform.machine()}-apple-macosx13.0',
            '-module-cache-path', str(directory / 'ModuleCache'),
        ]
        print('Compiling production Focus lifecycle and isolated fixtures...', flush=True)
        compile_modules(directory, sources, shared)
        installed = directory / 'Telegram.app'
        replacement = directory / 'Replacement.app'
        identity = 'org.telegram.FocusLifecycleFixture.' + uuid.uuid4().hex
        first_executable = make_application(installed, 'A', directory, fixtures / 'Fixture.swift', shared, identity)
        make_application(replacement, 'B', directory, fixtures / 'Fixture.swift', shared, identity)
        first = FixtureProcess(first_executable)
        try:
            first.read_until('READY A', timeout=10)
            installed.rename(directory / 'Previous.app')
            replacement.rename(installed)
            extension = installed / 'Contents/Extensions/FocusIntents.appex'
            with (extension / 'Contents/Info.plist').open('rb') as source:
                executable_name = plistlib.load(source)['CFBundleExecutable']
            second_executable = extension / 'Contents/MacOS' / executable_name
            print('Replaced A with B at the same executable path and bundle version; no notification sent.', flush=True)
            first.read_until()
            if first.process.returncode != 0:
                raise AssertionError(f'Old fixture exited with {first.process.returncode}')
            ready = first.marker_time('READY A')
            finished = first.marker_time('WORK_FINISHED')
            exited = first.marker_time('EXIT')
            if finished - ready < 34.9 or exited - finished < 1.99:
                raise AssertionError('Old fixture retired before active work and its grace period completed')
            if not any('retiring after an application update' in line for line in first.lines):
                raise AssertionError('Old fixture did not use production lifecycle retirement')
            print(f'PASS: A retired after {exited - ready:.2f}s, {exited - finished:.2f}s after work finished.', flush=True)
        finally:
            first.close()

        second = FixtureProcess(second_executable)
        try:
            second.read_until('READY B', timeout=10)
            second.read_until()
            if second.process.returncode != 0:
                raise AssertionError(f'Current fixture exited with {second.process.returncode}')
            ready = second.marker_time('READY B')
            normal = second.marker_time('NORMAL B')
            second.marker_time('EXIT')
            if normal - ready < 44.9:
                raise AssertionError('Current fixture did not cover a periodic installation check')
            if sum(line.startswith('NOTIFIED B ') for line in second.lines) != 3:
                raise AssertionError('Current fixture did not send all same-build launch notifications')
            if any('retiring after an application update' in line for line in second.lines):
                raise AssertionError('Current fixture was incorrectly retired')
            print('PASS: B remained alive through same-build notifications and periodic checking.', flush=True)
        finally:
            second.close()
    print('All lifecycle subprocess checks passed; temporary files and fixture processes cleaned up.', flush=True)


if __name__ == '__main__':
    run()
