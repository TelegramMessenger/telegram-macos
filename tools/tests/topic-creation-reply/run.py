import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=root)
args = parser.parse_args()
source = (args.source_root / 'packages/ChatUI/Sources/ChatUI/ChatRowItem.swift').read_text()
reply_start = source.index('if let attribute = attribute as? ReplyMessageAttribute, let replyMessage =')
start = source.index('var ignore: Bool = false', reply_start)
end = source.index('if !ignore {', start)
fixture = Path(__file__).with_name('TopicCreationReplyTests.swift').read_text()
fixture = fixture.replace('__REPLY_POLICY__', source[start:end])
with tempfile.TemporaryDirectory(prefix='topic-creation-reply-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['swiftc', str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
