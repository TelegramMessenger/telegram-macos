import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import ColorPalette
import SwiftSignalKit
import InstantPageUI
import Localization
import PremiumUI
import Strings
import TelegramContext
import TelegramLinks
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer
import StarsUI


public struct WPLayoutPresentation {
    public let text: NSColor
    public let activity: PeerNameColors.Colors
    public let link: NSColor
    public let selectText: NSColor
    public let ivIcon: CGImage
    public let renderType: ChatItemRenderType
    public let pattern: Int64?
}

public class WPLayout: Equatable {
    public let content:TelegramMediaWebpageLoadedContent
    public let parent:Message
    public let context: any AccountContextProtocol
    public let fontSize:CGFloat
    public weak var table:TableView?
    
    private var _siteNameAttr:NSAttributedString?
    
    public private(set) var size:NSSize = NSZeroSize
    public private(set) var contentRect:NSRect = NSZeroRect
    
    public private(set) var textLayout:TextViewLayout?
    private let mayCopyText: Bool
    
    public var insets: NSEdgeInsets = NSEdgeInsets(left: 8.0, right: 6, top: 3, bottom: 5)
    public var imageInsets: NSEdgeInsets = NSEdgeInsets(left: 0, right: 0, top: 3, bottom: 0)
    
    public var mediaCount: Int? {
        if let instantPage = content.instantPage, isGalleryAssemble, content.type == "telegram_album" {
            if let block = instantPage._parse().blocks.filter({ value in
                if case .slideshow = value {
                    return true
                } else if case .collage = value {
                    return true
                } else {
                    return false
                }
            }).last {
                switch block {
                case let .slideshow(items, _), let .collage(items , _):
                    if items.count == 1 {
                        return nil
                    }
                    return items.count
                default:
                    break
                }
               
            }
        }
        return nil
    }
    
