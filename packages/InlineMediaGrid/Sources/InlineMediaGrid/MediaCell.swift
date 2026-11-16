import Cocoa
import TelegramCore
import TelegramMediaPlayer
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramMedia
import ColorPalette
import Localization
import InAppSettings
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import MessageUtils
import AvatarUI

private let story_privacy_some_users = TelegramThemeHooks.shared.image(.iconPeerStorySomeUsers).precomposed(.white)
private let story_privacy_contacts = TelegramThemeHooks.shared.image(.iconPeerStoryContacts).precomposed(.white)
private let story_privacy_close_friends = TelegramThemeHooks.shared.image(.iconPeerStoryCloseFriends).precomposed(.white)
private let story_pinned = TelegramThemeHooks.shared.image(.iconPeerStoryPinned).precomposed(.white)

public protocol MediaCellLayoutable {
    var context: any AccountContextProtocol { get }
    var viewType:MediaCell.Type { get }
    var frame: NSRect { get }
    var corners:ImageCorners { get }
    var hasImmediateData: Bool { get }
    var isSecret: Bool { get }
    var isSpoiler: Bool { get }
    var isSensitive: Bool { get }
    var id: MessageId { get }
    var peerId: PeerId { get }

    var imageMedia: ImageMediaReference? { get }
    var fileMedia: FileMediaReference? { get }
    

    func isEqual(to: MediaCellLayoutable) -> Bool
    
    func makeImageReference(_ image: TelegramMediaImage) -> ImageMediaReference
    func makeFileReference(_ file: TelegramMediaFile) -> FileMediaReference

}

public struct MediaCellLayoutItem : Equatable, MediaCellLayoutable {
    public static func == (lhs: MediaCellLayoutItem, rhs: MediaCellLayoutItem) -> Bool {
        return lhs.message == rhs.message && lhs.corners == rhs.corners && lhs.frame == rhs.frame
    }
    
    public func isEqual(to: MediaCellLayoutable) -> Bool {
        if let to = to as? MediaCellLayoutItem {
            return to == self
        } else {
            return false
        }
    }
    
    public let message: Message
    public let frame: NSRect
    public let viewType:MediaCell.Type
    public let corners:ImageCorners
    public let context: any AccountContextProtocol
    public init(message: Message, frame: NSRect, viewType: MediaCell.Type, corners: ImageCorners, context: any AccountContextProtocol) {
        self.message = message
        self.frame = frame
        self.viewType = viewType
        self.corners = corners
        self.context = context
    }
    
    public var isSecret: Bool {
        return self.message.isMediaSpoilered || self.message.containsSecretMedia
    }
    public var isSpoiler: Bool {
        return self.message.isMediaSpoilered || self.message.isSensitiveContent(platform: "ios", contentSettings: context.contentSettings)
    }
    
    public var isSensitive: Bool {
        return self.message.isSensitiveContent(platform: "ios", contentSettings: context.contentSettings) && !context.contentConfig.sensitiveContentEnabled
    }
    
    public var id: MessageId {
        return self.message.id
    }
    public var peerId: PeerId {
        return self.message.id.peerId
    }

    public var imageMedia: ImageMediaReference? {
        if let media = self.message.media.first as? TelegramMediaImage {
            return .message(message: MessageReference(message), media: media)
        }
        return nil
    }
    public var fileMedia: FileMediaReference? {
        if let media = self.message.media.first as? TelegramMediaFile {
            return .message(message: MessageReference(message), media: media)
        }
        return nil
    }
    
    public func makeImageReference(_ image: TelegramMediaImage) -> ImageMediaReference {
        return .message(message: MessageReference(message), media: image)
    }
    public func makeFileReference(_ file: TelegramMediaFile) -> FileMediaReference {
        return .message(message: MessageReference(message), media: file)
    }

    
    public var hasImmediateData: Bool {
        if let image = message.media.first as? TelegramMediaImage {
            return image.immediateThumbnailData != nil
        } else if let file = message.media.first as? TelegramMediaFile {
            return file.immediateThumbnailData != nil
        }
        return false
    }
}

final class StoryViewsView: ShadowView {
    private static let icon = TelegramThemeHooks.shared.image(.iconChannelViews).precomposed(.white)
    
