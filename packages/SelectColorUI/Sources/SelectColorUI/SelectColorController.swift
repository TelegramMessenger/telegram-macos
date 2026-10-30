import Cocoa
import TGUIKit
import UniqueGiftBackground
import SwiftSignalKit
import TelegramCore
import Postbox
import InAppSettings
import ColorPalette
import ThemeSettings
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import AvatarUI
import LocalAnimations
import ChatHistoryModel
import PremiumStatusUI
import StarsUI
import WallpaperUI
import SettingsUI
import SceneEffects
import InlineStickerLayer


private final class CollectionRowItem : GeneralRowItem {
    
    struct Item : Comparable, Identifiable {
        let value: SelectColorState.Collection
        let index: Int
        let selected: Bool
        
        var stableId: AnyHashable {
            return value.stableId
        }
        static func < (lhs: Item, rhs: Item) -> Bool {
            return lhs.index < rhs.index
        }
        
        func makeItem(_ size: NSSize, arguments: Arguments) -> TableRowItem {
            return FilterChipRowItem(size, stableId: stableId, context: arguments.context, text: self.text, selected: self.selected, select: { arguments.collection(self.value) })
        }
        
        var text: NSAttributedString {
            let attr = NSMutableAttributedString()
            switch self.value {
            case .all:
                attr.append(
                    string: strings().selectColorMyGifts,
                    color: selected ? theme.colors.darkGrayText : theme.colors.listGrayText,
                    font: .normal(.text)
                )
            case let .collection(value):
                attr.append(
                    string: "\(clown_space)\(value.title ?? "")",
                    color: selected ? theme.colors.darkGrayText : theme.colors.listGrayText,
                    font: .normal(.text)
                )
                attr.insertEmbedded(.embeddedAnimated(value.file, playPolicy: .framesCount(1)), for: clown)
            }
            return attr
        }
    }
    
    fileprivate let items: [Item]
    fileprivate let selected: Int64?
    fileprivate let context: (any AccountContextProtocol)?
    fileprivate let arguments: Arguments?
    fileprivate let _stableId: AnyHashable
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, filters: [SelectColorState.Collection], selected: Int64?, arguments: Arguments) {
        var items: [Item] = []
        for (i, filter) in filters.enumerated() {
            items.append(.init(value: filter, index: i, selected: filter.stableId == selected))
        }
        self.items = items
        self.context = context
        self.selected = selected
        self.arguments = arguments
        self._stableId = stableId
        super.init(initialSize, viewType: .firstItem)
    }
    
    override var hasBorder: Bool {
        return false
    }
    
    override var stableId: AnyHashable {
        return _stableId
    }
    
    override var height: CGFloat {
        return 50
    }
    
    override func viewClass() -> AnyClass {
        return CollectionFilterRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonFilter
    }

    override var accessibilityValue: String? {
        return items.first(where: { $0.selected })?.text.string.replacingOccurrences(of: clown, with: "").trimmingCharacters(in: .whitespaces)
    }
}

private final class CollectionFilterRowView : GeneralContainableRowView, TableViewDelegate {
    
    private var ignoreNextAnimation: Bool = false

    
    func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {
        if let item = item as? FilterChipRowItem {
            item.select()
        }
    }
    
    func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        return true
    }
    
    func isSelectable(row: Int, item: TableRowItem) -> Bool {
        return true
    }
    
    private let tableView = HorizontalTableView(frame: .zero)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(tableView)
        tableView.getBackgroundColor = {
            .clear
        }
        
        
        tableView.delegate = self
        
        tableView.layer?.masksToBounds = false
        tableView.documentView?.layer?.masksToBounds = false
        tableView.clipView.layer?.masksToBounds = false
        
        layout()

    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var items: [CollectionRowItem.Item] = []
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? CollectionRowItem else {
            return
        }
        
        let animated = animated && !ignoreNextAnimation

        
        _ = item.context
        let items = item.items
        let arguments = item.arguments
        
        guard let arguments else {
            return
        }
        
        applyMergedRows(tableView, current: &self.items, items: items, animated: animated, makeItem: { item in
            return item.makeItem(bounds.size, arguments: arguments)
        })
        
        layout()
                
    }
    
    override func layout() {
        super.layout()
        if tableView.listHeight < bounds.width - 40 {
            tableView.contentInsets = NSEdgeInsets(bottom: 0)
            tableView.frame = focus(NSMakeSize(tableView.listHeight, 40))
        } else {
            tableView.contentInsets = NSEdgeInsets(bottom: 40)
            tableView.frame = focus(NSMakeSize(bounds.width - 40, 40))
        }
    }
}




private class GroupInfoRowItem : GeneralRowItem {
    fileprivate let text: TextViewLayout
    init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, action:@escaping()->Void) {
        self.text = .init(.initialize(string: strings().selectColorGroupBlockInfo, color: theme.colors.text, font: .normal(.text)).detectBold(with: .medium(.text)))
        super.init(initialSize, stableId: stableId, viewType: viewType, action: action)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        text.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right - viewType.innerInset.left - 30)
        return true
    }
    
    override var height: CGFloat {
        return text.layoutSize.height + viewType.innerInset.top + viewType.innerInset.bottom
    }
    
    override func viewClass() -> AnyClass {
        return GroupInfoRowView.self
    }

    override var accessibilityLabel: String? {
        return text.attributedString.string
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}

private final class GroupInfoRowView: GeneralContainableRowView {
    private let textView = TextView()
    private let imageView = ImageView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        containerView.scaleOnClick = true
        imageView.isAccessibilityDecorative = true
        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)
    }
    
    override func layout() {
        super.layout()
        guard let item = item as? GroupInfoRowItem else {
            return
        }
        self.imageView.centerY(x: item.viewType.innerInset.left)
        self.textView.centerY(x: self.imageView.frame.maxX + item.viewType.innerInset.left)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GroupInfoRowItem else {
            return
        }
        self.imageView.image = TelegramThemeHooks.shared.image(.iconGroupBlockBoost).precomposed(theme.colors.accent)
        self.imageView.sizeToFit()
        textView.update(item.text)
    }
}

private class ProfilePreviewRowItem : GeneralRowItem {
    fileprivate let theme: TelegramPresentationTheme
    fileprivate let peer: Peer
    fileprivate let nameColor: PeerColor?
    fileprivate let backgroundEmojiId: Int64?
    fileprivate let context: any AccountContextProtocol
    fileprivate let nameLayout: TextViewLayout
    fileprivate let statusLayout: TextViewLayout
    fileprivate let getColor:(PeerColor)->PeerNameColors.Colors
    init(_ initialSize: NSSize, stableId: AnyHashable, peer: Peer, subscribers: Int?, isGroup: Bool, nameColor: PeerColor?, backgroundEmojiId: Int64?, context: any AccountContextProtocol, theme: TelegramPresentationTheme, viewType: GeneralViewType, getColor:@escaping(PeerColor)->PeerNameColors.Colors) {
        self.theme = theme
        self.peer = peer
        self.getColor = getColor
        self.nameColor = nameColor
        self.backgroundEmojiId = backgroundEmojiId
        self.context = context
        let textColor: NSColor
        let grayText: NSColor
        if let nameColor = nameColor {
            textColor = getColor(nameColor).main.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
            grayText = textColor.withAlphaComponent(0.4)
        } else {
            textColor = theme.colors.text
            grayText = theme.colors.listGrayText
        }

        
        let status: String
        if let subscribers = subscribers {
            if isGroup {
                status = strings().peerStatusMemberOther(subscribers)
            } else {
                status = strings().peerStatusSubscribersOther(subscribers)
            }
        } else {
            status = strings().peerStatusRecently
        }
        
        self.nameLayout = .init(.initialize(string: peer.displayTitle, color: textColor, font: .medium(18)), maximumNumberOfLines: 1)
        self.statusLayout = .init(.initialize(string: status, color: grayText, font: .normal(15)))
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    var accentColor: NSColor {
        if let nameColor = nameColor?.nameColor {
            let textColor = context.peerNameColors.getProfile(nameColor).main.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
            return textColor
        } else {
            return theme.colors.accent
        }
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        
        nameLayout.measure(width: blockWidth - 60)
        statusLayout.measure(width: blockWidth - 60)

        return true
    }
    
    override func viewClass() -> AnyClass {
        return ProfilePreviewRowView.self
    }

    override var accessibilityLabel: String? {
        return nameLayout.attributedString.string
    }

    override var accessibilityValue: String? {
        return statusLayout.attributedString.string
    }
    
    
    override var hasBorder: Bool {
        return false
    }
    override var height: CGFloat {
        return 240
    }
}

private final class ProfilePreviewRowView : GeneralContainableRowView {
    private let avatar = AvatarControl(font: .avatar(18))
    private let nameView = TextView()
    private let statusView = TextView()
    private var statusControl: PremiumStatusControl?
    private var emojiSpawn: PeerInfoSpawnEmojiView?
    private let backgroundView = PeerInfoBackgroundView(frame: .zero)
    private var uniqueBackground: UniqueGiftBackgroundView?
    private var uniqueBackgroundContent: UniqueGiftBackgroundContent?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(avatar)
        addSubview(nameView)
        addSubview(statusView)
        
        
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
        statusView.userInteractionEnabled = false
        statusView.isSelectable = false
        
        avatar.setFrameSize(NSMakeSize(120, 120))
        avatar.layer?.cornerRadius = avatar.frame.height / 2
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? ProfilePreviewRowItem else {
            return
        }
        avatar.setPeer(account: item.context.account, peer: item.peer)
        
        
        
        nameView.update(item.nameLayout)
        statusView.update(item.statusLayout)
        
        let control = PremiumStatusControl.control(item.peer, account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, left: false, isSelected: false, isBig: true, playTwice: true, color: item.accentColor, cached: self.statusControl, animated: animated, autoupdate: false)
        if let control = control {
            self.statusControl = control
            self.addSubview(control)
        } else if let view = self.statusControl {
            performSubviewRemoval(view, animated: animated)
            self.statusControl = nil
        }
        
        if let nameColor = item.nameColor {
            backgroundView.gradient = [item.getColor(nameColor).main, item.getColor(nameColor).secondary ?? item.getColor(nameColor).main]
        } else {
            backgroundView.gradient = [NSColor(0xffffff, 0)]
        }
        
        if animated {
            backgroundView.layer?.animateBackground()
        }
        
        
        let uniqueContent = item.peer.emojiStatus.flatMap(UniqueGiftBackgroundContent.init(emojiStatus:))
        if let uniqueContent {
            if self.uniqueBackground == nil {
                let current = UniqueGiftBackgroundView(frame: containerView.bounds)
                addSubview(current, positioned: .above, relativeTo: backgroundView)
                self.uniqueBackground = current
            }
            self.uniqueBackgroundContent = uniqueContent
        } else if let view = self.uniqueBackground {
            performSubviewRemoval(view, animated: animated)
            self.uniqueBackground = nil
            self.uniqueBackgroundContent = nil
        }
        backgroundView.isHidden = uniqueContent != nil

