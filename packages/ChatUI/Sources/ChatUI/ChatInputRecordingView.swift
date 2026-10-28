import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import AlertsUI
import InputDataUI
import MediaRecorderUI


public class ChatInputRecordingView: View {

    private let descView: TextView = TextView()
    private let timerView = RecordingTimerView()
    private let statusImage: ImageView = ImageView()
    private let recView: View = View(frame: NSMakeRect(0, 0, 14, 14))

    private let chatInteraction: ChatInteraction
    private let recorder: ChatRecordingState

    private let disposable: MetaDisposable = MetaDisposable()
    private let micLevelDisposable: MetaDisposable = MetaDisposable()

    private let glassEffect: LiquidGlassView = LiquidGlassView(frame: NSZeroRect, cornerRadius: 20, hasShadow: true, hasBorder: true)

    public var glassInset: NSEdgeInsets = NSEdgeInsetsZero

    private var glassFrameInLayout: NSRect {
        let bottomY = frame.height - 40
        let minX = glassInset.left
        let width = max(0, frame.width - glassInset.left - glassInset.right)
        return NSMakeRect(minX, bottomY, width, 40)
    }

    private let overlayView: ChatRecorderOverlayView
    private let lockControl: ChatRecorderLockControl
    private let singleTimeControl: ChatRecorderSingleTimeControl
    private let pauseControl: ChatRecorderPauseControl

    private let overlaySize: CGFloat = 100
    private let overlayVisibleDiameter: CGFloat = 60
    private let controlSize: CGFloat
    private let lockHeight: CGFloat

    private let stackGap: CGFloat = 10

    private var state: ChatRecordingOverlayState
    private var startMouseLocation: NSPoint = .zero
    private var sendButtonCenter: NSPoint = .zero
    private var didLayoutOverlay: Bool = false
    private var didUpdateSendButtonCenter: Bool = false
    private var appliedFloatingVisibility: (ChatRecordingOverlayState, Bool, Bool)?
    private var lockness: CGFloat = 0
    private var overlayDragOffset: CGFloat = 0
    private var overlayDragOffsetX: CGFloat = 0
    private var transcribeProgress: CGFloat = 0
    private var isTranscribing: Bool = false
    private var descMode: DescriptionMode = .plain

    private enum DescriptionMode: Equatable {
        case plain
        case fixed
        case swipe
        case transcribing
    }

    private var canTranscribe: Bool {
        return !isVideoRecorder && ChatVoiceTranscription.isSupported && chatInteraction.voiceTranscription != nil
    }
    private var columnAnchor: NSPoint?

    private let deleteButton: ImageButton = ImageButton()
    private let scrubber: RecordingTrimScrubberView = RecordingTrimScrubberView(frame: NSZeroRect)

    private let composerButtonSize: CGFloat = 40
    private let composerGap: CGFloat = 10
    private let trimBarInset: CGFloat = 3

    private let isVideoRecorder: Bool
    private var isPaused: Bool = false
    private var isDismissing: Bool = false
    private var overlayHandedOff: Bool = false
    private var draggingPreview: Bool = false
    private var preview: ChatRecordingPreviewData?
    private var previewPlayer: RecordingPreviewPlayer?
    private var trimRange: Range<Double> = 0 ..< 0
    private var previewGeneration = UUID()
    private var isResuming = false

    private var descHold: Bool = false
    private var descWidth: CGFloat = 0

    private let previewDisposable = MetaDisposable()
    private let resumeDisposable = MetaDisposable()
    private let submissionDisposable = MetaDisposable()

    private var overlayWindow: ChatRecorderOverlayWindow?

    private var parent: Window? {
        return chatInteraction.interactionContext.window
    }

