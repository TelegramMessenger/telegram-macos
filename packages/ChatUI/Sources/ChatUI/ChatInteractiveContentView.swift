import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import TGUIKit
import TelegramMedia
import TelegramMediaPlayer
import TelegramMediaResources
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import InlineMediaGrid

extension AutoremoveTimeoutMessageAttribute : @retroactive Equatable {
    public static func == (lhs: AutoremoveTimeoutMessageAttribute, rhs: AutoremoveTimeoutMessageAttribute) -> Bool {
        return lhs.timeout == rhs.timeout && lhs.countdownBeginTime == rhs.countdownBeginTime && lhs.associatedMessageIds == rhs.associatedMessageIds
    }
}



public protocol ChatVideoAutoplayPlayer: AnyObject {
    var status: Signal<MediaPlayerStatus, NoError> { get }
    func play()
    func pause()
    func seek(timestamp: Double)
    func seek(timestamp: Double, play: Bool?)
    func setVolume(_ volume: Float)
    func getVolume(_ completion: @escaping (Float) -> Void)
    func attachPlayerView(_ node: MediaPlayerView)
    func setActionAtEnd(_ value: MediaPlayerActionAtEnd)
}

extension MediaPlayer: ChatVideoAutoplayPlayer {
    public func setActionAtEnd(_ value: MediaPlayerActionAtEnd) {
        self.actionAtEnd = value
    }
}

final class ChatVideoChunkedAutoplayPlayer: ChatVideoAutoplayPlayer {
    private let player: ChunkMediaPlayerV2
    private var volume: Float

    init(postbox: Postbox, fileReference: FileMediaReference, volume: Float, view: MediaPlayerView) {
        self.volume = volume
        self.player = ChunkMediaPlayerV2(
            params: ChunkMediaPlayerV2.MediaDataReaderParams(useV2Reader: true),
            source: .directFetch(ChunkMediaPlayerV2.SourceDescription.ResourceDescription(
                postbox: postbox,
                size: fileReference.media.size ?? 0,
                reference: fileReference.resourceReference(fileReference.media.resource),
                userLocation: fileReference.userLocation,
                userContentType: fileReference.userContentType,
                statsCategory: statsCategoryForFileWithAttributes(fileReference.media.attributes),
                fetchAutomatically: false
            )),
            video: true,
            enableSound: false,
            volume: volume,
            playerNode: view
        )
    }

    var status: Signal<MediaPlayerStatus, NoError> {
        return self.player.status
    }

    func play() {
        self.player.play()
    }

    func pause() {
        self.player.pause()
    }

    func seek(timestamp: Double) {
        self.player.seek(timestamp: timestamp, play: nil)
    }

    func seek(timestamp: Double, play: Bool?) {
        self.player.seek(timestamp: timestamp, play: play)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        self.player.setVolume(volume: volume)
    }

    func getVolume(_ completion: @escaping (Float) -> Void) {
        completion(self.volume)
    }

    func attachPlayerView(_ node: MediaPlayerView) {
    }

    func setActionAtEnd(_ value: MediaPlayerActionAtEnd) {
        switch value {
        case let .loop(f):
            self.player.actionAtEnd = .loop(f)
        case let .action(f):
            self.player.actionAtEnd = .action(f)
        case let .loopDisablingSound(f):
            self.player.actionAtEnd = .loopDisablingSound(f)
        case .stop:
            self.player.actionAtEnd = .stop
        }
    }
}

fileprivate final class ChatVideoAccessoryTimer {
    private var source: DispatchSourceTimer?

    init(completion: @escaping () -> Void) {
        let source = DispatchSource.makeTimerSource(queue: .main)
        self.source = source
        source.setEventHandler { [weak self] in
            guard self?.source != nil else {
                return
            }
            completion()
        }
        restart()
        source.resume()
    }

    func restart() {
        source?.schedule(deadline: .now() + 0.5, repeating: 0.5)
    }

    func invalidate() {
        source?.cancel()
        source = nil
    }

    deinit {
        invalidate()
    }
}

public final class ChatVideoAutoplayView {
    public let mediaPlayer: ChatVideoAutoplayPlayer
    public let view: MediaPlayerView

    fileprivate var playTimer: ChatVideoAccessoryTimer?
    fileprivate var playTimerAnimated = false
    public var status: MediaPlayerStatus?

    private var timer: SwiftSignalKit.Timer? = nil

    public init(mediaPlayer: ChatVideoAutoplayPlayer, view: MediaPlayerView) {
        self.mediaPlayer = mediaPlayer
        self.view = view
        mediaPlayer.setActionAtEnd(.loop(nil))
    }
    
    public func toggleVolume(_ enabled: Bool, animated: Bool) {
        if !animated {
            mediaPlayer.setVolume(enabled ? 1 : 0)
            timer?.invalidate()
            timer = nil
        } else {
            timer = nil
            
            let start:(Float) -> Void = { [weak self] volume in
                let fps = Float(1000 / 60)
                var current:Float = volume

                let tick = (enabled ? 1 - current : -current) / (fps * 0.3)
                
                self?.timer = SwiftSignalKit.Timer(timeout: abs(Double(tick)), repeat: true, completion: { [weak self] in
                    current += tick
                    self?.mediaPlayer.setVolume(min(1, max(0, current)))
                    
                    if current >= 1 || current <= 0 {
                        self?.timer?.invalidate()
                    }
                }, queue: .mainQueue())
                
                self?.timer?.start()
            }
            
            mediaPlayer.getVolume { volume in
                Queue.mainQueue().justDispatch {
                    start(volume)
                }
            }
        }
    }
    
    fileprivate func stopPlayTimer() {
        playTimer?.invalidate()
        playTimer = nil
    }

    deinit {
        view.removeFromSuperview()
        timer?.invalidate()
        stopPlayTimer()
    }
}


private final class VideoTimestampView : View {
    let progress: LinearProgressControl = .init(progressHeight: 3)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(progress)
        self.isEventLess = true
        
        self.layer = CornerMaskLayerSimple()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        progress.frame = NSMakeRect(0, frame.height - 3, frame.width, 3)
    }
}

final class ChatMediaImageHost {
    private weak var owner: NSView?
    private(set) var view: TransformImageView?
    private(set) var layer: TransformImageLayer?

    #if DEBUG
    static var parityMutation: CGFloat = 0
    #endif

    init(owner: NSView) {
        self.owner = owner
        let view = TransformImageView()
        self.view = view
        owner.addSubview(view)
    }

    private var layerShift: CGFloat {
        #if DEBUG
        return ChatMediaImageHost.parityMutation
        #else
        return 0
        #endif
    }

    func setLayerHosted(_ hosted: Bool, keepingImage: Bool) {
        guard hosted != (layer != nil), let owner else { return }
        let previousImage = keepingImage ? (view?.image ?? layer?.image) : nil
        let frame = self.frame
        if hosted {
            let layer = TransformImageLayer()
            layer.zPosition = -1
            layer.frame = frame.offsetBy(dx: layerShift, dy: 0)
            layer.visibilityView = owner
            owner.layer?.addSublayer(layer)
            view?.removeFromSuperview()
            view = nil
            self.layer = layer
            if let previousImage {
                layer.image = previousImage
            }
        } else {
            let view = TransformImageView(frame: frame)
            owner.addSubview(view, positioned: .below, relativeTo: nil)
            layer?.removeFromSuperlayer()
            layer = nil
            self.view = view
            if let previousImage {
                view.image = previousImage
            }
        }
    }

