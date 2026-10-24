import Cocoa
import TelegramCore
import TelegramMedia
import Postbox
import SwiftSignalKit
import TGUIKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import ChatModeTypes
import ChatHistoryModel
import GeneralRows
import LocalAnimations
import TelegramMediaUtils
import AvatarUI
import MessageUtils
import InstantPageUI
import SecureIdUtils
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils

final class MGalleryGIFContainerView: View {
    let player = MediaPlayerView(backgroundThread: true)

    var rotation: ImageOrientation? {
        didSet {
            if oldValue != rotation {
                needsLayout = true
            }
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        player.layerContentsRedrawPolicy = .duringViewResize
        autoresizesSubviews = false
        addSubview(player)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let playerSize = rotation?.isQuarterTurn == true ? NSMakeSize(bounds.height, bounds.width) : bounds.size
        player.frameCenterRotation = 0
        player.frame = NSMakeRect(floor((bounds.width - playerSize.width) / 2), floor((bounds.height - playerSize.height) / 2), playerSize.width, playerSize.height)
        player.frameCenterRotation = rotation?.viewRotationDegrees ?? 0
    }
}

public class MGalleryGIFItem: MGalleryItem {

    private var mediaPlayer: MediaPlayer!
    private let rotateDisposable = MetaDisposable()
    
    public override init(_ context: any AccountContextProtocol, _ entry: GalleryEntry, _ pagerSize: NSSize) {
        super.init(context, entry, pagerSize)
        
        let view = self.view
        
        let fileReference = entry.fileReference(media)
        let id = self.entry.peer?.id ?? self.entry.message?.id.peerId
        let userLocation: MediaResourceUserLocation
        if let id = id {
            userLocation = .peer(id)
        } else {
            userLocation = .other
        }
        self.mediaPlayer = MediaPlayer(postbox: context.account.postbox, userLocation: userLocation, userContentType: .video, reference: fileReference.resourceReference(media.resource), streamable: media.isStreamable, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: false)
        mediaPlayer.actionAtEnd = .loop(nil)

        
        disposable.set(view.get().start(next: { [weak self] view in
            if let view = (view as? MGalleryGIFContainerView) {
                self?.mediaPlayer.attachPlayerView(view.player)
            }
        }))

        rotateDisposable.set((combineLatest(rotate.get(), self.view.get()) |> deliverOnMainQueue).start(next: { [weak self] orientation, view in
            guard let self, let container = view as? MGalleryGIFContainerView else {
                return
            }
            if orientation != nil {
                container.layer?.contents = nil
            }
            container.rotation = orientation
            if let magnify = container.superview?.superview as? MagnifyView {
                magnify.contentSize = self.rotatedContentSize(for: orientation)
            }
        }))
        
    }
    
    public override func appear(for view: NSView?) {
        super.appear(for: view)
        self.mediaPlayer.play()
    }
    
    public override func disappear(for view: NSView?) {
        super.disappear(for: view)
        
        self.mediaPlayer.pause()
    }
    
    public override var status:Signal<MediaResourceStatus, NoError> {
        if let message = entry.message {
            return chatMessageFileStatus(context: context, message: message, file: media)
        } else {
            return context.account.postbox.mediaBox.resourceStatus(media.resource)
        }
    }
    
    public var media:TelegramMediaFile {
        switch entry {
        case .message(let entry):
            // Rich messages keep media in the instant page (`message.media` is empty); fall back to it.
            let resolved = entry.message!.media.first ?? entry.message!.effectiveMedia.first
            if let media = resolved as? TelegramMediaFile {
                return media
            } else if let media = resolved as? TelegramMediaWebpage {
                switch media.content {
                case let .Loaded(content):
                    return content.file!
                default:
                    fatalError("")
                }
            }
        case .instantMedia(let media, _):
            return media.media as! TelegramMediaFile
        case let  .photo(_, _, photo, _, _, _, _, _, _):
            let video = photo.videoRepresentations.last!
            let file = TelegramMediaFile(fileId: photo.imageId, partialReference: nil, resource: video.resource, previewRepresentations: photo.representations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: video.resource.size, attributes: [.Video(duration:0, size: PixelDimensions(640, 640), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)], alternativeRepresentations: [])
            
            return file
        case let .media(media, _, _):
            return media as! TelegramMediaFile
        default:
            fatalError()
        }
        
        fatalError("")
    }
    
//    override var maxMagnify:CGFloat {
//        return 1.0
//    }

    public override func singleView() -> NSView {
        return MGalleryGIFContainerView(frame: NSZeroRect)
    }
    
    public override var sizeValue: NSSize {
        if let size = media.dimensions?.size {
            
            var size = size
            
            if size.width == 0 || size.height == 0 {
                size = NSMakeSize(300, 300)
            }
            
            let aspectRatio = size.width / size.height
            let addition = max(300 - size.width, 300 - size.height)
            
            if addition > 0 {
                size.width += addition * aspectRatio
                size.height += addition
            }
            
            return size.fitted(pagerSize)
        }
        return pagerSize
    }
    
    private var hasRequested: Bool = false
    
    public override func releaseResources() {
        guard hasRequested else {
            return
        }
        hasRequested = false
        releaseDisplayedImage()
    }
    
    public override func request(immediately: Bool) {
        super.request(immediately: immediately)
        guard !hasRequested else {
            return
        }
        hasRequested = true
        let size = media.dimensions?.size.fitted(pagerSize) ?? sizeValue
        
        let signal:Signal<ImageDataTransformation,NoError> = chatMessageVideo(account: context.account, fileReference: entry.fileReference(media), scale: System.backingScale)
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets())
        let result = signal |> deliverOn(graphicsThreadPool) |> mapToThrottled { generator -> Signal<CGImage?, NoError> in
            return .single(generator.execute(arguments, generator.data)?.generateImage())
        }
        
    
        path.set(context.account.postbox.mediaBox.resourceData(media.resource) |> mapToSignal { (resource) -> Signal<String, NoError> in
            if resource.complete {
                return .single(link(path:resource.path, ext:kMediaGifExt)!)
            }
            return .never()
        })

        self.image.set(result |> map { GPreviewValueClass(.image($0 != nil ? NSImage(cgImage: $0!, size: $0!.backingSize) : nil, nil)) } |> deliverOnMainQueue)
    
        fetch()
    }
    
 
    deinit {
        rotateDisposable.dispose()
    }
    
    public override func fetch() -> Void {
        fetching.set(chatMessageFileInteractiveFetched(account: context.account, fileReference: entry.fileReference(media)).start())
    }

    
}