    public init(frame frameRect: NSRect, chatInteraction: ChatInteraction, recorder: ChatRecordingState) {
        self.chatInteraction = chatInteraction
        self.recorder = recorder
        self.isVideoRecorder = recorder is ChatRecordingVideoState
        self.state = recorder is ChatRecordingAudioState ? .voice : .video
        
        

        controlSize = 40
        lockHeight = 50

        overlayView = ChatRecorderOverlayView(frame: NSMakeRect(0, 0, overlaySize, overlaySize))
        overlayView.isFlat = chatInteraction.context.isLite(.blur)
        lockControl = ChatRecorderLockControl(frame: NSMakeRect(0, 0, controlSize, lockHeight))
        singleTimeControl = ChatRecorderSingleTimeControl(frame: NSMakeRect(0, 0, controlSize, controlSize))
        pauseControl = ChatRecorderPauseControl(frame: NSMakeRect(0, 0, controlSize, controlSize))

        super.init(frame: frameRect)

        layer?.masksToBounds = false

        addSubview(glassEffect, positioned: .below, relativeTo: nil)
        backgroundColor = .clear


        statusImage.image = FastSettings.recordingState == .voice ? theme.icons.chatVoiceRecording : theme.icons.chatVideoRecording
        statusImage.animates = true
        statusImage.setAccessibilityLabel(FastSettings.recordingState == .voice ? strings().voiceOverChatRecordModeVoiceMessage : strings().voiceOverChatRecordModeVideoMessage)
        statusImage.sizeToFit()

        addSubview(descView)
        addSubview(timerView)
        addSubview(recView)
        addSubview(deleteButton)
        addSubview(scrubber)

        deleteButton.isHidden = true
        scrubber.isHidden = true
        deleteButton.autohighlight = false
        deleteButton.scaleOnClick = true
        deleteButton.setAccessibilityLabel(strings().voiceOverCommonDelete)

        deleteButton.set(handler: { [weak self] _ in
            self?.discardRecording()
        }, for: .Click)

        pauseControl.layer?.opacity = 0
        pauseControl.set(handler: { [weak self] _ in
            self?.togglePause()
        }, for: .Click)

        scrubber.togglePlay = { [weak self] in
            self?.previewPlayer?.toggle()
        }
        scrubber.seek = { [weak self] value in
            self?.previewPlayer?.seek(to: value)
        }
        scrubber.trimUpdated = { [weak self] range, updatedEnd, applied in
            self?.updateTrim(range, updatedEnd: updatedEnd, applied: applied)
        }

        overlayView.updateState(state)
        singleTimeControl.layer?.opacity = 0
        singleTimeControl.selectionChanged = { [weak self] value in
            self?.recorder.isOneTime = value
        }

        recView.layer?.cornerRadius = recView.frame.width / 2

        disposable.set(combineLatest(recorder.status |> deliverOnMainQueue, recorder.holdpromise.get() |> deliverOnMainQueue).start(next: { [weak self] state, hold in
            guard let self, !self.isDismissing, !self.recorder.isCancelled else {
                return
            }
            switch state {
            case let .recording(duration):
                if duration > 0, !self.isVideoRecorder {
                }
                self.updateDescription(hold)
                self.timerView.update(duration: duration, running: true)
                self.updatePaused(false)
            case let .paused(duration):
                if duration > 0 {
                    self.updateDescription(hold)
                    self.timerView.update(duration: duration, running: false)
                    self.updatePaused(true)
                }
            }
        }))

        submissionDisposable.set((recorder.submissionState.get() |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.updateSubmissionState(state)
        }))

