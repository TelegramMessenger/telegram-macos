import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import ChatHistoryModel
import TelegramTheme
import HTMLBubbles

enum ChatHTMLDocumentRows {
    static func item(_ initialSize: NSSize, interaction: ChatInteraction, entry: ChatHistoryEntry, message: Message, theme: TelegramPresentationTheme, fallback: () -> TableRowItem) -> TableRowItem {
        guard let file = HTMLDocumentBubbles.document(in: message) else {
            return fallback()
        }
        let context = interaction.interactionContext
        let mediaBox = context.account.postbox.mediaBox
        switch HTMLDocumentStore.shared.status(mediaBox: mediaBox, message: message, file: file) {
        case let .ready(state):
            return ChatHTMLRowItem(initialSize, interaction, context, entry, theme: theme, document: state)
        case .failed:
            return fallback()
        case let .loading(key):
            let item: TableRowItem
            if let previous = HTMLDocumentStore.shared.previousState(mediaBox: mediaBox, messageId: message.id) {
                item = ChatHTMLRowItem(initialSize, interaction, context, entry, theme: theme, document: previous)
            } else {
                item = ChatHTMLDocumentSkeletonItem(initialSize, interaction, context, entry, theme: theme)
            }
            HTMLDocumentStore.shared.whenResolved(key) { [weak item] in
                if let item = item as? ChatRowItem {
                    replace(item, attempts: 20)
                }
            }
            return item
        }
    }

    private static func replace(_ item: ChatRowItem, attempts: Int) {
        guard let table = item.table, item.index != -1 else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak item] in
                    if let item = item {
                        replace(item, attempts: attempts - 1)
                    }
                }
            }
            return
        }
        let updated = ChatRowItem.item(table.frame.size, from: item.entry, interaction: item.chatInteraction, theme: item.presentation)
        _ = updated.makeSize(table.frame.width, oldWidth: 0)
        table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(item.index, updated)], animated: false, state: .saveVisible(.upper, false)))
    }
}

final class ChatHTMLDocumentSkeletonItem: ChatRowItem {
    let style = HTMLDocumentBubbles.style

    var isCard: Bool {
        return style == .card
    }

    var isBare: Bool {
        return style == .bare
    }

    override var hasBubble: Bool {
        get {
            return !isCard && !isBare && super.hasBubble
        }
        set {
            super.hasBubble = newValue
        }
    }

    override var min_block_width: CGFloat {
        return HTMLDocumentBubbles.bubbleWidth
    }

    override var additionalLineForDateInBubbleState: CGFloat? {
        return isCard || isBare ? nil : super.additionalLineForDateInBubbleState
    }

    override var rightSize: NSSize {
        return isBare && isBubbled ? .zero : super.rightSize
    }

    override func makeContentSize(_ width: CGFloat) -> NSSize {
        return NSMakeSize(max(min(width, HTMLDocumentBubbles.bubbleWidth), 40), HTMLDocumentBubbles.skeletonHeight)
    }

    override func viewClass() -> AnyClass {
        return ChatHTMLDocumentSkeletonView.self
    }
}

private final class ChatHTMLDocumentSkeletonView: ChatRowView {
    private let card = View(frame: .zero)
    private let placeholder = View(frame: .zero)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        addSubview(card)
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = 14
        addSubview(placeholder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? ChatHTMLDocumentSkeletonItem else {
            return
        }
        layoutSkeleton(item)
        if item.isCard {
            card.isHidden = false
            card.backgroundColor = item.presentation.chat.bubbleBackgroundColor(true, true)
            card.layer?.borderWidth = 1
            card.layer?.borderColor = (item.presentation.colors.isDark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.10)).cgColor
        } else {
            card.isHidden = true
        }
        placeholder.layer?.backgroundColor = item.presentation.colors.grayText.withAlphaComponent(0.12).cgColor
        if placeholder.layer?.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.45
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            placeholder.layer?.add(pulse, forKey: "pulse")
        }
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        if let item = item as? ChatHTMLDocumentSkeletonItem {
            layoutSkeleton(item)
        }
    }

    private func layoutSkeleton(_ item: ChatHTMLDocumentSkeletonItem) {
        let bounds = NSMakeRect(0, 0, item.contentSize.width, item.contentSize.height)
        card.frame = bounds
        placeholder.frame = item.isCard ? bounds.insetBy(dx: 14, dy: 12) : bounds
    }
}
