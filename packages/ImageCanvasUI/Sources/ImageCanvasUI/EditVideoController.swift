import Cocoa
import AVFoundation
import TGUIKit
import SwiftSignalKit
import ColorPalette
import Localization
import TelegramContext
import TelegramMediaUtils

public enum EditVideoIcons {
    public static var edit: NSImage {
        return NSImage(resource: .iconEditVideoCrop)
    }
}

public struct EditedVideoData: Equatable {
    public let originalUrl: URL
    public var trimStart: Double
    public var trimEnd: Double
    public var isMuted: Bool
    public var tools: [EditVideoTool: Int]
    public var tint: EditVideoTint
    public var orientation: EditVideoOrientation
    public var crop: CGRect?
    public var paintings: [EditImageDrawTouch]
    public var entities: [EditImageCanvasEntity]
    public var quality: EditVideoQuality?

    public init(originalUrl: URL, trimStart: Double, trimEnd: Double, isMuted: Bool = false, tools: [EditVideoTool: Int] = [:], tint: EditVideoTint = EditVideoTint(), orientation: EditVideoOrientation = .up, crop: CGRect? = nil, paintings: [EditImageDrawTouch] = [], entities: [EditImageCanvasEntity] = [], quality: EditVideoQuality? = nil) {
        self.originalUrl = originalUrl
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.isMuted = isMuted
        self.tools = tools
        self.tint = tint
        self.orientation = orientation
        self.crop = crop
        self.paintings = paintings
        self.entities = entities
        self.quality = quality
    }

    public var hasCrop: Bool {
        return orientation != .up || crop != nil
    }

    public var hasPaint: Bool {
        return !paintings.isEmpty || !entities.isEmpty
    }

    public var hasTools: Bool {
        return tools.values.contains(where: { $0 != 0 }) || !tint.isDefault
    }

    public func isTrimmed(duration: Double) -> Bool {
        return trimStart > EditVideoExport.epsilon || trimEnd < duration - EditVideoExport.epsilon
    }

    public func hasChanges(duration: Double) -> Bool {
        return isTrimmed(duration: duration) || isMuted || hasCrop || hasPaint || hasTools || quality != nil
    }
}

private final class EditVideoPlayerView: View {
    let playerLayer = AVPlayerLayer()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private func editedVideoFrameData(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    return data as Data
}

private let playButtonImage: CGImage = generateImage(NSMakeSize(60, 60), rotatedContext: { size, context in
    context.clear(size.bounds)
    context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
    context.fillEllipse(in: size.bounds)
    context.setFillColor(NSColor.white.cgColor)
    context.move(to: CGPoint(x: 24, y: 18))
    context.addLine(to: CGPoint(x: 24, y: 42))
    context.addLine(to: CGPoint(x: 43, y: 30))
    context.closePath()
    context.fillPath()
})!

private func qualityIcon(_ text: String, color: NSColor) -> CGImage {
    return generateImage(NSMakeSize(30, 30), contextGenerator: { size, context in
        context.clear(size.bounds)
        let rect = NSMakeRect(1, 4, 28, 22).insetBy(dx: 1, dy: 1)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.0 - 1.0 / System.backingScale)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil))
        context.strokePath()
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(x: rect.midX - bounds.width / 2.0 - bounds.minX, y: rect.midY - bounds.height / 2.0 - bounds.minY)
        CTLineDraw(line, context)
    })!
}

func makeEditVideoCancelButton() -> ImageButton {
    let button = ImageButton(frame: NSMakeRect(0, 0, 40, 40))
    button.autohighlight = false
    button.scaleOnClick = true
    button.set(image: EditImageCanvasGlyph.close(), for: .Normal)
    button.set(background: NSColor.white.withAlphaComponent(0.15), for: .Normal)
    button.layer?.cornerRadius = 20
    button.setAccessibilityLabel(strings().voiceOverCommonCancel)
    return button
}

func makeEditVideoDoneButton() -> ImageButton {
    let button = ImageButton(frame: NSMakeRect(0, 0, 40, 40))
    button.autohighlight = false
    button.scaleOnClick = true
    button.set(image: EditImageCanvasGlyph.check(), for: .Normal)
    button.set(background: nightAccentPalette.accent, for: .Normal)
    button.layer?.cornerRadius = 20
    button.setAccessibilityLabel(strings().voiceOverCommonDone)
    return button
}

