import Cocoa
import TGUIKit
import TelegramCore
import TGCurrencyFormatter
import Postbox
import SwiftSignalKit
import InAppSettings
import CurrencyFormat
import ThemeSettings
import TelegramMedia
import TelegramMediaPlayer
import AlertsUI
import AvatarUI
import ChatHistoryModel
import GeneralRows
import InputDataUI
import LocalAnimations
import Localization
import MessageTextUtils
import MessageUtils
import PremiumUI
import StarsUI
import Strings
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import SecureIdUtils
import InlineStickerLayer
import SceneEffects
import UniqueGiftBackground

public class ChatServiceItem: ChatRowItem {

    public override var accessibilityKind: ChatMessageAccessibility.Kind {
        return .text(text.attributedString.string)
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return nil
    }
    
    
    
    public static var photoSize = NSMakeSize(200, 200)

    public let text:TextViewLayout
    public private(set) var imageArguments:TransformImageArguments?
    public private(set) var image:TelegramMediaImage?
    
    public struct GiftData {
        
        public struct Ribbon {
            public let color: NSColor
            public let text: String
        }
        
        public enum Source {
            case premium(days: Int32)
            case starGift(amount: Int64, date: Int32, from: EnginePeer?, to: EnginePeer?, purpose: Star_TransactionPurpose)
            case stars(amount: Int64, date: Int32, transactionId: String?, peer: EnginePeer?)
            case ton(amount: Int64, date: Int32, transactionId: String?, peer: EnginePeer?)
        }
        
        public struct UniqueAttributes {
            public struct Attribute {
                public var name: TextViewLayout
                public var value: TextViewLayout
            }
            public var header: TextViewLayout
            public var attributes: [Attribute]
            
            public var height: CGFloat {
                var height: CGFloat = 5
                height += header.layoutSize.height
                height += 5
                
                for attribute in attributes {
                    height += attribute.value.layoutSize.height + 6
                }
                height += 5
                return height
            }
            
            public func makeSize(width: CGFloat) {
                header.measure(width: width)
                
                for attribute in attributes {
                    attribute.name.measure(width: width / 2)
                    attribute.value.measure(width: width / 2)
                }
            }
        }
        
        public typealias GiftMessage = StarsUI.GiftMessage

        public let from: PeerId
        public let to: PeerId
        public let text: TextViewLayout
        public let info: TextViewLayout?
        public let source: Source
        public let ribbon: Ribbon?

        public let authorLayout: TextViewLayout?
        public let author: EnginePeer?

        public let uniqueAttributes: UniqueAttributes?
        public let giftMessage: GiftMessage?
        public let isPrepaidUpgrade: Bool

        public init(from: PeerId, to: PeerId, text: TextViewLayout, info: TextViewLayout?, source: Source, ribbon: Ribbon?, uniqueAttributes: UniqueAttributes?, giftMessage: GiftMessage?, authorLayout: TextViewLayout?, author: EnginePeer?, isPrepaidUpgrade: Bool) {
            self.from = from
            self.to = to
            self.text = text
            self.info = info
            self.source = source
            self.ribbon = ribbon
            self.uniqueAttributes = uniqueAttributes
            self.giftMessage = giftMessage
            self.text.measure(width: 200)
            self.info?.measure(width: 200)
            self.isPrepaidUpgrade = isPrepaidUpgrade
            self.uniqueAttributes?.makeSize(width: 200)
            self.giftMessage?.makeSize(width: 200)
            authorLayout?.measure(width: 200)
            authorLayout?.generateAutoBlock(backgroundColor: NSColor.black.withAlphaComponent(0.15))
            self.authorLayout = authorLayout
            self.author = author
        }
        
        var stickerSize: NSSize {
            switch source {
            case .starGift:
                return NSMakeSize(120, 120)
            default:
                return NSMakeSize(150, 150)
            }
        }

        public var height: CGFloat {
            var height = 10 + stickerSize.height + 10 + text.layoutSize.height + 15
            if let info {
                height += 4 + info.layoutSize.height
            }
            if let uniqueAttributes {
                height += uniqueAttributes.height
            }
            if let giftMessage {
                height += giftMessage.height
            }
            if let authorLayout {
                height += authorLayout.layoutSize.height
            }
            return height + 38
        }
        
        public var alt: String {
            if case .premium(let months) = source {
                let alt: String
                switch months {
                case 1:
                    alt = "1️⃣"
                case 3:
                    alt = "2️⃣"
                case 6:
                    alt = "3️⃣"
                case 12:
                    alt = "4️⃣"
                case 24:
                    alt = "5️⃣"
                default:
                    alt = "5️⃣"
                }
                return alt
            } else {
                return ""
            }
        }
    }
    
    public struct OfferData {
        public let context: any AccountContextProtocol
        public let message: Message
        public let receiver: EnginePeer
        public let amount: CurrencyAmount
        public let text: TextViewLayout
        public let info: TextViewLayout?
        public let gift: StarGift.UniqueGift
        
        public let isActive: Bool
        
        public let replyMarkupModel: ReplyMarkupNode?
        
        public init(context: any AccountContextProtocol, message: Message, receiver: EnginePeer, amount: CurrencyAmount, gift: StarGift.UniqueGift, text: TextViewLayout, info: TextViewLayout?, isActive: Bool, theme: TelegramPresentationTheme, accept: @escaping()->Void = {}, reject: @escaping()->Void = {}) {
            self.context = context
            self.message = message
            self.isActive = isActive
            self.amount = amount
            self.receiver = receiver
            self.gift = gift
            self.text = text
            self.info = info
            
            self.text.measure(width: 220)
            self.info?.measure(width: 220)
            if isActive {
                var rows: [ReplyMarkupRow] = []
                rows.append(.init(buttons: [
                    .init(title: strings().chatServiceOfferReject, titleWhenForwarded: nil, action: .url(SuggestedPostMessageAttribute.commandDecline), style: nil),
                    .init(title: strings().chatServiceOfferAccept, titleWhenForwarded: nil, action: .url(SuggestedPostMessageAttribute.commandApprove), style: nil)
                ]))
                replyMarkupModel = ReplyMarkupNode(rows, [], ReplyMarkupInteractions(context: context, proccess: { btn, _ in
                    switch btn.action {
                    case let .url(value):
                        if value == SuggestedPostMessageAttribute.commandDecline {
                            reject()
                        } else if value == SuggestedPostMessageAttribute.commandApprove {
                            accept()
                        }
                    default:
                        break
                    }
                }), theme, paid: false, xtrAmount: nil, isPostSuggest: true)
                
                replyMarkupModel?.measureSize(240)
            } else {
                replyMarkupModel = nil
            }

        }
        
        public var height: CGFloat {
            var height = 10 + 80 + 10 + text.layoutSize.height + 10
            
            if let info {
                height += info.layoutSize.height + 10
            }
            if let replyMarkupModel {
                height += replyMarkupModel.size.height + 2
            }
            return height
        }
        
        public var size: NSSize {
            return NSMakeSize(240, height)
        }
        
    }
    
    public struct SuggestPhotoData {
        public let from: PeerId
        public let to: PeerId
        public let text: TextViewLayout
        public let image: TelegramMediaImage
        public let isIncoming: Bool
        public init(from: PeerId, to: PeerId, text: TextViewLayout, isIncoming: Bool, image: TelegramMediaImage) {
            self.from = from
            self.to = to
            self.text = text
            self.isIncoming = isIncoming
            self.image = image
            self.text.measure(width: 160)
        }
        
        public var height: CGFloat {
            return 10 + 100 + 10 + text.layoutSize.height + 10 + 30 + 10
        }
    }
    
    public struct SetThemeData {
        public let text: TextViewLayout
        public let gift: StarGift.UniqueGift
        public init(text: TextViewLayout, gift: StarGift.UniqueGift) {
            self.text = text
            self.gift = gift
            self.text.measure(width: 180)
        }
        
        public var height: CGFloat {
            return 10 + 80 + 10 + text.layoutSize.height + 10 + 30 + 10
        }
        
        public var size: NSSize {
            return NSMakeSize(200, height)
        }
    }
    
    public struct SuggestBirthdayData {
        public let text: TextViewLayout
        public let birthday: TelegramBirthday
        public let isIncoming: Bool
        public init(text: TextViewLayout, birthday: TelegramBirthday, isIncoming: Bool) {
            self.text = text
            self.birthday = birthday
            self.isIncoming = isIncoming
            self.text.measure(width: 180)
        }
        
        public var height: CGFloat {
            return 10 + 80 + 10 + text.layoutSize.height + 10 + 50 + (isIncoming ? 40 : 0)
        }
        
        public var size: NSSize {
            return NSMakeSize(200, height)
        }
    }
    
    public struct CommunityChangedData {
        public let text: TextViewLayout
        public let communityId: PeerId
        public init(text: TextViewLayout, communityId: PeerId) {
            self.text = text
            self.communityId = communityId
            self.text.measure(width: 180)
        }
        public var height: CGFloat {
            return 10 + 80 + 10 + text.layoutSize.height + 10 + 34 + 10
        }
        public var size: NSSize {
            return NSMakeSize(200, height)
        }
    }

    public struct CopyProtectionRequestData {
        public let text: TextViewLayout
        public let items: [TextViewLayout]
        public let isActive: Bool
        public let replyMarkupModel: ReplyMarkupNode?

        public init(text: TextViewLayout, items: [TextViewLayout], isActive: Bool, theme: TelegramPresentationTheme, context: any AccountContextProtocol, accept: @escaping () -> Void = {}, reject: @escaping () -> Void = {}) {
            self.text = text
            self.items = items
            self.isActive = isActive

            self.text.measure(width: 220)
            for item in self.items {
                item.measure(width: 220)
            }

            if isActive {
                var rows: [ReplyMarkupRow] = []
                rows.append(.init(buttons: [
                    .init(title: strings().chatServiceCopyProtectionReject, titleWhenForwarded: nil, action: .url("reject"), style: nil),
                    .init(title: strings().chatServiceCopyProtectionAccept, titleWhenForwarded: nil, action: .url("accept"), style: nil)
                ]))
                replyMarkupModel = ReplyMarkupNode(rows, [], ReplyMarkupInteractions(context: context, proccess: { btn, _ in
                    switch btn.action {
                    case let .url(value):
                        if value == "reject" {
                            reject()
                        } else if value == "accept" {
                            accept()
                        }
                    default:
                        break
                    }
                }), theme, paid: false, xtrAmount: nil, isPostSuggest: true)
                replyMarkupModel?.measureSize(240)
            } else {
                replyMarkupModel = nil
            }
        }

        public var itemsHeight: CGFloat {
            guard !items.isEmpty else { return 0 }
            return items.reduce(0) { $0 + $1.layoutSize.height } + CGFloat(items.count - 1) * 10
        }

        public var height: CGFloat {
            var height: CGFloat = 10 + text.layoutSize.height + 10 + itemsHeight + 15
            if let replyMarkupModel {
                height += replyMarkupModel.size.height + 2
            }
            return height
        }

        public var size: NSSize {
            return NSMakeSize(240, height)
        }
    }

    public struct SuggestpostHeader {
        fileprivate let peer: Peer
        fileprivate let attributes: ChatServiceItem.GiftData.UniqueAttributes
        public init(text: String, peer: Peer, authorName: String, isIncoming: Bool) {
            
            self.peer = peer
            
            let components = text.components(separatedBy: ":")
            let amount = components[1]
            let timestamp = components[2]
            let currency = CurrencyAmount.Currency(components[3])

            let color = theme.chatServiceItemTextColor
            
            let timeString: String
            if let int = Int32(timestamp), int > 0 {
                timeString = stringForDate(timestamp: int)
            } else {
                timeString = strings().chatServiceSuggestPostHeaderTimeAnytime
            }

            let amountString: String
            if let int = Int(amount), int > 0 {
                switch currency {
                case .stars:
                    amountString = strings().starListItemCountOther(int)
                case .ton:
                    amountString = formatCurrencyAmount(Int64(int), currency: TON).prettyCurrencyNumberUsd + " " + TON
                }
            } else {
                amountString = strings().chatServiceSuggestPostHeaderPriceFree
            }

            attributes = .init(
                header: .init(
                    .initialize(string: isIncoming ? strings().chatServiceSuggestPostHeaderTitle(peer.displayTitle) : strings().chatServiceSuggestPostHeaderTitleYou, color: color, font: .medium(.text)).detectBold(with: .medium(.text)),
                    alignment: .center
                ),
                attributes: [
                    .init(
                        name: .init(.initialize(string: strings().chatServiceSuggestPostHeaderLabelPrice, color: color.withAlphaComponent(0.7), font: .normal(.text))),
                        value: .init(.initialize(string: amountString, color: color, font: .medium(.text)))
                    ),
                    .init(
                        name: .init(.initialize(string: strings().chatServiceSuggestPostHeaderLabelTime, color: color.withAlphaComponent(0.7), font: .normal(.text))),
                        value: .init(.initialize(string: timeString, color: color, font: .medium(.text)))
                    )
                ]
            )

            attributes.makeSize(width: 140)
        }
        
        public var height: CGFloat {
            return attributes.height
        }
    }
    
    public struct SuggestPostData {
        public let status: TelegramMediaActionType.SuggestedPostApprovalStatus
        public let layout: TextViewLayout
        public let titleLayout: TextViewLayout
        public let messageId: MessageId?
        
        public init(status: TelegramMediaActionType.SuggestedPostApprovalStatus, messageId: MessageId?, peer: Peer, isIncoming: Bool) {
            self.status = status
            self.messageId = messageId
            var text: String = ""
            
            switch status {
            case .approved(let timestamp, let amount):
                self.titleLayout = .init(
                    .initialize(string: strings().chatServiceSuggestPostStatusTitle, color: theme.chatServiceItemTextColor, font: .medium(.text)).detectBold(with: .medium(.text)),
                    alignment: .center
                )

                var text = ""

                if let timestamp {
                    let date = stringForDate(timestamp: timestamp)
                    if !isIncoming {
                        text += strings().chatServiceSuggestPostStatusPublishOutgoing(peer.displayTitle, date)
                    } else {
                        text += strings().chatServiceSuggestPostStatusPublishIncoming(peer.displayTitle, date)
                    }
                }

                if let amount, amount.amount.value > 0 {
                    text += "\n\n"
                    let formatted = amount.fullyFormatted
                    if !isIncoming {
                        text += strings().chatServiceSuggestPostStatusChargeOutgoing(formatted)
                    } else {
                        text += strings().chatServiceSuggestPostStatusChargeIncoming(formatted)
                    }
                }

                text += "\n\n"
                if !isIncoming {
                    text += strings().chatServiceSuggestPostStatusReleaseOutgoing(peer.displayTitle)
                } else {
                    text += strings().chatServiceSuggestPostStatusReleaseIncoming(peer.displayTitle)
                }

                text += "\n\n"
                text += strings().chatServiceSuggestPostStatusRefundCondition(peer.displayTitle)

            case .rejected(let reason, let comment):
                let title: String
                switch reason {
                case .generic:
                    title = strings().chatServiceSuggestPostStatusRejectedTitle
                case .lowBalance:
                    title = strings().chatServiceSuggestPostStatusRejectedLowBalanceTitle
                }

                self.titleLayout = .init(
                    .initialize(string: title, color: theme.chatServiceItemTextColor, font: .medium(.text)),
                    alignment: .center
                )

                switch reason {
                case .generic:
                    if !isIncoming {
                        if let comment {
                            text = strings().chatServiceSuggestPostStatusRejectedOutgoingWithComment(comment)
                        } else {
                            text = strings().chatServiceSuggestPostStatusRejectedOutgoingNoComment
                        }
                    } else {
                        if let comment {
                            text = strings().chatServiceSuggestPostStatusRejectedIncomingWithComment(peer.displayTitle, comment)
                        } else {
                            text = strings().chatServiceSuggestPostStatusRejectedIncomingNoComment(peer.displayTitle)
                        }
                    }

                case .lowBalance:
                    if !isIncoming {
                        text = strings().chatServiceSuggestPostStatusRejectedOutgoingLowBalance(peer.displayTitle)
                    } else {
                        text = strings().chatServiceSuggestPostStatusRejectedIncomingLowBalance(peer.displayTitle)
                    }
                }
            }
            
            let grayTextColor: NSColor = theme.chatServiceItemTextColor
            
            let attr = NSMutableAttributedString()
            attr.append(string: text, color: grayTextColor, font: .normal(.text))
            attr.detectBoldColorInString(with: .medium(.text))
            self.layout = TextViewLayout(attr, alignment: .left)
            
            self.titleLayout.measure(width: 200)
            self.layout.measure(width: 200)

        }
        
        public var height: CGFloat {
            var height: CGFloat = 10 + titleLayout.layoutSize.height + 10
            if !layout.string.isEmpty {
                height += layout.layoutSize.height + 10
            }
            return height
        }
    }
    
    public struct WallpaperData {
        public let wallpaper: Wallpaper
        public let aesthetic: TelegramWallpaper
        public let peerId: PeerId
        public let isIncoming: Bool
        public let forBoth: Bool
        public let installed: TelegramWallpaper?
        public init(wallpaper: Wallpaper, aesthetic: TelegramWallpaper, peerId: PeerId, isIncoming: Bool, forBoth: Bool, installed: TelegramWallpaper?) {
            self.wallpaper = wallpaper
            self.aesthetic = aesthetic
            self.peerId = peerId
            self.isIncoming = isIncoming
            self.forBoth = forBoth
            self.installed = installed
        }
        
        public var height: CGFloat {
            return 160
        }
    }
    public struct StoryData {
        public let media: TelegramMediaStory
        public let storyItem: Stories.StoredItem
        public let text: TextViewLayout
        public let isIncoming: Bool
        public let avatar: AvatarStoryIndicatorComponent?
        public let context: any AccountContextProtocol
        public let peer: PeerReference
        public init(context: any AccountContextProtocol, peer: PeerReference, maxReadId: Int32?, media: TelegramMediaStory, storyItem: Stories.StoredItem, text: TextViewLayout, theme: TelegramPresentationTheme, isIncoming: Bool) {
            self.media = media
            self.context = context
            self.storyItem = storyItem
            self.text = text
            self.peer = peer
            self.isIncoming = isIncoming
            
            if storyItem.expirationTimestamp > context.timestamp, let maxReadId = maxReadId {
                let isUnread: Bool = maxReadId < storyItem.id && isIncoming
                self.avatar = .init(hasUnseen: isUnread, hasUnseenCloseFriendsItems: false, hasLiveItems: false, theme: theme, activeLineWidth: 1.5, inactiveLineWidth: 1.5, counters: .init(totalCount: 1, unseenCount: isUnread ? 1 : 0))
            } else {
                self.avatar = nil
            }
            self.text.measure(width: 140)
        }
        
        public var height: CGFloat {
            return 10 + 80 + 10 + text.layoutSize.height + 10
        }
    }
    
    
    public struct WalletTransferData {
        public static let cardSize = NSMakeSize(216, 148)
        public static let outerInset: CGFloat = 4
        public static let captionSpacing: CGFloat = 7
        public static let captionBottomInset: CGFloat = 4
        public static let textOverlap: CGFloat = 4

        public let amount: Int64
        public let isIncoming: Bool
        public let transactionId: String
        public let comment: String?
        public let commentEncrypted: Bool
        public let hasEncryptedComment: Bool
        public let peer: EnginePeer?
        public let peerAddress: String
        public let name: String
        public let operationId: String?
        public let pendingTransactionId: String?
        public let captionLayout: TextViewLayout?

        public init(amount: Int64, isIncoming: Bool, transactionId: String, comment: String?, commentEncrypted: Bool = false, peer: EnginePeer?, peerAddress: String, name: String, operationId: String? = nil, pendingTransactionId: String? = nil, textColor: NSColor) {
            self.amount = amount
            self.isIncoming = isIncoming
            self.transactionId = transactionId
            self.comment = comment
            self.commentEncrypted = commentEncrypted
            self.peer = peer
            self.peerAddress = peerAddress
            self.name = name
            self.operationId = operationId
            self.pendingTransactionId = pendingTransactionId
            self.hasEncryptedComment = commentEncrypted
            if self.hasEncryptedComment {
                let placeholder = NSMutableAttributedString()
                placeholder.append(string: strings().chatServiceItemEncryptedComment, color: textColor, font: .normal(13))
                placeholder.addAttribute(TextInputAttributes.spoiler, value: true as NSNumber, range: placeholder.range)
                let layout = TextViewLayout(placeholder, alignment: .center, spoilerColor: textColor, isSpoilerRevealed: false)
                layout.measure(width: WalletTransferData.cardSize.width - 24)
                self.captionLayout = layout
            } else if !commentEncrypted, let comment, !comment.isEmpty {
                let layout = TextViewLayout(.initialize(string: comment, color: textColor, font: .normal(13)), alignment: .center)
                layout.measure(width: WalletTransferData.cardSize.width - 24)
                self.captionLayout = layout
            } else {
                self.captionLayout = nil
            }
        }

        public var width: CGFloat {
            return WalletTransferData.cardSize.width + WalletTransferData.outerInset * 2
        }

        public var height: CGFloat {
            var height = WalletTransferData.cardSize.height + WalletTransferData.outerInset * 2
            if let captionLayout {
                height += WalletTransferData.captionSpacing + captionLayout.layoutSize.height + WalletTransferData.captionBottomInset
            }
            return height
        }
    }

    @available(macOS 10.15, *)
    public func openWalletTransfer(decryptComment: Bool, morphSource: (() -> NSView?)? = nil) {
        guard let data = self.walletTransferData, let walletContext = ChatHistoryUIHooks.shared.walletHooks.walletContext(context) else {
            return
        }
        guard context.appConfiguration.getBoolValue("wallet_available", orElse: false) else {
            showModalText(for: context.window, text: strings().chatServiceItemWalletUnavailable)
            return
        }
        showModal(with: ChatHistoryUIHooks.shared.walletHooks.makeWalletTransactionController(context, walletContext, data, self.message?.timestamp ?? 0, decryptComment), for: context.window, morphSource: morphSource)
    }

    public func previewGift(morphSource: (() -> NSView?)? = nil) {
        if let offerData = offerData {
            if offerData.gift.flags.contains(.isBurned) {
                showModalText(for: context.window, text: strings().chatServiceGiftUsedForCrafting)
                return
            }
            showModal(with: StarGift_Nft_Controller(context: context, gift: .unique(offerData.gift), source: .quickLook(nil, offerData.gift)), for: context.window, morphSource: morphSource)
        }
    }

    public func openGift(morphSource: (() -> NSView?)? = nil) {
        if let giftData {
            switch giftData.source {
            case let .premium(months):
                prem(with: PremiumBoardingController(context: context, source: .gift(from: giftData.from, to: giftData.to, months: months, slug: nil, unclaimed: false)), for: context.window, morphSource: morphSource)
            case let .stars(amount, date, _, from):
                let transaction = StarsContext.State.Transaction(flags: [], id: "", count: .init(amount: .init(value: amount, nanos: 0), currency: .stars), date: date, peer: .unsupported, title: "", description: nil, photo: nil, transactionDate: nil, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: nil, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil)
                showModal(with: Star_TransactionScreen(context: context, fromPeerId: context.peerId, peer: from, transaction: transaction, purpose: .gift), for: context.window, morphSource: morphSource)
            case let .ton(amount, date, _, from):
                let transaction = StarsContext.State.Transaction(flags: [], id: "", count: .init(amount: .init(value: amount, nanos: 0), currency: .ton), date: date, peer: .unsupported, title: "", description: nil, photo: nil, transactionDate: nil, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: nil, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil)
                showModal(with: Star_TransactionScreen(context: context, fromPeerId: context.peerId, peer: from, transaction: transaction, purpose: .tonGift), for: context.window, morphSource: morphSource)
            case let .starGift(amount, date, from, to, purpose):
                let transaction: StarsContext.State.Transaction = StarsContext.State.Transaction(flags: [], id: "", count: .init(amount: .init(value: amount, nanos: 0), currency: .stars), date: date, peer: to.flatMap { .peer($0) } ?? .unsupported, title: "", description: nil, photo: nil, transactionDate: nil, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: purpose.gift, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil)
                
                switch purpose {
                case let .starGift(gift, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _):
                    if let unique = gift.unique {
                        if unique.flags.contains(.isBurned) {
                            showModalText(for: context.window, text: strings().chatServiceGiftUsedForCrafting)
                            return
                        }
                        showModal(with: StarGift_Nft_Controller(context: context, gift: gift, source: .quickLook(nil, unique), transaction: transaction, purpose: purpose), for: context.window, morphSource: morphSource)
                        return
                    }
                default:
                    break
                }
                
                let reference = purpose.reference ?? message.flatMap({ .message(messageId: $0.id )})
                
                showModal(with: Star_TransactionScreen(context: context, fromPeerId: context.peerId, peer: from, transaction: transaction, purpose: purpose, reference: reference), for: context.window, morphSource: morphSource)
            }
        } else if let setThemeData {
            if setThemeData.gift.flags.contains(.isBurned) {
                showModalText(for: context.window, text: strings().chatServiceGiftUsedForCrafting)
                return
            }
            showModal(with: StarGift_Nft_Controller(context: context, gift: .unique(setThemeData.gift), source: .quickLook(nil, setThemeData.gift)), for: context.window, morphSource: morphSource)
        }
    }
    
    
    public private(set) var giftData: GiftData? = nil
    public private(set) var walletTransferData: WalletTransferData? = nil
    public private(set) var offerData: OfferData? = nil

    public private(set) var suggestPhotoData: SuggestPhotoData? = nil
    public private(set) var wallpaperData: WallpaperData? = nil
    public private(set) var storydata: StoryData? = nil
    public private(set) var suggestChannelsData: ChannelSuggestData? = nil
    public private(set) var suggestPostStatus: SuggestPostData? = nil
    public private(set) var suggestPostHeader: SuggestpostHeader? = nil
    public private(set) var setThemeData: SetThemeData? = nil

    public private(set) var suggestBirthdayData: SuggestBirthdayData? = nil
    public private(set) var communityChangedData: CommunityChangedData? = nil
    public private(set) var copyProtectionRequestData: CopyProtectionRequestData? = nil
    
    public override init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction, _ context: any AccountContextProtocol, _ entry: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        let message:Message = entry.message!
                
        
        let linkColor: NSColor = theme.controllerBackgroundMode.hasWallpaper ? theme.chatServiceItemTextColor : entry.renderType == .bubble ? theme.chat.linkColor(true, entry.renderType == .bubble) : theme.colors.link
        let grayTextColor: NSColor = theme.chatServiceItemTextColor

        let authorId:PeerId? = message.author?.id
        var authorName:String = ""
        if let displayTitle = message.author?.displayTitle {
            authorName = displayTitle
        }
        let isIncoming: Bool = message.isIncoming(context.account, entry.renderType == .bubble)
        _ = theme.wallpaper.wallpaper != .none && entry.renderType == .bubble
        