    var frame: NSRect {
        if let view {
            return view.frame
        }
        if let layer {
            return layer.frame.offsetBy(dx: -layerShift, dy: 0)
        }
        return .zero
    }

    func setFrameSize(_ size: NSSize) {
        view?.setFrameSize(size)
        if let layer, layer.frame.size != size {
            layer.frame = NSRect(origin: layer.frame.origin, size: size)
        }
    }

    func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        if let view {
            transition.updateFrame(view: view, frame: frame)
        }
        if let layer {
            transition.updateFrame(layer: layer, frame: frame.offsetBy(dx: layerShift, dy: 0))
        }
    }

    func set(arguments: TransformImageArguments) {
        view?.set(arguments: arguments)
        layer?.set(arguments: arguments)
    }

    var isFullyLoaded: Bool {
        return view?.isFullyLoaded ?? layer?.isFullyLoaded ?? false
    }

    var ignoreFullyLoad: Bool {
        get { view?.ignoreFullyLoad ?? layer?.ignoreFullyLoad ?? false }
        set {
            view?.ignoreFullyLoad = newValue
            layer?.ignoreFullyLoad = newValue
        }
    }

    var animatesAlphaOnFirstTransition: Bool {
        get { view?.animatesAlphaOnFirstTransition ?? layer?.animatesAlphaOnFirstTransition ?? false }
        set {
            view?.animatesAlphaOnFirstTransition = newValue
            layer?.animatesAlphaOnFirstTransition = newValue
        }
    }

    var preventsCapture: Bool {
        get { view?.preventsCapture ?? false }
        set { view?.preventsCapture = newValue }
    }

    var opacity: Float {
        get { view?.layer?.opacity ?? layer?.opacity ?? 1 }
        set {
            view?.layer?.opacity = newValue
            layer?.opacity = newValue
        }
    }

    func setSignal(signal: Signal<TransformImageResult?, NoError>, clearInstantly: Bool) {
        view?.setSignal(signal: signal, clearInstantly: clearInstantly)
        layer?.setSignal(signal: signal, clearInstantly: clearInstantly)
    }

    func setSignal(_ signal: Signal<ImageDataTransformation, NoError>, animate: Bool, cacheImage: @escaping (TransformImageResult) -> Void, isProtected: Bool, alreadyRendered: TransformImageArguments?) {
        if let view {
            view.setSignal(signal, animate: animate, cacheImage: cacheImage, isProtected: isProtected, alreadyRendered: alreadyRendered)
        } else if let layer {
            assert(!isProtected)
            layer.setSignal(signal, animate: animate, cacheImage: cacheImage, alreadyRendered: alreadyRendered)
        }
    }

    func change(size: NSSize, animated: Bool) {
        if let view {
            view._change(size: size, animated: animated)
            return
        }
        guard let layer, layer.frame.size != size else { return }
        if animated {
            var presentBounds = layer.bounds
            if let presentation = layer.presentation(), layer.animation(forKey: "bounds") != nil {
                presentBounds.size = presentation.bounds.size
            }
            layer.animateBounds(from: presentBounds, to: NSMakeRect(0, 0, size.width, size.height), duration: 0.2, timingFunction: .easeOut)
        } else {
            layer.removeAnimation(forKey: "bounds")
        }
        layer.frame = NSRect(origin: layer.frame.origin, size: size)
    }

    func hostDidMoveToWindow() {
        layer?.hostDidMoveToWindow()
    }

    var contents: Any? {
        return view?.layer?.contents ?? layer?.contents
    }

    func copy() -> Any {
        if let view {
            return view.copy()
        }
        guard let owner, let layer else { return NSView() }
        let bounds = layer.bounds
        let visibleRect = owner.effectiveVisibleRect
        let view = NSView()
        view.wantsLayer = true
        view.background = .clear
        view.layer?.contents = layer.image
        view.frame = visibleRect
        view.layer?.masksToBounds = true
        if bounds != visibleRect {
            if let image = layer.contents {
                view.layer?.contents = generateImage(bounds.size, contextGenerator: { size, ctx in
                    ctx.clear(bounds)
                    ctx.setFillColor(.clear)
                    ctx.fill(bounds)
                    if visibleRect.minY != 0  {
                        ctx.clip(to: NSMakeRect(0, 0, bounds.width, bounds.height - ( bounds.height - visibleRect.height)))
                    } else {
                        ctx.clip(to: NSMakeRect(0, (bounds.height - visibleRect.height), bounds.width, bounds.height - ( bounds.height - visibleRect.height)))
                    }
                    ctx.draw(image as! CGImage, in: bounds)
                }, opaque: false)
            }
        }
        view.layer?.shouldRasterize = true
        view.layer?.rasterizationScale = owner.backingScaleFactor
        return view
    }
}

public class ChatInteractiveContentView: ChatMediaContentView {

    /// When set, the image is rendered with square (0) corners instead of the default `.cornerRadius`.
    /// Used by full-bleed rich-message media in bubble mode. Default false → unchanged chat behavior.
    public var squareCorners: Bool = false

    private var appliedCorners: ImageCorners?

    private func mediaCorners(_ positionFlags: LayoutPositionFlags?, _ parameters: ChatMediaLayoutParameters?) -> ImageCorners {
        return .chatMedia(positionFlags, bubble: parameters?.bubbleCorners(), inner: squareCorners ? 0 : .cornerRadius)
    }

    private lazy var image = ChatMediaImageHost(owner: self)
    private var videoAccessory: ChatMessageAccessoryView? = nil
    private var progressView:RadialProgressView?
    private var timableProgressView: TimableProgressView? = nil
    private let statusDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private let coverFetchDisposable = MetaDisposable()
    
    private var videoTimeProgress: VideoTimestampView?
    
    
    private let partDisposable = MetaDisposable()
    private weak var attachedAutoplayView: ChatVideoAutoplayView?
    private var preloadedStreamableKey: String?

    private var authenticFetchStatus: MediaResourceStatus?

    
    private let mediaPlayerStatusDisposable = MetaDisposable()
    private var autoplayVideoView: ChatVideoAutoplayView?
    
    private var livePhotoBadge: ImageView?
    private var livePhotoFile: TelegramMediaFile?
    private var livePhotoView: ChatVideoAutoplayView?
    private var livePhotoPlayed: Bool = false
    private let livePhotoStatusDisposable = MetaDisposable()
    private let livePhotoFetchDisposable = MetaDisposable()
    private let livePhotoPlayerStatusDisposable = MetaDisposable()
    
    private var inkView: MediaInkView?
    
    public override var backgroundColor: NSColor {
        get {
            return super.backgroundColor
        }
        set {
            super.backgroundColor = .clear
        }
    }
    
