import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramMedia
import InputView
import InputTextView
import ChatModeTypes

public enum StarsStickerPlayback {
    case standard
    case previewFrames
    case onceEnd
    case loopHidden
}

public protocol StarsStickerView: AnyObject {
    var overridePlayValue: Bool? { get set }
    var starsStickerReady: Signal<Bool, NoError> { get }
    func updateStarsSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, colors: [LottieColor], playback: StarsStickerPlayback, animated: Bool)
}
public protocol StarsLiveMessagePreviewRow: TableRowItem {
}

public protocol StarsFilterChipRow: AnyObject {
    var select: () -> Void { get }
}


public struct StarsHooks {
    public let openChat: (any AccountContextProtocol, PeerId, ChatInitialAction?) -> Void
    public let openChatAt: (any AccountContextProtocol, MessageId) -> Void
    public let openChatIfNotCurrent: (any AccountContextProtocol, PeerId) -> Void
    public let isBubbledServiceItem: (TableRowItem?) -> Bool
    public let wearGiftBoostLevel: (any AccountContextProtocol) -> Int32
    public let openBoostForWear: (any AccountContextProtocol, Peer, ChannelBoostStatus?, MyBoostStatus?, Window) -> Void
    public let makeGiftMessagePreview: (NSSize, AnyHashable, any AccountContextProtocol, StarGift.UniqueGift, Updated_ChatTextInputState, @escaping () -> Void) -> TableRowItem
    public let openInviteHash: (any AccountContextProtocol, String, @escaping (PeerId) -> Void) -> Void
    public let showEmojiPicker: (any AccountContextProtocol, Control, @escaping (TelegramMediaFile, String) -> Void, @escaping (String) -> Void) -> Void
    public let makeInputTextRow: (NSSize, AnyHashable, any AccountContextProtocol, Updated_ChatTextInputState, String, Int32, @escaping (String) -> String, @escaping (Updated_ChatTextInputState) -> Void) -> TableRowItem
    public let openPeerInfo: (any AccountContextProtocol, PeerId) -> Void
    public let openGiftsProfile: (any AccountContextProtocol, PeerId, ProfileGiftsContext?) -> Void
    public let makeStickerView: (NSRect) -> NSView
    public let applyMessageEntities: ([MessageTextEntity], String, any AccountContextProtocol, CGFloat, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, NSColor?, Bool, Bool) -> NSAttributedString
    public let applyGiftMessagePreviewEntities: ([MessageTextEntity], String, any AccountContextProtocol) -> NSAttributedString
    public let shareLink: (any AccountContextProtocol, String, Window) -> Void
    public let openLink: (any AccountContextProtocol, String, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void
    public let inputTextViewSize: (NSView, CGFloat) -> (NSSize, CGFloat)
    public let openMiniApp: (any AccountContextProtocol, EnginePeer) -> Void
    public let makeCraftAboutFeatureItem: (NSSize, AnyHashable, [GiftCraftFeature]) -> TableRowItem
    public let makeCraftingAreaItem: (NSSize, AnyHashable, GiftCraftingAreaData) -> TableRowItem
    public let makeAvatarMenuItem: (any AccountContextProtocol, Peer) -> ContextMenuItem?
    public let openTonBalance: (any AccountContextProtocol, Int64?) -> Void
    public let giftTransferBlockchainOption: (any AccountContextProtocol, Window, StarGift.UniqueGift, StarGiftReference, ProfileGiftsContext) -> (title: String, icon: NSImage, action: () -> Void)?
    public let giftMoveToGiftsAction: (any AccountContextProtocol, Window, StarGift.UniqueGift) -> (() -> Void)?
    public var giftTransferBlockchainOptionWithContext: ((any AccountContextProtocol, Window, StarGift.UniqueGift, StarGiftReference, ProfileGiftsContext, AnalyticsContext) -> (title: String, icon: NSImage, action: () -> Void)?)?

    public func giftTransferBlockchainOptionObserved(_ context: any AccountContextProtocol, _ window: Window, _ gift: StarGift.UniqueGift, _ reference: StarGiftReference, _ giftsContext: ProfileGiftsContext, analyticsContext: AnalyticsContext) -> (title: String, icon: NSImage, action: () -> Void)? {
        if let giftTransferBlockchainOptionWithContext {
            return giftTransferBlockchainOptionWithContext(context, window, gift, reference, giftsContext, analyticsContext)
        }
        let presentation = analyticsContext.beginPresentation()
        guard let option = giftTransferBlockchainOption(context, window, gift, reference, giftsContext) else { return nil }
        return (title: option.title, icon: option.icon, action: {
            withExtendedLifetime(presentation) { option.action() }
        })
    }

    public let selectContact: (any AccountContextProtocol, Window, String, @escaping ([PeerId]) -> Signal<Bool, NoError>) -> Signal<[PeerId], NoError>
    public let openMultigift: (any AccountContextProtocol, Bool) -> Void
    public let openStarMonetization: (any AccountContextProtocol, PeerId, StarsRevenueStatsContext?) -> Void
    public let openMessagesPrivacy: (any AccountContextProtocol, SelectivePrivacySettings, GlobalPrivacySettings, @escaping (SelectivePrivacySettings, GlobalPrivacySettings) -> Void) -> Void
    public let showGalleryMedia: (any AccountContextProtocol, [Media], Message, InteractionContentViewProtocol?) -> Void
    public let makeRecentPeerRow: (NSSize, Peer, any AccountContextProtocol, AnyHashable, String?, @escaping () -> Void) -> TableRowItem
    public let makeFilterChipRow: (NSSize, AnyHashable, any AccountContextProtocol, NSAttributedString, Bool, @escaping () -> Void, (() -> [ContextMenuItem])?) -> TableRowItem
    public let makeSelectGiftsModal: (any AccountContextProtocol, Int32, PeerId, @escaping ([ProfileGiftsContext.State.StarGift], [ProfileGiftsContext.State.StarGift]) -> Void) -> ModalViewController
    public let applyMenuItemEmoji: (ContextMenuItem, any AccountContextProtocol, TelegramMediaFile) -> Void
    public let makeLiveMessagePreviewRow: (NSSize, AnyHashable, any AccountContextProtocol, GroupCallMessagesContext.Message) -> StarsLiveMessagePreviewRow
    public let updateBirthday: (Date, any AccountContextProtocol) -> Void
    public let openAffiliatePeer: (any AccountContextProtocol, PeerId, Bool) -> Void

    public init(openChat: @escaping (any AccountContextProtocol, PeerId, ChatInitialAction?) -> Void,
                openChatAt: @escaping (any AccountContextProtocol, MessageId) -> Void,
                openChatIfNotCurrent: @escaping (any AccountContextProtocol, PeerId) -> Void,
                isBubbledServiceItem: @escaping (TableRowItem?) -> Bool,
                wearGiftBoostLevel: @escaping (any AccountContextProtocol) -> Int32,
                openBoostForWear: @escaping (any AccountContextProtocol, Peer, ChannelBoostStatus?, MyBoostStatus?, Window) -> Void,
                makeGiftMessagePreview: @escaping (NSSize, AnyHashable, any AccountContextProtocol, StarGift.UniqueGift, Updated_ChatTextInputState, @escaping () -> Void) -> TableRowItem,
                openInviteHash: @escaping (any AccountContextProtocol, String, @escaping (PeerId) -> Void) -> Void,
                showEmojiPicker: @escaping (any AccountContextProtocol, Control, @escaping (TelegramMediaFile, String) -> Void, @escaping (String) -> Void) -> Void,
                makeInputTextRow: @escaping (NSSize, AnyHashable, any AccountContextProtocol, Updated_ChatTextInputState, String, Int32, @escaping (String) -> String, @escaping (Updated_ChatTextInputState) -> Void) -> TableRowItem,
                openPeerInfo: @escaping (any AccountContextProtocol, PeerId) -> Void,
                openGiftsProfile: @escaping (any AccountContextProtocol, PeerId, ProfileGiftsContext?) -> Void,
                makeStickerView: @escaping (NSRect) -> NSView,
                applyMessageEntities: @escaping ([MessageTextEntity], String, any AccountContextProtocol, CGFloat, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, NSColor?, Bool, Bool) -> NSAttributedString,
                applyGiftMessagePreviewEntities: @escaping ([MessageTextEntity], String, any AccountContextProtocol) -> NSAttributedString,
                shareLink: @escaping (any AccountContextProtocol, String, Window) -> Void,
                openLink: @escaping (any AccountContextProtocol, String, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void,
                inputTextViewSize: @escaping (NSView, CGFloat) -> (NSSize, CGFloat),
                openMiniApp: @escaping (any AccountContextProtocol, EnginePeer) -> Void,
                makeAvatarMenuItem: @escaping (any AccountContextProtocol, Peer) -> ContextMenuItem?,
                openTonBalance: @escaping (any AccountContextProtocol, Int64?) -> Void,
                giftTransferBlockchainOption: @escaping (any AccountContextProtocol, Window, StarGift.UniqueGift, StarGiftReference, ProfileGiftsContext) -> (title: String, icon: NSImage, action: () -> Void)?,
                giftMoveToGiftsAction: @escaping (any AccountContextProtocol, Window, StarGift.UniqueGift) -> (() -> Void)?,
                selectContact: @escaping (any AccountContextProtocol, Window, String, @escaping ([PeerId]) -> Signal<Bool, NoError>) -> Signal<[PeerId], NoError>,
                openMultigift: @escaping (any AccountContextProtocol, Bool) -> Void,
                openStarMonetization: @escaping (any AccountContextProtocol, PeerId, StarsRevenueStatsContext?) -> Void,
                openMessagesPrivacy: @escaping (any AccountContextProtocol, SelectivePrivacySettings, GlobalPrivacySettings, @escaping (SelectivePrivacySettings, GlobalPrivacySettings) -> Void) -> Void,
                showGalleryMedia: @escaping (any AccountContextProtocol, [Media], Message, InteractionContentViewProtocol?) -> Void,
                makeRecentPeerRow: @escaping (NSSize, Peer, any AccountContextProtocol, AnyHashable, String?, @escaping () -> Void) -> TableRowItem,
                makeFilterChipRow: @escaping (NSSize, AnyHashable, any AccountContextProtocol, NSAttributedString, Bool, @escaping () -> Void, (() -> [ContextMenuItem])?) -> TableRowItem,
                makeSelectGiftsModal: @escaping (any AccountContextProtocol, Int32, PeerId, @escaping ([ProfileGiftsContext.State.StarGift], [ProfileGiftsContext.State.StarGift]) -> Void) -> ModalViewController,
                applyMenuItemEmoji: @escaping (ContextMenuItem, any AccountContextProtocol, TelegramMediaFile) -> Void,
                makeLiveMessagePreviewRow: @escaping (NSSize, AnyHashable, any AccountContextProtocol, GroupCallMessagesContext.Message) -> StarsLiveMessagePreviewRow,
                updateBirthday: @escaping (Date, any AccountContextProtocol) -> Void,
                openAffiliatePeer: @escaping (any AccountContextProtocol, PeerId, Bool) -> Void,
                 makeCraftAboutFeatureItem: @escaping (NSSize, AnyHashable, [GiftCraftFeature]) -> TableRowItem,
                 makeCraftingAreaItem: @escaping (NSSize, AnyHashable, GiftCraftingAreaData) -> TableRowItem) {
        self.openChat = openChat
        self.openChatAt = openChatAt
        self.openChatIfNotCurrent = openChatIfNotCurrent
        self.isBubbledServiceItem = isBubbledServiceItem
        self.wearGiftBoostLevel = wearGiftBoostLevel
        self.openBoostForWear = openBoostForWear
        self.makeGiftMessagePreview = makeGiftMessagePreview
        self.openInviteHash = openInviteHash
        self.showEmojiPicker = showEmojiPicker
        self.makeInputTextRow = makeInputTextRow
        self.openPeerInfo = openPeerInfo
        self.openGiftsProfile = openGiftsProfile
        self.makeStickerView = makeStickerView
        self.applyMessageEntities = applyMessageEntities
        self.applyGiftMessagePreviewEntities = applyGiftMessagePreviewEntities
        self.shareLink = shareLink
        self.openLink = openLink
        self.inputTextViewSize = inputTextViewSize
        self.openMiniApp = openMiniApp
        self.makeCraftAboutFeatureItem = makeCraftAboutFeatureItem
        self.makeCraftingAreaItem = makeCraftingAreaItem
        self.makeAvatarMenuItem = makeAvatarMenuItem
        self.openTonBalance = openTonBalance
        self.giftTransferBlockchainOption = giftTransferBlockchainOption
        self.giftMoveToGiftsAction = giftMoveToGiftsAction
        self.selectContact = selectContact
        self.openMultigift = openMultigift
        self.openStarMonetization = openStarMonetization
        self.openMessagesPrivacy = openMessagesPrivacy
        self.showGalleryMedia = showGalleryMedia
        self.makeRecentPeerRow = makeRecentPeerRow
        self.makeFilterChipRow = makeFilterChipRow
        self.makeSelectGiftsModal = makeSelectGiftsModal
        self.applyMenuItemEmoji = applyMenuItemEmoji
        self.makeLiveMessagePreviewRow = makeLiveMessagePreviewRow
        self.updateBirthday = updateBirthday
        self.openAffiliatePeer = openAffiliatePeer
    }

    private static var value: StarsHooks?

    public static var shared: StarsHooks {
        guard let value = value else {
            preconditionFailure("StarsHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: StarsHooks) {
        self.value = hooks
    }
}

public func installStarsHooks(_ hooks: StarsHooks) {
    StarsHooks.install(hooks)
}