func layoutEditVideoRow(in view: NSView, y: CGFloat, cancel: NSView, done: NSView, center: [NSView]) {
    let rowWidth = min(view.frame.width - 32, 440)
    let rowX = floor((view.frame.width - rowWidth) / 2.0)
    cancel.setFrameOrigin(NSMakePoint(rowX, y))
    done.setFrameOrigin(NSMakePoint(rowX + rowWidth - done.frame.width, y))
    let spacing: CGFloat = 10
    let total = center.reduce(0, { $0 + $1.frame.width }) + spacing * CGFloat(max(0, center.count - 1))
    var x = floor((view.frame.width - total) / 2.0)
    for item in center {
        item.setFrameOrigin(NSMakePoint(x, y + floor((40 - item.frame.height) / 2.0)))
        x += item.frame.width + spacing
    }
}

private final class EditVideoView: View {
    let playerView = EditVideoPlayerView(frame: .zero)
    let videoControl = Control()
    let playButton = ImageButton()
    let mute: ImageButton
    let scrubber = EditVideoScrubberView(frame: .zero)
    let cancel = makeEditVideoCancelButton()
    let done = makeEditVideoDoneButton()
    let crop: ImageButton
    let paint: ImageButton
    let tools: ImageButton
    let quality: ImageButton
    var videoSize: NSSize = NSMakeSize(16, 9)
    var onLayout: (() -> Void)?

    required init(frame frameRect: NSRect) {
        self.mute = makeGlassIconButton(NSImage(resource: .iconEditVideoSound).precomposed(.white), label: strings().voiceOverCommonMute)
        self.crop = makeGlassIconButton(NSImage(resource: .iconEditVideoCrop).precomposed(.white), label: strings().voiceOverCommonCrop)
        self.paint = makeGlassIconButton(NSImage(resource: .iconEditVideoPaint).precomposed(.white), label: strings().voiceOverCommonDraw)
        self.tools = makeGlassIconButton(NSImage(resource: .iconEditVideoTools).precomposed(.white), label: strings().editVideoControllerTools)
        self.quality = makeGlassIconButton(qualityIcon("HD", color: .white), label: strings().editVideoControllerQuality)
        super.init(frame: frameRect)
        playButton.set(image: playButtonImage, for: .Normal)
        playButton.autohighlight = false
        playButton.scaleOnClick = true
        _ = playButton.sizeToFit(.zero, NSMakeSize(60, 60), thatFit: true)
        playButton.setAccessibilityLabel(strings().voiceOverCommonPlay)
        videoControl.setAccessibilityLabel(strings().voiceOverCommonPlay)

        addSubview(playerView)
        addSubview(videoControl)
        addSubview(playButton)
        addSubview(scrubber)
        addSubview(mute)
        addSubview(cancel)
        addSubview(done)
        addSubview(crop)
        addSubview(paint)
        addSubview(tools)
        addSubview(quality)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateMute(isMuted: Bool, isHidden: Bool) {
        let image = isMuted ? NSImage(resource: .iconEditVideoGif).precomposed(nightAccentPalette.accent) : NSImage(resource: .iconEditVideoSound).precomposed(.white)
        mute.set(image: image, for: .Normal)
        mute.isHidden = isHidden
        mute.setAccessibilityLabel(isMuted ? strings().voiceOverCommonUnmute : strings().voiceOverCommonMute)
    }

    func updateTabs(crop hasCrop: Bool, paint hasPaint: Bool, tools hasTools: Bool, quality: EditVideoQuality, explicitQuality: Bool, qualityEnabled: Bool) {
        crop.set(image: NSImage(resource: .iconEditVideoCrop).precomposed(hasCrop ? nightAccentPalette.accent : .white), for: .Normal)
        paint.set(image: NSImage(resource: .iconEditVideoPaint).precomposed(hasPaint ? nightAccentPalette.accent : .white), for: .Normal)
        tools.set(image: NSImage(resource: .iconEditVideoTools).precomposed(hasTools ? nightAccentPalette.accent : .white), for: .Normal)
        self.quality.set(image: qualityIcon(quality.shortTitle, color: explicitQuality ? nightAccentPalette.accent : .white), for: .Normal)
        self.quality.isEnabled = qualityEnabled
        self.quality.alphaValue = qualityEnabled ? 1.0 : 0.4
    }

    func updatePlaying(_ isPlaying: Bool) {
        playButton.isHidden = isPlaying
        videoControl.setAccessibilityLabel(isPlaying ? strings().voiceOverCommonPause : strings().voiceOverCommonPlay)
    }

    override func layout() {
        super.layout()
        let rowY = frame.height - 16 - 40
        layoutEditVideoRow(in: self, y: rowY, cancel: cancel, done: done, center: [crop, paint, tools, quality])

        let scrubberWidth = min(frame.width - 32, 720)
        let scrubberY = rowY - 16 - EditVideoScrubberView.height
        scrubber.frame = NSMakeRect(floor((frame.width - scrubberWidth) / 2.0), scrubberY, scrubberWidth, EditVideoScrubberView.height)

        let top: CGFloat = 24
        let bottom = scrubberY - 12 - mute.frame.height - 8
        let area = NSMakeRect(24, top, max(1, frame.width - 48), max(1, bottom - top))
        let fitted = videoSize.aspectFitted(area.size)
        playerView.frame = NSMakeRect(floor(area.midX - fitted.width / 2.0), floor(area.midY - fitted.height / 2.0), fitted.width, fitted.height)
        videoControl.frame = playerView.frame
        playButton.setFrameOrigin(NSMakePoint(floor(playerView.frame.midX - playButton.frame.width / 2.0), floor(playerView.frame.midY - playButton.frame.height / 2.0)))
        mute.setFrameOrigin(NSMakePoint(scrubber.frame.minX, scrubberY - 8 - mute.frame.height))
        onLayout?()
    }
}

public final class EditVideoController: ModalViewController {
    private let context: (any AccountContextProtocol)?
    private let asset: AVURLAsset
    private let duration: Double
    private let hasAudio: Bool
    private let displaySize: NSSize
    private let initialData: EditedVideoData?
    private var data: EditedVideoData
    private var overlay: CGImage?
    private let completion: (URL, EditedVideoData?) -> Void
    public var onCancelled: (() -> Void)?
    private let item: AVPlayerItem
    private let player: AVPlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private let thumbnailsDisposable = MetaDisposable()
    private var thumbnailsCount: Int = 0
    private var thumbnailsSize: NSSize = .zero
    private var thumbnailsGeneration = UUID()
    private var presentationActive = true
    private var isClosing = false
    private var resumeAfterSeek = false
    private var isSeeking = false

