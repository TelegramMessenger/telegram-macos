import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramMediaResources
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils



public class ChatMapContentView: ChatMediaContentView {
    private let imageView:TransformImageView = TransformImageView()
    private let iconView:ImageView = ImageView()
    private var textView:TextView?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        imageView.addSubview(iconView)
        iconView.isAccessibilityDecorative = true
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func executeInteraction(_ isControl: Bool) {
        if let parameters = self.parameters as? ChatMediaMapLayoutParameters {
            parameters.execute()
        }
    }
    
    public override func layout() {
        super.layout()
        if let parameters = parameters as? ChatMediaMapLayoutParameters {
            imageView.set(arguments: parameters.arguments)
            imageView.setFrameSize(parameters.arguments.imageSize)
            iconView.center()
            textView?.update(parameters.venueText)
            textView?.centerY(x:70)
        }
    }
    
    public override func update(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, parameters: ChatMediaLayoutParameters?, animated: Bool = false, positionFlags: LayoutPositionFlags? = nil, approximateSynchronousValue: Bool = false) {
        let versionUpdated = parent?.stableVersion != self.parent?.stableVersion
        var mediaUpdated = self.media == nil || !media.isSemanticallyEqual(to: self.media!) || versionUpdated
        iconView.image = theme.icons.chatMapPin
        iconView.sizeToFit()

        super.update(with: media, size: size, context: context, parent: parent, table: table, parameters: parameters, animated: animated, positionFlags: positionFlags)
        
        if let positionFlags = positionFlags {
            let maskLayer: CAShapeLayer = CAShapeLayer()
            maskLayer.path = CGPath.bubbleCorners(size: frame.size, corners: .chatMedia(positionFlags, bubble: parameters?.bubbleCorners(), flat: parameters?.flatSides ?? []))
            layer?.mask = maskLayer
        } else {
            layer?.mask = nil
        }
        
        
        
        if let parameters = parameters as? ChatMediaMapLayoutParameters, let resource = parameters.resource as? MapSnapshotMediaResource {
            
            imageView.setSignal(signal: cachedMedia(media: media, arguments: parameters.arguments, scale: backingScaleFactor, positionFlags: positionFlags), clearInstantly: false)
            mediaUpdated = mediaUpdated && !self.imageView.hasImage
            
            imageView.setSignal( chatMapSnapshotImage(account: context.account, resource: resource), clearInstantly: false, animate: mediaUpdated, cacheImage: { [weak media] result in
                if let media = media {
                    cacheMedia(result, media: media, arguments: parameters.arguments, scale: System.backingScale, positionFlags: positionFlags)
                }
            })
            
            if parameters.isVenue {
                if textView == nil {
                    textView = TextView()
                    
                    textView?.isSelectable = false
                    addSubview(textView!)
                }
                
            }
        }
        needsLayout = true
    }
    
}