    let iconLayer = SimpleLayer()
    private let textView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconLayer.masksToBounds = true
        layer?.addSublayer(iconLayer)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        self.isEventLess = true
        self.textView.isEventLess = true
        
        self.direction = .vertical(true)
        self.shadowBackground = NSColor.black.withAlphaComponent(0.25)
    }
    
    func update(_ seenCount: Int, animated: Bool) {
        let layout = TextViewLayout.init(.initialize(string: seenCount.prettyNumber, color: .white, font: .normal(.small)))
        layout.measure(width: .greatestFiniteMagnitude)
        self.textView.update(layout)
        
        self.iconLayer.contents = StoryViewsView.icon
        self.iconLayer.frame.size = StoryViewsView.icon.backingSize
        
    }
    
    override func layout() {
        super.layout()
        self.iconLayer.frame.origin = NSMakePoint(10, round((frame.height - iconLayer.frame.height) / 2.0))
        self.textView.centerY(x: self.iconLayer.frame.maxX + 5)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class StoryPrivacyView: ShadowView {
    let iconLayer = SimpleLayer()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconLayer.masksToBounds = true
        layer?.addSublayer(iconLayer)
        
        self.isEventLess = true
        
        self.direction = .vertical(false)
        self.shadowBackground = NSColor.black.withAlphaComponent(0.25)
    }
    
    func update(_ privacy: EngineStoryPrivacy, isPinned: Bool, animated: Bool) {
        let image: CGImage?
        if isPinned {
            image = story_pinned
        } else {
            switch privacy.base {
            case .closeFriends:
                image = story_privacy_close_friends
            case .everyone:
                image = nil
            case .contacts:
                image = story_privacy_contacts
            case .nobody:
                image = story_privacy_some_users
            }
        }
        self.iconLayer.contents = image
        if let image {
            self.iconLayer.frame.size = image.backingSize
        }
    }
    
    override func layout() {
        super.layout()
        self.iconLayer.frame.origin = NSMakePoint(frame.width - iconLayer.frame.width - 5, round((frame.height - iconLayer.frame.height) / 2.0))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class StoryHeaderView: View {
    private let avatar = AvatarControl(font: .avatar(5))
    private let nameView = TextView()
    private let shadowView = ShadowView(frame: .zero)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(shadowView)
        shadowView.direction = .vertical(false)
        shadowView.shadowBackground = NSColor.black.withAlphaComponent(0.6)
        addSubview(self.avatar)
        addSubview(self.nameView)
        
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
        self.avatar.userInteractionEnabled = false
        
        self.avatar.setFrameSize(NSMakeSize(15, 15))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func set(_ peer: EnginePeer, context: any AccountContextProtocol) {
        self.avatar.setPeer(account: context.account, peer: peer._asPeer())
        
        let layout = TextViewLayout(.initialize(string: peer._asPeer().displayTitle, color: NSColor.white, font: .medium(.small)), maximumNumberOfLines: 1)
        layout.measure(width: frame.width - (10 + 15 + 5))
        
        self.nameView.update(layout)
    }
    
    override func layout() {
        super.layout()
        shadowView.frame = bounds
        self.avatar.centerY(x: 5)
        self.nameView.centerY(x: avatar.frame.maxX + 5)
    }
}


open class MediaCell : Control {
    
    private var selectionView:SelectingControl?
    
    public var selecting: Bool? {
        return selectionView?.isSelected
    }
    
    fileprivate let imageView: TransformImageView
    public private(set) var layoutItem: MediaCellLayoutable?
    fileprivate var context: (any AccountContextProtocol)?
    
    private var unsupported: TextView?
    
    private var inkView: MediaInkView?
    

    public required init(frame frameRect: NSRect) {
        imageView = TransformImageView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height))
        super.init(frame: frameRect)
        addSubview(imageView)
        userInteractionEnabled = false
    }
    private var storyViews: StoryViewsView?
    private var storyPrivacy: StoryPrivacyView?
    
    
    private var storyHeaderView: StoryHeaderView?

    open override func mouseMoved(with event: NSEvent) {
        superview?.superview?.mouseMoved(with: event)
    }
    open override func mouseEntered(with event: NSEvent) {
        superview?.superview?.mouseEntered(with: event)
    }
    open override func mouseExited(with event: NSEvent) {
        superview?.superview?.mouseExited(with: event)
    }
    open func update(layout: MediaCellLayoutable, selected: Bool?, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        let previousLayout = self.layoutItem
        self.layoutItem = layout
        self.context = context
        let isUpdated = previousLayout == nil || !previousLayout!.isEqual(to: layout)
        if isUpdated, !(self is MediaGifCell) {
            let media: Media
            let imageSize: NSSize
            let cacheArguments: TransformImageArguments
            let signal: Signal<ImageDataTransformation, NoError>
            
            if let imageMedia = layout.imageMedia, let largestSize = largestImageRepresentation(imageMedia.media.representations)?.dimensions.size {
                media = imageMedia.media
                imageSize = largestSize.aspectFilled(layout.frame.size)
                cacheArguments = TransformImageArguments(corners: layout.corners, imageSize: imageSize, boundingSize: layout.frame.size, intrinsicInsets: NSEdgeInsets())
                
                if layout.isSecret {
                    signal = chatSecretPhoto(account: context.account, imageReference: imageMedia, scale: backingScaleFactor, synchronousLoad: false)
                } else {
                    signal = mediaGridMessagePhoto(account: context.account, imageReference: imageMedia, scale: backingScaleFactor)
                }

            } else if let fileMedia = layout.fileMedia  {
                let largestSize = fileMedia.media.previewRepresentations.last?.dimensions.size ?? fileMedia.media.imageSize
                imageSize = largestSize.aspectFilled(layout.frame.size)
                cacheArguments = TransformImageArguments(corners: layout.corners, imageSize: imageSize, boundingSize: layout.frame.size, intrinsicInsets: NSEdgeInsets())
                if layout.isSecret {
                    media = fileMedia.media
                    signal = chatSecretMessageVideo(account: context.account, fileReference: fileMedia, scale: backingScaleFactor)
                } else if fileMedia.media.previewRepresentations.isEmpty {
                    let blur = TelegramMediaImage(imageId: fileMedia.media.fileId, representations: [], immediateThumbnailData: fileMedia.media.immediateThumbnailData, reference: nil, partialReference: nil, flags: TelegramMediaImageFlags())
                    media = blur
                    signal = mediaGridMessagePhoto(account: context.account, imageReference: layout.makeImageReference(blur), scale: backingScaleFactor)
                } else {
                    media = fileMedia.media
                    signal = chatMessageVideo(account: context.account, fileReference: fileMedia, scale: backingScaleFactor)
                }
            } else {
                
                let current: TextView
                if let view = self.unsupported {
                    current = view
                } else {
                    current = TextView()
                    self.unsupported = current
                    current.userInteractionEnabled = false
                    current.isSelectable = false
                    addSubview(current)
                }
                let text = TextViewLayout(.initialize(string: strings().mediaCellUnsupported, color: theme.colors.listGrayText, font: .italic(.short)))
                text.measure(width: layout.frame.width - 10)
                current.update(text)
                
                self.imageView.clear()
                needsLayout = true
                return
            }
            
            if let unsupported = self.unsupported {
                performSubviewRemoval(unsupported, animated: animated)
                self.unsupported = nil
            }
            
            self.imageView.setSignal(signal: cachedMedia(media: media, arguments: cacheArguments, scale: backingScaleFactor), clearInstantly: previousLayout?.id != layout.id)
            
           
            if !self.imageView.isFullyLoaded {
                self.imageView.setSignal(signal, animate: animated, cacheImage: { result in
                    cacheMedia(result, media: media, arguments: cacheArguments, scale: System.backingScale)
                })
            }
            self.imageView.set(arguments: cacheArguments)
        }
        if layout.isSpoiler {
            let current: MediaInkView
            if let view = self.inkView {
                current = view
            } else {
                current = MediaInkView(frame: layout.frame.size.bounds)
                current.userInteractionEnabled = false
                self.inkView = current
                
                self.addSubview(current)
            }
            
            let image: TelegramMediaImage
            if let current = layout.imageMedia {
                image = current.media
            } else if let current = layout.fileMedia {
                image = TelegramMediaImage(imageId: current.media.fileId, representations: current.media.previewRepresentations, immediateThumbnailData: current.media.immediateThumbnailData, reference: nil, partialReference: nil, flags: TelegramMediaImageFlags())
            } else {
                fatalError()
            }
            let imageReference = layout.makeImageReference(image)
            current.update(isRevealed: false, updated: isUpdated, context: layout.context, imageReference: imageReference, size: layout.frame.size, corners: nil, synchronousLoad: false, isSensitive: layout.isSensitive, payAmount: nil)
            current.frame = layout.frame.size.bounds
        } else {
            if let view = self.inkView {
                view.userInteractionEnabled = false
                performSubviewRemoval(view, animated: animated)
                self.inkView = nil
            }
        }
        
        if let layout = layout as? StoryCellLayoutItem, let itemPeer = layout.item.peer {
            let current: StoryHeaderView
            if let view = self.storyHeaderView {
                current = view
            } else {
                current = StoryHeaderView(frame: NSMakeRect(0, 0, frame.width, 25))
                addSubview(current)
                self.storyHeaderView = current
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.set(itemPeer, context: layout.context)
        } else if let view = self.storyHeaderView {
            performSubviewRemoval(view, animated: animated)
            self.storyHeaderView = nil
        }
        
        if let layout = layout as? StoryCellLayoutItem, let seenCount = layout.item.storyItem.views?.seenCount {
            let current: StoryViewsView
            if let view = self.storyViews {
                current = view
            } else {
                current = StoryViewsView(frame: NSMakeRect(0, 0, frame.width, 20))
                addSubview(current)
                self.storyViews = current
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.update(seenCount, animated: animated)
        } else if let view = self.storyViews {
            performSubviewRemoval(view, animated: animated)
            self.storyViews = nil
        }
        
        
        if let layout = layout as? StoryCellLayoutItem, let privacy = layout.item.storyItem.privacy, context.peerId == layout.peerId, selected == nil {
            let current: StoryPrivacyView
            if let view = self.storyPrivacy {
                current = view
            } else {
                current = StoryPrivacyView(frame: NSMakeRect(0, 0, frame.width, 20))
                addSubview(current)
                self.storyPrivacy = current
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.update(privacy, isPinned: layout.isPinned, animated: animated)
        } else if let view = self.storyPrivacy {
            performSubviewRemoval(view, animated: animated)
            self.storyPrivacy = nil
        }
        
        
        updateSelectionState(animated: animated, selected: selected)
    }
    
    open override func copy() -> Any {
        return imageView.copy()
    }
    
    open func innerAction() -> MediaCellInvokeActionResult {
        return .gallery
    }
    
    open func addAccesoryOnCopiedView(view: NSView) {
        
    }
    
    open func updateMouse(_ inside: Bool) {
        
    }
    
    open func updateSelectionState(animated: Bool, selected: Bool?) {
        if let selected = selected {
            if let selectionView = self.selectionView {
                selectionView.set(selected: selected, animated: animated)
            } else {
                selectionView = SelectingControl(unselectedImage: theme.icons.chatGroupToggleUnselected, selectedImage: theme.icons.chatGroupToggleSelected)
                addSubview(selectionView!)
                selectionView?.set(selected: selected, animated: animated)
                if animated {
                    selectionView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    selectionView?.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.2)
                }
            }
        } else {
            if let selectionView = selectionView {
                self.selectionView = nil
                if animated {
                    selectionView.layer?.animateScaleSpring(from: 1.0, to: 0.1, duration: 0.2)
                    selectionView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak selectionView] completion in
                        selectionView?.removeFromSuperview()
                    })
                } else {
                    selectionView.removeFromSuperview()
                }
            }
        }
        needsLayout = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func layout() {
        super.layout()
        imageView.frame = NSMakeRect(0, 0, frame.width - 1, frame.height)
        if let selectionView = selectionView {
            selectionView.setFrameOrigin(frame.width - selectionView.frame.width - 5, 5)
        }
        inkView?.frame = imageView.frame
        self.unsupported?.resize(frame.width - 10)
        self.unsupported?.center()
        
        if let storyViews = storyViews {
            storyViews.frame = NSMakeRect(0, frame.height - storyViews.frame.height, frame.width, storyViews.frame.height)
        }
    }
}

