import Cocoa
import TelegramCore
import InAppSettings
import Postbox
import TGUIKit
import ChatHistoryModel
import TelegramContext
import TelegramMediaUtils
import TelegramTheme

public class ChatFileMediaItem: ChatMediaItem {

    
    public override init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        super.init(initialSize, chatInteraction, context, object, theme: theme)
        self.parameters = ChatMediaLayoutParameters.layout(for: (self.media as! TelegramMediaFile), isWebpage: false, chatInteraction: chatInteraction, presentation: .make(for: object.message!, account: context.account, renderType: object.renderType, theme: theme), automaticDownload: object.additionalData.automaticDownload.isDownloable(object.message!), isIncoming: object.message!.isIncoming(context.account, object.renderType == .bubble), isFile: true, autoplayMedia: object.autoplayMedia, isChatRelated: true, isCopyProtected: object.message!.isCopyProtected(cachedData: chatInteraction.presentation.cachedData))
        
        (self.parameters as? ChatFileLayoutParameters)?.showMedia = { [weak self] message in
            guard let `self` = self else {return}
            
            var type: ChatGalleryAppearType = .history
            if let parameters = self.parameters as? ChatMediaGalleryParameters, parameters.isWebpage {
                type = .alone
            } else if message.containsSecretMedia {
                type = .secret
            }
                        
            showChatGallery(context: context, message: message, self.table, self.parameters as? ChatMediaGalleryParameters, type: type, chatMode: self.chatInteraction.mode, chatLocation: self.chatInteraction.chatLocation, contextHolder: self.chatInteraction.contextHolder(), cachedPeerData: self.chatInteraction.presentation.cachedData, analyticsContext: self.chatInteraction.captureAnalyticsContext())
        }
            
        (self.parameters as? ChatFileLayoutParameters)?.showMessage = { [weak self] message in
            self?.chatInteraction.focusMessageId(nil, .init(messageId: message.id, string: nil), .CenterEmpty)
        }
        
    }
    
    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        
        var width = width
        
        let parameters = self.parameters as! ChatFileLayoutParameters
        let optionalWidth = parameters.makeLabelsForWidth(width)
                
        width = min(width, optionalWidth)
        
        return NSMakeSize(width, parameters.hasThumb ? 70 : 40)
    }
    

    public override var lastLineContentWidth: ChatRowItem.LastLineData? {
        if let lastLineContentWidth = super.lastLineContentWidth {
            return lastLineContentWidth
        }
        let file = media as! TelegramMediaFile
        if file.previewRepresentations.isEmpty {
            let parameters = self.parameters as! ChatFileLayoutParameters

            let mwidth = max(parameters.uploadingLayout.layoutSize.width, parameters.downloadingLayout.layoutSize.width, parameters.finderLayout.layoutSize.width)

            let width = mwidth + 50
            return ChatRowItem.LastLineData(width: width, single: false)
        }
        return nil
    }
    
    
    public override func contentNode() -> ChatMediaContentView.Type {
        return ChatFileContentView.self
    }
    
}
