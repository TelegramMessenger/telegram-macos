import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramMedia
import ObjcUtils
import TGVideoCameraMovie
import AVFoundation

public enum ChatRecordingOverlayState: Equatable {
    case voice
    case video
    case fixed
}

final class ChatRecorderOverlayWindow: Window {
    private static let margin: CGFloat = 120

    private weak var parentHost: Window?

    init(parent: Window) {
        self.parentHost = parent
        super.init(contentRect: parent.frame.insetBy(dx: -ChatRecorderOverlayWindow.margin, dy: -ChatRecorderOverlayWindow.margin), styleMask: [.borderless], backing: .buffered, defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.animationBehavior = .none
        self.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        self.level = parent.level
        self.appearance = parent.appearance
        self._canBecomeKey = false
        self._canBecomeMain = false
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.masksToBounds = false
    }

    func attach() {
        guard let parent = self.parentHost else {
            return
        }
        self.updateFrame()
        if self.parent !== parent {
            parent.addChildWindow(self, ordered: .above)
        }
    }

    func detach() {
        self.parentHost?.removeChildWindow(self)
        self.orderOut(nil)
    }

    func updateFrame() {
        guard let parent = self.parentHost else {
            return
        }
        let frame = parent.frame.insetBy(dx: -ChatRecorderOverlayWindow.margin, dy: -ChatRecorderOverlayWindow.margin)
        if self.frame != frame {
            self.setFrame(frame, display: false)
        }
    }

    func convert(_ point: NSPoint, fromWindow window: NSWindow) -> NSPoint {
        guard let contentView = self.contentView else {
            return point
        }
        return contentView.convert(self.convertPoint(fromScreen: window.convertPoint(toScreen: point)), from: nil)
    }

    func convert(_ point: NSPoint, from view: NSView) -> NSPoint {
        guard let window = view.window else {
            return point
        }
        return self.convert(view.convert(point, to: nil), fromWindow: window)
    }
}

public final class ChatRecorderLockControl : View {
    private let idleView: LottiePlayerView = LottiePlayerView()
    private let lockingView: LottiePlayerView = LottiePlayerView()

    private var glassEffect: LiquidGlassView?
    private let glassWidth: CGFloat = 40

    private var lockData: Data?
    private var idleData: Data?
    private let animSize: NSSize

    public required init(frame frameRect: NSRect) {
        self.animSize = NSMakeSize(frameRect.width, frameRect.width)
        super.init(frame: frameRect)
        layer?.masksToBounds = false

        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: glassWidth / 2, hasShadow: true, hasBorder: true)
        glassEffect = glass
        addSubview(glass)

        addSubview(idleView)
        addSubview(lockingView)
        lockingView.isHidden = true

        if let path = Bundle.main.path(forResource: "LockWait", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            self.idleData = data
        }
        if let path = Bundle.main.path(forResource: "Lock", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            self.lockData = data
        }

        updateLocalizationAndTheme(theme: theme)
        startIdle()
    }

    private func lottieColors() -> [LottieColor] {
        let color = theme.colors.text
        return [LottieColor(keyPath: "", color: color)]
    }

    private func startIdle() {
        guard let data = idleData else { return }
        let animation = LottieAnimation(compressed: data, key: .init(key: .bundle("LockWait"), size: animSize), cachePurpose: .none, playPolicy: .loop, maximumFps: 60, colors: lottieColors(), runOnQueue: .mainQueue())
        idleView.set(animation)
    }

