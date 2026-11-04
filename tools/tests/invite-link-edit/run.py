import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=root)
args = parser.parse_args()
root = args.root


def source(path):
    return (root / 'packages/InviteLinksUI/Sources/InviteLinksUI' / path).read_text()


def section(text, start, end):
    offset = text.index(start)
    return text[offset:text.index(end, offset)]


def edit_call(text):
    return section(text, 'manager?.editPeerExportedInvitation(link: link, title:', '\n')


controller = source('ClosureInviteLinkController.swift')
state = section(controller, 'public struct ClosureInviteLinkState: Equatable {', '//\nprivate let _id_period')
initial = section(controller, '    var initialState = ClosureInviteLinkState(', '    var getController:(()->InputDataController?)? = nil')
save = section(controller, '    controller.validateData = { data in', '    return modalController')
stops = section(controller, '        let hour: Int32 = 60 * 60', '        let titles: [String] = sizes.map { value in')
count_stops = section(controller, '            var sizes:[Int32] = [1, 10, 50, 100, Int32.max]', '            let titles: [String] = sizes.map { value in')
row_icon = section(source('InviteLinkRowItem.swift'), '    func update(link: _ExportedInvitation) {', '\n}\n\nprivate final class InviteLinkTokenView')
fixture = (Path(__file__).with_name('InviteLinkEditTests.swift.in').read_text()
           .replace('__STATE__', state)
           .replace('__INITIAL_STATE__', initial)
           .replace('__VALIDATE__', save)
           .replace('__PERIOD_STOPS__', stops)
           .replace('__COUNT_STOPS__', count_stops)
           .replace('__ROW_ICON_UPDATE__', row_icon)
           .replace('__LIST_CALL__', edit_call(source('InviteLinksController.swift')))
           .replace('__LINK_SCREEN_CALL__', edit_call(source('ExportedInvitationController.swift'))))

with tempfile.TemporaryDirectory(prefix='invite-link-edit-tests-') as directory:
    directory = Path(directory)
    main = directory / 'main.swift'
    main.write_text(fixture)
    binary = directory / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(directory / 'cache'), str(main), '-o', str(binary)], check=True)
    raise SystemExit(subprocess.run([str(binary)]).returncode)
