import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import TelegramCallsCore
import TelegramTheme
import TelegramUtils


private final class NoStreamView : View {
    private let progressView = InfiniteProgressView(color: GroupCallTheme.customTheme.textColor, lineWidth: 2)
    private var textView: TextView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        progressView.setFrameSize(NSMakeSize(30, 30))
        addSubview(progressView)
        progressView.color = GroupCallTheme.customTheme.textColor
        self.progressView.progress = nil
    }
    
    func update(initialTimestamp: TimeInterval, title: String?, transition: ContainedViewLayoutTransition) {
        self.progressView.viewDidMoveToWindow()
        
        if Date().timeIntervalSince1970 - initialTimestamp > 10 {
            let current: TextView
            var isNew = false
            if let view = self.textView {
                current = view
            } else {
                current = TextView()
                current.isSelectable = false
                current.userInteractionEnabled = false
                self.textView = current
                addSubview(current)
                if transition.isAnimated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                isNew = true
            }
            let layout = TextViewLayout(.initialize(string: title == nil ? strings().voiceChatRTMPError : strings().voiceChatRTMPViewerError(title!), color: GroupCallTheme.customTheme.textColor, font: .normal(.text)), alignment: .center)
            layout.measure(width: frame.width)
            current.update(layout)
            
            if isNew {
                current.center()
            }
            updateLayout(size: frame.size, transition: transition)
        } else if let view = textView {
            performSubviewRemoval(view, animated: transition.isAnimated)
            self.textView = nil
        } else {
            delay(1, closure: { [weak self] in
                self?.update(initialTimestamp: initialTimestamp, title: title, transition: .animated(duration: 0.2, curve: .easeOut))
            })
        }
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        if let textView = textView {
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: frame.height / 2 + 4))
            transition.updateFrame(view: progressView, frame: progressView.centerFrameX(y: frame.height / 2 - progressView.frame.height - 4))
        } else {
            transition.updateFrame(view: progressView, frame: focus(progressView.frame.size))
        }
    }
    
    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public final class GroupCallView : View {
    
    public enum ControlsMode {
        case normal
        case invisible
    }
    
    private var controlsMode: ControlsMode = .normal

    public let peersTable: TableView = TableView(frame: NSMakeRect(0, 0, 340, 329))

    public let titleView: GroupCallTitleView = GroupCallTitleView(frame: NSMakeRect(0, 0, 380, 54))
    private let peersTableContainer: View = View(frame: NSMakeRect(0, 0, 340, 329))
    private var glassTableBackgroundView: LiquidGlassView?
    public let controlsContainer: GroupCallControlsView
    
    private var scheduleView: GroupCallScheduleView?
    public private(set) var tileView: GroupCallTileView?

    private var scrollView = ScrollView()
    
    private var speakingTooltipView: GroupCallSpeakingTooltipView?
    
    private var noStreamView: NoStreamView?
    
    private let backgroundContainerView = View()
    private let liquidGlassBackgroundView: LiquidGlassView
    
    private var secureEmojiView: GroupCallSecureEmojiView?
    private var secureVisualBackgroundView: Control?
    
    private var sendMessageView: GroupCallSendMessageView?
    private var messagesView: GroupCallMessagesView?

    public var arguments: GroupCallUIArguments? {
        didSet {
            controlsContainer.arguments = arguments
        }
    }
    
    private final class Content : View {
        
        var state: GroupCallUIState? {
            didSet {
                needsDisplay = true
            }
        }
        
        override func layout() {
            super.layout()
            needsDisplay = true
        }
        
        override func draw(_ layer: CALayer, in ctx: CGContext) {
            ctx.setFillColor(.clear)
            ctx.fill(bounds)
            var rect: CGRect = .zero
            if let state = self.state {
                switch state.mode {
                case .video:
                    if state.videoActive(.main).isEmpty || !state.isFullScreen {
                        rect = NSMakeRect(0, 54, min(frame.width - 40, 600), frame.height - 180)
                        rect.origin.x = focus(rect.size).minX
                    } else {
                        rect = NSMakeRect(5, 54, frame.width - 10, frame.height - 5 - 54)
                    }
                case .voice:
                    rect = NSMakeRect(0, 54, min(frame.width - 40, 600), frame.height - 271)
                    rect.origin.x = focus(rect.size).minX
                }
                if rect != .zero {
                    let path = CGMutablePath()
                    path.addRoundedRect(in: rect, cornerWidth: 10, cornerHeight: 10)
                    ctx.addPath(path)
                    ctx.clip()
                    ctx.clear(rect)
                }
            }
        }
    }
    
    private let content = Content()
    
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            var bp = 0
            bp += 1
        }
    }
    
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        
        if superview == nil {
            var bp = 0
            bp += 1
        }
    }
    
    public required init(frame frameRect: NSRect, callMode: GroupCallUIState.Mode) {
        controlsContainer = GroupCallControlsView(frame: .init(x: 0, y: 0, width: 360, height: 320), callMode: callMode)
        liquidGlassBackgroundView = LiquidGlassView(frame: frameRect.size.bounds, cornerRadius: 0, hasShadow: true, hasBorder: true, tintAlpha: 0.5, forceAppearance: .forceDark)
        liquidGlassBackgroundView.customTint = TelegramThemeHooks.shared.darkAppearance().colors.listBackground.withAlphaComponent(0.6)
        super.init(frame: frameRect)

        self.addSubview(liquidGlassBackgroundView)
        self.addSubview(backgroundContainerView)

        backgroundContainerView.backgroundColor = GroupCallTheme.windowBackground.withAlphaComponent(0.4)

        addSubview(scrollView)
        
        addSubview(peersTableContainer)

        let tableGlass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 20, hasShadow: false, hasBorder: false, forceAppearance: .forceDark, customTint: GroupCallTheme.membersColor.withAlphaComponent(0.35), forceBlur: true)
        addSubview(tableGlass, positioned: .above, relativeTo: peersTableContainer)
        glassTableBackgroundView = tableGlass

        addSubview(peersTable)

        peersTable.layer?.cornerRadius = 20
        peersTable.clipView.layer?.cornerRadius = 20
        peersTableContainer.layer?.cornerRadius = 20
        
        addSubview(content)

        addSubview(controlsContainer)
        addSubview(titleView)

        content.isEventLess = true
                
        scrollView.clipView._mouseDownCanMoveWindow = true
        scrollView._mouseDownCanMoveWindow = true
        
        scrollView.background = .clear
        scrollView.layer?.cornerRadius = 20
        peersTableContainer.layer?.cornerRadius = 20
        updateLocalizationAndTheme(theme: theme)
        
        peersTable._mouseDownCanMoveWindow = true
        
        peersTable.getBackgroundColor = {
            .clear
        }
        peersTable.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] pos in
            guard let `self` = self else {
                return
            }
            self.peersTableContainer.frame = self.substrateRect()
            self.glassTableBackgroundView?.frame = self.substrateRect()
        }))
        
        
        peersTable.applyExternalScroll = { [weak self] event in
            guard let strongSelf = self, !strongSelf.isFullScreen, let state = strongSelf.state else {
                return false
            }
            
            if state.videoActive(.main).isEmpty {
                return false
            }
            if state.pinnedData.focused != nil || state.pinnedData.permanent != nil {
                return false
            }
            
            let tileHeight = strongSelf.tileView?.frame.height ?? 0
            
            if tileHeight <= 280 {
                return false
            }
            if state.videoActive(.main).count == 1 {
                return false
            }
            if strongSelf.peersTable.documentOffset.y > 0 {
                return false
            }
            if strongSelf.peersTable.listHeight + strongSelf.videoRect.height < strongSelf.frame.height - 180 {
                return false
            }

            
            let local = strongSelf.scrollTempOffset
            
            var scrollTempOffset = local
            

            
            scrollTempOffset += -event.scrollingDeltaY
            
            
            strongSelf.scrollTempOffset = min(max(0, scrollTempOffset), strongSelf.videoRect.height + 5)

            strongSelf.updateLayout(size: strongSelf.frame.size, transition: .immediate)
            
            if strongSelf.tableRect.minY == strongSelf.titleView.frame.maxY {
                return false
            }
            
            return true
        }
        
        scrollView.applyExternalScroll = { [weak self] event in
            
            guard let strongSelf = self, let state = strongSelf.state, let tileView = strongSelf.tileView else {
                return false
            }
            
            if !state.isFullScreen {
                return strongSelf.peersTable.applyExternalScroll?(event) ?? false
            }
            
            let local = strongSelf.scrollTempOffset
            
            var scrollTempOffset = local
            
            scrollTempOffset += -event.scrollingDeltaY
            
            strongSelf.scrollTempOffset = min(max(0, scrollTempOffset), -(strongSelf.frame.height - tileView.frame.height - strongSelf.titleView.frame.height - 5))
            
            strongSelf.updateLayout(size: strongSelf.frame.size, transition: .immediate)

            
            return true
        }

        
        updateLayout(size: frame.size, transition: .immediate)
        
        
