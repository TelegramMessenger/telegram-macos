from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / "packages/HTMLBubbles/Sources/HTMLBubbles"
contents = (source / "HTMLDemoChatContents.swift").read_text()
catalog = (source / "HTMLDemoCatalog.swift").read_text()
field = next(line for line in contents.splitlines() if "private var multiplayerClient:" in line)
constructor = re.search(r'        if [^\n]*chat.id == "html-voxel-clash" \{.*?\n        \}', contents, re.S).group()
open_link = re.search(r'    public func openGameLink\(.*?\n    \}', contents, re.S).group()
command_link = next(line for line in contents.splitlines() if "client.openLink(text." in line)
chats = re.search(r'    public static let chats: \[HTMLDemoChat\] = \{.*?\n    \}\(\)', catalog, re.S).group()
support = '''
import Foundation
final class DemoVisibility { var isHTMLBubbleVisible = true }
final class HTMLBubbleState {
    var twidgetHost: NSObject?
    var visibility: DemoVisibility?
    func sendDemoEvent(_ json: String) {}
    static func prewarmLibraries() {}
}
struct DemoPeer { func toInt64() -> Int64 { 1 } }
enum DemoEngine { case twidget, webKit }
enum DemoPreset { case allWidgets, voxelClash }
struct DemoWidget { let summary: Int }
public struct HTMLDemoChat {
    let id: String
    let title: String
    let status: String
    let peer: DemoPeer
    let engine: DemoEngine
    let preset: DemoPreset
}
final class ClientOwner {
FIELD
    init(chat: HTMLDemoChat, accountName: String, accountPeerId: DemoPeer) {
CONSTRUCTOR
    }
OPEN_LINK
    func openCommand(_ text: String) {
        if let client = multiplayerClient {
COMMAND_LINK
        }
    }
}
enum CatalogFixture {
    static func widgetFiles(_ preset: DemoPreset) -> [DemoWidget] { [] }
    static func makeUser(index: Int, name: String, isBot: Bool) -> DemoPeer { DemoPeer() }
CHATS
}
'''
for key, value in {"FIELD": field, "CONSTRUCTOR": constructor, "OPEN_LINK": open_link, "COMMAND_LINK": command_link, "CHATS": chats}.items():
    support = support.replace(key, value)

with tempfile.TemporaryDirectory(prefix="html-multiplayer-availability-") as directory:
    work = Path(directory)
    fixture = work / "Support.swift"
    fixture.write_text(support)
    client = source / "HTMLMultiplayerDemoClient.swift"
    for target in ("x86_64-apple-macosx10.13", "x86_64-apple-macosx10.15", "arm64-apple-macosx11.0"):
        command = ["xcrun", "swiftc", "-typecheck", "-swift-version", "5", "-target", target,
                   "-module-cache-path", str(work / "cache"), str(fixture), str(client)]
        subprocess.run(command, check=True)
        print(f"PASS {target}: production client, extracted owner and catalog", flush=True)
    fixture.write_text(support.replace('if #available(macOS 10.15, *), chat.id', 'if chat.id'))
    command[command.index("-target") + 1] = "x86_64-apple-macosx10.13"
    result = subprocess.run(command, capture_output=True, text=True)
    assert result.returncode != 0 and "only available in macOS 10.15 or newer" in result.stderr
    print("PASS negative control: removing the construction guard fails compilation")