        if uniqueContent == nil, let emoji = item.backgroundEmojiId {
            let current: PeerInfoSpawnEmojiView
            if let view = self.emojiSpawn {
                current = view
            } else {
                var rect = focus(NSMakeSize(180, 180))
                rect.origin.y = 0
                current = PeerInfoSpawnEmojiView(frame: rect)
                self.emojiSpawn = current
                addSubview(current, positioned: .above, relativeTo: backgroundView)
            }
            let color: NSColor
            if let nameColor = item.nameColor {
                let main = item.getColor(nameColor).main
                color = main.blended(withFraction: 0.1, of: .black) ?? NSColor.black.withAlphaComponent(0.15)
            } else {
                color = theme.colors.text.withAlphaComponent(0.3)
            }
            
            SettingsHooks.shared.setPeerInfoSpawnEmoji(current, emoji, color, item.context, animated)
        } else if let view = self.emojiSpawn {
            performSubviewRemoval(view, animated: animated)
            self.emojiSpawn = nil
        }
        
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        
        backgroundView.frame = containerView.bounds
        avatar.centerX(y: 30)
        nameView.centerX(y: avatar.frame.maxY + 20)
        statusView.centerX(y: nameView.frame.maxY + 4)
        emojiSpawn?.centerX(y: 30)
        if let uniqueBackground, let content = uniqueBackgroundContent, let item = item as? ProfilePreviewRowItem {
            uniqueBackground.frame = containerView.bounds
            uniqueBackground.update(context: item.context, content: content, style: .profile(avatarCenter: NSMakePoint(containerView.bounds.width / 2, avatar.frame.midY), avatarSize: avatar.frame.width, defaultHeight: containerView.bounds.height, gradientCenter: NSMakePoint(0.5, 0.5)))
        }
        
        statusControl?.setFrameOrigin(NSMakePoint(nameView.frame.maxX, nameView.frame.minY))
    }
}

private class PreviewRowItem: GeneralRowItem {

    fileprivate let theme: TelegramPresentationTheme
    fileprivate let items:[TableRowItem]
    fileprivate let getColor:(PeerColor)->PeerNameColors.Colors
    init(_ initialSize: NSSize, stableId: AnyHashable, peer: Peer, nameColor: PeerColor?, backgroundEmojiId: Int64?, emojiStatus: PeerEmojiStatus?, context: any AccountContextProtocol, theme: TelegramPresentationTheme, viewType: GeneralViewType, getColor:@escaping(PeerColor)->PeerNameColors.Colors) {
        self.theme = theme.withUpdatedBackgroundSize(WallpaperDimensions.aspectFilled(NSMakeSize(200, 200)))
        self.getColor = getColor
        let peerId = PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(0))
        
        let chatInteraction = SettingsHooks.shared.makeSelectColorPreviewContext(context, .peer(peerId), true, true, true)
        
        let previewPeer: Peer?
        if let peer = peer as? TelegramUser {
            previewPeer = TelegramUser(id: peerId, accessHash: peer.accessHash, firstName: peer.firstName, lastName: peer.lastName, username: peer.username, phone: peer.phone, photo: peer.photo, botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: emojiStatus, usernames: [], storiesHidden: nil, nameColor: nameColor, backgroundEmojiId: backgroundEmojiId, profileColor: nameColor?.nameColor, profileBackgroundEmojiId: backgroundEmojiId, subscriberCount: nil, verificationIconFileId: nil)
        } else if let peer = peer as? TelegramChannel {
            previewPeer = TelegramChannel(id: peerId, accessHash: peer.accessHash, title: peer.title, username: peer.username, photo: peer.profileImageRepresentations, creationDate: peer.creationDate, version: peer.version, participationStatus: peer.participationStatus, info: peer.info, flags: peer.flags, restrictionInfo: peer.restrictionInfo, adminRights: peer.adminRights, bannedRights: peer.bannedRights, defaultBannedRights: peer.defaultBannedRights, usernames: peer.usernames, storiesHidden: peer.storiesHidden, nameColor: nameColor?.nameColor, backgroundEmojiId: backgroundEmojiId, profileColor: nameColor?.nameColor, profileBackgroundEmojiId: backgroundEmojiId, emojiStatus: emojiStatus, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
        } else {
            previewPeer = nil
        }
      
           

        
                
        
        if let previewPeer = previewPeer {
            
            let firstMessage = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: previewPeer.id, namespace: 0, id: 0), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 18 + 60*60*18, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: previewPeer, text: strings().selectColorMessage1, attributes: [], media: [], peers:SimpleDictionary([previewPeer.id : previewPeer]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])

            
            let timestamp1: Int32 = 60 * 20 + 60 * 60 * 18
            
            let media = TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: 0), content: TelegramMediaWebpageContent.Loaded(TelegramMediaWebpageLoadedContent(url: "", displayUrl: "", hash: 0, type: "photo", websiteName: appName, title: strings().selectColorMessage2PreviewTitle, text: strings().selectColorMessage2PreviewText, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil, attributes: [], instantPage: nil)))

            let secondMessage = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: previewPeer.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: timestamp1, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: previewPeer, text: strings().selectColorMessage2, attributes: [ReplyMessageAttribute(messageId: firstMessage.id, threadMessageId: nil, quote: nil, isQuote: false, innerSubject: nil)], media: [media], peers:SimpleDictionary([previewPeer.id : previewPeer]) , associatedMessages: SimpleDictionary([firstMessage.id : firstMessage]), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
            
            let secondEntry: ChatHistoryEntry = .MessageEntry(secondMessage, MessageIndex(secondMessage), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
            
            let item2 = SettingsHooks.shared.makeChatPreviewItem(initialSize, chatInteraction, secondEntry, theme)
            self.items = [item2]
        } else {
            self.items = []
        }
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
        
        chatInteraction.getGradientOffsetRect = { [weak self] in
            guard let `self` = self else {
                return .zero
            }
            return CGRect(origin: NSMakePoint(0, self.height), size: NSMakeSize(self.width, self.height))
        }
        
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        let itemWidth = self.blockWidth - self.viewType.innerInset.left - self.viewType.innerInset.right
        for item in items {
            _ = item.makeSize(itemWidth, oldWidth: 0)
        }
        return true
    }
    
    override var instantlyResize: Bool {
        return true
    }
    
    override var height: CGFloat {
        var height: CGFloat = self.viewType.innerInset.top + self.viewType.innerInset.bottom
        
        for item in self.items {
            height += item.height
        }
        return height
    }
    
    override func viewClass() -> AnyClass {
        return PreviewRowView.self
    }

    override var accessibilityLabel: String? {
        let labels = items.compactMap { $0.accessibilityLabel }
        return labels.isEmpty ? strings().selectColorMessage2 : labels.joined(separator: "\n")
    }
    
}

private final class PreviewRowView : GeneralContainableRowView {
    private let backgroundView: BackgroundView
    private let itemsView = View()
    required init(frame frameRect: NSRect) {
        backgroundView = BackgroundView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height))
        backgroundView.useSharedAnimationPhase = false
        super.init(frame: frameRect)
        addSubview(self.backgroundView)
        self.backgroundView.addSubview(itemsView)
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PreviewRowItem else {
            return
        }
        
        self.layout()
        
        
    
        var y: CGFloat = item.viewType.innerInset.top
        for (i, item) in item.items.enumerated() {
            let vz = item.viewClass() as! TableRowView.Type
            let view: TableRowView
            if self.itemsView.subviews.count > i {
                view = self.itemsView.subviews[i] as! TableRowView
            } else {
                view = vz.init(frame:NSMakeRect(0, y, self.backgroundView.frame.width, item.height))
            }
            view.set(item: item, animated: false)
            if view.superview == nil {
                self.itemsView.addSubview(view)
            }
            
            if let view = view as? AppearanceChatPreviewRowView {
                view.updateBackground(animated: false, item: view.item, rotated: true)
            }
            
            y += item.height
        }
        
        
    }
    
    override func updateColors() {
        guard let item = item as? PreviewRowItem else {
            return
        }
        self.containerView.backgroundColor = background
        self.backgroundView.backgroundMode = item.theme.bubbled ? item.theme.backgroundMode : .color(color: item.theme.colors.chatBackground)
        self.borderView.backgroundColor = theme.colors.border.cgColor
        self.backgroundColor = item.viewType.rowBackground
    }
    
    override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    override func layout() {
        super.layout()
        self.backgroundView.frame = self.containerView.bounds
        self.borderView.frame = NSMakeRect(0, self.containerView.frame.height - .borderSize, self.containerView.frame.width, .borderSize)
        itemsView.frame = backgroundView.bounds
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



public func generateRingImage(nameColor: PeerNameColors.Colors) -> CGImage {
    return generateImage(CGSize(width: 35, height: 35), rotatedContext: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        context.setStrokeColor(nameColor.main.cgColor)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: bounds.insetBy(dx: 1.0, dy: 1.0))
    })!
}

public func generateFillImage(nameColor: PeerNameColors.Colors) -> CGImage {
    return generateImage(CGSize(width: 35, height: 35), rotatedContext: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)
        
        let circleBounds = bounds
        context.addEllipse(in: circleBounds)
        context.clip()
        
        if let secondColor = nameColor.secondary {
            context.setFillColor(secondColor.cgColor)
            context.fill(circleBounds)
            
            context.move(to: .zero)
            context.addLine(to: CGPoint(x: size.width, y: 0.0))
            context.addLine(to: CGPoint(x: 0.0, y: size.height))
            context.closePath()
            context.setFillColor(nameColor.main.cgColor)
            context.fillPath()
            
            if let thirdColor = nameColor.tertiary {
                context.setFillColor(thirdColor.cgColor)
                context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
                context.rotate(by: .pi / 4.0)
                
                let path = CGMutablePath()
                path.addRoundedRect(in: CGRect(origin: CGPoint(x: -8, y: -8), size: CGSize(width: 16, height: 16)), cornerWidth: 4, cornerHeight: 4)
                context.addPath(path)
                context.fillPath()
            }
        } else {
            context.setFillColor(nameColor.main.cgColor)
            context.fill(circleBounds)
        }
    })!
}




private enum PeerNameColorEntryId: Hashable {
    case color(Int32)
    case collectible(UInt32)
}

private enum PeerNameColorEntry: Comparable, Identifiable {
    case color(Int, PeerColor, Bool)
    
    var stableId: PeerNameColorEntryId {
        switch self {
            case let .color(_, color, _):
            switch color {
            case let .preset(value):
                return .color(value.rawValue)
            case let .collectible(value):
                return .collectible(value.accentColor)
            }
                
        }
    }
    
    static func ==(lhs: PeerNameColorEntry, rhs: PeerNameColorEntry) -> Bool {
        switch lhs {
            case let .color(lhsIndex, lhsAccentColor, lhsSelected):
                if case let .color(rhsIndex, rhsAccentColor, rhsSelected) = rhs, lhsIndex == rhsIndex, lhsAccentColor == rhsAccentColor, lhsSelected == rhsSelected {
                    return true
                } else {
                    return false
                }
        }
    }
    
    static func <(lhs: PeerNameColorEntry, rhs: PeerNameColorEntry) -> Bool {
        switch lhs {
            case let .color(lhsIndex, _, _):
                switch rhs {
                    case let .color(rhsIndex, _, _):
                        return lhsIndex < rhsIndex
            }
        }
    }
    
    func item(initialSize: NSSize, context: any AccountContextProtocol, getColor:@escaping(PeerColor)->PeerNameColors.Colors, action: @escaping (PeerColor) -> Void) -> PeerNameColorIconItem {
        switch self {
            case let .color(_, color, selected):
            return PeerNameColorIconItem(initialSize: initialSize, stableId: self.stableId, context: context, color: color, selected: selected, action: action, getColor: getColor)
        }
    }
}



