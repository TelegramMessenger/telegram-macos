import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


source = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
scheduled = section(source, '        case .scheduled:\n            items.append(ContextMenuItem(strings().chatContextClearScheduled', '        case .history:')
composer_button = section(source, '            let hasScheduledMessages = combineLatest(', '        default:\n            break')
fixture = Path(__file__).with_name('ScheduledClearTests.swift.in').read_text().replace('__SCHEDULED_CASE__', scheduled).replace('__COMPOSER_BUTTON__', composer_button)

with tempfile.TemporaryDirectory(prefix='scheduled-clear-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