//        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: OperationQueue.main, using: { [weak self] notification in
//            let bounds = self?.scrollView.contentView.bounds
//            if bounds?.minY == 0 {
//                var bp = 0
//                bp += 1
//            }
//            NSLog("bounds: \(bounds)")
//        })
    }
    
    private func substrateRect() -> NSRect {
        var isVertical: Bool? = nil
        var offset: CGFloat = 0
        peersTable.enumerateItems(with: { item in
            if let item = item as? GroupCallParticipantRowItem {
                isVertical = item.isVertical
            }
            if isVertical == true {
                offset += item.height
            }
            if let item = item as? GroupCallTileRowItem {
                offset += item.height
            }
            return isVertical == nil || isVertical == true
        })

        var originY = tableRect.origin.y + offset - peersTable.documentOffset.y
        if originY < tableRect.origin.y {
            originY = tableRect.origin.y
        }
        let h = min(max(0, tableRect.maxY - originY), peersTable.listHeight)

        return .init(origin: NSMakePoint(tableRect.origin.x, originY), size: NSMakeSize(self.peersTable.frame.width, h))
    }
    
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        peersTableContainer.backgroundColor = GroupCallTheme.membersColor.withAlphaComponent(0.5)
        titleView.backgroundColor = .clear
    }
    
    public func updateMouse(animated: Bool, isReal: Bool) {
        guard let window = self.window else {
            return
        }
        let location = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        
        var mode: ControlsMode
        let videoView = self.tileView
        if let videoView = videoView {
            if NSPointInRect(location, videoView.frame) && mouseInside() {
                if isReal && window.isKeyWindow {
                    mode = .normal
                } else {
                    mode = self.controlsMode
                }
            } else if self.sendMessageView == nil, !contextMenuOnScreen() {
                mode = .invisible
            } else {
                mode = .normal
            }
        } else {
            mode = .normal
        }
        
        if state?.state.networkState == .connecting {
            mode = .normal
        }
        
        _ = self.controlsMode
        self.controlsMode = mode
        
        controlsContainer.change(opacity: mode == .invisible && isFullScreen && state?.controlsTooltip == nil ? 0 : 1, animated: animated)
        tileView?.updateMode(controlsMode: mode, controlsState: controlsContainer.mode, animated: animated)
        
        self.updateLayout(size: self.frame.size, transition: .animated(duration: 0.2, curve: .easeOut))

    }
    
    public func idleHide() {
        
        guard let window = self.window else {
            return
        }
        let location = window.mouseLocationOutsideOfEventStream
        
        let frame = controlsContainer.convert(controlsContainer.fullscreenBackgroundView.frame, to: nil)

        
        
        let hasVideo = tileView != nil
        let mode: ControlsMode = hasVideo && isFullScreen && !NSPointInRect(location, frame) ? .invisible :.normal
        _ = self.controlsMode
        self.controlsMode = mode
        
        controlsContainer.change(opacity: mode == .invisible && isFullScreen && state?.controlsTooltip == nil ? 0 : 1, animated: true)
        
        
        
        var videosMode: ControlsMode
        if !isFullScreen {
            if NSPointInRect(location, frame) && mouseInside() {
                videosMode = .normal
            } else {
                videosMode = .invisible
            }
        } else {
            videosMode = mode
        }
        
            self.controlsMode = videosMode
        
        tileView?.updateMode(controlsMode: videosMode, controlsState: controlsContainer.mode, animated: true)

    }
    
    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        
        
        let hasVideo = isFullScreen && (self.tileView != nil)
        
        let isVideo = controlsContainer.callMode == .video || controlsContainer.callMode == .voice
        
        transition.updateFrame(view: backgroundContainerView, frame: size.bounds)
        transition.updateFrame(view: liquidGlassBackgroundView, frame: size.bounds)
        liquidGlassBackgroundView.updateLayout(size: size, transition: transition)

        
        peersTableContainer.setFrameSize(NSMakeSize(substrateRect().width, peersTableContainer.frame.height))
        peersTable.setFrameSize(NSMakeSize(tableRect.width, peersTable.frame.height))
        
        transition.updateFrame(view: peersTable, frame: tableRect)

        transition.updateFrame(view: peersTableContainer, frame: substrateRect())
        if let glassTableBackgroundView {
            let frame = substrateRect()
            ContainedViewLayoutTransition.immediate.updateFrame(view: glassTableBackgroundView, frame: frame)
            glassTableBackgroundView.updateLayout(size: frame.size, transition: .immediate)
        }
        if hasVideo {
            if isFullScreen, state?.hideParticipants == true {
                transition.updateFrame(view: controlsContainer, frame: controlsContainer.centerFrameX(y: size.height - controlsContainer.frame.height + 75))
            } else {
                transition.updateFrame(view: controlsContainer, frame: controlsContainer.centerFrameX(y: size.height - controlsContainer.frame.height + 75, addition: -peersTable.frame.width / 2))
            }
        } else {
            if isVideo {
                transition.updateFrame(view: controlsContainer, frame: controlsContainer.centerFrameX(y: size.height - controlsContainer.frame.height + 100))
            } else {
                transition.updateFrame(view: controlsContainer, frame: controlsContainer.centerFrameX(y: size.height - controlsContainer.frame.height + 50))
            }
        }
        
        let titleRect = NSMakeRect(0, 0, frame.width, 54)
        transition.updateFrame(view: titleView, frame: titleRect)
        titleView.updateLayout(size: titleRect.size, transition: transition)
        
        controlsContainer.updateLayout(size: controlsContainer.frame.size, transition: transition)
       
        if let tileView = self.tileView {
            let size = tileView.getSize(videoRect.size)
            var rect = videoRect
            if tileView.superview != self {
                rect = size.bounds
            }
            transition.updateFrame(view: tileView, frame: rect)
            tileView.updateLayout(size: rect.size, transition: transition)
    
        }
        let clipRect = videoRect.size.bounds
        var scrollRect = videoRect
        scrollRect.size.height += 5
        transition.updateFrame(view: scrollView.contentView, frame: clipRect)
        transition.updateFrame(view: scrollView, frame: scrollRect)
        
        transition.updateFrame(view: content, frame: bounds)
        
        
        if let scheduleView = self.scheduleView {
            let rect = tableRect
            transition.updateFrame(view: scheduleView, frame: rect)
            scheduleView.updateLayout(size: rect.size, transition: transition)
        }
        
        if let current = speakingTooltipView {
            let hasTable = isFullScreen && state?.hideParticipants == false
            transition.updateFrame(view: current, frame: current.centerFrameX(y: 60, addition: hasTable ? (-peersTable.frame.width / 2) : 0))
        }
        
        if let view = noStreamView {
            transition.updateFrame(view: view, frame: focus(view.frame.size))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        
        if let view = secureEmojiView {
            // Keep this in step with the same decision in updateUIAfterFullScreenUpdated: the pill sits
            // over the participants table only while that table is actually there. Collapsing it used to
            // park the pill at `size.width + 5` here — following the table off-screen — while the state
            // pass centred it, so it slid to the middle and was then shoved out of view.
            let isOverParticipants: Bool
            if let state = self.state {
                isOverParticipants = isFullScreen && !state.videoActive(.main).isEmpty && !state.hideParticipants
            } else {
                isOverParticipants = false
            }

            if self.state?.showConferenceKey == true {
                transition.updateFrame(view: view, frame: size.bounds.focus(view.frame.size))
            } else if let state = self.state, isOverParticipants {
                let tableX = size.width - GroupCallTheme.tileTableWidth - 5
                let videoY: CGFloat = state.isConference && !isFullScreen ? 94 : 54
                transition.updateFrame(view: view, frame: NSMakeRect(tableX, videoY, view.frame.width, view.frame.height))
            } else {
                transition.updateFrame(view: view, frame: size.bounds.focusX(view.frame.size, y: 52))
            }

            // Centred over the video it is an overlay like the controls, so it follows them: hidden when
            // they auto-hide, back on hover. Anchored to the table (or expanded to the full key) it is
            // part of the chrome and stays put.
            let followsControls = !isOverParticipants && self.state?.showConferenceKey != true
            let isHidden = followsControls && controlsMode == .invisible && isFullScreen && state?.controlsTooltip == nil
            view.change(opacity: isHidden ? 0 : 1, animated: transition.isAnimated)

            view.updateLayout(size: view.frame.size, transition: transition)
        }
        
        if let view = secureVisualBackgroundView {
            transition.updateFrame(view: view, frame: size.bounds)
        }
        
        if let view = sendMessageView {
            transition.updateFrame(view: view, frame: size.bounds)
            view.controlsRect = controlsContainer.frame
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        
        if let view = messagesView {
            transition.updateFrame(view: view, frame: size.bounds)
            var rect = controlsContainer.frame
            if controlsMode == .invisible && self.isFullScreen {
                rect.origin.y = size.height - 130
            }
            view.controlsRect = rect
            view.updateLayout(size: view.frame.size, transition: transition)
        }
    }
    
    
    
    private var tableRect: NSRect {
        var size = peersTable.frame.size
        let width = min(frame.width - 40, 600)
        
        if let state = state {
            if !state.videoActive(.main).isEmpty {
                if isFullScreen {
                    size = NSMakeSize(GroupCallTheme.tileTableWidth, frame.height - 54 - 5)
                } else {
                    var videoHeight = max(160, frame.height - 180 - 200)
                    videoHeight -= (self.scrollTempOffset)
                    size = NSMakeSize(width, frame.height - 180 - max(0, videoHeight) - 5)
                }
            } else {
                switch controlsContainer.callMode {
                case .voice:
                    size = NSMakeSize(width, frame.height - 271)
                case .video:
                    size = NSMakeSize(width, frame.height - 180)
                }
            }
        }
        var rect = focus(size)
        rect.origin.y = 54
        
        if let state = state, !state.videoActive(.main).isEmpty {
            if !isFullScreen {
                rect.origin.y = videoRect.maxY + 5
            } else {
                rect.origin.x = frame.width - size.width - 5
                rect.origin.y = 50
                rect.size.height += 4
                if state.hideParticipants {
                    rect.origin.x = (frame.width + 5)
                }
            }
        }
        
        if let state = state, state.isConference, isFullScreen {
            rect.origin.y += 40
            rect.size.height -= 40
        }

        if let state = state, state.isConference, secureEmojiView != nil, state.videoActive(.main).isEmpty, !isFullScreen {
            let emojiOffset: CGFloat = 40
            rect.origin.y += emojiOffset
            rect.size.height -= emojiOffset
        }

        return rect
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        let prevFullScreen = self.isFullScreen
        super.setFrameSize(newSize)
        
        if prevFullScreen != self.isFullScreen, let state = self.state {
            updateUIAfterFullScreenUpdated(state, reloadTable: false)
        }
    }
    
    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
        
        self.peersTable.beginTableUpdates()
        self.peersTable.layoutSubtreeIfNeeded()
        self.peersTable.endTableUpdates()
    }
    
    public var isFullScreen: Bool {
        if let state = state {
            if state.isStream {
                return true
            }
            return state.isFullScreen
        }
        if frame.width >= GroupCallTheme.fullScreenThreshold {
            return true
        }
        return false
    }
    
    public var videoRect: NSRect {
        var rect: CGRect
        if isFullScreen, let state = state {
            let tableWidth: CGFloat
            tableWidth = (GroupCallTheme.tileTableWidth + 20)
            
            if state.hideParticipants, isFullScreen {
                let width = frame.width - 10
                var height = frame.height - 5 - 54
                if let tileView = tileView {
                    height = tileView.getSize(NSMakeSize(width, height)).height
                }
                rect = CGRect(origin: .init(x: 5, y: 54 - scrollTempOffset), size: .init(width: width, height: height))
            } else {
                let width = frame.width - tableWidth + 5
                var height = frame.height - 5 - 54
                if let tileView = tileView {
                    height = tileView.getSize(NSMakeSize(width, height)).height
                }
                rect = CGRect(origin: .init(x: 5, y: 54 - scrollTempOffset), size: .init(width: width, height: height))
            }
            
        } else {
            let width = min(frame.width - 40, 600)
            
            var height = max(200, frame.height - 180 - 200)
            if let tileView = tileView {
                height = tileView.getSize(NSMakeSize(width, height)).height
            }
            rect = focus(NSMakeSize(width, height))
            rect.origin.y = 54 - scrollTempOffset
        }
        if let state, state.isConference, !isFullScreen {
            rect.origin.y = 94
            rect.size.height -= 40
        }
        return rect
    }
    
    public var state: GroupCallUIState?
    
    public var markWasScheduled: Bool? = false
    
    private var _scrollTempOffset: CGFloat = 0
    private var scrollTempOffset: CGFloat {
        get {
            if let state = state {
                if state.pinnedData.isEmpty {
                    return 0
                } else {
                    return _scrollTempOffset
                }
            }
            return 0
        }
        set {
            _scrollTempOffset = newValue
        }
    }
    
    public func applyUpdates(_ state: GroupCallUIState, _ tableTransition: TableUpdateTransition, _ call: PresentationGroupCall, animated: Bool) {
                
        let duration: Double = 0.3
        
        let previousState = self.state
        
        if previousState?.isFullScreen != state.isFullScreen {
            self.scrollTempOffset = 0
        }
        
        if let previousState = previousState {
            if let markWasScheduled = self.markWasScheduled, !state.state.canManageCall {
                if !markWasScheduled {
                    self.markWasScheduled = previousState.state.scheduleState != nil && state.state.scheduleState == nil
                }
                if self.markWasScheduled == true {
                    switch state.state.networkState {
                    case .connecting:
                        return
                    default:
                        self.markWasScheduled = nil
                    }
                }
               
            }
        }
        self.state = state
        titleView.update(state.peer, state, call.account, recordClick: { [weak self, weak state] in
            if let state = state {
                self?.arguments?.recordClick(state.state)
            }
        }, resizeClick: { [weak self] in
            self?.arguments?.toggleScreenMode()
        }, hidePeersClick: { [weak self] in
            self?.arguments?.togglePeersHidden()
        }, settingsClick: { [weak self] in
            self?.arguments?.settings()
        } , animated: animated)
        controlsContainer.update(state, voiceSettings: state.voiceSettings, audioLevel: nil, animated: animated)
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: duration, curve: state.showConferenceKey != previousState?.showConferenceKey ? .spring : .easeOut) : .immediate
        
        if let _ = state.state.scheduleTimestamp {
            let current: GroupCallScheduleView
            if let view = self.scheduleView {
                current = view
            } else {
                current = GroupCallScheduleView(frame: tableRect)
                self.scheduleView = current
                addSubview(current)
            }
        } else {
            if let view = self.scheduleView {
                self.scheduleView = nil
                if animated {
                    view.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak view] _ in
                        view?.removeFromSuperview()
                    })
                    view.layer?.animateScaleSpring(from: 1, to: 0.1, duration: 0.3)
                } else {
                    view.removeFromSuperview()
                }
            }
        }
        scheduleView?.update(state, arguments: arguments, animated: animated)

        if animated {
            let from: CGFloat = state.state.scheduleTimestamp != nil ? 1 : 0
            let to: CGFloat = state.state.scheduleTimestamp != nil ? 0 : 1
            if previousState?.state.scheduleTimestamp != state.state.scheduleTimestamp {
                let remove: Bool = state.state.scheduleTimestamp != nil
                if !remove {
                    self.addSubview(peersTableContainer, positioned: .below, relativeTo: content)
                    if let glassTableBackgroundView {
                        self.addSubview(glassTableBackgroundView, positioned: .above, relativeTo: peersTableContainer)
                    }
                    self.addSubview(peersTable, positioned: .below, relativeTo: content)
                }
                self.peersTable.layer?.animateAlpha(from: from, to: to, duration: duration, removeOnCompletion: false, completion: { [weak self] _ in
                    if remove {
                        self?.peersTable.removeFromSuperview()
                        self?.glassTableBackgroundView?.removeFromSuperview()
                        self?.peersTableContainer.removeFromSuperview()
                    }
                })
            }
        } else {
            if state.state.scheduleState != nil {
                peersTable.removeFromSuperview()
                glassTableBackgroundView?.removeFromSuperview()
                peersTableContainer.removeFromSuperview()
            } else if peersTable.superview == nil {
                addSubview(peersTableContainer, positioned: .below, relativeTo: content)
                if let glassTableBackgroundView {
                    addSubview(glassTableBackgroundView, positioned: .above, relativeTo: peersTableContainer)
                }
                addSubview(peersTable, positioned: .below, relativeTo: content)
            }
        }
        
        if !state.videoActive(.main).isEmpty {
            let current: GroupCallTileView
            if let tileView = self.tileView {
                current = tileView
            } else {
                current = GroupCallTileView(call: call, arguments: arguments, frame: videoRect.size.bounds)
                self.tileView = current
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: duration)
                }
            }
            
            let _ = current.update(state: state, context: call.accountContext, transition: transition, size: videoRect.size, animated: animated, controlsMode: self.controlsMode)
                        
            self.addSubview(current, positioned: .below, relativeTo: content)
        } else {
            if let tileView = self.tileView {
                self.tileView = nil
                if animated {
                    tileView.layer?.animateAlpha(from: 1, to: 0, duration: duration, removeOnCompletion: false, completion: { [weak tileView] _ in
                        tileView?.removeFromSuperview()
                    })
                } else {
                    tileView.removeFromSuperview()
                }
            }
        }
        scrollView.isHidden = self.tileView == nil

        
        
        if previousState?.tooltipSpeaker != state.tooltipSpeaker {
            
            if let current = self.speakingTooltipView {
                self.speakingTooltipView = nil
                if animated {
                    current.layer?.animateAlpha(from: 1, to: 0, duration: duration, removeOnCompletion: false, completion: { [weak current] _ in
                        current?.removeFromSuperview()
                    })
                    current.layer?.animatePosition(from: current.frame.origin, to: current.frame.origin - NSMakePoint(0, 10), removeOnCompletion: false)
                } else {
                    current.removeFromSuperview()
                }
            }
            if let tooltipSpeaker = state.tooltipSpeaker {
                let current: GroupCallSpeakingTooltipView
                var presented = false
                if let speakingTooltipView = self.speakingTooltipView {
                    current = speakingTooltipView
                } else {
                    current = GroupCallSpeakingTooltipView(frame: .zero)
                    self.speakingTooltipView = current
                    addSubview(current)
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: duration)
                    }
                    presented = true
                    
                    current.set(handler: { [weak self] _ in
                        if tooltipSpeaker.hasVideo {
                            self?.arguments?.focusVideo(tooltipSpeaker.videoEndpoint ?? tooltipSpeaker.presentationEndpoint)
                        }
                    }, for: .Click)
                }
                current.setPeer(data: tooltipSpeaker, account: call.account, audioLevel: arguments?.audioLevel ?? { _ in return nil })
                
                if presented {
                    let hasTable = isFullScreen && state.hideParticipants == false
                    current.setFrameOrigin(current.centerFrameX(y: 60, addition: hasTable ? (-peersTable.frame.width / 2) : 0).origin)
                    if animated {
                        current.layer?.animatePosition(from: current.frame.origin - NSMakePoint(0, 10), to: current.frame.origin)
                    }
                }
            }
        }
        
        if state.state.scheduleState == nil, state.isStream, state.videoActive(.main).isEmpty, let peer = state.peer {
            let current: NoStreamView
            if let view = self.noStreamView {
                current = view
            } else {
                current = NoStreamView(frame: focus(NSMakeSize(300, 300)))
                self.noStreamView = current
                addSubview(current)
            }
            current.update(initialTimestamp: state.initialTimestamp, title: !peer.groupAccess.isCreator ? peer.displayTitle : nil, transition: transition)
        } else if let view = noStreamView {
            performSubviewRemoval(view, animated: animated)
            self.noStreamView = nil
        }
        
        if state.isConference, state.showConferenceKey {
            let current: Control
            let isNew: Bool
            if let view = self.secureVisualBackgroundView {
                current = view
                isNew = false
            } else {
                current = Control(frame: .zero)
                current.setAccessibilityLabel(strings().voiceOverCommonHide)
                self.secureVisualBackgroundView = current
                addSubview(current, positioned: .below, relativeTo: self.secureEmojiView)
                isNew = true
            }
            
            current.backgroundColor = NSColor.black.withAlphaComponent(0.8)
            
            current.setSingle(handler: { [weak self] _ in
                self?.arguments?.toggleShowConferenceKey(false)
            }, for: .Click)
            
            if isNew {
                current.frame = bounds
            }
            transition.updateFrame(view: current, frame: self.bounds)
            if isNew {
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
        } else if let view = self.secureVisualBackgroundView {
            performSubviewRemoval(view, animated: animated)
            self.secureVisualBackgroundView = nil
        }
        
        if state.isConference {
            let current: GroupCallSecureEmojiView
            let isNew: Bool
            if let view = self.secureEmojiView {
                current = view
                isNew = false
            } else {
                current = GroupCallSecureEmojiView(frame: .zero)
                self.secureEmojiView = current
                addSubview(current)
                isNew = true
            }
            let fullScreenWithVideo = isFullScreen && !state.videoActive(.main).isEmpty && !state.hideParticipants
            let size = current.update(state, encryptionKeyEmoji: state.encryptionKeyEmoji, call.account, isFullScreen: fullScreenWithVideo, toggle: { [weak self] in
                self?.arguments?.toggleShowConferenceKey(!state.showConferenceKey)
            }, transition: isNew ? .immediate : transition)

            let secureFrame: NSRect
            if state.showConferenceKey {
                secureFrame = self.bounds.focus(size)
            } else if fullScreenWithVideo {
                let tableX = self.frame.width - GroupCallTheme.tileTableWidth - 5
                let videoY: CGFloat = state.isConference && !state.isFullScreen ? 94 : 54
                secureFrame = NSMakeRect(tableX, videoY, size.width, size.height)
            } else {
                secureFrame = self.bounds.focusX(size, y: 52)
            }

            if isNew {
                current.setFrameSize(size)
                current.frame = secureFrame
            }
            let transition = isNew ? ContainedViewLayoutTransition.immediate : transition
            transition.updateFrame(view: current, frame: secureFrame)
            
            if isNew {
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
                }
            }
        } else if let view = self.secureEmojiView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.secureEmojiView = nil
        }
        
       
        if state.messages.input, let arguments {
            let current: GroupCallSendMessageView
            let isNew: Bool
            if let view = self.sendMessageView {
                current = view
                isNew = false
            } else {
                current = GroupCallSendMessageView(frame: frame.size.bounds, controlsRect: controlsContainer.frame)
                self.sendMessageView = current
                addSubview(current)
                isNew = true
            }
            current.update(state: state.messages, arguments: arguments, animated: animated)
            
            if isNew, animated {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                current.textContainer.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)

            }
        } else if let view = sendMessageView {
            performSubviewRemoval(view, animated: animated)
            view.textContainer.layer?.animateScaleSpring(from: 1, to: 0.1, duration: 0.2)
            self.sendMessageView = nil
        }
        
        if !state.messages.messages.isEmpty, let arguments {
            let current: GroupCallMessagesView
            let isNew: Bool
            if let view = self.messagesView {
                current = view
                isNew = false
            } else {
                var rect = controlsContainer.frame
                if controlsMode == .invisible && self.isFullScreen {
                    rect.origin.y = frame.height - 130
                }
                current = GroupCallMessagesView(frame: frame.size.bounds, controlsRect: rect)
                self.messagesView = current
                addSubview(current, positioned: .below, relativeTo: controlsContainer)
                isNew = true
            }
            current.update(state: state.messages, callState: state, arguments: arguments, animated: animated)
            
            if isNew, animated {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        } else if let view = messagesView {
            performSubviewRemoval(view, animated: animated)
            self.messagesView = nil
        }
        
        content.state = state

        CATransaction.begin()
        if !tableTransition.isEmpty {
            peersTable.merge(with: tableTransition)
        }
        CATransaction.commit()
        
        updateLayout(size: frame.size, transition: transition)
        updateUIAfterFullScreenUpdated(state, reloadTable: false)

    }
    
    public var isVertical: Bool {
        return isFullScreen && state?.dominantSpeaker != nil
    }
    
    private func updateUIAfterFullScreenUpdated(_ state: GroupCallUIState, reloadTable: Bool) {
        
        peersTable.layer?.cornerRadius = isVertical ? 0 : 20
                
        updateMouse(animated: false, isReal: false)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public var firstResponder: NSResponder? {
        return self.sendMessageView?.firstResponder
    }
}
