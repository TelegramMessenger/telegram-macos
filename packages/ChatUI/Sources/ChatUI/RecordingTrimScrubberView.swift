import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import ColorPalette
import TelegramTheme
import TelegramMedia
import TelegramMediaUtils
import ObjcUtils
import Localization
import TGVideoCameraMovie
import AVFoundation

private enum Metrics {
    public static let handleWidth: CGFloat = 16
    public static let gripWidth: CGFloat = 3
    public static let gripHeight: CGFloat = 12
    public static let gripOffset: CGFloat = 8
    public static let gripVideoOffset: CGFloat = 10
    public static let hitSlop: CGFloat = 9
    public static let dimAlpha: CGFloat = 0.5
    public static let cropInset: CGFloat = 0.15
    public static let minAspect: CGFloat = 0.66
    public static let waveInset: CGFloat = handleWidth
    public static let sampleWidth: CGFloat = 2
    public static let sampleGap: CGFloat = 1
    public static let sampleMaxHeight: CGFloat = 11
    public static let sampleMinHeight: CGFloat = 2
    public static let pillWidth: CGFloat = 63
    public static let pillCollapsedWidth: CGFloat = 27
    public static let pillHeight: CGFloat = 22
    public static let pillCollapsePadding: CGFloat = 7
    public static let iconSize: CGFloat = 12
    public static let pillSpacing: CGFloat = 4
    public static let pillPadding: CGFloat = 6
    public static let minTrimWidth: CGFloat = 56
    public static let trimmableDuration: Double = 2
}

private final class TrimWaveformLayer: SimpleLayer {
    public var waveform: AudioWaveform?
    public var outsideColor: NSColor = .clear
    public var unplayedColor: NSColor = .clear
    public var playedColor: NSColor = .clear
    public var trimRange: Range<CGFloat> = 0 ..< 0
    public var progressX: CGFloat = 0

    public override init() {
        super.init()
        needsDisplayOnBoundsChange = true
    }
    public override init(layer: Any) { super.init(layer: layer) }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func draw(in ctx: CGContext) {
        guard let waveform, bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return }
        let step = Metrics.sampleWidth + Metrics.sampleGap
        guard let count = Int(exactly: max(1, floor(bounds.width / step))), count <= 4096 else { return }
        let peaks = waveform.peaks(count: count)
        guard !peaks.isEmpty else { return }
        func fill(_ path: CGPath, _ color: NSColor) {
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        let outside = CGMutablePath()
        let unplayed = CGMutablePath()
        for (i, peak) in peaks.enumerated() {
            let offset = CGFloat(i) * step
            let height = min(Metrics.sampleMaxHeight, max(Metrics.sampleMinHeight, peak * Metrics.sampleMaxHeight))
            let bar = CGPath(roundedRect: CGRect(x: offset, y: (bounds.height - height) / 2, width: Metrics.sampleWidth, height: height), cornerWidth: Metrics.sampleWidth / 2, cornerHeight: Metrics.sampleWidth / 2, transform: nil)
            (trimRange.contains(offset + Metrics.sampleWidth / 2) ? unplayed : outside).addPath(bar)
        }
        fill(outside, outsideColor)
        fill(unplayed, unplayedColor)
        let playedWidth = max(0, min(progressX, trimRange.upperBound) - trimRange.lowerBound)
        if playedWidth > 0 {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: trimRange.lowerBound, y: 0, width: playedWidth, height: bounds.height))
            fill(unplayed, playedColor)
            ctx.restoreGState()
        }
    }
}

private final class TrimWaveformView: View {
    private let content = TrimWaveformLayer()

