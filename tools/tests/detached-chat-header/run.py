import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatHeaderBubblesView.swift').read_text()
start = source.index('private final class DetachedChatWindowControlsView:')
end = source.index('private final class RightActionsCluster:', start)
fixture = Path(__file__).with_name('WindowControlsTests.swift').read_text()
fixture = fixture.replace('__WINDOW_CONTROLS__', source[start:end])
with tempfile.TemporaryDirectory(prefix='detached-chat-header-') as directory:
    directory = Path(directory)
    source_path = directory / 'main.swift'
    source_path.write_text(fixture)
    executable = directory / 'WindowControlsTests'
    environment = os.environ.copy()
    environment['CLANG_MODULE_CACHE_PATH'] = str(directory / 'ModuleCache')
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'ModuleCache'), str(source_path), '-o', str(executable)], env=environment, check=True)
    raise SystemExit(subprocess.run([str(executable)], env=environment).returncode)