    public override func previewMediaIfPossible() -> Bool {
        guard let context = self.context, let window = self._window, let table = self.table, parent == nil || parent?.containsSecretMedia == false, fetchStatus == .Local else {return false}
        startModalPreviewHandle(table, window: window, context: context)
        return true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        //background = .random
        _ = self.image
    }
    

    
    public override func updateMouse() {
       
    }
    
    
    public override func open() {
        if let parent = parent {
            let forceSpoiler = parameters?.forceSpoiler == true
            let messageSpoiler = parent.isMediaSpoilered
            let isSpoiler = (messageSpoiler || forceSpoiler) && (parameters?.isRevealed == false)
            if isSpoiler {
                parameters?.revealMedia(parent)
            } else {
                parameters?.showMedia(parent)
                autoplayVideoView?.toggleVolume(false, animated: false)
            }
        }
    }
    
    private func updateMediaStatus(_ status: MediaPlayerStatus, animated: Bool = false) {
        if let autoplayVideoView = autoplayVideoView, let media = self.media as? TelegramMediaFile {
            autoplayVideoView.status = status
            autoplayVideoView.playTimerAnimated = animated
            updateVideoAccessory(.Local, file: media, mediaPlayerStatus: status, animated: animated)
            
            switch status.status {
            case .playing:
                if let timer = autoplayVideoView.playTimer {
                    timer.restart()
                } else {
                    autoplayVideoView.playTimer = ChatVideoAccessoryTimer(completion: { [weak self, weak autoplayVideoView] in
                        guard let self, let autoplayVideoView, self.autoplayVideoView === autoplayVideoView, let status = autoplayVideoView.status, let media = self.media as? TelegramMediaFile else {
                            autoplayVideoView?.stopPlayTimer()
                            return
                        }
                        self.updateVideoAccessory(.Local, file: media, mediaPlayerStatus: status, animated: autoplayVideoView.playTimerAnimated)
                    })
                }
            default:
                autoplayVideoView.stopPlayTimer()
            }

            
        }
    }
    

    public override func interactionControllerDidFinishAnimation(interactive: Bool) {

    }
    
    public override func addAccesoryOnCopiedView(view: NSView) {
        if let videoAccessory = videoAccessory?.copy() as? NSView {
            if effectiveVisibleRect.minY < videoAccessory.frame.midY && effectiveVisibleRect.minY + effectiveVisibleRect.height > videoAccessory.frame.midY {
                videoAccessory.frame.origin.y = frame.height - videoAccessory.frame.maxY
                view.addSubview(videoAccessory)
            }
           
        }
        if let progressView = progressView {
            let pView = RadialProgressView(theme: progressView.theme, twist: true)
            pView.state = progressView.state
            pView.frame = progressView.frame
            if effectiveVisibleRect.minY < progressView.frame.midY && effectiveVisibleRect.minY + effectiveVisibleRect.height > progressView.frame.midY {
                pView.frame.origin.y = frame.height - progressView.frame.maxY
                view.addSubview(pView)
            }
        }
        self.autoplayVideoView?.mediaPlayer.seek(timestamp: 0)
    }
    
    public func removeNotificationListeners() {
        NotificationCenter.default.removeObserver(self)
    }
    
    public override func viewDidUpdatedDynamicContent() {
        super.viewDidUpdatedDynamicContent()
        updatePlayerIfNeeded()
    }
    
    deinit {
        let deInit = {
            self.removeNotificationListeners()
            self.mediaPlayerStatusDisposable.dispose()
            self.partDisposable.dispose()
            self.fetchDisposable.dispose()
            self.coverFetchDisposable.dispose()
            self.livePhotoStatusDisposable.dispose()
            self.livePhotoFetchDisposable.dispose()
            self.livePhotoPlayerStatusDisposable.dispose()
        }
        deInit()
    }
    
    private var lite: Bool {
        return (isGif && TelegramUtilsHooks.shared.isLite(.gif)) || (!isGif && TelegramUtilsHooks.shared.isLite(.video))

    }
    
    @objc public func updatePlayerIfNeeded() {
        
        guard autoplayVideoView != nil || livePhotoView != nil else {
            return
        }
        
        var accept = window != nil && window!.isKeyWindow && !NSIsEmptyRect(visibleRect) && !self.isDynamicContentLocked
        
        if lite {
            accept = accept && mouseInside()
        }
                        
        if let autoplayView = autoplayVideoView {
            if accept {
                autoplayView.mediaPlayer.play()
                self.progressView?.isHidden = true
            } else {
                autoplayView.mediaPlayer.pause()
                autoplayView.stopPlayTimer()
                self.progressView?.isHidden = false
            }
        }

        if let livePhotoView = livePhotoView {
            if !accept {
                if livePhotoPlayed {
                    livePhotoPlayed = false
                    livePhotoView.mediaPlayer.pause()
                    hideLivePhotoVideo(animated: false)
                }
            } else if !livePhotoPlayed {
                livePhotoPlayed = true
                livePhotoView.mediaPlayer.seek(timestamp: 0, play: true)
            }
        }
    }

    private func updateLivePhoto(_ image: TelegramMediaImage, parent: Message?, context: any AccountContextProtocol, isSpoiler: Bool, isProtected: Bool, corners: ImageCorners) {
        guard let video = image.video, let parent = parent, !parent.containsSecretMedia, !isSpoiler else {
            removeLivePhoto()
            return
        }

        let badge: ImageView
        if let view = self.livePhotoBadge {
            badge = view
        } else {
            badge = ImageView()
            badge.isEventLess = true
            badge.isAccessibilityDecorative = true
            self.livePhotoBadge = badge
            addSubview(badge)
        }
        badge.image = theme.icons.livePhotoBadge
        badge.sizeToFit()

        if livePhotoFile?.fileId != video.fileId {
            removeLivePhotoPlayer()
            livePhotoFile = video
            let fileReference = FileMediaReference.message(message: MessageReference(parent), media: video)
            livePhotoStatusDisposable.set((chatMessageFileStatus(context: context, message: parent, file: video) |> deliverOnMainQueue).start(next: { [weak self] status in
                if case .Local = status {
                    self?.makeLivePhotoPlayer(fileReference, context: context)
                }
            }))
        }

        if let view = livePhotoView?.view {
            view.corners = corners
            view.preventsCapture = isProtected
        }
    }

    private func makeLivePhotoPlayer(_ fileReference: FileMediaReference, context: any AccountContextProtocol) {
        guard livePhotoView == nil else {
            return
        }
        let file = fileReference.media
        let player = ChatVideoAutoplayView(mediaPlayer: MediaPlayer(postbox: context.account.postbox, userLocation: fileReference.userLocation, userContentType: fileReference.userContentType, reference: fileReference.resourceReference(file.resource), streamable: file.isStreamable, video: true, preferSoftwareDecoding: false, enableSound: false, volume: 0.0, fetchAutomatically: false), view: MediaPlayerView(backgroundThread: true))
        player.mediaPlayer.setActionAtEnd(.stop)
        player.view.setVideoLayerGravity(.resizeAspectFill)
        player.view.layer?.opacity = 0
        player.view.corners = self.appliedCorners
        player.view.preventsCapture = parameters?.isProtected ?? false
        addSubview(player.view, positioned: .above, relativeTo: image.view)
        player.mediaPlayer.attachPlayerView(player.view)
        livePhotoView = player
        livePhotoPlayed = false

        livePhotoPlayerStatusDisposable.set((player.mediaPlayer.status |> deliverOnMainQueue).start(next: { [weak self] status in
            switch status.status {
            case .playing:
                self?.showLivePhotoVideo()
            case .paused:
                self?.hideLivePhotoVideo(animated: true)
            case .buffering:
                break
            }
        }))

        needsLayout = true
        updatePlayerIfNeeded()
    }