        updateLocalizationAndTheme(theme: theme)
    }

    public func updateSendButtonCenter(_ center: NSPoint, transition: ContainedViewLayoutTransition) {
        self.sendButtonCenter = center
        didUpdateSendButtonCenter = true
        layoutFloatingControls(transition: didLayoutOverlay ? transition : .immediate)
        if !didLayoutOverlay, overlayView.superview != nil {
            didLayoutOverlay = true
            overlayView.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.4)
            overlayView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        }
    }

    private func updateFloatingFrame(_ view: NSView, _ localFrame: NSRect, transition: ContainedViewLayoutTransition) {
        if let host = view.superview, host !== self {
            transition.updateFrame(view: view, frame: self.convert(localFrame, to: host))
        } else {
            transition.updateFrame(view: view, frame: localFrame)
        }
    }

    private var sendButtonCenterInOverlaySpace: NSPoint {
        if let overlayWindow, self.window != nil {
            return overlayWindow.convert(sendButtonCenter, from: self)
        }
        guard let host = overlayView.superview else { return sendButtonCenter }
        return self.convert(sendButtonCenter, to: host)
    }

    private var floatingControls: [NSView] {
        [overlayView, lockControl, pauseControl, singleTimeControl]
    }

    private var ownedFloatingControls: [NSView] {
        floatingControls.filter { !(overlayHandedOff && $0 === overlayView) }
    }

    private var floatingStack: [(view: NSView, height: CGFloat)] {
        if isTranscribing {
            return []
        }
        if state != .fixed {
            return [(lockControl, lockHeight - (lockHeight - controlSize) * lockness)]
        }
        if recorder.canPause {
            return [(pauseControl, controlSize), (singleTimeControl, controlSize)]
        }
        return [(singleTimeControl, controlSize)]
    }

    private func layoutFloatingControls(transition: ContainedViewLayoutTransition) {
        guard didUpdateSendButtonCenter else {
            for view in ownedFloatingControls {
                view.layer?.opacity = 0
            }
            return
        }
        overlayWindow?.updateFrame()
        let center = sendButtonCenterInOverlaySpace
        if !overlayHandedOff {
            transition.updateFrame(view: overlayView, frame: NSMakeRect(
                center.x - overlaySize / 2 - overlayDragOffsetX,
                center.y - overlaySize / 2 + overlayDragOffset,
                overlaySize, overlaySize
            ))
        }

        let controlX = center.x - controlSize / 2
        let anchorTop: CGFloat
        if let columnAnchor, let overlayWindow, let window = self.window {
            anchorTop = overlayWindow.convert(columnAnchor, fromWindow: window).y
        } else if let columnAnchor, let host = overlayView.superview {
            anchorTop = host.convert(columnAnchor, from: nil).y
        } else {
            anchorTop = center.y + overlayVisibleDiameter / 2
        }
        let baseY = anchorTop + stackGap
        var y = baseY

        let stack = floatingStack
        for entry in stack {
            transition.updateFrame(view: entry.view, frame: NSMakeRect(controlX, y, controlSize, entry.height))
            (entry.view as? ChatRecorderLockControl)?.updateLayout(size: NSMakeSize(controlSize, entry.height), transition: transition)
            y += entry.height + stackGap
        }

        for view in floatingControls where view !== overlayView && !stack.contains(where: { $0.view === view }) {
            transition.updateFrame(view: view, frame: NSMakeRect(controlX, baseY, controlSize, view.frame.height))
        }
        updateFloatingVisibility()
    }

    private func updateFloatingVisibility() {
        let key = (state, recorder.canPause, isTranscribing)
        if let applied = appliedFloatingVisibility, applied == key {
            return
        }
        appliedFloatingVisibility = key
        if !overlayHandedOff {
            overlayView.layer?.opacity = 1
        }
        if isTranscribing {
            lockControl.change(opacity: 0, animated: true)
            pauseControl.change(opacity: 0, animated: true)
            singleTimeControl.change(opacity: 0, animated: true)
        } else if state == .fixed {
            lockControl.change(opacity: 0, animated: true)
            if recorder.canPause {
                pauseControl.kind = .pause
                pauseControl.layer?.opacity = 1
                pauseControl.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                showPauseTooltip()
            } else {
                pauseControl.layer?.opacity = 0
            }
            singleTimeControl.layer?.opacity = 1
            singleTimeControl.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        } else {
            lockControl.layer?.opacity = 1
            pauseControl.layer?.opacity = 0
            singleTimeControl.layer?.opacity = 0
        }
    }

    public func updateColumnAnchor(_ anchor: NSPoint?, transition: ContainedViewLayoutTransition) {
        columnAnchor = anchor
        layoutFloatingControls(transition: transition)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        statusImage.image = FastSettings.recordingState == .voice ? theme.icons.chatVoiceRecording : theme.icons.chatVideoRecording
        recView.backgroundColor = theme.colors.accent
        deleteButton.set(image: theme.icons.chatDeleteMessagesActive, for: .Normal)
        _ = deleteButton.sizeToFit(.zero, NSMakeSize(composerButtonSize, composerButtonSize), thatFit: true)
        deleteButton.setGlassEffect(size: NSMakeSize(composerButtonSize, composerButtonSize))
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window = newWindow as? Window {
            showOverlay(window: window)
            startBlinking()
        } else {
            resetPreviewState()
            if isTranscribing {
                chatInteraction.voiceTranscription?.recordingStopped()
            }
            (window as? Window)?.removeAllHandlers(for: self)
            hideOverlay()
            recView.layer?.removeAllAnimations()
        }
    }

    public override func viewDidMoveToWindow() {
        updateDescription(false)
        timerView.update(duration: 0, running: false)
        if window != nil, isPaused, preview == nil {
            loadPreview()
        }
    }

    private func updateDescription(_ hold: Bool) {
        let width = glassFrameInLayout.width - 50 - 60
        let mode: DescriptionMode
        if isTranscribing {
            mode = .transcribing
        } else if transcribeProgress > 0.15 {
            mode = .swipe
        } else {
            mode = hold ? .fixed : .plain
        }
        guard hold != descHold || width != descWidth || mode != descMode || descView.textLayout == nil else {
            return
        }
        let modeChanged = mode != descMode && descView.textLayout != nil
        descHold = hold
        descWidth = width
        descMode = mode

        let text: String
        switch mode {
        case .plain:
            text = strings().audioRecordHelpPlain
        case .fixed:
            text = strings().audioRecordHelpFixed
        case .swipe:
            text = strings().chatRecordingTranscribeSwipe
        case .transcribing:
            text = strings().chatRecordingTranscribeActive
        }
        if modeChanged, window != nil {
            descView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        }

        let descLayout = TextViewLayout(.initialize(string: text, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 2, truncationType: .middle, alignment: .center)
        descLayout.measure(width: width)
        descView.update(descLayout)

        self.needsLayout = true
    }

    deinit {
        overlayWindow?.detach()
        timerView.stop()
        disposable.dispose()
        micLevelDisposable.dispose()
        previewDisposable.dispose()
        resumeDisposable.dispose()
        submissionDisposable.dispose()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let bottomY = size.height - 40
        let glassMinX = glassInset.left
        let glassMaxX = size.width - glassInset.right
        let midY = bottomY + 20

        var barMinX = glassMinX
        var barMaxX = glassMaxX
        if isPaused {
            let deleteFrame = NSMakeRect(glassMinX, bottomY, composerButtonSize, 40)
            updateFloatingFrame(deleteButton, deleteFrame, transition: transition)
            barMinX = deleteFrame.maxX + composerGap
            barMaxX = max(barMinX, sendButtonCenter.x - composerButtonSize / 2 - composerGap)
        }

        let glassFrame = NSMakeRect(barMinX, bottomY, max(0, barMaxX - barMinX), 40)
        transition.updateFrame(view: glassEffect, frame: glassFrame)
        glassEffect.updateLayout(size: glassFrame.size, transition: transition)

        if isPaused {
            let trimFrame = glassFrame.insetBy(dx: trimBarInset, dy: trimBarInset)
            updateFloatingFrame(scrubber, trimFrame, transition: transition)
            scrubber.updateLayout(size: trimFrame.size, transition: transition)
            return
        }

        updateDescription(descHold)

        transition.updateFrame(view: recView, frame: NSMakeRect(glassMinX + 20, midY - recView.frame.height / 2, recView.frame.width, recView.frame.height))
        transition.updateFrame(view: timerView, frame: NSMakeRect(recView.frame.maxX + 10, midY - timerView.frame.height / 2, timerView.frame.width, timerView.frame.height))
        transition.updateFrame(view: statusImage, frame: NSMakeRect(glassMaxX - statusImage.frame.width - 20, midY - statusImage.frame.height / 2, statusImage.frame.width, statusImage.frame.height))

        let maxDescWidth = glassFrame.width - (statusImage.frame.width + 20 + 50)
        let descX = glassMinX + 60 + floorToScreenPixels(backingScaleFactor, (maxDescWidth - descView.frame.width) / 2)
        transition.updateFrame(view: descView, frame: NSMakeRect(descX, midY - descView.frame.height / 2, descView.frame.width, descView.frame.height))
    }

    private func showOverlay(window: Window) {
        startMouseLocation = window.mouseLocationOutsideOfEventStream

        overlayWindow?.detach()
        let overlayWindow = ChatRecorderOverlayWindow(parent: window)
        self.overlayWindow = overlayWindow
        overlayWindow.attach()

        if let contentView = window.contentView, let floatingHost = overlayWindow.contentView {
            for view in floatingControls {
                floatingHost.addSubview(view, positioned: .above, relativeTo: nil)
            }
            contentView.addSubview(deleteButton, positioned: .above, relativeTo: nil)
            contentView.addSubview(scrubber, positioned: .above, relativeTo: nil)
            layoutFloatingControls(transition: .immediate)
            updateLayout(size: frame.size, transition: .immediate)
        }

        let isVideoRecorder = self.isVideoRecorder
        micLevelDisposable.set((recorder.micLevel |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.overlayView.updateLevel(isVideoRecorder ? CGFloat(value) * ChatRecordingBlobAppearance.maxLevel : CGFloat(value))
        }))

        let mouseMoved: (NSEvent) -> KeyHandlerResult = { [weak self] _ in
            guard let self else { return .rejected }
            if self.isPaused {
                return .rejected
            }
            self.overlayView.updateInside()
            return .invoked
        }
        window.set(mouseHandler: mouseMoved, with: self, for: .mouseMoved, priority: .modal)
        overlayWindow.set(mouseHandler: mouseMoved, with: self, for: .mouseMoved, priority: .modal)

        window.set(mouseHandler: { [weak self] _ -> KeyHandlerResult in
            guard let self else { return .rejected }
            if self.draggingPreview {
                return .rejected
            }
            if self.state != .fixed {
                self.handleDrag()
            }
            return .invoked
        }, with: self, for: .leftMouseDragged, priority: .modal)

        let proccessMouseUp: (NSEvent) -> KeyHandlerResult = { [weak self] _ in
            guard let self else { return .rejected }
            return self.proccessMouseUp()
        }

        window.set(mouseHandler: { _ in return .invoked }, with: self, for: .leftMouseDown, priority: .modal)
        window.set(mouseHandler: proccessMouseUp, with: self, for: .leftMouseUp, priority: .modal)
        window.set(mouseHandler: { [weak self] _ in
            return self?.isMouseOverTranscription == true ? .invokeNext : .invoked
        }, with: self, for: .rightMouseDown, priority: .modal)
        window.set(mouseHandler: { [weak self] _ in
            return self?.isMouseOverTranscription == true ? .invokeNext : .invoked
        }, with: self, for: .rightMouseUp, priority: .modal)
        overlayWindow.set(mouseHandler: { _ in return .invoked }, with: self, for: .leftMouseDown, priority: .modal)
        overlayWindow.set(mouseHandler: proccessMouseUp, with: self, for: .leftMouseUp, priority: .modal)
        overlayWindow.set(mouseHandler: { _ in return .invoked }, with: self, for: .rightMouseDown, priority: .modal)
        overlayWindow.set(mouseHandler: { _ in return .invoked }, with: self, for: .rightMouseUp, priority: .modal)

        if recorder.autohold {
            hold()
        }
    }

    private func hideOverlay() {
        timerView.stop()
        micLevelDisposable.set(nil)
        for view in ownedFloatingControls {
            view.removeFromSuperview()
        }
        overlayWindow?.removeAllHandlers(for: self)
        overlayWindow?.detach()
        overlayWindow = nil
        addSubview(deleteButton)
        addSubview(scrubber)
        didLayoutOverlay = false
        didUpdateSendButtonCenter = false
        appliedFloatingVisibility = nil
    }

    public func animateOut(completion: @escaping () -> Void) {
        guard !isDismissing else {
            return
        }
        isDismissing = true
        if isTranscribing {
            chatInteraction.voiceTranscription?.recordingStopped()
        }

        parent?.removeAllHandlers(for: self)
        overlayWindow?.removeAllHandlers(for: self)
        timerView.stop()
        micLevelDisposable.set(nil)
        resetPreviewState()
        recView.layer?.removeAllAnimations()

        let duration: Double = 0.3
        let fade: Double = 0.18

        CATransaction.begin()

        if !isVideoRecorder, !recorder.isCancelled, let host = overlayView.superview, let flight = chatInteraction.voiceSendFlight, let parentContent = parent?.contentView {
            moveFloating(overlayView, to: parentContent)
            if flight.launch(overlay: overlayView) {
                overlayHandedOff = true
            } else {
                moveFloating(overlayView, to: host)
            }
        }

        let overlayLayer = overlayView.superview != nil && !overlayHandedOff ? overlayView.layer : nil

        if let overlayLayer {
            overlayLayer.animateScaleSpring(from: 1.0, to: 0.1, duration: duration, removeOnCompletion: false, bounce: false, completion: { _ in
                completion()
            })
            overlayLayer.animateAlpha(from: 1, to: 0, duration: fade, timingFunction: .spring, removeOnCompletion: false)
        }

        let fading: [NSView] = [lockControl, pauseControl, singleTimeControl, deleteButton, scrubber]
        for view in fading where view.superview != nil {
            let from = view.layer?.presentation()?.opacity ?? view.layer?.opacity ?? 1
            guard from > 0 else {
                continue
            }
            view.layer?.animateAlpha(from: CGFloat(from), to: 0, duration: fade, timingFunction: .spring, removeOnCompletion: false)
        }

        layer?.animateAlpha(from: 1, to: 0, duration: fade, timingFunction: .spring, removeOnCompletion: false, completion: { _ in
            if overlayLayer == nil {
                completion()
            }
        })

        CATransaction.commit()
    }

    private func handleDrag() {
        guard let parent else { return }
        let location = parent.mouseLocationOutsideOfEventStream
        let dif = max(0, location.y - startMouseLocation.y)
        let lockThreshold: CGFloat = 110

        if canTranscribe {
            let dx = max(0, startMouseLocation.x - location.x)
            let centerX = convert(NSMakePoint(glassFrameInLayout.midX, 0), to: nil).x
            let threshold = max(80, startMouseLocation.x - centerX)
            let progress = dx > dif ? min(1, dx / threshold) : 0
            if progress >= 1 {
                beginTranscription()
                return
            }
            updateTranscribeProgress(progress)
        }

        overlayView.updateInside()

        if dif > lockThreshold {
            hold()
            return
        }

        lockness = min(1.0, dif / lockThreshold) * (1 - transcribeProgress)
        overlayDragOffset = dif * 0.3

        layoutFloatingControls(transition: .immediate)
        lockControl.updateLockness(lockness)
    }

    private func hold() {
        guard let parent else { return }
        recorder.holdpromise.set(true)

        overlayView.updateInside()

        self.state = .fixed
        overlayView.updateState(.fixed)

        parent.remove(object: self, for: .leftMouseDown)
        parent.remove(object: self, for: .leftMouseUp)
        overlayWindow?.remove(object: self, for: .leftMouseDown)
        overlayWindow?.remove(object: self, for: .leftMouseUp)

        let proccessMouseUp: (NSEvent) -> KeyHandlerResult = { [weak self] _ in
            guard let self else { return .rejected }
            if findModal(InputDataModalController.self) != nil {
                return .rejected
            }
            if self.isMouseOverChatNavigation || self.isMouseOverTranscription {
                return .invokeNext
            }
            if self.singleTimeControl.mouseInside() || self.pauseControl.mouseInside() {
                return .invokeNext
            }
            if self.isPaused, self.deleteButton.mouseInside() || self.scrubber.mouseInside() {
                self.draggingPreview = true
                return .invokeNext
            }
            return self.proccessMouseUp()
        }
        parent.set(mouseHandler: proccessMouseUp, with: self, for: .leftMouseDown, priority: .modal)
        overlayWindow?.set(mouseHandler: proccessMouseUp, with: self, for: .leftMouseDown, priority: .modal)

        let endPreviewDrag: (NSEvent) -> KeyHandlerResult = { [weak self] _ in
            self?.draggingPreview = false
            return .rejected
        }
        parent.set(mouseHandler: endPreviewDrag, with: self, for: .leftMouseUp, priority: .modal)
        overlayWindow?.set(mouseHandler: endPreviewDrag, with: self, for: .leftMouseUp, priority: .modal)

        overlayDragOffset = 0

        layoutFloatingControls(transition: .animated(duration: 0.3, curve: .spring))
    }

    private func updateTranscribeProgress(_ progress: CGFloat) {
        transcribeProgress = progress
        overlayDragOffsetX = progress * 60
        overlayView.updateTranscribeProgress(progress)
        lockControl.layer?.opacity = Float(1 - progress)
        updateDescription(descHold)
        descView.layer?.opacity = Float(progress > 0.15 ? min(1, 0.4 + progress) : 1 - progress * 4)
    }

    private func beginTranscription() {
        guard !isTranscribing, let transcription = chatInteraction.voiceTranscription else {
            return
        }
        isTranscribing = true
        transcribeProgress = 0
        overlayDragOffsetX = 0
        descView.layer?.opacity = 1
        overlayView.setTranscribing(true, animated: true)
        hold()
        updateDescription(true)
        transcription.start()
    }

    private func stopTranscribing() {
        chatInteraction.voiceTranscription?.recordingStopped()
        resetPreviewState()
        recorder.discard(from: chatInteraction, closingOtherModals: true)
    }

    private var isMouseOverTranscription: Bool {
        guard isTranscribing, let parent, let contentView = parent.contentView else {
            return false
        }
        var view = contentView.hitTest(parent.mouseLocationOutsideOfEventStream)
        while let current = view {
            if current is ChatVoiceTranscriptionView {
                return true
            }
            view = current.superview
        }
        return false
    }

    private func moveFloating(_ view: NSView, to newHost: NSView) {
        guard let oldHost = view.superview, oldHost !== newHost, let oldWindow = oldHost.window, let newWindow = newHost.window else {
            return
        }
        let screenRect = oldWindow.convertToScreen(oldHost.convert(view.frame, to: nil))
        let frame = newHost.convert(newWindow.convertFromScreen(screenRect), from: nil)
        view.removeFromSuperview()
        view.frame = frame
        newHost.addSubview(view, positioned: .above, relativeTo: nil)
    }

    private func showPauseTooltip() {
        let control = self.pauseControl
        getAppTooltipLimited(for: .pauseRecording, callback: { value in
            delay(0.35, closure: { [weak control] in
                if let control, control.superview != nil {
                    tooltip(for: control, text: value)
                }
            })
        })
    }

    private var isMouseOverChatNavigation: Bool {
        guard let parent, let contentView = parent.contentView else {
            return false
        }
        var view = contentView.hitTest(parent.mouseLocationOutsideOfEventStream)
        while let current = view {
            if current is ChatNavigationScroller {
                return true
            }
            view = current.superview
        }
        return false
    }

    private func proccessMouseUp() -> KeyHandlerResult {
        if isTranscribing {
            stopTranscribing()
            return .invoked
        }
        if self.overlayView.mouseInside() || (self.isPaused && self.overlayView.isMouseInsideCentre) {
            self.stopAndSend()
            return .invoked
        }
        if self.isPaused, let modal = findModal(VideoRecorderModalController.self), modal.view._mouseInside() {
            self.draggingPreview = true
            return .invokeNext
        }
        self.stopAndCancel()
        return .invoked
    }

    private func togglePause() {
        if isPaused {
            resumeRecording()
        } else {
            recorder.pause()
        }
    }

    private func updatePaused(_ paused: Bool) {
        guard paused != isPaused else {
            return
        }
        isPaused = paused

        recView.isHidden = paused
        timerView.isHidden = paused
        descView.isHidden = paused
        statusImage.isHidden = paused
        deleteButton.isHidden = !paused
        scrubber.isHidden = !paused

        if paused {
            recView.layer?.removeAllAnimations()
            overlayView.updateLevel(0)
            loadPreview()
        } else {
            resetPreviewState()
            startBlinking()
        }
        pauseControl.kind = paused ? .recordMore : .pause
        overlayView.updatePaused(paused)
        layoutFloatingControls(transition: .animated(duration: 0.3, curve: .spring))
        needsLayout = true
    }

    private func loadPreview() {
        guard window != nil, isPaused, !isResuming, !recorder.isPreparingSubmission, !isDismissing, !recorder.isCancelled else { return }
        previewGeneration = UUID()
        let generation = previewGeneration
        let request = MetaDisposable()
        previewDisposable.set(request)
        request.set((recorder.previewData |> take(1) |> deliverOnMainQueue).start(next: { [weak self] preview in
            guard let self, self.previewGeneration == generation else { return }
            self.applyPreview(preview)
        }))
    }

    private func startBlinking() {
        recView.layer?.removeAllAnimations()
        let animate = CABasicAnimation(keyPath: "opacity")
        animate.fromValue = 1.0
        animate.toValue = 0.3
        animate.repeatCount = 10000
        animate.duration = 1.5
        animate.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
        recView.layer?.add(animate, forKey: "opacity")
    }

    private func refreshScrubber() {
        guard let preview else {
            return
        }
        scrubber.update(duration: preview.duration, waveform: preview.waveform, trimRange: trimRange, position: previewPlayer?.position ?? trimRange.lowerBound, isPlaying: previewPlayer?.isPlaying ?? false, isVideo: isVideoRecorder)
    }

    private func applyPreview(_ preview: ChatRecordingPreviewData?) {
        guard isPaused, !isResuming, !recorder.isPreparingSubmission, !isDismissing, !recorder.isCancelled else { return }
        guard let preview, preview.duration.isFinite, preview.duration > 0 else {
            return
        }
        self.preview = preview
        self.trimRange = RecordingTrimState(duration: preview.duration, range: recorder.trimRange).range
        recorder.updateTrimRange(self.trimRange, duration: preview.duration)

        if isVideoRecorder {
            scrubber.setVideo(path: preview.path, placeholder: preview.thumb)
        } else {
            let player = RecordingPreviewPlayer(postbox: chatInteraction.interactionContext.account.postbox, preview: preview, trimRange: trimRange)
            player.onUpdate = { [weak self] in
                self?.refreshScrubber()
            }
            previewPlayer = player
        }

        refreshScrubber()
        needsLayout = true
    }

    private func updateTrim(_ range: Range<Double>, updatedEnd: Bool, applied: Bool) {
        guard !isResuming, !recorder.isPreparingSubmission else { return }
        guard let preview, preview.duration.isFinite, preview.duration > 0 else { return }
        let range = RecordingTrimState(duration: preview.duration, range: range).range
        self.trimRange = range
        recorder.updateTrimRange(range)
        recorder.updatePreviewTrim(range, updatedEnd: updatedEnd, applied: applied)
        if let previewPlayer {
            previewPlayer.updateTrim(range, updatedEnd: updatedEnd, applied: applied)
        } else {
            refreshScrubber()
        }
    }

    private func tearDownPlayback() {
        previewPlayer = nil
        scrubber.setVideo(path: nil, placeholder: nil)
    }

    private func resetPreviewState() {
        previewGeneration = UUID()
        resumeDisposable.set(nil)
        setResuming(false)
        previewDisposable.set(nil)
        tearDownPlayback()
        preview = nil
    }

    private func resumeRecording() {
        guard let parent, preview != nil, isPaused, !isResuming, !recorder.isPreparingSubmission, !isDismissing, !recorder.isCancelled else {
            return
        }
        if recorder.isTrimmed {
            let generation = previewGeneration
            let range = recorder.trimRange
            verifyAlert_button(for: parent, information: strings().chatInputRecordingViewResumeDiscardTrimmed, ok: strings().chatInputRecordingViewResume, cancel: strings().modalCancel, successHandler: { [weak self] _ in
                guard let self, self.previewGeneration == generation, self.recorder.trimRange == range else { return }
                self.resumeAfterConfirm()
            }, cancelHandler: { [weak self] in
            })
        } else {
            resumeAfterConfirm()
        }
    }

    private func resumeAfterConfirm() {
        guard let preview, isPaused, !isResuming, !recorder.isPreparingSubmission, !isDismissing, !recorder.isCancelled else { return }
        previewGeneration = UUID()
        let generation = previewGeneration
        previewDisposable.set(nil)
        setResuming(true)
        tearDownPlayback()
        let request = MetaDisposable()
        resumeDisposable.set(request)
        request.set(recorder.applyTrimAndResume().start(next: { [weak self] success in
            guard let self, self.previewGeneration == generation, !self.isDismissing, !self.recorder.isCancelled else { return }
            if success {
                self.resetPreviewState()
            } else {
                self.setResuming(false)
                self.applyPreview(preview)
                if let parent = self.parent {
                    alert(for: parent, info: strings().unknownError)
                }
            }
        }))
    }

    private func setResuming(_ value: Bool) {
        isResuming = value
        pauseControl.isEnabled = !value && !recorder.isPreparingSubmission
        scrubber.userInteractionEnabled = !value && !recorder.isPreparingSubmission
    }

    private func updateSubmissionState(_ state: ChatRecordingSubmissionState) {
        guard !isDismissing, !recorder.isCancelled else { return }
        switch state {
        case .idle:
            break
        case .preparing:
            previewGeneration = UUID()
            previewDisposable.set(nil)
            tearDownPlayback()
            pauseControl.isEnabled = false
            scrubber.userInteractionEnabled = false
            singleTimeControl.isEnabled = false
        case .failed:
            singleTimeControl.isEnabled = true
            setResuming(false)
            loadPreview()
            if let parent {
                alert(for: parent, info: strings().unknownError)
            }
        }
    }

    private func discardRecording() {
        resetPreviewState()
        recorder.discard(from: chatInteraction, closingOtherModals: true)
    }

    private func stopAndSend() {
        guard !isResuming, !recorder.isPreparingSubmission else { return }
        recorder.isOneTime = singleTimeControl.isSelected
        recorder.send(from: chatInteraction, closingOtherModals: true)
    }

    private func stopAndCancel() {
        guard let parent else { return }
        if state == .fixed {
            verifyAlert_button(for: parent, information: strings().chatRecordingCancel, ok: strings().alertDiscard, cancel: strings().alertNO, successHandler: { [weak self] _ in
                self?.discardRecording()
            }, cancelHandler: { [weak self] in
            })
        } else {
            discardRecording()
        }
    }
}

