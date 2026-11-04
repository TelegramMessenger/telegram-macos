from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
package_sources = root / 'packages/FocusFilterCore/Sources'

with tempfile.TemporaryDirectory(prefix='telegram-focus-intents-') as directory:
    directory = Path(directory)
    shared = ['xcrun', 'swiftc', '-swift-version', '5', '-target', f'{platform.machine()}-apple-macosx13.0', '-module-cache-path', str(directory / 'ModuleCache')]
    for module in ['FocusFilterCore', 'FocusFilterInfrastructure']:
        sources = sorted((package_sources / module).glob('*.swift'))
        if not sources:
            raise SystemExit(f'Missing sources for {module}')
        command = shared + ['-emit-module', '-emit-library', '-module-name', module, '-I', str(directory), '-L', str(directory)]
        if module == 'FocusFilterInfrastructure':
            command += ['-lFocusFilterCore']
        command += [str(source) for source in sources]
        command += ['-emit-module-path', str(directory / f'{module}.swiftmodule'), '-o', str(directory / f'lib{module}.dylib')]
        subprocess.run(command, check=True)
    subprocess.run(shared + [
        '-typecheck', '-parse-as-library', '-I', str(directory)
    ] + [str(source) for source in sorted((root / 'FocusIntents').glob('*.swift'))], check=True)
    executable = directory / 'tests'
    subprocess.run(shared + [
        '-parse-as-library', '-I', str(directory), '-L', str(directory),
        '-lFocusFilterCore', '-lFocusFilterInfrastructure',
        '-Xlinker', '-rpath', '-Xlinker', str(directory),
        str(root / 'FocusIntents/FocusEntities.swift'),
        str(root / 'FocusIntents/FocusFilterIntent.swift'),
        str(fixtures / 'FocusIntentTests.swift'),
        '-o', str(executable)
    ], check=True)
    raise SystemExit(subprocess.run([str(executable)]).returncode)