    private func showLivePhotoVideo() {
        guard let layer = livePhotoView?.view.layer, layer.opacity != 1 else {
            return
        }
        layer.opacity = 1
    }

    private func hideLivePhotoVideo(animated: Bool) {
        guard let layer = livePhotoView?.view.layer, layer.opacity != 0 else {
            return
        }
        layer.opacity = 0
        if animated {
            layer.animateAlpha(from: 1, to: 0, duration: 0.3)
        }
    }

    private func removeLivePhotoPlayer() {
        livePhotoStatusDisposable.set(nil)
        livePhotoFetchDisposable.set(nil)
        livePhotoPlayerStatusDisposable.set(nil)
        livePhotoView = nil
        livePhotoFile = nil
        livePhotoPlayed = false
    }

    private func removeLivePhoto() {
        removeLivePhotoPlayer()
        livePhotoBadge?.removeFromSuperview()
        livePhotoBadge = nil
    }
    
    public var isGif: Bool {
        if let media = self.media as? TelegramMediaFile {
            return media.isVideo && media.isAnimated
        } else {
            return false
        }
    }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        self.updatePlayerIfNeeded()
    }
    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        self.updatePlayerIfNeeded()
    }
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        self.updatePlayerIfNeeded()
    }
    
    
    private let animatableContentObserver = AnimatableContentObserver()

    public func updateListeners() {
        animatableContentObserver.update(for: self, target: self, selector: #selector(updatePlayerIfNeeded), contentView: table?.clipView, documentView: table?.view, options: [.contentBounds, .ownBounds, .documentFrame])
    }
    public override func willRemove() {
        super.willRemove()
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    public override func viewDidMoveToWindow() {
        updateListeners()
        self.updatePlayerIfNeeded()
        if window != nil {
            image.hostDidMoveToWindow()
        }
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updatePlayerIfNeeded()
    }
    
    public override func layout() {
        super.layout()
        
        progressView?.center()
        timableProgressView?.center()
        videoAccessory?.setFrameOrigin(8, 8)
        livePhotoBadge?.setFrameOrigin(8, 8)
        self.image.setFrameSize(frame.size)
        inkView?.frame = self.image.frame

        if let livePhotoView = livePhotoView, let image = media as? TelegramMediaImage {
            let dimensions = image.representationForDisplayAtSize(PixelDimensions(frame.size))?.dimensions.size ?? frame.size
            let size = blurBackground ? dimensions.aspectFitted(frame.size) : frame.size
            livePhotoView.view.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - size.width) / 2), floorToScreenPixels(backingScaleFactor, (frame.height - size.height) / 2), size.width, size.height)
        }

        if let file = media as? TelegramMediaFile {
            let dimensions = file.dimensions?.size ?? frame.size
            let size = blurBackground ? dimensions.aspectFitted(frame.size) : frame.size
            self.autoplayVideoView?.view.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - size.width) / 2), floorToScreenPixels(backingScaleFactor, (frame.height - size.height) / 2), size.width, size.height)
        }
        
        if let videoTimeProgress {
            videoTimeProgress.frame = bounds
        }
        
    }
    
    private func updateVideoAccessory(_ status: MediaResourceStatus, file: TelegramMediaFile, mediaPlayerStatus: MediaPlayerStatus? = nil, animated: Bool = false) {
        let maxWidth = frame.width - 10
        let text: String
        
        var isBuffering: Bool = false
        if let fetchStatus = self.fetchStatus, let status = mediaPlayerStatus {
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
        
        switch status {
        case let .Fetching(_, progress), let .Paused(progress):
            let current = String.prettySized(with: Int(Float(file.elapsedSize) * progress), afterDot: 1, forceDecimal: true)
            var size = "\(current) / \(String.prettySized(with: file.elapsedSize))"
            if maxWidth < 150 || file.elapsedSize == 0 {
                size = "\(Int(progress * 100))%"
            }
            if file.isStreamable, parent?.groupingKey == nil, maxWidth > 150 {
                if let parent = parent {
                    if !parent.flags.contains(.Unsent) && !parent.flags.contains(.Failed) {
                        size = String.durationTransformed(elapsed: file.videoDuration) + ", \(size)"
                    }
                } else {
                    size = String.durationTransformed(elapsed: file.videoDuration) + ", \(size)"
                } 
            }
            text = size
        case .Remote:
            var size = String.durationTransformed(elapsed: file.videoDuration)
            if file.isStreamable, parent?.groupingKey == nil, maxWidth > 100 {
                 size = size + ", " + String.prettySized(with: file.elapsedSize)
            }
            text = size
        case .Local:
            if file.isVideo && file.isAnimated {
                text = "GIF"
            } else {
                if let status = mediaPlayerStatus, status.generationTimestamp > 0, status.duration > 0 {
                    var timestamp = status.timestamp
                    if case .playing = status.status {
                        timestamp += max(0.0, CACurrentMediaTime() - status.generationTimestamp) * status.baseRate
                    }
                    let remainingDuration = max(0.0, min(status.duration, status.duration - timestamp))
                    text = String.durationTransformed(elapsed: Int(remainingDuration))
                } else {
                    text = String.durationTransformed(elapsed: file.videoDuration)
                }
            }
        }
        
        let isStreamable: Bool
        if let parent = parent {
            isStreamable = !parent.flags.contains(.Unsent) && !parent.flags.contains(.Failed) && file.isStreamable && !isHLSVideo(file: file)
        } else {
            isStreamable = file.isStreamable && !isHLSVideo(file: file)
        }
        
        let isCompact = parent?.groupingKey != nil || file.isAnimated || frame.width < 200 || isHLSVideo(file: file)
        
        
        videoAccessory?.updateText(text, maxWidth: maxWidth, status: status, isStreamable: isStreamable, isCompact: isCompact, soundOffOnImage: nil, isBuffering: isBuffering, animated: animated, fetch: { [weak self] in
            self?.fetch(userInitiated: true)
        }, cancelFetch: { [weak self] in
            self?.cancelFetching()
        }, click: {
                
        })
        
    }
    
    public override func executeInteraction(_ isControl: Bool) {
        
        
        if let progressView = progressView {
            switch progressView.state {
            case .Fetching:
                if isControl {
                    if let parent = parent, parent.flags.contains(.Unsent) && !parent.flags.contains(.Failed) {
                        delete()
                    }
                    cancelFetching()
                }
            default:
                super.executeInteraction(isControl)
            }
        } else {
            if autoplayVideo {
                open()
            } else {
                super.executeInteraction(isControl)
            }
        }
    }
    
    public var isStory: Bool {
        return parent?.media.first is TelegramMediaStory
    }
    
    public var autoplayVideo: Bool {
        if let autoremoveAttribute = parent?.autoremoveAttribute, autoremoveAttribute.timeout <= 60 {
           return false
        }
        if parent?.media.first is TelegramMediaStory {
            return false
        }
        if let media = media as? TelegramMediaFile, media.videoCover != nil {
            return false
        }
        // An unsent (uploading) video must show its upload-progress ring, not an autoplay preview —
        // otherwise the autoplay player replaces the radial and the upload looks like it has no progress
        // (the symptom on collage videos, where photos showed a ring but videos didn't).
        if let parent = parent, parent.flags.contains(.Unsent) {
            return false
        }
        if parent == nil {
            return true
        }
        if let media = media as? TelegramMediaFile, let parameters = self.parameters {
            let autoplay = (media.isStreamable || authenticFetchStatus == .Local) && (autoDownload || authenticFetchStatus == .Local) && parameters.autoplay && (parent?.groupingKey == nil || self.frame.width == superview?.frame.width)
            return autoplay
        }
        return false
    }
    
    public var blurBackground: Bool {
        let blur = ((parent != nil && parent?.groupingKey == nil) || parent == nil)
        if let fillContent = parameters?.fillContent, fillContent {
            return false
        }
        return blur
    }

    public override func update(size: NSSize) {

        let corners = mediaCorners(positionFlags, parameters)
        self.appliedCorners = corners
        
        var dimensions: NSSize = size
        
        if let image = media as? TelegramMediaImage {
            dimensions = image.representationForDisplayAtSize(PixelDimensions(size))?.dimensions.size ?? size
        } else if let file = media as? TelegramMediaFile {
            dimensions = file.dimensions?.size ?? size
        }
        
        let arguments = TransformImageArguments(corners: corners, imageSize: blurBackground ? dimensions.aspectFitted(size) : dimensions.aspectFilled(size), boundingSize: size, intrinsicInsets: NSEdgeInsets(), resizeMode: blurBackground ? .blurBackground : .none)
        
        self.image.set(arguments: arguments)
        if self.image.isFullyLoaded {
            
        }
    }
    private var previousIsSpoiler: Bool? = nil

    public override func update(with media: Media, size:NSSize, context:any AccountContextProtocol, parent:Message?, table:TableView?, parameters:ChatMediaLayoutParameters? = nil, animated: Bool, positionFlags: LayoutPositionFlags? = nil, approximateSynchronousValue: Bool = false) {
        
        if preloadedStreamableKey != streamablePreloadKey(media: media, parent: parent) {
            partDisposable.set(nil)
            preloadedStreamableKey = nil
        }
        
        var videoTimestamp: Int32?
        if let parent = parent {
            var storedVideoTimestamp: Int32?
            for attribute in parent.attributes {
                if let attribute = attribute as? ForwardVideoTimestampAttribute {
                    videoTimestamp = attribute.timestamp
                } else if let attribute = attribute as? DerivedDataMessageAttribute {
                    if let value = attribute.data["mps"]?.get(MediaPlaybackStoredState.self) {
                        storedVideoTimestamp = Int32(value.timestamp)
                    }
                }
            }
            if let storedVideoTimestamp {
                videoTimestamp = storedVideoTimestamp
            }

        }
        
        _ = parent?.stableVersion != self.parent?.stableVersion && self.parent?.stableId == parent?.stableId
        
        let removeViewAnimated = self.parent == nil || self.parent?.media.first?.id == parent?.media.first?.id
        
        let forceSpoiler = parameters?.forceSpoiler == true
        let messageSpoiler = parent?.isMediaSpoilered ?? false
        
        
        let isSensitive: Bool
        if let parent = parent {
            isSensitive = parent.isSensitiveContent(platform: "ios") && !context.contentConfig.sensitiveContentEnabled
        } else {
            isSensitive = false
        }
        
        let isSpoiler = (messageSpoiler || forceSpoiler || isSensitive) && (parameters?.isRevealed == false)
        let bypassSharedPreviewCache = parent != nil && parent?.containsSecretMedia != true && isSpoiler

        
        let corners = mediaCorners(positionFlags, parameters)
        let mediaUpdated = self.media == nil || !media.isSemanticallyEqual(to: self.media!) || (parent?.autoremoveAttribute != self.parent?.autoremoveAttribute) || positionFlags != self.positionFlags || corners != self.appliedCorners || self.frame.size != size || previousIsSpoiler != isSpoiler
        self.appliedCorners = corners
        
        self.previousIsSpoiler = isSpoiler

        if mediaUpdated, let rhs = media as? TelegramMediaFile, let lhs = self.media as? TelegramMediaFile  {
            if !lhs.isSemanticallyEqual(to: rhs) {
                self.autoplayVideoView = nil
            }
        }
        
        
        var clearInstantly: Bool = mediaUpdated
        if clearInstantly, parent?.stableId == self.parent?.stableId {
            clearInstantly = false
        }
        
        super.update(with: media, size: size, context: context, parent:parent, table: table, parameters:parameters, positionFlags: positionFlags)
        
        let isProtected = !isSpoiler && (parameters?.isProtected ?? false)
        

        
        
        let hostsImageLayer = !ChatRowView.usesLegacyRowChrome && !isProtected && !isSpoiler && parent?.containsSecretMedia != true && (media as? TelegramMediaImage).map { $0.video == nil } == true
        self.image.setLayerHosted(hostsImageLayer, keepingImage: !clearInstantly)
        self.image.preventsCapture = isProtected


        var dimensions: NSSize = size
        
        if let image = media as? TelegramMediaImage {
            dimensions = image.representationForDisplayAtSize(PixelDimensions(size))?.dimensions.size ?? size
        } else if let file = media as? TelegramMediaFile {
            if let image = file.videoCover {
                dimensions = image.representationForDisplayAtSize(PixelDimensions(size))?.dimensions.size ?? size
            } else {
                dimensions = file.dimensions?.size ?? size
            }
        }
        

        var updateImageSignal: Signal<ImageDataTransformation, NoError>?
        var updatedStatusSignal: Signal<(MediaResourceStatus, MediaResourceStatus), NoError>?
        
        if mediaUpdated /*mediaUpdated*/ {
        
            
            let arguments = TransformImageArguments(corners: corners, imageSize: blurBackground ? dimensions.aspectFitted(size) : dimensions.aspectFilled(size), boundingSize: size, intrinsicInsets: NSEdgeInsets(), resizeMode: blurBackground ? .blurBackground : .none)


            
            if let image = media as? TelegramMediaImage {
                
                autoplayVideoView = nil
                videoAccessory?.removeFromSuperview()
                videoAccessory = nil
                
                updateLivePhoto(image, parent: parent, context: context, isSpoiler: isSpoiler, isProtected: isProtected, corners: corners)
                
                if let parent = parent, parent.containsSecretMedia || isSpoiler {
                    updateImageSignal = chatSecretPhoto(account: context.account, imageReference: ImageMediaReference.message(message: MessageReference(parent), media: image), scale: backingScaleFactor, synchronousLoad: approximateSynchronousValue)
                } else {
                    updateImageSignal = chatMessagePhoto(account: context.account, imageReference: parent != nil ? ImageMediaReference.message(message: MessageReference(parent!), media: image) : ImageMediaReference.standalone(media: image), scale: backingScaleFactor, synchronousLoad: approximateSynchronousValue)
                }
                
                if let parent = parent, parent.flags.contains(.Unsent) && !parent.flags.contains(.Failed) {
                    updatedStatusSignal = combineLatest(chatMessagePhotoStatus(account: context.account, photo: image), context.account.pendingMessageManager.pendingMessageStatus(parent.id))
                        |> map { resourceStatus, pendingStatus in
                            if let pendingStatus = pendingStatus.0, parent.forwardInfo == nil || resourceStatus != .Local {
                                let progress: Float
                                progress = pendingStatus.progress.mediaProgress[image.imageId] ?? pendingStatus.progress.progress
                                return (.Fetching(isActive: true, progress: min(progress, progress * 85 / 100)), .Fetching(isActive: true, progress: min(progress, progress * 85 / 100)))
                            } else {
                                return (resourceStatus, resourceStatus)
                            }
                    } |> deliverOnMainQueue
                } else {
                    updatedStatusSignal = chatMessagePhotoStatus(account: context.account, photo: image, approximateSynchronousValue: approximateSynchronousValue) |> map {($0, $0)} |> deliverOnMainQueue
                }
            
            } else if let file = media as? TelegramMediaFile {
                
                removeLivePhoto()
                
                let fileReference = parent != nil ? FileMediaReference.message(message: MessageReference(parent!), media: file) : FileMediaReference.standalone(media: file)
                
               
                
                if file.isVideo, size.height > 80 {
                    if videoAccessory == nil {
                        videoAccessory = ChatMessageAccessoryView(frame: NSMakeRect(5, 5, 0, 0))
                        addSubview(videoAccessory!)
                    }
                } else {
                    videoAccessory?.removeFromSuperview()
                    videoAccessory = nil
                }
                
                if let parent = parent, parent.containsSecretMedia || isSpoiler {
                    updateImageSignal = chatSecretMessageVideo(account: context.account, fileReference: fileReference, scale: backingScaleFactor)
                } else {
                    updateImageSignal = chatMessageVideo(account: context.account, fileReference: fileReference, scale: backingScaleFactor) //chatMessageVideo(account: account, video: file, scale: backingScaleFactor)
                }
                
                if let image = file.videoCover {
                    coverFetchDisposable.set(chatMessagePhotoInteractiveFetched(account: context.account, imageReference: parent != nil ? ImageMediaReference.message(message: MessageReference(parent!), media: image) : ImageMediaReference.standalone(media: image)).start())
                } else {
                    coverFetchDisposable.set(nil)
                }
                
                if let parent = parent, parent.flags.contains(.Unsent) && !parent.flags.contains(.Failed) {
                    updatedStatusSignal = combineLatest(chatMessageFileStatus(context: context, message: parent, file: file), context.account.pendingMessageManager.pendingMessageStatus(parent.id))
                        |> map { resourceStatus, pendingStatus in
                            if let pendingStatus = pendingStatus.0 {
                                let progress: Float
                                progress = pendingStatus.progress.mediaProgress[file.fileId] ?? pendingStatus.progress.progress
                                return (.Fetching(isActive: true, progress: progress), .Fetching(isActive: true, progress: progress))
                            } else {
                                if file.isStreamable && parent.id.peerId.namespace != Namespaces.Peer.SecretChat {
                                    return (.Local, resourceStatus)
                                }
                                return (resourceStatus, resourceStatus)
                            }
                    } |> deliverOnMainQueue
                } else {
                    if file.resource is LocalFileVideoMediaResource {
                        updatedStatusSignal = .single((.Local, .Local))
                    } else {
                        let signal: Signal<MediaResourceStatus, NoError>
                        if let parent = parent {
                            signal = chatMessageFileStatus(context: context, message: parent, file: file, approximateSynchronousValue: approximateSynchronousValue)
                        } else {
                            signal = context.account.postbox.mediaBox.resourceStatus(file.resource)
                        }
                        updatedStatusSignal = signal |> deliverOnMainQueue |> map { [weak parent, weak file] status in
                            if let parent = parent, let file = file {
                                if file.isStreamable && parent.id.peerId.namespace != Namespaces.Peer.SecretChat {
                                    return (.Local, status)
                                }
                            }
                            return (status, status)
                        }
                    }
                }
            }
            
            self.image.setSignal(signal: bypassSharedPreviewCache ? .single(nil) : cachedMedia(media: media, arguments: arguments, scale: backingScaleFactor, positionFlags: positionFlags), clearInstantly: clearInstantly)

            var alreadyRendered: TransformImageArguments? = nil
            if !bypassSharedPreviewCache, self.image.isFullyLoaded, case .none = arguments.resizeMode {
                alreadyRendered = arguments
            }

            if let updateImageSignal = updateImageSignal {
                self.image.ignoreFullyLoad = mediaUpdated

                self.image.setSignal(updateImageSignal, animate: removeViewAnimated, cacheImage: { [weak media] result in
                    if let media = media, !bypassSharedPreviewCache {
                        cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale, positionFlags: positionFlags)
                    }
                }, isProtected: isProtected, alreadyRendered: alreadyRendered)
            }
            
            if let signal = updatedStatusSignal, let parent = parent, let parameters = parameters {
                updatedStatusSignal = combineLatest(signal, parameters.getUpdatingMediaProgress(parent.id)) |> map { value, updating in
                    if let progress = updating {
                        return (.Fetching(isActive: true, progress: progress), .Fetching(isActive: true, progress: progress))
                    } else {
                        return value
                    }
                }
            }
            
            self.image.set(arguments: arguments)
            
            self.image.change(size: size, animated: animated)
            
            autoplayVideoView?.view.corners = corners
            

            
            if isSpoiler {
                let current: MediaInkView
                if let view = self.inkView {
                    current = view
                } else {
                    current = MediaInkView(frame: size.bounds)
                    self.inkView = current
                    
                    let aboveView = self.progressView ?? videoAccessory
                    if let view = aboveView {
                        self.addSubview(current, positioned: .below, relativeTo: view)
                    } else {
                        self.addSubview(current)
                    }
                    if animated {
                        current.layer?.animateAlpha(from: 0.3, to: 1, duration: 0.2)
                    }
                }
                current.removeAllHandlers()
                current.set(handler: { [weak self] current in
                    if let parent = self?.parent {
                        self?.parameters?.revealMedia(parent)
                    }
                }, for: .Click)
                
                current.userInteractionEnabled = parameters?.canReveal ?? true
                
               // self.image.layer?.opacity = 0
                self.autoplayVideoView?.view.layer?.opacity = 0
                
                let image: TelegramMediaImage
                if let current = media as? TelegramMediaImage {
                    image = current
                } else if let file = media as? TelegramMediaFile {
                    image = TelegramMediaImage(imageId: file.fileId, representations: file.previewRepresentations, immediateThumbnailData: file.immediateThumbnailData, reference: nil, partialReference: nil, flags: TelegramMediaImageFlags())
                } else {
                    fatalError()
                }
                
                let imageReference = parent != nil ? ImageMediaReference.message(message: MessageReference(parent!), media: image) : ImageMediaReference.standalone(media: image)

                
                current.update(isRevealed: false, updated: mediaUpdated, context: context, imageReference: imageReference, size: size, corners: corners, synchronousLoad: approximateSynchronousValue, isSensitive: isSensitive, payAmount: parameters?.payAmount)
                current.frame = size.bounds
            } else {
                if let view = self.inkView {
                    view.userInteractionEnabled = false
                    performSubviewRemoval(view, animated: removeViewAnimated)
                    self.inkView = nil
                }
                self.image.opacity = 1
                self.autoplayVideoView?.view.layer?.opacity = 1
            }

            var first: Bool = true
            weak var statusSubscribedAutoplay: ChatVideoAutoplayView?
            
            if let updateStatusSignal = updatedStatusSignal {
                self.statusDisposable.set(updateStatusSignal.start(next: { [weak self] (status, authentic) in
                    
                    if let strongSelf = self {
                        
                        strongSelf.authenticFetchStatus = authentic
                        
                        
                        var authentic = authentic
                        if strongSelf.autoplayVideo {
                            strongSelf.fetchStatus = authentic
                            authentic = .Local
                        } else {
                            switch authentic {
                            case .Fetching:
                                strongSelf.fetchStatus = status
                            default:
                                strongSelf.fetchStatus = status
                            }
                        }
                        
                        
                        if let file = strongSelf.media as? TelegramMediaFile, strongSelf.autoplayVideo {
                            
                           
                            
                            if strongSelf.autoplayVideoView == nil, !isSpoiler {
                                let autoplay: ChatVideoAutoplayView
                                
                                let fileReference = parent != nil ? FileMediaReference.message(message: MessageReference(parent!), media: file) : FileMediaReference.standalone(media: file)
                                

//                                let isHLS: Bool = isHLSVideo(file: fileReference.media)
//                                
//                                if isHLS {
//                                    fileReference = HLSVideoContent.minimizedHLSQuality(file: fileReference)?.file ?? fileReference
//                                }
                                
                                let autoplayPlayerView = MediaPlayerView(backgroundThread: true)
                                let autoplayPlayer: ChatVideoAutoplayPlayer
                                if isAV1Video(file: fileReference.media) {
                                    autoplayPlayer = ChatVideoChunkedAutoplayPlayer(postbox: context.account.postbox, fileReference: fileReference, volume: 0.0, view: autoplayPlayerView)
                                } else {
                                    autoplayPlayer = MediaPlayer(postbox: context.account.postbox, userLocation: fileReference.userLocation, userContentType: fileReference.userContentType, reference: fileReference.resourceReference(fileReference.media.resource), streamable: file.isStreamable, video: true, preferSoftwareDecoding: false, enableSound: false, volume: 0.0, fetchAutomatically: false)
                                }
                                autoplay = ChatVideoAutoplayView(mediaPlayer: autoplayPlayer, view: autoplayPlayerView)
                                
                                strongSelf.autoplayVideoView = autoplay
                                if !strongSelf.blurBackground {
                                    strongSelf.autoplayVideoView?.view.setVideoLayerGravity(.resizeAspectFill)
                                } else {
                                    strongSelf.autoplayVideoView?.view.setVideoLayerGravity(.resize)
                                }
                            }
                            if let autoplay = strongSelf.autoplayVideoView {
                                let dimensions = (file.dimensions?.size ?? size)
                                let value = strongSelf.blurBackground ? dimensions.aspectFitted(size) : size
                                
                                autoplay.view.frame = NSMakeRect(0, 0, value.width, value.height)
                                autoplay.view.corners = corners
                                let subviews = strongSelf.subviews
                                let isPlacedAboveImage = autoplay.view.superview === strongSelf && strongSelf.image.view.flatMap({ subviews.firstIndex(of: $0) }).map { $0 + 1 < subviews.count && subviews[$0 + 1] === autoplay.view } == true
                                if !isPlacedAboveImage {
                                    strongSelf.addSubview(autoplay.view, positioned: .above, relativeTo: strongSelf.image.view)
                                }
                                if strongSelf.attachedAutoplayView !== autoplay {
                                    autoplay.mediaPlayer.attachPlayerView(autoplay.view)
                                    strongSelf.attachedAutoplayView = autoplay
                                }
                                autoplay.view.center()
                                autoplay.view.preventsCapture = isProtected
                            }
                            
                        } else {
                            strongSelf.autoplayVideoView = nil
                        }
                        
                        if let autoplay = strongSelf.autoplayVideoView, statusSubscribedAutoplay !== autoplay {
                            statusSubscribedAutoplay = autoplay
                            strongSelf.mediaPlayerStatusDisposable.set((autoplay.mediaPlayer.status |> deliverOnMainQueue).start(next: { [weak strongSelf] status in
                                strongSelf?.updateMediaStatus(status, animated: !first)
                            }))
                        }
                        
                        
                        strongSelf.updatePlayerIfNeeded()
                        
                        if let file = media as? TelegramMediaFile, strongSelf.autoplayVideoView == nil  {
                            strongSelf.updateVideoAccessory(parent == nil ? .Local : authentic, file: file, animated: !first)
                            first = false
                        }
                        var containsSecretMedia:Bool = false
                        
                        if let message = parent {
                            containsSecretMedia = message.containsSecretMedia
                        }
                        
                        if let autoremoveAttribute = parent?.autoremoveAttribute, autoremoveAttribute.timeout <= 60, autoremoveAttribute.countdownBeginTime != nil {
                            strongSelf.progressView?.removeFromSuperview()
                            strongSelf.progressView = nil
                            if strongSelf.timableProgressView == nil {
                                strongSelf.timableProgressView = TimableProgressView(size: NSMakeSize(parent?.groupingKey != nil ? 30 : 40.0, parent?.groupingKey != nil ? 30 : 40.0))
                                strongSelf.addSubview(strongSelf.timableProgressView!)
                            }
                        } else {
                            strongSelf.timableProgressView?.removeFromSuperview()
                            strongSelf.timableProgressView = nil
                            
                            switch status {
                            case .Local:
                                strongSelf.image.animatesAlphaOnFirstTransition = false
                            default:
                                strongSelf.image.animatesAlphaOnFirstTransition = false
                            }
                            
                            var removeProgress: Bool = strongSelf.autoplayVideo && !isSpoiler && strongSelf.lite == false
                            if case .Local = status, media is TelegramMediaImage, !containsSecretMedia {
                                removeProgress = true
                            }
                            if strongSelf.isStory || (isSensitive && isSpoiler) {
                                removeProgress = true
                            }
                            if let media = media as? TelegramMediaFile {
                                if isHLSVideo(file: media) {
                                    removeProgress = true
                                }
                            }
                            
                            if removeProgress {
                                 if let progressView = strongSelf.progressView {
                                    switch progressView.state {
                                    case .Fetching:
                                        progressView.state = .Fetching(progress:1.0, force: false)
                                    case .ImpossibleFetching:
                                        progressView.state = .ImpossibleFetching(progress:1.0, force: false)
                                    default:
                                        break
                                    }
                                    strongSelf.progressView = nil
                                     performSubviewRemoval(progressView, animated: removeViewAnimated)
                                }
                            } else {
                                strongSelf.progressView?.layer?.removeAllAnimations()
                                if strongSelf.progressView == nil {
                                    let progressView = RadialProgressView(theme:RadialProgressTheme(backgroundColor: .blackTransparent, foregroundColor: .white, icon: playerPlayThumb))
                                    progressView.frame = CGRect(origin: CGPoint(), size: CGSize(width: parent?.groupingKey != nil ? 30 : 40.0, height: parent?.groupingKey != nil ? 30 : 40.0))
                                    strongSelf.progressView = progressView
                                    strongSelf.addSubview(progressView, positioned: .above, relativeTo: strongSelf.inkView)
                                    strongSelf.progressView?.center()
                                    progressView.fetchControls = strongSelf.fetchControls
                                }
                            }
                        }
                        
                        
                        let progressStatus: MediaResourceStatus
                        if strongSelf.parent?.groupingKey != nil {
                            switch authentic {
                            case .Fetching:
                                progressStatus = authentic
                            default:
                                progressStatus = status
                            }
                        } else {
                            progressStatus = status
                        }
        
                        
                        switch progressStatus {
                        case let .Fetching(_, progress), let .Paused(progress):
                            
                            let sentGrouped = parent?.groupingKey != nil && (parent!.flags.contains(.Sending) || parent!.flags.contains(.Unsent))
                            
                            strongSelf.progressView?.setState(parent == nil ? .ImpossibleFetching(progress: progress, force: false) : (progress == 1.0 && sentGrouped ? .Success : .Fetching(progress: progress, force: false)), animated: strongSelf.statusChangeIsAnimatable)
                        case .Local:
                            var state: RadialProgressState = .None
                            if containsSecretMedia {
                                state = .Icon(image: parent?.groupingKey != nil ? theme.icons.chatSecretThumbSmall : theme.icons.chatSecretThumb)
                                
                                if let attribute = parent?.autoremoveAttribute, let countdownBeginTime = attribute.countdownBeginTime {
                                    let difference:TimeInterval = TimeInterval((countdownBeginTime + attribute.timeout)) - (CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
                                    let start = difference / Double(attribute.timeout) * 100.0
                                    strongSelf.timableProgressView?.theme = TimableProgressTheme(outer: 3, seconds: difference, start: start, border: false)
                                    strongSelf.timableProgressView?.progress = 0
                                    strongSelf.timableProgressView?.startAnimation()
                                    
                                }
                            } else {
                                if let file = media as? TelegramMediaFile {
                                    if file.isVideo {
                                        state = .Play
                                    }
                                }
                            }
                            
                            strongSelf.progressView?.setState(state, animated: strongSelf.statusChangeIsAnimatable)
                        case .Remote:
                            strongSelf.progressView?.setState(.Remote, animated: strongSelf.statusChangeIsAnimatable)
                        }
                        
                        
                        strongSelf.updateVideoTimestamp(videoTimestamp, duration: (media as? TelegramMediaFile)?.duration, animated: animated)
                        
                        strongSelf.needsLayout = true
                    }
                }))
               
            }
        } else {
            self.updateVideoTimestamp(videoTimestamp, duration: (media as? TelegramMediaFile)?.duration, animated: animated)
            self.needsLayout = true
        }
    }
    
    private func updateVideoTimestamp(_ videoTimestamp: Int32?, duration: Double?, animated: Bool) {
        if let videoTimestamp, let duration, duration > 0 {
            let current: VideoTimestampView
            if let view = self.videoTimeProgress {
                current = view
            } else {
                current = VideoTimestampView(frame: bounds)
                self.videoTimeProgress = current
                addSubview(current)
            }
            current.progress.set(progress: Double(videoTimestamp) / duration, animated: animated)
            current.progress.fetchingColor = theme.colors.redUI
            current.progress.containerBackground = NSColor.grayBackground.withAlphaComponent(0.2)
            current.progress.style = ControlStyle(foregroundColor: theme.colors.accent, backgroundColor: .clear, highlightColor: .clear)
            
            (current.layer as? CornerMaskLayerSimple)?.corners = appliedCorners
            
        } else if let view = self.videoTimeProgress {
            performSubviewRemoval(view, animated: animated)
            self.videoTimeProgress = nil
        }
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        image.updateFrame(bounds, transition: transition)
        
    }
    
    
    public override func clean() {
        statusDisposable.dispose()
    }
    
    public override func cancel() {
        fetchDisposable.set(nil)
        livePhotoFetchDisposable.set(nil)
        statusDisposable.set(nil)
    }
    
   
    public override func fetch(userInitiated: Bool) {
        if let context = context {
            if let media = media as? TelegramMediaFile, !media.isLocalResource {
                if let parent = parent {
                    fetchDisposable.set(messageMediaFileInteractiveFetched(context: context, messageId: parent.id, messageReference: .init(parent), file: media, userInitiated: userInitiated).start())
                } else {
                    fetchDisposable.set(freeMediaFileInteractiveFetched(context: context, fileReference: FileMediaReference.standalone(media: media)).start())
                }
            }  else if let media = media as? TelegramMediaImage, !media.isLocalResource {
                fetchDisposable.set(chatMessagePhotoInteractiveFetched(account: context.account, imageReference: parent != nil ? ImageMediaReference.message(message: MessageReference(parent!), media: media) : ImageMediaReference.standalone(media: media)).start())
                if let video = media.video, let parent = parent, !parent.containsSecretMedia {
                    livePhotoFetchDisposable.set(messageMediaFileInteractiveFetched(context: context, messageId: parent.id, messageReference: .init(parent), file: video, userInitiated: userInitiated).start())
                } else {
                    livePhotoFetchDisposable.set(nil)
                }
            }
        }
    }
    
    
    
    private func streamablePreloadKey(media: Media?, parent: Message?) -> String? {
        guard let media = media as? TelegramMediaFile, let parent = parent else {
            return nil
        }
        return "\(parent.id)-\(media.fileId)-\(media.resource.id.stringRepresentation)"
    }

    public override func preloadStreamblePart() {
        let key = streamablePreloadKey(media: media, parent: parent)
        if let key, key == preloadedStreamableKey {
            return
        }
        preloadedStreamableKey = key
        if let context = context {
            if let media = media as? TelegramMediaFile, let parent = parent {
                if isHLSVideo(file: media) {
                    let fetchSignal = HLSVideoContent.minimizedHLSQualityPreloadData(postbox: context.account.postbox, file: .message(message: MessageReference(parent), media: media), userLocation: .peer(parent.id.peerId), prefixSeconds: 10, autofetchPlaylist: true, initialQuality: FastSettings.videoQuality)
                    |> mapToSignal { fileAndRange -> Signal<Never, NoError> in
                        guard let fileAndRange else {
                            return .complete()
                        }
                        return freeMediaFileResourceInteractiveFetched(postbox: context.account.postbox, userLocation: .peer(parent.id.peerId), fileReference: fileAndRange.0, resource: fileAndRange.0.media.resource, range: (fileAndRange.1, .default))
                        |> ignoreValues
                        |> `catch` { _ -> Signal<Never, NoError> in
                            return .complete()
                        }
                    }
                    partDisposable.set(fetchSignal.start())
                } else {
                    let reference = FileMediaReference.message(message: MessageReference(parent), media: media)
                                    
                    let preload = preloadVideoResource(postbox: context.account.postbox, userLocation: .peer(parent.id.peerId), userContentType: .init(file: media), resourceReference: reference.resourceReference(media.resource), duration: 3.0)
                    partDisposable.set(preload.start())
                }
            }
        }
    }
    
    
    public override func copy() -> Any {
        return image.copy()
    }

    #if DEBUG
    var debugImageHost: (isPhoto: Bool, layer: Bool) {
        return (media is TelegramMediaImage, image.layer != nil)
    }
    #endif
    public override var contents: Any? {
        return image.contents
    }
    
}