    public var webPage: TelegramMediaWebpage {
        if let game = parent.anyMedia as? TelegramMediaGame {
            return TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: arc4random64()), content: .Loaded(TelegramMediaWebpageLoadedContent.init(url: "", displayUrl: "", hash: 0, type: "game", websiteName: game.title, title: nil, text: game.description, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: game.image, file: game.file, story: nil, attributes: [], instantPage: nil)))
        }
        return parent.anyMedia as! TelegramMediaWebpage
    }
    
    public let presentation: WPLayoutPresentation
    public let chatInteraction: ChatInteraction
    
    private var _approximateSynchronousValue: Bool = false
    public var approximateSynchronousValue: Bool {
        get {
            let result = _approximateSynchronousValue
            _approximateSynchronousValue = false
            return result
        }
    }
    private let entities: [MessageTextEntity]?
    public let adAttribute: AdMessageAttribute?
    public let uniqueGift: StarGift.UniqueGift?
    
    public init(with content:TelegramMediaWebpageLoadedContent, context: any AccountContextProtocol, chatInteraction:ChatInteraction, parent:Message, fontSize: CGFloat, presentation: WPLayoutPresentation, approximateSynchronousValue: Bool, mayCopyText: Bool, entities: [MessageTextEntity]? = nil, adAttribute: AdMessageAttribute? = nil, uniqueGift: StarGift.UniqueGift? = nil) {
        self.content = content
        self.context = context
        self.uniqueGift = uniqueGift
        self.presentation = presentation
        self.chatInteraction = chatInteraction
        self.mayCopyText = mayCopyText
        self.parent = parent
        self.fontSize = fontSize
        self.entities = entities
        self.adAttribute = adAttribute
        self._approximateSynchronousValue = approximateSynchronousValue
        
        if let websiteName = content.websiteName {
            let siteName: String
            switch content.type {
            case "telegram_background":
                siteName = strings().chatWPBackgroundTitle
            case "telegram_voicechat":
                siteName = strings().chatWPVoiceChatTitle
            default:
                siteName = websiteName
            }
            _siteNameAttr = .initialize(string: siteName, color: presentation.activity.main, font: .medium(.text))
        }
        
    
        
        
        let attributedText:NSMutableAttributedString = NSMutableAttributedString()
        
        
        if let siteName = _siteNameAttr {
            attributedText.append(siteName)
            attributedText.append(string: "\n", font: .normal(.text))
        }
        var text = content.type != "telegram_background" ? content.text?.trimmed : nil
        
        if text == nil, let story = content.story, let storedItem = parent.associatedStories[story.storyId]?.get(Stories.StoredItem.self) {
            switch storedItem {
            case let .item(item):
                text = item.text.prefixWithDots(100)
            default:
                break
            }
        }
        
        var title: String? = content.title ?? content.author
        
        for attr in content.attributes {
            switch attr {
            case let .giftAuction(auction):
                if let auctionStartDate = auction.gift.generic?.auctionStartDate, auctionStartDate > context.timestamp {
                    title = strings().chatWPAuctionUpcoming
                }
            default:
                break
            }
        }
        
        if let title = title, content.type != "telegram_background" {
            _ = attributedText.append(string: title, color: presentation.text, font: .medium(fontSize))
            if text != nil {
                _ = attributedText.append(string: "\n")
            }
        }
        
        
        if let text = text, uniqueGift == nil, content.type != "telegram_auction" {
            
            let entitites = entities ?? []

            let attributed = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entitites)], for: text, message: nil, context: context, fontSize: fontSize, openInfo: chatInteraction.openInfo, textColor: presentation.text, linkColor: presentation.link, monospacedPre: presentation.text, monospacedCode: presentation.text, isDark: false, bubbled: false).mutableCopy() as! NSMutableAttributedString

            InlineStickerItem.apply(to: attributed, associatedMedia: parent.associatedMedia, entities: entitites, isPremium: true, offset: 0)

            attributedText.insert(attributed, at: attributedText.length)
            
        }
        if attributedText.length > 0 {
            var p: ParsingType = [.Links]
            let wname = content.websiteName?.lowercased() ?? ""
            if wname == "instagram" || wname == "twitter" {
                p = [.Links, .Mentions, .Hashtags]
            }
            if adAttribute == nil {
                ChatHistoryLink.detectLinks(attributedText, type: p, color: presentation.link, dotInMention: wname == "instagram")
            }

            
            textLayout = TextViewLayout(attributedText, maximumNumberOfLines:10, truncationType: .end, cutout: nil, selectText: presentation.selectText, strokeLinks: presentation.renderType == .bubble, alwaysStaticItems: true, mayItems: mayCopyText)
            
            
            let interactions = LinkHooks.shared.globalLinkExecutor()
            interactions.resolveLink = { link in
                 if let link = link as? ChatHistoryInAppLinkValue {
                    if case .external(let url, _) = link.chatHistoryInAppLink {
                        switch wname {
                        case "instagram":
                            if url.hasPrefix("@") {
                                return "https://instagram.com/\(url.nsstring.substring(from: 1))"
                            }
                            if url.hasPrefix("#") {
                                return "https://instagram.com/explore/tags/\(url.nsstring.substring(from: 1))"
                            }
                        case "twitter":
                            if url.hasPrefix("@") {
                                return "https://twitter.com/\(url.nsstring.substring(from: 1))"
                            }
                            if url.hasPrefix("#") {
                                return "https://twitter.com/hashtag/\(url.nsstring.substring(from: 1))"
                            }
                        default:
                            break
                        }
                    }
                    return link.link
                }
                return nil
                
            }
            interactions.processURL = { link in
                if let link = link as? ChatHistoryInAppLinkValue {
                    var link = link
                    if case .external(let url, _) = link.chatHistoryInAppLink {
                        switch wname {
                        case "instagram":
                            if url.hasPrefix("@") {
                                link = ChatHistoryLink.external(link: "https://instagram.com/\(url.nsstring.substring(from: 1))", false)
                            }
                            if url.hasPrefix("#") {
                                link = ChatHistoryLink.external(link: "https://instagram.com/explore/tags/\(url.nsstring.substring(from: 1))", false)
                            }
                        case "twitter":
                            if url.hasPrefix("@") {
                                link = ChatHistoryLink.external(link: "https://x.com/\(url.nsstring.substring(from: 1))", false)
                            }
                            if url.hasPrefix("#") {
                                link = ChatHistoryLink.external(link: "https://x.com/hashtag/\(url.nsstring.substring(from: 1))", false)
                            }
                        default:
                            link = ChatHistoryLink.inApp(for: url.nsstring, context: context, peerId: nil, openInfo: chatInteraction.openInfo, hashtag: nil, command: nil, applyProxy: nil, confirm: false)
                            break
                        }
                    }
                    if let adAttribute = adAttribute {
                        chatInteraction.markAdAction(adAttribute.opaqueId, adAttribute.hasContentMedia)
                    }
                    ChatHistoryLink.execute(inapp: link)
                }
            }
            
            textLayout?.interactions = interactions
            
        }