public final class MediaPhotoCell : MediaCell {
    private var livePhotoBadge: ImageView?

    public override func update(layout: MediaCellLayoutable, selected: Bool?, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        super.update(layout: layout, selected: selected, context: context, table: table, animated: animated)
        if layout.imageMedia?.media.video != nil, !layout.isSecret, !layout.isSpoiler {
            let current: ImageView
            if let view = self.livePhotoBadge {
                current = view
            } else {
                current = ImageView()
                current.isEventLess = true
                current.isAccessibilityDecorative = true
                self.livePhotoBadge = current
                addSubview(current)
            }
            current.image = theme.icons.livePhotoBadge
            current.sizeToFit()
        } else if let view = self.livePhotoBadge {
            view.removeFromSuperview()
            self.livePhotoBadge = nil
        }
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        livePhotoBadge?.setFrameOrigin(5, 5)
    }
}

public enum MediaCellInvokeActionResult {
    case nothing
    case gallery
}



public class MediaVideoCell : MediaCell {
    
    
    private let mediaPlayerStatusDisposable = MetaDisposable()
    
    private let videoAccessory: ChatMessageAccessoryView = ChatMessageAccessoryView(frame: NSZeroRect)
    private var status:MediaResourceStatus?
    private var authenticStatus: MediaResourceStatus?
    private let statusDisposable = MetaDisposable()
    private let fetchingDisposable = MetaDisposable()
    private let partDisposable = MetaDisposable()
        
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(self.videoAccessory)
    }
    
    public override func updateMouse(_ inside: Bool) {
           
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func fetch() {
        if let context = context, let layoutItem = self.layoutItem, let file = layoutItem.fileMedia {
            fetchingDisposable.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(layoutItem.peerId), userContentType: .other, reference: file.resourceReference(file.media.resource)).start())
        }
    }
      
    private func cancelFetching() {
        if let context = context, let layoutItem = self.layoutItem, let fileMedia = layoutItem.fileMedia {
            cancelFreeMediaFileInteractiveFetch(context: context, resource: fileMedia.media.resource)
        }
    }
      
    public override func innerAction() -> MediaCellInvokeActionResult {
        if layoutItem?.fileMedia != nil, self.window != nil {
            return .gallery
        }
        return .nothing
    }
    
    public func preloadStreamblePart() {
        if let layoutItem = self.layoutItem, !TelegramUtilsHooks.shared.isLite(.any) {
            let context = layoutItem.context
            if context.autoplayMedia.preloadVideos {
                if let fileMedia = layoutItem.fileMedia {
                    
                    if isHLSVideo(file: fileMedia.media) {
                        let fetchSignal = HLSVideoContent.minimizedHLSQualityPreloadData(postbox: context.account.postbox, file: fileMedia, userLocation: .peer(layoutItem.peerId), prefixSeconds: 10, autofetchPlaylist: true, initialQuality: FastSettings.videoQuality)
                        |> mapToSignal { fileAndRange -> Signal<Never, NoError> in
                            guard let fileAndRange else {
                                return .complete()
                            }
                            return fetchedResourceRangeUntilOnDisk(mediaBox: context.account.postbox.mediaBox, resource: fileAndRange.0.media.resource, range: fileAndRange.1, fetch: freeMediaFileResourceInteractiveFetched(postbox: context.account.postbox, userLocation: .peer(layoutItem.peerId), fileReference: fileAndRange.0, resource: fileAndRange.0.media.resource, range: (fileAndRange.1, .default)))
                        }
                        partDisposable.set(fetchSignal.start())
                    } else {
                        let preload = preloadVideoResource(postbox: context.account.postbox, userLocation: .peer(layoutItem.peerId), userContentType: .init(file: fileMedia.media), resourceReference: fileMedia.resourceReference(fileMedia.media.resource), duration: 2.5)
                        partDisposable.set(preload.start())
                    }
                }
            }
        }
    }
    
    private func updateVideoAccessory(_ status: MediaResourceStatus, mediaPlayerStatus: MediaPlayerStatus? = nil, file: TelegramMediaFile, animated: Bool) {
        let maxWidth = frame.width - 10
        let text: String
        
        let status: MediaResourceStatus = .Local
        
        
        if let status = mediaPlayerStatus, status.generationTimestamp > 0, status.duration > 0 {
            text = String.durationTransformed(elapsed: Int(status.duration - (status.timestamp + (CACurrentMediaTime() - status.generationTimestamp))))
        } else {
            text = String.durationTransformed(elapsed: Int(file.videoDuration))
        }
        
        var isBuffering: Bool = false
        if let fetchStatus = self.authenticStatus, let status = mediaPlayerStatus {
            switch status.status {
            case .buffering:
                switch fetchStatus {
                case .Local:
                    break
                default:
                    isBuffering = true
                }
            default:
                break
            }
            
        }
        
        videoAccessory.updateText(text, maxWidth: maxWidth, status: status, isStreamable: file.isStreamable, isCompact: true, isBuffering: isBuffering, animated: animated, fetch: { [weak self] in
            self?.fetch()
        }, cancelFetch: { [weak self] in
            self?.cancelFetching()
        })
        needsLayout = true
    }
    
    public override func update(layout: MediaCellLayoutable, selected: Bool?, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        super.update(layout: layout, selected: selected, context: context, table: table, animated: animated)
        let fileMedia = layout.fileMedia!
        
        let updatedStatusSignal = context.account.postbox.mediaBox.resourceStatus(fileMedia.media.resource) |> deliverOnMainQueue |> map { status -> (MediaResourceStatus, MediaResourceStatus) in
            if fileMedia.media.isStreamable && layout.id.peerId.namespace != Namespaces.Peer.SecretChat {
               return (.Local, status)
           }
           return (status, status)
       }  |> deliverOnMainQueue
       
       var first: Bool = true
       
       statusDisposable.set(updatedStatusSignal.start(next: { [weak self] status, authentic in
           guard let `self` = self else {return}
           
           self.updateVideoAccessory(authentic, mediaPlayerStatus: nil, file: fileMedia.media, animated: !first)
            first = false
            self.status = status
            self.authenticStatus = authentic
        }))
        partDisposable.set(nil)
    }
    
    public override func addAccesoryOnCopiedView(view: NSView) {
        let videoAccessory = self.videoAccessory.copy() as! ChatMessageAccessoryView
        if visibleRect.minY < videoAccessory.frame.midY && visibleRect.minY + visibleRect.height > videoAccessory.frame.midY {
             videoAccessory.frame.origin.y = frame.height - videoAccessory.frame.maxY
             view.addSubview(videoAccessory)
         }

    }
    
    public override func layout() {
        super.layout()
        videoAccessory.setFrameOrigin(5, 5)
    }
    
    deinit {
        statusDisposable.dispose()
        fetchingDisposable.dispose()
        partDisposable.dispose()
        mediaPlayerStatusDisposable.dispose()
    }
}



