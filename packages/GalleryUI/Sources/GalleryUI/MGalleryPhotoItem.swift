import Cocoa
import TelegramCore

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
import TelegramMedia
import AvatarUI
import MessageUtils
import InstantPageUI
import SecureIdUtils
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils

public class MGalleryPhotoItem: MGalleryItem {
    
    public let media:TelegramMediaImage
    public let secureIdAccessContext: SecureIdAccessContext?
    private let representation:TelegramMediaImageRepresentation
    private let livePhotoVideo: TelegramMediaFile?
    private var livePhotoPlayer: MediaPlayer?
    private weak var livePhotoPlayerView: MediaPlayerView?
    private var didAutoplayLivePhoto: Bool = false
    private var isRotated: Bool = false
    public private(set) var isLivePlaybackActive: Bool = false
    private var isLiveAutoplaying: Bool = false
    private let livePlaying = ValuePromise<Bool>(false, ignoreRepeated: true)
    private let livePhotoViewDisposable = MetaDisposable()
    private let livePhotoStatusDisposable = MetaDisposable()
    private let livePhotoRotateDisposable = MetaDisposable()
    private let livePhotoFetching = MetaDisposable()
    public override init(_ context: any AccountContextProtocol, _ entry: GalleryEntry, _ pagerSize: NSSize) {
        switch entry {
        case .message(let entry):
            // Rich messages carry their media inside the instant page (`message.media` is empty),
            // so `anyMedia` is nil — fall back to the effective (instant-page) media.
            let media = entry.message!.anyMedia ?? entry.message!.effectiveMedia.first(where: { value in
                if value is TelegramMediaImage { return true }
                if let file = value as? TelegramMediaFile { return file.isGraphicFile }
                return false
            }) ?? entry.message!.effectiveMedia.first
            if let webpage = media as? TelegramMediaWebpage {
                if case let .Loaded(content) = webpage.content, let image = content.image {
                    self.media = image
                } else if case let .Loaded(content) = webpage.content, let media = content.file  {
                    let represenatation = TelegramMediaImageRepresentation(dimensions: media.dimensions ?? PixelDimensions(0, 0), resource: media.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
                    var representations = media.previewRepresentations
                    representations.append(represenatation)
                    self.media = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: representations, immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
                    
                } else {
                    fatalError("image for webpage not found")
                }
            } else {
                if let media = media as? TelegramMediaFile {
                    let represenatation = TelegramMediaImageRepresentation(dimensions: media.dimensions ?? PixelDimensions(0, 0), resource: media.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
                    var representations = media.previewRepresentations
                    representations.append(represenatation)
                    self.media = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: representations, immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
                } else {
                    self.media = media as! TelegramMediaImage
                }
            }
            secureIdAccessContext = nil
        case .instantMedia(let media, _):
            self.media = media.media as! TelegramMediaImage
            secureIdAccessContext = nil
        case let .secureIdDocument(document, _):
            self.media = document.image
            self.secureIdAccessContext = document.context
        case .media(let media, _, _):
            self.media = media as! TelegramMediaImage
            secureIdAccessContext = nil
        default:
            fatalError("photo item not supported entry type")
        }
        
        self.representation = media.representationForDisplayAtSize(PixelDimensions(NSMakeSize(1280, 1280)))!
        if let message = entry.message, !message.containsSecretMedia {
            self.livePhotoVideo = media.video
        } else {
            self.livePhotoVideo = nil
        }
        super.init(context, entry, pagerSize)

        if let video = livePhotoVideo {
            let fileReference = entry.fileReference(video)
            let player = MediaPlayer(postbox: context.account.postbox, userLocation: fileReference.userLocation, userContentType: fileReference.userContentType, reference: fileReference.resourceReference(video.resource), streamable: video.isStreamable, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: false)
            player.actionAtEnd = .stop
            self.livePhotoPlayer = player

            livePhotoViewDisposable.set(view.get().start(next: { [weak self] view in
                if let playerView = view.subviews.compactMap({ $0 as? MediaPlayerView }).first {
                    self?.livePhotoPlayerView = playerView
                    player.attachPlayerView(playerView)
                }
            }))

            livePhotoStatusDisposable.set((player.status |> deliverOnMainQueue).start(next: { [weak self] status in
                switch status.status {
                case .playing:
                    self?.setLivePhotoVideoVisible(true, animated: true)
                case .paused:
                    self?.setLivePhotoVideoVisible(false, animated: true)
                case .buffering:
                    break
                }
            }))

            livePhotoRotateDisposable.set(rotate.get().start(next: { [weak self] orientation in
                self?.isRotated = orientation != nil
                if orientation != nil {
                    self?.stopLivePhoto(animated: false)
                }
            }))
        }
    }

    public var isLivePhoto: Bool {
        return livePhotoVideo != nil
    }

    public var isLivePlaying: Bool {
        return isLivePlaybackActive || isLiveAutoplaying
    }

    public var livePlayingValue: Signal<Bool, NoError> {
        return livePlaying.get()
    }

    private func updateLivePlaying() {
        livePlaying.set(isLivePlaying)
    }

    public func toggleLivePlayback() {
        if isLivePlaying {
            stopLivePhoto(animated: true)
        } else {
            setLivePlayback(true)
        }
    }

    private func finishLiveAutoplay() {
        guard isLiveAutoplaying else {
            return
        }
        isLiveAutoplaying = false
        updateLivePlaying()
    }

    public func setLivePlayback(_ active: Bool) {
        guard let player = livePhotoPlayer, isLivePlaybackActive != active else {
            return
        }
        if active {
            guard !isRotated else {
                return
            }
            isLivePlaybackActive = true
            isLiveAutoplaying = false
            updateLivePlaying()
            player.actionAtEnd = .loop(nil)
            player.playOnceWithSound(playAndRecord: false)
        } else {
            stopLivePhoto(animated: true)
        }
    }

    private func stopLivePhoto(animated: Bool) {
        guard let player = livePhotoPlayer, didAutoplayLivePhoto || isLivePlaybackActive else {
            return
        }
        isLivePlaybackActive = false
        isLiveAutoplaying = false
        updateLivePlaying()
        player.actionAtEnd = .stop
        player.setSoundEnabled(false)
        player.seek(timestamp: 0, play: false)
        setLivePhotoVideoVisible(false, animated: animated)
    }

    private func setLivePhotoVideoVisible(_ visible: Bool, animated: Bool) {
        guard let layer = livePhotoPlayerView?.layer else {
            return
        }
        let opacity: Float = visible ? 1 : 0
        guard layer.opacity != opacity else {
            return
        }
        layer.opacity = opacity
        if animated {
            layer.animateAlpha(from: visible ? 0 : 1, to: CGFloat(opacity), duration: 0.2)
        }
    }

    public override func singleView() -> NSView {
        let view = super.singleView()
        if livePhotoVideo != nil {
            let playerView = MediaPlayerView(backgroundThread: true)
            playerView.setVideoLayerGravity(.resizeAspectFill)
            playerView.autoresizingMask = [.width, .height]
            playerView.frame = view.bounds
            playerView.layer?.opacity = 0
            playerView.layer?.zPosition = 1
            view.addSubview(playerView)
        }
        return view
    }

    public override func appear(for view: NSView?) {
        super.appear(for: view)
        if let player = livePhotoPlayer, !didAutoplayLivePhoto, !isRotated {
            didAutoplayLivePhoto = true
            isLiveAutoplaying = true
            updateLivePlaying()
            player.actionAtEnd = .action({ [weak self] in
                Queue.mainQueue().async {
                    self?.finishLiveAutoplay()
                }
            })
            player.seek(timestamp: 0, play: true)
        }
    }

    public override func disappear(for view: NSView?) {
        super.disappear(for: view)
        stopLivePhoto(animated: false)
    }
    
    
    public override var sizeValue: NSSize {
        if let largest = media.representations.last {
            if let modifiedSize = modifiedSize {
                return modifiedSize.fitted(pagerSize)
            }
            return largest.dimensions.size.fitted(pagerSize)
        }
        return NSZeroSize
    }
    
    public override func smallestValue(for size: NSSize) -> NSSize {
        if let largest = media.representations.last {
            if let modifiedSize = modifiedSize {
                let lhsProportion = modifiedSize.width/modifiedSize.height
                let rhsProportion = largest.dimensions.size.width/largest.dimensions.size.height
                
                if lhsProportion != rhsProportion {
                    return modifiedSize.fitted(size)
                }
            }
            return largest.dimensions.size.fitted(size)
        }
        return pagerSize
    }
    
    public override var status:Signal<MediaResourceStatus, NoError> {
        return chatMessagePhotoStatus(account: context.account, photo: media)
    }
    
    private var hasRequested: Bool = false
    
    public override func request(immediately: Bool) {
        super.request(immediately: immediately)
        
        if !hasRequested {
            let context = self.context
            let entry = self.entry
            let media = self.media
            let secureIdAccessContext = self.secureIdAccessContext
                        
            let sizeValue: Signal<NSSize, NoError> = size.get() |> map { size in
                return NSMakeSize(floorToScreenPixels(System.backingScale, size.width), floorToScreenPixels(System.backingScale, size.height))
            } |> distinctUntilChanged(isEqual: { lhs, rhs -> Bool in
                return lhs == rhs
            })
            
            let rotateValue = rotate.get() |> distinctUntilChanged(isEqual: { lhs, rhs -> Bool in
                return lhs == rhs
            })
            
            
            let signal = combineLatest(sizeValue, rotateValue) |> mapToSignal { [weak self] size, orientation -> Signal<(NSSize, ImageOrientation?), NoError> in
                guard let `self` = self else {return .complete()}
                
                var size = size
                if self.sizeValue.width > self.sizeValue.height && size.width < size.height
                    || self.sizeValue.width < self.sizeValue.height && size.width > size.height {
                    size = NSMakeSize(size.height, size.width)
                }
                
                var newSize = self.smallestValue(for: size)
                if let orientation = orientation {
                    if orientation == .right || orientation == .left {
                        newSize = self.rotatedSize(newSize)
                    }
                }
                return .single((newSize, orientation))
                
            }
            
            class Data {
                let image: NSImage?
                let orientation: ImageOrientation?
                init(_ image: NSImage?, _ orientation: ImageOrientation?) {
                    self.image = image
                    self.orientation = orientation
                }
            }
            
            let result = combineLatest(signal, self.magnify.get() |> distinctUntilChanged) |> mapToSignal { [weak self] data, magnify -> Signal<Data, NoError> in
                
                let (size, orientation) = data
                return chatGalleryPhoto(account: context.account, imageReference: entry.imageReference(media), scale: System.backingScale, secureIdAccessContext: secureIdAccessContext, synchronousLoad: true, drawChessboard: true)
                    |> deliverOn(graphicsThreadPool)
                    |> map { [weak self] transform in
                        
                        var size = NSMakeSize(ceil(size.width * magnify), ceil(size.height * magnify))
                        let image = transform(TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets()))
                        
                        if let image = image, orientation == nil {
                            let newSize = image.size.aspectFitted(size)
                            if newSize != size {
                                size = newSize
                                let modifiedSize = NSMakeSize(image.size.width * System.backingScale, image.size.height * System.backingScale)
                                Queue.mainQueue().async {
                                    self?.modifiedSize = modifiedSize
                                }
                            }
                        }
                        
                        if let orientation = orientation {
                            let transformed = image?.createMatchingBackingDataWithImage(orienation: orientation, keepColorSpace: true)
                            if let transformed = transformed {
                                return Data(NSImage(cgImage: transformed, size: size), orientation)
                            }
                        }
                        if let image = image {
                            return Data(NSImage(cgImage: image, size: size), orientation)
                        } else {
                            return Data(nil, orientation)
                        }
                }
                
            }
            
            path.set(context.account.postbox.mediaBox.resourceData(representation.resource) |> mapToSignal { resource -> Signal<String, NoError> in
                if resource.complete {
                    return .single(link(path:resource.path, ext:kMediaImageExt)!)
                }
                return .never()
            })
            
            self.image.set(result |> map { GPreviewValueClass(.image($0.image, $0.orientation)) } |> deliverOnMainQueue)
            
            
            fetch()
            
            hasRequested = true
        }
        
    }
    
    public override var backgroundColor: NSColor {
        if self.entry.isProtected {
            return .clear
        } else {
            return theme.colors.transparentBackground
        }
    }
    
    public override func fetch() -> Void {
        if let message = entry.message, let file = entry.message?.anyMedia as? TelegramMediaFile {
            fetching.set(messageMediaFileInteractiveFetched(context: context, messageId: message.id, messageReference: .init(message), file: file, userInitiated: true).start())
        } else {
            fetching.set(chatMessagePhotoInteractiveFetched(account: context.account, imageReference: entry.imageReference(media)).start())
        }
        if let video = livePhotoVideo, let message = entry.message {
            livePhotoFetching.set(messageMediaFileInteractiveFetched(context: context, messageId: message.id, messageReference: .init(message), file: video, userInitiated: true).start())
        }
    }
    
    public override func cancel() -> Void {
        super.cancel()
        livePhotoFetching.set(nil)
        chatMessagePhotoCancelInteractiveFetch(account: context.account, photo: media)
    }

    public override func releaseResources() {
        stopLivePhoto(animated: false)
        guard hasRequested else {
            return
        }
        hasRequested = false
        releaseDisplayedImage()
    }
    
    
    deinit {
        var bp:Int = 0
        bp += 1
        livePhotoViewDisposable.dispose()
        livePhotoStatusDisposable.dispose()
        livePhotoRotateDisposable.dispose()
        livePhotoFetching.dispose()
    }
    
}
