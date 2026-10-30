import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import ChatHistoryModel

private var pickerLifetimeEvidence: PickerLifetimeEvidence?

private final class PickerLifetimeButton: NSButton {
    var invoke: (() -> Void)?
    @objc func run() { invoke?() }
}

private final class PickerLifetimeEvidence {
    let interaction: ChatInteraction
    let button: NSButton
    let request = MetaDisposable()
    var picker: Window?
    var row: ChatRowItem?
    weak var retiredRow: ChatRowItem?
    var checks: [[String: Any]] = []

    init(source: ChatInteraction, button: NSButton) {
        self.interaction = ChatInteraction(chatLocation: .peer(PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(123456))), context: source.interactionContext)
        self.button = button
    }

    func peer(restricted: Bool) -> TelegramChannel {
        return TelegramChannel(id: interaction.peerId, accessHash: nil, title: "Reaction lifetime test", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: restricted ? TelegramChatBannedRights(flags: [.banSendReactions], untilDate: Int32.max) : nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    func rights(_ restricted: Bool) {
        let peer = peer(restricted: restricted)
        interaction.update(animated: false) { $0.updatedPeer { _ in peer }.updatedMainPeer(peer).withUpdatedCachedData(CachedChannelData()).withUpdatedAllowedReactions(.all) }
    }

    func run() {
        rights(false)
        let peer = peer(restricted: false)
        let message = Message(stableId: 5, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 5), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1782388800, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: peer, text: "Local reaction picker lifetime model", attributes: [], media: [], peers: SimpleDictionary([peer.id: peer]), associatedMessages: .init(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        let entry = ChatHistoryEntry.MessageEntry(message, message.index, true, .bubble, .Full(rank: nil, rankType: .none, header: .normal), nil, .init())
        row = ChatRowItem.item(NSMakeSize(800, 400), from: entry, interaction: interaction, theme: theme) as? ChatRowItem
        retiredRow = row
        request.set((row!.menuAdditionView |> take(1) |> deliverOnMainQueue).start(next: { [weak self] picker in
            guard let self else { return }
            self.picker = picker
            self.row = nil
            DispatchQueue.main.async {
                self.request.set(nil)
                DispatchQueue.main.async {
                    self.checks.append(["name": "production picker created without boosts", "pass": self.picker != nil])
                    self.checks.append(["name": "callbacks do not retain retired row", "pass": self.retiredRow == nil])
                    self.rights(true)
                    self.rights(false)
                    self.picker = nil
                    DispatchQueue.main.async {
                        self.checks.append(["name": "closing production picker releases retired row", "pass": self.retiredRow == nil])
                        let passed = self.checks.filter { $0["pass"] as? Bool == true }.count
                        self.button.title = "Picker lifetime: \(passed)/\(self.checks.count) passed"
                        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TELEGRAM_PICKER_EVIDENCE"] ?? NSTemporaryDirectory()).appendingPathComponent("picker-lifetime.json")
                        if let data = try? JSONSerialization.data(withJSONObject: self.checks, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: output, options: .atomic) }
                    }
                }
            }
        }))
    }
}

func codexInstallPickerLifetimeEvidence(source: ChatInteraction, parent: NSView) {
    guard source.mode == .history else { return }
    let button = PickerLifetimeButton(frame: NSMakeRect(20, 170, 260, 30))
    button.title = "Check reaction picker lifetime"
    button.bezelStyle = .rounded
    button.target = button
    button.action = #selector(PickerLifetimeButton.run)
    button.invoke = { [weak button] in
        guard let button else { return }
        pickerLifetimeEvidence = PickerLifetimeEvidence(source: source, button: button)
        pickerLifetimeEvidence?.run()
    }
    parent.addSubview(button)
}
