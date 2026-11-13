import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def body(source, marker):
    start = source.index('{', source.index(marker)) + 1
    depth = 1
    for index in range(start, len(source)):
        depth += (source[index] == '{') - (source[index] == '}')
        if depth == 0:
            return source[start:index]
    raise AssertionError('Unclosed Swift body: ' + marker)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--revision')
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}

    def read(path):
        data = subprocess.check_output(['git', '-C', str(ROOT), 'show', args.revision + ':' + path], env=env) if args.revision else (ROOT / path).read_bytes()
        return data.decode('utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8')

    rows = read('packages/AffiliateUI/Sources/AffiliateUI/Affiliate_IntroRows.swift')
    header, promo = rows.split('public final class Affiliate_PromoItem :', 1)
    general = read('packages/GeneralRows/Sources/GeneralRows/GeneralRowItem.swift')
    options = read('packages/TGUIKit/Sources/OptionsListView.swift')
    strings = read('Telegram-Mac/en.lproj/Localizable.strings')
    fonts = read('packages/TGUIKit/Sources/TGFont.swift')
    widths = re.search(r'width: initialSize.width - 40([^\n]*)', promo).group(1)
    width_inset = re.search(r'widthInset: ([0-9.]+)', widths)
    option_init = body(options, 'public init(image:')
    option_layout = body(options, 'override func layout()')
    header_super = re.search(r'        super.init\(initialSize, stableId: stableId[^\n]+', header).group().strip()
    caller_types = []
    for name in ('Affiliate_PeerController.swift', 'Affiliate_StartController.swift'):
        source = read('packages/AffiliateUI/Sources/AffiliateUI/' + name)
        caller_types.append(re.search(r'return Affiliate_HeaderItem\([^\n]+viewType: (\.[A-Za-z]+)\)', source).group(1))

    def localized(key):
        return re.search(r'^"' + re.escape(key) + r'" = ("(?:[^"\\]|\\.)*");$', strings, re.MULTILINE).group(1)

    sets = []
    for kind, title_key, info_key in [('Join', 'AffiliateSetup.TitleJoin', 'AffiliateSetup.TextJoin'), ('New', 'AffiliateSetup.TitleNew', 'AffiliateSetup.Header.Info')]:
        pairs = ', '.join('(' + localized(f'AffiliateSetup.Intro{kind}.Title{i}') + ', ' + localized(f'AffiliateSetup.Intro{kind}.Text{i}') + ')' for i in range(1, 4))
        sets.append(f'({localized(title_key)}, {localized(info_key)}, [{pairs}])')
    replacements = {
        '__INNER_INSET__': body(general, 'public var innerInset:'),
        '__SINGLE_ITEM__': body(general, 'public static var singleItem:'),
        '__BLOCK_WIDTH__': body(general, 'open var blockWidth:'),
        '__HEADER_SUPER__': header_super,
        '__HEADER_SIZE__': body(header, 'public override func makeSize('),
        '__HEADER_HEIGHT__': body(header, 'public override var height:'),
        '__HEADER_LAYOUT__': body(header, 'public override func layout()'),
        '__PROMO_SIZE__': body(promo, 'public override func makeSize('),
        '__PROMO_HEIGHT__': body(promo, 'public override var height:'),
        '__OPTION_SIZE__': body(options, 'public func makeSize(width:'),
        '__OPTION_FRAME_SIZE__': body(options, 'public var size:'),
        '__CONTENT_SIZE__': body(options, 'public static func contentSize('),
        '__OPTIONS_HEIGHT__': body(options, 'public static func height('),
        '__OPTION_LAYOUT__': option_layout,
        '__WIDTH_INSET__': width_inset.group(1) if width_inset else '0',
        '__CALLER_TYPES__': ', '.join(caller_types),
        '__ENGLISH_FIXTURES__': ',\n    '.join(sets),
        '__HEADER_FONT__': re.search(r'static let header: CGFloat = ([0-9.]+)', fonts).group(1),
        '__TEXT_FONT__': re.search(r'static let text: CGFloat = ([0-9.]+)', fonts).group(1),
    }
    assert 'self.textInset = textInset' in option_init and 'self.widthInset = widthInset' in option_init
    assert 'widthInset: CGFloat = 0' in options and 'textInset: CGFloat = 40' in options
    assert 'optionsView.centerX(y: 15)' in promo and 'optionsView.spacing = 15' in promo
    assert 'subview.centerX(y: y)' in options and 'max(option.width, size.width)' in replacements['__CONTENT_SIZE__']
    swift = Path(__file__).with_name('AffiliateLayoutTests.swift.in').read_text()
    for key, value in replacements.items():
        swift = swift.replace(key, value)
    assert not re.search(r'__[A-Z_]+__', swift)

    def run(output):
        source = output / 'main.swift'
        source.write_text(swift)
        binary = output / 'tests'
        print('Native CoreText with extracted row/option contracts; no Telegram window, SceneKit or account operations.', flush=True)
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(output / 'module-cache'), str(source), '-o', str(binary)], env=env, check=True)
        subprocess.run([str(binary)], env=env, check=True)

    if args.output_dir:
        output = args.output_dir.absolute()
        output.mkdir(parents=True, exist_ok=False)
        run(output)
    else:
        with tempfile.TemporaryDirectory(prefix='affiliate-layout-') as directory:
            run(Path(directory))


if __name__ == '__main__':
    main()