        let nameColor:(PeerId) -> NSColor = { peerId in
            return theme.chatServiceItemTextColor
        }
        
        
        let attributedString:NSMutableAttributedString = NSMutableAttributedString()
        if let media = message.media[0] as? TelegramMediaAction {
           
            if let peer = coreMessageMainPeer(message) {
               
                switch media.action {
                case let .groupCreated(title: title):
                    if !peer.isChannel {
                        let _ =  attributedString.append(string: strings().chatServiceGroupCreated1(authorName, title), color: grayTextColor, font: .normal(theme.fontSize))
                        
                        if let authorId = authorId {
                            let range = attributedString.string.nsstring.range(of: authorName)
                            if range.location != NSNotFound {
                                let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                                attributedString.add(link: link, for: range, color: nameColor(authorId))
                                attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                                
                            }
                        }
                    } else {
                        let _ =  attributedString.append(string: strings().chatServiceChannelCreated, color: grayTextColor, font: .normal(theme.fontSize))
                    }
                    
                    
                case let .addedMembers(peerIds):
                    if peerIds.first == authorId {
                        let _ =  attributedString.append(string: strings().chatServiceGroupAddedSelf(authorName), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    } else {
                        let _ =  attributedString.append(string: strings().chatServiceGroupAddedMembers1(authorName, ""), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        for peerId in peerIds {
                            
                            if let peer = message.peers[peerId] {
                                let range = attributedString.append(string: peer.displayTitle, color: nameColor(peer.id), font: .medium(theme.fontSize))
                                if range.location != NSNotFound {
                                    let link = ChatHistoryLink.peerInfo(link: "", peerId: peerId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                                    attributedString.add(link: link, for: range, color: nameColor(peerId))
                                    if peerId != peerIds.last {
                                        _ = attributedString.append(string: ", ", color: grayTextColor, font: .normal(theme.fontSize))
                                    }
                                    if range.location != NSNotFound {
                                        //attributedString.insert(.embeddedAvatar(.init(peer), space: !noSpace, link: link), at: range.location)
                                        if peerId == peerIds.last {
                                            attributedString.insert(.initialize(string: " "), at: range.location)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    
                case let .removedMembers(peerIds):
                    if peerIds.first == message.author?.id {
                        let _ =  attributedString.append(string: strings().chatServiceGroupRemovedSelf(authorName), color: grayTextColor, font: .normal(theme.fontSize))
                    } else {
                        let _ =  attributedString.append(string: strings().chatServiceGroupRemovedMembers1(authorName, ""), color: grayTextColor, font: .normal(theme.fontSize))
                        for peerId in peerIds {
                            
                            if let peer = message.peers[peerId] {
                                let range = attributedString.append(string: peer.displayTitle, color: nameColor(peerId), font: .medium(theme.fontSize))
                                if range.location != NSNotFound {
                                    let link = ChatHistoryLink.peerInfo(link: "", peerId: peerId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                                    attributedString.add(link: link, for: range, color: nameColor(peer.id))
                                    if peerId != peerIds.last {
                                        _ = attributedString.append(string: ", ", color: grayTextColor, font: .normal(theme.fontSize))
                                    }
                                    if range.location != NSNotFound {
                               //         attributedString.insert(.embeddedAvatar(.init(peer), space: !noSpace, link: link), at: range.location)
                                        if peerId == peerIds.last {
                                            attributedString.insert(.initialize(string: " "), at: range.location)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(NSAttributedString.Key.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    
                case let .photoUpdated(image):
                    if let image = image {
                        
                        let text: String
                        if image.videoRepresentations.isEmpty {
                            text = peer.isChannel ? strings().chatServiceChannelUpdatedPhoto : strings().chatServiceGroupUpdatedPhoto(authorName)
                        } else {
                            text = peer.isChannel ? strings().chatServiceChannelUpdatedVideo : strings().chatServiceGroupUpdatedVideo(authorName)
                        }
                        
                        let _ =  attributedString.append(string: text, color: grayTextColor, font: .normal(theme.fontSize))
                        let size = ChatServiceItem.photoSize
                        imageArguments = TransformImageArguments(corners: ImageCorners(radius: 10), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets())
                    } else {
                        let _ =  attributedString.append(string: peer.isChannel ? strings().chatServiceChannelRemovedPhoto : strings().chatServiceGroupRemovedPhoto(authorName), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        
                    }
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(NSAttributedString.Key.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    self.image = image
                    
                    
                case let .titleUpdated(title):
                    let _ =  attributedString.append(string: peer.isChannel ? strings().chatServiceChannelUpdatedTitle(title) : strings().chatServiceGroupUpdatedTitle1(authorName, title), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .customText(text, _, additionalAttributes):
                    
                    if text.contains("post_suggest") {
                        
                        var peer: Peer = peer
                        if let monoforumId = (peer as? TelegramChannel)?.linkedMonoforumId {
                            peer = message.peers[monoforumId] ?? peer
                        }
                        self.suggestPostHeader = SuggestpostHeader(text: text, peer: peer, authorName: authorName, isIncoming: isIncoming)
                    } else {
                        let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        if let additionalAttributes = additionalAttributes {
                            for (range, key, value) in additionalAttributes.attributes {
                                attributedString.addAttribute(key, value: value, range: range)
                            }
                        }
                    }
                case let .botDomainAccessGranted(domain):
                    let _ = attributedString.append(string: strings().chatServiceBotPermissionAllowed(domain), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                case let .botAppAccessGranted(appName, _):
                    let _ = attributedString.append(string: strings().authSessionsMessageApp(appName ?? ""), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                case .pinnedMessageUpdated:
                    var replyMessageText = ""
                    var pinnedId: MessageId?
                    for attribute in message.attributes {
                        if let attribute = attribute as? ReplyMessageAttribute, let message = message.associatedMessages[attribute.messageId] {
                            let text = (pullText(from: message).string as String).replacingOccurrences(of: "\n", with: " ")
                            replyMessageText = message.restrictedText(context.contentSettings) ?? text
                            pinnedId = attribute.messageId
                        }
                    }
                    let cutted = replyMessageText.prefixWithDots(30)
                    _ = attributedString.append(string: strings().chatServiceGroupUpdatedPinnedMessage1(authorName, cutted), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    let pinnedRange = attributedString.string.nsstring.range(of: cutted)
                    if pinnedRange.location != NSNotFound {
                        attributedString.add(link: LinkHooks.shared.callbackLink("", { [weak chatInteraction] _ in
                            if let pinnedId = pinnedId {
                                chatInteraction?.focusMessageId(nil, .init(messageId: pinnedId, string: nil), .CenterEmpty)
                            }
                        }), for: pinnedRange, color: grayTextColor)
                        attributedString.addAttribute(NSAttributedString.Key.font, value: NSFont.medium(theme.fontSize), range: pinnedRange)
                    }
                   
                    
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)

                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(NSAttributedString.Key.font, value: NSFont.medium(theme.fontSize), range: range)
                            
                        }
                    }
                    
                case .joinedByLink:
                    let _ =  attributedString.append(string: strings().chatServiceGroupJoinedByLink(authorName), color: grayTextColor, font: .normal(theme.fontSize))
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    
                case .channelMigratedFromGroup, .groupMigratedToChannel:
                    let _ =  attributedString.append(string: strings().chatServiceGroupMigratedToSupergroup, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                case let .messageAutoremoveTimeoutUpdated(seconds, autoSourcePeerId):
                    
                    if let authorId = authorId {
                        if authorId == context.peerId {
                            if seconds > 0 {
                                if autoSourcePeerId == context.peerId {
                                    let _ =  attributedString.append(string: strings().chatAutoremoveTimerSetUserGlobalYou(autoremoveLocalized(Int(seconds))), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                                    
                                } else {
                                    let _ =  attributedString.append(string: strings().chatServiceSecretChatSetTimerSelf1(autoremoveLocalized(Int(seconds))), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                                }
                                
                            } else {
                                let _ =  attributedString.append(string: strings().chatServiceSecretChatDisabledTimerSelf1, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                            }
                        } else {
                            if let peer = coreMessageMainPeer(message) {
                                if peer.isGroup || peer.isSupergroup {
                                    if seconds > 0 {
                                        let _ =  attributedString.append(string: strings().chatServiceGroupSetTimer(autoremoveLocalized(Int(seconds))), color: grayTextColor, font: .normal(theme.fontSize))
                                    } else {
                                        let _ =  attributedString.append(string: strings().chatServiceGroupDisabledTimer, color: grayTextColor, font: .normal(theme.fontSize))
                                    }
                                } else if peer.isChannel {
                                    if seconds > 0 {
                                        let _ =  attributedString.append(string: strings().chatServiceChannelSetTimer(autoremoveLocalized(Int(seconds))), color: grayTextColor, font: .normal(theme.fontSize))
                                    } else {
                                        let _ =  attributedString.append(string: strings().chatServiceChannelDisabledTimer, color: grayTextColor, font: .normal(theme.fontSize))
                                    }
                                } else {
                                    if seconds > 0 {
                                        if autoSourcePeerId == authorId {
                                            let _ =  attributedString.append(string: strings().chatAutoremoveTimerSetUserGlobal(authorName, autoremoveLocalized(Int(seconds))), color: grayTextColor, font: .normal(theme.fontSize))
                                        } else {
                                            let _ =  attributedString.append(string: strings().chatServiceSecretChatSetTimer1(authorName, autoremoveLocalized(Int(seconds))), color: grayTextColor, font: .normal(theme.fontSize))
                                        }
                                    } else {
                                        let _ =  attributedString.append(string: strings().chatServiceSecretChatDisabledTimer1(authorName), color: grayTextColor, font: .normal(theme.fontSize))
                                    }
                                }
                                let range = attributedString.string.nsstring.range(of: authorName)
                                if range.location != NSNotFound {
                                    let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                                    attributedString.add(link: link, for: range, color: nameColor(authorId))
                                    attributedString.addAttribute(NSAttributedString.Key.font, value: NSFont.medium(theme.fontSize), range: range)
                                }
                            }

                        }
                    }
                case .historyScreenshot:
                    let _ =  attributedString.append(string: strings().chatServiceGroupTookScreenshot(authorName), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .phoneCall(callId: _, discardReason: reason, duration: duration, _):
                    if let reason = reason {
                        switch reason {
                        case .busy:
                            _ = attributedString.append(string: strings().chatListServiceCallCancelled, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        case .disconnect:
                            _ = attributedString.append(string: strings().chatListServiceCallMissed, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        case .hangup:
                            if let duration = duration {
                                if message.author?.id == context.peerId {
                                    _ = attributedString.append(string: strings().chatListServiceCallOutgoing(.durationTransformed(elapsed: Int(duration))), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                                } else {
                                    _ = attributedString.append(string: strings().chatListServiceCallIncoming(.durationTransformed(elapsed: Int(duration))), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                                }
                            }
                        case .missed:
                            _ = attributedString.append(string: strings().chatListServiceCallMissed, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        }
                    } else if let duration = duration {
                        if authorId == context.peerId {
                            _ = attributedString.append(string: strings().chatListServiceCallOutgoing(.durationTransformed(elapsed: Int(duration))), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        } else {
                            _ = attributedString.append(string: strings().chatListServiceCallIncoming(.durationTransformed(elapsed: Int(duration))), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        }
                    }
                case let .gameScore(gameId: _, score: score):
                    
                    var gameName:String = ""
                    for attr in message.attributes {
                        if let attr = attr as? ReplyMessageAttribute {
                            if let message = message.associatedMessages[attr.messageId], let gameMedia = message.anyMedia as? TelegramMediaGame {
                                gameName = gameMedia.name
                            }
                        }
                    }
                    
                    if let authorId = authorId {
                        let range = attributedString.append(string: authorName, color: linkColor, font: NSFont.medium(theme.fontSize))
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            _ = attributedString.append(string: " ")
                            
                        }
                    }
                    _ = attributedString.append(string: strings().chatListServiceGameScored1Other(Int(score), gameName), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                case let .paymentSent(currency, totalAmount, _, isRecurringInit, isRecurringUsed):
                    var paymentMessage:Message?
                    for attr in message.attributes {
                        if let attr = attr as? ReplyMessageAttribute {
                            if let message = message.associatedMessages[attr.messageId] {
                                paymentMessage = message
                            }
                        }
                    }
                    let media = paymentMessage?.anyMedia as? TelegramMediaInvoice
                    
                    if let paymentMessage = paymentMessage, let media = media, let peer = paymentMessage.peers[paymentMessage.id.peerId] {
                        if isRecurringInit {
                            _ = attributedString.append(string: strings().chatServicePaymentSentRecurringInit(TGCurrencyFormatter.shared().formatAmount(totalAmount, currency: currency), peer.displayTitle, media.title), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        } else if isRecurringUsed {
                            _ = attributedString.append(string: strings().chatServicePaymentSentRecurringUsed(TGCurrencyFormatter.shared().formatAmount(totalAmount, currency: currency), peer.displayTitle, media.title), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        } else {
                            _ = attributedString.append(string: strings().chatServicePaymentSent1(TGCurrencyFormatter.shared().formatAmount(totalAmount, currency: currency), peer.displayTitle, media.title), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        }
                        attributedString.detectBoldColorInString(with: .medium(theme.fontSize))
                        
                        attributedString.add(link:LinkHooks.shared.callbackLink("", { _ in
                            if currency == XTR {
                                _ = showModalProgress(signal: context.engine.payments.requestBotPaymentReceipt(messageId: message.id), for: context.window).startStandalone(next: { receipt in
                                    if let transactionId = receipt.transactionId {
                                        let transaction = StarsContext.State.Transaction(flags: .isLocal, id: transactionId, count: .init(amount: .init(value: -media.totalAmount, nanos: 0), currency: .stars), date: message.timestamp, peer: .peer(.init(peer)), title: media.title, description: media.description, photo: media.photo, transactionDate: message.timestamp, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: nil, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil)
                                        showModal(with: Star_TransactionScreen(context: context, fromPeerId: context.peerId, peer: messageMainPeer(.init(message)), transaction: transaction), for: context.window)
                                    }
                                })
                                
                            } else {
                                ChatNavigationHooks.shared.showPaymentsReceipt(context, message.id, media, context.window)
                            }
                        }), for: attributedString.range, color: grayTextColor)
                    } else if let peer = coreMessageMainPeer(message) {
                        if isRecurringInit {
                            _ = attributedString.append(string: strings().chatServicePaymentSentRecurringInitNoTitle(TGCurrencyFormatter.shared().formatAmount(totalAmount, currency: currency), peer.displayTitle), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        } else if isRecurringUsed {
                            _ = attributedString.append(string: strings().chatServicePaymentSentRecurringUsedNoTitle(TGCurrencyFormatter.shared().formatAmount(totalAmount, currency: currency), peer.displayTitle), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        } else {
                            _ = attributedString.append(string: strings().chatServicePaymentSent1NoTitle(TGCurrencyFormatter.shared().formatAmount(totalAmount, currency: currency), peer.displayTitle), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        }
                        attributedString.detectBoldColorInString(with: .medium(theme.fontSize))
                    }
                    
                    if currency == XTR {
                        attributedString.insertEmbedded(.embedded(name: XTR_ICON, color: grayTextColor, resize: false), for: XTR)
                    }
                case let .botSentSecureValues(types):
                    let permissions = types.map({$0.rawValue}).joined(separator: ", ")
                     _ = attributedString.append(string: strings().chatServiceSecureIdAccessGranted(peer.displayTitle, permissions), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                case .peerJoined:
                    let _ =  attributedString.append(string: strings().chatServicePeerJoinedTelegram(authorName), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                            
                        }
                    }
                case let .geoProximityReached(fromId, toId, distance):
                    let distanceString = stringForDistance(distance: Double(distance))
                    let text: String
                    if fromId == context.peerId {
                        text = strings().notificationProximityYouReached1(distanceString, message.peers[toId]?.displayTitle ?? "")
                    } else if toId == context.peerId {
                        text = strings().notificationProximityReachedYou1(message.peers[fromId]?.displayTitle ?? "", distanceString)
                    } else {
                        text = strings().notificationProximityReached1(message.peers[fromId]?.displayTitle ?? "", distanceString, message.peers[toId]?.displayTitle ?? "")
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))

                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                            
                        }
                    }
                    if let peer = message.peers[toId], !peer.displayTitle.isEmpty {
                        let range = attributedString.string.nsstring.range(of: peer.displayTitle)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: peer.id, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link:link, for: range, color: nameColor(peer.id))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                            //attributedString.insert(.embeddedAvatar(.init(peer), space: !noSpace, link: link), at: range.location)
                        }
                    }
                    if let peer = message.peers[fromId], !peer.displayTitle.isEmpty {
                        let range = attributedString.string.nsstring.range(of: peer.displayTitle)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: peer.id, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(peer.id))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                          //  attributedString.insert(.embeddedAvatar(.init(peer), space: !noSpace, link: link), at: range.location)
                        }
                    }
                case let .groupPhoneCall(callId, accessHash, scheduleDate, duration):
                    let text: String
                    if let duration = duration {
                        if peer.isChannel {
                            text = strings().chatServiceVoiceChatFinishedChannel1(autoremoveLocalized(Int(duration)))
                        } else if authorId == context.peerId {
                            text = strings().chatServiceVoiceChatFinishedYou(autoremoveLocalized(Int(duration)))
                        } else {
                            text = strings().chatServiceVoiceChatFinished(authorName, autoremoveLocalized(Int(duration)))
                        }
                        let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    } else {
                        if peer.isChannel {
                            if let scheduled = scheduleDate {
                                text = strings().chatServiceVoiceChatScheduledChannel1(stringForMediumDate(timestamp: scheduled))
                            } else {
                                text = strings().chatServiceVoiceChatStartedChannel1
                            }
                        } else if authorId == context.peerId {
                            if let scheduled = scheduleDate {
                                text = strings().chatServiceVoiceChatScheduledYou(stringForMediumDate(timestamp: scheduled))
                            } else {
                                text = strings().chatServiceVoiceChatStartedYou
                            }
                        } else {
                            if let scheduled = scheduleDate {
                                text = strings().chatServiceVoiceChatScheduled(authorName, stringForMediumDate(timestamp: scheduled))
                            } else {
                                text = strings().chatServiceVoiceChatStarted(authorName)
                            }
                        }
                        let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes.init(body: MarkdownAttributeSet(font: .normal(theme.fontSize), textColor: grayTextColor), bold: MarkdownAttributeSet(font: .medium(theme.fontSize), textColor: grayTextColor), link: MarkdownAttributeSet(font: .medium(theme.fontSize), textColor: linkColor), linkAttribute: { [weak chatInteraction] link in
                            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink("", { _ in
                                
                                let call = chatInteraction?.presentation.groupCall?.activeCall ?? CachedChannelData.ActiveCall(id: callId, accessHash: accessHash, title: nil, scheduleTimestamp: scheduleDate, subscribedToScheduled: false, isStream: false)
                                
                                chatInteraction?.joinGroupCall(call, nil)
                            }))
                        }))
                        attributedString.append(parsed)
                    }
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .setChatTheme(chatTheme):
                    let text: String
                    
                    var emoji: String = ""
                    var file: TelegramMediaFile? = nil
                    switch chatTheme {
                    case let .emoticon(emoticon):
                        emoji = emoticon
                    case let .gift(starGift, _):
                        if case let .unique(uniqueGift) = starGift {
                            for attribute in uniqueGift.attributes {
                                if case let .model(_, fileValue, _, _) = attribute {
                                    file = fileValue
                                    emoji = clown
                                    break
                                }
                            }
                        }
                    }
                    
                    
                    switch chatTheme {
                    case let .gift(gift, _):
                        if let unique = gift.unique {
                            let text: NSAttributedString
                            if isIncoming {
                                text = .initialize(
                                    string: strings().chatThemeOtherSet(authorName, "\(unique.title + " #" + "\(unique.number)")"),
                                    color: grayTextColor,
                                    font: .normal(.text)
                                )
                            } else {
                                text = .initialize(
                                    string: strings().chatThemeSelfSet("\(unique.title + " #" + "\(unique.number)")"),
                                    color: grayTextColor,
                                    font: .normal(.text)
                                )
                            }

                            self.setThemeData = .init(text: .init(text, alignment: .center), gift: unique)
                        }
                    case .emoticon:
                        if message.author?.id == context.peerId {
                            if emoji.isEmpty {
                                text = strings().chatServiceDisabledThemeYou
                            } else {
                                text = strings().chatServiceUpdateThemeYou(emoji)
                            }
                        } else {
                            if emoji.isEmpty {
                                text = strings().chatServiceDisabledTheme(authorName)
                            } else {
                                text = strings().chatServiceUpdateTheme(authorName, emoji)
                            }
                        }
                        
                        
                        let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes.init(body: MarkdownAttributeSet(font: .normal(theme.fontSize), textColor: grayTextColor), bold: MarkdownAttributeSet(font: .medium(theme.fontSize), textColor: grayTextColor), link: MarkdownAttributeSet(font: .medium(theme.fontSize), textColor: linkColor), linkAttribute: { link in
                            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink("", { _ in
                                
                            }))
                        }))
                        attributedString.append(parsed)

                        if let authorId = authorId {
                            let range = attributedString.string.nsstring.range(of: authorName)
                            if range.location != NSNotFound {
                                let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                                attributedString.add(link: link, for: range, color: nameColor(authorId))
                                attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                                
                            }
                        }
                        
                        if !emoji.isEmpty {
                            let range = attributedString.string.nsstring.range(of: emoji)
                            if range.location != NSNotFound {
                                attributedString.add(link:LinkHooks.shared.callbackLink("", { [weak chatInteraction] _ in
                                    chatInteraction?.setupChatThemes()
                                }), for: range, color: linkColor)
                            }
                        }
                        
                        if let file {
                            attributedString.insertEmbedded(.embeddedAnimated(file), for: clown)
                        }
                    }
                    
                case let .inviteToGroupPhoneCall(callId, accessHash, peerIds):
                    let text: String
                    
                    let list = NSMutableAttributedString()
                    for peerId in peerIds {
                        
                        if let peer = message.peers[peerId] {
                            let range = list.append(string: peer.displayTitle, color: nameColor(peerId), font: .medium(theme.fontSize))
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:peerId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            list.add(link: link, for: range, color: nameColor(peer.id))
                            if peerId != peerIds.last {
                                _ = list.append(string: ", ", color: grayTextColor, font: .normal(theme.fontSize))
                            }
                            if range.location != NSNotFound {
                          //      list.insert(.embeddedAvatar(.init(peer), space: !noSpace, link: link), at: range.location)
                                if peerId == peerIds.last {
                                    list.insert(.initialize(string: " "), at: range.location)
                                }
                            }
                        }
                    }
                    
                    if message.author?.id == context.peerId {
                        text = strings().chatServiceVoiceChatInvitationByYou("%mark%")
                    } else if peerIds.first == context.peerId {
                        text = strings().chatServiceVoiceChatInvitationForYou(authorName)
                    } else {
                        text = strings().chatServiceVoiceChatInvitation(authorName, "%mark%")
                    }
                    
                    let parsed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes.init(body: MarkdownAttributeSet(font: .normal(theme.fontSize), textColor: grayTextColor), bold: MarkdownAttributeSet(font: .medium(theme.fontSize), textColor: grayTextColor), link: MarkdownAttributeSet(font: .medium(theme.fontSize), textColor: linkColor), linkAttribute: { [weak chatInteraction] link in
                        return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink("", { _ in
                            chatInteraction?.joinGroupCall(CachedChannelData.ActiveCall(id: callId, accessHash: accessHash, title: nil, scheduleTimestamp: nil, subscribedToScheduled: false, isStream: false), nil)
                        }))
                    }))
                    attributedString.append(parsed)
                    
                    let markRange = attributedString.string.nsstring.range(of: "%mark%")
                    if markRange.location != NSNotFound {
                        attributedString.replaceCharacters(in: markRange, with: list)
                    }

                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                            
                        }
                    }
                case .joinedByRequest:
                    let text: String
                    if authorId == context.peerId {
                        if message.peers[message.id.peerId]?.isChannel == true {
                            text = strings().chatServiceJoinedChannelByRequest
                        } else {
                            text = strings().chatServiceJoinedGroupByRequest
                        }
                    } else {
                        if message.peers[message.id.peerId]?.isChannel == true {
                            text = strings().chatServiceUserJoinedChannelByRequest(authorName)
                        } else {
                            text = strings().chatServiceUserJoinedGroupByRequest(authorName)
                        }
                    }
                    let _ =  attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .webViewData(text):
                    let _ =  attributedString.append(string: strings().chatServiceWebData(text), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                case let .giftPremium(currency, amount, days, _, _, text, entities):
                    
                    
                    let header = NSMutableAttributedString()
                    
                    _ = header.append(string: strings().giftPremiumHeader(timeIntervalString(Int(days) * 60 * 60 * 24)), color: grayTextColor, font: .normal(theme.fontSize))
                    header.detectBoldColorInString(with: .medium(theme.fontSize))
                    
                    let info = NSMutableAttributedString()
                    
                    if let text = text, !text.isEmpty {
                        let attr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities ?? [])], for: text, message: nil, context: context, fontSize: theme.fontSize, openInfo: { _, _, _, _ in }, textColor: grayTextColor, isDark: theme.colors.isDark, bubbled: true).mutableCopy() as! NSMutableAttributedString
                        InlineStickerItem.apply(to: attr, associatedMedia: message.associatedMedia, entities: entities ?? [], isPremium: context.isPremium)
                        info.append(attr)
                    } else {
                        info.append(string: strings().giftPremiumText, color: grayTextColor, font: .normal(.text))
                    }
                    
                    
                    self.giftData = .init(from: authorId ?? message.id.peerId, to: message.id.peerId, text: TextViewLayout(header, alignment: .center), info: info.string.isEmpty ? nil : TextViewLayout(info, maximumNumberOfLines: 4, alignment: .center), source: .premium(days: days), ribbon: nil, uniqueAttributes: nil, giftMessage: nil, authorLayout: nil, author: nil, isPrepaidUpgrade: false)
                    
                    let text: String
                    let formattedCurrency: String
                    if currency == XTR {
                        formattedCurrency = strings().starListItemCountOther(Int(amount))
                    } else {
                        formattedCurrency = formatCurrencyAmount(amount, currency: currency)
                    }
                    if authorId == context.peerId {
                        
                        text = strings().chatServicePremiumGiftSentYou(formattedCurrency)
                    } else {
                        text = strings().chatServicePremiumGiftSent(authorName, formattedCurrency)
                    }
                    let _ =  attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .suggestedProfilePhoto(image):
                    
                    
                    if let image = image {
                                                
                        let info = NSMutableAttributedString()
                        if authorId == context.peerId {
                            _ = info.append(string: strings().chatServiceSuggestPhotoInfoYou(message.peers[message.id.peerId]?.compactDisplayTitle ?? ""), color: grayTextColor, font: .normal(.text))
                        } else {
                            _ = info.append(string: strings().chatServiceSuggestPhotoInfo(authorName), color: grayTextColor, font: .normal(.text))
                        }
                        self.suggestPhotoData = .init(from: authorId ?? message.id.peerId, to: message.id.peerId, text: TextViewLayout(info, alignment: .center), isIncoming: authorId != context.peerId, image: image)
                    } else {
                        let text: String
                        if authorId == context.peerId {
                            text = strings().chatServiceYouSuggestedPhoto
                        } else {
                            text = strings().chatServiceSuggestedPhoto(authorName)
                        }
                        let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        
                        if let authorId = authorId {
                            let range = attributedString.string.nsstring.range(of: authorName)
                            if range.location != NSNotFound {
                                let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                                attributedString.add(link: link, for: range, color: nameColor(authorId))
                                attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                            }
                        }
                    }
                case let .topicCreated(title, _, iconFileId):
                    let text: String
                    if let iconFileId = iconFileId {
                        text = strings().chatServiceGroupTopicCreatedIcon("~~\(iconFileId)~~", title.prefixWithDots(30))
                    } else {
                        text = strings().chatServiceGroupTopicCreated(title)
                    }
                    let _ =  attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    if let fileId = iconFileId {
                        let range = text.nsstring.range(of: "~~\(fileId)~~")
                        if range.location != NSNotFound {
                            InlineStickerItem.apply(to: attributedString, associatedMedia: [:], entities: [.init(range: range.lowerBound ..< range.upperBound, type: .CustomEmoji(stickerPack: nil, fileId: fileId))], isPremium: context.isPremium)
                        }
                    }
                case let .topicEdited(components):
                    let text: String
                    var fileId: Int64? = nil
                    if let component = components.first {
                        switch component {
                        case let .title(title):
                            if authorId == context.peerId {
                                text = strings().chatServiceGroupTopicEditedYouTitle(title.prefixWithDots(30))
                            } else {
                                text = strings().chatServiceGroupTopicEditedTitle(authorName, title.prefixWithDots(30))
                            }
                        case let .iconFileId(iconFileId):
                            fileId = iconFileId
                            if let iconFileId = iconFileId {
                                if authorId == context.peerId {
                                    text = strings().chatServiceGroupTopicEditedYouIcon("~~\(iconFileId)~~")
                                } else {
                                    text = strings().chatServiceGroupTopicEditedIcon(authorName, "~~\(iconFileId)~~")
                                }
                            } else {
                                if authorId == context.peerId {
                                    text = strings().chatServiceGroupTopicEditedYouIconRemoved
                                } else {
                                    text = strings().chatServiceGroupTopicEditedIconRemoved(authorName)
                                }
                            }
                        case let .isClosed(closed):
                            if authorId == context.peerId {
                                if closed {
                                    text = strings().chatServiceGroupTopicEditedYouPaused
                                } else {
                                    text = strings().chatServiceGroupTopicEditedYouResumed
                                }
                            } else {
                                if closed {
                                    text = strings().chatServiceGroupTopicEditedPaused(authorName)
                                } else {
                                    text = strings().chatServiceGroupTopicEditedResumed(authorName)
                                }
                            }
                        case let .isHidden(hidden):
                            if authorId == context.peerId {
                                if hidden {
                                    text = strings().chatServiceGroupTopicEditedYouHided
                                } else {
                                    text = strings().chatServiceGroupTopicEditedYouUnhided
                                }
                            } else {
                                if hidden {
                                    text = strings().chatServiceGroupTopicEditedHided(authorName)
                                } else {
                                    text = strings().chatServiceGroupTopicEditedUnhided(authorName)
                                }
                            }
                        }
                    } else {
                        var title: String = ""
                        var iconFileId: Int64?
                        for component in components {
                            switch component {
                            case let .title(value):
                                title = value.prefixWithDots(30)
                            case let .iconFileId(value):
                                iconFileId = value
                            case .isClosed:
                                break
                            case .isHidden:
                                break
                            }
                        }
                        fileId = iconFileId
                        if let iconFileId = iconFileId {
                            if authorId == context.peerId {
                                text = strings().chatServiceGroupTopicEditedYouMixed("~~\(iconFileId)~~", title)
                            } else {
                                text = strings().chatServiceGroupTopicEditedMixed(authorName, "~~\(iconFileId)~~", title)
                            }
                        } else {
                            if authorId == context.peerId {
                                text = strings().chatServiceGroupTopicEditedYouTitle(title)
                            } else {
                                text = strings().chatServiceGroupTopicEditedTitle(authorName, title)
                            }
                        }
                    }
                    let _ =  attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                   
                    if let fileId = fileId {
                        let range = text.nsstring.range(of: "~~\(fileId)~~")
                        if range.location != NSNotFound {
                            InlineStickerItem.apply(to: attributedString, associatedMedia: [:], entities: [.init(range: range.lowerBound ..< range.upperBound, type: .CustomEmoji(stickerPack: nil, fileId: fileId))], isPremium: context.isPremium)
                        }
                    }
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    
                case .attachMenuBotAllowed:
                    _ = attributedString.append(string: strings().chatServiceBotWriteAllowed, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                case let .requestedPeer(_, peerIds):
                    
                    if let botPeer = message.peers[message.id.peerId] {
                        _ = botPeer.displayTitle
                        let resultTitleString: String
                        if peerIds.count == 1 {
                            if let peer = message.peers[peerIds[0]] {
                                resultTitleString = strings().chatServicePeerRequested(peer.displayTitle, botPeer.displayTitle)
                            } else {
                                resultTitleString = ""
                            }
                        } else {
                            let peers: [String] = peerIds.compactMap { message.peers[$0]?.displayTitle }
                            resultTitleString = strings().chatServicePeerRequestedMultiple(peers.joined(separator: ", "), botPeer.displayTitle)
                        }

                        _ = attributedString.append(string: resultTitleString, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        
                        for peerId in peerIds {
                            if let peer = message.peers[peerId] {
                                let range = attributedString.string.nsstring.range(of: peer.displayTitle)
                                if range.location != NSNotFound {
                                    let link = ChatHistoryLink.peerInfo(link: "", peerId: peerId, action:nil, openChat: true, postId: nil, callback: chatInteraction.openInfo)
                                    attributedString.add(link: link, for: range, color: nameColor(peerId))
                                    attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                                   // attributedString.insert(.embeddedAvatar(.init(peer), space: !noSpace, link: link), at: range.location)
                                }
                            }

                        }
                        

                    }
                    
                    
                case let .setChatWallpaper(wallpaper, forBoth):
                    
                    let text: String
                    if authorId == context.peerId {
                        if forBoth {
                            let peerName = message.peers[message.id.peerId]?.compactDisplayTitle ?? ""
                            text = strings().chatServiceYouChangedWallpaperBoth(peerName)
                        } else {
                            text = strings().chatServiceYouChangedWallpaper
                        }
                    } else {
                        text = strings().chatServiceChangedWallpaper(authorName)
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                       
                    }
                    
                    let installedWallpaper = entry.additionalData.cachedData?.wallpaper
                    self.wallpaperData = .init(wallpaper: wallpaper.uiWallpaper(nil), aesthetic: wallpaper, peerId: message.id.peerId, isIncoming: authorId != context.peerId, forBoth: forBoth, installed: installedWallpaper)
                case .setSameChatWallpaper:
                    let text: String
                    if authorId == context.peerId {
                        text = strings().chatServiceYouChangedToSameWallpaper
                    } else {
                        text = strings().chatServiceChangedToSameWallpaper(authorName)
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .giveawayLaunched(stars):
                    let text: String
                    if let stars {
                        text = strings().chatServiceGiveawayStartedStarsOther(authorName, Int(stars))
                    } else {
                        text = strings().chatServiceGiveawayStarted(authorName)
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case .joinedChannel:
                    let text = strings().chatServiceJoinedChannel
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    if let recommendedChannels = entry.additionalData.recommendedChannels, !recommendedChannels.channels.isEmpty, !recommendedChannels.isHidden {
                        self.suggestChannelsData = .init(channels: recommendedChannels, context: context, presentation: theme)
                    }
                case let .giveawayResults(winners, unclaimed, stars):
                    var text: String
                    if winners == 0 {
                        text = stars ? strings().chatServiceGiveawayResultsNoWinnersStarsOther(Int(unclaimed)) : strings().chatServiceGiveawayResultsNoWinnersOther(Int(unclaimed))
                    } else if unclaimed > 0 {
                        text = stars ? strings().chatServiceGiveawayResultsStarsOther(Int(winners)) : strings().chatServiceGiveawayResultsOther(Int(winners))
                        let winnersString = stars ? strings().chatServiceGiveawayResultsMixedWinnersStarsOther(Int(winners)) : strings().chatServiceGiveawayResultsMixedWinnersOther(Int(winners))
                        let unclaimedString = stars ? strings().chatServiceGiveawayResultsMixedUnclaimedStarsOther(Int(unclaimed)) : strings().chatServiceGiveawayResultsMixedUnclaimedOther(Int(unclaimed))
                        text = winnersString + "\n" + unclaimedString
                    } else {
                        text = stars ? strings().chatServiceGiveawayResultsStarsOther(Int(winners)) : strings().chatServiceGiveawayResultsOther(Int(winners))
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    attributedString.detectBoldColorInString(with: .medium(theme.fontSize))
                    
                    let messageId: MessageId? = message.replyAttribute?.messageId
                    
                    if let messageId = messageId {
                        attributedString.add(link: LinkHooks.shared.callbackLink("", { [weak chatInteraction] _ in
                            chatInteraction?.focusMessageId(nil, .init(messageId: messageId, string: nil), .CenterEmpty)
                        }), for: attributedString.range, color: grayTextColor)
                    }
                case let .boostsApplied(boosts):
                    let text: String
                    if authorId == context.peerId {
                        if boosts == 1 {
                            text = strings().notificationBoostSingleYou
                        } else {
                            let boostsString = strings().notificationBoostTimesOther(Int(boosts), "\(boosts)")
                            text = strings().notificationBoostMultipleYou(boostsString)
                        }
                    } else {
                        let peerName = message.author?.compactDisplayTitle ?? ""
                        if boosts == 1 {
                            text = strings().notificationBoostSingle(peerName)
                        } else {
                            let boostsString = strings().notificationBoostTimesOther(Int(boosts), "\(boosts)")
                            text = strings().notificationBoostMultiple(peerName, boostsString)
                        }
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .paymentRefunded(_, _, totalAmount, _, transactionId):
                    let peerName = message.author?.compactDisplayTitle ?? ""

                    let _ = attributedString.append(string: strings().chatServiceRefund(peerName, "\(clown_space)\(totalAmount)"), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    attributedString.insertEmbedded(.embedded(name: XTR_ICON, color: grayTextColor, resize: false), for: clown)
                    
                    if let peer = message.author {
                        let transaction = StarsContext.State.Transaction(flags: [.isRefund], id: transactionId, count: .init(amount: .init(value: totalAmount, nanos: 0), currency: .stars), date: message.timestamp, peer: .peer(.init(peer)), title: nil, description: nil, photo: nil, transactionDate: nil, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: nil, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil)
                        let link = LinkHooks.shared.callbackLink("", { _ in
                            showModal(with: Star_TransactionScreen(context: context, fromPeerId: context.peerId, peer: .init(peer), transaction: transaction), for: context.window)
                        })
                        attributedString.add(link: link, for: attributedString.range, color: grayTextColor)
                    }
                    
                case let .giftStars(currency, amount, count, _, _, transactionId):
                    
                    let info = NSMutableAttributedString()
                    let header = NSMutableAttributedString()
                    header.append(string: strings().starListItemCountOther(Int(count)), color: grayTextColor, font: .medium(theme.fontSize + 1))
                    
                    
                    _ = info.append(string: strings().starsGiftServiceInfo, color: grayTextColor, font: .normal(theme.fontSize))
                    info.detectBoldColorInString(with: .medium(theme.fontSize))
                    
                    
                    
                    self.giftData = .init(from: authorId ?? message.id.peerId, to: message.id.peerId, text: TextViewLayout(header, alignment: .center), info: TextViewLayout(info, alignment: .center), source: .stars(amount: isIncoming ? count : -count, date: message.timestamp, transactionId: transactionId, peer: isIncoming ? message.author.flatMap(EnginePeer.init) : message.peers[message.id.peerId].flatMap(EnginePeer.init)), ribbon: nil, uniqueAttributes: nil, giftMessage: nil, authorLayout: nil, author: nil, isPrepaidUpgrade: false)
                    
                    let text: String
                    if authorId == context.peerId {
                        text = strings().chatServicePremiumGiftSentYou(formatCurrencyAmount(amount, currency: currency))
                    } else {
                        if authorId == servicePeerId {
                            text = strings().chatServicePremiumGiftSent(strings().chatServicePremiumUnknown, formatCurrencyAmount(amount, currency: currency))
                        } else {
                            text = strings().chatServicePremiumGiftSent(authorName, formatCurrencyAmount(amount, currency: currency))
                        }
                    }
                    let _ =  attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .starGift(gift, convertStars, text, entities, nameHidden, savedToProfile, convertedToStars, upgraded, canUpgrade, upgradeStars, isRefunded, isPrepaidUpgrade, _, peerId, senderId, savedId, _, giftMessageId, upgradeSeparate, auctionAcquired, toId, number):
                    let info = NSMutableAttributedString()
                    let header = NSMutableAttributedString()
                    
                    
                    let authorPeer: EnginePeer?
                    if let authorId = gift.releasedBy {
                        authorPeer = message.peers[authorId].flatMap(EnginePeer.init)
                    } else {
                        authorPeer = nil
                    }
                    
                    let authorLayout: TextViewLayout?
                    if let authorPeer, let addressName = authorPeer.addressName {
                        authorLayout = TextViewLayout(
                            .initialize(
                                string: strings().starTransactionReleasedBy(addressName),
                                color: .white,
                                font: .normal(.short)
                            ),
                            maximumNumberOfLines: 1,
                            truncationType: .middle
                        )
                    } else {
                        authorLayout = nil
                    }
                    
                    
                    guard let gift = gift.generic else {
                        break
                    }
                    
                   
                    let toPeer: EnginePeer?
                    if authorId != context.peerId {
                        toPeer = context.myPeer.flatMap { .init($0) }
                    } else {
                        toPeer = message.peers[message.id.peerId].flatMap( { .init($0) })
                    }
                    
                    var headerTitle: String? = nil
                    if let title = gift.title {
                        headerTitle = gift.title
                        if let number {
                            headerTitle = title + " #\(number)"
                        }
                    }
                    
                    if message.id.peerId == context.peerId {
                        header.append(string: headerTitle ?? strings().notificationStarGiftSelfTitle, color: grayTextColor, font: .medium(theme.fontSize + 1))
                    } else {
                        if let senderId, let author = message.peers[senderId] {
                            header.append(string: strings().chatServiceStarGiftFrom("\(author.displayTitle)"), color: grayTextColor, font: .medium(theme.fontSize + 1))
                        } else {
                            if let toId {
                                if toId == context.peerId {
                                    header.append(string: headerTitle ?? strings().notificationStarGiftSelfTitle, color: grayTextColor, font: .medium(theme.fontSize + 1))
                                } else if let author = message.peers[toId] {
                                    header.append(string: strings().chatServiceStarGiftFrom("\(author.displayTitle)"), color: grayTextColor, font: .medium(theme.fontSize + 1))
                                }
                            } else if context.peerId == message.author?.id {
                                header.append(string: strings().chatServiceStarGiftFrom("\(authorName)"), color: grayTextColor, font: .medium(theme.fontSize + 1))
                            } else {
                                header.append(string: strings().chatServiceStarGiftFor("\(authorName)"), color: grayTextColor, font: .medium(theme.fontSize + 1))
                            }
                        }
                    }
     

                    if let text = text, !text.isEmpty {
                        let attr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities ?? [])], for: text, message: nil, context: context, fontSize: theme.fontSize, openInfo: { _, _, _, _ in }, textColor: grayTextColor, isDark: theme.colors.isDark, bubbled: true).mutableCopy() as! NSMutableAttributedString
                        
                        InlineStickerItem.apply(to: attr, associatedMedia: message.associatedMedia, entities: entities ?? [], isPremium: context.isPremium)

                        info.append(attr)

                    } else if isRefunded {
                        info.append(string: strings().chatServiceStarGiftRefunded, color: grayTextColor, font: .normal(theme.fontSize))
                    } else if let upgradeStars, upgradeStars > 0, !upgraded, message.id.peerId != context.peerId {
                        let text: String
                        if isIncoming {
                            text = strings().chatServiceGiftUnpackIncoming
                        } else {
                            text = strings().chatServiceGiftUnpackOutgoing(toPeer?._asPeer().compactDisplayTitle ?? "")
                        }
                        info.append(string: text, color: grayTextColor, font: .normal(theme.fontSize))
                    } else if let convertStars {
                        let text: String

                        if message.id.peerId == context.peerId {
                            text = strings().notificationStarsGiftSubtitleSelf
                        } else {
                            let displayTitle = message.peers[message.id.peerId]?.compactDisplayTitle ?? ""
                            let convertStarsString = strings().starListItemCountOther(Int(convertStars))

                            if isIncoming {
                                if savedToProfile {
                                    text = strings().starsStarGiftTextKeptOnPageIncoming
                                } else if convertedToStars {
                                    text = strings().starsStarGiftTextConvertedIncoming(convertStarsString)
                                } else {
                                    if let peerId, peerId.namespace == Namespaces.Peer.CloudChannel {
                                        text = strings().starsStarGiftTextIncomingChannel(convertStarsString)
                                    } else {
                                        text = strings().starsStarGiftTextIncoming(convertStarsString)
                                    }
                                }
                            } else {
                                if savedToProfile {
                                    text = strings().starsStarGiftTextKeptOnPageOutgoing(displayTitle)
                                } else if convertedToStars {
                                    text = strings().starsStarGiftTextConvertedOutgoing(displayTitle, convertStarsString)
                                } else {
                                    text = strings().starsStarGiftTextOutgoing(displayTitle, convertStarsString)
                                }
                            }
                        }
                        
                        info.append(string: text, color: grayTextColor, font: .normal(theme.fontSize))
                    }
                    
                    let reference: StarGiftReference
                    if let peerId, let giftMessageId {
                        reference = .message(messageId: EngineMessage.Id(peerId: peerId, namespace: Namespaces.Message.Cloud, id: giftMessageId))
                    } else if let peerId, let savedId {
                        reference = .peer(peerId: peerId, id: savedId)
                    } else {
                        reference = .message(messageId: message.id)
                    }

                    
                    let purpose: Star_TransactionPurpose = .starGift(gift: .generic(gift), convertStars: convertStars, text: text, entities: entities, nameHidden: nameHidden, savedToProfile: savedToProfile, converted: convertedToStars, fromProfile: false, upgraded: upgraded, prepaidUpgradeHash: nil, transferStars: nil, canExportDate: nil, reference:  reference, sender: senderId.flatMap { message.peers[$0].flatMap(EnginePeer.init)}, saverId: savedId, canTransferDate: nil, canResaleDate: nil, dropOriginalDetailsStars: nil, canUpgrade: canUpgrade, number: number, isRefunded: isRefunded, canCraftAt: nil, craftChancePermille: nil, upgradeStars: upgradeStars)
                    
                    let ribbon: ChatServiceItem.GiftData.Ribbon?
                    if let availability = gift.availability {
                        ribbon = .init(color: theme.chatServiceItemColor, text: strings().starTransactionAvailabilityOf(1, Int(availability.total).prettyNumber))
                    } else {
                        ribbon = nil
                    }
                    
                    
                    self.giftData = .init(from: authorId ?? message.id.peerId, to: toPeer?.id ?? message.id.peerId, text: TextViewLayout(header, alignment: .center), info: info.string.isEmpty ? nil : TextViewLayout(info, maximumNumberOfLines: 4, alignment: .center), source: .starGift(amount: isIncoming ? gift.price : -gift.price, date: message.timestamp, from: senderId.flatMap { message.peers[$0].flatMap(EnginePeer.init)} ?? message.author.flatMap { .init($0) }, to: toPeer, purpose: purpose), ribbon: ribbon, uniqueAttributes: nil, giftMessage: nil, authorLayout: authorLayout, author: authorPeer, isPrepaidUpgrade: (upgradeStars ?? 0) > 0 && !upgraded)
                    
                    var finalPrice = gift.price
                    if let upgradeStars, !upgradeSeparate {
                        finalPrice += upgradeStars
                    }

                    let text: String
                    if authorId == context.peerId {
                        if message.id.peerId == context.peerId {
                            text = strings().notificationStarsGiftSelfBought(
                                strings().starListItemCountOther(Int(finalPrice))
                            )
                        } else {
                            if isPrepaidUpgrade, let upgradeStars, let toPeer {
                                let giftValue = strings().starListItemCountOther(Int(upgradeStars))
                                let toPeerName = toPeer._asPeer().compactDisplayTitle

                                if let senderId, let author = message.peers[senderId] {
                                    if senderId == context.peerId {
                                        text = strings().notificationStarsGiftUpgradeToSelf(giftValue, toPeerName)
                                    } else {
                                        let authorName = author.compactDisplayTitle
                                        text = strings().notificationStarsGiftUpgradeFromOther(giftValue, toPeerName, authorName)
                                    }
                                } else {
                                    text = strings().notificationStarsGiftUpgradeGeneric(giftValue, toPeerName)
                                }
                            } else {
                                text = strings().chatServiceStarGiftSentYou(
                                    strings().starListItemCountOther(Int(finalPrice))
                                )
                            }
                        }
                    } else {

                        if auctionAcquired {
                            text = strings().notificationStarsGiftSelfAuctionBought(
                                strings().starListItemCountOther(Int(gift.price)))
                        } else if isPrepaidUpgrade, let upgradeStars {
                            let formattedStars = strings().starListItemCountOther(Int(upgradeStars))

                            if let senderId, let author = message.peers[senderId] {
                                if senderId == context.peerId {
                                    text = strings().chatStarsGiftUpgradeSelf(authorName, formattedStars)
                                } else {
                                    text = strings().chatStarsGiftUpgradeOther(authorName, formattedStars, author.compactDisplayTitle)
                                }
                            } else {
                                text = strings().chatStarsGiftUpgradeSelf(authorName, formattedStars)
                            }
                        } else {
                            if let senderId, let author = message.peers[senderId], let peerId = peerId, let toPeer = message.peers[peerId] {
                                text = strings().chatServiceStarGiftChannelSelt(author.displayTitle, toPeer.displayTitle, strings().starListItemCountOther(Int(finalPrice)))
                            } else {
                                text = strings().chatServiceStarGiftSent(authorName, strings().starListItemCountOther(Int(finalPrice)))
                            }
                        }
                    }
                    let _ =  attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    attributedString.detectBoldColorInString(with: .medium(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }

                case let .starGiftUnique(gift, isUpgrade, isTransferred, savedToProfile, canExportDate, transferStars, refunded, isPrepaidUpgrade, _, senderId, saverId, resaleStars, canTransferDate, canResaleDate, dropOriginalDetailsStars, _, fromOffer, canCraftAt, isCrafted, giftText, giftEntities, nameHidden):


                    let authorPeer: EnginePeer?
                    if let authorId = gift.releasedBy {
                        authorPeer = message.peers[authorId].flatMap(EnginePeer.init)
                    } else {
                        authorPeer = nil
                    }

                    let authorLayout: TextViewLayout?
                    if let authorPeer, let addressName = authorPeer.addressName {
                        authorLayout = TextViewLayout(
                            .initialize(
                                string: strings().starTransactionReleasedBy(addressName),
                                color: grayTextColor,
                                font: .normal(.short)
                            ),
                            maximumNumberOfLines: 1,
                            truncationType: .middle
                        )
                    } else {
                        authorLayout = nil
                    }
                    
                    
                    if case let .unique(gift) = gift {
                        var text: String = ""
                        if let messagePeer = message.peers[message.id.peerId] {
                            let peerName = senderId.flatMap { message.peers[$0]?.displayTitle } ?? messagePeer.compactDisplayTitle
                            let _: [(Int, EnginePeer.Id?)] = [(0, messagePeer.id)]
                            if isCrafted {
                                text = strings().chatServiceCraftedUniqueCollectible
                            } else if let resaleStars {
                                
                                let giftString = "\(gift.title) #\(gift.number)"

                                if fromOffer {
                                    if message.author?.id == context.account.peerId {
                                        text = strings().chatServiceOfferSoldGift(giftString, peerName, resaleStars.fullyFormatted)
                                    } else {
                                        text = strings().chatServiceOfferBoughtGift(giftString, peerName, resaleStars.fullyFormatted)
                                    }
                                } else if message.author?.id == context.account.peerId {
                                    if message.id.peerId == context.account.peerId {
                                        text = strings().chatServiceResaleYouSelf(giftString, resaleStars.fullyFormatted)
                                    } else {
                                        text = strings().chatServiceResaleYou(giftString, resaleStars.fullyFormatted, peerName)
                                    }
                                } else {
                                    text = strings().chatServiceResale(peerName, giftString, resaleStars.fullyFormatted)
                                }
                            } else if isUpgrade {
                                if message.author?.id == context.account.peerId {
                                    if isPrepaidUpgrade {
                                        text = strings().notificationStarsGiftUpgradePrepaidYou(peerName)
                                    } else {
                                        text = strings().notificationStarsGiftUpgradeYou(peerName)
                                    }
                                } else {
                                    if isPrepaidUpgrade {
                                        text = strings().notificationStarsGiftUpgradePrepaid(peerName)
                                    } else if let _ = senderId {
                                        text = strings().notificationStarsGiftUpgradeChannel(peerName)
                                    } else {
                                        text = strings().notificationStarsGiftUpgrade(peerName)
                                    }
                                }
                            } else if isTransferred {
                                if message.author?.id == context.account.peerId {
                                    text = strings().notificationStarsGiftTransferYou
                                } else {
                                    text = strings().notificationStarsGiftTransfer(peerName)
                                }
                            }
                        }
                        
                        
                        let _ =  attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        
                        
                        if let authorId = authorId {
                            let range = attributedString.string.nsstring.range(of: authorName)
                            if range.location != NSNotFound {
                                let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                                attributedString.add(link: link, for: range, color: nameColor(authorId))
                                attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                            }
                        }
                        attributedString.detectBoldColorInString(with: .medium(.text))
                        
                        let purpose: Star_TransactionPurpose = .starGift(gift: .unique(gift), convertStars: nil, text: text, entities: nil, nameHidden: false, savedToProfile: savedToProfile, converted: false, fromProfile: false, upgraded: true, prepaidUpgradeHash: nil, transferStars: transferStars, canExportDate: canExportDate, reference: .message(messageId: message.id), sender: senderId.flatMap { message.peers[$0].flatMap(EnginePeer.init)}, saverId: saverId, canTransferDate: canTransferDate, canResaleDate: canResaleDate, dropOriginalDetailsStars: dropOriginalDetailsStars, canUpgrade: false, number: nil, isRefunded: false, canCraftAt: canCraftAt, craftChancePermille: gift.craftChancePermille, upgradeStars: nil)
                        

                        
                        
                        let toPeer: EnginePeer?
                        if authorId != context.peerId {
                            toPeer = context.myPeer.flatMap { .init($0) }
                        } else {
                            toPeer = message.peers[message.id.peerId].flatMap( { .init($0) })
                        }
                        
                        let info = NSMutableAttributedString()
                        let header = NSMutableAttributedString()
                        
                        if gift.flags.contains(.isBurned) {
                            header.append(string: strings().chatServiceGiftBurnedHeader, color: NSColor.white.withAlphaComponent(0.8), font: .medium(theme.fontSize + 1))
                        } else if isCrafted {
                            header.append(string: strings().chatServiceCraftedGift, color: NSColor.white.withAlphaComponent(0.8), font: .medium(theme.fontSize + 1))
                        } else {
                            if let senderId, let author = message.peers[senderId] {
                                header.append(string: strings().chatServiceStarGiftFrom("\(author.displayTitle)"), color: NSColor.white.withAlphaComponent(0.8), font: .medium(theme.fontSize + 1))
                            } else {
                                if context.peerId == message.author?.id {
                                    header.append(string: strings().chatServiceStarGiftFrom("\(authorName)"), color: NSColor.white.withAlphaComponent(0.8), font: .medium(theme.fontSize + 1))
                                } else {
                                    header.append(string: strings().chatServiceStarGiftFor("\(authorName)"), color: NSColor.white.withAlphaComponent(0.8), font: .medium(theme.fontSize + 1))
                                }
                            }
                        }
                        
                        let senderPeer = senderId.flatMap { message.peers[$0].flatMap(EnginePeer.init) }

                        let giftMessage: GiftData.GiftMessage?
                        if let giftText, !giftText.isEmpty {
                            let messageAttr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: giftEntities ?? [])], for: giftText, message: nil, context: context, fontSize: theme.fontSize, openInfo: { _, _, _, _ in }, textColor: NSColor.white, linkColor: NSColor.white, isDark: theme.colors.isDark, bubbled: true).mutableCopy() as! NSMutableAttributedString
                            InlineStickerItem.apply(to: messageAttr, associatedMedia: message.associatedMedia, entities: giftEntities ?? [], isPremium: context.isPremium)
                            giftMessage = .init(peer: nameHidden ? nil : (senderPeer ?? message.author.flatMap(EnginePeer.init)), text: TextViewLayout(messageAttr))
                        } else {
                            giftMessage = nil
                        }

                        var attributes: [GiftData.UniqueAttributes.Attribute] = []

                        var backdropColor: NSColor?

                        for attribute in gift.attributes {
                            switch attribute {
                            case let .backdrop(_, _, _, outerColor, _, _, _):
                                backdropColor = NSColor(UInt32(outerColor))
                            default:
                                break
                            }
                        }

                        if giftMessage == nil {
                            for attribute in gift.attributes {
                                switch attribute {
                                case let .backdrop(name, _, _, _, _, _, _):
                                    attributes.append(.init(name: .init(.initialize(string: strings().giftUniqueBackdrop, color: NSColor.white.withAlphaComponent(0.8), font: .normal(.text))),
                                                            value: .init(.initialize(string: name, color: NSColor.white, font: .medium(.text)))))
                                case let .model(name, _, _, _):
                                    attributes.append(.init(name: .init(.initialize(string: strings().giftUniqueModel, color: NSColor.white.withAlphaComponent(0.8), font: .normal(.text))),
                                                            value: .init(.initialize(string: name, color: NSColor.white, font: .medium(.text)))))
                                case let .pattern(name, _, _):
                                    attributes.append(.init(name: .init(.initialize(string: strings().giftUniqueSymbol, color: NSColor.white.withAlphaComponent(0.8), font: .normal(.text))),
                                                            value: .init(.initialize(string: name, color: NSColor.white, font: .medium(.text)))))
                                default:
                                    break
                                }
                            }
                        }
                        let ribbon: ChatServiceItem.GiftData.Ribbon?
                        if gift.flags.contains(.isBurned) {
                            ribbon = .init(color: theme.colors.redUI.withMultipliedBrightnessBy(1.1), text: strings().chatServiceGiftRibbonBurned)
                        } else if fromOffer {
                            if !isIncoming {
                                ribbon = .init(color: theme.colors.redUI.withMultipliedBrightnessBy(1.1), text: strings().chatServiceGiftRibbonSold)
                            } else {
                                ribbon = nil
                            }
                        } else {
                            ribbon = .init(color: backdropColor ?? theme.chatServiceItemColor, text: strings().chatServiceGiftRibbonGift)
                        }

                        
                        var uniqueAttributes: GiftData.UniqueAttributes?
                        if !refunded {
                            uniqueAttributes = .init(header: .init(.initialize(string: "\(gift.title) #\(gift.number)", color: NSColor.white.withAlphaComponent(0.8), font: .medium(.header))), attributes: attributes)
                        }
                        
                        
                        if refunded {
                            info.append(string: strings().giftUpgradeRefunded, color: grayTextColor, font: .normal(theme.fontSize))
                        }
                        
                        self.giftData = .init(from: authorId ?? message.id.peerId, to: message.id.peerId, text: TextViewLayout(header, alignment: .center), info: info.string.isEmpty ? nil : TextViewLayout(info, maximumNumberOfLines: 4, alignment: .center), source: .starGift(amount: 0, date: message.timestamp, from: senderPeer ?? message.author.flatMap(EnginePeer.init), to: toPeer, purpose: purpose), ribbon: ribbon, uniqueAttributes: uniqueAttributes, giftMessage: giftMessage, authorLayout: authorLayout, author: authorPeer, isPrepaidUpgrade: false)

                    } else if refunded, let gift = gift.generic {
                        let toPeer: EnginePeer?
                        if authorId != context.peerId {
                            toPeer = context.myPeer.flatMap { .init($0) }
                        } else {
                            toPeer = message.peers[message.id.peerId].flatMap( { .init($0) })
                        }

                        let info = NSMutableAttributedString()
                        let header = NSMutableAttributedString()

                        if let senderId, let author = message.peers[senderId] {
                            header.append(string: strings().chatServiceStarGiftFrom("\(author.displayTitle)"), color: grayTextColor, font: .medium(theme.fontSize + 1))
                        } else if context.peerId == message.author?.id {
                            header.append(string: strings().chatServiceStarGiftFrom("\(authorName)"), color: grayTextColor, font: .medium(theme.fontSize + 1))
                        } else {
                            header.append(string: strings().chatServiceStarGiftFor("\(authorName)"), color: grayTextColor, font: .medium(theme.fontSize + 1))
                        }

                        info.append(string: strings().chatServiceStarGiftRefunded, color: grayTextColor, font: .normal(theme.fontSize))

                        let purpose: Star_TransactionPurpose = .starGift(gift: .generic(gift), convertStars: nil, text: nil, entities: nil, nameHidden: false, savedToProfile: savedToProfile, converted: false, fromProfile: false, upgraded: false, prepaidUpgradeHash: nil, transferStars: nil, canExportDate: nil, reference: .message(messageId: message.id), sender: senderId.flatMap { message.peers[$0].flatMap(EnginePeer.init)}, saverId: saverId, canTransferDate: nil, canResaleDate: nil, dropOriginalDetailsStars: nil, canUpgrade: false, number: nil, isRefunded: true, canCraftAt: nil, craftChancePermille: nil, upgradeStars: nil)

                        self.giftData = .init(from: authorId ?? message.id.peerId, to: message.id.peerId, text: TextViewLayout(header, alignment: .center), info: TextViewLayout(info, maximumNumberOfLines: 4, alignment: .center), source: .starGift(amount: 0, date: message.timestamp, from: senderId.flatMap { message.peers[$0].flatMap(EnginePeer.init)} ?? message.author.flatMap { .init($0) }, to: toPeer, purpose: purpose), ribbon: nil, uniqueAttributes: nil, giftMessage: nil, authorLayout: authorLayout, author: authorPeer, isPrepaidUpgrade: false)
                    }
                case let .paidMessagesRefunded(_, stars):
                    let starsString = strings().starListItemCountOther(Int(stars))
                    let text: String
                    
                    
                    let toPeer: Peer?
                    if authorId != context.peerId {
                        toPeer = context.myPeer
                    } else {
                        toPeer = message.peers[message.id.peerId]
                    }
                    
                    if authorId == context.peerId {
                        text = strings().notificationPaidMessageRefundYou(starsString, toPeer?.compactDisplayTitle ?? authorName)
                    } else {
                        text = strings().notificationPaidMessageRefund(toPeer?.compactDisplayTitle ?? authorName, starsString)
                    }
                    
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))

                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case .paidMessagesPriceEdited(let stars, _):
                    let starsString = strings().starListItemCountOther(Int(stars))
                    let text: String
                    if authorId == context.peerId {
                        text = strings().notificationPaidMessagePriceChangedYou(starsString)
                    } else {
                        text = strings().notificationPaidMessagePriceChanged(authorName, starsString)
                    }
                    
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .todoCompletions(completed, incompleted):
                    
                    let todo: Message?
                    if let replyAttribute = message.replyAttribute {
                        todo = message.associatedMessages[replyAttribute.messageId]
                    } else {
                        todo = nil
                    }
                    
                    guard let todo, let todoMedia = todo.media.first as? TelegramMediaTodo else {
                        break
                    }
                    
                    let marked = !completed.isEmpty ? todoMedia.items.filter({ completed.contains($0.id) }) : todoMedia.items.filter({ incompleted.contains($0.id) })

                    
                    let makeValues: ([TelegramMediaTodo.Item]) -> (String, [MessageTextEntity]) = { items in
                        var resultString = ""
                        var entities: [MessageTextEntity] = []
                        var offset = 0

                        for (index, item) in items.enumerated() {
                            resultString += "'"
                            offset += 1

                            for entity in item.entities {
                                let adjustedRange = (entity.range.lowerBound + offset)..<(entity.range.upperBound + offset)
                                entities.append(MessageTextEntity(range: adjustedRange, type: entity.type))
                            }

                            resultString += item.text
                            offset += item.text.count

                            resultString += "'"
                            offset += 1

                            if index < items.count - 1 {
                                resultString += ", "
                                offset += 2
                            }
                        }

                        return (resultString, entities)
                    }

                    var rawString: String

                                
                    if !completed.isEmpty {
                        if authorId == context.peerId {
                            rawString = strings().chatServiceTodoMarkedDoneYou
                        } else {
                            rawString = strings().chatServiceTodoMarkedDone
                        }
                    } else if !incompleted.isEmpty {
                        if authorId == context.peerId {
                            rawString = strings().chatServiceTodoMarkedUndoneYou
                        } else {
                            rawString = strings().chatServiceTodoMarkedUndone
                        }
                    } else {
                        rawString = ""
                    }
                    
                    if !rawString.isEmpty {
                        
                        let values = makeValues(marked)
                        
                        let valuesRange = rawString.nsstring.range(of: "{values}")
                        let valuesLength = values.0.length
                        if valuesRange.location != NSNotFound {
                            rawString = rawString.nsstring.replacingCharacters(in: valuesRange, with: values.0)
                        }
                        let authorRange = rawString.nsstring.range(of: "{author}")
                        if authorRange.location != NSNotFound {
                            rawString = rawString.nsstring.replacingCharacters(in: authorRange, with: authorName)
                        }
                        
                        var offset = valuesRange.location
                        if authorRange.location != NSNotFound {
                            offset += (authorName.length - authorRange.length)
                        }
                        
                        var entities: [MessageTextEntity] = []
                        
                        for entity in values.1 {
                            entities.append(.init(range: entity.range.lowerBound + offset ..< entity.range.upperBound + offset, type: entity.type))
                        }
                        
                        let _ = attributedString.append(string: rawString, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                        
                        InlineStickerItem.apply(to: attributedString, associatedMedia: [:], entities: entities, isPremium: context.isPremium)
                        
                        if valuesRange.location != NSNotFound {
                            let range = NSMakeRange(offset, valuesLength)
                            attributedString.add(link: LinkHooks.shared.callbackLink("", { [weak chatInteraction] _ in
                                chatInteraction?.focusMessageId(nil, .init(messageId: todo.id, string: nil), .CenterEmpty)
                            }), for: range, color: grayTextColor)
                            attributedString.addAttribute(NSAttributedString.Key.font, value: NSFont.medium(theme.fontSize), range: range)
                        }

                    }
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .todoAppendTasks(tasks):
                    let todo: Message?
                    if let replyAttribute = message.replyAttribute {
                        todo = message.associatedMessages[replyAttribute.messageId]
                    } else {
                        todo = nil
                    }

                    guard let todo, let todoMedia = todo.media.first as? TelegramMediaTodo else {
                        break
                    }

                    let makeValues: ([TelegramMediaTodo.Item]) -> (String, [MessageTextEntity]) = { items in
                        var resultString = ""
                        var entities: [MessageTextEntity] = []
                        var offset = 0

                        for (index, item) in items.enumerated() {
                            resultString += "'"
                            offset += 1

                            for entity in item.entities {
                                let adjustedRange = (entity.range.lowerBound + offset)..<(entity.range.upperBound + offset)
                                entities.append(MessageTextEntity(range: adjustedRange, type: entity.type))
                            }

                            resultString += item.text
                            offset += item.text.count

                            resultString += "'"
                            offset += 1

                            if index < items.count - 1 {
                                resultString += ", "
                                offset += 2
                            }
                        }

                        return (resultString, entities)
                    }

                    let isMultiple = tasks.count > 1
                    var rawString: String

                    if authorId == context.peerId {
                        rawString = isMultiple ? strings().chatServiceTodoAddedMultiYou : strings().chatServiceTodoAddedYou
                    } else {
                        rawString = isMultiple ? strings().chatServiceTodoAddedMulti : strings().chatServiceTodoAdded
                    }

                    if !rawString.isEmpty {
                        let values = makeValues(tasks)
                        let valuesRange = rawString.nsstring.range(of: "{values}")
                        let valuesLength = values.0.length
                        if valuesRange.location != NSNotFound {
                            rawString = rawString.nsstring.replacingCharacters(in: valuesRange, with: values.0)
                        }

                        let authorRange = rawString.nsstring.range(of: "{author}")
                        if authorRange.location != NSNotFound {
                            rawString = rawString.nsstring.replacingCharacters(in: authorRange, with: authorName)
                        }

                        let taskTitle = "'\(todoMedia.text)'"
                        let taskRange = rawString.nsstring.range(of: "{task}")
                        if taskRange.location != NSNotFound {
                            rawString = rawString.nsstring.replacingCharacters(in: taskRange, with: taskTitle)
                        }

                        var offset = valuesRange.location
                        if authorRange.location != NSNotFound {
                            offset += (authorName.length - authorRange.length)
                        }
                        

                        var entities: [MessageTextEntity] = []
                        for entity in values.1 {
                            entities.append(.init(range: entity.range.lowerBound + offset ..< entity.range.upperBound + offset, type: entity.type))
                        }

                        let _ = attributedString.append(string: rawString, color: grayTextColor, font: NSFont.normal(theme.fontSize))

                        InlineStickerItem.apply(to: attributedString, associatedMedia: [:], entities: entities, isPremium: context.isPremium)

                        if valuesRange.location != NSNotFound {
                            let range = NSMakeRange(offset, valuesLength)
                            attributedString.add(link: LinkHooks.shared.callbackLink("", { [weak chatInteraction] _ in
                                chatInteraction?.focusMessageId(nil, .init(messageId: todo.id, string: nil), .CenterEmpty)
                            }), for: range, color: grayTextColor)
                            attributedString.addAttribute(NSAttributedString.Key.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }

                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .suggestedPostApprovalStatus(status):
                    
                    var peer: Peer = peer
                    if let monoforumId = (peer as? TelegramChannel)?.linkedMonoforumId {
                        peer = message.peers[monoforumId] ?? peer
                    }
                    
                    let postId: MessageId?
                    if let replyAttribute = message.replyAttribute {
                        postId = replyAttribute.messageId
                    } else {
                        postId = nil
                    }
                    
                    self.suggestPostStatus = SuggestPostData(status: status, messageId: postId, peer: peer, isIncoming: isIncoming)
                case let .giftTon(currency, amount, cryptoCurrency, cryptoAmount, transactionId):
                    
                    let cryptoAmount = cryptoAmount ?? 0
                    
                    let info = NSMutableAttributedString()
                    let header = NSMutableAttributedString()
                    let formatted: String
                    if let cryptoCurrency {
                        formatted = formatCurrencyAmount(cryptoAmount, currency: cryptoCurrency).prettyCurrencyNumberUsd + " " + cryptoCurrency
                    } else {
                        formatted = formatCurrencyAmount(amount, currency: currency)
                    }
                    
                    header.append(string: formatted, color: grayTextColor, font: .medium(theme.fontSize + 1))
                    
                    
                    _ = info.append(
                        string: strings().chatServiceTonGiftInfo,
                        color: grayTextColor,
                        font: .normal(theme.fontSize)
                    )
                    info.detectBoldColorInString(with: .medium(theme.fontSize))
                    
                    
                    self.giftData = .init(from: authorId ?? message.id.peerId, to: message.id.peerId, text: TextViewLayout(header, alignment: .center), info: TextViewLayout(info, alignment: .center), source: .ton(amount: isIncoming ? cryptoAmount : -cryptoAmount, date: message.timestamp, transactionId: transactionId, peer: isIncoming ? message.author.flatMap(EnginePeer.init) : message.peers[message.id.peerId].flatMap(EnginePeer.init)), ribbon: nil, uniqueAttributes: nil, giftMessage: nil, authorLayout: nil, author: nil, isPrepaidUpgrade: false)
                    
                    
                    let text: String
                    if authorId == context.peerId {
                        text = strings().chatServicePremiumGiftSentYou(formatCurrencyAmount(amount, currency: currency))
                    } else {
                        if authorId == servicePeerId {
                            text = strings().chatServicePremiumGiftSent(strings().chatServicePremiumUnknown, formatCurrencyAmount(amount, currency: currency))
                        } else {
                            text = strings().chatServicePremiumGiftSent(authorName, formatCurrencyAmount(amount, currency: currency))
                        }
                    }
                    let _ =  attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .walletTonConnectRequest(flags, sessionId, _, _, _, dappName):
                    let text: String
                    if flags & (1 << 3) != 0 {
                        text = dappName.map { strings().chatServiceItemWalletRequestFromDeclined($0) } ?? strings().chatServiceItemWalletRequestDeclined
                    } else if flags & (1 << 2) != 0 {
                        text = dappName.map { strings().chatServiceItemWalletRequestFromAccepted($0) } ?? strings().chatServiceItemWalletRequestAccepted
                    } else {
                        text = dappName.map { strings().chatServiceItemWalletRequestFrom($0) } ?? strings().chatServiceItemWalletRequest
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    let servicePeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))
                    let messageId = message.id
                    if #available(macOS 10.15, *), messageId.namespace == Namespaces.Message.Cloud, messageId.peerId == servicePeerId, message.author?.id == servicePeerId, isIncoming {
                        let link = ChatHistoryLink.code(text, { _ in
                            ChatHistoryUIHooks.shared.walletHooks.walletContext(context)?.openChatTonConnectRequest(sessionId: sessionId, messageId: messageId)
                        })
                        attributedString.add(link: link, for: NSMakeRange(0, attributedString.length), color: grayTextColor)
                    }
                case let .gramTransfer(amount, peerAddress, transactionId, comment, commentEncrypted):
                    let conversationPeer = message.peers[message.id.peerId]
                    let isUnknownSender = message.id.peerId == servicePeerId
                    let peerName = conversationPeer?.compactDisplayTitle ?? authorName
                    let amountText = formatGramsText(amount, maxDecimalPositions: 3)
                    let text: String
                    if isIncoming && isUnknownSender {
                        text = strings().chatServiceItemGramTransferUnknown(amountText)
                    } else if isIncoming {
                        text = strings().chatServiceItemGramTransfer(peerName, amountText)
                    } else {
                        text = strings().chatServiceItemGramTransferYou(peerName, amountText)
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    if let conversationPeer {
                        let range = attributedString.string.nsstring.range(of: peerName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: conversationPeer.id, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(conversationPeer.id))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    let amountRange = attributedString.string.nsstring.range(of: amountText, options: .backwards)
                    if amountRange.location != NSNotFound {
                        attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: amountRange)
                    }
                    let fiatText: String?
                    if let fiat = entry.additionalData.walletFiatRate {
                        fiatText = formatTonFiatValue(amount, rate: fiat.unitsPerGram, currencySymbol: fiat.currencySymbol)
                    } else if #available(macOS 10.15, *), let fiat = ChatHistoryUIHooks.shared.walletHooks.walletContext(context)?.chatFiatRate {
                        fiatText = formatTonFiatValue(amount, rate: fiat.unitsPerGram, currencySymbol: fiat.currencySymbol)
                    } else if let rate = context.appConfiguration.data?["ton_usd_rate"] as? Double, rate.isFinite, rate > 0 {
                        fiatText = formatTonUsdValue(amount, rate: rate)
                    } else {
                        fiatText = nil
                    }
                    if let fiatText {
                        let _ = attributedString.append(string: strings().chatServiceItemGramTransferFiat(fiatText), color: grayTextColor, font: NSFont.normal(theme.fontSize))
                    }
                    let trimmedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let pendingAttribute = message.attributes.first { $0 is PendingWalletTransferMessageAttribute } as? PendingWalletTransferMessageAttribute
                    self.walletTransferData = WalletTransferData(
                        amount: amount,
                        isIncoming: isIncoming,
                        transactionId: transactionId,
                        comment: trimmedComment?.isEmpty == false ? trimmedComment : nil,
                        commentEncrypted: commentEncrypted,
                        peer: conversationPeer.flatMap(EnginePeer.init),
                        peerAddress: peerAddress,
                        name: isUnknownSender ? strings().chatServiceItemUnknownUser : peerName,
                        operationId: pendingAttribute?.operationId,
                        pendingTransactionId: pendingAttribute?.transactionId,
                        textColor: grayTextColor
                    )
                case let .suggestedPostSuccess(amount):
                    var isUser = true
                    var channelName: String = ""
                    if let peer = message.peers[message.id.peerId] as? TelegramChannel {
                        channelName = peer.title
                        if peer.isMonoForum, let linkedMonoforumId = peer.linkedMonoforumId, let mainChannel = message.peers[linkedMonoforumId] as? TelegramChannel, mainChannel.hasPermission(.manageDirect) {
                            isUser = false
                        }
                    }
                    let _ = isUser
                    
                    let amountString: String = amount.fullyFormatted
                    
                    attributedString.append(string: strings().chatServiceSuggestPostSuccessReceived(channelName, amountString), color: grayTextColor, font: .normal(.text))
                case let .suggestedPostRefund(info):
                    var isUser = true
                    if let peer = message.peers[message.id.peerId] as? TelegramChannel {
                        if peer.isMonoForum, let linkedMonoforumId = peer.linkedMonoforumId, let mainChannel = message.peers[linkedMonoforumId] as? TelegramChannel, mainChannel.hasPermission(.manageDirect) {
                            isUser = false
                        }
                    }
                    let text: String
                    if info.isUserInitiated {
                        if isUser {
                            text = strings().chatServiceSuggestPostRefundedUser
                        } else {
                            text = strings().chatServiceSuggestPostRefundedOther
                        }
                    } else {
                        text = strings().chatServiceSuggestPostRefundedDeleted
                    }
                    attributedString.append(string: text, color: grayTextColor, font: .normal(.text))
                case let .suggestedBirthday(birthday):
                    
                    let text: String
                    if isIncoming {
                        text = strings().chatServiceBirthdaySuggestedToYou(authorName)
                    } else if let peer = message.peers[message.id.peerId] {
                        text = strings().chatServiceBirthdaySuggestedToOther(peer.compactDisplayTitle)
                    } else {
                        text = ""
                    }

                    self.suggestBirthdayData = .init(text: .init(.initialize(string: text, color: grayTextColor, font: .normal(.text)), alignment: .center), birthday: birthday, isIncoming: isIncoming)
                case let .communityChanged(communityId):
                    if let communityId = communityId, let community = message.peers[communityId] as? TelegramCommunity {
                        let addedPeer = message.peers[message.id.peerId]
                        let text: String
                        if let user = addedPeer as? TelegramUser, user.botInfo != nil {
                            text = strings().chatServiceBotAddedToCommunity(community.title)
                        } else if let channel = addedPeer as? TelegramChannel, case .broadcast = channel.info {
                            text = strings().chatServiceChannelAddedToCommunity(community.title)
                        } else if authorId == context.peerId {
                            text = strings().chatServiceYouAddedGroup(community.title)
                        } else {
                            text = strings().chatServiceAddedGroup(authorName, community.title)
                        }
                        self.communityChangedData = .init(text: .init(.initialize(string: text, color: grayTextColor, font: .normal(.text)), alignment: .center), communityId: communityId)
                    }
                case .joinedViaCommunity:
                    let text: String
                    if authorId == context.peerId {
                        text = strings().textUtilsJoinedViaCommunityYou
                    } else {
                        text = strings().textUtilsJoinedViaCommunity(authorName)
                    }
                    let _ = attributedString.append(string: text, color: grayTextColor, font: .normal(theme.fontSize))
                    if let authorId = authorId, authorId != context.peerId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: grayTextColor)
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case let .starGiftPurchaseOfferDeclined(gift, amount, hasExpired):
                    if let gift = gift.unique {
                        let text: String
                        let giftString = "\(gift.title) #\(gift.number)"
                        let peerName = message.peers[message.id.peerId]?.compactDisplayTitle ?? ""
                        if hasExpired {
                            if !isIncoming {
                                text = strings().chatServiceGiftOfferExpiredOutgoing(peerName, giftString, amount.fullyFormatted)
                            } else {
                                text = strings().chatServiceGiftOfferExpiredIncoming(peerName, giftString, amount.fullyFormatted)
                            }
                        } else {
                            if !isIncoming {
                                text = strings().chatServiceGiftOfferRejectedOutgoing(peerName, giftString, amount.fullyFormatted)
                            } else {
                                text = strings().chatServiceGiftOfferRejectedIncoming(peerName, giftString, amount.fullyFormatted)
                            }
                        }
                        
                        attributedString.append(string: text, color: grayTextColor, font: .normal(.text))
                                                
                    }
                    
                case let .starGiftPurchaseOffer(gift, amount, expireDate, isAccepted, isDeclined):
                    if let gift = gift.unique {
                        let text: String
                        let info: String
                        let giftString = "\(gift.title) #\(gift.number)"
                        let peerName = message.peers[message.id.peerId]?.compactDisplayTitle ?? ""

                        if isIncoming {
                            text = strings().chatServiceOfferReceivedOffer(peerName, amount.fullyFormatted, giftString)
                        } else {
                            text = strings().chatServiceOfferSentOffer(amount.fullyFormatted, peerName, giftString)
                        }

                        let isActive: Bool = !isAccepted && !isDeclined && expireDate > context.timestamp && isIncoming

                        if isAccepted {
                            info = strings().chatServiceOfferAccepted

                        } else if isDeclined {
                            info = strings().chatServiceOfferRejected
                        } else if expireDate < context.timestamp {
                            info = strings().chatServiceOfferExpired
                        } else {
                            info = strings().chatServiceOfferExpiresIn(timerText(Int(expireDate - context.timestamp)))
                        }
                        if let authorPeer = message.author {
                            
                            
                            let textLayout = TextViewLayout(.initialize(string: text, color: grayTextColor, font: .normal(.text)).detectBold(with: .medium(.text)), alignment: .center)
                            
                            let infoLayout = TextViewLayout(.initialize(string: info, color: grayTextColor, font: .normal(.short)).detectBold(with: .medium(.text)), alignment: .center)

                            self.offerData = .init(context: context, message: message, receiver: .init(authorPeer), amount: amount, gift: gift, text: textLayout, info: infoLayout, isActive: isActive, theme: theme, accept: {
                                let giftString = "\(gift.title) #\(gift.number)"

                                let comission: Double = context.marketComission(amount.currency)
                                let receiveAmount = ChatHistoryUIHooks.shared.currencyAmount(context, amount, comission)

                                var priceFooter: ModalAlertData.Footer? = nil
                                
                                if let valueAmount = gift.valueUsdAmount {
                                    let usd_rate: Double
                                    let offerUsdValue: Double
                                    let giftUsdValue = Double(valueAmount) / 100.0

                                    switch amount.currency {
                                    case .ton:
                                        usd_rate = context.appConfiguration.getGeneralValueDouble("ton_usd_rate", orElse: 3)
                                        offerUsdValue = Double(amount.amount.value) / 1_000_000_000 * usd_rate
                                    case .stars:
                                        usd_rate = context.appConfiguration.getGeneralValueDouble("star_usd_rate", orElse: 0.013)
                                        offerUsdValue = Double(amount.amount.value) * usd_rate
                                    }
                                    
                                    let fraction = giftUsdValue / offerUsdValue
                                    let percentage = Int(fraction * 100) - 100

                                    var text: String?
                                    var color: NSColor?
                                    if percentage > 20 {
                                        text = strings().chatServiceGiftOfferValueHigher("\(percentage)" + "%")
                                        color = theme.colors.redUI
                                    } else if percentage < -20, context.debug {
                                        text = strings().chatServiceGiftOfferValueLower("\(abs(percentage))" + "%")
                                        color = theme.colors.greenUI
                                    }
                                    if let text, let color {
                                        priceFooter = .init(id: "priceFooter", value: { initialSize, stableId, theme, _ in
                                            return GeneralTextRowItem(initialSize, text: .initialize(string: text, color: color, font: .normal(.text)).detectBold(with: .medium(.text)), viewType: .modern(position: .inner, insets: NSEdgeInsets(top: 10)))
                                        })
                                    }
                                }
                                
                                let data = ModalAlertData(title: nil, info: strings().chatServiceOfferConfirmSale(giftString, authorPeer.compactDisplayTitle, amount.fullyFormatted, receiveAmount.fullyFormatted), description: nil, ok: strings().chatServiceOfferConfirmSaleOk, options: [], mode: .confirm(text: strings().modalCancel, isThird: false), header: .init(id: "header", value: { initialSize, stableId, presentation in
                                    return TransferUniqueGiftHeaderItem(initialSize, stableId: stableId, gift: gift, toPeer: .init(authorPeer), context: context)
                                }), footer: ModalAlertData.Footer(id: "footer", value: { initialSize, stableId, presentation, action in
                                    return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: getTransferAttributesRows(gift: gift, includeValue: false), context: context)
                                }), footer1: priceFooter)
                                
                                showModalAlert(for: context.window, data: data, completion: { result in
                                    _ = showModalProgress(signal: context.engine.payments.resolveStarGiftOffer(messageId: message.id, accept: true), for: context.window).startStandalone()
                                })
                            }, reject: {
                                verifyAlert(for: context.window, information: strings().chatServiceOfferRejectConfirm, ok: strings().chatServiceOfferReject, successHandler: { _ in
                                    _ = showModalProgress(signal: context.engine.payments.resolveStarGiftOffer(messageId: message.id, accept: false), for: context.window).startStandalone()
                                })
                            })
                        }
                        
                    }
                case let .groupCreatorChange(groupCreatorChange):
                    var targetName = ""
                    if let peer = message.peers[groupCreatorChange.targetPeerId] {
                        targetName = peer.displayTitle
                    }
                    let text: String
                    switch groupCreatorChange.kind {
                    case .pending:
                        text = strings().notificationGroupCreatorChangePending(authorName, targetName)
                    case .applied:
                        text = strings().notificationGroupCreatorChangeApplied(authorName, targetName)
                    }
                    attributedString.append(string: text, color: grayTextColor, font: .normal(.text))
                    
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    let range = attributedString.string.nsstring.range(of: targetName)
                    if range.location != NSNotFound {
                        let link = ChatHistoryLink.peerInfo(link: "", peerId: groupCreatorChange.targetPeerId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                        attributedString.add(link: link, for: range, color: nameColor(groupCreatorChange.targetPeerId))
                        attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                    }
                case let .copyProtectionToggle(_, newValue):
                    let name = authorId == context.peerId ? strings().chatServiceYou : authorName
                    if newValue {
                        let _ = attributedString.append(string: strings().chatServiceCopyProtectionSharingDisabled(name), color: grayTextColor, font: .normal(theme.fontSize))
                    } else {
                        let _ = attributedString.append(string: strings().chatServiceCopyProtectionSharingEnabled(name), color: grayTextColor, font: .normal(theme.fontSize))
                    }
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: name)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId:authorId, action:nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                case .noPaidMessagesTokenUsed:
                    let peerName = message.peers[message.id.peerId]?.compactDisplayTitle ?? ""
                    let serviceText = noPaidMessagesTokenUsedText(peerName: peerName, isAuthor: authorId == context.peerId)
                    let _ = attributedString.append(string: serviceText.text, color: grayTextColor, font: .normal(theme.fontSize))
                    if serviceText.peerRange.location != NSNotFound, serviceText.peerRange.length > 0 {
                        let link = ChatHistoryLink.peerInfo(link: "", peerId: message.id.peerId, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                        attributedString.add(link: link, for: serviceText.peerRange, color: grayTextColor)
                        attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: serviceText.peerRange)
                    }
                case let .managedBotCreated(botId):
                    let botName = message.peers[botId]?.displayTitle ?? ""
                    let _ = attributedString.append(string: strings().chatServiceManagedBotCreated(authorName, botName), color: grayTextColor, font: .normal(theme.fontSize))
                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    let botRange = attributedString.string.nsstring.range(of: botName)
                    if botRange.location != NSNotFound {
                        let link = ChatHistoryLink.peerInfo(link: "", peerId: botId, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                        attributedString.add(link: link, for: botRange, color: nameColor(botId))
                        attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: botRange)
                    }
                case let .pollOptionAppended(option):
                    let pollMessage: Message?
                    if let replyAttribute = message.replyAttribute {
                        pollMessage = message.associatedMessages[replyAttribute.messageId]
                    } else {
                        pollMessage = nil
                    }

                    let optionText = "'\(option.text)'"
                    let _ = attributedString.append(string: strings().chatServicePollOptionAppended(authorName, optionText), color: grayTextColor, font: .normal(theme.fontSize))

                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    if let pollMessage = pollMessage {
                        let optionRange = attributedString.string.nsstring.range(of: optionText)
                        if optionRange.location != NSNotFound {
                            attributedString.add(link: LinkHooks.shared.callbackLink("", { [weak chatInteraction] _ in
                                chatInteraction?.focusMessageId(nil, .init(messageId: pollMessage.id, string: nil, pollOptionId: option.opaqueIdentifier), .CenterEmpty)
                            }), for: optionRange, color: grayTextColor)
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: optionRange)
                        }
                    }
                case let .pollOptionDeleted(option):
                    let pollMessage: Message?
                    if let replyAttribute = message.replyAttribute {
                        pollMessage = message.associatedMessages[replyAttribute.messageId]
                    } else {
                        pollMessage = nil
                    }

                    let optionText = "'\(option.text)'"
                    let _ = attributedString.append(string: strings().chatServicePollOptionDeleted(authorName, optionText), color: grayTextColor, font: .normal(theme.fontSize))

                    if let authorId = authorId {
                        let range = attributedString.string.nsstring.range(of: authorName)
                        if range.location != NSNotFound {
                            let link = ChatHistoryLink.peerInfo(link: "", peerId: authorId, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo)
                            attributedString.add(link: link, for: range, color: nameColor(authorId))
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: range)
                        }
                    }
                    if let pollMessage = pollMessage {
                        let optionRange = attributedString.string.nsstring.range(of: optionText)
                        if optionRange.location != NSNotFound {
                            attributedString.add(link: LinkHooks.shared.callbackLink("", { [weak chatInteraction] _ in
                                chatInteraction?.focusMessageId(nil, .init(messageId: pollMessage.id, string: nil), .CenterEmpty)
                            }), for: optionRange, color: grayTextColor)
                            attributedString.addAttribute(.font, value: NSFont.medium(theme.fontSize), range: optionRange)
                        }
                    }
                case let .copyProtectionRequest(hasExpired, _, newValue):

                    let expirePeriod = context.appConfiguration.getGeneralValue("no_forwards_request_expire_period", orElse: 86400)
                    let isTimedOut = message.timestamp + expirePeriod < context.timestamp

                    
                    if hasExpired || isTimedOut {
                        let _ = attributedString.append(string: strings().chatServiceCopyProtectionRequestExpired, color: grayTextColor, font: .normal(theme.fontSize))
                    } else {
                        let name = authorId == context.peerId ? strings().chatServiceYou : authorName
                        let headerText = newValue ? strings().chatServiceCopyProtectionWouldLikeDisableIncludes(name) : strings().chatServiceCopyProtectionWouldLikeEnableIncludes(name)

                        let headerAttr = NSMutableAttributedString()
                        let _ = headerAttr.append(string: headerText, color: grayTextColor, font: .normal(.text))
                        if authorId != nil {
                            let range = headerAttr.string.nsstring.range(of: name)
                            if range.location != NSNotFound {
                                headerAttr.addAttribute(.font, value: NSFont.medium(.text), range: range)
                            }
                        }
                        let textLayout = TextViewLayout(headerAttr, alignment: .center)

                        let itemStrings = [
                            strings().chatServiceCopyProtectionForwardingMessages,
                            strings().chatServiceCopyProtectionSavingPhotosVideos,
                            strings().chatServiceCopyProtectionCopyingMessages,
                            strings().chatServiceCopyProtectionTakingScreenshots
                        ]
                        let itemLayouts: [TextViewLayout] = itemStrings.map { text in
                            let attr = NSMutableAttributedString()
                            let _ = attr.append(string: text, color: grayTextColor, font: .normal(.text))
                            return TextViewLayout(attr, alignment: .left)
                        }


                        let isOutgoing = authorId == context.peerId
                        let isActive = !isTimedOut && !isOutgoing

                        self.copyProtectionRequestData = .init(text: textLayout, items: itemLayouts, isActive: isActive, theme: theme, context: context, accept: {
                            _ = (context.engine.peers.toggleMessageCopyProtection(peerId: message.id.peerId, enabled: newValue, requestMessageId: message.id) |> deliverOnMainQueue).start(next: { result in
                                switch result {
                                case .applied:
                                    showModalText(for: context.window, text: newValue ? strings().chatServiceCopyProtectionSharingDisabledToast : strings().chatServiceCopyProtectionSharingEnabledToast)
                                case .requested:
                                    showModalText(for: context.window, text: newValue ? strings().chatServiceCopyProtectionSharingWillBeDisabled : strings().chatServiceCopyProtectionSharingWillBeEnabled)
                                }
                            })
                        }, reject: {
                            _ = (context.engine.peers.toggleMessageCopyProtection(peerId: message.id.peerId, enabled: !newValue, requestMessageId: message.id) |> deliverOnMainQueue).start(next: { result in
                                switch result {
                                case .applied:
                                    showModalText(for: context.window, text: !newValue ? strings().chatServiceCopyProtectionSharingDisabledToast : strings().chatServiceCopyProtectionSharingEnabledToast)
                                case .requested:
                                    showModalText(for: context.window, text: !newValue ? strings().chatServiceCopyProtectionSharingWillBeDisabled : strings().chatServiceCopyProtectionSharingWillBeEnabled)
                                }
                            })
                        })
                    }
                default:
                    break
                }
            }
        } else if let media = message.media[0] as? TelegramMediaExpiredContent {
            let text:String
            switch media.data {
            case .image:
                text = strings().serviceMessageExpiredPhoto
            case .file:
                if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    text = strings().serviceMessageExpiredVideo
                } else {
                    text = strings().serviceMessageExpiredVideo
                }
            case .voiceMessage:
                text = strings().serviceMessageExpiredVoiceMessage
            case .videoMessage:
                text = strings().serviceMessageExpiredVideoMessage
            }
            _ = attributedString.append(string: text, color: grayTextColor, font: .normal(theme.fontSize))
            
        } else if message.id.peerId.namespace == Namespaces.Peer.CloudUser, message.autoremoveAttribute != nil || message.autoclearTimeout != nil {
            let isPhoto: Bool = message.anyMedia is TelegramMediaImage
            if authorId == context.peerId {
                _ = attributedString.append(string: isPhoto ? strings().serviceMessageDesturctingPhotoYou(authorName) : strings().serviceMessageDesturctingVideoYou(authorName), color: grayTextColor, font: .normal(theme.fontSize))
            } else if let _ = authorId {
                _ = attributedString.append(string:  isPhoto ? strings().serviceMessageDesturctingPhoto(authorName) : strings().serviceMessageDesturctingVideo(authorName), color: grayTextColor, font: .normal(theme.fontSize))
            }
        } else if let story = message.media.first as? TelegramMediaStory {
            
            if message.isExpiredStory {
                if isIncoming {
                    _ = attributedString.append(string:  strings().chatServiceStoryExpiredMentionTextIncoming, color: grayTextColor, font: .normal(theme.fontSize))
                } else {
                    var name: String = ""
                    if let displayTitle = message.peers[message.id.peerId]?.compactDisplayTitle {
                        name = displayTitle
                    }
                    _ = attributedString.append(string:  strings().chatServiceStoryExpiredMentionTextOutgoing(name), color: grayTextColor, font: .normal(theme.fontSize))
                }
                
                attributedString.insert(.initialize(string: clown, color: grayTextColor, font: .normal(theme.fontSize)), at: 0)
                let file = LocalAnimatedSticker.expired_story.monochromeFile
                
                attributedString.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .attribute(.init(fileId: file.fileId.id, file: file, emoji: clown))), range: NSMakeRange(0, 2))

                
            } else if let item = message.associatedStories[story.storyId]?.get(Stories.StoredItem.self), let peer = message.author, let peerReference = PeerReference(peer) {
                let info = NSMutableAttributedString()
                
                let text: String
                
                var authorName: String = ""
                if let displayTitle = message.peers[message.id.peerId]?.compactDisplayTitle {
                    authorName = displayTitle
                }
                
                if isIncoming {
                    text = strings().chatServiceStoryMentioned(authorName)
                } else {
                    text = strings().chatServiceStoryMentionedYou(authorName)
                }
                
                _ = info.append(string: text, color: grayTextColor, font: .normal(theme.fontSize))
                info.detectBoldColorInString(with: .medium(theme.fontSize))
                
                self.storydata = .init(context: context, peer: peerReference, maxReadId: entry.additionalData.storyReadMaxId, media: story, storyItem: item, text: TextViewLayout(info, alignment: .center), theme: theme, isIncoming: isIncoming)
            }
        }
        
        
        text = TextViewLayout(attributedString.detectBold(with: .medium(.text)), truncationType: .end, cutout: nil, alignment: .center)
        text.mayItems = false
        text.interactions = LinkHooks.shared.globalLinkExecutor()
        super.init(initialSize, chatInteraction, entry, theme: theme)
    }
    
    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        return NSZeroSize
    }
    
    public func removeBackground() {
        if let id = self.message?.id.peerId {
            _ = context.engine.themes.revertChatWallpaper(peerId: id).start()
        }
    }
    
    public func openChannel(_ peerId: PeerId) {
        guard let message = self.message else {
            return
        }
        chatInteraction.openInfo(peerId, true, nil, nil)
        
        var jsonString: String = "{"
        jsonString += "\"ref_channel_id\": \"\(message.id.peerId.id._internalGetInt64Value())\","
        jsonString += "\"open_channel_id\": \"\(peerId.id._internalGetInt64Value())\""
        jsonString += "}"
        
        if let data = jsonString.data(using: .utf8), let json = JSON(data: data) {
            context.engine.accountData.addAppLogEvent(type: "channels.open_recommended_channel", data: json)
        }
        
    }
    
    public func openCommunity(_ communityId: PeerId) {
        ChatHistoryUIHooks.shared.showCommunityView(context, communityId)
    }

    public func openPremiumBoarding() {
        let context = self.context
        let limit = context.appConfiguration.getGeneralValue("recommended_channels_limit_premium", orElse: 0)

        showModalText(for: context.window, text: strings().similarChannelAlertText(Int(limit)), callback: { _ in
            prem(with: PremiumBoardingController(context: context, source: .recommended_channels), for: context.window)
        })
    }
    public func dismissRecommendedChannels() {
        guard let message = self.message else {
            return
        }
        _ = context.engine.peers.toggleRecommendedChannelsHidden(peerId: message.id.peerId, hidden: true).start()
    }
    public func revealRecommendedChannels() {
        guard let message = self.message else {
            return
        }
        if let data = self.entry.additionalData.recommendedChannels {
            _ = context.engine.peers.toggleRecommendedChannelsHidden(peerId: message.id.peerId, hidden: !data.isHidden).start()
        }
    }

    
    public override var isBubbled: Bool {
        return presentation.wallpaper.wallpaper != .none && super.isBubbled
    }

    public var walletTransferSpacing: CGFloat {
        return (isBubbled ? 0 : 6) - WalletTransferData.textOverlap
    }
    
    public override var height: CGFloat {
        var height:CGFloat = text.layoutSize.height + (isBubbled ? 0 : 12)
        if let imageArguments = imageArguments {
            height += imageArguments.imageSize.height + (isBubbled ? 9 : 6)
        }
        if let data = self.giftData {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = self.walletTransferData {
            height += data.height + walletTransferSpacing + (isBubbled ? 9 : 0)
        }
        if let data = self.suggestPhotoData {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = self.suggestPostStatus {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = self.suggestPostHeader {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = self.setThemeData {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = self.wallpaperData {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = self.storydata {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = suggestBirthdayData {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = communityChangedData {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = self.suggestChannelsData {
            data.makeSize(width: width - 80)
            height += data.size.height + (isBubbled ? 9 : 6)
        }
        if let data = self.offerData {
            height += data.height + (isBubbled ? 9 : 6)
        }
        if let data = self.copyProtectionRequestData {
            height += data.height + (isBubbled ? 9 : 6)
        }
        
        if let reactionsLayout {
            height += reactionsLayout.size.height
        }
        
        return height
    }
    
    fileprivate var serviceBackgroundColor: NSColor {
        guard walletTransferData != nil else {
            return presentation.chatServiceItemColor
        }
        let backgroundColor: NSColor
        switch presentation.controllerBackgroundMode {
        case .plain:
            backgroundColor = presentation.colors.chatBackground
        case let .color(color):
            backgroundColor = color
        default:
            return presentation.chatServiceItemColor
        }
        return backgroundColor.blended(withFraction: 0.12, of: backgroundColor.brightnessAdjustedColor) ?? presentation.chatServiceItemColor
    }

    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        text.measure(width: blockWidth)
        
        if let reactions = reactionsLayout {
            reactions.measure(for: min(320, blockWidth))
        }
        
        
        if isBubbled || walletTransferData != nil {
            if shouldBlurService {
                text.generateAutoBlock(backgroundColor: serviceBackgroundColor.withAlphaComponent(1))
            } else {
                text.generateAutoBlock(backgroundColor: serviceBackgroundColor)
            }
        }
        return true
    }
    
    public override var shouldBlurService: Bool {
        if context.isLite(.blur) {
            return false
        }
        return presentation.shouldBlurService
    }
    
    public override func viewClass() -> AnyClass {
        return ChatServiceRowView.self
    }
    
    public func openPhotoEditor(_ image: TelegramMediaImage) -> Void {
        ChatNavigationHooks.shared.openPhotoEditor(self.context, image)
    }
    
    public func openSuggestBirthday(_ birthday: TelegramBirthday, morphSource: (() -> NSView?)? = nil) {
        
        
        let context = self.context
        
        if let date = birthday.dateForPicker {
            guard let controller = ChatNavigationHooks.shared.makeBirthdayCalendar(context.window, date) else {
                return
            }
                        
            let nav = NavigationViewController(controller, context.window)
                        
            nav._frameRect = NSMakeRect(0, 0, 300, 310)
            
            class Wrap : ModalController {
                let context: any AccountContextProtocol
                let birthday: TelegramBirthday
                
                private var interactions: ModalInteractions?
                private var isVisible = true
                private var hasSubmitted = false
                private let saveAction = ChatBirthdaySaveAction()
                
                init(_ controller: NavigationViewController, context: any AccountContextProtocol, birthday: TelegramBirthday) {
                    self.context = context
                    self.birthday = birthday
                    super.init(controller)
                }
                
                override func viewWillAppear(_ animated: Bool) {
                    super.viewWillAppear(animated)
                    self.isVisible = true
                    self.saveAction.setActive(true)
                }

                override func viewWillDisappear(_ animated: Bool) {
                    self.isVisible = false
                    self.saveAction.setActive(false)
                    super.viewWillDisappear(animated)
                }

                override var modalInteractions: ModalInteractions? {
                    
                    if let interactions {
                        return interactions
                    }
                    
                    let bottomLayout: TextViewLayout?
                    if let _ = birthday.year {
                        let attr = NSMutableAttributedString()
                        attr.append(string: strings().chatServiceBirthdayHideYear, color: theme.colors.accent, font: .normal(.text))
                        attr.addAttribute(NSAttributedString.Key.link, value: "", range: attr.range)
                        bottomLayout = TextViewLayout(attr)
                        bottomLayout?.measure(width: 300)
                    } else {
                        bottomLayout = nil
                    }

                    let interactions = ModalInteractions(
                        acceptTitle: strings().chatServiceBirthdayAddToProfile,
                        accept: { [weak self] in
                            guard let self, self.isVisible, !self.hasSubmitted, !self.saveAction.isPending, let controller = self.controller.controller as? (any ChatBirthdayCalendar), let window = self.view.window as? Window else { return }
                            let birthday = controller.date.birthday
                            let canPresent: () -> Bool = { [weak self, weak controller, weak window] in
                                guard let self, let controller, let window else { return false }
                                return self.isVisible && !self.hasSubmitted && self.view.window === window && self.context.window === window && self.controller.controller === controller
                            }
                            self.saveAction.perform(signal: self.context.engine.accountData.updateBirthday(birthday: birthday), window: window, canPresent: canPresent, failed: { error in
                                switch error {
                                case .flood:
                                    showModalText(for: window, text: strings().loginFloodWait)
                                case .generic:
                                    showModalText(for: window, text: strings().unknownError)
                                }
                            }, completed: { [weak self, weak controller] in
                                guard let self, let controller else { return }
                                if controller.date.birthday == birthday {
                                    self.hasSubmitted = true
                                    self.modal?.close()
                                }
                                showModalText(for: window, text: strings().birthdayAlertAdded)
                            })
                        },
                        height: bottomLayout != nil ? 80 : 60,
                        singleButton: true,
                        bottomText: bottomLayout,
                        customTheme: {
                            .init(text: theme.colors.text, background: theme.colors.background, listBackground: theme.colors.background)
                        }
                    )

                    
                    bottomLayout?.interactions.processURL = { [weak self, weak interactions] _ in
                        let controller = self?.controller.controller as? (any ChatBirthdayCalendar)
                        guard let self, self.isVisible, !self.hasSubmitted, !self.saveAction.isPending, let controller else {
                            return
                        }
                        controller.hideYear()
                        self.modal?.setInteractionHeight(height: 60, animated: true)
                        interactions?.updateBottomText(nil)
                        self.modal?.resize(with: controller.frame.size, animated: true)
                    }
                    
                    self.interactions = interactions
                    
                    return interactions
                }
            }
            let modal = Wrap(nav, context: context, birthday: birthday)
            modal.bar = .init(height: 0)
            showModal(with: modal, for: context.window, morphSource: morphSource)
        }
        
        
    }
}

public class UniqueAttributesView : View {
    private let headerView = TextView()
    private let leftAttrs: View = View()
    private let rightAttrs: View = View()
    private let attrContainer = View()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(headerView)
        attrContainer.addSubview(rightAttrs)
        attrContainer.addSubview(leftAttrs)

        addSubview(attrContainer)
        
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
    }
     public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func set(attributes: ChatServiceItem.GiftData.UniqueAttributes, animated: Bool) {
        headerView.update(attributes.header)
        
        while leftAttrs.subviews.count > attributes.attributes.count {
            leftAttrs.subviews.last?.removeFromSuperview()
        }
        while leftAttrs.subviews.count < attributes.attributes.count {
            let textView = TextView()
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            leftAttrs.addSubview(textView)
        }
        
        
        while rightAttrs.subviews.count > attributes.attributes.count {
            rightAttrs.subviews.last?.removeFromSuperview()
        }
        while rightAttrs.subviews.count < attributes.attributes.count {
            let textView = TextView()
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            rightAttrs.addSubview(textView)
        }
        
        for (i, attribute) in attributes.attributes.enumerated() {
            let left = self.leftAttrs.subviews[i] as! TextView
            let right = self.rightAttrs.subviews[i] as! TextView
            left.update(attribute.name)
            right.update(attribute.value)
        }
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: headerView, frame: headerView.centerFrameX(y: 5))

        // Calculate max widths
        let maxLeftWidth = leftAttrs.subviews.map { $0.frame.width }.max() ?? 0
        let maxRightWidth = rightAttrs.subviews.map { $0.frame.width }.max() ?? 0
        let attrHeight = size.height - headerView.frame.height - 5

        let leftFrame = NSRect(x: 0, y: 0, width: maxLeftWidth, height: attrHeight)
        let rightFrame = NSRect(x: maxLeftWidth + 6, y: 0, width: maxRightWidth, height: attrHeight)

        transition.updateFrame(view: leftAttrs, frame: leftFrame)
        transition.updateFrame(view: rightAttrs, frame: rightFrame)

        let containerWidth = maxLeftWidth + 6 + maxRightWidth
        let containerFrame = NSRect(x: (size.width - containerWidth) / 2,
                                    y: headerView.frame.maxY + 5,
                                    width: containerWidth,
                                    height: attrHeight)
        transition.updateFrame(view: attrContainer, frame: containerFrame)

        var y: CGFloat = 0
        for (i, left) in leftAttrs.subviews.enumerated() {
            let right = rightAttrs.subviews[i]
            
            let leftFrame = NSRect(
                x: maxLeftWidth - left.frame.width,
                y: y,
                width: left.frame.width,
                height: left.frame.height
            )
            let rightFrame = NSRect(
                x: 0,
                y: y,
                width: right.frame.width,
                height: right.frame.height
            )

            transition.updateFrame(view: left, frame: leftFrame)
            transition.updateFrame(view: right, frame: rightFrame)

            y += max(left.frame.height, right.frame.height) + 6
        }
    }
}

private enum ChatWalletTransferStatus: Equatable {
    case waiting
    case pending
    case completed
    case unavailable
}

private struct ChatWalletTransferWalletState: Equatable {
    let status: ChatWalletTransferStatus
    let operationId: String?
    let transactionHash: Data?
}

func chatWalletTransferTransactionHash(_ value: String?) -> Data? {
    guard let value else {
        return nil
    }
    let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    if parts.count == 2 && UInt64(parts[0]) == nil {
        return nil
    }
    guard let hash = parts.last.flatMap({ Data(base64Encoded: String($0)) }), hash.count == 32 else {
        return nil
    }
    return hash
}

@available(macOS 10.15, *)
private func chatWalletTransferWalletState(_ state: ChatWalletTransferSnapshot, operationId: String?, transactionHash: Data?) -> ChatWalletTransferWalletState? {
    if let transaction = state.transactions.first(where: { transaction in
        guard transaction.isOutgoingTransfer else {
            return false
        }
        return operationId.map { transaction.presentationId == "pending:\($0)" } == true
            || (transactionHash != nil && chatWalletTransferTransactionHash(transaction.transactionHash ?? transaction.id) == transactionHash)
    }) {
        let status: ChatWalletTransferStatus
        switch transaction.status {
        case .pending:
            status = .pending
        case .completed:
            status = .completed
        case .failed:
            status = .unavailable
        }
        return ChatWalletTransferWalletState(
            status: status,
            operationId: operationId ?? (transaction.presentationId.hasPrefix("pending:") ? String(transaction.presentationId.dropFirst("pending:".count)) : nil),
            transactionHash: chatWalletTransferTransactionHash(transaction.transactionHash ?? transaction.id) ?? transactionHash
        )
    }
    if let pending = state.pendingTransfers.first(where: { pending in
        !pending.isCollectible && (pending.id == operationId
            || (transactionHash != nil && chatWalletTransferTransactionHash(pending.transactionHash) == transactionHash))
    }) {
        let status: ChatWalletTransferStatus
        switch pending.status {
        case .broadcasting:
            status = .waiting
        case .pending, .submissionUnknown:
            status = .pending
        case .confirmed:
            status = .completed
        }
        return ChatWalletTransferWalletState(status: status, operationId: pending.id, transactionHash: chatWalletTransferTransactionHash(pending.transactionHash) ?? transactionHash)
    }
    return nil
}

private let chatWalletTransferRibbonSize = NSMakeSize(54.8, 54.8)
private let chatWalletTransferRibbonCenter = NSMakePoint(33.057, 21.744)
private let chatWalletTransferRibbonOverhang: CGFloat = 2

private let chatWalletTransferRibbonPath: CGPath = {
    let path = CGMutablePath()
    path.move(to: NSMakePoint(50.115, 24.659))
    path.addLine(to: NSMakePoint(30.142, 4.686))
    path.addCurve(to: NSMakePoint(26.539, 1.474), control1: NSMakePoint(28.413, 2.957), control2: NSMakePoint(27.548, 2.092))
    path.addCurve(to: NSMakePoint(23.648, 0.276), control1: NSMakePoint(25.644, 0.925), control2: NSMakePoint(24.669, 0.521))
    path.addCurve(to: NSMakePoint(18.828, 0), control1: NSMakePoint(22.497, 0), control2: NSMakePoint(21.274, 0))
    path.addLine(to: NSMakePoint(4.897, 0))
    path.addCurve(to: NSMakePoint(0.701, 0.479), control1: NSMakePoint(2.474, 0), control2: NSMakePoint(1.262, 0))
    path.addCurve(to: NSMakePoint(0.006, 2.157), control1: NSMakePoint(0.214, 0.895), control2: NSMakePoint(-0.044, 1.519))
    path.addCurve(to: NSMakePoint(2.634, 5.463), control1: NSMakePoint(0.064, 2.892), control2: NSMakePoint(0.921, 3.749))
    path.addLine(to: NSMakePoint(49.338, 52.166))
    path.addCurve(to: NSMakePoint(52.644, 54.795), control1: NSMakePoint(51.052, 53.880), control2: NSMakePoint(51.908, 54.737))
    path.addCurve(to: NSMakePoint(54.322, 54.100), control1: NSMakePoint(53.282, 54.845), control2: NSMakePoint(53.906, 54.586))
    path.addCurve(to: NSMakePoint(54.8, 49.904), control1: NSMakePoint(54.8, 53.539), control2: NSMakePoint(54.8, 52.327))
    path.addLine(to: NSMakePoint(54.8, 35.972))
    path.addCurve(to: NSMakePoint(54.525, 31.153), control1: NSMakePoint(54.8, 33.526), control2: NSMakePoint(54.8, 32.303))
    path.addCurve(to: NSMakePoint(53.327, 28.262), control1: NSMakePoint(54.280, 30.132), control2: NSMakePoint(53.876, 29.157))
    path.addCurve(to: NSMakePoint(50.115, 24.659), control1: NSMakePoint(52.709, 27.253), control2: NSMakePoint(51.844, 26.388))
    path.closeSubpath()
    return path
}()

private let chatWalletTransferRibbonImage: CGImage? = generateImage(chatWalletTransferRibbonSize, rotatedContext: { size, ctx in
    ctx.clear(size.bounds)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(chatWalletTransferRibbonPath)
    ctx.fillPath()
})

private func chatWalletTransferRibbon(color: NSColor) -> CGImage? {
    return generateGradientTintedImage(image: chatWalletTransferRibbonImage, colors: [color])
}

private func chatWalletTransferRibbonText(_ text: String) -> CGImage? {
    let maxWidth: CGFloat = 52
    var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.semibold(11), .foregroundColor: NSColor.white]))
    let width = ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
    if width > maxWidth {
        line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.semibold(11 * maxWidth / width), .foregroundColor: NSColor.white]))
    }
    let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    return generateImage(chatWalletTransferRibbonSize, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.translateBy(x: chatWalletTransferRibbonCenter.x, y: chatWalletTransferRibbonCenter.y)
        ctx.rotate(by: .pi / 4)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = NSMakePoint(-glyphBounds.midX, glyphBounds.midY)
        CTLineDraw(line, ctx)
    })
}

private final class ChatWalletTransferBadgeView: View {
    enum Status: Equatable {
        case sending
        case sent
        case received
    }

    private static let clockRadius: CGFloat = 7
    private static let clockInset: CGFloat = 12 + (1 - 1 / System.backingScale)
    private static let clockCenter = NSMakePoint(chatWalletTransferRibbonSize.width - chatWalletTransferRibbonOverhang - clockInset - clockRadius, clockInset + clockRadius + chatWalletTransferRibbonOverhang)
    private static let clockLineWidth: CGFloat = 4 / 3
    private static let clockColor = NSColor.white
    private static let morphRadius: CGFloat = 43
    private static let morphFrameDuration: Double = 1 / 60
    private static let textSlideOffset = NSMakePoint(-14.5 / sqrt(2), 14.5 / sqrt(2))

    private let clockLayer = SimpleLayer()
    private let ringLayer = SimpleShapeLayer()
    private let handsLayer = SimpleLayer()
    private let minuteHandLayer = SimpleShapeLayer()
    private let hourHandLayer = SimpleShapeLayer()
    private let ribbonClipLayer = SimpleLayer()
    private let ribbonMaskLayer = SimpleLayer()
    private let morphLayer = SimpleLayer()
    private let morphMaskLayer = SimpleShapeLayer()
    private let ribbonLayer = SimpleLayer()
    private let tintLayer = SimpleLayer()
    private let glintLayer = SimpleGradientLayer()
    private let textLayer = SimpleLayer()

    private var status: Status?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true

        let clockBounds = NSMakeRect(0, 0, Self.clockRadius * 2, Self.clockRadius * 2)
        let clockMid = NSMakePoint(clockBounds.midX, clockBounds.midY)
        let minutePath = CGMutablePath()
        minutePath.move(to: clockMid)
        minutePath.addLine(to: NSMakePoint(clockMid.x, clockMid.y - 11 / 3))
        let hourPath = CGMutablePath()
        hourPath.move(to: clockMid)
        hourPath.addLine(to: NSMakePoint(clockMid.x + 3, clockMid.y))
        let ringPath = CGPath(ellipseIn: clockBounds.insetBy(dx: Self.clockLineWidth / 2, dy: Self.clockLineWidth / 2), transform: nil)
        let shapes: [(SimpleShapeLayer, CGPath)] = [(ringLayer, ringPath), (minuteHandLayer, minutePath), (hourHandLayer, hourPath)]
        for (shape, path) in shapes {
            shape.frame = clockBounds
            shape.path = path
            shape.fillColor = nil
            shape.strokeColor = Self.clockColor.cgColor
            shape.lineWidth = Self.clockLineWidth
            shape.lineCap = .round
        }
        handsLayer.frame = clockBounds
        handsLayer.addSublayer(minuteHandLayer)
        handsLayer.addSublayer(hourHandLayer)
        clockLayer.frame = clockBounds.offsetBy(dx: Self.clockCenter.x - Self.clockRadius, dy: Self.clockCenter.y - Self.clockRadius)
        clockLayer.addSublayer(ringLayer)
        clockLayer.addSublayer(handsLayer)

        let ribbonBounds = chatWalletTransferRibbonSize.bounds
        ribbonMaskLayer.frame = ribbonBounds
        ribbonMaskLayer.contents = chatWalletTransferRibbonImage
        ribbonClipLayer.frame = ribbonBounds
        ribbonClipLayer.mask = ribbonMaskLayer
        morphMaskLayer.frame = ribbonBounds
        morphMaskLayer.fillRule = .evenOdd
        morphLayer.frame = ribbonBounds
        tintLayer.backgroundColor = Self.clockColor.cgColor
        glintLayer.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.7).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        glintLayer.locations = [0, 0.5, 1]
        glintLayer.opacity = 0
        glintLayer.compositingFilter = "plusL"
        for sublayer in [ribbonLayer, tintLayer, glintLayer, textLayer] {
            sublayer.frame = ribbonBounds
            morphLayer.addSublayer(sublayer)
        }
        ribbonClipLayer.addSublayer(morphLayer)

        clockLayer.isHidden = true
        ribbonClipLayer.isHidden = true
        layer?.addSublayer(ribbonClipLayer)
        layer?.addSublayer(clockLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            glintLayer.removeAllAnimations()
            applyStatus()
        } else {
            updateClockAnimation()
        }
    }

    func update(status: Status, animated: Bool) {
        guard self.status != status else {
            return
        }
        let previousStatus = self.status
        self.status = status
        glintLayer.removeAllAnimations()
        if status != .sending {
            ribbonLayer.contents = chatWalletTransferRibbon(color: status == .received ? NSColor(rgb: 0x42b0ff) : NSColor(rgb: 0x00cf00))
            textLayer.contents = chatWalletTransferRibbonText(status == .received ? strings().chatServiceItemRibbonReceived : strings().chatServiceItemRibbonSent)
        }
        if animated, previousStatus == .sending, status == .sent, window != nil {
            removeSentAnimations()
            animateSent()
        } else {
            applyStatus()
        }
    }

    func updateArrival(finish: Double) {
        guard finish >= 0 else {
            ribbonClipLayer.opacity = 0
            return
        }
        let ribbon = ChatWalletTransferArrivalMotion.ribbon(finish: finish)
        let pivot = NSMakePoint(200 - frame.minX, 24 - frame.minY)
        ribbonClipLayer.setAffineTransform(ChatWalletTransferArrivalMotion.ribbonTransform(length: ribbon.length, width: ribbon.width, pivot: pivot, center: ribbonClipLayer.position))
        ribbonClipLayer.opacity = Float(ChatWalletTransferArrivalMotion.ribbonAlpha(length: ribbon.length))
        textLayer.opacity = Float(ChatWalletTransferArrivalMotion.ribbonTextAlpha(length: ribbon.length))
    }

    func resetArrival() {
        glintLayer.removeAllAnimations()
        ribbonClipLayer.setAffineTransform(.identity)
        ribbonClipLayer.opacity = 1
        textLayer.opacity = 1
    }

    func playArrivalGlint() {
        glintLayer.removeAllAnimations()
        animateGlint()
    }

    private func applyStatus() {
        removeSentAnimations()
        clockLayer.isHidden = status != .sending
        ringLayer.isHidden = false
        ribbonClipLayer.isHidden = status == nil || status == .sending
        morphLayer.mask = nil
        tintLayer.opacity = 0
        updateClockAnimation()
    }

    private func removeSentAnimations() {
        let layers: [CALayer] = [morphMaskLayer, handsLayer, tintLayer, textLayer]
        for sublayer in layers {
            sublayer.removeAllAnimations()
        }
    }

    private func updateClockAnimation() {
        let hands: [(SimpleShapeLayer, Double)] = [(minuteHandLayer, 2 / 3), (hourHandLayer, 2)]
        if status == .sending, window != nil {
            for (hand, duration) in hands where hand.animation(forKey: "rotation") == nil {
                let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
                rotation.fromValue = 0
                rotation.toValue = Double.pi * 2
                rotation.duration = duration
                rotation.repeatCount = .infinity
                rotation.timingFunction = CAMediaTimingFunction(name: .linear)
                hand.add(rotation, forKey: "rotation")
            }
        } else {
            for (hand, _) in hands {
                hand.removeAnimation(forKey: "rotation")
            }
        }
    }

    private func animateSent() {
        let frameDuration = Self.morphFrameDuration
        let holeRadius = Self.clockRadius - Self.clockLineWidth
        let paths = (0 ... 11).map { index -> CGPath in
            let radius = Self.clockRadius + (Self.morphRadius - Self.clockRadius) * bezierPoint(0.2, 0.05, 0.8, 1, CGFloat(index) / 11)
            return Self.morphPath(radius: radius, holeRadius: holeRadius * max(0, 1 - CGFloat(index) / 3))
        }

        clockLayer.isHidden = false
        ringLayer.isHidden = true
        ribbonClipLayer.isHidden = false
        morphMaskLayer.path = paths.last
        morphLayer.mask = morphMaskLayer
        tintLayer.opacity = 0

        morphMaskLayer.animateKeyframes(values: paths, duration: 11 * frameDuration, keyPath: "path", timingFunction: .linear)
        handsLayer.animateScale(from: 1, to: 0, duration: 3 * frameDuration, timingFunction: .linear, removeOnCompletion: false)
        textLayer.animatePosition(from: Self.textSlideOffset, to: .zero, duration: 11 * frameDuration, timingFunction: .default, additive: true)
        textLayer.animate(from: NSNumber(value: 0), to: NSNumber(value: 1), keyPath: "opacity", timingFunction: .default, duration: 12 * frameDuration, delay: frameDuration)
        tintLayer.animateAlpha(from: 1, to: 0, duration: 13 * frameDuration, timingFunction: .easeOut, completion: { [weak self] completed in
            if completed {
                self?.applyStatus()
            }
        })
        animateGlint()
    }

    private func animateGlint() {
        let size = chatWalletTransferRibbonSize
        let origin = NSMakePoint(ChatServiceItem.WalletTransferData.outerInset + ChatServiceItem.WalletTransferData.cardSize.width - size.width + chatWalletTransferRibbonOverhang, ChatServiceItem.WalletTransferData.outerInset - chatWalletTransferRibbonOverhang)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            return NSMakePoint((x - origin.x) / size.width, (y - origin.y) / size.height)
        }
        let delay = 0.6
        let duration = 0.55
        glintLayer.startPoint = point(226, 0)
        glintLayer.endPoint = point(254, 12)
        glintLayer.animate(from: NSValue(point: point(136, 0)), to: NSValue(point: glintLayer.startPoint), keyPath: "startPoint", timingFunction: .linear, duration: duration, delay: delay)
        glintLayer.animate(from: NSValue(point: point(164, 12)), to: NSValue(point: glintLayer.endPoint), keyPath: "endPoint", timingFunction: .linear, duration: duration, delay: delay)

        let frameCount = Int(ceil(duration * 120))
        var values: [NSNumber] = [0]
        var keyTimes: [NSNumber] = [0]
        for index in 0 ... frameCount {
            let progress = Double(index) / Double(frameCount)
            values.append(NSNumber(value: index == frameCount ? 0 : sin(.pi * progress)))
            keyTimes.append(NSNumber(value: (delay + duration * progress) / (delay + duration)))
        }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = values
        opacity.keyTimes = keyTimes
        opacity.duration = delay + duration
        opacity.timingFunction = CAMediaTimingFunction(name: .linear)
        glintLayer.add(opacity, forKey: "opacity")
    }

    private static func morphPath(radius: CGFloat, holeRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: NSMakeRect(clockCenter.x - radius, clockCenter.y - radius, radius * 2, radius * 2))
        path.addEllipse(in: NSMakeRect(clockCenter.x - holeRadius, clockCenter.y - holeRadius, holeRadius * 2, holeRadius * 2))
        return path
    }
}

@available(macOS 10.15, *)
final class ChatWalletTransferView: Control, MorphHoldObserving {
    private static let bounceKey = "bounce"
    private static let landingKey = "landing"
    private static let flightLandingKey = "flightLanding"

    private var visualEffect: VisualEffect?
    private let cardView: any ChatWalletCardView = ChatHistoryUIHooks.shared.walletHooks.makeCardView(CGRect(origin: .zero, size: ChatServiceItem.WalletTransferData.cardSize))
    // Morph from the whole transfer view (card + ribbon + background), not just the inner card: holding
    // only the card left the ribbon and background on screen while the card morphed away, and on close the
    // card came back dark under a still-visible ribbon. The snapshot crossfade and the removed modal border
    // absorb the `outerInset` margin, so the card no longer overshoots at the hand-off.
    var morphSourceView: NSView? { return self }
    private let badgeView = ChatWalletTransferBadgeView(frame: chatWalletTransferRibbonSize.bounds)
    private var captionView: TextView?
    private var hasEncryptedCaption = false

    private var walletContext: (any ChatWalletContext)?
    private let walletStateDisposable = MetaDisposable()
    private var isObservingWalletState = false
    private weak var item: ChatServiceItem?
    private(set) var messageId: MessageId?
    private(set) var messageStableId: UInt32?
    private(set) var transferOperationId: String?
    private(set) var transferTransactionHash: Data?
    private var transferStatus: ChatWalletTransferStatus?
    private(set) var isIncomingTransfer = false
    private var isPlayingHighlightShimmer = false
    private(set) var isAwaitingTransferFlight = false
    private var isPreparedForArrival = false
    private var arrivalDidGlint = false

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(cardView)
        addSubview(badgeView)
        cardView.isEventLess = true
        cardView.onDiamondLanding = { [weak self] power in
            self?.animateDiamondLandingBump(power: power)
        }
        cardView.onArrivalInterrupted = { [weak self] in
            self?.cancelIncomingTransferAnimation()
        }
        scaleOnClick = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        walletStateDisposable.dispose()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            layer?.removeAnimation(forKey: Self.bounceKey)
            layer?.removeAnimation(forKey: Self.landingKey)
            layer?.removeAnimation(forKey: Self.flightLandingKey)
            cancelIncomingTransferAnimation()
        }
        updateShimmer(animated: false)
        if window != nil {
            updateIncomingTransferVisibility()
        }
    }

    var isMouseInsideEncryptedCaption: Bool {
        guard hasEncryptedCaption, let captionView, let window else {
            return false
        }
        return captionView.frame.insetBy(dx: -3, dy: -3).contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    func update(item: ChatServiceItem, data: ChatServiceItem.WalletTransferData, animated: Bool) {
        cardView.update(amount: data.amount, isIncoming: data.isIncoming, name: data.name, address: data.peerAddress)

        isIncomingTransfer = data.isIncoming
        hasEncryptedCaption = data.hasEncryptedComment

        if let captionLayout = data.captionLayout {
            let current: TextView
            if let view = self.captionView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                current.isEventLess = true
                self.captionView = current
                addSubview(current)
            }
            current.update(captionLayout)
        } else if let view = self.captionView {
            performSubviewRemoval(view, animated: animated)
            self.captionView = nil
        }

        if item.shouldBlurService {
            let current: VisualEffect
            if let view = self.visualEffect {
                current = view
            } else {
                current = VisualEffect(frame: bounds)
                self.visualEffect = current
                addSubview(current, positioned: .below, relativeTo: self.subviews.first)
            }
            current.bgColor = item.presentation.blurServiceColor
            current.layer?.opacity = item.presentation.colors.isDark ? 0.6 : 1.0
            self.backgroundColor = .clear
        } else {
            if let view = self.visualEffect {
                performSubviewRemoval(view, animated: animated)
                self.visualEffect = nil
            }
            self.backgroundColor = item.serviceBackgroundColor
        }

        let walletContext = ChatHistoryUIHooks.shared.walletHooks.walletContext(item.context)
        let stableId = item.message?.stableId
        let isSameMessage = stableId != nil && self.messageStableId == stableId && self.walletContext === walletContext
        if !isSameMessage {
            cancelIncomingTransferAnimation()
        }
        self.item = item
        self.messageId = item.message?.id
        self.messageStableId = stableId
        updateWalletSubscription(walletContext: walletContext, data: data, isSameMessage: isSameMessage)
        setAwaitingTransferFlight(!data.isIncoming && item.chatInteraction.walletTransferAnimation?.isAwaitingFlight(self) == true)
        updateIncomingTransferVisibility()

        needsLayout = true
    }

    private func updateWalletSubscription(walletContext: (any ChatWalletContext)?, data: ChatServiceItem.WalletTransferData, isSameMessage: Bool) {
        if !isSameMessage {
            walletStateDisposable.set(nil)
            isObservingWalletState = false
            transferOperationId = nil
            transferTransactionHash = nil
            transferStatus = nil
            layer?.removeAnimation(forKey: Self.bounceKey)
            layer?.removeAnimation(forKey: Self.landingKey)
            layer?.removeAnimation(forKey: Self.flightLandingKey)
            isAwaitingTransferFlight = false
            badgeView.isHidden = false
            isPlayingHighlightShimmer = false
            cardView.updateShimmer(visible: false, repeating: true, animated: false, completion: nil)
            cardView.resetTransferState()
        }
        if self.walletContext !== walletContext {
            walletStateDisposable.set(nil)
            isObservingWalletState = false
            self.walletContext = walletContext
        }

        if data.isIncoming {
            updateTransferStatus(.completed, animated: false)
            return
        }
        transferOperationId = data.operationId ?? transferOperationId
        transferTransactionHash = chatWalletTransferTransactionHash(data.pendingTransactionId)
            ?? chatWalletTransferTransactionHash(data.transactionId)
            ?? transferTransactionHash
        applyWalletState(walletContext.flatMap {
            chatWalletTransferWalletState($0.chatTransferSnapshot, operationId: transferOperationId, transactionHash: transferTransactionHash)
        }, animated: isSameMessage)

        guard !isObservingWalletState, transferStatus != .completed, let walletContext else {
            return
        }
        isObservingWalletState = true
        walletStateDisposable.set((walletContext.chatTransferState
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self, self.transferStatus != .completed else {
                return
            }
            self.applyWalletState(
                chatWalletTransferWalletState(state, operationId: self.transferOperationId, transactionHash: self.transferTransactionHash),
                animated: true
            )
        }))
    }

    private func applyWalletState(_ state: ChatWalletTransferWalletState?, animated: Bool) {
        if let state {
            transferOperationId = state.operationId ?? transferOperationId
            transferTransactionHash = state.transactionHash ?? transferTransactionHash
            updateTransferStatus(state.status, animated: animated)
        } else if transferStatus == .pending || transferStatus == .unavailable {
            updateTransferStatus(.unavailable, animated: animated)
        } else {
            updateTransferStatus(transferOperationId == nil ? .completed : .waiting, animated: animated)
        }
    }

    private func updateTransferStatus(_ status: ChatWalletTransferStatus, animated: Bool) {
        guard transferStatus != .completed else {
            return
        }
        let previousStatus = transferStatus
        transferStatus = status
        updateTransferAppearance(previousStatus: previousStatus, animated: animated)
    }

    private func updateTransferAppearance(previousStatus: ChatWalletTransferStatus?, animated: Bool) {
        let status = transferStatus
        if isPreparedForArrival {
            return
        }
        if isAwaitingTransferFlight {
            updateShimmer(animated: false)
            return
        }
        if previousStatus == status {
            if status == .pending {
                updateShimmer(animated: false)
            }
            return
        }
        updateShimmer(animated: animated && previousStatus != nil)
        let badgeStatus = self.badgeStatus
        cardView.updateTransferState(isSending: badgeStatus == .sending, isPending: status == .pending, animateCompletion: !isIncomingTransfer && status == .completed && previousStatus != nil && animated && window != nil)
        let animateSent = status == .completed && previousStatus != nil && animated && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        badgeView.update(status: badgeStatus, animated: animateSent)
        if animateSent {
            animateSentBounce()
        }
    }

    private var badgeStatus: ChatWalletTransferBadgeView.Status {
        if isIncomingTransfer {
            return .received
        } else if transferStatus == .completed {
            return .sent
        } else {
            return .sending
        }
    }

    func setAwaitingTransferFlight(_ awaiting: Bool, animated: Bool = false) {
        guard isAwaitingTransferFlight != awaiting else {
            return
        }
        isAwaitingTransferFlight = awaiting
        cardView.setAwaitingTransferFlight(awaiting, animated: animated)
        if awaiting {
            layer?.removeAnimation(forKey: Self.flightLandingKey)
            badgeView.isHidden = true
            updateShimmer(animated: false)
        } else {
            badgeView.isHidden = false
            updateTransferAppearance(previousStatus: nil, animated: false)
            if animated {
                badgeView.layer?.animateAlpha(from: 0, to: 1, duration: 0.15)
            }
        }
    }

    func transferDiamondTarget(in view: NSView) -> (center: NSPoint, width: CGFloat)? {
        guard window != nil else {
            return nil
        }
        return cardView.transferDiamondTarget(in: view)
    }

    func acceptTransferDiamond(_ diamond: InteractiveDiamondView) {
        isAwaitingTransferFlight = false
        cardView.acceptTransferDiamond(diamond)
        badgeView.isHidden = false
        updateTransferAppearance(previousStatus: .pending, animated: true)
        animateTransferFlightLanding()
    }

    func morphHoldDidChange(_ isHeld: Bool) {
        cardView.setCovered(isHeld)
    }

    private func animateTransferFlightLanding() {
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        let center = NSMakePoint(frame.width / 2, frame.height / 2)
        let duration = ChatWalletTransferFlightMotion.landingDuration
        let frameCount = Int(duration * 120)
        let landing = CAKeyframeAnimation(keyPath: "transform")
        landing.values = (0 ... frameCount).map { index -> NSValue in
            let impact = ChatWalletTransferFlightMotion.landing(at: duration * Double(index) / Double(frameCount), isLast: index == frameCount)
            var transform = CATransform3DMakeTranslation(center.x, center.y + impact.offset, 0)
            transform = CATransform3DScale(transform, impact.scale, impact.scale, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            return NSValue(caTransform3D: transform)
        }
        landing.duration = duration
        landing.timingFunction = CAMediaTimingFunction(name: .linear)
        layer?.add(landing, forKey: Self.flightLandingKey)
    }

    var canPlayIncomingTransferAnimation: Bool {
        guard isIncomingTransfer, let window, window.isKeyWindow, NSApp.isActive, frame.width > 0, let item, let table = item.table else {
            return false
        }
        return NSLocationInRange(item.index, table.visibleRows()) && !cardView.isDiamondExpanded
    }

    func updateIncomingTransferVisibility() {
        guard let item, let message = item.message, isIncomingTransfer, frame.width > 0, let animation = item.chatInteraction.walletTransferAnimation else {
            return
        }
        var state = animation.arrivalState(message.id)
        if state == nil, canPlayIncomingTransferAnimation {
            animation.requestArrival(message)
            state = animation.arrivalState(message.id)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finishIncomingTransferAnimation()
            return
        }
        switch state {
        case let .queued(rise):
            prepareIncomingTransferAnimation(rise: rise)
        case let .playing(startTime, rise):
            prepareIncomingTransferAnimation(rise: rise)
            updateIncomingTransferAnimation(startTime: startTime, rise: rise, at: CACurrentMediaTime())
        case .finished:
            finishIncomingTransferAnimation()
        case nil:
            if let rise = animation.arrivalRise(message), !cardView.isDiamondExpanded {
                prepareIncomingTransferAnimation(rise: rise)
            } else {
                finishIncomingTransferAnimation()
            }
        }
    }

    private func prepareIncomingTransferAnimation(rise: Bool) {
        guard !isPreparedForArrival else {
            return
        }
        isPreparedForArrival = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        superview?.layer?.masksToBounds = false
        superview?.layer?.zPosition = 1
        layer?.removeAnimation(forKey: Self.bounceKey)
        layer?.removeAnimation(forKey: Self.landingKey)
        isPlayingHighlightShimmer = false
        cardView.prepareIncomingTransferAnimation()
        badgeView.updateArrival(finish: -1)
        layer?.opacity = rise ? 0 : 1
        CATransaction.commit()
    }

    @discardableResult
    func updateIncomingTransferAnimation(startTime: CFTimeInterval, rise: Bool, at timestamp: CFTimeInterval) -> Double? {
        guard canPlayIncomingTransferAnimation else {
            return nil
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            cancelIncomingTransferAnimation()
            return nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }
        prepareIncomingTransferAnimation(rise: rise)
        let finish = cardView.updateIncomingTransferAnimation(startTime: startTime, at: timestamp)
        let motion = ChatWalletTransferArrivalMotion.card(time: max(0, timestamp - startTime), finish: finish, rise: rise, height: frame.height)
        layer?.opacity = Float(motion.opacity)
        let center = NSMakePoint(frame.width / 2, frame.height / 2)
        var transform = CATransform3DMakeTranslation(center.x, center.y + motion.offset, 0)
        transform = CATransform3DScale(transform, motion.scale, motion.scale, 1)
        transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
        layer?.transform = transform
        badgeView.updateArrival(finish: finish)
        if finish >= ChatWalletTransferArrivalMotion.glintDelay && !arrivalDidGlint {
            arrivalDidGlint = true
            badgeView.playArrivalGlint()
        }
        return finish
    }

    private func cancelIncomingTransferAnimation() {
        guard isPreparedForArrival, let messageId else {
            return
        }
        item?.chatInteraction.walletTransferAnimation?.cancelArrival(messageId)
        finishIncomingTransferAnimation()
    }

    func finishIncomingTransferAnimation() {
        guard isPreparedForArrival else {
            return
        }
        isPreparedForArrival = false
        arrivalDidGlint = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardView.finishIncomingTransferAnimation()
        layer?.opacity = 1
        layer?.transform = CATransform3DIdentity
        superview?.layer?.masksToBounds = true
        superview?.layer?.zPosition = 0
        badgeView.resetArrival()
        updateShimmer(animated: false)
        CATransaction.commit()
    }

    func playHighlight() {
        guard window != nil, !isPreparedForArrival else {
            return
        }
        isPlayingHighlightShimmer = true
        cardView.updateShimmer(visible: false, repeating: true, animated: false, completion: nil)
        updateShimmer(animated: false)
        animateHighlightBump()
    }

    private func updateShimmer(animated: Bool) {
        if window == nil {
            isPlayingHighlightShimmer = false
        }
        let visible = !isAwaitingTransferFlight && (transferStatus == .pending || isPlayingHighlightShimmer) && window != nil
        cardView.updateShimmer(visible: visible, repeating: !isPlayingHighlightShimmer, animated: animated && window != nil, completion: { [weak self] in
            self?.isPlayingHighlightShimmer = false
            self?.updateShimmer(animated: false)
        })
    }

    private func animateSentBounce() {
        let center = NSMakePoint(frame.width / 2, frame.height / 2)
        let duration = 1.2
        let frameCount = Int(duration * 120)
        let bounce = CAKeyframeAnimation(keyPath: "transform")
        bounce.values = (0 ... frameCount).map { index -> NSValue in
            let time = duration * Double(index) / Double(frameCount)
            let offset = index == frameCount ? 0 : -sin(2 * Double.pi * 2 * time) * exp(-time / 0.25)
            let scale = CGFloat(1 + 0.045 * offset)
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            return NSValue(caTransform3D: transform)
        }
        bounce.duration = duration
        bounce.timingFunction = CAMediaTimingFunction(name: .linear)
        layer?.add(bounce, forKey: Self.bounceKey)
    }

    private func animateDiamondLandingBump(power: CGFloat) {
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        let center = NSMakePoint(frame.width / 2, frame.height / 2)
        let duration = 1.0
        let frameCount = Int(duration * 120)
        let bump = CAKeyframeAnimation(keyPath: "transform")
        bump.values = (0 ... frameCount).map { index -> NSValue in
            let time = duration * Double(index) / Double(frameCount)
            let bounce = index == frameCount ? 0 : sin(2 * Double.pi * 2.4 * time) * exp(-time / 0.2)
            let scale = 1 - 0.05 * power * CGFloat(bounce)
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            return NSValue(caTransform3D: transform)
        }
        bump.duration = duration
        bump.timingFunction = CAMediaTimingFunction(name: .linear)
        bump.isAdditive = true
        layer?.add(bump, forKey: Self.landingKey)
    }

    private func animateHighlightBump() {
        guard window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        let center = NSMakePoint(frame.width / 2, frame.height / 2)
        let delay = 0.18
        let durationFactor = 1.7
        let duration = 0.9 * durationFactor
        let frameCount = Int(ceil(duration * 120))
        var values: [NSValue] = [NSValue(caTransform3D: CATransform3DIdentity)]
        var keyTimes: [NSNumber] = [0]
        for index in 0 ... frameCount {
            let progress = Double(index) / Double(frameCount)
            let time = duration * progress / durationFactor
            let offset = index == frameCount ? 0 : sin(2 * Double.pi * 1.6 * time) * exp(-time / 0.2)
            let scale = CGFloat(1 + 0.06 * offset)
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            values.append(NSValue(caTransform3D: transform))
            keyTimes.append(NSNumber(value: (delay + duration * progress) / (delay + duration)))
        }
        let bump = CAKeyframeAnimation(keyPath: "transform")
        bump.values = values
        bump.keyTimes = keyTimes
        bump.duration = delay + duration
        bump.timingFunction = CAMediaTimingFunction(name: .linear)
        layer?.add(bump, forKey: Self.bounceKey)
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        typealias Metrics = ChatServiceItem.WalletTransferData
        if let visualEffect {
            transition.updateFrame(view: visualEffect, frame: size.bounds)
        }
        let cardFrame = CGRect(origin: CGPoint(x: Metrics.outerInset, y: Metrics.outerInset), size: Metrics.cardSize)
        transition.updateFrame(view: cardView, frame: cardFrame)
        let ribbonSize = chatWalletTransferRibbonSize
        transition.updateFrame(view: badgeView, frame: CGRect(origin: CGPoint(x: cardFrame.maxX - ribbonSize.width + chatWalletTransferRibbonOverhang, y: cardFrame.minY - chatWalletTransferRibbonOverhang), size: ribbonSize))
        if let captionView {
            let captionOrigin = CGPoint(
                x: floorToScreenPixels(backingScaleFactor, (size.width - captionView.frame.width) / 2),
                y: cardFrame.maxY + Metrics.captionSpacing
            )
            transition.updateFrame(view: captionView, frame: CGRect(origin: captionOrigin, size: captionView.frame.size))
        }
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
}

public class ChatServiceRowView: TableRowView, RevealTableView {
    
    private class GiftView : Control {
        
        
        
        private let disposable = MetaDisposable()
        
        private var visualEffect: VisualEffect?
        
        private let textView = InteractiveTextView()
        private var infoView: InteractiveTextView?
        
        private let button = TextButton()
        
        private var badgeView: ImageView?
        
        private var authorView: TextView?
        
        private let stickerView: MediaAnimatedStickerView = MediaAnimatedStickerView(frame: NSMakeSize(150, 150).bounds)

        private var uniqueBackground: UniqueGiftBackgroundView?
        private var uniqueBackgroundContent: UniqueGiftBackgroundContent?
        private var uniqueBackgroundContext: (any AccountContextProtocol)?
        private var attributesView: UniqueAttributesView?
        private var messageView: GiftMessageView?
        private let buttonStars = GiftButtonStarsView(frame: .zero)

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(stickerView)
            addSubview(textView)
            addSubview(button)
            textView.userInteractionEnabled = false

            button.addSubview(buttonStars, positioned: .below, relativeTo: button.subviews.first)
            button.layer?.masksToBounds = true

            stickerView.userInteractionEnabled = false
            self.scaleOnClick = true
            layer?.cornerRadius = 24
        }
        
        func update(item: ChatServiceItem, data: ChatServiceItem.GiftData, animated: Bool) {
            
            let context = item.context
            let alt:String = data.alt
            
            var uniqueGift: StarGift.UniqueGift?
            
            switch data.source {
            case let .starGift(_, _, _, _, purpose):
                switch purpose {
                case let .starGift(gift, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _):
                    switch gift {
                    case let .unique(gift):
                        uniqueGift = gift
                    default:
                        break
                    }
                default:
                    break
                }
            default:
                break
            }
            
            
            
            textView.set(text: data.text, context: item.context)
            
            if let badge = data.ribbon {
                let current: ImageView
                if let view = self.badgeView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    addSubview(current)
                    self.badgeView = current
                }
                                
                let ribbon = generateGradientTintedImage(image: TelegramThemeHooks.shared.image(.giftRibbon).precomposed(), colors: [badge.color.withMultiplied(hue: 0.97, saturation: 1.45, brightness: 0.89), badge.color.withMultiplied(hue: 1.01, saturation: 1.22, brightness: 1.04)], direction: .mirroredDiagonal)!
                
                
                current.image = generateGiftBadgeBackground(background: ribbon, text: badge.text)
                
                current.sizeToFit()
            } else if let view = badgeView {
                performSubviewRemoval(view, animated: false)
                self.badgeView = nil
            }
            
            
            let isUnique = uniqueGift != nil
            let overlayColor = item.presentation.colors.isDark && !isUnique ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.12)

            button.userInteractionEnabled = false
            button.set(font: .medium(.text), for: .Normal)
            button.set(color: isUnique ? .white : item.presentation.chatServiceItemTextColor, for: .Normal)
            button.set(background: overlayColor, for: .Normal)
            if data.isPrepaidUpgrade, data.to == context.peerId {
                button.set(text: strings().chatStarsGiftButtonUnpack, for: .Normal)
            } else {
                button.set(text: strings().chatServiceGiftView, for: .Normal)
            }
            button.sizeToFit(NSMakeSize(38, 0))
            button.setFrameSize(NSMakeSize(button.frame.width, 34))
            button.layer?.cornerRadius = 17
            buttonStars.frame = button.bounds
            
            if let infoLayout = data.info {
                let current: InteractiveTextView
                if let view = self.infoView {
                    current = view
                } else {
                    current = InteractiveTextView(frame: .zero)
                    current.userInteractionEnabled = false
                    self.infoView = current
                    self.addSubview(current)
                }
                current.set(text: infoLayout, context: item.context)
            } else if let view = self.infoView {
                performSubviewRemoval(view, animated: animated)
                self.infoView = nil
            }
            
            let stickerFile: Signal<TelegramMediaFile, NoError>
            switch data.source {
            case .premium:
                stickerFile = ChatHistoryUIHooks.shared.giftStickers(item.context)
                |> map { items in
                    return items.first(where: {
                        $0.stickerText?.fixed == alt
                    }) ?? items.first
                }
                |> filter { $0 != nil }
                |> map { $0! }
                |> take(1)
                |> deliverOnMainQueue
            case let .stars(amount, _, _, _):
                stickerFile = .single(LocalAnimatedSticker.bestForStarsGift(abs(amount)).file)
            case let .ton(amount, _, _, _):
                stickerFile = .single(LocalAnimatedSticker.bestForTonGift(abs(amount)).file)
            case let .starGift(_, _, _, _, purpose):
                switch purpose {
                case let .starGift(gift, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _):
                    switch gift {
                    case let .unique(gift):
                        if let file = gift.file {
                            stickerFile = .single(file)
                        } else {
                            stickerFile = .complete()
                        }
                    case let .generic(gift):
                        stickerFile = .single(gift.file)
                    }
                default:
                    stickerFile = .complete()
                }
            }
            
            stickerView.setFrameSize(data.stickerSize)
            disposable.set(stickerFile.start(next: { [weak self] file in
                self?.setFile(file, size: data.stickerSize, context: context)
            }))
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            
            if let uniqueGift, let _ = data.uniqueAttributes {
                if let content = UniqueGiftBackgroundContent(gift: uniqueGift) {
                    if self.uniqueBackground == nil {
                        let current = UniqueGiftBackgroundView(frame: bounds.insetBy(dx: 4, dy: 4))
                        self.addSubview(current, positioned: .below, relativeTo: stickerView)
                        self.uniqueBackground = current
                    }
                    self.uniqueBackgroundContent = content
                    self.uniqueBackgroundContext = context
                } else if let view = self.uniqueBackground {
                    performSubviewRemoval(view, animated: animated)
                    self.uniqueBackground = nil
                    self.uniqueBackgroundContent = nil
                    self.uniqueBackgroundContext = nil
                }
                
                if let attributes = data.uniqueAttributes {
                    let current: UniqueAttributesView
                    if let view = self.attributesView {
                        current = view
                    } else {
                        current = UniqueAttributesView(frame: NSMakeRect(0, 0, 200, attributes.height))
                        addSubview(current)
                        self.attributesView = current
                    }
                    current.setFrameSize(NSMakeSize(200, attributes.height))
                    current.set(attributes: attributes, animated: animated)

                }


            } else {
                if let view = self.uniqueBackground {
                    performSubviewRemoval(view, animated: animated)
                    self.uniqueBackground = nil
                    self.uniqueBackgroundContent = nil
                    self.uniqueBackgroundContext = nil
                }
                if let view = self.attributesView {
                    performSubviewRemoval(view, animated: animated)
                    self.attributesView = nil
                }
            }

            if let giftMessage = data.giftMessage {
                let current: GiftMessageView
                if let view = self.messageView {
                    current = view
                } else {
                    current = GiftMessageView(frame: giftMessage.size.bounds)
                    addSubview(current)
                    self.messageView = current
                }
                current.setFrameSize(giftMessage.size)
                current.set(message: giftMessage, context: context, animated: animated)
            } else if let view = self.messageView {
                performSubviewRemoval(view, animated: animated)
                self.messageView = nil
            }

            if let authorLayout = data.authorLayout, let author = data.author {
                let current: TextView
                if let view = self.authorView {
                    current = view
                } else {
                    current = TextView()
                    current.userInteractionEnabled = true
                    current.scaleOnClick = true
                    current.isSelectable = false
                    self.authorView = current
                    self.addSubview(current)
                }
                current.update(authorLayout)
                                
                current.setSingle(handler: { [weak item] view in
                    item?.chatInteraction.openInfo(author.id, false, nil, nil)
                }, for: .Click)
            } else if let view = self.authorView {
                performSubviewRemoval(view, animated: animated)
                self.authorView = nil
            }
            
            
            needsLayout = true
        }
        
        private func setFile(_ file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol) {
            let parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .onceEnd, media: file)
            stickerView.update(with: file, size: size, context: context, table: nil, parameters: parameters, animated: false)
            needsLayout = true
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: stickerView, frame: stickerView.centerFrameX(y: 10))
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: stickerView.frame.maxY + 10))

            var offset: CGFloat = 0
            if let authorView {
                transition.updateFrame(view: authorView, frame: authorView.centerFrameX(y: textView.frame.maxY + 7))
                offset += authorView.frame.height
            }
            
            if let infoView {
                transition.updateFrame(view: infoView, frame: infoView.centerFrameX(y: textView.frame.maxY + 4 + offset))
            }

            if let badgeView {
                let badgeFrame = NSRect(
                    x: size.width - badgeView.frame.width,
                    y: 0,
                    width: badgeView.frame.width,
                    height: badgeView.frame.height
                )
                transition.updateFrame(view: badgeView, frame: badgeFrame)
            }

            transition.updateFrame(view: button, frame: button.centerFrameX(y: size.height - 10 - button.frame.height))
            transition.updateFrame(view: buttonStars, frame: button.bounds)

            if let visualEffect = visualEffect {
                transition.updateFrame(view: visualEffect, frame: NSRect(origin: .zero, size: size))
            }

            if let uniqueBackground, let content = uniqueBackgroundContent, let context = uniqueBackgroundContext {
                let backgroundFrame = size.bounds.insetBy(dx: 4, dy: 4)
                transition.updateFrame(view: uniqueBackground, frame: backgroundFrame)
                uniqueBackground.update(context: context, content: content, style: .message(patternCenterY: stickerView.frame.midY - backgroundFrame.minY + 32, cornerRadius: 20))
            }

            if let attributesView {
                let attrFrame = bounds.focusX(attributesView.frame.size, y: textView.frame.maxY + 5 + offset)
                transition.updateFrame(view: attributesView, frame: attrFrame)
            }

            if let messageView {
                let previous: CGFloat
                if let attributesView {
                    previous = attributesView.frame.maxY
                } else if let infoView {
                    previous = infoView.frame.maxY
                } else if let authorView {
                    previous = authorView.frame.maxY
                } else {
                    previous = textView.frame.maxY
                }
                let messageFrame = bounds.focusX(messageView.frame.size, y: previous + ChatServiceItem.GiftData.GiftMessage.topSpacing)
                transition.updateFrame(view: messageView, frame: messageFrame)
            }
        }

        
        deinit {
            disposable.dispose()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private class SuggestView : Control {
        

        var interactive: NSView? {
            return self.photo ?? self.photoVideoView
        }
        
        private let disposable = MetaDisposable()
        private var photo: TransformImageView?
        
        private var photoVideoView: MediaPlayerView?
        private var photoVideoPlayer: MediaPlayer?

        private var visualEffect: VisualEffect?
        
        private let textView = TextView()
                
        fileprivate let viewButton = TextButton()
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            addSubview(viewButton)
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
            viewButton.scaleOnClick = true
            viewButton.autohighlight = false
            self.scaleOnClick = true
            layer?.cornerRadius = 20
        }
        
        private var videoRepresentation: TelegramMediaImage.VideoRepresentation?

        
        func update(item: ChatServiceItem, data: ChatServiceItem.SuggestPhotoData, animated: Bool) {
            
            let size = NSMakeSize(100, 100)
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            
            if let represenstation = data.image.representationForDisplayAtSize(.init(640, 640)) {
                
                let arguments = TransformImageArguments(corners: .init(radius: size.height / 2), imageSize: represenstation.dimensions.size, boundingSize: size, intrinsicInsets: .init())
                
                let photo: TransformImageView
                if let view = self.photo {
                    photo = view
                } else {
                    photo = TransformImageView(frame: size.bounds)
                    self.photo = photo
                    addSubview(photo)
                }
                
                photo.setSignal(signal: cachedMedia(media: data.image, arguments: arguments, scale: System.backingScale))
                
                if !photo.isFullyLoaded, let message = item.message {
                    photo.setSignal(chatMessagePhoto(account: item.context.account, imageReference: .message(message: .init(message), media: data.image), scale: System.backingScale, autoFetchFullSize: true), cacheImage: { result in
                        cacheMedia(result, media: data.image, arguments: arguments, scale: System.backingScale)
                    })
                }
                
                photo.set(arguments: arguments)
            } else if let photo = self.photo {
                performSubviewRemoval(photo, animated: animated)
                self.photo = nil
            }
            
            if let video = data.image.videoRepresentations.last {
                let equal = videoRepresentation?.resource.id == video.resource.id
                
                if !equal {
                    self.photoVideoView?.removeFromSuperview()
                    self.photoVideoView = nil
                    
                    self.photoVideoView = MediaPlayerView(backgroundThread: true)
                    photoVideoView?.layer?.cornerRadius = size.height / 2
                    if #available(macOS 10.15, *) {
                        self.photoVideoView?.layer?.cornerCurve = .circular
                    }
                    self.addSubview(self.photoVideoView!)
                    self.photoVideoView!.isEventLess = true
                    
                    self.photoVideoView!.frame = size.bounds

                    let file = TelegramMediaFile(fileId: MediaId(namespace: 0, id: 0), partialReference: nil, resource: video.resource, previewRepresentations: data.image.representations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: video.resource.size, attributes: [], alternativeRepresentations: [])
                    
                    
                    let reference: MediaResourceReference
                    
                    if let peer = item.peer, let peerReference = PeerReference(peer) {
                        reference = MediaResourceReference.avatar(peer: peerReference, resource: file.resource)
                    } else {
                        reference = MediaResourceReference.standalone(resource: file.resource)
                    }
                    
                    let userLocation: MediaResourceUserLocation
                    if let id = item.message?.id.peerId {
                        userLocation = .peer(id)
                    } else {
                        userLocation = .other
                    }
                    
                    let mediaPlayer = MediaPlayer(postbox: item.context.account.postbox, userLocation: userLocation, userContentType: .avatar, reference: reference, streamable: true, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: true)
                    
                    mediaPlayer.actionAtEnd = .loop(nil)
                    
                    self.photoVideoPlayer = mediaPlayer
                    
                    if let seekTo = video.startTimestamp {
                        mediaPlayer.seek(timestamp: seekTo)
                    }
                    mediaPlayer.attachPlayerView(self.photoVideoView!)
                    self.videoRepresentation = video
                }
            } else {
                self.photoVideoPlayer = nil
                self.photoVideoView?.removeFromSuperview()
                self.photoVideoView = nil
                self.videoRepresentation = nil
            }
                        
            textView.update(data.text)
            
            viewButton.set(font: .normal(.text), for: .Normal)
            viewButton.set(color: item.shouldBlurService ? .white : theme.colors.underSelectedColor, for: .Normal)
            viewButton.set(background: item.shouldBlurService ? item.presentation.chatServiceItemColor.withAlphaComponent(0.5) : item.presentation.colors.accent, for: .Normal)
            viewButton.set(text: strings().chatServiceSuggestView, for: .Normal)
            viewButton.sizeToFit(NSMakeSize(20, 12))
            
            viewButton.layer?.cornerRadius = viewButton.frame.height / 2
            needsLayout = true
        }
        
        func updateAnimatableContent() -> Void {
            let accept = window != nil && window!.isKeyWindow && !NSIsEmptyRect(visibleRect) && !self.isDynamicContentLocked
            
            if let photoVideoPlayer = photoVideoPlayer {
                if accept {
                    photoVideoPlayer.play()
                } else {
                    photoVideoPlayer.pause()
                }
            }
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            if let visualEffect = visualEffect {
                transition.updateFrame(view: visualEffect, frame: NSRect(origin: .zero, size: size))
            }

            if let photo = photo {
                transition.updateFrame(view: photo, frame: photo.centerFrameX(y: 10))
            }

            if let photoVideoView = photoVideoView {
                transition.updateFrame(view: photoVideoView, frame: photoVideoView.centerFrameX(y: 10))
            }

            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: 120)) // 110 + 10
            transition.updateFrame(view: viewButton, frame: viewButton.centerFrameX(y: textView.frame.maxY + 10))
        }

        
        deinit {
            disposable.dispose()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private class SuggestPostView : Control {
        

        private var visualEffect: VisualEffect?
        
        private let textView = InteractiveTextView()
        private let titleView = InteractiveTextView()

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            addSubview(titleView)
            textView.userInteractionEnabled = false
            titleView.userInteractionEnabled = false
            self.scaleOnClick = true
            layer?.cornerRadius = 20
        }
        
        func update(item: ChatServiceItem, data: ChatServiceItem.SuggestPostData, animated: Bool) {
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            
            titleView.set(text: data.titleLayout, context: item.context)
            textView.set(text: data.layout, context: item.context)
            needsLayout = true
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: titleView, frame: titleView.centerFrameX(y: 10))
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: titleView.frame.maxY + 10))
            if let visualEffect {
                transition.updateFrame(view: visualEffect, frame: size.bounds)
            }
        }
        
        deinit {
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    
    private class SuggestPostHeaderView : Control {
        

        private var visualEffect: VisualEffect?
        
        private let attributesView = UniqueAttributesView(frame: .zero)

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(attributesView)
            self.scaleOnClick = false
            layer?.cornerRadius = 20
        }
        
        func update(item: ChatServiceItem, data: ChatServiceItem.SuggestpostHeader, animated: Bool) {
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            
            attributesView.set(attributes: data.attributes, animated: animated)
            attributesView.setFrameSize(NSMakeSize(frame.width, data.attributes.height))
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: attributesView, frame: attributesView.centerFrameX(y: 0))
            if let visualEffect {
                transition.updateFrame(view: visualEffect, frame: size.bounds)
            }
        }
        
        deinit {
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private class GiftOfferView : Control {
        
        private var backgroundView: NSView?
        
        private let textView = TextView(frame: .zero)
        private let infoView = TextView()
        private var replyMarkupView: View?
        
        typealias GiftView = UniqueGiftTileView
        
        private let giftView = GiftView(frame: NSMakeRect(0, 0, 80, 80))
        
        private weak var item: ChatServiceItem?
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            
            addSubview(textView)
            addSubview(infoView)
            addSubview(giftView)
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
            infoView.userInteractionEnabled = false
            infoView.isSelectable = false
            
            giftView.setFrameSize(NSMakeSize(80, 80))
            giftView.layer?.cornerRadius = 20
            giftView.backgroundColor = .clear
            
            scaleOnClick = true
            
            self.setSingle(handler: { [weak self] _ in
                self?.item?.previewGift(morphSource: { [weak self] in self })
            }, for: .Click)
            
        }
        
        private func ensureBackgroundView(isBlurred: Bool, animated: Bool) -> NSView {
            if let current = backgroundView {
                let isCurrentBlur = current is VisualEffect
                if isCurrentBlur != isBlurred {
                    performSubviewRemoval(current, animated: animated)
                    backgroundView = nil
                }
            }
            
            if let backgroundView {
                return backgroundView
            }
            
            let newBackground: NSView
            if isBlurred {
                let effect = VisualEffect(frame: .zero)
                effect.layer?.cornerRadius = 20
                newBackground = effect
            } else {
                let plain = View(frame: .zero)
                plain.layer?.cornerRadius = 20
                newBackground = plain
            }
            
            backgroundView = newBackground
            addSubview(newBackground, positioned: .below, relativeTo: nil)
            
            return newBackground
        }
        
        func update(item: ChatServiceItem, data: ChatServiceItem.OfferData, animated: Bool) {
            self.item = item
            
            let useBlur = item.shouldBlurService
            let bgView = ensureBackgroundView(isBlurred: useBlur, animated: animated)
            
            if let effect = bgView as? VisualEffect {
                effect.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    effect.layer?.opacity = 0.6
                } else {
                    effect.layer?.opacity = 1.0
                }
                self.backgroundColor = .clear
            } else {
                bgView.background = item.presentation.chatServiceItemColor
                bgView.layer?.opacity = 1.0
                self.backgroundColor = .clear
            }
            
            giftView.update(uniqueGift: data.gift, context: item.context)
            textView.update(data.text)
            infoView.update(data.info)
            
            if let replyMarkup = data.replyMarkupModel {
                if replyMarkupView == nil {
                    replyMarkupView = View(
                        frame: CGRect(
                            origin: NSMakePoint(0, data.size.height - replyMarkup.size.height),
                            size: replyMarkup.size
                        )
                    )
                    if let replyMarkupView {
                        addSubview(replyMarkupView)
                    }
                }
                replyMarkup.view = replyMarkupView
                replyMarkup.redraw()
                replyMarkup.layout(transition: .immediate)
            } else if let replyMarkupView {
                performSubviewRemoval(replyMarkupView, animated: animated)
                self.replyMarkupView = nil
            }
            
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: giftView, frame: giftView.centerFrameX(y: 10))
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: giftView.frame.maxY + 10))
            transition.updateFrame(view: infoView, frame: infoView.centerFrameX(y: textView.frame.maxY + 10))
            
            if let backgroundView {
                let bgHeight: CGFloat
                if let replyMarkupView {
                    bgHeight = size.height - replyMarkupView.frame.height - 2.0
                } else {
                    bgHeight = size.height
                }
                let bgFrame = CGRect(origin: .zero, size: NSMakeSize(size.width, bgHeight))
                transition.updateFrame(view: backgroundView, frame: bgFrame)
            }
        }
        
        deinit {
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    
    private class CopyProtectionRequestView : Control {

        private var backgroundView: NSView?

        private let textView = TextView(frame: .zero)
        private let itemsContainer = View(frame: .zero)
        private var itemViews: [TextView] = []
        private var checkViews: [ImageView] = []
        private var replyMarkupView: View?

        private weak var item: ChatServiceItem?

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            addSubview(itemsContainer)
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }

        private func ensureBackgroundView(isBlurred: Bool, animated: Bool) -> NSView {
            if let current = backgroundView {
                let isCurrentBlur = current is VisualEffect
                if isCurrentBlur != isBlurred {
                    performSubviewRemoval(current, animated: animated)
                    backgroundView = nil
                }
            }
            if let backgroundView {
                return backgroundView
            }
            let newBackground: NSView
            if isBlurred {
                let effect = VisualEffect(frame: .zero)
                effect.layer?.cornerRadius = 20
                newBackground = effect
            } else {
                let plain = View(frame: .zero)
                plain.layer?.cornerRadius = 20
                newBackground = plain
            }
            backgroundView = newBackground
            addSubview(newBackground, positioned: .below, relativeTo: nil)
            return newBackground
        }

        func update(item: ChatServiceItem, data: ChatServiceItem.CopyProtectionRequestData, animated: Bool) {
            self.item = item

            let useBlur = item.shouldBlurService
            let bgView = ensureBackgroundView(isBlurred: useBlur, animated: animated)

            if let effect = bgView as? VisualEffect {
                effect.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    effect.layer?.opacity = 0.6
                } else {
                    effect.layer?.opacity = 1.0
                }
                self.backgroundColor = .clear
            } else {
                bgView.background = item.presentation.chatServiceItemColor
                bgView.layer?.opacity = 1.0
                self.backgroundColor = .clear
            }

            textView.update(data.text)

            while itemViews.count > data.items.count {
                itemViews.removeLast().removeFromSuperview()
            }
            while itemViews.count < data.items.count {
                let view = TextView(frame: .zero)
                view.userInteractionEnabled = false
                view.isSelectable = false
                itemsContainer.addSubview(view)
                itemViews.append(view)
            }
            while checkViews.count > data.items.count {
                checkViews.removeLast().removeFromSuperview()
            }
            while checkViews.count < data.items.count {
                let view = ImageView(frame: .zero)
                view.isAccessibilityDecorative = true
                itemsContainer.addSubview(view)
                checkViews.append(view)
            }
            let checkImage = TelegramThemeHooks.shared.image(.iconTodoOtherCheck).precomposed(item.presentation.chatServiceItemTextColor)
            for (i, layout) in data.items.enumerated() {
                itemViews[i].update(layout)
                checkViews[i].image = checkImage
                checkViews[i].sizeToFit()
            }

            if let replyMarkup = data.replyMarkupModel {
                if replyMarkupView == nil {
                    replyMarkupView = View(
                        frame: CGRect(
                            origin: NSMakePoint(0, data.size.height - replyMarkup.size.height),
                            size: replyMarkup.size
                        )
                    )
                    if let replyMarkupView {
                        addSubview(replyMarkupView)
                    }
                }
                replyMarkup.view = replyMarkupView
                replyMarkup.redraw()
                replyMarkup.layout(transition: .immediate)
            } else if let replyMarkupView {
                performSubviewRemoval(replyMarkupView, animated: animated)
                self.replyMarkupView = nil
            }

            self.updateLayout(size: self.frame.size, transition: .immediate)
        }

        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }

        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: 10))

            let checkSpacing: CGFloat = 4
            let checkWidth: CGFloat = checkViews.first?.frame.width ?? 0
            let checkInset: CGFloat = checkViews.isEmpty ? 0 : checkWidth + checkSpacing

            var maxWidth: CGFloat = 0
            for view in itemViews {
                maxWidth = max(maxWidth, view.frame.width + checkInset)
            }
            var y: CGFloat = 0
            for (i, view) in itemViews.enumerated() {
                transition.updateFrame(view: view, frame: NSMakeRect(checkInset, y, view.frame.width, view.frame.height))
                if i < checkViews.count {
                    let checkY = y + floor((view.frame.height - checkViews[i].frame.height) / 2)
                    transition.updateFrame(view: checkViews[i], frame: NSMakeRect(0, checkY, checkViews[i].frame.width, checkViews[i].frame.height))
                }
                y = view.frame.maxY + 10
            }
            let containerHeight = y > 0 ? y - 10 : 0
            let containerFrame = NSMakeRect(floor((size.width - maxWidth) / 2), textView.frame.maxY + 10, maxWidth, containerHeight)
            transition.updateFrame(view: itemsContainer, frame: containerFrame)

            if let backgroundView {
                let bgHeight: CGFloat
                if let replyMarkupView {
                    bgHeight = size.height - replyMarkupView.frame.height - 2.0
                } else {
                    bgHeight = size.height
                }
                let bgFrame = CGRect(origin: .zero, size: NSMakeSize(size.width, bgHeight))
                transition.updateFrame(view: backgroundView, frame: bgFrame)
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private class SetChatThemeView : Control {
        

        private var visualEffect: VisualEffect?
        
        private let textView = TextView(frame: .zero)
        fileprivate let viewButton = TextButton()
        
        typealias GiftView = UniqueGiftTileView
        
        private let giftView = GiftView(frame: NSMakeRect(0, 0, 80, 80))

        private weak var item: ChatServiceItem?
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            addSubview(giftView)
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
            giftView.setFrameSize(NSMakeSize(80, 80))
            giftView.layer?.cornerRadius = 20
            giftView.backgroundColor = .clear
            
            self.scaleOnClick = true
            layer?.cornerRadius = 20
            
            addSubview(viewButton)
            viewButton.scaleOnClick = true
            viewButton.autohighlight = false
            viewButton.userInteractionEnabled = false
            
            self.set(handler: { [weak self] _ in
                self?.item?.openGift(morphSource: { [weak self] in self })
            }, for: .Click)
        }
        
        func update(item: ChatServiceItem, data: ChatServiceItem.SetThemeData, animated: Bool) {
            
            self.item = item
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            
            giftView.update(uniqueGift: data.gift, context: item.context)
            
            self.textView.update(data.text)
            
            viewButton.set(font: .normal(.text), for: .Normal)
            viewButton.set(color: item.shouldBlurService ? .white : theme.colors.underSelectedColor, for: .Normal)
            viewButton.set(background: item.shouldBlurService ? item.presentation.chatServiceItemColor.withAlphaComponent(0.5) : item.presentation.colors.accent, for: .Normal)

            viewButton.set(text: strings().chatServiceSetThemeButtonView, for: .Normal)
            viewButton.sizeToFit(NSMakeSize(20, 12))
                        
            viewButton.layer?.cornerRadius = viewButton.frame.height / 2

            
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: giftView, frame: giftView.centerFrameX(y: 10))
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: giftView.frame.maxY + 10))
            transition.updateFrame(view: viewButton, frame: viewButton.centerFrameX(y: textView.frame.maxY + 10))

            if let visualEffect {
                transition.updateFrame(view: visualEffect, frame: size.bounds)
            }
        }
        
        deinit {
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }



    
    private class WallpaperView : Control {
        
        private let disposable = MetaDisposable()
        private let wallpaper: TransformImageView = TransformImageView(frame: NSMakeRect(0, 0, 100, 100))
        

        private var visualEffect: VisualEffect?
                        
        fileprivate let viewButton = TextButton()
        private var progressView: RadialProgressView?
        private let statusDisposable = MetaDisposable()
        private var progressText: TextView?
        
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(wallpaper)
            addSubview(viewButton)
            viewButton.scaleOnClick = true
            viewButton.autohighlight = false
            self.scaleOnClick = true
            self.wallpaper.layer?.cornerRadius = 50
            layer?.cornerRadius = 20
        }
        
        private var message: Message?
        
        func update(item: ChatServiceItem, data: ChatServiceItem.WallpaperData, animated: Bool) {
            
            let previous = self.message
            
            guard let messageId = item.message?.id else {
                return
            }
            
            
            self.message = item.message
            
            let mediaUpdated = previous?.stableId != item.message?.stableId
            
            let context = item.context
            
            let size = NSMakeSize(100, 100)
            if messageId.namespace == Namespaces.Message.Local {
                self.statusDisposable.set((item.context.account.pendingPeerMediaUploadManager.uploadProgress(messageId: messageId)
                |> deliverOnMainQueue).start(next: { [weak self, weak item] progress in
                    if let item = item {
                        self?.updateProgress(progress, messageId: messageId, item: item, context: context)
                    }
                }))
            } else {
                self.statusDisposable.set(nil)
                self.updateProgress(nil, messageId: messageId, item: item, context: context)
            }
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            let updateImageSignal = wallpaperPreview(accountContext: item.context, palette: item.presentation.colors, wallpaper: data.wallpaper, mode: .thumbnail)
            
            let arguments = TransformImageArguments(corners: .init(), imageSize: size, boundingSize: size, intrinsicInsets: .init())
            
            let settings = TelegramThemeSettings(baseTheme: .classic, accentColor: 0, outgoingAccentColor: nil, messageColors: [], animateMessageColors: false, wallpaper: data.aesthetic)
            
            wallpaper.setSignal(signal: cachedMedia(media: settings, arguments: arguments, scale: System.backingScale), clearInstantly: mediaUpdated)
            
            if !wallpaper.isFullyLoaded {
                wallpaper.setSignal(updateImageSignal, clearInstantly: mediaUpdated, cacheImage: { result in
                    cacheMedia(result, media: settings, arguments: arguments, scale: System.backingScale)
                })
            }
            
            wallpaper.set(arguments: arguments)
                        
            
            
            let text: String
            if data.isIncoming {
                if data.forBoth, data.installed?.isBasicallyEqual(to: data.aesthetic) == true {
                    text = strings().chatServiceRemoveBackground
                } else {
                    text = strings().chatServiceViewBackground
                }
            } else {
                text = strings().chatServiceUpdateBackground
            }
            
            viewButton.set(font: .normal(.text), for: .Normal)
            viewButton.set(color: item.shouldBlurService ? .white : theme.colors.underSelectedColor, for: .Normal)
            viewButton.set(background: item.shouldBlurService ? item.presentation.chatServiceItemColor.withAlphaComponent(0.5) : item.presentation.colors.accent, for: .Normal)

            viewButton.set(text: text, for: .Normal)
            viewButton.sizeToFit(NSMakeSize(20, 12))
                        
            viewButton.layer?.cornerRadius = viewButton.frame.height / 2
            needsLayout = true
        }
        
        
        private func updateProgress(_ progress: Float?, messageId: MessageId, item: ChatServiceItem, context: any AccountContextProtocol) {
                        
            self.viewButton.isHidden = progress != nil

            if let progress = progress {
                let current: RadialProgressView
                if let view = self.progressView {
                    current = view
                } else {
                    current = RadialProgressView(theme:RadialProgressTheme(backgroundColor: .blackTransparent, foregroundColor: .white, icon: playerPlayThumb))
                    current.frame = wallpaper.focus(NSMakeSize(40, 40))
                    self.progressView = current
                    wallpaper.addSubview(current)
                    
                }
                current.fetchControls = .init(fetch: {
                    context.account.pendingPeerMediaUploadManager.cancel(peerId: messageId.peerId)
                })
                current.state = .Fetching(progress: progress, force: false)
                
                
                let progressTextView: TextView
                if let view = self.progressText {
                    progressTextView = view
                } else {
                    progressTextView = TextView()
                    progressTextView.userInteractionEnabled = false
                    progressTextView.isSelectable = false
                    self.progressText = progressTextView
                    self.addSubview(progressTextView)
                }
                let text = strings().chatServiceUploadingWallpaper("\(Int(progress * 100))")
                let attr = NSMutableAttributedString()
                attr.append(string: text, color: item.presentation.chatServiceItemTextColor, font: .normal(.short))
                attr.detectBoldColorInString(with: .medium(.short))
                let layout = TextViewLayout(attr, alignment: .center)
                layout.measure(width: frame.width - 40)
                progressTextView.update(layout)
            } else {
                if let view = self.progressView {
                    performSubviewRemoval(view, animated: true)
                    self.progressView = nil
                }
                if let view = self.progressText {
                    performSubviewRemoval(view, animated: true)
                    self.progressText = nil
                }
            }
            needsLayout = true
        }

        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            if let visualEffect = visualEffect {
                transition.updateFrame(view: visualEffect, frame: NSRect(origin: .zero, size: size))
            }

            transition.updateFrame(view: wallpaper, frame: wallpaper.centerFrameX(y: 10))
            transition.updateFrame(view: viewButton, frame: viewButton.centerFrameX(y: wallpaper.frame.maxY + 10))

            if let progressText = progressText {
                transition.updateFrame(view: progressText, frame: progressText.centerFrameX(y: wallpaper.frame.maxY + 10))
            }
            if let progressView = progressView {
                transition.updateFrame(view: progressView, frame: progressView.centerFrame())
            }
        }

        
        deinit {
            statusDisposable.dispose()
            disposable.dispose()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private class SuggestBirthdayView : Control {
        
        
        private final class DateView: View {
            private let day = ColumnView(frame: .zero)
            private let month = ColumnView(frame: .zero)
            private var year: ColumnView?

            // tweaky constants to match the screenshot vibe
            private struct Metrics {
                static let columnSpacing: CGFloat = 10
                static let verticalGap: CGFloat = 6
                static let sideInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            }

            private final class ColumnView: View {
                private let titleView = TextView()
                private let infoView = TextView()

                // cached sizes from last update(measured)
                private var titleSize: CGSize {
                    return titleView.frame.size
                }
                private var infoSize: CGSize  {
                    return infoView.frame.size
                }

                required init(frame frameRect: NSRect) {
                    super.init(frame: frameRect)
                    addSubview(infoView)
                    addSubview(titleView)
                }

                required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

                func update(title: TextViewLayout, info: TextViewLayout) {
                    self.titleView.update(info)
                    self.infoView.update(title)
                    
                    needsLayout = true
                }

                var requiredWidth: CGFloat { max(titleSize.width, infoSize.width) }

                var requiredHeight: CGFloat { titleSize.height + Metrics.verticalGap + infoSize.height }

                override func layout() {
                    super.layout()
                    // center each text block horizontally within our bounds
                    let titleX = floor((bounds.width - titleSize.width) * 0.5)
                    let infoX  = floor((bounds.width - infoSize.width) * 0.5)

                    // put title at top, info below with a small gap
                    let titleY: CGFloat = bounds.height - titleSize.height
                    titleView.frame = CGRect(origin: CGPoint(x: titleX, y: titleY), size: titleSize)

                    let infoY = titleY - Metrics.verticalGap - infoSize.height
                    infoView.frame = CGRect(origin: CGPoint(x: infoX, y: infoY), size: infoSize)
                }
            }

            required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(day)
                addSubview(month)
            }

            required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

            func update(birthday: TelegramBirthday, color: NSColor) {
                
                
                let titleFont: NSFont = .medium(.text)
                let infoFont: NSFont  = .normal(.text)
               
                
                let dayTitleLayout = TextViewLayout(.initialize(string: strings().birthdayDayTitle, color: color.withAlphaComponent(0.8), font: titleFont))
                let dayInfoLayout = TextViewLayout(.initialize(string: "\(birthday.day)", color: color, font: infoFont))
                dayTitleLayout.measure(width: .greatestFiniteMagnitude)
                dayInfoLayout.measure(width: .greatestFiniteMagnitude)
                day.update(title: dayTitleLayout, info: dayInfoLayout)

                let monthString = monthName(from: Int(birthday.month)) ?? "\(birthday.month)"
                let monthTitleLayout = TextViewLayout(.initialize(string: strings().birthdayMonthTitle, color: color.withAlphaComponent(0.8), font: titleFont))
                let monthInfoLayout = TextViewLayout(.initialize(string: monthString, color: color, font: infoFont))
                monthTitleLayout.measure(width: .greatestFiniteMagnitude)
                monthInfoLayout.measure(width: .greatestFiniteMagnitude)
                month.update(title: monthTitleLayout, info: monthInfoLayout)


                if let y = birthday.year {
                    if year == nil {
                        let yCol = ColumnView(frame: .zero)
                        year = yCol
                        addSubview(yCol)
                    }
                    let yearTitleLayout = TextViewLayout(.initialize(string: "Year", color: color.withAlphaComponent(0.8), font: titleFont))
                    let yearInfoLayout  = TextViewLayout(.initialize(string: "\(y)", color: color, font: infoFont))
                    yearTitleLayout.measure(width: .greatestFiniteMagnitude)
                    yearInfoLayout.measure(width: .greatestFiniteMagnitude)
                    year?.update(title: yearTitleLayout, info: yearInfoLayout)
                } else {
                    year?.removeFromSuperview()
                    year = nil
                }

                needsLayout = true
            }

            override func layout() {
                super.layout()

                let columns: [ColumnView] = [day, month, year].compactMap { $0 }
                guard !columns.isEmpty else { return }

                // natural sizes
                let widths = columns.map { $0.requiredWidth }
                let heights = columns.map { $0.requiredHeight }
                let tallest = heights.max() ?? 0

                let contentHeight = tallest
                let y = floor((bounds.height - contentHeight) * 0.5)

                let sumWidths = widths.reduce(0, +)


                let N = CGFloat(columns.count)
                let W = bounds.width
                let minGap = Metrics.columnSpacing

                var startX: CGFloat = 0
                var gap: CGFloat = 0

                let candidateGap = (W - sumWidths) / (N + 1)
                if candidateGap >= minGap {
                    gap = floor(candidateGap)
                    startX = gap
                } else {
                    gap = minGap
                    let totalContentWidth = sumWidths + gap * (N - 1)
                    startX = floor((W - totalContentWidth) * 0.5)
                }

                var x = startX
                for (i, col) in columns.enumerated() {
                    let w = widths[i]
                    col.frame = CGRect(x: x, y: y, width: w, height: contentHeight)
                    x += w + gap
                }
            }


            private func monthName(from month: Int) -> String? {
                guard (1...12).contains(month) else { return nil }
                let df = DateFormatter()
                df.locale = .current
                return df.monthSymbols[month - 1]
            }
        }

        
        private let dateView: DateView = DateView(frame: .zero)

        private var visualEffect: VisualEffect?
        private let mediaView: MediaAnimatedStickerView = MediaAnimatedStickerView(frame: NSMakeRect(0, 0, 100, 100))
        private let textView = TextView()
        fileprivate let viewButton = TextButton()
        
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(mediaView)
            addSubview(dateView)
            addSubview(viewButton)
            addSubview(textView)
            
            mediaView.userInteractionEnabled = false
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
            viewButton.scaleOnClick = true
            viewButton.autohighlight = false
            self.scaleOnClick = true
            self.mediaView.layer?.cornerRadius = 50
            layer?.cornerRadius = 20
        }
        
        
        func update(item: ChatServiceItem, data: ChatServiceItem.SuggestBirthdayData, animated: Bool) {
            
            
            
            
            self.setSingle(handler: { [weak item, weak self] _ in
                item?.openSuggestBirthday(data.birthday, morphSource: { [weak self] in self })
            }, for: .Click)
            
            textView.update(data.text)
            
            dateView.update(birthday: data.birthday, color: item.presentation.chatServiceItemTextColor)
            
            mediaView.update(with: LocalAnimatedSticker.birthday_cake.file, size: NSMakeSize(80, 80), context: item.context, table: item.table, animated: animated)
   
            
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
            
            self.userInteractionEnabled = data.isIncoming
            
            self.viewButton.isHidden = !data.isIncoming
            viewButton.userInteractionEnabled = false

            viewButton.set(font: .normal(.text), for: .Normal)
            viewButton.set(color: item.shouldBlurService ? .white : theme.colors.underSelectedColor, for: .Normal)
            viewButton.set(background: item.shouldBlurService ? item.presentation.chatServiceItemColor.withAlphaComponent(0.5) : item.presentation.colors.accent, for: .Normal)

            viewButton.set(text: strings().alertView, for: .Normal)
            viewButton.sizeToFit(NSMakeSize(20, 12))
                        
            viewButton.layer?.cornerRadius = viewButton.frame.height / 2
            needsLayout = true
        }
        

        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            if let visualEffect = visualEffect {
                transition.updateFrame(view: visualEffect, frame: NSRect(origin: .zero, size: size))
            }
            

            transition.updateFrame(view: mediaView, frame: mediaView.centerFrameX(y: 10))
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: mediaView.frame.maxY + 10))
            transition.updateFrame(view: dateView, frame: CGRect(origin: NSMakePoint(0, textView.frame.maxY + 10), size: NSMakeSize(size.width, 40)))
            transition.updateFrame(view: viewButton, frame: viewButton.centerFrameX(y: dateView.frame.maxY + 10))

        }

        
        deinit {

        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private class CommunityChangedView : Control {

        private var visualEffect: VisualEffect?
        private let avatar: AvatarControl = AvatarControl(font: .avatar(.title))
        private let textView = TextView()
        fileprivate let viewButton = TextButton()

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            avatar.setFrameSize(NSMakeSize(80, 80))
            addSubview(avatar)
            addSubview(viewButton)
            addSubview(textView)

            avatar.userInteractionEnabled = false
            textView.userInteractionEnabled = false
            textView.isSelectable = false

            viewButton.scaleOnClick = true
            viewButton.autohighlight = false
            self.scaleOnClick = true
            layer?.cornerRadius = 20
        }

        func update(item: ChatServiceItem, data: ChatServiceItem.CommunityChangedData, animated: Bool) {
            let community = item.message?.peers[data.communityId] as? TelegramCommunity
            avatar.setPeer(account: item.context.account, peer: community, cornerRadius: 20)

            textView.update(data.text)

            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                self.backgroundColor = .clear
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }

            viewButton.set(font: .medium(.text), for: .Normal)
            viewButton.set(color: item.presentation.chatServiceItemTextColor, for: .Normal)
            viewButton.set(background: item.shouldBlurService ? item.presentation.blurServiceColor.withAlphaComponent(0.2) : item.presentation.chatServiceItemColor, for: .Normal)
            viewButton.set(text: strings().alertView, for: .Normal)
            viewButton.sizeToFit(NSMakeSize(20, 14))
            viewButton.layer?.cornerRadius = viewButton.frame.height / 2

            needsLayout = true
        }

        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }

        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            if let visualEffect = visualEffect {
                transition.updateFrame(view: visualEffect, frame: NSRect(origin: .zero, size: size))
            }
            transition.updateFrame(view: avatar, frame: avatar.centerFrameX(y: 10))
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: avatar.frame.maxY + 10))
            transition.updateFrame(view: viewButton, frame: viewButton.centerFrameX(y: textView.frame.maxY + 10))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private class _StoryView : Control {

        private let disposable = MetaDisposable()
        fileprivate let mediaView: TransformImageView = TransformImageView(frame: NSMakeSize(74, 74).bounds)
        fileprivate let avatar: AvatarControl = AvatarControl(font: .avatar(.title))
        private let statusView: AvatarStoryIndicatorComponent.IndicatorView = .init(frame: NSMakeSize(80, 80).bounds)
        
        private var visualEffect: VisualEffect?
        
        private let textView = TextView()
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            avatar.setFrameSize(NSMakeSize(74, 74))
            addSubview(mediaView)
            addSubview(avatar)
            addSubview(statusView)
            addSubview(textView)
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            
            avatar.userInteractionEnabled = false
            
            self.scaleOnClick = true
            layer?.cornerRadius = 20
                        
            mediaView.layer?.cornerRadius = mediaView.frame.height / 2
        }
        
        func update(item: ChatServiceItem, data: ChatServiceItem.StoryData, animated: Bool) {
            guard item.message != nil else {
                return
            }
            let context = item.context
                    
            switch data.storyItem {
            case let .item(storyItem):
                if let media = storyItem.media {
                    
                    let updateImageSignal: Signal<ImageDataTransformation, NoError>

                    let imageSize: NSSize
                    if let media = media as? TelegramMediaImage {
                        let reference = ImageMediaReference.story(peer: data.peer, id: storyItem.id, media: media)
                        updateImageSignal = chatMessagePhoto(account: context.account, imageReference: reference, scale: backingScaleFactor, synchronousLoad: false)
                        imageSize = media.representations.last?.dimensions.size ?? ChatHistoryUIHooks.shared.storyLayoutViewSize()
                    } else if let media = media as? TelegramMediaFile {
                        let reference = FileMediaReference.story(peer: data.peer, id: storyItem.id, media: media)
                        updateImageSignal = chatMessageVideo(account: context.account, fileReference:reference, scale: backingScaleFactor)
                        imageSize = media.dimensions?.size ?? ChatHistoryUIHooks.shared.storyLayoutViewSize()
                    } else {
                        updateImageSignal = .complete()
                        imageSize = ChatHistoryUIHooks.shared.storyLayoutViewSize()
                    }
                    
                    let arguments = TransformImageArguments.init(corners: .init(radius: 0), imageSize: imageSize, boundingSize: mediaView.frame.size, intrinsicInsets: .init())
                    
                    mediaView.setSignal(signal: cachedMedia(media: media, arguments: arguments, scale: backingScaleFactor))
                    
                    if !mediaView.isFullyLoaded {
                        mediaView.setSignal(updateImageSignal, cacheImage: { result in
                            cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale)
                        })
                    }
                    mediaView.set(arguments: arguments)
                    avatar.setPeer(account: item.context.account, peer: item.message?.author)
                    avatar.isHidden = !storyItem.isForwardingDisabled
                }
            case .placeholder:
                break
            }
            
            if let component = data.avatar {
                statusView.update(component: component, availableSize: NSMakeSize(74, 74), transition: .immediate)
                statusView.isHidden = false
            } else {
                statusView.isHidden = true
            }
            textView.update(data.text)
                        
            if item.shouldBlurService {
                let current: VisualEffect
                if let view = self.visualEffect {
                    current = view
                } else {
                    current = VisualEffect(frame: bounds)
                    self.visualEffect = current
                    addSubview(current, positioned: .below, relativeTo: self.subviews.first)
                }
                current.bgColor = item.presentation.blurServiceColor
                if item.presentation.colors.isDark {
                    current.layer?.opacity = 0.6
                } else {
                    current.layer?.opacity = 1.0
                }
                
                self.backgroundColor = .clear
                
            } else {
                if let view = visualEffect {
                    performSubviewRemoval(view, animated: animated)
                    self.visualEffect = nil
                }
                self.backgroundColor = item.presentation.chatServiceItemColor
            }
        }
        
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: statusView, frame: statusView.centerFrameX(y: 10))

            transition.updateFrame(view: mediaView, frame: mediaView.centerFrameX(y: 13))
            transition.updateFrame(view: avatar, frame: avatar.centerFrameX(y: 13))

            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: statusView.frame.maxY + 10))
        }

        
        deinit {
            disposable.dispose()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    
    
    private var textView:TextView
    private var imageView:TransformImageView?
    
    private var photoVideoView: MediaPlayerView?
    private var photoVideoPlayer: MediaPlayer?
    private var videoRepresentation: TelegramMediaImage.VideoRepresentation?
    
    private var giftView: GiftView?
    private var walletTransferViewStorage: Any?
    @available(macOS 10.15, *)
    var walletTransferView: ChatWalletTransferView? {
        get {
            return self.walletTransferViewStorage as? ChatWalletTransferView
        }
        set {
            self.walletTransferViewStorage = newValue
        }
    }
    private var storyView: _StoryView?
    private var suggestPostView: SuggestPostView?
    private var suggestPostHeaderView: SuggestPostHeaderView?
    private var suggestView: SuggestView?
    private var wallpaperView: WallpaperView?
    private var suggestChannelsView: ChatChannelSuggestView?
    private var setChatThemeView: SetChatThemeView?
    private var giftOfferView: GiftOfferView?
    private var copyProtectionRequestView: CopyProtectionRequestView?
    private var reactionsView:ChatReactionsView?
    private var suggestBirthdayView: SuggestBirthdayView?
    private var communityChangedView: CommunityChangedView?

    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: SimpleLayer] = [:]
    private let swipingRightView = View()
    private var swipeDelta: CGFloat?
    private var playedSwipeToReplyHaptic = false
    public var endRevealState: SwipeDirection?
    
    public required init(frame frameRect: NSRect) {
        textView = TextView()
        textView.isSelectable = false
        super.init(frame: frameRect)
        addSubview(textView)
        swipingRightView.layer?.masksToBounds = false


        textView.set(handler: { [weak self] control in
            if let item = self?.item as? ChatServiceItem {
                if let _ = item.entry.additionalData.recommendedChannels {
                    item.revealRecommendedChannels()
                } else if let message = item.message, let action = message.extendedMedia as? TelegramMediaAction {
                    switch action.action {
                    case let .messageAutoremoveTimeoutUpdated(timeout, _):
                        if let peer = item.chatInteraction.peer {
                            if peer.canManageDestructTimer, timeout > 0 {
                                item.chatInteraction.showDeleterSetup(control)
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }, for: .Click)
    }
    
    public override var backdorColor: NSColor {
        .clear
    }

    private func photoFrame(for item: ChatServiceItem, arguments: TransformImageArguments, size: NSSize) -> NSRect {
        let offset: CGFloat = item.entry.additionalData.monoforumState == .vertical ? 40 : 0
        let baseY = 6 + textView.frame.height + (item.isBubbled ? 0 : 6)
        return NSRect(
            x: round((size.width - arguments.imageSize.width) / 2) + offset,
            y: baseY,
            width: arguments.imageSize.width,
            height: arguments.imageSize.height
        )
    }

    private func removePhotoVideo() {
        photoVideoPlayer?.pause()
        photoVideoPlayer = nil
        photoVideoView?.removeFromSuperview()
        photoVideoView = nil
        videoRepresentation = nil
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    public override func focusAnimation(_ innerId: AnyHashable?, text: String?) {
        if #available(macOS 10.15, *), let view = walletTransferView {
            view.playHighlight()
        } else {
            super.focusAnimation(innerId, text: text)
        }
    }

    public override func doubleClick(in location: NSPoint) {
        if let item = self.item as? ChatRowItem, item.chatInteraction.presentation.state == .normal {
            if self.hitTest(location) == nil || self.hitTest(location) == self, let message = item.message {
                item.chatInteraction.setupReplyMessage(message, .init(messageId: message.id, quote: nil, innerSubject: nil) )
            }
        }
    }
    
    
    public func updatePlayerIfNeeded() {
        let accept = window != nil && window!.isKeyWindow && !NSIsEmptyRect(visibleRect) && !self.isDynamicContentLocked
        if let photoVideoPlayer = photoVideoPlayer {
            if accept {
                photoVideoPlayer.play()
            } else {
                photoVideoPlayer.pause()
            }
        }
    }
    
    public override func addAccesoryOnCopiedView(innerId: AnyHashable, view: NSView) {
        photoVideoPlayer?.seek(timestamp: 0)
    }

    
    
    public override func mouseUp(with event: NSEvent) {
        if let imageView = imageView, imageView._mouseInside() {
            if let item = self.item as? ChatServiceItem {
                showPhotosGallery(context: item.context, peerId: item.chatInteraction.peerId, firstStableId: item.stableId, item.table, nil)
            }
        } else {
            super.mouseUp(with: event)
        }
    }
    
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool) -> NSView {
        return self.suggestView?.interactive ?? imageView ?? self
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated:animated)
        textView.disableBackgroundDrawing = true

        guard let item = item as? ChatServiceItem else {
            return
        }
        textView.update(item.text)
        
        
        if item.shouldBlurService {
            textView.blurBackground = item.presentation.blurServiceColor
            textView.backgroundColor = .clear
        } else {
            textView.blurBackground = nil
            textView.backgroundColor = .clear
        }

        var interactiveTextView: Bool = false

        if let message = item.message, let action = message.extendedMedia as? TelegramMediaAction {
            switch action.action {
            case let .messageAutoremoveTimeoutUpdated(timeout, _):
                if let peer = item.chatInteraction.peer {
                    interactiveTextView = peer.canManageDestructTimer && timeout > 0
                }
            default:
                break
            }
        }
        textView.scaleOnClick = interactiveTextView


        if let arguments = item.imageArguments, let image = item.image {
            let mediaFrame = photoFrame(for: item, arguments: arguments, size: frame.size)
            let imageView: TransformImageView
            if let current = self.imageView {
                imageView = current
            } else {
                imageView = TransformImageView(frame: mediaFrame)
                self.imageView = imageView
                self.addSubview(imageView)
            }
            imageView.frame = mediaFrame
            imageView.setSignal(signal: cachedMedia(media: image, arguments: arguments, scale: backingScaleFactor))
            imageView.setSignal(chatMessagePhoto(account: item.context.account, imageReference: ImageMediaReference.message(message: MessageReference(item.message!), media: image), toRepresentationSize:NSMakeSize(300, 300), scale: backingScaleFactor, autoFetchFullSize: true), cacheImage: { [weak image] result in
                if let media = image {
                    cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale, positionFlags: nil)
                }
            })
            imageView.set(arguments: arguments)

            if let video = image.videoRepresentations.last {
                let needsNewPlayer = videoRepresentation?.resource.id != video.resource.id
                    || photoVideoPlayer == nil
                    || photoVideoView == nil

                if needsNewPlayer {
                    removePhotoVideo()

                    let photoVideoView = MediaPlayerView()
                    photoVideoView.isEventLess = true
                    self.photoVideoView = photoVideoView
                }

                if let photoVideoView {
                    photoVideoView.layer?.cornerRadius = arguments.corners.topLeft.corner
                    if #available(macOS 10.15, *) {
                        photoVideoView.layer?.cornerCurve = .circular
                    }
                    photoVideoView.frame = mediaFrame
                    if photoVideoView.superview == nil {
                        self.addSubview(photoVideoView)
                    }

                    if needsNewPlayer {
                        let file = TelegramMediaFile(fileId: MediaId(namespace: 0, id: 0), partialReference: nil, resource: video.resource, previewRepresentations: image.representations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: video.resource.size, attributes: [], alternativeRepresentations: [])

                        let userLocation: MediaResourceUserLocation
                        if let id = item.message?.id.peerId {
                            userLocation = .peer(id)
                        } else {
                            userLocation = .other
                        }

                        let mediaPlayer = MediaPlayer(postbox: item.context.account.postbox, userLocation: userLocation, userContentType: .avatar, reference: MediaResourceReference.standalone(resource: file.resource), streamable: true, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: true)
                        mediaPlayer.actionAtEnd = .loop(nil)
                        self.photoVideoPlayer = mediaPlayer

                        if let seekTo = video.startTimestamp {
                            mediaPlayer.seek(timestamp: seekTo)
                        }
                        mediaPlayer.attachPlayerView(photoVideoView)
                        videoRepresentation = video
                        updatePlayerIfNeeded()
                    }
                }
            } else {
                removePhotoVideo()
            }
        } else {
            self.imageView?.removeFromSuperview()
            self.imageView = nil
            removePhotoVideo()
        }
        
        
        if let giftData = item.giftData {
            _ = item.context
            let current: GiftView
            if let view = self.giftView {
                current = view
            } else {
                current = GiftView(frame: NSMakeRect(0, 0, 220, giftData.height))
                self.giftView = current
                addSubview(current)
            }
            current.setFrameSize(NSMakeSize(220, giftData.height))
            current.removeAllHandlers()
            current.set(handler: { [weak item] _ in
                item?.openGift(morphSource: { [weak item] in (item?.view as? ChatServiceRowView)?.giftView })
            }, for: .Click)
            current.update(item: item, data: giftData, animated: animated)
        } else if let view = self.giftView {
            performSubviewRemoval(view, animated: animated)
            self.giftView = nil
        }

        if #available(macOS 10.15, *) {
            if let data = item.walletTransferData {
                let current: ChatWalletTransferView
                if let view = self.walletTransferView {
                    current = view
                } else {
                    current = ChatWalletTransferView(frame: NSMakeRect(0, 0, data.width, data.height))
                    self.walletTransferView = current
                    addSubview(current)
                }
                current.setFrameSize(NSMakeSize(data.width, data.height))
                current.removeAllHandlers()
                current.set(handler: { [weak item] control in
                    // Re-resolve the current card view at morph time: the table can reload, replacing the
                    // row view, so capturing `control`/`self` would go stale by the time the modal closes.
                    item?.openWalletTransfer(decryptComment: (control as? ChatWalletTransferView)?.isMouseInsideEncryptedCaption == true, morphSource: { [weak item] in
                        (item?.view as? ChatServiceRowView)?.walletTransferView?.morphSourceView
                    })
                }, for: .Click)
                current.update(item: item, data: data, animated: animated)
            } else if let view = self.walletTransferView {
                performSubviewRemoval(view, animated: animated)
                self.walletTransferView = nil
            }
        }
        
        if let data = item.suggestPhotoData {
            let current: SuggestView
            if let view = self.suggestView {
                current = view
            } else {
                current = SuggestView(frame: NSMakeRect(0, 0, 200, data.height))
                self.suggestView = current
                addSubview(current)
                
                let open: (Control)->Void = { [weak self] _ in
                    if let item = self?.item as? ChatServiceItem, let message = item.message {
                        if !data.isIncoming {
                            showChatGallery(context: item.context, message: message, item.table, type: .alone, chatMode: item.chatInteraction.mode, chatLocation: item.chatInteraction.chatLocation, cachedPeerData: item.chatInteraction.presentation.cachedData)
                        } else {
                            item.openPhotoEditor(data.image)
                        }
                    }
                }
                current.set(handler: open, for: .Click)
                current.viewButton.set(handler: open, for: .Click)
            }
            
            current.update(item: item, data: data, animated: animated)
        } else if let view = self.suggestView {
            performSubviewRemoval(view, animated: animated)
            self.suggestView = nil
        }
        
        if let data = item.suggestPostStatus {
            let current: SuggestPostView
            if let view = self.suggestPostView {
                current = view
            } else {
                current = SuggestPostView(frame: NSMakeRect(0, 0, 240, data.height))
                self.suggestPostView = current
                addSubview(current)
            }
            
            current.update(item: item, data: data, animated: animated)
            current.setFrameSize(NSMakeSize(240, data.height))
            
            current.setSingle(handler: { [weak item] _ in
                if let messageId = data.messageId {
                    item?.chatInteraction.focusMessageId(nil, .init(messageId: messageId, string: nil), .CenterEmpty)
                }
            }, for: .Click)
        } else if let view = self.suggestPostView {
            performSubviewRemoval(view, animated: animated)
            self.suggestPostView = nil
        }
        
        if let data = item.suggestPostHeader {
            let current: SuggestPostHeaderView
            if let view = self.suggestPostHeaderView {
                current = view
            } else {
                current = SuggestPostHeaderView(frame: NSMakeRect(0, 0, 240, data.height))
                self.suggestPostHeaderView = current
                addSubview(current)
            }
            
            current.update(item: item, data: data, animated: animated)
            current.setFrameSize(NSMakeSize(160, data.height))
            
            
        } else if let view = self.suggestPostHeaderView {
            performSubviewRemoval(view, animated: animated)
            self.suggestPostHeaderView = nil
        }

        
        if let data = item.wallpaperData {
            let current: WallpaperView
            if let view = self.wallpaperView {
                current = view
            } else {
                current = WallpaperView(frame: NSMakeRect(0, 0, 200, data.height))
                self.wallpaperView = current
                addSubview(current)
                
                let open: (Control)->Void = { [weak self] _ in
                    if let item = self?.item as? ChatServiceItem, let messageId = item.message?.id, let data = item.wallpaperData {
                        if data.forBoth, data.installed?.isBasicallyEqual(to: data.aesthetic) == true, data.isIncoming {
                            item.removeBackground()
                        } else {
                            if data.isIncoming {
                                let chatInteraction = item.chatInteraction
                                ChatNavigationHooks.shared.showWallpaperPreview(item.context, data.wallpaper, messageId, { [weak chatInteraction] in
                                    chatInteraction?.closeChatThemes()
                                }, item.context.window)
                            } else {
                                item.chatInteraction.setupChatThemes()
                            }
                        }
                    }
                }
                current.set(handler: open, for: .Click)
                current.viewButton.set(handler: open, for: .Click)
            }
            
            current.update(item: item, data: data, animated: animated)
        } else if let view = self.wallpaperView {
            performSubviewRemoval(view, animated: animated)
            self.wallpaperView = nil
        }

        if let storyData = item.storydata {
            let current: _StoryView
            if let view = self.storyView {
                current = view
            } else {
                current = _StoryView(frame: NSMakeRect(0, 0, 160, storyData.height))
                self.storyView = current
                addSubview(current)
                
                current.set(handler: { [weak self] _ in
                    if let item = self?.item as? ChatRowItem, let message = item.message {
                        item.chatInteraction.openStory(message.id, storyData.media.storyId)
                    }
                }, for: .Click)
            }
            
            current.update(item: item, data: storyData, animated: animated)
        } else if let view = self.storyView {
            performSubviewRemoval(view, animated: animated)
            self.storyView = nil
        }
        
        if let data = item.suggestChannelsData {
            let current: ChatChannelSuggestView
            if let view = self.suggestChannelsView {
                current = view
            } else {
                current = ChatChannelSuggestView(frame: data.size.bounds)
                self.suggestChannelsView = current
                addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2, timingFunction: .easeOut)
                }
            }
            current.setFrameSize(data.size)
            current.set(item: item, data: data, animated: animated)
        } else if let view = self.suggestChannelsView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.suggestChannelsView = nil
        }
        
        if let data = item.setThemeData {
            let current: SetChatThemeView
            if let view = self.setChatThemeView {
                current = view
            } else {
                current = SetChatThemeView(frame: data.size.bounds)
                self.setChatThemeView = current
                addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2, timingFunction: .easeOut)
                }
            }
            current.setFrameSize(data.size)
            current.update(item: item, data: data, animated: animated)
        } else if let view = self.setChatThemeView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.setChatThemeView = nil
        }
        
        if let data = item.offerData {
            let current: GiftOfferView
            if let view = self.giftOfferView {
                current = view
            } else {
                current = GiftOfferView(frame: data.size.bounds)
                self.giftOfferView = current
                addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2, timingFunction: .easeOut)
                }
            }
            current.setFrameSize(data.size)
            current.update(item: item, data: data, animated: animated)
        } else if let view = self.giftOfferView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.giftOfferView = nil
        }
        
        if let data = item.copyProtectionRequestData {
            let current: CopyProtectionRequestView
            if let view = self.copyProtectionRequestView {
                current = view
            } else {
                current = CopyProtectionRequestView(frame: data.size.bounds)
                self.copyProtectionRequestView = current
                addSubview(current)

                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2, timingFunction: .easeOut)
                }
            }
            current.setFrameSize(data.size)
            current.update(item: item, data: data, animated: animated)
        } else if let view = self.copyProtectionRequestView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.copyProtectionRequestView = nil
        }

        if let data = item.suggestBirthdayData {
            let current: SuggestBirthdayView
            if let view = self.suggestBirthdayView {
                current = view
            } else {
                current = SuggestBirthdayView(frame: data.size.bounds)
                self.suggestBirthdayView = current
                addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2, timingFunction: .easeOut)
                }
            }
            current.setFrameSize(data.size)
            current.update(item: item, data: data, animated: animated)
        } else if let view = self.suggestBirthdayView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.suggestBirthdayView = nil
        }

        if let data = item.communityChangedData {
            let current: CommunityChangedView
            if let view = self.communityChangedView {
                current = view
            } else {
                current = CommunityChangedView(frame: data.size.bounds)
                self.communityChangedView = current
                addSubview(current)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2, timingFunction: .easeOut)
                }
            }
            current.setFrameSize(data.size)
            current.update(item: item, data: data, animated: animated)
            let open: (Control)->Void = { [weak self] _ in
                if let item = self?.item as? ChatServiceItem, let data = item.communityChangedData {
                    item.openCommunity(data.communityId)
                }
            }
            current.viewButton.setSingle(handler: open, for: .Click)
        } else if let view = self.communityChangedView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.communityChangedView = nil
        }

        if let reactionsLayout = item.reactionsLayout  {
            if reactionsView == nil {
                reactionsView = ChatReactionsView(frame: reactionsRect(item))
                addSubview(reactionsView!)
            }
            guard let reactionsView = reactionsView else {return}
            reactionsView.update(with: reactionsLayout, animated: animated)
        } else {
            if let view = self.reactionsView {
                self.reactionsView = nil
                performSubviewRemoval(view, animated: animated, scale: true)
            }
        }

        
        updateInlineStickers(context: item.context, view: self.textView, textLayout: item.text)
        
        
        self.needsLayout = true
    }
    
    
    public func reactionsRect(_ item: ChatRowItem) -> CGRect {
        guard let reactionsLayout = item.reactionsLayout else {
            return .zero
        }
        let contentFrameY = frame.height - reactionsLayout.size.height
        
        let frame = self.frame.focusX(reactionsLayout.size, y: contentFrameY).offsetBy(dx: item.monoforumState == .vertical ? 40 : 0, dy: 0)
        
        return frame
    }
    
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? ChatServiceItem else {
            return
        }
        let swipeOffset = swipeDelta ?? 0
        transition.updateFrame(view: swipingRightView, frame: NSMakeRect(size.width + swipeOffset, 0, max(rightRevealWidth, -swipeOffset), size.height))

        if let reactionsView {
            transition.updateFrame(view: reactionsView, frame: reactionsRect(item).offsetBy(dx: swipeOffset, dy: 0))
        }
        
        let offset: CGFloat = (item.entry.additionalData.monoforumState == .vertical ? 40 : 0) + swipeOffset
        
        transition.updateFrame(view: textView, frame: textView.centerFrameX(y: 6, addition: offset))

        let baseY = textView.frame.maxY + (item.isBubbled ? 0 : 6)

        if let imageArguments = item.imageArguments {
            let mediaFrame = photoFrame(for: item, arguments: imageArguments, size: size)
            if let imageView = imageView {
                transition.updateFrame(view: imageView, frame: mediaFrame)
                imageView.set(arguments: imageArguments)
            }

            if let photoVideoView = photoVideoView {
                transition.updateFrame(view: photoVideoView, frame: mediaFrame)
            }
        }
        
        if let view = giftView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if #available(macOS 10.15, *), let view = walletTransferView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: textView.frame.maxY + item.walletTransferSpacing).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = suggestView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = suggestPostView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = setChatThemeView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = giftOfferView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = copyProtectionRequestView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = suggestPostHeaderView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = wallpaperView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = storyView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = suggestChannelsView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = suggestBirthdayView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let view = communityChangedView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: baseY).offsetBy(dx: offset, dy: 0))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
    }


    public override func updateAnimatableContent() -> Void {
        for (_, value) in inlineStickerItemViews {
            if let value = value as? InlineStickerItemLayer, let superview = value.superview {
                var isKeyWindow: Bool = false
                if let window = self.window {
                    if !window.canBecomeKey {
                        isKeyWindow = true
                    } else {
                        isKeyWindow = window.isKeyWindow
                    }
                }
                value.isPlayable = NSIntersectsRect(value.frame, superview.visibleRect) && isKeyWindow && !isEmojiLite
            }
        }
        self.updatePlayerIfNeeded()
        self.suggestView?.updateAnimatableContent()
    }
    
    public override var isEmojiLite: Bool {
        if let item = item as? ChatServiceItem {
            return item.context.isLite(.emoji)
        }
        return super.isEmojiLite
    }
    
    public func updateInlineStickers(context: any AccountContextProtocol, view textView: TextView, textLayout: TextViewLayout) {
        var validIds: [InlineStickerItemLayer.Key] = []
        var index: Int = textView.hashValue

        let textColor: NSColor
        if textLayout.attributedString.length > 0 {
            var range:NSRange = NSMakeRange(NSNotFound, 0)
            let attrs = textLayout.attributedString.attributes(at: 0, effectiveRange: &range)
            textColor = attrs[.foregroundColor] as? NSColor ?? theme.colors.text
        } else {
            textColor = theme.colors.text
        }
        
        for item in textLayout.embeddedItems {
            if let stickerItem = item.value as? InlineStickerItem {
                if case let .attribute(emoji) = stickerItem.source {
                    let id = InlineStickerItemLayer.Key(id: emoji.fileId, index: index)
                    validIds.append(id)
                    
                    
                    var rect: NSRect
                    if textLayout.isBigEmoji {
                        rect = item.rect
                    } else {
                        rect = item.rect
                    }
                    if let item = self.item as? ChatServiceItem, item.isBubbled {
                        rect = rect.offsetBy(dx: 9, dy: 2)
                    }
                    
                    let view: InlineStickerItemLayer
                    if let current = self.inlineStickerItemViews[id] as? InlineStickerItemLayer, current.frame.size == rect.size {
                        view = current
                    } else {
                        self.inlineStickerItemViews[id]?.removeFromSuperlayer()
                        view = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: rect.size, textColor: textColor)
                        self.inlineStickerItemViews[id] = view
                        view.superview = textView
                        textView.addEmbeddedLayer(view)
                    }
                    index += 1
                    var isKeyWindow: Bool = false
                    if let window = window {
                        if !window.canBecomeKey {
                            isKeyWindow = true
                        } else {
                            isKeyWindow = window.isKeyWindow
                        }
                    }
                    view.isPlayable = NSIntersectsRect(rect, textView.visibleRect) && isKeyWindow
                    view.frame = rect
                } else if case let .avatar(peer) = stickerItem.source {
                    let id = InlineStickerItemLayer.Key(id: peer.id.toInt64(), index: index)
                    validIds.append(id)
                    var rect = NSMakeRect(item.rect.minX, item.rect.minY + 1, item.rect.width - 3, item.rect.width - 3)
                   
                    if textView.textLayout?.hasBlock == true {
                        rect.origin.x += 7
                        rect.origin.y += 4
                    } else {
                        rect.origin.y += 2
                    }
                    
                    let view: InlineAvatarLayer
                    if let current = inlineStickerItemViews[id] as? InlineAvatarLayer {
                        view = current
                    } else {
                        inlineStickerItemViews[id]?.removeFromSuperlayer()
                        view = InlineAvatarLayer(context: context, frame: rect, peer: peer)
                        self.inlineStickerItemViews[id] = view
                        textView.addEmbeddedLayer(view)
                    }
                    index += 1
                    view.frame = rect
               }
            }
        }
        
        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
        }
    }
    
    public override func onInsert(_ animation: NSTableView.AnimationOptions, appearAnimated: Bool) {
        if let item = item as? ChatRowItem, !TelegramUtilsHooks.shared.isLite(.animations) {
            if item.isBubbled, appearAnimated {
                self.layer?.animateScaleSpring(from: 0.5, to: 1, duration: 0.4, bounce: false)
                self.layer?.animateAlpha(from: 0, to: 1, duration: 0.35)
            }
        }
    }
    
    public func storyControl(_ storyId: StoryId) -> NSView? {
        return storyView?.mediaView
    }
    
    public var storyMediaControl: NSView? {
        return storyView?.avatar
    }
    
    public var additionalRevealDelta: CGFloat {
        return 0
    }

    public var containerX: CGFloat {
        return swipeDelta ?? 0
    }

    public var width: CGFloat {
        return frame.width
    }

    public var rightRevealWidth: CGFloat {
        return 40
    }

    public var leftRevealWidth: CGFloat {
        return 0
    }

    public func initRevealState() {
        defer {
            updateSwipingRightViewAttachment()
        }
        swipingRightView.removeAllSubviews()
        guard let item = item as? ChatRowItem else {
            return
        }
        swipeDelta = 0
        playedSwipeToReplyHaptic = false
        swipingRightView.frame = NSMakeRect(frame.width, 0, rightRevealWidth, frame.height)

        let control = ChatSwipeToReplyView(frame: CGRect(origin: .zero, size: ChatSwipeToReplyView.controlSize))
        control.update(item: item)
        control.updateProgress(0)
        swipingRightView.addSubview(control)
        control.centerY(x: ChatRowView.revealActionInset)
    }

    public func moveReveal(delta: CGFloat) {
        if swipingRightView.subviews.isEmpty {
            initRevealState()
        }
        swipeDelta = delta
        updateLayout(size: frame.size, transition: .immediate)

        guard let control = swipingRightView.subviews.first as? ChatSwipeToReplyView else {
            return
        }
        control.centerY(x: ChatRowView.revealActionInset)

        let progress = min(1, max(0, -delta / ChatRowView.replyRevealThreshold))
        control.updateProgress(progress)

        if progress == 1 {
            if !playedSwipeToReplyHaptic {
                playedSwipeToReplyHaptic = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
            }
        } else {
            playedSwipeToReplyHaptic = false
        }
    }

    public func completeReveal(direction: SwipeDirection) {
        let delta = swipeDelta ?? 0
        swipeDelta = nil
        playedSwipeToReplyHaptic = false
        endRevealState = nil

        if case .right = direction, -delta >= ChatRowView.replyRevealThreshold {
            _ = (item as? ChatRowItem)?.replyAction()
        }

        updateLayout(size: frame.size, transition: .animated(duration: 0.2, curve: .easeOut))

        if let control = swipingRightView.subviews.first as? ChatSwipeToReplyView {
            control.animateOut(completion: { [weak control, weak self] in
                control?.removeFromSuperview()
                self?.updateSwipingRightViewAttachment()
            })
        }
    }

    private func updateSwipingRightViewAttachment() {
        if swipingRightView.subviews.isEmpty {
            swipingRightView.removeFromSuperview()
        } else if swipingRightView.superview == nil {
            addSubview(swipingRightView, positioned: .above, relativeTo: textView)
        }
    }
    
}

final class UniqueGiftTileView: View {
    private let stickerView: MediaAnimatedStickerView = MediaAnimatedStickerView(frame: NSMakeSize(50, 50).bounds)
    private let backgroundView = UniqueGiftBackgroundView(frame: NSMakeRect(0, 0, 80, 80))
    private var content: UniqueGiftBackgroundContent?
    private var context: (any AccountContextProtocol)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(stickerView)
        stickerView.userInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(uniqueGift: StarGift.UniqueGift, context: any AccountContextProtocol) {
        self.content = UniqueGiftBackgroundContent(gift: uniqueGift)
        self.context = context
        backgroundView.isHidden = self.content == nil
        if let file = uniqueGift.file {
            let parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .onceEnd, media: file)
            stickerView.update(with: file, size: stickerView.frame.size, context: context, table: nil, parameters: parameters, animated: false)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        stickerView.center()
        backgroundView.frame = bounds
        if let content = self.content, let context = self.context {
            backgroundView.update(context: context, content: content, style: .item(giftCenterY: stickerView.frame.midY, cornerRadius: 20))
        }
    }
}