    public var waveform: AudioWaveform? {
        didSet {
            content.waveform = waveform
            content.setNeedsDisplay()
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        backgroundColor = .clear
        layer?.addSublayer(content)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func set(outsideColor: NSColor, unplayedColor: NSColor, playedColor: NSColor) {
        content.outsideColor = outsideColor
        content.unplayedColor = unplayedColor
        content.playedColor = playedColor
        content.setNeedsDisplay()
    }
    public func update(trimRange: Range<CGFloat>, progressWidth: CGFloat) {
        content.trimRange = trimRange
        content.progressX = progressWidth
        content.setNeedsDisplay()
    }
    public override func layout() {
        super.layout()
        content.frame = bounds
    }
}

private final class TrimHandle: Control {
    private let content = View()
    private let fill = CALayer()
    private let grip = View()

    public var isLeft = true {
        didSet {
            if isLeft != oldValue {
                needsLayout = true
            }
        }
    }
    public var isVideo = false {
        didSet {
            if isVideo != oldValue {
                updateLocalizationAndTheme(theme: theme)
            }
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fill.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull(), "cornerRadius": NSNull(), "hidden": NSNull(), "contents": NSNull()]
        layer?.masksToBounds = false
        content.isEventLess = true
        content.backgroundColor = .clear
        content.layer?.masksToBounds = true
        content.layer?.addSublayer(fill)
        grip.isEventLess = true
        grip.layer?.cornerRadius = Metrics.gripWidth / 2
        content.addSubview(grip)
        addSubview(content)
        set(cursor: .resizeLeftRight, for: .Hover)
        set(cursor: .resizeLeftRight, for: .Highlight)
        updateLocalizationAndTheme(theme: theme)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = .clear
        fill.backgroundColor = theme.colors.accent.cgColor
        fill.isHidden = !isVideo
        grip.backgroundColor = isVideo ? .white : theme.colors.underSelectedColor
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        content.frame = bounds.insetBy(dx: Metrics.hitSlop, dy: 0)
        let w = content.frame.width
        let h = content.frame.height
        fill.cornerRadius = h / 2
        fill.frame = CGRect(x: isLeft ? 0 : -w, y: 0, width: w * 2, height: h)
        let offset = isVideo ? Metrics.gripVideoOffset : Metrics.gripOffset
        grip.frame = CGRect(x: isLeft ? offset : w - offset - Metrics.gripWidth, y: floorToScreenPixels(backingScaleFactor, (h - Metrics.gripHeight) / 2), width: Metrics.gripWidth, height: Metrics.gripHeight)
    }
}

private final class TrimThumbnailsView: View {
    public var isEmpty: Bool { subviews.isEmpty }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        backgroundColor = .clear
        layer?.masksToBounds = true
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func render(_ images: [CGImage]) {
        while subviews.count > images.count { subviews.removeLast() }
        while subviews.count < images.count { addSubview(makeThumb()) }
        for (view, image) in zip(subviews, images) {
            (view as? ImageView)?.image = image
        }
        needsLayout = true
    }

    private func makeThumb() -> ImageView {
        let view = ImageView()
        view.isEventLess = true
        view.isAccessibilityDecorative = true
        view.contentGravity = .resizeAspectFill
        view.layer?.masksToBounds = true
        view.layer?.contentsRect = CGRect(x: Metrics.cropInset, y: Metrics.cropInset, width: 1 - Metrics.cropInset * 2, height: 1 - Metrics.cropInset * 2)
        let separator = View()
        separator.isEventLess = true
        separator.backgroundColor = .black.withAlphaComponent(0.3)
        view.addSubview(separator)
        return view
    }

    public override func layout() {
        super.layout()
        guard !subviews.isEmpty, frame.size.width.isFinite, frame.size.height.isFinite, frame.size.width >= 0, frame.size.height >= 0 else { return }
        let width = frame.size.width / CGFloat(subviews.count)
        for (i, view) in subviews.enumerated() {
            view.frame = CGRect(x: CGFloat(i) * width, y: 0, width: width, height: frame.height)
            view.subviews.first?.frame = CGRect(x: width - .borderSize, y: 0, width: .borderSize, height: frame.height)
        }
    }
}

public final class RecordingTrimScrubberView: View {
    private let thumbnails = TrimThumbnailsView(frame: NSZeroRect)
    private let dimClip = View()
    private let dimLeft = View()
    private let dimRight = View()
    private let selection = View()
    private let waveformView = TrimWaveformView(frame: NSZeroRect)
    private let leftHandle = TrimHandle(frame: NSZeroRect)
    private let rightHandle = TrimHandle(frame: NSZeroRect)
    private let seekArea = Control()
    private let playPill = Control()
    private let playPillGlass = LiquidGlassView(frame: NSZeroRect, cornerRadius: Metrics.pillHeight / 2, hasShadow: true, hasBorder: true, tintAlpha: 0.5)
    private let playIcon = ImageView()
    private let durationView = TextView()
    private let videoPosition = View()

    private var duration: Double = 0
    private var trimRange: Range<Double> = 0 ..< 0
    private var position: Double = 0
    private var isPlaying = false
    private var isVideo = false
    private var selectionFrame: NSRect = .zero
    private var durationText = ""
    private var videoPath: String?
    private var videoPlaceholder: CGImage?
    private var thumbnailsRequest: (path: String, count: Int, size: NSSize)?
    private var thumbnailsGeneration = UUID()
    private var drag: DragState?
    private let thumbnailsDisposable = MetaDisposable()

    public var trimUpdated: ((Range<Double>, Bool, Bool) -> Void)?
    public var seek: ((Double) -> Void)?
    public var togglePlay: (() -> Void)?

    private struct DragState {
        public var origin: NSPoint
        public var range: Range<Double>
        public var isEnd: Bool
        public var width: CGFloat
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [thumbnails, dimClip, selection, waveformView, videoPosition, seekArea, leftHandle, rightHandle, playPill] as [NSView] {
            addSubview(view)
        }
        dimClip.addSubview(dimLeft)
        dimClip.addSubview(dimRight)
        for view in [playPillGlass, playIcon, durationView] as [NSView] {
            playPill.addSubview(view)
        }
        dimClip.isEventLess = true
        dimClip.backgroundColor = .clear
        dimClip.layer?.masksToBounds = true
        for dim in [dimLeft, dimRight] {
            dim.isEventLess = true
            dim.backgroundColor = .black.withAlphaComponent(Metrics.dimAlpha)
        }
        playIcon.isEventLess = true
        playIcon.isAccessibilityDecorative = true
        playPill.setAccessibilityLabel(strings().voiceOverCommonPlay)
        seekArea.setAccessibilityLabel(strings().voiceOverCommonPlaybackPosition)
        durationView.isEventLess = true
        durationView.isSelectable = false
        durationView.userInteractionEnabled = false
        selection.isEventLess = true
        videoPosition.isEventLess = true
        videoPosition.backgroundColor = .white
        videoPosition.layer?.cornerRadius = 1
        selection.layer?.masksToBounds = true
        rightHandle.isLeft = false
        playPill.layer?.masksToBounds = false
        playPill.scaleOnClick = true
        playPill.set(handler: { [weak self] _ in self?.togglePlay?() }, for: .Click)
        setupGestures()
        updateLocalizationAndTheme(theme: theme)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { thumbnailsDisposable.dispose() }

    private func setupGestures() {
        seekArea.set(handler: { [weak self] c in self?.performSeek(from: c) }, for: .Down)
        seekArea.set(handler: { [weak self] c in self?.performSeek(from: c) }, for: .MouseDragging)
        for (handle, isEnd) in [(leftHandle, false), (rightHandle, true)] {
            handle.set(handler: { [weak self] c in self?.beginDrag(from: c, isEnd: isEnd) }, for: .Down)
            handle.set(handler: { [weak self] _ in self?.endDrag() }, for: .Up)
            handle.set(handler: { [weak self] c in self?.moveDrag(from: c, isEnd: isEnd) }, for: .MouseDragging)
        }
    }

    private func performSeek(from control: Control) {
        guard duration > 0, trackWidth(frame.width) > 0, let location = control.window?.mouseLocationOutsideOfEventStream else { return }
        let point = convert(location, from: nil)
        guard point.x.isFinite else { return }
        seek?(value(forX: point.x))
    }

    private func beginDrag(from control: Control, isEnd: Bool) {
        guard duration >= Metrics.trimmableDuration, trackWidth(frame.width) > 0, let point = control.window?.mouseLocationOutsideOfEventStream, point.x.isFinite else {
            drag = nil
            return
        }
        drag = DragState(origin: point, range: trimRange, isEnd: isEnd, width: frame.width)
    }

    private func endDrag() {
        guard let state = drag, state.width == frame.width else {
            drag = nil
            return
        }
        drag = nil
        trimUpdated?(trimRange, state.isEnd, true)
    }

    private func moveDrag(from control: Control, isEnd: Bool) {
        guard let state = drag, state.isEnd == isEnd, state.width == frame.width, let current = control.window?.mouseLocationOutsideOfEventStream, current.x.isFinite, duration > 0, trackWidth(frame.width) > 0 else {
            drag = nil
            return
        }
        let delta = Double((current.x - state.origin.x) / trackWidth(frame.width)) * duration
        guard delta.isFinite else { return }
        let range: Range<Double>
        if isEnd {
            let minimum = min(minimumTrimDuration, state.range.upperBound - state.range.lowerBound)
            range = state.range.lowerBound ..< min(duration, max(state.range.lowerBound + minimum, state.range.upperBound + delta))
        } else {
            let minimum = min(minimumTrimDuration, state.range.upperBound - state.range.lowerBound)
            range = max(0, min(state.range.upperBound - minimum, state.range.lowerBound + delta)) ..< state.range.upperBound
        }
        guard range != trimRange else { return }
        trimRange = range
        needsLayout = true
        trimUpdated?(range, isEnd, false)
    }

    private func trackWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return 0 }
        return max(0, width - Metrics.handleWidth * 2)
    }
    private var minimumTrimDuration: Double {
        guard duration > 0, trackWidth(frame.width) > 0 else { return duration }
        return min(duration, max(1, Double(Metrics.minTrimWidth / trackWidth(frame.width)) * duration))
    }
    private func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }
    private func snap(_ value: CGFloat) -> CGFloat { floorToScreenPixels(backingScaleFactor, value) }
    private func handleOriginX(for value: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return snap(trackWidth(width) * CGFloat(clamp01(value / duration)))
    }
    private func value(forX x: CGFloat) -> Double {
        guard x.isFinite, trackWidth(frame.width) > 0 else { return trimRange.lowerBound }
        if x <= Metrics.handleWidth + handleOriginX(for: trimRange.lowerBound, width: frame.width) {
            return trimRange.lowerBound
        }
        if x >= Metrics.handleWidth + handleOriginX(for: trimRange.upperBound, width: frame.width) {
            return trimRange.upperBound
        }
        let value = clamp01(Double((x - Metrics.handleWidth) / trackWidth(frame.width))) * duration
        return min(trimRange.upperBound, max(trimRange.lowerBound, value))
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = .clear
        selection.backgroundColor = isVideo ? .clear : theme.colors.accent
        waveformView.set(outsideColor: theme.colors.grayIcon.withAlphaComponent(0.4), unplayedColor: theme.colors.underSelectedColor.withAlphaComponent(0.5), playedColor: theme.colors.underSelectedColor)
        playPill.backgroundColor = .clear
        refreshPlayIcon()
        updateDurationText(force: true)
    }

