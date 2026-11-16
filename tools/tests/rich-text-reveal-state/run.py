import argparse
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/ChatUI/Sources/ChatUI/ChatRichTextRowItem.swift')
parser.add_argument('--evidence', type=Path, required=True)
args = parser.parse_args()
source = args.source.read_text()
declaration = next(line for line in source.splitlines() if line.startswith('private ') and 'instantPageStreamRevealCursors' in line)
start = source.index('    public var isRevealAnimationActive: Bool {')
getter = source[start:source.index('\n    }', start) + len('\n    }')]
store_source = source[source.index('        let seed = self.revealController?'):]
old = '        instantPageStreamRevealCursors[item.stableId] = seed'
if old in store_source:
    store = old
else:
    start = store_source.index('        _ = instantPageStreamRevealCursors.modify {')
    store = store_source[start:store_source.index('\n        }', start) + len('\n        }')]
start = source.index('    private func finishReveal(')
tail = source[start:]
old = '        instantPageStreamRevealCursors.removeValue(forKey: item.stableId)'
if old in tail:
    remove = old
else:
    start = tail.index('        _ = instantPageStreamRevealCursors.modify {')
    remove = tail[start:tail.index('\n        }', start) + len('\n        }')]
fixture = Path(__file__).with_name('RevealStateTests.swift').read_text().replace('__DECLARATION__', declaration).replace('__GETTER__', getter).replace('__STORE__', store).replace('__REMOVE__', remove)
atomic = (root / 'submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit/Source/Atomic.swift').read_text()
args.evidence.mkdir(parents=True, exist_ok=True)
(args.evidence / 'main.swift').write_text(atomic + '\n' + fixture)
binary = str(args.evidence / 'tests')
command = ['swiftc', '-sanitize=thread', '-module-cache-path', '/tmp/rich-text-reveal-state-cache', str(args.evidence / 'main.swift'), '-o', binary]
result = subprocess.run(command, capture_output=True, text=True)
output = '$ ' + ' '.join(command) + '\n' + result.stdout + result.stderr
if result.returncode:
    print(output)
    raise SystemExit(result.returncode)
result = subprocess.run([binary], capture_output=True, text=True, env={**os.environ, 'TSAN_OPTIONS': 'halt_on_error=1:exitcode=66'}, timeout=120)
output += '\n$ ' + binary + '\n' + result.stdout + result.stderr + f'\nexit {result.returncode}\n'
(args.evidence / 'results.log').write_text(output)
print(result.stdout + result.stderr[:3500] + f'\nexit {result.returncode}')
raise SystemExit(result.returncode)