private class PeerNameColorIconItem: TableRowItem {
    let color: PeerColor
    let selected: Bool
    let action: (PeerColor) -> Void
    let context: any AccountContextProtocol
    let getColor:(PeerColor)->PeerNameColors.Colors
    public init(initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, color: PeerColor, selected: Bool, action: @escaping (PeerColor) -> Void, getColor:@escaping(PeerColor)->PeerNameColors.Colors) {
        self.color = color
        self.selected = selected
        self.action = action
        self.context = context
        self.getColor = getColor
        super.init(initialSize, stableId: stableId)
    }
    
    override var height: CGFloat {
        return 55
    }
    override var width: CGFloat {
        return 55
    }
    
    override func viewClass() -> AnyClass {
        return PeerNameColorIconView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonColor
    }
}

private final class PeerNameColorIconView : ColorSwatchView {

    private var item: TableRowItem?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        control.set(handler: { [weak self] _ in
            guard let item = self?.item as? PeerNameColorIconItem else {
                return
            }
            item.action(item.color)
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(item: TableRowItem, animated: Bool) {

        self.item = item

        guard let item = item as? PeerNameColorIconItem else {
            return
        }

        let colors = item.getColor(item.color)

        update(fill: generateFillImage(nameColor: colors), ring: generateRingImage(nameColor: colors), selected: item.selected, animated: animated)
        control.setAccessibilityLabel(strings().voiceOverCommonColor)
        control.setAccessibilityValue(item.selected ? strings().voiceOverCommonSelected : nil)
    }
}

private final class PeerNamesRowItem : GeneralRowItem {
    fileprivate let colors: [PeerColor]
    fileprivate let selected: PeerColor?
    fileprivate let selectAction:(PeerColor)->Void
    fileprivate let context: any AccountContextProtocol
    fileprivate let getColor:(PeerColor)->PeerNameColors.Colors

    let itemSize: NSSize = NSMakeSize(45, 45)
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, colors: [PeerColor], selected: PeerColor?, viewType: GeneralViewType, action: @escaping(PeerColor)->Void, getColor:@escaping(PeerColor)->PeerNameColors.Colors) {
        self.colors = colors
        self.context = context
        self.selected = selected
        self.selectAction = action
        self.getColor = getColor
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    var frames:[CGRect] = []
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        frames.removeAll()
        
        let perRow = Int(floor((blockWidth - 10) / itemSize.width))

        var point: CGPoint = NSMakePoint(5, 5)
        for i in 1 ... colors.count {
            frames.append(CGRect(origin: point, size: itemSize))
            if i % perRow == 0 {
                point.x = 5
                point.y += itemSize.height
            } else {
                point.x += itemSize.width
            }
        }
        
        return true
    }
    
    override var instantlyResize: Bool {
        return true
    }
    
    override var height: CGFloat {
        _ = floor((blockWidth - 10) / itemSize.width)
        
        return frames[frames.count - 1].maxY + 5
    }
    
    override func viewClass() -> AnyClass {
        return PeerNamesRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonColor
    }
}

private final class PeerNamesRowView : GeneralContainableRowView {
    let tableView: View
    required init(frame frameRect: NSRect) {
        tableView = View(frame: frameRect)
        super.init(frame: frameRect)
        addSubview(tableView)
    }
    
    override func layout() {
        super.layout()
        tableView.frame = containerView.bounds
        guard let item = item as? PeerNamesRowItem else {
            return
        }
        
        for (i, subview) in tableView.subviews.enumerated() {
            subview.frame = item.frames[i]
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var previous: [PeerNameColorEntry] = []
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PeerNamesRowItem else {
            return
        }
        
        var entries: [PeerNameColorEntry] = []
        
        var index: Int = 0
        for color in item.colors {
            entries.append(.color(index, color, color == item.selected))
            index += 1
        }

        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: previous, rightList: entries)
        
        //let animation: NSTableView.AnimationOptions = animated ? .effectFade : .none
        
        for rdx in deleteIndices.reversed() {
            tableView.subviews[rdx].removeFromSuperview()
        }
        
        
        for (idx, entry, _) in indicesAndItems {
            let view = PeerNameColorIconView(frame: item.itemSize.bounds)
            let item = entry.item(initialSize: bounds.size, context: item.context, getColor: item.getColor, action: item.selectAction)
            view.set(item: item, animated: animated)
            tableView.subviews.insert(view, at: idx)
        }
        for (idx, entry, _) in updateIndices {
            let item = item
            let updatedItem = entry.item(initialSize: bounds.size, context: item.context, getColor: item.getColor, action: item.selectAction)
            (tableView.subviews[idx] as? PeerNameColorIconView)?.set(item: updatedItem, animated: animated)
        }

        self.previous = entries
        
        needsLayout = true
        
    }
    
}


private final class Arguments {
    let context: any AccountContextProtocol
    let premiumConfiguration: any SelectColorPremiumConfiguration
    let source: SelectColorSource
    let destination: SelectColorControllerDestination
    let toggleColor:(PeerColor, SelectColorType) -> Void
    let showEmojiPanel:(SelectColorType)->Void
    let showEmojiPack:()->Void
    let removeIcon:(SelectColorType)->Void
    let resetColor:(SelectColorType)->Void
    let getColor:(PeerColor, SelectColorType)->PeerNameColors.Colors
    let showEmojiStatus:()->Void
    let showChannelWallpaper:()->Void
    let boost:()->Void
    let wearCollectible:(StarGift)->Void
    let collection:(SelectColorState.Collection)->Void
    let buyAndApply:(StarGift.UniqueGift, Bool)->Void
    init(context: any AccountContextProtocol, source: SelectColorSource, destination: SelectColorControllerDestination, toggleColor:@escaping(PeerColor, SelectColorType) -> Void, showEmojiPanel:@escaping(SelectColorType)->Void, showEmojiPack:@escaping()->Void, removeIcon:@escaping(SelectColorType)->Void, resetColor:@escaping(SelectColorType)->Void, getColor:@escaping(PeerColor, SelectColorType)->PeerNameColors.Colors, showEmojiStatus:@escaping()->Void, showChannelWallpaper:@escaping()->Void, boost:@escaping()->Void, wearCollectible:@escaping(StarGift)->Void, collection:@escaping(SelectColorState.Collection)->Void, buyAndApply: @escaping(StarGift.UniqueGift, Bool)->Void) {
        self.context = context
        self.source = source
        self.destination = destination
        self.premiumConfiguration = SettingsHooks.shared.selectColorPremiumConfiguration(context)
        self.toggleColor = toggleColor
        self.showEmojiPanel = showEmojiPanel
        self.showEmojiPack = showEmojiPack
        self.removeIcon = removeIcon
        self.resetColor = resetColor
        self.getColor = getColor
        self.showEmojiStatus = showEmojiStatus
        self.showChannelWallpaper = showChannelWallpaper
        self.boost = boost
        self.wearCollectible = wearCollectible
        self.collection = collection
        self.buyAndApply = buyAndApply
    }
}

struct SelectColorState : Equatable {
    
    enum Collection : Equatable {
        case all
        case collection(value: StarGift.Gift)
        
        var gift: StarGift.Gift? {
            switch self {
            case let .collection(value):
                return value
            case .all:
                return nil
            }
        }
        
        var stableId: Int64? {
            switch self {
            case .all:
                return nil
            case let .collection(value):
                return value.id
            }
        }
    }
    
    var boostLevel: Int32 {
        if let status = status {
            return Int32(status.level)
        } else if let channel = peer._asPeer() as? TelegramChannel {
            return channel.approximateBoostLevel ?? 0
        } else {
            return 0
        }
    }
    
    var wearable: [StarGift.UniqueGift] = []
    
    func filterWearable(_ dest: SelectColorControllerDestination) -> [StarGift.UniqueGift] {
        var values: [StarGift.UniqueGift] = []
        
        if let id = selectedCollection.stableId {
            if let state = resaleState[id] {
                return state.gifts.compactMap {
                    $0.unique
                }
            } else {
                return []
            }
        }
        
        if dest == .all || dest == .profile {
            values = wearable
        } else {
            values = wearable.filter {
                $0.peerColor != nil
            }
        }
        return values.filter { value in
            if selectedCollection != .all {
                return value.giftId == selectedCollection.stableId
            } else {
                return true
            }
        }
    }
    
    var collections: [Collection] = []
    var selectedCollection: Collection = .all
    
    var resaleState:[Int64 : ResaleGiftsContext.State] = [:]
    
    func getCollections(dest: SelectColorControllerDestination) -> [Collection] {
        var collections: [Collection] = [.all]
        
        for collection in self.collections {
            switch collection {
            case let .collection(value: value):
                if dest == .name, value.flags.contains(.peerColorAvailable) {
                    collections.append(collection)
                } else if dest == .profile || dest == .all {
                    collections.append(collection)

                }
            default:
                continue
            }
        }
        
//        for value in wearable {
//            let id = value.giftId
//            if let first = self.collections.first(where: { $0.gift?.id == id}), !keys.contains(id) {
//                collections.append(first)
//                keys.insert(id)
//            }
//        }
        return collections
    }

    var peer: EnginePeer
    
    var status: ChannelBoostStatus?
    var myStatus: MyBoostStatus?

    var selected: PeerColor?
    var selected_profile: PeerColor?
    
    
    var selected_Gift: StarGift.UniqueGift?

    var backgroundEmojiId: Int64? = nil
    var backgroundEmojiId_profile: Int64? = nil
    
    var emojiStatus:PeerEmojiStatus?
    var emojiStatusGift: StarGift.UniqueGift?

    struct GiftSelectionRestore : Equatable {
        var selected: PeerColor?
        var selected_profile: PeerColor?
        var backgroundEmojiId_profile: Int64?
        var emojiStatus: PeerEmojiStatus?
    }
    var giftSelectionRestore: GiftSelectionRestore?
    
    mutating func rememberSelectionBeforeGift() {
        if selected_Gift == nil, emojiStatusGift == nil {
            giftSelectionRestore = .init(selected: selected, selected_profile: selected_profile, backgroundEmojiId_profile: backgroundEmojiId_profile, emojiStatus: emojiStatus)
        }
    }
    
    mutating func deselectGift() {
        guard selected_Gift != nil || emojiStatusGift != nil else {
            return
        }
        if let restore = giftSelectionRestore {
            selected = restore.selected
            selected_profile = restore.selected_profile
            backgroundEmojiId_profile = restore.backgroundEmojiId_profile
            emojiStatus = restore.emojiStatus
        }
        selected_Gift = nil
        emojiStatusGift = nil
        giftSelectionRestore = nil
    }
    
    var saving: Bool = false
    var subscribers: Int?
    var icon: CGImage?
    var icon_profile: CGImage?
    var icon_emojiStatus: CGImage?
    
    var theme: TelegramPresentationTheme
    
    var wallpaper: TelegramWallpaper?
    var actualWallpaper: TelegramWallpaper?
    
    var emojiPack: StickerPackCollectionInfo?
    var actualEmojiPack: StickerPackCollectionInfo?
    
    
    var icon_emojiPack: CGImage?
    
    var myBalance: StarsAmount?
    var myTonBalance: StarsAmount?