    public init(context: (any AccountContextProtocol)?, url: URL, edited: EditedVideoData?, completion: @escaping (URL, EditedVideoData?) -> Void) {
        let originalUrl = edited?.originalUrl ?? url
        let asset = AVURLAsset(url: originalUrl)
        let seconds = CMTimeGetSeconds(asset.duration)
        let duration = seconds.isFinite ? max(0, seconds) : 0
        self.context = context
        self.asset = asset
        self.duration = duration
        self.hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
        self.displaySize = EditVideoExport.displaySize(of: originalUrl)
        self.initialData = edited
        var data = edited ?? EditedVideoData(originalUrl: originalUrl, trimStart: 0, trimEnd: duration)
        data.trimStart = min(duration, max(0, data.trimStart))
        data.trimEnd = min(duration, data.trimEnd)
        if data.trimEnd <= data.trimStart {
            data.trimEnd = duration
        }
        self.data = data
        self.item = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: item)
        self.completion = completion
        super.init()
        bar = .init(height: 0)
    }

    deinit {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        thumbnailsDisposable.dispose()
    }

    public override var containerBackground: NSColor {
        return .clear
    }

    public override var isVisualEffectBackground: Bool {
        return true
    }

    public override var background: NSColor {
        return .clear
    }

    public override func measure(size: NSSize) {
        if let contentSize = self.modal?.window.contentView?.frame.size {
            self.modal?.resize(with: NSMakeSize(contentSize.width - 80, contentSize.height - 80), animated: false)
        }
    }

    public override var dynamicSize: Bool {
        return true
    }

    public override func viewClass() -> AnyClass {
        return EditVideoView.self
    }

    private var genericView: EditVideoView {
        return self.view as! EditVideoView
    }

    private var isGif: Bool {
        return data.isMuted && hasAudio
    }

