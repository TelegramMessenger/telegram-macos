import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import SwiftSignalKit
import ThemeSettings
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import FoundationUtils
import TelegramMediaUtils
import TelegramLinks
import ChatHistoryModel
import FilePanels
import WallpaperUI


public class ThemePreviewRowItem: GeneralRowItem {

    fileprivate let theme: TelegramPresentationTheme
    fileprivate let items:[TableRowItem]
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, theme: TelegramPresentationTheme, viewType: GeneralViewType) {
        self.theme = theme.withUpdatedBackgroundSize(WallpaperDimensions.aspectFilled(NSMakeSize(200, 200)))
        
        let chatInteraction = SettingsHooks.shared.makeChatPreviewContext(context, context.peerId, true)
        
      
        
        let fromUser1 = TelegramUser(id: PeerId(1), accessHash: nil, firstName: context.myPeer?.displayTitle ?? "", lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: context.myPeer?.nameColor, backgroundEmojiId: context.myPeer?.backgroundEmojiId, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        
        let fromUser2 = TelegramUser(id: PeerId(2), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName2, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        
        
        
        let firstMessage = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 18 + 60*60*18, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser1, text: strings().appearanceSettingsChatPreview1, attributes: [], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        
        let firstEntry: ChatHistoryEntry = .MessageEntry(firstMessage, MessageIndex(firstMessage), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        
        
        let timestamp1: Int32 = 60 * 20 + 60 * 60 * 18

        let secondMessage = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 0), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: timestamp1, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser2, text: strings().appearanceSettingsChatPreview2, attributes: [ReplyMessageAttribute(messageId: firstMessage.id, threadMessageId: nil, quote: nil, isQuote: false, innerSubject: nil)], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary([firstMessage.id : firstMessage]), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        
        let secondEntry: ChatHistoryEntry = .MessageEntry(secondMessage, MessageIndex(secondMessage), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        
        let timestamp2: Int32 = 60 * 22 + 60 * 60 * 18
        
        let thridMessage = Message(stableId: 2, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: timestamp2, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser1, text: strings().appearanceSettingsChatPreview3, attributes: [], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        
        let thridEntry: ChatHistoryEntry = .MessageEntry(thridMessage, MessageIndex(thridMessage), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        
        
        let item1 = SettingsHooks.shared.makeChatPreviewItem(initialSize, chatInteraction, firstEntry, theme)
        let item2 = SettingsHooks.shared.makeChatPreviewItem(initialSize, chatInteraction, secondEntry, theme)
        let item3 = SettingsHooks.shared.makeChatPreviewItem(initialSize, chatInteraction, thridEntry, theme)
        
        
        self.items = [item1, item2, item3]
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
        
        chatInteraction.getGradientOffsetRect = { [weak self] in
            guard let `self` = self else {
                return .zero
            }
            return CGRect(origin: NSMakePoint(0, self.height), size: NSMakeSize(self.width, self.height))
        }
        
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        let itemWidth = self.blockWidth - self.viewType.innerInset.left - self.viewType.innerInset.right
        for item in items {
            _ = item.makeSize(itemWidth, oldWidth: 0)
        }
        return true
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = self.viewType.innerInset.top + self.viewType.innerInset.bottom
        
        for item in self.items {
            height += item.height
        }
        return height
    }
    
    public override func viewClass() -> AnyClass {
        return ThemePreviewRowView.self
    }
    
    public override var accessibilityLabel: String? {
        return strings().appearanceSettingsChatPreviewHeader
    }
    
}

private final class ThemePreviewRowView : TableRowView {
    private var containerView = GeneralRowContainerView(frame: NSZeroRect)
    private let backgroundView: BackgroundView
    private let itemsView = View()
    private let borderView: View = View()
    public required init(frame frameRect: NSRect) {
        backgroundView = BackgroundView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height))
        backgroundView.useSharedAnimationPhase = false
        super.init(frame: frameRect)
        self.containerView.addSubview(self.backgroundView)
        self.containerView.addSubview(self.borderView)
        self.addSubview(containerView)
        self.backgroundView.addSubview(itemsView)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
    
        containerView.applySettingsCorners(item)
        super.set(item: item, animated: animated)
        
        guard let item = item as? ThemePreviewRowItem else {
            return
        }
        
        self.layout()
        
        self.itemsView.removeAllSubviews()
        
        
        switch item.theme.backgroundMode {
        case .background, .tiled:
            borderView.isHidden = item.theme.bubbled
        case .plain:
            borderView.isHidden = false
        case .gradient:
            borderView.isHidden = item.theme.bubbled
        case let .color(color):
            borderView.isHidden = color != item.theme.colors.background
        }
        
        var y: CGFloat = item.viewType.innerInset.top
        for item in item.items {
            let vz = item.viewClass() as! TableRowView.Type
            let view = vz.init(frame:NSMakeRect(0, y, self.backgroundView.frame.width, item.height))
            view.set(item: item, animated: false)
            self.itemsView.addSubview(view)
            
            if let view = view as? AppearanceChatPreviewRowView {
                view.updateBackground(animated: false, item: view.item, rotated: true)
            }
            
            y += item.height
        }
        
        
    }
    
    public override func updateColors() {
        guard let item = item as? ThemePreviewRowItem else {
            return
        }
        self.containerView.backgroundColor = background
        self.backgroundView.backgroundMode = item.theme.bubbled ? item.theme.backgroundMode : .color(color: item.theme.colors.chatBackground)
        self.borderView.backgroundColor = theme.colors.border
        self.backgroundColor = item.viewType.rowBackground
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    public override func layout() {
        super.layout()
        guard let item = item as? ThemePreviewRowItem else {
            return
        }
        self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
        self.containerView.setCorners(item.viewType.corners)
        self.backgroundView.frame = self.containerView.bounds
        self.borderView.frame = NSMakeRect(0, self.containerView.frame.height - .borderSize, self.containerView.frame.width, .borderSize)
        itemsView.frame = backgroundView.bounds
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