    func isSame(to peer: Peer) -> Bool {
        if peer.profileColor != selected_profile?.nameColor {
            return false
        }
        if peer.nameColor != selected {
            return false
        }
        if peer.backgroundEmojiId != backgroundEmojiId {
            return false
        }
        if peer.profileBackgroundEmojiId != backgroundEmojiId_profile {
            return false
        }
        if peer.emojiStatus != emojiStatus {
            return false
        }
        if wallpaper != actualWallpaper {
            return false
        }
        if emojiPack != actualEmojiPack {
            return false
        }
        return true
    }

}

private let _id_colors = InputDataIdentifier("_id_colors")
private let _id_preview = InputDataIdentifier("_id_preview")
private let _id_emojies = InputDataIdentifier("_id_emojies")
private let _id_icon = InputDataIdentifier("_id_icon")
private let _id_icon_remove = InputDataIdentifier("_id_icon_remove")
private let _id_reset_color = InputDataIdentifier("_id_reset_color")
private let _id_collections = InputDataIdentifier("_id_collections")


private let _id_colors_profile = InputDataIdentifier("_id_colors_profile")
private let _id_preview_profile = InputDataIdentifier("_id_preview_profile")
private let _id_emojies_profile = InputDataIdentifier("_id_emojies_profile")
private let _id_icon_profile = InputDataIdentifier("_id_icon_profile")
private let _id_icon_remove_profile = InputDataIdentifier("_id_icon_remove_profile")
private let _id_reset_color_profile = InputDataIdentifier("_id_reset_color_profile")
private let _id_reset_color_name = InputDataIdentifier("_id_reset_color_name")

private let _id_emoji_status = InputDataIdentifier("_id_emoji_status")
private let _id_emoji_pack = InputDataIdentifier("_id_emoji_pack")

private let _id_group_block = InputDataIdentifier("_id_group_block")

private let _id_wallpaper = InputDataIdentifier("_id_wallpaper")
private let _id_loading = InputDataIdentifier("_id_loading")

private func _id_stars_gifts(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_stars_gifts_\(index)")
}


private func entries(_ state: SelectColorState, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    
    var afterNameImage_NameIcon: CGImage? = nil
    var afterNameImage_ProfileIcon: CGImage? = nil
    var afterNameImage_WallpaperIcon: CGImage? = nil
    var afterNameImage_EmojiPack: CGImage? = nil

    switch arguments.source {
    case .channel:
        if state.boostLevel < arguments.premiumConfiguration.minChannelNameIconLevel {
            afterNameImage_NameIcon = SettingsHooks.shared.boostLevelBadgeImage(strings().boostBadgeLevel(Int(arguments.premiumConfiguration.minChannelNameIconLevel)))
        }
        if state.boostLevel < arguments.premiumConfiguration.minChannelProfileIconLevel {
            afterNameImage_ProfileIcon = SettingsHooks.shared.boostLevelBadgeImage(strings().boostBadgeLevel(Int(arguments.premiumConfiguration.minChannelProfileIconLevel)))
        }
        if state.boostLevel < arguments.premiumConfiguration.minChannelWallpaperLevel {
            afterNameImage_WallpaperIcon = SettingsHooks.shared.boostLevelBadgeImage(strings().boostBadgeLevel(Int(arguments.premiumConfiguration.minChannelWallpaperLevel)))
        }
    case .group:
        if state.boostLevel < arguments.premiumConfiguration.minGroupProfileIconLevel {
            afterNameImage_ProfileIcon = SettingsHooks.shared.boostLevelBadgeImage(strings().boostBadgeLevel(Int(arguments.premiumConfiguration.minGroupProfileIconLevel)))
        }
        if state.boostLevel < arguments.premiumConfiguration.minGroupWallpaperLevel {
            afterNameImage_WallpaperIcon = SettingsHooks.shared.boostLevelBadgeImage(strings().boostBadgeLevel(Int(arguments.premiumConfiguration.minGroupWallpaperLevel)))
        }
        if state.boostLevel < arguments.premiumConfiguration.minGroupEmojiPackLevel {
            afterNameImage_EmojiPack = SettingsHooks.shared.boostLevelBadgeImage(strings().boostBadgeLevel(Int(arguments.premiumConfiguration.minGroupEmojiPackLevel)))
        }
    default:
        break
    }
    
    if arguments.destination == .all || arguments.destination == .name {
        switch arguments.source {
        case .channel, .account:
            
            
            
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_preview, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return PreviewRowItem(initialSize, stableId: stableId, peer: arguments.source.peer, nameColor: state.selected, backgroundEmojiId: state.backgroundEmojiId, emojiStatus: state.emojiStatus, context: arguments.context, theme: state.theme, viewType: .firstItem, getColor: { name in
                    arguments.getColor(name, .name)
                })
            }))
            
            var colors: [PeerColor] = []
            for index in arguments.context.peerNameColors.displayOrder {
                colors.append(.preset(PeerNameColor(rawValue: index)))
            }
            
            let colorsViewType: GeneralViewType
            colorsViewType = .innerItem
          
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_colors, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return PeerNamesRowItem(initialSize, stableId: stableId, context: arguments.context, colors: colors, selected: state.selected, viewType: colorsViewType, action: { color in
                    arguments.toggleColor(color, .name)
                }, getColor: {
                    arguments.getColor($0, .name)
                })
            }))
            
            
            let type: GeneralInteractedType
            if let icon = state.icon {
                type = .imageContext(icon, "")
            } else {
                type = .context(strings().selectColorIconSelectOff)
            }
            
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_icon, data: .init(name: strings().selectColorIconSelectReplies, color: theme.colors.text, icon: nil, type: type, viewType: .lastItem, enabled: true, action: {
                arguments.showEmojiPanel(.name)
            }, afterNameImage: afterNameImage_NameIcon)))
            
            let iconInfo: String
            switch arguments.source {
            case .account:
                iconInfo = strings().selectColorIconInfoUser
            case .channel, .group:
                iconInfo = strings().selectColorIconInfoChannel
            }
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(iconInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
            
            if state.selected != state.peer.nameColor {
                entries.append(.sectionId(sectionId, type: .normal))
                sectionId += 1
                
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_reset_color_name, data: .init(name: strings().selectColorResetColorName, color: theme.colors.accent, viewType: .singleItem, action: {
                    arguments.resetColor(.name)
                })))
            }
        default:
            break
        }
    }
    
    
    switch arguments.source {
    case .channel:
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        let title: String
        let info: String
        switch arguments.source {
        case .channel:
            title = strings().selectColorChannelWallpaper
            info = strings().selectColorChannelWallpaperInfo
        case .group:
            title = strings().selectColorGroupWallpaper
            info = strings().selectColorGroupWallpaperInfo
        default:
            fatalError()
        }
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_wallpaper, data: .init(name: title, color: theme.colors.text, icon: nil, type: .next, viewType: .singleItem, enabled: true, action: {
            arguments.showChannelWallpaper()
        }, afterNameImage: afterNameImage_WallpaperIcon)))
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(info), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    default:
        break
    }
    
    
    //!!!!!!PROFILE!!!!!!!
    
    if arguments.destination == .all || arguments.destination == .profile {
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().selectColorProfilePageTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        let previewViewType: GeneralViewType
        let isGroup: Bool
        switch arguments.source {
        case .group:
            previewViewType = .singleItem
            isGroup = true
        default:
            previewViewType = .firstItem
            isGroup = false
        }
        

        var peer: EnginePeer = state.peer
        switch peer {
        case let .channel(channel):
            peer = .channel(channel.withUpdatedEmojiStatus(state.emojiStatus))
        case let .user(user):
            peer = .user(user.withUpdatedEmojiStatus(state.emojiStatus))
        default:
            break
        }
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_preview_profile, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return ProfilePreviewRowItem(initialSize, stableId: stableId, peer: peer._asPeer(), subscribers: state.subscribers, isGroup: isGroup, nameColor: state.selected_profile, backgroundEmojiId: state.backgroundEmojiId_profile, context: arguments.context, theme: theme, viewType: previewViewType, getColor: {
                arguments.getColor($0, .profile)
            })
        }))
        
        switch arguments.source {
        case .group:
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_group_block, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                return GroupInfoRowItem(initialSize, stableId: stableId, viewType: .singleItem, action: {
                    arguments.boost()
                })
            }))
            
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        default:
            break
        }
        
        
        var colors: [PeerColor] = []
        for index in arguments.context.peerNameColors.profileDisplayOrder {
            colors.append(.preset(PeerNameColor(rawValue: index)))
        }
        
       
        let colorsViewType: GeneralViewType
        switch arguments.source {
        case .group:
            colorsViewType = .firstItem
        default:
            colorsViewType = .innerItem
        }
        
        var selected_profile = state.selected_profile
        if case .starGift = state.emojiStatus?.content {
            selected_profile = nil
        }

      
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_colors_profile, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return PeerNamesRowItem(initialSize, stableId: stableId, context: arguments.context, colors: colors, selected: selected_profile, viewType: colorsViewType, action: { color in
                arguments.toggleColor(color, .profile)
            }, getColor: {
                arguments.getColor($0, .profile)
            })
        }))
        
        let type: GeneralInteractedType
        if let icon = state.icon_profile {
            type = .imageContext(icon, "")
        } else {
            type = .context(strings().selectColorIconSelectOff)
        }
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_icon_profile, data: .init(name: strings().selectColorIconSelectProfile, color: theme.colors.text, icon: nil, type: type, viewType: .lastItem, enabled: true, action: {
            arguments.showEmojiPanel(.profile)
        }, afterNameImage: afterNameImage_ProfileIcon)))
        
        let iconInfo: String
        switch arguments.source {
        case .account:
            iconInfo = strings().selectColorIconInfoUserProfile
        case .channel:
            iconInfo = strings().selectColorIconInfoChannelProfile
        case .group:
            iconInfo = strings().selectColorIconInfoGroupProfile
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(iconInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        
        if state.selected_profile != nil {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_reset_color_profile, data: .init(name: strings().selectColorResetColorProfile, color: theme.colors.accent, viewType: .singleItem, action: {
                arguments.resetColor(.profile)
            })))
        }
//        
    }
