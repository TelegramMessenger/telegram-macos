import Cocoa

import TelegramCore

import Postbox
import SwiftSignalKit
import TGUIKit
import AVFoundation
import AVKit
import TelegramMedia
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

public class MGalleryVideoItem: MGalleryItem {
    public var startTime: TimeInterval = 0
    private var playAfter:Bool = false
    private let controller: SVideoController
    public var playerState: Signal<AVPlayerState, NoError> {
        return controller.status |> map { value in
            switch value.status {
            case .playing:
                return .playing(duration: value.duration)
            case .paused:
                return .paused(duration: value.duration)
            case let .buffering(initial, whilePlaying):
                if whilePlaying {
                    return .playing(duration: value.duration)
                } else if !whilePlaying && !initial {
                    return .paused(duration: value.duration)
                } else {
                    return .waiting
                }
            }
        } |> deliverOnMainQueue
    }
    
    public func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])? {
        return controller.mediaPlayer.videoQualityState()
    }
    
    public override init(_ context: any AccountContextProtocol, _ entry: GalleryEntry, _ pagerSize: NSSize) {
        controller = SVideoController(context: context, reference: entry.fileReference(entry.file!), message: entry.message, isProtected: entry.isProtected, isControlsLimited: entry.message?.adAttribute != nil)
        super.init(context, entry, pagerSize)
        
        rotateDisposable.set((rotate.get() |> deliverOnMainQueue).start(next: { [weak self] orientation in
            guard let self else {
                return
            }
            let view = self.controller.genericView
            if orientation != nil {
                view.layer?.contents = nil
            }
            view.rotation = orientation
            if let magnify = view.superview?.superview as? MagnifyView {
                magnify.contentSize = self.rotatedContentSize(for: orientation)
            }
        }))

        controller.togglePictureInPictureImpl = { [weak self] enter, control in
            guard let `self` = self else {return}
            if enter, let viewer = viewer {
                let frame = control.view.window!.convertToScreen(control.view.convert(control.view.bounds, to: nil))
                for item in viewer.pager.items where item !== self {
                    item.releaseResources()
                }
                closeGalleryViewer(false)
                showPipVideo(control: control, viewer: viewer, item: self, origin: frame.origin, delegate: viewer.delegate, contentInteractions: viewer.contentInteractions, type: viewer.type)
            } else if !enter {
                exitPictureInPicture()
            }
        }
    }
    
    deinit {
        updateMagnifyDisposable.dispose()
        rotateDisposable.dispose()
    }
        
    public override func singleView() -> NSView {
        return controller.genericView
        
    }
    private var isPausedGlobalPlayer: Bool = false
    private let updateMagnifyDisposable = MetaDisposable()
    private let rotateDisposable = MetaDisposable()
    
    public override func appear(for view: NSView?) {
        super.appear(for: view)
        
        pausepip()
        
        isPausedGlobalPlayer = GalleryHooks.shared.pauseGlobalAudio(context)

        controller.play(startTime)
        controller.viewDidAppear(false)
        self.startTime = 0
        
        
        updateMagnifyDisposable.set((magnify.get() |> deliverOnMainQueue).start(next: { [weak self] value in
            if value < 1.0 {
                _ = self?.hideControls(forceHidden: true)
            } else {
                _ = self?.unhideControls(forceUnhidden: true)
            }
        }))
    }
    
    public override var maxMagnify: CGFloat {
        return min(pagerSize.width / sizeValue.width, pagerSize.height / sizeValue.height)
    }
    
    public override func disappear(for view: NSView?) {
        super.disappear(for: view)
        if isPausedGlobalPlayer {
            GalleryHooks.shared.resumeGlobalAudio(context)
        }
        if controller.style != .pictureInPicture {
            controller.pause()
        }
        controller.viewDidDisappear(false)
        updateMagnifyDisposable.set(nil)
        playAfter = false
    }
    
    public override var status:Signal<MediaResourceStatus, NoError> {
        if media.isStreamable {
            return .single(.Local)
        } else {
            return realStatus
        }
    }
    
    public override var realStatus:Signal<MediaResourceStatus, NoError> {
        if let message = entry.message {
            return chatMessageFileStatus(context: context, message: message, file: media)
        } else {
            return context.account.postbox.mediaBox.resourceStatus(media.resource)
        }
    }
    
    public var media:TelegramMediaFile {
        return entry.file!
    }
    private var examinatedSize: CGSize?
    public var dimensions: CGSize? {
        
        if let examinatedSize = examinatedSize {
            return examinatedSize
        }
        if let dimensions = media.dimensions {
            return dimensions.size
        }
        let linked = link(path: context.account.postbox.mediaBox.resourcePath(media.resource), ext: "mp4")
        guard let path = linked else {
            return media.dimensions?.size
        }
        
        let url = URL(fileURLWithPath: path)
        guard let track = AVURLAsset(url: url).tracks(withMediaType: .video).first else {
            return media.dimensions?.size
        }
        try? FileManager.default.removeItem(at: url)
        let size = track.naturalSize.applying(track.preferredTransform)
        self.examinatedSize = NSMakeSize(abs(size.width), abs(size.height))
        
        return examinatedSize
        
    }
    
    public override var notFittedSize: NSSize {
        if let size = dimensions {
            return size.fitted(pagerSize)
        }
        return pagerSize
    }
    
    public override var sizeValue: NSSize {
        if let size = dimensions {
            
            let pagerSize = self.pagerSize
            
            
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
            
//            let addition = max(400 - size.width, 400 - size.height)
//            if addition > 0 {
//                size.width += addition
//                size.height += addition
//            }
            
            size = size.fitted(pagerSize)

            return size
        }
        return pagerSize
    }
    
    public func hideControls(forceHidden: Bool = false) -> Bool {
        return controller.hideControlsIfNeeded(forceHidden)
    }
    public func unhideControls(forceUnhidden: Bool = true) -> Bool {
        return controller.unhideControlsIfNeeded(forceUnhidden)
    }
    
    public override func toggleFullScreen() {
        controller.toggleFullScreen()
    }
    
    public override func togglePlayerOrPause() {
        controller.togglePlayerOrPause()
    }
    
    public override func rewindBack() {
        controller.rewindBackward()
    }
    public override func rewindForward() {
        controller.rewindForward()
    }
    
    public var isFullscreen: Bool {
        return controller.isFullscreen
    }
    
    
    private var hasRequested: Bool = false
    
    public override func releaseResources() {
        guard hasRequested, controller.style != .pictureInPicture else {
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
        
        let signal:Signal<ImageDataTransformation,NoError> = chatMessageVideo(account: context.account, fileReference: entry.fileReference(media), scale: System.backingScale, synchronousLoad: true, noVideoCover: true)
        
        let size = sizeValue
        
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets(), resizeMode: .none)
        let result = signal |> mapToThrottled { data -> Signal<CGImage?, NoError> in
            return .single(data.execute(arguments, data.data)?.generateImage())
        }
        
        path.set(context.account.postbox.mediaBox.resourceData(media.resource) |> mapToSignal { (resource) -> Signal<String, NoError> in
            if resource.complete {
                return .single(link(path:resource.path, ext:kMediaVideoExt)!)
            }
            return .never()
        })
        self.image.set(media.previewRepresentations.isEmpty ? .single(GPreviewValueClass(.image(nil, nil))) |> deliverOnMainQueue : result |> map { GPreviewValueClass(.image($0 != nil ? NSImage(cgImage: $0!, size: $0!.backingSize) : nil, nil)) } |> deliverOnMainQueue)
        
        fetch()
    }
    
    
    public override func fetch() -> Void {
        if !media.isStreamable {
            if let parent = entry.message {
                _ = messageMediaFileInteractiveFetched(context: context, messageId: parent.id, messageReference: .init(parent), file: media, userInitiated: true).start()
            } else {
                _ = freeMediaFileInteractiveFetched(context: context, fileReference: FileMediaReference.standalone(media: media)).start()
            }
        }
    }

}