    private var hasChanges: Bool {
        if let initialData = initialData {
            return data != initialData
        }
        return data.hasChanges(duration: duration)
    }

    private var isPlaying: Bool {
        return player.rate != 0
    }

    private var currentTime: Double {
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? seconds : data.trimStart
    }

    private var effectiveQuality: EditVideoQuality {
        return data.quality ?? EditVideoQuality.bestAvailable(for: displaySize)
    }

    private func spec(includeQuality: Bool) -> EditVideoRenderSpec {
        return EditVideoRenderSpec(url: data.originalUrl, trimStart: data.trimStart, trimEnd: data.trimEnd, isMuted: isGif, tools: data.tools, tint: data.tint, orientation: data.orientation, crop: data.crop, overlay: overlay, quality: includeQuality ? data.quality : nil)
    }

    private func time(_ seconds: Double) -> CMTime {
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func seekExact(_ seconds: Double) {
        player.seek(to: time(seconds), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func still(at seconds: Double) -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        return try? generator.copyCGImage(at: time(seconds), actualTime: nil)
    }

    private func renderOverlay() {
        guard data.hasPaint else {
            overlay = nil
            return
        }
        let size = displaySize.fitted(NSMakeSize(1920, 1920))
        guard let base = generateImage(size, contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
        }, scale: 1.0) else {
            overlay = nil
            return
        }
        let image = EditedImageData(originalUrl: data.originalUrl, paintings: data.paintings, entities: data.entities)
        overlay = image.makeImage(base, interface: false)
    }

    private func refreshPreview() {
        let preview = spec(includeQuality: false)
        if preview.needsRender {
            item.videoComposition = EditVideoRenderer.videoComposition(for: asset, spec: preview, outputSize: nil, enhanceAt: data.trimStart)
        } else {
            item.videoComposition = nil
        }
        genericView.videoSize = EditVideoRenderer.croppedSize(display: displaySize, spec: preview)
        genericView.needsLayout = true
        if !isPlaying {
            seekExact(currentTime)
        }
        updateControls()
    }

    private func updateControls() {
        genericView.updateMute(isMuted: data.isMuted, isHidden: !hasAudio)
        genericView.updateTabs(crop: data.hasCrop, paint: data.hasPaint, tools: data.hasTools, quality: effectiveQuality, explicitQuality: data.quality != nil, qualityEnabled: !isGif)
    }

    private func play() {
        guard presentationActive, !isClosing, duration.isFinite, duration > 0 else {
            return
        }
        let current = currentTime
        if current < data.trimStart || current >= data.trimEnd - 0.5 {
            seekExact(data.trimStart)
            genericView.scrubber.setPosition(data.trimStart)
        }
        player.play()
        genericView.updatePlaying(true)
    }

    private func pause() {
        player.pause()
        genericView.updatePlaying(false)
    }

    private func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func applyRange() {
        item.forwardPlaybackEndTime = data.trimEnd < duration - 0.01 ? time(data.trimEnd) : .invalid
    }

    private func handlePlaybackEnd() {
        guard presentationActive, !isClosing else { return }
        if isGif {
            seekExact(data.trimStart)
            player.play()
        } else {
            pause()
            seekExact(data.trimStart)
            genericView.scrubber.setPosition(data.trimStart)
        }
    }

    private func toggleMute() {
        data.isMuted.toggle()
        player.isMuted = data.isMuted
        if data.isMuted {
            tooltip(for: genericView.mute, text: strings().editVideoControllerMutedTooltip)
            play()
        }
        updateControls()
    }

    private func showQualityMenu(_ control: Control) {
        guard !isGif, let event = NSApp.currentEvent else {
            return
        }
        let menu = ContextMenu(presentation: .current(nightAccentPalette))
        menu.addItem(ContextMenuItem(strings().videoQualityAuto, handler: { [weak self] in
            self?.data.quality = nil
            self?.updateControls()
        }, state: data.quality == nil ? .on : nil))
        let best = EditVideoQuality.bestAvailable(for: displaySize)
        for quality in EditVideoQuality.allCases.reversed() where quality.rawValue <= best.rawValue {
            menu.addItem(ContextMenuItem(quality.title, handler: { [weak self] in
                self?.data.quality = quality
                self?.updateControls()
            }, state: data.quality == quality ? .on : nil))
        }
        AppMenu(menu: menu).show(event: event, view: control)
    }

    private func openCrop() {
        guard let window = self.window, let still = still(at: currentTime) else {
            return
        }
        pause()
        let editor = EditVideoCropController(still: still, orientation: data.orientation, crop: data.crop, completion: { [weak self] orientation, crop in
            self?.data.orientation = orientation
            self?.data.crop = crop
            self?.refreshPreview()
        })
        showModal(with: editor, for: window, animated: false, animationType: .alpha)
    }

    private func openPaint() {
        guard let window = self.window, let still = still(at: currentTime) else {
            return
        }
        pause()
        let editor = EditImageCanvasController(image: still, actions: data.paintings, entities: data.entities, context: context, updatedImage: { [weak self] paintings, entities in
            self?.data.paintings = paintings
            self?.data.entities = entities
            self?.renderOverlay()
            self?.refreshPreview()
        }, closeHandler: {}, alone: true)
        showModal(with: editor, for: window, animated: false, animationType: .alpha)
    }

    private func openTools() {
        guard let window = self.window, let still = still(at: currentTime) else {
            return
        }
        pause()
        let editor = EditVideoToolsController(still: still, spec: spec(includeQuality: false), completion: { [weak self] tools, tint in
            self?.data.tools = tools
            self?.data.tint = tint
            self?.refreshPreview()
        })
        showModal(with: editor, for: window, animated: false, animationType: .alpha)
    }

    private func updateThumbnailsIfNeeded() {
        let width = genericView.scrubber.stripWidth
        guard presentationActive, !isClosing, width.isFinite, width > 1, duration.isFinite, duration > 0, displaySize.width.isFinite, displaySize.height.isFinite, displaySize.width > 0, displaySize.height > 0 else { return }
        let aspect = max(0.5, displaySize.width / displaySize.height)
        let thumbWidth = ceil(EditVideoScrubberView.stripHeight * aspect)
        let thumbnailSize = NSMakeSize(thumbWidth, EditVideoScrubberView.stripHeight)
        let pixelSize = thumbnailSize.multipliedByScreenScale()
        guard pixelSize.width.isFinite, pixelSize.height.isFinite, pixelSize.width > 0, pixelSize.height > 0, pixelSize.width <= 4096, pixelSize.height <= 4096, let count = Int(exactly: ceil(width / thumbWidth)), count > 0, count <= 4096 else { return }
        guard count != thumbnailsCount || pixelSize != thumbnailsSize else { return }
        thumbnailsCount = count
        thumbnailsSize = pixelSize
        thumbnailsGeneration = UUID()
        let generation = thumbnailsGeneration
        let request = MetaDisposable()
        thumbnailsDisposable.set(request)
        let signal = generateVideoScrubberThumbs(for: asset, composition: nil, size: thumbnailSize, count: count, gradually: true, blur: true) |> deliverOnMainQueue
        request.set(signal.start(next: { [weak self] images, _ in
            guard let self, self.presentationActive, !self.isClosing, self.thumbnailsGeneration == generation, !images.isEmpty else { return }
            self.genericView.scrubber.setThumbnails(images, width: thumbWidth)
        }))
    }

    private func done() {
        guard !isClosing else {
            return
        }
        if !hasChanges {
            isClosing = true
            pause()
            close()
            return
        }
        if !data.hasChanges(duration: duration) {
            isClosing = true
            pause()
            completion(data.originalUrl, nil)
            close()
            return
        }
        isClosing = true
        pause()
        let spec = self.spec(includeQuality: true)
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "edited_video_\(Int64.random(in: 0 ... Int64.max)).mp4")
        let info = PendingVideoRenderInfo(duration: data.trimEnd - data.trimStart, dimensions: EditVideoExport.outputDimensions(spec, display: displaySize), hasAudio: hasAudio && !data.isMuted, frame: {
            return EditVideoExport.frame(spec, maxSide: 800).flatMap(editedVideoFrameData)
        })
        PendingVideoRenders.shared.add(path: url.path, info: info, render: EditVideoExport.export(spec, to: url))
        completion(url, data)
        close()
    }