//    

    switch arguments.source {
    case .group:
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        let title: String = strings().selectColorEmojiPackGroup
        let emojiPackInfo: String = strings().selectColorEmojiPackInfoGroup
        
        let statusType: GeneralInteractedType
        if let icon = state.icon_emojiPack {
            statusType = .imageContext(icon, "")
        } else {
            statusType = .nextContext("")
        }
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_emoji_pack, data: .init(name: title, color: theme.colors.text, icon: nil, type: statusType, viewType: .singleItem, enabled: true, action: {
            arguments.showEmojiPack()
        }, afterNameImage: afterNameImage_EmojiPack)))
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(emojiPackInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    default:
        break
    }
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    switch arguments.source {
    case .group:
        
        let title: String
        let info: String
        switch arguments.source {
        case .channel:
            title = strings().selectColorChannelWallpaper
            info = strings().selectColorChannelWallpaperInfo
        case .group:
            title = strings().selectColorGroupWallpaper
            info = strings().selectColorGroupWallpaperInfo
        default:
            fatalError()
        }
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_wallpaper, data: .init(name: title, color: theme.colors.text, icon: nil, type: .next, viewType: .singleItem, enabled: true, action: {
            arguments.showChannelWallpaper()
        }, afterNameImage: afterNameImage_WallpaperIcon)))
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(info), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    default:
        break
    }
    
    switch arguments.source {
    case .account:
        let wearable = state.filterWearable(arguments.destination)
        if !wearable.isEmpty || arguments.destination != .all {
           
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().selectColorUseGiftTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            
           
            
            let selected: StarGift.UniqueGift?
            if arguments.destination == .all || arguments.destination == .profile {
                selected = wearable.first(where: { $0.file?.fileId.id == state.emojiStatus?.fileId })
            } else {
                selected = wearable.first(where: { $0.id == state.selected?.collectibleId })
            }
            
            let chunks = wearable.chunks(3)
            
            struct Tuple : Equatable {
                let chunk: [StarGift.UniqueGift]
                let viewType: GeneralViewType
                let selected: StarGift.UniqueGift?
            }
            
            var tupls: [Tuple] = []
            
            for (_, chunk) in chunks.enumerated() {
                tupls.append(.init(chunk: chunk, viewType: .innerItem, selected: selected))
            }
            
           
            let collections = state.getCollections(dest: arguments.destination)
            
            if !collections.isEmpty {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collections, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                    return CollectionRowItem(initialSize, stableId: stableId, context: arguments.context, filters: collections, selected: state.selectedCollection.stableId, arguments: arguments)
                }))
            } else {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_s_\(-1)"), equatable: nil, comparable: nil, item: { initialSize, stableId in
                    return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .firstItem, drawCustomSeparator: false, backgroundColor: theme.colors.background, containable: true)
                }))
            }
            
            if !collections.isEmpty, let stableId = state.selectedCollection.stableId, tupls.isEmpty, let resaleState = state.resaleState[stableId] {
                if case .loading = resaleState.dataState {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                        return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .innerItem, height: 135, hasBorder: false)
                    }))
                } else {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                        return SettingsHooks.shared.makeStickerHeaderItem(
                            initialSize,
                            stableId,
                            arguments.context,
                            LocalAnimatedSticker.duck_empty,
                            .initialize(string: strings().selectColorEmpty, color: theme.colors.grayText, font: .normal(.text)),
                            .innerItem,
                            false
                        )
                    }))
                }
               
            }
            
            
            
            for (i, tuple) in tupls.enumerated() {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_stars_gifts(i), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                    return GiftOptionsRowItem(initialSize, stableId: stableId, context: arguments.context, options: tuple.chunk.map { .initialize($0, context: arguments.context, showNumber: state.selectedCollection != .all) }, perRowCount: 3, fitToSize: false, viewType: tuple.viewType, callback: { option, _ in
                        if let gift = option.gift {
                            arguments.wearCollectible(gift)
                        }
                    }, selected: selected.flatMap { .unique($0) })
                }))
                if i != tupls.count - 1 {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_s_\(i)"), equatable: nil, comparable: nil, item: { initialSize, stableId in
                        return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .innerItem, drawCustomSeparator: false, backgroundColor: theme.colors.background, containable: true)
                    }))
                }
            }
            
            if state.selectedCollection == .all, tupls.isEmpty {
                
                let text: String
                switch arguments.destination {
                case .all:
                    text = strings().selectColorNoGifts
                case .profile:
                    text = strings().selectColorNoGiftsProfile
                case .name:
                    text = strings().selectColorNoGiftsName
                }
                
                let attr = parseMarkdownIntoAttributedString(
                    text,
                    attributes: MarkdownAttributes(
                        body: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.grayText),
                        bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.colors.grayText),
                        link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accentIcon),
                        linkAttribute: { contents in
                            return (NSAttributedString.Key.link.rawValue, contents)
                        }
                    )
                )
                
                let interactions = TextViewInteractions(processURL: { _ in
                    if collections.count > 1 {
                        arguments.collection(collections[1])
                    }
                })
                
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
                    return SettingsHooks.shared.makeInteractiveStickerHeaderItem(initialSize, stableId, arguments.context, LocalAnimatedSticker.duck_empty, attr, .innerItem, false, interactions)
                }))
            } 
            
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_s_\(1000)"), equatable: nil, comparable: nil, item: { initialSize, stableId in
                return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .lastItem, drawCustomSeparator: false, backgroundColor: theme.colors.background, containable: true)
            }))
            
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().selectColorUseGiftInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1


            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1
            
        }
        
    default:
        break
    }
    
    return entries
}

enum SelectColorType {
    case name
    case profile
}

enum SelectColorSource {
    case account(Peer)
    case channel(Peer)
    case group(Peer)
    
    var isGroup: Bool {
        switch self {
        case .group:
            return true
        default:
            return false
        }
    }

    var peerId: PeerId {
        switch self {
        case .account(let peer):
            return peer.id
        case .channel(let peer):
            return peer.id
        case .group(let peer):
            return peer.id
        }
    }
    var peer: Peer {
        switch self {
        case .account(let peer):
            return peer
        case .channel(let peer):
            return peer
        case .group(let peer):
            return peer
        }
    }
    
    func nameColor(_ type: SelectColorType) -> PeerColor? {
        switch type {
        case .name:
            return peer.nameColor
        case .profile:
            return peer.profileColor.flatMap { .preset($0) }

        }
    }
    func backgroundIcon(_ type: SelectColorType) -> Int64? {
        switch type {
        case .name:
            return peer.backgroundEmojiId
        case .profile:
            return peer.profileBackgroundEmojiId
        }
    }
}

public final class SelectColorCallback {
    public var getState:(()->(PeerColor?, Int64?))? = nil
    public var validate:(()->Void)? = nil
    public init() {
        
    }
}

public enum SelectColorControllerDestination {
    case all
    case profile
    case name
}

public class SelectColorControllerCollectData {
    
    var connector:(()->SelectColorState)?
    var _buyAndApply:((StarGift.UniqueGift)->Void)?
    
    func getData() -> SelectColorState? {
        return connector?()
    }
    func buyAndApply(_ gift: StarGift.UniqueGift) {
        _buyAndApply?(gift)
    }
}