public class MediaGifCell : MediaCell {
    private let gifView: GIFContainerView = GIFContainerView(frame: .zero)
    private var status:MediaResourceStatus?
    private let statusDisposable = MetaDisposable()
    private let fetchingDisposable = MetaDisposable()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(self.gifView)

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func fetch() {
        
    }
    
    private func cancelFetching() {

    }
    
    public override func innerAction() -> MediaCellInvokeActionResult {
        return .gallery
    }
    

    public override func copy() -> Any {
        return gifView.copy()
    }
    
    public override func update(layout: MediaCellLayoutable, selected: Bool?, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        let previousLayout = self.layoutItem
        let isUpdated = previousLayout == nil || !previousLayout!.isEqual(to: layout)
        super.update(layout: layout, selected: selected, context: context, table: table, animated: animated)
        if isUpdated, let fileMedia = layout.fileMedia {
            gifView.update(with: fileMedia, size: frame.size, viewSize: frame.size, context: context, table: nil)
            gifView.userInteractionEnabled = false
        }
    }
    
    
    public override func layout() {
        super.layout()
        gifView.frame = NSMakeRect(0, 0, frame.width - 1, frame.height)
        
    }
    
    deinit {
        statusDisposable.dispose()
        fetchingDisposable.dispose()
    }
}

public func mediaCellInteractionContentView<T: MediaCell>(_ contentViews: [T?], for innerId: AnyHashable, fallback: NSView) -> NSView {
    if let innerId = innerId.base as? MessageId {
        let view = contentViews.compactMap { $0 }.first(where: { $0.layoutItem?.id == innerId })
        return view ?? NSView()
    }
    return fallback
}

public func addMediaCellAccesoryOnCopiedView<T: MediaCell>(_ contentViews: [T?], innerId: AnyHashable, view: NSView) {
    if let innerId = innerId.base as? MessageId {
        let cell = contentViews.compactMap { $0 }.first(where: { $0.layoutItem?.id == innerId })
        cell?.addAccesoryOnCopiedView(view: view)
    }
}
