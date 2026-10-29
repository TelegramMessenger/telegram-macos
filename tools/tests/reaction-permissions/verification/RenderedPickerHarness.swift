import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import TelegramContext
import ChatHistoryModel
import GeneralRows

private var reactionEvidence: ReactionEvidence?
private let reactionEvidenceRoot = FileManager.default.temporaryDirectory.appendingPathComponent("telegram-reaction-ui")

final class ReactionEvidenceButton: NSButton {
    var invoke: (() -> Void)?
    @objc func run() { invoke?() }
}

private final class ReactionEvidence {
    let window: Window
    let table: TableView
    let interaction: ChatInteraction
    var row: ChatRowItem!
    var report: [[String: Any]] = []
    let status: NSTextField
    let source: ChatInteraction
    var mode = "restricted"
    var addition = MetaDisposable()
    var picker: Window?
    var pickerContent: NSView?

    init(source: ChatInteraction) {
        self.source = source
        let rect = NSMakeRect(0, 0, 820, 560)
        self.window = Window(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.window.title = "Reaction permissions — controlled native model"
        let host = View(frame: rect)
        host.backgroundColor = theme.colors.chatBackground
        self.table = TableView(frame: NSMakeRect(0, 150, 820, 410))
        table.backgroundColor = theme.colors.chatBackground
        self.interaction = ChatInteraction(chatLocation: .peer(PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(123456))), context: source.interactionContext)
        self.status = NSTextField(labelWithString: "Member · reactions restricted")
        status.textColor = theme.colors.text
        status.font = .systemFont(ofSize: 16, weight: .medium)
        status.frame = NSMakeRect(24, 20, 770, 28)
        host.addSubview(status)
        let note = NSTextField(labelWithString: "Production chat row and reaction picker. Local TelegramCore peer model; no server changes.")
        note.textColor = theme.colors.grayText
        note.frame = NSMakeRect(24, 52, 770, 22)
        host.addSubview(note)
        host.addSubview(table)
        window.contentView = host
        addButton("Show reaction picker", x: 24) { [weak self] in self?.showMenu() }
        addButton("Allow reactions", x: 215) { [weak self] in self?.update("allowed") }
        addButton("Restrict reactions", x: 405) { [weak self] in self?.update("restricted") }
        addButton("Administrator", x: 595) { [weak self] in self?.update("admin") }
        installRow()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func addButton(_ title: String, x: CGFloat, action: @escaping () -> Void) {
        let button = ReactionEvidenceButton(frame: NSMakeRect(x, 92, 175, 30))
        button.title = title
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(ReactionEvidenceButton.run)
        button.invoke = action
        window.contentView?.addSubview(button)
    }

    func peer(_ mode: String) -> TelegramGroup {
        let id = interaction.peerId
        let role: TelegramGroupRole = mode == "admin" ? .admin(.init(rights: []), rank: nil) : .member
        return TelegramGroup(id: id, title: "Reaction permission test", photo: [], participantCount: 2, role: role, membership: .Member, flags: [], defaultBannedRights: mode == "allowed" ? nil : TelegramChatBannedRights(flags: [.banSendReactions], untilDate: Int32.max), migrationReference: nil, creationDate: 0, version: 0)
    }

    func installRow() {
        let peer = peer(mode)
        interaction.update(animated: false) { $0.updatedPeer { _ in peer }.updatedMainPeer(peer) }
        let message = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1782388800, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: peer, text: "Reactions are restricted for this member.", attributes: [], media: [], peers: SimpleDictionary([peer.id: peer]), associatedMessages: .init(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        let entry = ChatHistoryEntry.MessageEntry(message, message.index, true, .bubble, .Full(rank: nil, rankType: .none, header: .normal), nil, .init())
        row = ChatRowItem.item(NSMakeSize(820, 410), from: entry, interaction: interaction, theme: theme) as? ChatRowItem
        _ = row.makeSize(820, oldWidth: 0)
        _ = table.addItem(item: GeneralRowItem(NSMakeSize(820, 410), height: 100, stableId: "spacer", backgroundColor: .clear))
        _ = table.addItem(item: row)
        record("initial")
    }

    func update(_ mode: String) {
        self.mode = mode
        let peer = peer(mode)
        interaction.update(animated: false) { $0.updatedPeer { _ in peer }.updatedMainPeer(peer) }
        status.stringValue = mode == "restricted" ? "Member · reactions restricted" : mode == "allowed" ? "Member · reactions allowed (live rights change)" : "Administrator · default reaction ban (exempt)"
        record("rights_changed")
    }

    func record(_ event: String, hasPicker: Bool? = nil) {
        var check: [String: Any] = ["event": event, "mode": mode, "canReact": row?.canReact ?? false, "messagePeerRestricted": true, "time": Date().timeIntervalSince1970]
        if let hasPicker { check["hasPickerWindow"] = hasPicker }
        report.append(check)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) { try? data.write(to: reactionEvidenceRoot.appendingPathComponent("observations.json"), options: .atomic) }
    }

    func showMenu() {
        picker?.orderOut(nil)
        pickerContent?.removeFromSuperview()
        pickerContent = nil
        picker = nil
        addition.set((row.menuAdditionView |> take(1) |> deliverOnMainQueue).start(next: { [weak self] picker in
            guard let self else { return }
            self.record("picker_requested", hasPicker: picker != nil)
            self.picker = picker
            if let picker {
                if let content = picker.contentView?.subviews.first {
                    content.removeFromSuperview()
                    content.frame.origin = NSMakePoint(55, 180)
                    self.window.contentView?.addSubview(content)
                    self.pickerContent = content
                }
            }
        }))
    }
}

func codexInstallReactionEvidence(source: ChatInteraction, parent: NSView) {
    try? FileManager.default.createDirectory(at: reactionEvidenceRoot, withIntermediateDirectories: true)
    guard !parent.subviews.contains(where: { $0 is ReactionEvidenceButton }) else { return }
    let button = ReactionEvidenceButton(frame: NSMakeRect(20, 130, 230, 30))
    button.title = "Reaction permission validation"
    button.bezelStyle = .rounded
    button.target = button
    button.action = #selector(ReactionEvidenceButton.run)
    button.invoke = {
        reactionEvidence = ReactionEvidence(source: source)
    }
    parent.addSubview(button)
}