public func SelectColorController(context: any AccountContextProtocol, peer: Peer, callback: SelectColorCallback? = nil, destination: SelectColorControllerDestination = .profile, dataCollector: SelectColorControllerCollectData? = nil) -> InputDataController {

    let source: SelectColorSource
    if peer.isGroup || peer.isSupergroup {
        source = .group(peer)
    } else if peer.isChannel {
        source = .channel(peer)
    } else {
        source = .account(peer)
    }
    
    let actionsDisposable = DisposableSet()
    let saveAction = SelectColorSaveAction()
    let resaleContextDisposable = MetaDisposable()
    actionsDisposable.add(resaleContextDisposable)

    let initialState = SelectColorState(peer: .init(source.peer), selected: source.nameColor(.name), selected_profile: source.nameColor(.profile), backgroundEmojiId: source.backgroundIcon(.name), backgroundEmojiId_profile: source.backgroundIcon(.profile), emojiStatus: source.peer.emojiStatus, theme: theme.withUpdatedEmoticonThemes(context.emoticonThemes))
    
    
    
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SelectColorState) -> SelectColorState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let giftsSignal = context.engine.payments.cachedStarGifts()
    let peerSignal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peer.id))
    
    actionsDisposable.add(combineLatest(peerSignal, giftsSignal).start(next: { peer, gifts in
        updateState { current in
            var current = current
            if let peer {
                current.peer = peer
                current.emojiStatus = peer.emojiStatus
                switch peer.emojiStatus?.content {
                case let .starGift(_, _, _, _, _, innerColor, _, _, _):
                    current.selected_profile = .preset(.other(innerColor))
                default:
                    current.selected_profile = peer.profileColor.flatMap { .preset($0) }
                }
                current.selected = peer.nameColor
                current.backgroundEmojiId_profile = peer.profileBackgroundEmojiId
                current.backgroundEmojiId = peer.backgroundEmojiId
                
                current.collections = gifts?.compactMap { $0.generic }.filter { $0.title != nil }.map { .collection(value: $0) } ?? []
            }
            return current
        }
    }))
    
    let isGroup: Bool
    switch source {
    case .group:
        isGroup = true
    default:
        isGroup = false
    }
    
    callback?.getState = {
        return stateValue.with { ($0.selected, $0.backgroundEmojiId) }
    }
    

    let peerId: PeerId = source.peerId
    
    let getColor:(PeerColor, SelectColorType)->PeerNameColors.Colors = { color ,type in
        switch type {
        case .name:
            return color.nameColors(context)
        case .profile:
            return color.profileColors(context)
        }
    }
    func backgroundIcon(_ type: SelectColorType) -> Int64? {
        switch type {
        case .name:
            return stateValue.with { $0.backgroundEmojiId }
        case .profile:
            return stateValue.with { $0.backgroundEmojiId_profile }
        }
    }
    
    let cachedData = getCachedDataView(peerId: peerId, postbox: context.account.postbox)
    |> map { $0 as? CachedChannelData }
    |> map { $0 }
    |> take(1)
    
    
    actionsDisposable.add(cachedData.start(next: { cachedData in
        let wallpaper = cachedData?.wallpaper
        let emojiPack = cachedData?.emojiPack

        updateState { current in
            var current = current
            if let wallpaper = wallpaper {
                current.theme = current.theme.withUpdatedWallpaper(.init(wallpaper: .init(wallpaper), associated: nil))
            } else {
                current.theme = current.theme.withUpdatedWallpaper(theme.wallpaper)
            }
            current.wallpaper = wallpaper
            current.actualWallpaper = wallpaper
            current.emojiPack = emojiPack
            current.actualEmojiPack = emojiPack
            return current
        }
    }))
    
    var nameGiftsContext: ProfileGiftsContext? = nil
    var profileGiftsContext: ProfileGiftsContext? = nil
    
    let getCurrentContext:() -> ProfileGiftsContext? = {
        return nameGiftsContext ?? profileGiftsContext
    }
    
    switch source {
    case let .account(peer):
        
        if destination == .all || destination == .profile {
            if destination == .profile, peer.id == context.peerId, !peer.isPremium {
                profileGiftsContext = nil
            } else {
                profileGiftsContext = ProfileGiftsContext(account: context.account, peerId: context.account.peerId, filter:[.All, .unique], limit: 100)
            }
        } else if destination == .name  {
            nameGiftsContext = ProfileGiftsContext(account: context.account, peerId: context.account.peerId, filter: .peerColor, limit: 100)
        }
        
        let giftsContext = nameGiftsContext ?? profileGiftsContext
        

        if let giftsContext {
            actionsDisposable.add(giftsContext.state.start(next: { state in
                updateState { current in
                    var current = current
                    current.wearable = state.filteredGifts.compactMap { $0.gift.unique }
                    return current
                }
            }))
        }
    default:
        break
    }
    
    var backgroundEmojiId: Int64? = nil
    var color: PeerColor?
    var layer: InlineStickerItemLayer?
    actionsDisposable.add(statePromise.get().start(next: { state in
        if state.backgroundEmojiId != backgroundEmojiId || state.selected != color {
            DispatchQueue.main.async {
                if let emojiId = state.backgroundEmojiId {
                    
                    let color: NSColor
                    if let selected = state.selected {
                        color = getColor(selected, .name).main
                    } else {
                        color = theme.colors.text
                    }
                    layer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: emojiId, file: nil, emoji: clown), size: NSMakeSize(25, 25), playPolicy: .framesCount(1), textColor: color)
                    layer?.isPlayable = true
                    
                    layer?.contentDidUpdate = { image in
                        updateState { current in
                            var current = current
                            current.icon = image
                            return current
                        }
                    }

                } else {
                    layer = nil
                    updateState { current in
                        var current = current
                        current.icon = nil
                        return current
                    }
                }
            }
        }
        backgroundEmojiId = state.backgroundEmojiId
        color = state.selected
    }))
    
    var backgroundEmojiId_profile: Int64? = nil
    var color_profile: PeerColor?
    var layer_profile: InlineStickerItemLayer?
    actionsDisposable.add(statePromise.get().start(next: { state in
        if state.backgroundEmojiId_profile != backgroundEmojiId_profile || state.selected_profile != color_profile {
            DispatchQueue.main.async {
                if let emojiId = state.backgroundEmojiId_profile {
                    
                    let color: NSColor
                    if let selected = state.selected_profile {
                        color = getColor(selected, .profile).main
                    } else {
                        color = theme.colors.text
                    }
                    layer_profile = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: emojiId, file: nil, emoji: clown), size: NSMakeSize(25, 25), playPolicy: .framesCount(1), textColor: color)
                    layer_profile?.isPlayable = true
                    
                    layer_profile?.contentDidUpdate = { image in
                        updateState { current in
                            var current = current
                            current.icon_profile = image
                            return current
                        }
                    }

                } else {
                    layer_profile = nil
                    updateState { current in
                        var current = current
                        current.icon_profile = nil
                        return current
                    }
                }
            }
        }
        backgroundEmojiId_profile = state.backgroundEmojiId_profile
        color_profile = state.selected_profile
    }))
    
    var emojiStatus: PeerEmojiStatus?
    var emoji_statusLayer: InlineStickerItemLayer?
    actionsDisposable.add(statePromise.get().start(next: { state in
        if state.emojiStatus != emojiStatus  {
            DispatchQueue.main.async {
                if let emojiId = state.emojiStatus?.fileId {
                    
                    emoji_statusLayer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: emojiId, file: nil, emoji: clown), size: NSMakeSize(25, 25), playPolicy: .framesCount(1), textColor: theme.colors.accent)
                    emoji_statusLayer?.isPlayable = true
                    
                    emoji_statusLayer?.contentDidUpdate = { image in
                        updateState { current in
                            var current = current
                            current.icon_emojiStatus = image
                            return current
                        }
                    }

                } else {
                    emoji_statusLayer = nil
                    updateState { current in
                        var current = current
                        current.icon_emojiStatus = nil
                        return current
                    }
                }
            }
        }
        emojiStatus = state.emojiStatus
    }))
    
    
    var emojiPack_Layer: InlineStickerItemLayer?
    
    let emojiPack: Signal<(StickerPackCollectionInfo, StickerPackItem)?, NoError> = statePromise.get() |> map { $0.emojiPack } |> distinctUntilChanged |> mapToSignal { info in
        if let info = info {
            return context.engine.stickers.loadedStickerPack(reference: StickerPackReference.id(id: info.id.id, accessHash: info.accessHash), forceActualized: false) |> mapToSignal { result in
                switch result {
                case let .result(info, items, _):
                    if let item = items.first {
                        return .single((info._parse(), item))
                    } else {
                        return .single(nil)
                    }
                default:
                    return .complete()
                }
            }
        } else {
            return .single(nil)
        }
    }
    
    actionsDisposable.add(emojiPack.start(next: { info in
        DispatchQueue.main.async {
            if let item = info?.1 {
                emojiPack_Layer = InlineStickerItemLayer(account: context.account, file: item.file._parse(), size: NSMakeSize(25, 25), playPolicy: .framesCount(1), textColor: theme.colors.accent)
                emojiPack_Layer?.isPlayable = true
                
                emojiPack_Layer?.contentDidUpdate = { image in
                    updateState { current in
                        var current = current
                        current.icon_emojiPack = image
                        return current
                    }
                }
            } else {
                emojiPack_Layer = nil
                updateState { current in
                    var current = current
                    current.icon_emojiPack = nil
                    return current
                }
            }
        }
    }))
    
    let subscribers = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.ParticipantCount(id: source.peerId))
    
    actionsDisposable.add(subscribers.start(next: { value in
        updateState { current in
            var current = current
            current.subscribers = value
            return current
        }
    }))

    let boostStatus = combineLatest(context.engine.peers.getChannelBoostStatus(peerId: peerId), context.engine.peers.getMyBoostStatus())
    
    actionsDisposable.add(boostStatus.startStandalone(next: { stats, myStatus in
        updateState { current in
            var current = current
            current.status = stats
            current.myStatus = myStatus
            return current
        }
    }))
    
    actionsDisposable.add(combineLatest(context.starsContext.state, context.tonContext.state).startStrict(next: { state, tonState in
        updateState { current in
            var current = current
            current.myBalance = state?.balance
            current.myTonBalance = tonState?.balance
            return current
        }
    }))
    
    dataCollector?.connector = {
        return stateValue.with { $0 }
    }
    
    
    var close:(()->Void)? = nil
    var getController:(()->InputDataController?)? = nil

    
    let buyResellGift:(StarGift.UniqueGift, EnginePeer, BotPaymentForm, BotPaymentForm, ResaleGiftsContext, Bool)->Void = { gift, peer, starsForm, tonForm, resaleContext, needClose in
        
        let state = stateValue.with { $0 }
        
       
        _ = gift.resell?.fullyFormatted ?? ""

        _ = gift.resell?.amount ?? .zero
        
        
        var buyForSelected: CurrencyAmount.Currency = gift.resellForTonOnly ? .ton : .stars
        var modifyData:((ModalAlertData)->Void)? = nil
        
        var getData:()->ModalAlertData = { .init(info: "") }
        
        getData = {
            
            let form = buyForSelected == .stars ? starsForm : tonForm
            
            let fullAmount = form.invoice.prices.first?.amount ?? 0
            
            let resellAmount = CurrencyAmount(amount: StarsAmount.init(value: fullAmount, nanos: 0), currency: buyForSelected)
            
            let resellStars = resellAmount.fullyFormatted
            
            let infoText: String
            if peer.id == context.peerId {
                infoText = strings().starNftGiftBuyConfirmSelf(gift.title, resellStars)
            } else {
                infoText = strings().starNftGiftBuyConfirm(gift.title, resellStars, peer._asPeer().displayTitle)
            }
            
            return ModalAlertData(title: strings().starNftGiftConfirmTitle, info: infoText, description: nil, ok: strings().starNftGiftConfirmOk(resellStars), options: [], mode: .confirm(text: strings().modalCancel, isThird: false), header: .init(id: "header", value: { initialSize, stableId, presentation in
                return TransferUniqueGiftHeaderItem(initialSize, stableId: stableId, gift: gift, toPeer: peer, context: context, transferType: .buy(onlyTon: gift.resellForTonOnly), buyForSelected: buyForSelected, callback: { updated in
                    buyForSelected = updated
                    modifyData?(getData())
                })
            }), footer: ModalAlertData.Footer.init(id: "footer", value: { initialSize, stableId, presentation, action in
                return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: getTransferAttributesRows(gift: gift), context: context)
            }))
        }
        
       
        
        showModalAlert(for: context.window, data: getData(), completion: { result in
            
            let myBalance: StarsAmount
            if buyForSelected == .stars {
                myBalance = state.myBalance ?? .init(value: 0, nanos: 0)
            } else {
                myBalance = state.myTonBalance ?? .init(value: 0, nanos: 0)
            }
            
            let form = buyForSelected == .stars ? starsForm : tonForm
                        
            let fullAmount = form.invoice.prices.first?.amount ?? 0
            let resellAmount = CurrencyAmount(amount: StarsAmount.init(value: fullAmount, nanos: 0), currency: buyForSelected).fullyFormatted

            if fullAmount > myBalance.value {
                if buyForSelected == .ton {
                    showModal(with: SettingsNavigationHooks.shared.makeAddTonBalanceController(context, fullAmount - myBalance.value), for: context.window)
                } else {
                    let sourceValue: Star_ListScreenSource =  .buy(suffix: nil, amount: fullAmount)
                    showModal(with: Star_ListScreen(context: context, source: sourceValue), for: context.window)
                }
            } else {
                _ = showModalProgress(signal: context.engine.payments.sendStarsPaymentForm(formId: form.id, source: .starGiftResale(slug: gift.slug, toPeerId: peerId, ton: buyForSelected == .ton, hideName: true, text: nil, entities: nil)), for: context.window).startStandalone(next: { result in
                    switch result {
                    case let .done(_, _, uniqueStarGift):
                        PlayConfetti(for: context.window, stars: true)
                        context.starsContext.load(force: true)
                        context.tonContext.load(force: true)
                        context.starsSubscriptionsContext.load(force: true)
                        resaleContext.removeStarGift(gift: .unique(gift))
                        getCurrentContext()?.insertStarGifts(gifts: uniqueStarGift.flatMap { [$0] } ?? [])
                        
                        updateState { current in
                            var current = current
                            current.selectedCollection = .all
                            current.selected_Gift = uniqueStarGift?.gift.unique
                            return current
                        }
                        
                        
                        let successText: String
                        if peer.id == context.peerId {
                            successText = strings().starNftGiftBuySuccessSelf(gift.title, resellAmount)
                        } else {
                            successText = strings().starNftGiftBuySuccess(gift.title, resellAmount, peer._asPeer().displayTitle)
                        }
                        showModalText(for: context.window, text: successText)
                        
                        if needClose {
                            close?()
                        }
                    default:
                        break
                    }
                }, error: { error in
                    let text: String
                    switch error {
                    case .alreadyPaid:
                        text = strings().checkoutErrorInvoiceAlreadyPaid
                    case .generic:
                        text = strings().unknownError
                    case .paymentFailed:
                        text = strings().checkoutErrorPaymentFailed
                    case .precheckoutFailed:
                        text = strings().checkoutErrorPrecheckoutFailed
                    case .starGiftOutOfStock:
                        text = strings().giftSoldOutError
                    case .disallowedStarGift:
                        text = strings().giftSendDisallowError
                    case .starGiftUserLimit:
                        text = strings().giftOptionsGiftBuyLimitReached
                    case let .serverProvided(value):
                        text = value
                    }
                    showModalText(for: context.window, text: text)
                })
            }
        }, takeNewData: { f in
            modifyData = f
        })

        
    }
    
    

    var getControl:((SelectColorType?)->Control?)? = nil
    

    var resaleContexts:[Int64: ResaleGiftsContext] = [:]
    
    

    let arguments = Arguments(context: context, source: source, destination: destination, toggleColor: { value, type in
        updateState { current in
            var current = current
            switch type {
            case .name:
                current.selected = value
                current.selected_Gift = nil
            case .profile:
                current.selected_profile = value
                if case .starGift = current.emojiStatus?.content {
                    current.emojiStatus = nil
                    current.emojiStatusGift = nil
                }
            }
            return current
        }
    }, showEmojiPanel: { type in
        
        let selectedBg: SelectColorEmojiSelectedItem? = backgroundIcon(type).flatMap {
            .init(source: .custom($0), type: .normal)
        }
        let nameColor: PeerColor? = stateValue.with { state in
            return type == .name ? state.selected : state.selected_profile
        }
        let colors: PeerNameColors.Colors? = nameColor != nil ? getColor(nameColor!, type) : nil
        let emojis = SettingsHooks.shared.makeEmojisController(context, .backgroundIcon, selectedBg != nil ? [selectedBg!] : [], colors?.main ?? theme.colors.text)
        emojis._frameRect = NSMakeRect(0, 0, 350, 300)
        
        let interactions = SettingsHooks.shared.makeEntertainmentInteractions(.emoji, peerId)

        interactions.selectColorSendAnimatedEmoji = { [weak emojis] sticker, _, _, _, fromRect in
            
            if sticker.file._parse().mimeType.hasPrefix("bundle") {
                updateState { current in
                    var current = current
                    switch type {
                    case .name:
                        current.backgroundEmojiId = nil
                    case .profile:
                        current.backgroundEmojiId_profile = nil
                    }
                    return current
                }
            } else {
                updateState { current in
                    var current = current
                    switch type {
                    case .name:
                        current.backgroundEmojiId = sticker.file.fileId.id
                    case .profile:
                        current.backgroundEmojiId_profile = sticker.file.fileId.id
                    }
                    return current
                }
            }
            emojis?.closePopover()
        }
        
        emojis.updateSelectColorEmojis(with: interactions, chatLocation: .peer(peerId), context: context)

        if let emojiControl = getControl?(type) {
            showPopover(for: emojiControl, with: emojis)
        }
    }, showEmojiPack: {
        context.bindings.rootNavigation().push(SettingsHooks.shared.makeGroupEmojiPackController(context, peerId, stateValue.with { $0.emojiPack }, { info in
            updateState { current in
                var current = current
                current.emojiPack = info
                return current
            }
        }))
    }, removeIcon: { type in
        updateState { current in
            var current = current
            switch type {
            case .name:
                current.backgroundEmojiId = nil
            case .profile:
                current.backgroundEmojiId_profile = nil
            }
            return current
        }
    }, resetColor: { type in
        updateState { current in
            var current = current
            switch type {
            case .name:
                current.selected = current.peer.nameColor
                current.backgroundEmojiId = nil
                current.selected_Gift = nil
            case .profile:
                current.selected_profile = nil
                current.backgroundEmojiId_profile = nil
                current.emojiStatusGift = nil
            }
            return current
        }
    }, getColor: getColor, showEmojiStatus: {
        let setStatus:(Control, TelegramUser)->Void = { control, peer in
            let callback:(TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?)->Void = { file, gift, timeout, fromRect in
                guard let selection = SelectColorStatusUpdate.selection(file: file, gift: gift, timeout: timeout, timestamp: context.timestamp) else { return }
                updateState { current in
                    var current = current
                    current.emojiStatus = selection.status
                    current.emojiStatusGift = selection.gift
                    return current
                }
            }
            if control.popover == nil {
                showPopover(for: control, with: SettingsHooks.shared.makePremiumStatusController(context, callback, peer), edge: .maxY, inset: NSMakePoint(-80, -35), static: true, animationMode: .reveal)
            }
        }
        if let control = getControl?(nil) {
            switch source {
            case let .account(peer):
                if let peer = peer as? TelegramUser {
                    setStatus(control, peer)
                }
            case .channel, .group:
                let selectedBg: SelectColorEmojiSelectedItem? = stateValue.with { $0.emojiStatus?.fileId }.flatMap {
                    .init(source: .custom($0), type: .normal)
                }
                let emojis = SettingsHooks.shared.makeEmojisController(context, .channelStatus, selectedBg != nil ? [selectedBg!] : [], nil)
                emojis._frameRect = NSMakeRect(0, 0, 350, 300)
                
                let interactions = SettingsHooks.shared.makeEntertainmentInteractions(.emoji, peerId)

                interactions.selectColorSendAnimatedEmoji = { [weak emojis] sticker, gift, _, timeout, fromRect in
                    guard let selection = SelectColorStatusUpdate.selection(file: sticker.file._parse(), gift: gift, timeout: timeout, timestamp: context.timestamp) else { return }
                    updateState { current in
                        var current = current
                        current.emojiStatus = selection.status
                        current.emojiStatusGift = selection.gift
                        return current
                    }
                    emojis?.closePopover()
                }
                
                emojis.updateSelectColorEmojis(with: interactions, chatLocation: .peer(peerId), context: context)
                showPopover(for: control, with: emojis)
            }
        }
    }, showChannelWallpaper: {
        let actual = stateValue.with { $0.actualWallpaper }
        let current = stateValue.with { $0.wallpaper }
        showModal(with: ChannelWallpapersController(context: context, peerId: peerId, isGroup: source.isGroup, boostLevel: stateValue.with { $0.boostLevel }, selected: (actual != current, current), callback: { value in
            
            updateState { current in
                var current = current
                if let value = value {
                    current.theme = current.theme.withUpdatedWallpaper(.init(wallpaper: .init(value), associated: nil))
                } else {
                    current.theme = current.theme.withUpdatedWallpaper(theme.wallpaper)
                }
                current.wallpaper = value
                return current
            }
            
        }), for: context.window)
    }, boost: {
        let status = stateValue.with { $0.status }
        let myBoost = stateValue.with { $0.myStatus }
        if let status = status {
            showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, source.peer, status, myBoost, .basic), for: context.window)
        }
    }, wearCollectible: { gift in
        if gift.unique != nil {
            switch destination {
            case .all, .profile:
                if let unique = gift.unique, let file = unique.file, let patternFile = unique.pattern {
                    loop: for attr in unique.attributes {
                        switch attr {
                        case let .backdrop(_, _, innerColor, outerColor, patternColor, textColor, _):
                            updateState { current in
                                var current = current
                                current.rememberSelectionBeforeGift()
                                current.emojiStatus = .init(content: .starGift(id: unique.id, fileId: file.fileId.id, title: unique.title, slug: unique.slug, patternFileId: patternFile.fileId.id, innerColor: innerColor, outerColor: outerColor, patternColor: patternColor, textColor: textColor), expirationDate: nil)
                                current.selected_profile = .preset(.other(outerColor))
                                current.backgroundEmojiId_profile = patternFile.fileId.id
                                current.emojiStatusGift = unique
                                return current
                            }
                            break loop
                        default:
                            break
                        }
                    }
                }
            case .name:
                if let unique = gift.unique, let color = unique.peerColor {
                    updateState { current in
                        var current = current
                        current.rememberSelectionBeforeGift()
                        current.selected = .collectible(color)
                        current.selected_Gift = unique
                        return current
                    }
                }
                
            }
        }
    }, collection: { value in
        updateState { current in
            var current = current
            if current.selectedCollection != value {
                current.deselectGift()
            }
            current.selectedCollection = value
            return current
        }
        if let stableId = value.stableId {
            let resaleContext = resaleContexts[stableId] ?? ResaleGiftsContext(account: context.account, giftId: stableId, forCrafting: false)
            resaleContexts[stableId] = resaleContext
            resaleContextDisposable.set(resaleContext.state.start(next: { state in
                updateState { current in
                    var current = current
                    current.resaleState[stableId] = state
                    return current
                }
            }))
        } else {
            resaleContextDisposable.set(nil)
        }
        
        _ = getController?()
        
    //    controller?.tableView.scroll(to: .top(id: InputDataEntryId.custom(_id_collections), innerId: nil, animated: true, focus: .init(focus: false), inset: -30))
        
    }, buyAndApply: { gift, needClose in
        
        let state = stateValue.with { $0 }
        
        guard let collectionId = state.selectedCollection.stableId else {
            return
        }
        
        if let _ = gift.resellStars(context), let resaleContext = resaleContexts[collectionId] {
            let signal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue
            
            
            let formAndMaybeValidatedInfo_Stars: Signal<BotPaymentForm?, BotPaymentFormRequestError>
            if gift.resellForTonOnly {
                formAndMaybeValidatedInfo_Stars = .single(nil)
            } else {
                formAndMaybeValidatedInfo_Stars = context.engine.payments.fetchBotPaymentForm(source: .starGiftResale(slug: gift.slug, toPeerId: peerId, ton: false, hideName: true, text: nil, entities: nil), themeParams: nil)
                |> map(Optional.init)
            }
            
            
            let formAndMaybeValidatedInfo_Ton = context.engine.payments.fetchBotPaymentForm(source: .starGiftResale(slug: gift.slug, toPeerId: peerId, ton: true, hideName: true, text: nil, entities: nil), themeParams: nil)

            _ = showModalProgress(signal: combineLatest(signal |> castError(BotPaymentFormRequestError.self), formAndMaybeValidatedInfo_Stars, formAndMaybeValidatedInfo_Ton), for: context.window).start(next: { peer, starsForm, tonForm in
                if let peer {
                    buyResellGift(gift, peer, starsForm ?? tonForm, tonForm, resaleContext, needClose)
                }
                
            })
        }
    })
    
    dataCollector?._buyAndApply = { gift in
        return arguments.buyAndApply(gift, false)
    }
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    

    let controller = InputDataController(dataSignal: signal, title: strings().telegramAppearanceViewController, removeAfterDisappear: false, hasDone: true, doneString: {
        return strings().selectColorApply
    })
    
    controller.willDisappear = { _ in saveAction.setActive(false) }
    controller.willAppear = { _ in saveAction.setActive(true) }
    controller.onDeinit = {
        saveAction.setActive(false)
        actionsDisposable.dispose()
    }
    
    getController = { [weak controller] in
        return controller
    }
    
        
    let invoke:()->Void = { [weak controller] in
        guard let controller, saveAction.isActive, !saveAction.isPending, controller.isLoaded(), let window = controller.view.window as? Window else { return }
        let state = stateValue.with { $0 }
        if case .account = source {
            guard state.peer.id == context.peerId, state.peer._asPeer() is TelegramUser else { return }
        }

        if case .peerId(peerId) = state.selected_Gift?.owner {
        } else if let unique = state.selected_Gift {
            arguments.buyAndApply(unique, true)
            return
        }
        
        let nameColor = state.selected ?? state.peer.nameColor ?? .preset(.blue)
        let backgroundEmojiId = state.backgroundEmojiId
        let profileColor = state.selected_profile
        let profileBackgroundEmojiId = state.backgroundEmojiId_profile
        let emojiStatus = state.emojiStatus
        let emojiStatusGift = state.emojiStatusGift
        
        let wallpaper = state.wallpaper
        let actualWallpaper = state.actualWallpaper
        
        let emojiPack = state.emojiPack
        let actualEmojiPack = state.actualEmojiPack

        
        let request:(@escaping()->Void)->Void = { f in
            
            var signals:[Signal<Never, SelectColorSaveError>] = []

            switch source {
            case .account:
                signals.append(context.engine.accountData.updateNameColorAndEmoji(nameColor: nameColor.getUpdate(backgroundEmojiId), profileColor: profileColor?.nameColor, profileBackgroundEmojiId: profileBackgroundEmojiId) |> ignoreValues |> mapError { _ in SelectColorSaveError.generic })
                
            case .channel, .group:
                signals.append(context.engine.peers.updatePeerNameColorAndEmoji(peerId: peerId, nameColor: nameColor.nameColor ?? .blue, backgroundEmojiId: backgroundEmojiId, profileColor: profileColor?.nameColor, profileBackgroundEmojiId: profileBackgroundEmojiId) |> ignoreValues |> mapError { _ in SelectColorSaveError.generic })
                
                if emojiPack != actualEmojiPack {
                    signals.append(context.engine.peers.updateGroupSpecificEmojiset(peerId: peerId, info: emojiPack) |> ignoreValues |> mapError { _ in SelectColorSaveError.generic })
                }
            }
            
            
            signals.append(SelectColorStatusUpdate.request(context: context, peer: state.peer, status: emojiStatus, gift: emojiStatusGift))
            if wallpaper != actualWallpaper {
                if let wallpaper = wallpaper {
                    switch wallpaper {
                    case let .file(file):
                        let rep: TelegramMediaImageRepresentation = .init(dimensions: file.file.dimensions ?? .init(CGSize(width: 1024, height: 1024)), resource: file.file.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
                        
                        context.account.pendingPeerMediaUploadManager.add(peerId: peerId, content: .wallpaper(wallpaper: .image([rep], file.settings), forBoth: false))
                    default:
                        signals.append(context.engine.themes.setChatWallpaper(peerId: peerId, wallpaper: wallpaper, forBoth: false) |> mapError { _ in SelectColorSaveError.generic })
                    }
                } else {
                    signals.append(context.engine.themes.setChatWallpaper(peerId: peerId, wallpaper: nil, forBoth: false) |> mapError { _ in SelectColorSaveError.generic })
                }
            }
            let clearSaving: () -> Void = {
                updateState { current in
                    var current = current
                    current.saving = false
                    return current
                }
            }
            saveAction.perform(signal: combineLatest(signals) |> ignoreValues, window: window, canPresent: { [weak controller, weak window] in
                guard let controller, let window else { return false }
                return controller.isLoaded() && controller.view.window === window
            }, started: {
                updateState { current in
                    var current = current
                    current.saving = true
                    return current
                }
            }, cancelled: clearSaving, failed: { [weak controller, weak window, weak saveAction] in
                clearSaving()
                if let controller, let window, saveAction?.isActive == true, controller.view.window === window {
                    showModalText(for: window, text: strings().unknownError)
                }
            }, completed: {
                close?()
                f()
            })
        }

        let peer = source.peer
        switch source {
        case .channel, .group:
            _ = peer.id
            
            let stats = stateValue.with { $0.status }
            let myStatus = stateValue.with { $0.myStatus }
            
            let nameColorLevel: Int32
            let nameIconLevel: Int32

            let profileColorLevel: Int32
            let profileIconLevel: Int32

            let emojiStatusLevel: Int32
            let emojiPackLevel: Int32

            let wallpaperLevel: Int32
            let customWallpaperLevel: Int32

            
            switch source {
            case .channel:
                
                emojiPackLevel = 0

                
                nameColorLevel = arguments.context.peerNameColors.nameColorsChannelMinRequiredBoostLevel[stateValue.with { $0.selected?.nameColor?.rawValue ?? 0 }] ?? 0
                nameIconLevel = arguments.premiumConfiguration.minChannelNameIconLevel

                profileColorLevel = arguments.context.peerNameColors.nameColorsChannelMinRequiredBoostLevel[stateValue.with { $0.selected_profile?.nameColor?.rawValue ?? 0 }] ?? 0
                profileIconLevel = arguments.premiumConfiguration.minChannelProfileIconLevel

                emojiStatusLevel = arguments.premiumConfiguration.minChannelEmojiStatusLevel
                wallpaperLevel = arguments.premiumConfiguration.minChannelWallpaperLevel
                customWallpaperLevel = arguments.premiumConfiguration.minChannelCustomWallpaperLevel
            case .group:
                nameColorLevel = 0
                nameIconLevel = 0

                profileColorLevel = arguments.context.peerNameColors.nameColorsGroupMinRequiredBoostLevel[stateValue.with { $0.selected_profile?.nameColor?.rawValue ?? 0 }] ?? 0
                profileIconLevel = arguments.premiumConfiguration.minGroupProfileIconLevel

                emojiStatusLevel = arguments.premiumConfiguration.minGroupEmojiStatusLevel
                emojiPackLevel = arguments.premiumConfiguration.minGroupEmojiPackLevel

                wallpaperLevel = arguments.premiumConfiguration.minGroupWallpaperLevel
                customWallpaperLevel = arguments.premiumConfiguration.minGroupCustomWallpaperLevel
            default:
                fatalError()
            }

            if let stats = stats {
                if wallpaper != actualWallpaper {
                    if let wallpaper = wallpaper {
                        switch wallpaper {
                        case .emoticon:
                            if stats.level < wallpaperLevel {
                                showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, peer, stats, myStatus, .wallpaper(wallpaperLevel)), for: context.window)
                                return
                            }
                        default:
                            if stats.level < customWallpaperLevel {
                                showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, peer, stats, myStatus, .wallpaper(customWallpaperLevel)), for: context.window)
                                return
                            }
                        }
                    }
                }
                
                if stats.level < nameColorLevel, nameColor != peer.nameColor {
                    showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, peer, stats, myStatus, .nameColor(nameColorLevel)), for: context.window)
                } else if stats.level < nameIconLevel, backgroundEmojiId != peer.backgroundEmojiId {
                    showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, peer, stats, myStatus, .nameIcon(nameIconLevel)), for: context.window)
                } else if stats.level < profileColorLevel, profileColor?.nameColor != peer.profileColor {
                    showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, peer, stats, myStatus, .profileColor(profileColorLevel)), for: context.window)
                } else if stats.level < profileIconLevel, profileBackgroundEmojiId != peer.profileBackgroundEmojiId {
                    showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, peer, stats, myStatus, .profileIcon(profileIconLevel)), for: context.window)
                } else if stats.level < emojiStatusLevel, emojiStatus != peer.emojiStatus {
                    showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, peer, stats, myStatus, .emojiStatus(emojiStatusLevel)), for: context.window)
                } else if stats.level < emojiPackLevel, emojiPack != actualEmojiPack {
                    showModal(with: SettingsNavigationHooks.shared.makeBoostInfoController(context, peer, stats, myStatus, .emojiPack(emojiStatusLevel)), for: context.window)
                } else {
                    request({
                        let text: String
                        if isGroup {
                            text = strings().selectColorSuccessAppearanceGroup
                        } else {
                            text = strings().selectColorSuccessAppearanceChannel
                        }
                        showModalText(for: context.window, text: text)
                    })
                }
            }
        case .account:
            if context.isPremium {
                request({
                    showModalText(for: context.window, text: strings().selectColorSuccessAppearanceUser)
                })
            } else {
                showModalText(for: context.window, text: strings().selectColorPremium, callback: { _ in
                    SettingsNavigationHooks.shared.showPremiumBoarding(context, .settings, false, context.window, nil)
                })
            }
        }
    }
    
    controller.validateData = { _ in
        invoke()
        return .none
    }
    
    controller.updateDoneValue = { data in
        return { f in
            if stateValue.with({ $0.saving }) {
                f(.loading)
            } else {
                if !stateValue.with ({ $0.isSame(to: source.peer) }) {
                    f(.enabled(strings().selectColorApply))
                } else {
                    f(.disabled(strings().selectColorApply))
                }
            }
        }
    }
    
    
    weak var panelView: BuyPanel? = nil
    
    controller.didLoad = { [weak nameGiftsContext, weak profileGiftsContext] controller, _ in
        getControl = { [weak controller] type in
            let id: InputDataIdentifier
            if let type = type {
                switch type {
                case .name:
                    id = _id_icon
                case .profile:
                    id = _id_icon_profile
                }
            } else {
                id = _id_emoji_status
            }
            
            let view = controller?.tableView.item(stableId: InputDataEntryId.general(id))?.view as? GeneralInteractedRowView
            return view?.textView
        }
        controller.tableView.setScrollHandler({ position in
            switch position.direction {
            case .bottom:
                nameGiftsContext?.loadMore()
                profileGiftsContext?.loadMore()
                for (_, context) in resaleContexts {
                    context.loadMore()
                }
            default:
                break
            }
        })
        
        let gift = statePromise.get() |> map { $0.selected_Gift ?? $0.emojiStatusGift } |> distinctUntilChanged |> deliverOnMainQueue
        
        actionsDisposable.add(gift.start(next: { [weak controller] value in
            guard let controller else {
                return
            }
            if let value, value.owner != .peerId(peerId) {
                let panel: BuyPanel
                if let current = panelView {
                    panel = current
                } else {
                    panel = BuyPanel(frame: NSMakeRect(0, controller.frame.height - BuyPanel.height, controller.frame.width, BuyPanel.height))
                    panel.autoresizingMask = [.width, .minYMargin]
                    panel.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    panelView = panel
                }
                controller.addSubview(panel)
                panel.update(gift: value, arguments: arguments)
                controller.tableView.contentInsets.bottom = BuyPanel.height
            } else if let view = panelView {
                performSubviewRemoval(view, animated: true)
                panelView = nil
                controller.tableView.contentInsets.bottom = 0
            }
        }))
    }
   
    close = {
        updateState { current in
            var current = current
            current.saving = false
            return current
        }
        context.bindings.rootNavigation().back()
    }
    
    controller.contextObject = (nameGiftsContext, profileGiftsContext, resaleContexts)
    
    return controller
    
}