extension ChatInputRecordingView: ChatInputGlassMorphing {
    func glassMorphSlots(visible: Bool) -> ChatInputGlassSlots? {
        let bar = convert(visible ? visibleFrame(glassEffect) : glassEffect.frame, from: glassEffect.superview)
        let attach: NSRect
        if isPaused, let host = deleteButton.superview {
            attach = convert(visible ? visibleFrame(deleteButton) : deleteButton.frame, from: host)
        } else {
            attach = NSMakeRect(bar.minX, bar.minY, min(bar.width, bar.height), bar.height)
        }
        let voice: NSRect? = didUpdateSendButtonCenter ? NSMakeRect(sendButtonCenter.x - 2, sendButtonCenter.y - 2, 4, 4) : nil
        return ChatInputGlassSlots(attach: attach, text: bar, voice: voice)
    }

    func setMorphGlassHidden(_ hidden: Bool) {
        glassEffect.isHidden = hidden
        deleteButton.setGlassEffectHidden(hidden)
    }
}

final class RecordingTimerView: View {
    private let textView = TextView()
    private let font = NSFont.monospacedDigitSystemFont(ofSize: .text, weight: .regular)
    private var base: Double = 0
    private var baseTimestamp: Double = 0
    private var displayed: Double = 0
    private var text: String = ""
    private var animator: ConstantDisplayLinkAnimator?

