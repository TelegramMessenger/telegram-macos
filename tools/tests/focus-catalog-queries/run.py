from pathlib import Path
import os
import platform
import shutil
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
if platform.system() != 'Linux':
    raise SystemExit('This fixture runner requires Linux; on macOS run tools/tests/focus-intents/run.py')
compiler = os.environ.get('SWIFTC') or shutil.which('swiftc')
if compiler is None:
    raise SystemExit('Swift compiler required: set SWIFTC or add swiftc to PATH')

with tempfile.TemporaryDirectory(prefix='telegram-focus-catalog-queries-') as temporary:
    directory = Path(temporary)
    shared = [compiler, '-swift-version', '5', '-module-cache-path', str(directory / 'ModuleCache')]
    modules = {
        'FocusFilterCore': sorted((root / 'packages/FocusFilterCore/Sources/FocusFilterCore').glob('*.swift')),
        'AppIntents': [fixtures / 'AppIntentsFixture.swift'],
    }
    for module, sources in modules.items():
        if not sources:
            raise SystemExit(f'Missing sources for {module}')
        subprocess.run(shared + [
            '-emit-module', '-emit-library', '-module-name', module,
            '-emit-module-path', str(directory / f'{module}.swiftmodule'),
            '-o', str(directory / f'lib{module}.so'),
        ] + [str(source) for source in sources], check=True)
    executable = directory / 'tests'
    subprocess.run(shared + [
        '-parse-as-library', '-I', str(directory), '-L', str(directory),
        '-lFocusFilterCore', '-lAppIntents',
        '-Xlinker', '-rpath', '-Xlinker', str(directory),
        str(root / 'FocusIntents/FocusEntities.swift'),
        str(fixtures / 'FocusCatalogQueryTests.swift'),
        '-o', str(executable),
    ], check=True)
    raise SystemExit(subprocess.run([str(executable)]).returncode)
