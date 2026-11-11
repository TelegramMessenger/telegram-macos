from pathlib import Path
import atexit
import subprocess
import tempfile


def isolated_source_root(source):
    source = Path(source).resolve()
    scratch = tempfile.TemporaryDirectory(prefix='telegram-native-validation-')
    target = Path(scratch.name) / 'checkout'
    try:
        subprocess.run(['ditto', '--clone', str(source), str(target)], check=True)
    except BaseException:
        scratch.cleanup()
        raise
    atexit.register(scratch.cleanup)
    print('Disposable native validation checkout: ' + str(target), flush=True)
    return target