    required init(frame frameRect: NSRect = NSZeroRect) {
        super.init(frame: frameRect)
        backgroundColor = .clear
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(duration: TimeInterval, running: Bool) {
        if duration < base {
            displayed = duration
        }
        base = duration
        baseTimestamp = CACurrentMediaTime()

        if running {
            if animator == nil {
                animator = ConstantDisplayLinkAnimator(update: { [weak self] in
                    self?.render()
                })
                animator?.isPaused = false
            }
        } else {
            stop()
        }
        render()
    }

    func stop() {
        animator?.isPaused = true
        animator = nil
    }

    private func render() {
        let elapsed = animator != nil ? max(0, CACurrentMediaTime() - baseTimestamp) : 0
        displayed = max(displayed, base + elapsed)

        let seconds = Int(displayed)
        let centiseconds = Int((displayed - TimeInterval(seconds)) * 100)
        let text = String.durationTransformed(elapsed: seconds) + String(format: ",%02d", centiseconds)
        guard text != self.text else {
            return
        }
        self.text = text

        let layout = TextViewLayout(.initialize(string: text, color: theme.colors.text, font: font), maximumNumberOfLines: 1, alignment: .left)
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
        setFrameSize(textView.frame.size)
        superview?.needsLayout = true
    }

    deinit {
        stop()
    }
}
