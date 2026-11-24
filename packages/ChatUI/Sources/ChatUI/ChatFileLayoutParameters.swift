import Cocoa
import TelegramCore
import InAppSettings
import Postbox
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils

public class ChatFileLayoutParameters : ChatMediaGalleryParameters {
    public var nameNode:TextNode = TextNode()
    public var name:(TextNodeLayout, TextNode)?
    public let hasThumb:Bool
    public let fileName:String
    public let finderLayout: TextViewLayout
    public let saveLayout: TextViewLayout
    public let hasFileAction: Bool
    public let downloadLayout: TextViewLayout
    public let uploadingLayout: TextViewLayout
    public let downloadingLayout: TextViewLayout
    public init(fileName:String, hasThumb: Bool, presentation: ChatMediaPresentation, media: Media, automaticDownload: Bool, isIncoming: Bool, autoplayMedia: AutoplayMediaPreferences, isChatRelated: Bool = false, isCopyProtected: Bool) {
        self.fileName = fileName
        self.hasThumb = hasThumb
        self.hasFileAction = (!((media as? TelegramMediaFile)?.resource is LocalFileReferenceMediaResource) || isChatRelated) && !isCopyProtected
        
        let file = media as! TelegramMediaFile
        
        
        self.uploadingLayout = TextViewLayout(.initialize(string: strings().messagesFileStateFetchingOut2("100"), font: .normalMonospaced(.text)), alwaysStaticItems: true)
        self.downloadingLayout = TextViewLayout(.initialize(string: strings().messagesFileStateFetchingIn2("100"), font: .normalMonospaced(.text)), alwaysStaticItems: true)
        
        
        var attr:NSMutableAttributedString = NSMutableAttributedString()
        let _ = attr.append(string: .prettySized(with: file.elapsedSize), color: presentation.grayText, font: .normalMonospaced(.text))
        if !(file.resource is LocalFileReferenceMediaResource) || isChatRelated  {
            if !isCopyProtected {
                let _ = attr.append(string: " - ", color: presentation.grayText, font: .normal(.text))
                
                let range = attr.append(string: strings().messagesFileStateLocal, color: theme.bubbled && !isIncoming ? presentation.grayText : presentation.link, font: .medium(FontSize.text))
                attr.addAttribute(NSAttributedString.Key.link, value: "chat://file/finder", range: range)
            }
        }
        finderLayout = TextViewLayout(attr, maximumNumberOfLines: 1, alwaysStaticItems: true)

        attr = NSMutableAttributedString()
        let _ = attr.append(string: .prettySized(with: file.elapsedSize), color: presentation.grayText, font: .normalMonospaced(.text))
        if !(file.resource is LocalFileReferenceMediaResource) || isChatRelated  {
            if !isCopyProtected {
                let _ = attr.append(string: " - ", color: presentation.grayText, font: .normal(.text))
                let range = attr.append(string: strings().messagesFileStateSave, color: theme.bubbled && !isIncoming ? presentation.grayText : presentation.link, font: .medium(FontSize.text))
                attr.addAttribute(NSAttributedString.Key.link, value: "chat://file/save", range: range)
            }
        }
        saveLayout = TextViewLayout(attr, maximumNumberOfLines: 1, alwaysStaticItems: true)
        
        attr = NSMutableAttributedString()
        let _ = attr.append(string: .prettySized(with: file.elapsedSize), color: presentation.grayText, font: .normalMonospaced(.text))
        if !(file.resource is LocalFileReferenceMediaResource) || isChatRelated {
            let _ = attr.append(string: " - ", color: presentation.grayText, font: .normal(.text))
            let range = attr.append(string: strings().messagesFileStateRemote, color:  theme.bubbled && !isIncoming ? presentation.grayText : presentation.link, font: .medium(.text))
            attr.addAttribute(NSAttributedString.Key.link, value: "chat://file/download", range: range)
        }
        downloadLayout = TextViewLayout(attr, maximumNumberOfLines: 1, alwaysStaticItems: true)
        

        super.init(isWebpage: false, presentation: presentation, media: media, automaticDownload: automaticDownload, autoplayMedia: autoplayMedia, isRevealed: nil)
        
    }
    public override func makeLabelsForWidth(_ width: CGFloat) -> CGFloat {
        self.name = TextNode.layoutText(maybeNode: nameNode, .initialize(string: fileName , color: presentation.text, font: .medium(.text)), nil, 1, .middle, NSMakeSize(width - (hasThumb ? 80 : 50), 20), nil,false, .left)
        

        uploadingLayout.measure(width: width - (hasThumb ? 80 : 50))
        downloadingLayout.measure(width: width - (hasThumb ? 80 : 50))
        
        downloadLayout.measure(width: width - (hasThumb ? 80 : 50))
        finderLayout.measure(width: width - (hasThumb ? 80 : 50))
        saveLayout.measure(width: width - (hasThumb ? 80 : 50))
        
        return max(downloadLayout.layoutSize.width, uploadingLayout.layoutSize.width, finderLayout.layoutSize.width, downloadingLayout.layoutSize.width, self.name!.0.size.width) + (hasThumb ? 80 : 50)

    }
}
