import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import ChatUI
import GalleryUI
import GeneralRows
import InstantPageUI
import LocalAnimations
import Localization
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import Strings
import InputDataUI

public class PeerMediaWebpageRowItem: PeerMediaRowItem {
    
    public private(set) var textLayout:TextViewLayout?
    public private(set) var linkLayouts:[TextViewLayout] = []
    
    public private(set) var iconText:NSAttributedString?
    public private(set) var firstCharacter:String?
    public private(set) var icon:TelegramMediaImage?
    public private(set) var iconArguments:TransformImageArguments?
    public private(set) var thumb:CGImage? = nil
    //, gallery: GalleryAppearType = .history
    public override init(_ initialSize:NSSize, _ interface:ChatInteraction, _ object: PeerMediaSharedEntry, galleryType: GalleryAppearType = .history, gallery: @escaping(Message, GalleryAppearType)->Void, viewType: GeneralViewType = .legacy, inset: NSEdgeInsets = NSEdgeInsetsZero, customTheme: GeneralRowItem.Theme? = nil) {
        super.init(initialSize, interface, object, galleryType: galleryType, gallery: gallery, viewType: viewType, inset: inset, customTheme: customTheme)

        
        var linkLayouts:[TextViewLayout] = []
        
        var links:[NSAttributedString] = []

        for attr in message.attributes {
            if let attr = attr as? TextEntitiesMessageAttribute {
                for entity in attr.entities {
                    inner: switch entity.type {
                    case .Email:
                        let attributed = NSMutableAttributedString()
                        let link = message.text.nsstring.substring(with: NSMakeRange(min(entity.range.lowerBound, message.text.length), max(min(entity.range.upperBound - entity.range.lowerBound, message.text.length - entity.range.lowerBound), 0)))
                        let range = attributed.append(string: link, color: theme.colors.link, font: .normal(.text))
                        attributed.addAttribute(.link, value: ChatHistoryLink.inApp(for: link as NSString, context: interface.interactionContext, peerId: interface.peerId, openInfo: interface.openInfo, applyProxy: interface.applyProxy, confirm: false), range: range)
                        links.append(attributed)
                    case .Url:
                        let attributed = NSMutableAttributedString()
                        let link = message.text.nsstring.substring(with: NSMakeRange(min(entity.range.lowerBound, message.text.length), max(min(entity.range.upperBound - entity.range.lowerBound, message.text.length - entity.range.lowerBound), 0)))
                        let range = attributed.append(string: link, color: theme.colors.link, font: .normal(.text))
                        attributed.addAttribute(.link, value: ChatHistoryLink.inApp(for: link as NSString, context: interface.interactionContext, peerId: interface.peerId, openInfo: interface.openInfo, applyProxy: interface.applyProxy, confirm: false), range: range)
                        links.append(attributed)
                    case let .TextUrl(url):
                        let attributed = NSMutableAttributedString()
                        let range = attributed.append(string: url, color: theme.colors.link, font: .normal(.text))
                        attributed.addAttribute(.link, value: ChatHistoryLink.inApp(for: url as NSString, context: interface.interactionContext, peerId:
                            interface.peerId, openInfo: interface.openInfo, applyProxy: interface.applyProxy, confirm: false), range: range)
                        links.append(attributed)
                    default:
                        break inner
                    }
                }
                break
            }
        }
        
        for attributed in links {
            let linkLayout = TextViewLayout(attributed, maximumNumberOfLines: 1, truncationType: .middle)
            linkLayout.interactions = LinkHooks.shared.globalLinkExecutor()
            linkLayouts.append(linkLayout)
        }
        
        
        if let webpage = message.anyMedia as? TelegramMediaWebpage {
            if case let .Loaded(content) = webpage.content {
                
                var hostName: String = ""
                if let url = URL(string: content.url), let host = url.host, !host.isEmpty {
                    hostName = host
                    firstCharacter = host.prefix(1)
                } else {
                    firstCharacter = content.url.prefix(1)
                }
                
                var iconImageRepresentation:TelegramMediaImageRepresentation? = nil
                if let image = content.image {
                    iconImageRepresentation = largestImageRepresentation(image.representations)
                } else if let file = content.file {
                    iconImageRepresentation = largestImageRepresentation(file.previewRepresentations)
                }
                
                if let iconImageRepresentation = iconImageRepresentation {
                    icon = TelegramMediaImage(imageId: MediaId(namespace: 0, id: arc4random64()), representations: [iconImageRepresentation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
                    
                    let imageCorners = ImageCorners(radius: .cornerRadius)
                    iconArguments = TransformImageArguments(corners: imageCorners, imageSize: iconImageRepresentation.dimensions.size.aspectFilled(PeerMediaIconSize), boundingSize: PeerMediaIconSize, intrinsicInsets: NSEdgeInsets())
                }
                
               
                let attributedText = NSMutableAttributedString()

                let _ = attributedText.append(string: content.title ?? content.websiteName ?? hostName, color: theme.colors.text, font: .medium(.text))
                
                if let text = content.text {
                    let _ = attributedText.append(string: "\n")
                    let _ = attributedText.append(string: text, color: theme.colors.text, font: .normal(.short))
                    ChatHistoryLink.detectLinks(attributedText, type: [.Links], context: interface.interactionContext, openInfo: interface.openInfo)
                }
                
                textLayout = TextViewLayout(attributedText, maximumNumberOfLines: 3, truncationType: .end)
            }
        } else if let linkLayout = linkLayouts.first {
            let attributed = linkLayout.attributedString
            var hostName: String = attributed.string
            if let url = URL(string: attributed.string), let host = url.host, !host.isEmpty {
                hostName = host
                firstCharacter = host.prefix(1)
            } else {
                firstCharacter = "L"
            }
            
            let attributedText = NSMutableAttributedString()

            let _ = attributedText.append(string: hostName, color: theme.colors.text, font: .medium(.text))
            if !hostName.isEmpty {
                let _ = attributedText.append(string: "\n")
            }
            if message.text != linkLayout.attributedString.string {
                let _ = attributedText.append(string: message.text, color: theme.colors.text, font: .normal(.short))
            }
            textLayout = TextViewLayout(attributedText, maximumNumberOfLines: 3, truncationType: .end)
           
        }
        
        if icon == nil {
            thumb = generateMediaEmptyLinkThumb(color: theme.colors.listBackground, textColor: theme.colors.listGrayText, host: firstCharacter?.uppercased() ?? "H")
        }
        
        textLayout?.interactions = LinkHooks.shared.globalLinkExecutor()
        if message.stableId != UINT32_MAX {
            textLayout?.interactions.menuItems = { [weak self] inside in
                guard let `self` = self else {return .complete()}
                return self.menuItems(in: NSZeroPoint) |> map { items in
                    var items = items
                    if let layout = self.textLayout, layout.selectedRange.hasSelectText {
                        let text = layout.attributedString.attributedSubstring(from: layout.selectedRange.range)
                        items.insert(ContextMenuItem(strings().textCopy, handler: {
                            copyToClipboard(text.string)
                        }, itemImage: MenuAnimation.menu_copy.value), at: 0)
                        items.insert(ContextSeparatorItem(), at: 1)
                    }
                    return items
                }
            }
        }
        
        for linkLayout in linkLayouts {
            linkLayout.interactions = TextViewInteractions(processURL: { [weak self] url in
                if let webpage = self?.message.anyMedia as? TelegramMediaWebpage, let `self` = self, let url = webpage.content.url {
                    if self.hasInstantPage {
                        FeatureNavigationHooks.shared.openInstantView(self.interface.interactionContext, url, webpage)
                        return
                    }
                }
                LinkHooks.shared.globalLinkExecutor().processURL(url)
            }, copy: { [weak linkLayout] in
                guard let linkLayout = linkLayout else {return false}
                copyToClipboard(linkLayout.attributedString.string)
                return false
            }, localizeLinkCopy: { link in
                return strings().textContextCopyLink
            })
        }
        
        self.linkLayouts = linkLayouts
        
        _ = makeSize(initialSize.width, oldWidth: 0)
        
    }
    
    public var hasInstantPage: Bool {
        if let webpage = message.anyMedia as? TelegramMediaWebpage {
            if case let .Loaded(content) = webpage.content {
                if let instantPage = content.instantPage {
                    let hasInstantPage:()->Bool = {
                        if instantPage._parse().blocks.count == 3 {
                            switch instantPage._parse().blocks[2] {
                            case let .collage(_, caption), let .slideshow(_, caption):
                                return !attributedStringForRichText(caption.text, styleStack: InstantPageTextStyleStack()).string.isEmpty
                            default:
                                break
                            }
                        }
                        return true
                    }
                    
                    if content.websiteName?.lowercased() == "instagram" || content.websiteName?.lowercased() == "twitter" || content.websiteName?.lowercased() == "telegram" || content.type == "telegram_album"  {
                        return false
                    }
                    return hasInstantPage()
                }
            }
        }
        return false
    }
    
    public var isArticle: Bool {
        return message.stableId == UINT32_MAX
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        
        let result = super.makeSize(width, oldWidth: oldWidth)
        textLayout?.measure(width: self.blockWidth - contentInset.left - contentInset.right - self.viewType.innerInset.left - self.viewType.innerInset.right)
        
        for linkLayout in linkLayouts {
            linkLayout.measure(width: self.blockWidth - contentInset.left - contentInset.right - self.viewType.innerInset.left - self.viewType.innerInset.right - (hasInstantPage ? 10 : 0))
        }
        
        var textSizes:CGFloat = 0
        if let tLayout = textLayout {
            textSizes += tLayout.layoutSize.height
        }
        for linkLayout in linkLayouts {
            textSizes += linkLayout.layoutSize.height
        }
        
        contentSize = NSMakeSize(width, max(textSizes + contentInset.top + contentInset.bottom + 2.0, 40))
        
        return result
    }
    
    public override func viewClass() -> AnyClass {
        return PeerMediaWebpageRowView.self
    }

    public override var accessibilityLabel: String? {
        return linkLayouts.first?.attributedString.string ?? textLayout?.attributedString.string ?? strings().voiceOverCommonLink
    }
}


public class PeerMediaWebpageRowView : PeerMediaRowView {
    
    private var imageView:TransformImageView
    private var textView:TextView
    private var linkViews:[TextView] = []
    private var ivImage: ImageView? = nil
    public required init(frame frameRect: NSRect) {
        imageView = TransformImageView(frame:NSMakeRect(0, 0, PeerMediaIconSize.width, PeerMediaIconSize.height))
        textView = TextView()
        super.init(frame: frameRect)
        
        
        addSubview(imageView)
        addSubview(textView)
    }
    
   public override func layout() {
        super.layout()
        if let item = item as? PeerMediaWebpageRowItem {
            ivImage?.setFrameOrigin(item.contentInset.left, textView.frame.maxY + 6.0)
            textView.setFrameOrigin(NSMakePoint(item.contentInset.left,item.contentInset.top))
            
            var linkY: CGFloat = textView.frame.maxY + 2.0
            
            for linkView in self.linkViews {
                linkView.setFrameOrigin(NSMakePoint(item.contentInset.left + (item.hasInstantPage ? 10 : 0), linkY))
                linkY += linkView.frame.height
            }
            
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        guard let item = item as? PeerMediaWebpageRowItem, item.isArticle else {
            super.mouseUp(with: event)
            return
        }
       // item.linkLayout?.interactions.processURL(event)
        
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        let previous = self.item as? PeerMediaFileRowItem

        super.set(item: item,animated:animated)
        textView.backgroundColor = backdorColor
        if let item = item as? PeerMediaWebpageRowItem {
            
            textView.userInteractionEnabled = !item.isArticle
            
            textView.update(item.textLayout, origin: NSMakePoint(item.contentInset.left,item.contentInset.top))
            

            while self.linkViews.count > item.linkLayouts.count {
                let last = self.linkViews.removeLast()
                last.removeFromSuperview()
            }
            while self.linkViews.count < item.linkLayouts.count {
                let new = TextView()
                addSubview(new)
                self.linkViews.append(new)
            }
            
            var linkY: CGFloat = textView.frame.maxY + 2.0
            
            for (i, linkView) in self.linkViews.enumerated() {
                let linkLayout = item.linkLayouts[i]
                linkView.backgroundColor = backdorColor
                linkView.update(linkLayout, origin: NSMakePoint(item.contentInset.left + (item.hasInstantPage ? 10 : 0), linkY))
                linkY += linkLayout.layoutSize.height
            }
            
            if item.hasInstantPage {
                if ivImage == nil {
                    ivImage = ImageView()
                    ivImage?.isAccessibilityDecorative = true
                }
                ivImage!.image = theme.icons.chatInstantView
                ivImage!.sizeToFit()
                addSubview(ivImage!)
            } else {
                ivImage?.removeFromSuperview()
                ivImage = nil
            }
            
            let updateIconImageSignal:Signal<ImageDataTransformation,NoError>
            if let icon = item.icon {
                updateIconImageSignal = chatWebpageSnippetPhoto(account: item.interface.interactionContext.account, imageReference: ImageMediaReference.message(message: MessageReference(item.message), media: icon), scale: backingScaleFactor, small:true)
            } else {
                updateIconImageSignal = .complete()
            }
            
            
            if let icon = item.icon, let arguments = item.iconArguments {
                imageView.setSignal(signal: cachedMedia(media: icon, arguments: arguments, scale: System.backingScale), clearInstantly: previous?.message.id != item.message.id)
            } else {
                imageView.clear()
            }
            
            if !imageView.isFullyLoaded {
                if !imageView.hasImage {
                    imageView.layer?.contents = item.thumb
                }
                imageView.setSignal(updateIconImageSignal, clearInstantly: false, animate: true, cacheImage: { result in
                    if let icon = item.icon, let arguments = item.iconArguments {
                        cacheMedia(result, media: icon, arguments: arguments, scale: System.backingScale, positionFlags: nil)
                    }
                })
            }
            if let arguments = item.iconArguments {
                imageView.set(arguments: arguments)
            }

            
            needsLayout = true
        }
    }
    
    public override func updateSelectingMode(with selectingMode:Bool, animated:Bool = false) {
        super.updateSelectingMode(with: selectingMode, animated: animated)
        self.textView.isSelectable = !selectingMode
        for linkView in self.linkViews {
            linkView.userInteractionEnabled = !selectingMode
        }
        self.textView.userInteractionEnabled = !selectingMode
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