    private func refreshPlayIcon() {
        playIcon.image = playImage()
        playIcon.sizeToFit()
    }

    private func playImage() -> CGImage {
        let color = theme.colors.text.withAlphaComponent(0.7)
        let playing = isPlaying
        return generateImage(CGSize(width: Metrics.iconSize, height: Metrics.iconSize), rotatedContext: { size, ctx in
            ctx.clear(size.bounds)
            ctx.setFillColor(color.cgColor)
            if playing {
                ctx.fill(CGRect(x: 1, y: 1, width: 4, height: 10))
                ctx.fill(CGRect(x: 7, y: 1, width: 4, height: 10))
            } else {
                ctx.move(to: CGPoint(x: 1, y: 0))
                ctx.addLine(to: CGPoint(x: 1, y: 12))
                ctx.addLine(to: CGPoint(x: 11, y: 6))
                ctx.closePath()
                ctx.fillPath()
            }
        })!
    }

    private func updateDurationText(force: Bool = false) {
        let elapsed = isPlaying ? max(0, position - trimRange.lowerBound).rounded(.down) : max(0, trimRange.upperBound - trimRange.lowerBound).rounded()
        let value = Int(exactly: elapsed) ?? 0
        let text = String.durationTransformed(elapsed: value)
        guard force || text != durationText else { return }
        durationText = text
        let layout = TextViewLayout(.initialize(string: text, color: theme.colors.text.withAlphaComponent(0.7), font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        durationView.update(layout)
    }

    public func update(duration: Double, waveform: AudioWaveform?, trimRange: Range<Double>, position: Double, isPlaying: Bool, isVideo: Bool) {
        let wasPlaying = self.isPlaying
        let wasVideo = self.isVideo
        let state = RecordingTrimState(duration: duration, range: trimRange)
        if self.duration != state.duration || self.trimRange != state.range || wasVideo != isVideo {
            drag = nil
        }
        self.duration = state.duration
        self.trimRange = state.range
        self.position = state.position(position)
        self.isPlaying = isPlaying
        self.isVideo = isVideo
        playPill.setAccessibilityLabel(isPlaying ? strings().voiceOverCommonPause : strings().voiceOverCommonPlay)
        let canTrim = state.duration >= Metrics.trimmableDuration
        waveformView.waveform = waveform
        waveformView.isHidden = waveform == nil
        thumbnails.isHidden = !isVideo
        dimClip.isHidden = !isVideo
        for handle in [leftHandle, rightHandle] {
            handle.isVideo = isVideo
            handle.isHidden = !canTrim
        }
        if wasPlaying != isPlaying { refreshPlayIcon() }
        if wasVideo != isVideo {
            selection.backgroundColor = isVideo ? .clear : theme.colors.accent
            if !isVideo {
                invalidateThumbnails(clear: true)
            }
        }
        updateDurationText()
        needsLayout = true
    }

    private func invalidateThumbnails(clear: Bool) {
        thumbnailsGeneration = UUID()
        thumbnailsDisposable.set(nil)
        thumbnailsRequest = nil
        if clear {
            thumbnails.render([])
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            drag = nil
            invalidateThumbnails(clear: false)
        } else {
            needsLayout = true
        }
    }

    public func setVideo(path: String?, placeholder: CGImage?) {
        drag = nil
        invalidateThumbnails(clear: true)
        videoPath = path
        videoPlaceholder = placeholder
        needsLayout = true
    }

    private func updateThumbnails(size: NSSize) {
        guard window != nil, isVideo, let path = videoPath, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let thumbnailSize = NSMakeSize(size.height, size.height)
        let pixelSize = thumbnailSize.multipliedByScreenScale()
        guard pixelSize.width.isFinite, pixelSize.height.isFinite, pixelSize.width > 0, pixelSize.height > 0, pixelSize.width <= 4096, pixelSize.height <= 4096, let count = Int(exactly: ceil(size.width / size.height)), count > 0, count <= 4096 else { return }
        if let request = thumbnailsRequest, request.path == path, request.count == count, request.size == pixelSize {
            return
        }
        thumbnailsGeneration = UUID()
        let generation = thumbnailsGeneration
        thumbnailsRequest = (path, count, pixelSize)
        let request = MetaDisposable()
        thumbnailsDisposable.set(request)
        if let placeholder = videoPlaceholder, thumbnails.isEmpty {
            thumbnails.render(Array(repeating: placeholder.blurred, count: count))
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        request.set((generateVideoScrubberThumbs(for: asset, composition: nil, size: thumbnailSize, count: count, gradually: true, blur: true) |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self, self.window != nil, self.isVideo, self.thumbnailsGeneration == generation, !value.0.isEmpty else { return }
            self.thumbnails.render(value.0)
            self.needsLayout = true
        }))
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        guard size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0 else { return }
        let radius = size.height / 2
        let handleWidth = min(Metrics.handleWidth, size.width / 2)
        let leftX = handleOriginX(for: trimRange.lowerBound, width: size.width)
        let rightX = handleWidth + max(leftX, handleOriginX(for: trimRange.upperBound, width: size.width))
        let left = CGRect(x: leftX, y: 0, width: handleWidth, height: size.height)
        let right = CGRect(x: rightX, y: 0, width: handleWidth, height: size.height)
        transition.updateFrame(view: leftHandle, frame: left.insetBy(dx: -Metrics.hitSlop, dy: 0))
        transition.updateFrame(view: rightHandle, frame: right.insetBy(dx: -Metrics.hitSlop, dy: 0))
        selectionFrame = CGRect(x: left.minX, y: 0, width: max(0, right.maxX - left.minX), height: size.height)
        transition.updateFrame(view: selection, frame: selectionFrame)
        selection.layer?.cornerRadius = radius
        transition.updateFrame(view: thumbnails, frame: size.bounds)
        thumbnails.layer?.cornerRadius = radius
        transition.updateFrame(view: dimClip, frame: size.bounds)
        dimClip.layer?.cornerRadius = radius
        let dimL = isVideo ? left.maxX : selectionFrame.minX
        let dimR = isVideo ? right.minX : selectionFrame.maxX
        transition.updateFrame(view: dimLeft, frame: CGRect(x: 0, y: 0, width: max(0, dimL), height: size.height))
        transition.updateFrame(view: dimRight, frame: CGRect(x: dimR, y: 0, width: max(0, size.width - dimR), height: size.height))
        transition.updateFrame(view: waveformView, frame: CGRect(x: Metrics.waveInset, y: 0, width: max(0, size.width - Metrics.waveInset * 2), height: size.height))
        let played = handleWidth + handleOriginX(for: position, width: size.width)
        videoPosition.isHidden = !isVideo
        transition.updateFrame(view: videoPosition, frame: CGRect(x: played - 1, y: 3, width: 2, height: max(0, size.height - 6)))
        waveformView.update(trimRange: left.maxX - Metrics.waveInset ..< right.minX - Metrics.waveInset, progressWidth: played - Metrics.waveInset)
        let gap = max(0, right.minX - left.maxX)
        transition.updateFrame(view: seekArea, frame: CGRect(x: left.maxX, y: 0, width: gap, height: size.height))
        layoutPlayPill(gap: gap, leftX: left.maxX, height: size.height, transition: transition)
        updateThumbnails(size: size)
    }

    private func layoutPlayPill(gap: CGFloat, leftX: CGFloat, height: CGFloat, transition: ContainedViewLayoutTransition) {
        let icon = playIcon.frame.size
        let text = durationView.frame.size
        let contentWidth = icon.width + Metrics.pillSpacing + text.width
        let expandedWidth = max(Metrics.pillWidth, contentWidth + Metrics.pillPadding * 2)
        let collapsed = gap < expandedWidth + Metrics.pillCollapsePadding
        let pillWidth = collapsed ? Metrics.pillCollapsedWidth : expandedWidth
        let frame = CGRect(x: leftX + snap((gap - pillWidth) / 2), y: snap((height - Metrics.pillHeight) / 2), width: pillWidth, height: Metrics.pillHeight)
        transition.updateFrame(view: playPill, frame: frame)
        transition.updateFrame(view: playPillGlass, frame: frame.size.bounds)
        playPillGlass.cornerRadius = Metrics.pillHeight / 2
        playPillGlass.updateLayout(size: frame.size, transition: transition)
        playPill.isHidden = gap < Metrics.pillCollapsedWidth
        let iconY = snap((Metrics.pillHeight - icon.height) / 2)
        if collapsed {
            playIcon.frame = CGRect(x: snap((pillWidth - icon.width) / 2), y: iconY, width: icon.width, height: icon.height)
        } else {
            let contentX = snap((pillWidth - contentWidth) / 2)
            playIcon.frame = CGRect(x: contentX, y: iconY, width: icon.width, height: icon.height)
            durationView.frame = CGRect(x: contentX + icon.width + Metrics.pillSpacing, y: snap((Metrics.pillHeight - text.height) / 2), width: text.width, height: text.height)
        }
        durationView.isHidden = collapsed
    }
}
