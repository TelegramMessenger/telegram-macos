import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=root)
args = parser.parse_args()
source = args.source_root / 'packages/ChatUI/Sources/ChatUI'

def block(text, marker):
    start = text.index(marker) + len(marker)
    end = start
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end - 1]

row = (source / 'ChatRowItem.swift').read_text()
measure = block(row, '} else if let replyModel = replyModel {')
height_start = row.index('        if isBubbled {\n            if let additional = additionalLineForDateInBubbleState')
height = row[height_start:row.index('        if let _ = commentsBubbleData', height_start)]
adapter = (source / 'ChatRowGeometry+Item.swift').read_text()
content = 'extension ChatRowGeometry.Content {' + block(adapter, 'extension ChatRowGeometry.Content {') + '}\n'
adapter = (source / 'ChatRowAccessoryGeometry+Item.swift').read_text()
side = 'extension ChatRowGeometry.SideAccessory {' + block(adapter, 'extension ChatRowGeometry.SideAccessory {') + '}\n'
fixture = Path(__file__).with_name('SideReplyLayoutTests.swift').read_text().replace('__MEASURE__', measure).replace('__HEIGHT__', height)
with tempfile.TemporaryDirectory(prefix='side-reply-layout-') as temp:
    temp = Path(temp)
    for name in ['ChatRowGeometry.swift', 'ChatRowAccessoryGeometry.swift']:
        (temp / name).write_bytes((source / name).read_bytes())
    (temp / 'Adapters.swift').write_text('import Cocoa\n' + content + side)
    (temp / 'main.swift').write_text(fixture)
    binary = temp / 'tests'
    subprocess.run(['swiftc', str(temp / 'ChatRowGeometry.swift'), str(temp / 'ChatRowAccessoryGeometry.swift'), str(temp / 'Adapters.swift'), str(temp / 'main.swift'), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
