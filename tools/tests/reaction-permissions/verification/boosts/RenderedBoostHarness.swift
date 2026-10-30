import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import TelegramContext
import ChatHistoryModel
import GeneralRows
import InAppSettings

private var boostReactionEvidence: BoostReactionEvidence?
private let boostReactionEvidenceRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TELEGRAM_BOOST_EVIDENCE"] ?? NSTemporaryDirectory()).appendingPathComponent("reaction-boost")

final class BoostReactionEvidenceButton: NSButton {
    var invoke: (() -> Void)?
    @objc func run() { invoke?() }
}

private final class BoostReactionEvidence {
    let window: Window
    let table: TableView
    let interaction: ChatInteraction
    var row: ChatRowItem!
    var report: [[String: Any]] = []
    let status: NSTextField
    let source: ChatInteraction
    var mode = "boosted"
    var addition = MetaDisposable()
    var picker: Window?
    var pickerContent: NSView?

    init(source: ChatInteraction) {
        try? FileManager.default.createDirectory(at: boostReactionEvidenceRoot, withIntermediateDirectories: true)
        self.source = source
        let rect = NSMakeRect(0, 0, 820, 560)
        self.window = Window(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.window.title = "Boost reaction permissions — controlled native model"
        let host = View(frame: rect)
        host.backgroundColor = theme.colors.chatBackground
        self.table = TableView(frame: NSMakeRect(0, 150, 820, 410))
        table.backgroundColor = theme.colors.chatBackground
        self.interaction = ChatInteraction(chatLocation: .peer(PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(123456))), context: source.interactionContext)
        self.status = NSTextField(labelWithString: "Member · 2/2 boosts · default reaction ban")
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
        addButton("Add 2 boosts", x: 215) { [weak self] in self?.update("boosted") }
        addButton("Remove boosts", x: 405) { [weak self] in self?.update("restricted") }
        addButton("Personal ban", x: 595) { [weak self] in self?.update("personal") }
        installRow()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func addButton(_ title: String, x: CGFloat, action: @escaping () -> Void) {
        let button = BoostReactionEvidenceButton(frame: NSMakeRect(x, 92, 175, 30))
        button.title = title
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(BoostReactionEvidenceButton.run)
        button.invoke = action
        window.contentView?.addSubview(button)
    }

    func peer(_ mode: String) -> TelegramChannel {
        let ban = TelegramChatBannedRights(flags: [.banSendReactions], untilDate: Int32.max)
        return TelegramChannel(id: interaction.peerId, accessHash: nil, title: "Boost permission test", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: mode == "personal" ? ban : nil, defaultBannedRights: ban, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    func setState(_ mode: String, required: Int32? = 2, applied: Int32? = nil) {
        let peer = peer(mode)
        let cached = CachedChannelData().withUpdatedBoostsToUnrestrict(required).withUpdatedAppliedBoosts(applied ?? (mode == "restricted" ? 0 : 2))
        interaction.update(animated: false) { $0.updatedPeer { _ in peer }.updatedMainPeer(peer).withUpdatedCachedData(cached) }
    }

    func installRow() {
        let peer = peer(mode)
        setState(mode)
        let message = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1782388800, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: peer, text: "This member has enough boosts to bypass the default reaction restriction.", attributes: [], media: [], peers: SimpleDictionary([peer.id: peer]), associatedMessages: .init(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        let entry = ChatHistoryEntry.MessageEntry(message, message.index, true, .bubble, .Full(rank: nil, rankType: .none, header: .normal), nil, .init())
        row = ChatRowItem.item(NSMakeSize(820, 410), from: entry, interaction: interaction, theme: theme) as? ChatRowItem
        _ = row.makeSize(820, oldWidth: 0)
        _ = table.addItem(item: GeneralRowItem(NSMakeSize(820, 410), height: 100, stableId: "spacer", backgroundColor: .clear))
        _ = table.addItem(item: row)
        validateModels()
        record("initial")
    }

    func update(_ mode: String) {
        self.mode = mode
        setState(mode)
        status.stringValue = mode == "restricted" ? "Member · 0/2 boosts · default reaction ban" : mode == "boosted" ? "Member · 2/2 boosts · default reaction ban" : "Member · 2/2 boosts · PERSONAL reaction ban"
        record("rights_changed")
    }

    func validateModels() {
        var checks: [[String: Any]] = []
        func check(_ name: String, _ expected: Bool) {
            checks.append(["name": name, "expected": expected, "actual": row.canReact, "pass": row.canReact == expected])
        }
        setState("restricted"); check("default ban without boosts", false)
        setState("boosted"); check("sufficient boosts bypass default ban", true)
        setState("boosted", applied: 1); check("insufficient boosts do not bypass default ban", false)
        setState("boosted", required: 0); check("zero threshold does not bypass defaults", false)
        setState("boosted", required: nil); check("absent threshold does not bypass defaults", false)
        setState("boosted", applied: 3); check("extra boosts bypass default ban", true)
        setState("personal"); check("boosts do not bypass a personal ban", false)
        setState("boosted"); check("restoring live permission ignores stale message peer", true)
        interaction.update(animated: false) { $0.withUpdatedCachedData(nil) }
        check("missing cached data does not bypass defaults", false)
        if let data = try? JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: boostReactionEvidenceRoot.appendingPathComponent("models.json"), options: .atomic)
        }
        setState(mode)
    }

    func record(_ event: String, hasPicker: Bool? = nil) {
        var check: [String: Any] = ["event": event, "mode": mode, "canReact": row?.canReact ?? false, "messagePeerRestricted": true, "time": Date().timeIntervalSince1970]
        if let hasPicker { check["hasPickerWindow"] = hasPicker }
        report.append(check)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) { try? data.write(to: boostReactionEvidenceRoot.appendingPathComponent("observations.json"), options: .atomic) }
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

func codexInstallBoostReactionEvidence(source: ChatInteraction, parent: NSView) {
    guard !parent.subviews.contains(where: { $0 is BoostReactionEvidenceButton }) else { return }
    let button = BoostReactionEvidenceButton(frame: NSMakeRect(20, 130, 230, 30))
    button.title = "Reaction permission validation"
    button.bezelStyle = .rounded
    button.target = button
    button.action = #selector(BoostReactionEvidenceButton.run)
    button.invoke = {
        boostReactionEvidence = BoostReactionEvidence(source: source)
    }
    parent.addSubview(button)
}