    private func cancel() {
        guard !isClosing else {
            return
        }
        let close: () -> Void = { [weak self] in
            let onCancelled = self?.isClosing == false ? self?.onCancelled : nil
            self?.isClosing = true
            self?.pause()
            self?.onCancelled = nil
            onCancelled?()
            self?.close()
        }
        if hasChanges, let window = self.window, let confirm = ImageCanvasUIHooks.shared.confirm {
            confirm(window, strings().editImageControlConfirmDiscard, strings().alertDiscard, close)
        } else {
            close()
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let genericView = self.genericView
        genericView.playerView.playerLayer.player = player
        player.isMuted = data.isMuted
        player.actionAtItemEnd = .pause
        renderOverlay()
        applyRange()
        seekExact(data.trimStart)

        let scrubber = genericView.scrubber
        scrubber.minimumDuration = EditVideoExport.minimumTrimDuration
        scrubber.isTrimmingEnabled = duration >= EditVideoExport.minimumTrimmableDuration
        scrubber.update(duration: duration, trimStart: data.trimStart, trimEnd: data.trimEnd, position: data.trimStart)
        scrubber.onBeginTrimming = { [weak self] in
            self?.pause()
        }
        scrubber.onTrim = { [weak self] start, end, isEnd in
            guard let self = self, self.presentationActive, !self.isClosing else {
                return
            }
            self.data.trimStart = start
            self.data.trimEnd = end
            self.seekExact(isEnd ? end : start)
        }
        scrubber.onEndTrimming = { [weak self] in
            guard let self = self, self.presentationActive, !self.isClosing else {
                return
            }
            self.applyRange()
            self.genericView.scrubber.update(duration: self.duration, trimStart: self.data.trimStart, trimEnd: self.data.trimEnd, position: self.currentTime)
            if self.isGif {
                self.play()
            }
        }
        scrubber.onSeek = { [weak self] position in
            guard let self = self, self.presentationActive, !self.isClosing else {
                return
            }
            if !self.isSeeking {
                self.isSeeking = true
                self.resumeAfterSeek = self.isPlaying
                self.pause()
            }
            self.seekExact(position)
        }
        scrubber.onEndSeeking = { [weak self] in
            guard let self = self, self.presentationActive, !self.isClosing else {
                return
            }
            self.isSeeking = false
            if self.resumeAfterSeek {
                self.player.play()
                self.genericView.updatePlaying(true)
            }
        }

        genericView.videoControl.set(handler: { [weak self] _ in
            self?.togglePlay()
        }, for: .Click)
        genericView.playButton.set(handler: { [weak self] _ in
            self?.play()
        }, for: .Click)
        genericView.mute.set(handler: { [weak self] _ in
            self?.toggleMute()
        }, for: .Click)
        genericView.crop.set(handler: { [weak self] _ in
            self?.openCrop()
        }, for: .Click)
        genericView.paint.set(handler: { [weak self] _ in
            self?.openPaint()
        }, for: .Click)
        genericView.tools.set(handler: { [weak self] _ in
            self?.openTools()
        }, for: .Click)
        genericView.quality.set(handler: { [weak self] control in
            self?.showQualityMenu(control)
        }, for: .Click)
        genericView.cancel.set(handler: { [weak self] _ in
            self?.cancel()
        }, for: .Click)
        genericView.done.set(handler: { [weak self] _ in
            self?.done()
        }, for: .Click)
        genericView.onLayout = { [weak self] in
            self?.updateThumbnailsIfNeeded()
        }
        genericView.updatePlaying(false)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let self = self, self.presentationActive, !self.isClosing, self.isPlaying, !self.isSeeking else {
                return
            }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                self.genericView.scrubber.setPosition(seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.handlePlaybackEnd()
        }

        refreshPreview()
        readyOnce()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationActive = true
        updateThumbnailsIfNeeded()
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.togglePlay()
            return .invoked
        }, with: self, for: .Space, priority: .modal)
        if isGif {
            play()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        presentationActive = false
        isSeeking = false
        resumeAfterSeek = false
        thumbnailsGeneration = UUID()
        thumbnailsDisposable.set(nil)
        thumbnailsCount = 0
        thumbnailsSize = .zero
        pause()
        window?.removeAllHandlers(for: self)
    }

    public override func returnKeyAction() -> KeyHandlerResult {
        done()
        return .invoked
    }

    public override func escapeKeyAction() -> KeyHandlerResult {
        cancel()
        return .invoked
    }
}