//        attributedText.fixUndefinedEmojies()
        
    }
    
    public var isMediaClickable: Bool {
       return true
    }
    
    public var isStory: Bool {
        return content.story != nil
    }
    
    public func openStory() {
        if let story = content.story {
            chatInteraction.openStory(parent.id, story.storyId)
        }
    }
    
    public var isGalleryAssemble: Bool {
        if content.story != nil {
            return false
        }
        if content.embedType == "iframe" {
            return false
        }
        if (content.type == "video" && content.type == "video/mp4") || content.type == "photo" || ((content.websiteName?.lowercased() == "instagram" || content.websiteName?.lowercased() == "twitter" || content.websiteName?.lowercased() == "telegram")) || content.text == nil {
            return !content.url.isEmpty && content.type != "telegram_background" && content.type != "telegram_theme"
        }
       
        return content.type == "telegram_album" && content.type != "telegram_background" && content.type != "telegram_theme"
    }
    
    public var wallpaper: ChatHistoryInAppLinkValue? {
        if content.type == "telegram_background" {
            return ChatHistoryLink.inApp(for: content.url as NSString, context: context)
        }
        return nil
    }
    public var isPatternWallpaper: Bool {
        return content.file?.mimeType == "application/x-tgwallpattern"
    }
    
    public var wallpaperReference: WallpaperReference? {
        if let wallpaper = wallpaper {
            switch wallpaper.chatHistoryInAppLink {
            case let .wallpaper(_, _, preview):
                inner: switch preview {
                case let .slug(slug, _):
                    return .slug(slug)
                default:
                    break inner
                }
            default:
                break
            }
        }
        return nil
    }
    
    public var themeLink: ChatHistoryInAppLinkValue? {
        if content.type == "telegram_theme" {
            return ChatHistoryLink.inApp(for: content.url as NSString, context: context)
        }
        return nil
    }
    
    public var isTheme: Bool {
        return content.type == "telegram_theme" && (content.file != nil || content.isCrossplatformTheme)
    }
    
    public var isAuction: Bool {
        return content.type == "telegram_auction"
    }
    
    public var auctionAttribute: TelegramMediaWebpageGiftAuctionAttribute? {
        for attr in self.content.attributes {
            switch attr {
            case let .giftAuction(attr):
                return attr
            default:
                break
            }
        }
        return nil
    }
    
    public func viewClass() -> AnyClass {
        return WPArticleContentView.self
    }
    public private(set) var oldWidth:CGFloat = 0
    
    public func measure(width: CGFloat)  {
        
    }
    
    public func layout(with size:NSSize) -> Void {
        
        var buttonSize: CGFloat = 0
        if action_text != nil {
            buttonSize += 39
        }
        
        var size = NSMakeSize(max(size.width, hasInstantPage ? 160 : size.width), size.height + buttonSize)
        
        if uniqueGift != nil {
            size.height += 50
        }
        
        self.contentRect = NSMakeRect(insets.left, insets.top, size.width, size.height)
        self.size = NSMakeSize(size.width + insets.left + insets.right, size.height + insets.bottom + insets.top)
    }
    
    public var action_text:String? {
        
        if let adAtribute = parent.adAttribute {
            return adAtribute.buttonText
        }
        
        for attribute in content.attributes {
            switch attribute {
            case .starGift:
                return strings().chatViewCollectible
            case .giftAuction:
                return strings().chatJoinAuction
            default:
                break
            }
        }
        
        if self.content.type == "telegram_call" {
            return strings().chatJoinGroupCall
        }
        
        if self.isProxyConfig {
            return strings().chatApplyProxy
        } else if hasInstantPage {
            return strings().chatInstantView
        }
        if !self.hasInstantPage {
            let content = self.content
            let link = ChatHistoryLink.inApp(for: content.url.nsstring, context: context, messageId: parent.id, openInfo: chatInteraction.openInfo)
            switch link.chatHistoryInAppLink {
            case let .followResolvedName(_, _, postId, _, _, action, _):
                var actionIsSource: Bool = false
                if case .source = action {
                    actionIsSource = true
                }
                if let action = action, !actionIsSource {
                    inner: switch action {
                    case let .joinVoiceChat(hash):
                        if hash != nil {
                            return strings().chatMessageJoinVoiceChatAsSpeaker
                        } else {
                            return strings().chatMessageJoinVoiceChatAsListener
                        }
                    case .makeWebview:
                        return strings().chatMessageOpenApp
                    default:
                        break inner
                    }
                } else {
                    switch content.type {
                    case "telegram_channel":
                        return strings().chatMessageViewChannel
                    case "telegram_group":
                        return strings().chatMessageViewGroup
                    case "telegram_megagroup":
                        return strings().chatMessageViewGroup
                    case "telegram_gigagroup":
                        return strings().chatMessageViewGroup
                    case "telegram_user":
                        return strings().chatMessageSendMessage
                    default:
                        break
                    }
                }
                if let postId = postId, postId > 0 {
                    return strings().chatMessageActionShowMessage
                }
            case .folder:
                return strings().chatMessageViewChatList
            case .story:
                return strings().chatMessageOpenStory
            case .boost:
                return strings().chatMessageBoostChannel
            case .comments:
                return strings().chatMessageActionShowMessage
            case .joinchat:
                return strings().chatMessageActionRequestToJoin
            default:
                break
            }
            if self.wallpaper != nil {
                return strings().chatViewBackground
            }
            if self.isTheme {
                return strings().chatActionViewTheme
            }
        }
        return nil
    }
    
    public func premiumBoarding() {
        if context.isPremium, let opaqueId = self.adAttribute?.opaqueId {
            _ = context.engine.accountData.updateAdMessagesEnabled(enabled: false).startStandalone()
            chatInteraction.removeAd(opaqueId)
            showModalText(for: context.window, text: strings().chatDisableAdTooltip)
        } else {
            prem(with: PremiumBoardingController(context: context, source: .no_ads, openFeatures: true), for: context.window)
        }
    }
    
    public var isLeadingMedia: Bool {
        return content.type == "telegram_ad" && content.isMediaLargeByDefault == true
    }
    
    public func openUniqueGift(morphSource: (() -> NSView?)?) -> Bool {
        guard let uniqueGift = self.uniqueGift else {
            return false
        }
        let context = self.context
        _ = showModalProgress(signal: context.engine.payments.getUniqueStarGift(slug: uniqueGift.slug), for: context.window).start(next: { gift in
            showModal(with: StarGift_Nft_Controller(context: context, gift: .unique(gift), source: .quickLook(nil, gift), transaction: nil), for: context.window, morphSource: morphSource)
        }, error: { error in
            switch error {
            case .alreadyBurned:
                showModalText(for: context.window, text: strings().chatServiceGiftUsedForCrafting)
            default:
                showModalText(for: context.window, text: strings().unknownError)
            }
        })
        return true
    }

    public func invokeAction(morphSource: (() -> NSView?)? = nil) {
        if openUniqueGift(morphSource: morphSource) {
            return
        }
        if self.hasInstantPage {
            ChatNavigationHooks.shared.openBrowserTab(context, .instantView(url: self.content.url, webPage: parent.media[0] as! TelegramMediaWebpage, anchor: nil))
           // showInstantPage(InstantPageViewController(context, webPage: , message: parent.text))
        } else if let proxyConfig = self.proxyConfig {
            ChatNavigationHooks.shared.applyExternalProxy(proxyConfig, context.sharedContext.accountManager)
        } else if let adAttribute = parent.adAttribute {
            let link: ChatHistoryInAppLinkValue = ChatHistoryLink.inApp(for: adAttribute.url.nsstring, context: context, openInfo: chatInteraction.openInfo)
            ChatHistoryLink.execute(inapp: link)
            chatInteraction.markAdAction(adAttribute.opaqueId, adAttribute.hasContentMedia)
        } else {
            let link = ChatHistoryLink.inApp(for: self.content.url.nsstring, context: context, messageId: parent.id, openInfo: chatInteraction.openInfo)
            ChatHistoryLink.execute(inapp: link, morphSource: morphSource)
        }
    }
    
    public var hasInstantPage: Bool {
        if let instantPage = content.instantPage {
            if content.websiteName?.lowercased() == "instagram" || content.websiteName?.lowercased() == "twitter" || content.type == "telegram_album" {
                return false
            }
            let instantPage = instantPage._parse()
            if instantPage.blocks.count == 3 {
                switch instantPage.blocks[2] {
                case let .collage(_, caption), let .slideshow(_, caption):
                    return !attributedStringForRichText(caption.text, styleStack: InstantPageTextStyleStack()).string.isEmpty
                default:
                    break
                }
            }
            
            return true
        }
        return  false
    }
    
    public var isStickerPreview: Bool {
        for attr in content.attributes {
            switch attr {
            case .stickerPack:
                return true
            case .giftCollection:
                return true
            case .aiTextStyle:
                return true
            default:
                break
            }
        }
        return false
    }

    public var stickerFiles: [TelegramMediaFile] {
        for attr in content.attributes {
            switch attr {
            case let .stickerPack(attribute):
                return attribute.files
            case let .giftCollection(attr):
                return attr.files
            default:
                break
            }
        }
        return []
    }

    public var aiTextStyleEmojiFileId: Int64? {
        for attr in content.attributes {
            switch attr {
            case let .aiTextStyle(attr):
                return attr.emojiFileId
            default:
                break
            }
        }
        return nil
    }
    
    public var isProxyConfig: Bool {
        return content.type == "proxy"
    }
    
    public var proxyConfig: ProxyServerSettings? {
        return proxySettings(from: content.url).0
    }
    
}

public func ==(lhs:WPLayout, rhs:WPLayout) -> Bool {
    return lhs.content == rhs.content
}
