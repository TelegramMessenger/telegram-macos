from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
presentation = (root / 'packages/ChatUI/Sources/ChatUI/ChatPresentationInterfaceState.swift').read_text()
attach = (root / 'packages/ChatUI/Sources/ChatUI/ChatInputAttachView.swift').read_text()
action = (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text().split('\nfunc chatHasSameDeferredSendState')[0]
fixture = Path(__file__).with_name('AttachmentTests.swift').read_text().replace('__ACTION__', action)

def block_end(text, start):
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return end

permissions = []
for marker in ['    var canAttachFiles:', '    func canAttachMedia(', '    func canOpenFilePicker(']:
    start = presentation.index(marker)
    permissions.append(presentation[start:block_end(presentation, start)])
fixture = fixture.replace('__PICKER_PERMISSIONS__', '\n'.join(permissions))

for route, following, call, indent, placeholder in [
    ('attachFile', 'attachPhotoOrVideo', 'filePanel(', 24, '__FILES__'),
    ('attachPhotoOrVideo', 'attachPicture', 'filePanel(', 20, '__PHOTOS__'),
    ('attachPicture', 'attachLocation', 'pickImage(', 16, '__IMAGE__'),
]:
    start = source.index('        chatInteraction.' + route + ' =')
    end = source.index('        chatInteraction.' + following + ' =', start)
    route_source = source[start:end]
    declarations = '\n'.join(line for line in route_source.splitlines() if 'let journey =' in line or 'let selectionAction =' in line)
    start = route_source.index(call)
    closing = '\n' + (' ' * indent) + '})'
    end = route_source.index(closing, start) + len(closing)
    if route == 'attachFile':
        start = route_source.index('                    if self.chatInteraction.presentation.canOpenFilePicker(')
        end = block_end(route_source, start)
        end = block_end(route_source, route_source.index('else {', end))
        body = declarations + '\n' + route_source[start:end]
    elif route == 'attachPhotoOrVideo':
        start = route_source.index('                    let permissions:')
        body = declarations + '\n' + route_source[start:end]
    else:
        start = route_source.index('                let journey =')
        body = route_source[start:end]
    fixture = fixture.replace(placeholder, body)

start = source.index('        chatInteraction.attachAudio =')
start = source.index('            let presentation =', start)
end = source.index('\n        }', start)
fixture = fixture.replace('__AUDIO__', source[start:end])
start = source.index('            self?.chatInteraction.attachFile(true)')
end = source.index('        }, with: self, for: .O', start)
fixture = fixture.replace('__COMMAND_OPEN__', source[start:end])
start = attach.index('items.append(ContextMenuItem(strings().inputAttachAudio, handler: { [weak self] in')
start = attach.index('\n', start) + 1
end = attach.index('                }, itemImage: MenuAnimation.menu_music.value))', start)
fixture = fixture.replace('__AUDIO_MENU__', attach[start:end])
with tempfile.TemporaryDirectory(prefix='attachment-acquisition-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AttachmentAcquisition", targets: [.testTarget(name: "AttachmentAcquisitionTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/AttachmentTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
