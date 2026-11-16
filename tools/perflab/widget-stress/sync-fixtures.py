import argparse
from pathlib import Path
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
source = Path(__file__).resolve().parent
destination = source.parents[2] / 'packages/HTMLBubbles/Tests/HTMLBubblesTests/Fixtures/widget-sandbox/showcase/stress'
fixtures = sorted(source.glob('*.html'))
mismatches = []
for fixture in fixtures:
    target = destination / ('perflab-' + fixture.name)
    if args.check:
        if not target.exists() or target.read_bytes() != fixture.read_bytes():
            mismatches.append(target.name)
    else:
        destination.mkdir(parents=True, exist_ok=True)
        target.write_bytes(fixture.read_bytes())
if mismatches:
    sys.exit('Stress fixtures differ from the shared chat resources: ' + ', '.join(mismatches))
print(f'{len(fixtures)} identical fixtures available to both All Widgets chats')