private final class BuyPanel : View {
    static let buttonHeight: CGFloat = 40
    static let bottomInset: CGFloat = 8
    static let fadeHeight: CGFloat = 36
    static let height: CGFloat = fadeHeight + buttonHeight + bottomInset
    
    private let shadowView = EdgeEffectView()
    private let button = TextButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        shadowView.isEventLess = true
        addSubview(shadowView)
        addSubview(button)
        button.disableActions()
        button.scaleOnClick = true
        button.autohighlight = false
        button.setGlassEffect(tintColor: theme.colors.accent)
        updateLocalizationAndTheme(theme: theme)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = .clear
        button.set(background: .clear, for: .Normal)
        button.set(background: .clear, for: .Highlight)
        button.glassTintColor = theme.colors.accent
        button.set(color: theme.colors.underSelectedColor, for: .Normal)
        button.set(font: .medium(.text), for: .Normal)
        needsLayout = true
    }
    
    func update(gift: StarGift.UniqueGift, arguments: Arguments) {
        if let resellStars = gift.resell {
            button.set(text: strings().starNftBuyFor(resellStars.fullyFormatted), for: .Normal)
        }
        
        button.setSingle(handler: { [weak arguments] _ in
            arguments?.buyAndApply(gift, false)
        }, for: .Click)
        
        needsLayout = true
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        var view = result
        while let current = view, current !== self {
            if current === button {
                return result
            }
            view = current.superview
        }
        return nil
    }
    
    override func layout() {
        super.layout()
        let blockWidth = min(600, frame.width - 40)
        let buttonWidth = blockWidth - 40
        let buttonRect = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - buttonWidth) / 2), frame.height - BuyPanel.bottomInset - BuyPanel.buttonHeight, buttonWidth, BuyPanel.buttonHeight)
        button.layer?.cornerRadius = buttonRect.height / 2
        button.frame = buttonRect
        
        let edgeRect = NSMakeRect(0, buttonRect.minY - BuyPanel.fadeHeight, frame.width, frame.height - buttonRect.minY + BuyPanel.fadeHeight)
        shadowView.frame = edgeRect
        shadowView.update(color: theme.colors.listBackground, alpha: 1.0, edge: .top, edgeSize: edgeRect.height, rect: edgeRect, transition: .immediate)
    }
}