    public func updateLockness(_ lockness: CGFloat) {
        currentLockness = lockness
        updateLayout(size: frame.size, transition: .immediate)
        if lockness > 0 {
            idleView.isHidden = true
            lockingView.isHidden = false
            if let data = lockData {
                let totalFrames: Int32 = 30
                let targetFrame = max(1, min(Int32(lockness * CGFloat(totalFrames)), totalFrames - 1))
                let animation = LottieAnimation(compressed: data, key: .init(key: .bundle("Lock_\(targetFrame)"), size: animSize), cachePurpose: .none, playPolicy: .loopAt(firstStart: targetFrame, range: targetFrame...targetFrame), maximumFps: 60, colors: lottieColors(), runOnQueue: .mainQueue())
                lockingView.set(animation)
            }
        } else {
            idleView.isHidden = false
            lockingView.isHidden = true
        }
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = .clear
        idleView.setColors(lottieColors())
        lockingView.setColors(lottieColors())
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    private var currentLockness: CGFloat = 0

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let glass = glassEffect {
            let glassX = (size.width - glassWidth) / 2
            let glassFrame = NSMakeRect(glassX, 0, glassWidth, size.height)
            transition.updateFrame(view: glass, frame: glassFrame)
            glass.updateLayout(size: glassFrame.size, transition: transition)
            glass.cornerRadius = min(glassWidth, size.height) / 2
        }
        let animX = (size.width - animSize.width) / 2
        let baseY = (min(size.height, glassWidth) - animSize.height) / 2
        let offset = 5 * (1.0 - currentLockness)
        let animY = baseY + offset
        transition.updateFrame(view: idleView, frame: NSMakeRect(animX, animY, animSize.width, animSize.height))
        transition.updateFrame(view: lockingView, frame: NSMakeRect(animX, animY, animSize.width, animSize.height))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


public class ChatRecorderRoundButton : ImageButton {
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autohighlight = false
        scaleOnClick = true
        setGlassEffect(size: NSMakeSize(40, 40))
        updateLocalizationAndTheme(theme: theme)
    }

    public func icon(_ theme: TelegramPresentationTheme) -> CGImage? {
        return nil
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        backgroundColor = .clear
        if let icon = icon(theme) {
            set(image: icon, for: .Normal)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public final class ChatRecorderSingleTimeControl : ChatRecorderRoundButton {
    public var selectionChanged: ((Bool) -> Void)?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        set(handler: { control in
            control.isSelected = !control.isSelected
        }, for: .Click)
    }

    public override var isSelected: Bool {
        didSet {
            updateLocalizationAndTheme(theme: theme)
            if oldValue != isSelected {
                selectionChanged?(isSelected)
            }
        }
    }

    public override func icon(_ theme: TelegramPresentationTheme) -> CGImage? {
        return NSImage(named: isSelected ? "Icon_OnceView_Filled" : "Icon_OnceView")!.precomposed(theme.colors.text)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public final class ChatRecorderPauseControl : ChatRecorderRoundButton {
    public enum Kind {
        case pause
        case recordMore
    }

    public var kind: Kind = .pause {
        didSet {
            if kind != oldValue {
                updateLocalizationAndTheme(theme: theme)
            }
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    private static let iconSize: NSSize = NSMakeSize(30, 30)

    public override func icon(_ theme: TelegramPresentationTheme) -> CGImage? {
        switch kind {
        case .pause:
            let color = theme.colors.text
            return generateImage(ChatRecorderPauseControl.iconSize, rotatedContext: { size, context in
                context.clear(size.bounds)
                context.setFillColor(color.cgColor)
                let barWidth: CGFloat = 4.5
                let barHeight: CGFloat = 14
                let barSpacing: CGFloat = 7.5
                let cornerRadius: CGFloat = 1.5
                let x = (size.width - barSpacing - barWidth) / 2
                let y = (size.height - barHeight) / 2
                context.addPath(CGPath(roundedRect: NSMakeRect(x, y, barWidth, barHeight), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
                context.addPath(CGPath(roundedRect: NSMakeRect(x + barSpacing, y, barWidth, barHeight), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
                context.fillPath()
            })!
        case .recordMore:
            return FastSettings.recordingState == .voice ? theme.icons.chat_input_record_voice : theme.icons.chat_input_record_video
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class ChatRecorderOverlayView : Control {
    private let stateView: ImageView = ImageView()
    private var isPaused: Bool = false
    private let transcribeLines = ImageView()
    private let transcribeStop = ImageView()
    private var transcribeProgress: CGFloat = 0
    private(set) var isTranscribing: Bool = false
    let blobView: ChatRecordingBlobView
    private let recordingCentreDiameter: CGFloat
    private let pausedCentreDiameter: CGFloat = 40

    public required init(frame frameRect: NSRect) {
        recordingCentreDiameter = frameRect.width - 40
        let side = ChatRecordingBlobAppearance.side(centreDiameter: recordingCentreDiameter)
        blobView = ChatRecordingBlobView(frame: NSMakeRect(0, 0, side, side))

        super.init(frame: frameRect)
        layer?.masksToBounds = false
        backgroundColor = .clear

        addSubview(blobView)
        blobView.center()
        blobView.isDarkAppearance = theme.colors.isDark
        blobView.setColor(theme.colors.accent, animated: false)
        addSubview(stateView)
        stateView.isAccessibilityDecorative = true

        for glyph in [transcribeLines, transcribeStop] {
            glyph.isAccessibilityDecorative = true
            glyph.isEventLess = true
            glyph.layer?.opacity = 0
            addSubview(glyph)
        }
        transcribeLines.image = ChatRecorderOverlayView.linesGlyph
        transcribeStop.image = ChatRecorderOverlayView.stopGlyph
        layoutTranscribeGlyphs()

        blobView.startAnimating()
    }

    private static let glyphSize = NSMakeSize(30, 30)

    private static let linesGlyph: CGImage = generateImage(glyphSize, rotatedContext: { size, context in
        context.clear(size.bounds)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2.5)
        context.setLineCap(.round)
        let widths: [CGFloat] = [20, 20, 12]
        let left = (size.width - 20) / 2
        for (index, width) in widths.enumerated() {
            let y = size.height / 2 + CGFloat(index - 1) * 6
            context.move(to: CGPoint(x: left, y: y))
            context.addLine(to: CGPoint(x: left + width, y: y))
        }
        context.strokePath()
    })!

    private static let stopGlyph: CGImage = generateImage(glyphSize, rotatedContext: { size, context in
        context.clear(size.bounds)
        context.setFillColor(NSColor.white.cgColor)
        let side: CGFloat = 20
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
        context.fillPath()
    })!

    private func layoutTranscribeGlyphs() {
        let size = ChatRecorderOverlayView.glyphSize
        let frame = NSMakeRect(floorToScreenPixels(System.backingScale, (self.frame.width - size.width) / 2), floorToScreenPixels(System.backingScale, (self.frame.height - size.height) / 2), size.width, size.height)
        transcribeLines.frame = frame
        transcribeStop.frame = frame
    }

    public override func layout() {
        super.layout()
        layoutTranscribeGlyphs()
    }

    func updateTranscribeProgress(_ progress: CGFloat) {
        guard !isTranscribing else {
            return
        }
        let progress = max(0, min(1, progress))
        let wasTinted = transcribeProgress > 0.25
        transcribeProgress = progress
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let glyphScale = 0.6 + 0.4 * progress
        transcribeLines.layer?.opacity = Float(progress)
        transcribeLines.layer?.transform = ChatRecorderOverlayView.centeredScale(glyphScale, size: transcribeLines.frame.size)
        stateView.layer?.opacity = Float(1 - progress)
        CATransaction.commit()
        if wasTinted != (progress > 0.25) {
            updateInside()
        }
    }

    func setTranscribing(_ transcribing: Bool, animated: Bool) {
        guard transcribing != isTranscribing else {
            return
        }
        isTranscribing = transcribing
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transcribeLines.layer?.transform = CATransform3DIdentity
        transcribeLines.layer?.opacity = transcribing ? 1 : 0
        transcribeStop.layer?.opacity = 0
        stateView.layer?.opacity = transcribing ? 0 : 1
        CATransaction.commit()
        if transcribing, animated {
            layer?.animateScaleSpring(from: 0.8, to: 1, duration: 0.45, bounce: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: { [weak self] in
                self?.morphToStop()
            })
        } else if transcribing {
            morphToStop()
        }
        updateInside()
    }

    private func morphToStop() {
        guard isTranscribing else {
            return
        }
        guard let linesLayer = transcribeLines.layer, let stopLayer = transcribeStop.layer else {
            return
        }
        linesLayer.opacity = 0
        stopLayer.opacity = 1
        linesLayer.animateAlpha(from: 1, to: 0, duration: 0.2)
        stopLayer.animateAlpha(from: 0, to: 1, duration: 0.2)
        stopLayer.animateScaleSpring(from: 0.4, to: 1, duration: 0.35, bounce: true)
    }

    private static func centeredScale(_ scale: CGFloat, size: NSSize) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -size.width / 2, -size.height / 2, 0)
    }

    var isFlat: Bool {
        get {
            return blobView.isFlat
        }
        set {
            blobView.isFlat = newValue
        }
    }

    public func updateState(_ overlayState: ChatRecordingOverlayState) {
        switch overlayState {
        case .voice:
            stateView.image = theme.icons.chatOverlayVoiceRecording
        case .video:
            stateView.image = theme.icons.chatOverlayVideoRecording
        case .fixed:
            stateView.image = theme.icons.send_message_large
        }
        stateView.sizeToFit()
        stateView.center()

        updateInside()
    }

    func updateLevel(_ level: CGFloat) {
        blobView.updateLevel(level)
    }

    public func updatePaused(_ paused: Bool) {
        guard paused != isPaused else {
            return
        }
        isPaused = paused
        isEventLess = paused
        let side = ChatRecordingBlobAppearance.side(centreDiameter: paused ? pausedCentreDiameter : recordingCentreDiameter)
        blobView.setFrameSize(NSMakeSize(side, side))
        blobView.center()
        if paused {
            blobView.stopAnimating()
        } else {
            blobView.startAnimating()
        }
        updateInside()
    }

    var isMouseInsideCentre: Bool {
        guard let window = window else {
            return false
        }
        let point = blobView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let radius = (isPaused ? pausedCentreDiameter : recordingCentreDiameter) / 2
        return hypot(point.x - blobView.bounds.midX, point.y - blobView.bounds.midY) <= radius
    }

    public func updateInside() {
        let color = (isPaused || isTranscribing || transcribeProgress > 0.25 || mouseInside()) ? theme.colors.accent : theme.colors.redUI
        blobView.setColor(color, animated: true)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
