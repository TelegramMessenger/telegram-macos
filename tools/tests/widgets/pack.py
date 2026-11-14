from pathlib import Path
import argparse
import hashlib
import json
import zlib


def pack(source, output):
    raw = source.read_bytes()
    raw.decode('utf-8', errors='strict')
    if not raw or b'\0' in raw:
        raise ValueError('Widget HTML must be nonempty UTF-8 without NUL bytes')
    if len(raw) > 32768:
        raise ValueError(f'HTML is {len(raw)} bytes; server limit is 32768')
    payload = zlib.compress(raw, 9)
    if len(payload) > 4096:
        raise ValueError(f'Packed widget is {len(payload)} bytes; server limit is 4096')
    if output.suffix != '.tgw':
        raise ValueError('Output must have the .tgw extension')
    if output.resolve() == source.resolve():
        raise ValueError('Output must differ from the HTML source')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(payload)
    manifest = {
        'source': str(source.resolve()),
        'file': str(output.resolve()),
        'encoding': 'zlib',
        'level': 9,
        'htmlBytes': len(raw),
        'bytes': len(payload),
        'htmlSha256': hashlib.sha256(raw).hexdigest(),
        'sha256': hashlib.sha256(payload).hexdigest(),
    }
    output.with_suffix('.manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def main():
    parser = argparse.ArgumentParser(description='Pack UTF-8 HTML as a level-9 zlib .tgw for WidgetBot.')
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(pack(args.source, args.output), indent=2))
    except (OSError, UnicodeError, ValueError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
