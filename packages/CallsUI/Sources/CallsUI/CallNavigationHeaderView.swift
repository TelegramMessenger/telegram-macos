import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore

import Postbox
import TelegramCallsCore
import TelegramTheme
import TelegramIconsTheme
import Localization
import TelegramUtils
import TelegramContext
import ColorPalette
import InAppSettings


private let blue = NSColor(rgb: 0x0078ff)
private let lightBlue = NSColor(rgb: 0x59c7f8)
private let green = NSColor(rgb: 0x33c659)

private let purple =  NSColor(rgb: 0x766EE9)
private let lightPurple =  NSColor(rgb: 0xF05459)


public class CallStatusBarBackgroundView: View, CallStatusBarBackground {
    private let wavesView: CallStatusBarWavesView
    public var audioLevel: Float = 0.0  {
        didSet {
            self.wavesView.updateAudioLevel(CGFloat(audioLevel))
        }
    }

    public var isFlat: Bool {
        get {
            return self.wavesView.isFlat
        }
        set {
            self.wavesView.isFlat = newValue
        }
    }

    public var speaking:(Bool, Bool, Bool)? = nil {
        didSet {
            if let speaking = self.speaking, (speaking.0 != oldValue?.0 || speaking.1 != oldValue?.1 || speaking.2 != oldValue?.2) {
                self.wavesView.updateColors(self.targetColors(theme: theme), animated: true)
            }
        }
    }

    private func targetColors(theme: TelegramPresentationTheme) -> (NSColor, NSColor) {
        if let speaking = self.speaking, speaking.1 {
            if speaking.2 {
                if speaking.0 {
                    return (green, blue)
                } else {
                    return (blue, lightBlue)
                }
            } else {
                return (purple, lightPurple)
            }
        } else {
            return (theme.colors.grayIcon, theme.colors.grayIcon.lighter())
        }
    }

    public override init() {
        self.wavesView = CallStatusBarWavesView()

        super.init()

        self.layer?.masksToBounds = false
        self.addSubview(self.wavesView)

        self.wavesView.isDarkAppearance = theme.colors.isDark
        self.wavesView.updateColors(self.targetColors(theme: theme), animated: false)

        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivityChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivityChanged), name: NSApplication.didResignActiveNotification, object: nil)

        self.updateAnimations()

    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }


    public override func layout() {
        super.layout()

        let wavesFrame = NSMakeRect(0, 0, frame.width, frame.height + CallStatusBarWavesView.bottomOverflow)
        if self.wavesView.frame != wavesFrame {
            self.wavesView.frame = wavesFrame
            self.wavesView.update(barHeight: frame.height)
        }
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        self.wavesView.isDarkAppearance = theme.colors.isDark
        self.wavesView.updateColors(self.targetColors(theme: theme), animated: true)
    }

    private let occlusionDisposable = MetaDisposable()
    private var isCurrentlyInHierarchy: Bool = false {
        didSet {
            updateAnimations()
        }
    }
    
    deinit {
        occlusionDisposable.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationActivityChanged() {
        updateAnimations()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window as? Window {
            occlusionDisposable.set(window.takeOcclusionState.start(next: { [weak self] value in
                self?.isCurrentlyInHierarchy = value.contains(.visible)
            }))
        } else {
            occlusionDisposable.set(nil)
            isCurrentlyInHierarchy = false
        }
    }

    public func updateAnimations() {
        self.wavesView.isAnimating = isCurrentlyInHierarchy && NSApp.isActive
    }
}


public protocol CallStatusBarBackground : View {
    var audioLevel: Float { get set }
    var speaking:(Bool, Bool, Bool)? { get set }
    var isFlat: Bool { get set }
}


open class CallHeaderBasicView : NavigationHeaderView {


    private let _backgroundView: CallStatusBarBackground

    public var backgroundView: CallStatusBarBackground {
        return _backgroundView
    }

    private let container = View()

    fileprivate let callInfo:TextButton = TextButton()
    fileprivate let endCall:ImageButton = ImageButton()
    fileprivate let statusTextView:TextView = TextView()
    fileprivate let muteControl:ImageButton = ImageButton()
    public let disposable = MetaDisposable()
    public let hideDisposable = MetaDisposable()


    open override func hide(_ animated: Bool) {
        super.hide(true)
        disposable.set(nil)
        hideDisposable.set(nil)
    }
    
    private var statusTimer: SwiftSignalKit.Timer?
    private var lastStatusText: String?

    
    public var status: CallControllerStatusValue = .text("", nil) {
        didSet {
            if self.status != oldValue {
                self.statusTimer?.invalidate()
                
                if self.status.hasTimer == true {
                    self.statusTimer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
                        self?.updateStatus()
                    }, queue: Queue.mainQueue())
                    self.statusTimer?.start()
                    self.updateStatus()
                } else {
                    self.updateStatus()
                }
            }
        }
    }
    
    private func updateStatus(animated: Bool = true) {
        var statusText: String = ""
        switch self.status {
        case let .text(text, _):
            statusText = text
        case let .timer(referenceTime, _):
            let duration = Int32(CFAbsoluteTimeGetCurrent() - referenceTime)
            let durationString: String
            if duration > 60 * 60 {
                durationString = String(format: "%02d:%02d:%02d", arguments: [duration / 3600, (duration / 60) % 60, duration % 60])
            } else {
                durationString = String(format: "%02d:%02d", arguments: [(duration / 60) % 60, duration % 60])
            }
            statusText = durationString
        case let .startsIn(time):
            statusText = strings().chatHeaderVoiceChatStartsIn(timerText(time - Int(Date().timeIntervalSince1970)))
        }
        guard statusText != lastStatusText else {
            return
        }
        lastStatusText = statusText
        let layout = TextViewLayout.init(.initialize(string: statusText, color: .white, font: .normal(13)))
        layout.measure(width: .greatestFiniteMagnitude)
        self.statusTextView.update(layout)
        needsLayout = true
    }
    
    deinit {
        disposable.dispose()
        hideDisposable.dispose()
    }
    
    public override init(_ header: NavigationHeader) {
        self._backgroundView = CallStatusBarBackgroundView()
        super.init(header)

        backgroundView.wantsLayer = true
        addSubview(backgroundView)
        addSubview(container)
        statusTextView.backgroundColor = .clear
        statusTextView.userInteractionEnabled = false
        statusTextView.isSelectable = false

        callInfo.set(font: .medium(.text), for: .Normal)
        callInfo.disableActions()
        container.addSubview(callInfo)
        callInfo.userInteractionEnabled = false
        
        endCall.disableActions()
        endCall.setAccessibilityLabel(strings().voiceOverCommonEndCall)
        muteControl.setAccessibilityLabel(strings().voiceOverCommonMute)
        container.addSubview(endCall)
        
        endCall.scaleOnClick = true
        muteControl.scaleOnClick = true

        container.addSubview(statusTextView)

        callInfo.set(handler: { [weak self] _ in
            self?.showInfoWindow()
        }, for: .Click)
        
    
        endCall.set(handler: { [weak self] _ in
            self?.hangUp()
        }, for: .Click)
        
        
        muteControl.autohighlight = false
        container.addSubview(muteControl)
        
        muteControl.set(handler: { [weak self] _ in
            self?.toggleMute()
        }, for: .Click)
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    open func toggleMute() {
        
    }
    open func showInfoWindow() {
        
    }
    open func hangUp() {
        
    }

    public func setInfo(_ text: String) {
        self.callInfo.set(text: text, for: .Normal)
    }
    public func setMicroIcon(_ image: CGImage, isMuted: Bool? = nil) {
        if let isMuted {
            muteControl.setAccessibilityLabel(isMuted ? strings().voiceOverCommonUnmute : strings().voiceOverCommonMute)
        }
        muteControl.set(image: image, for: .Normal)
        _ = muteControl.sizeToFit()
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        let point = self.convert(event.locationInWindow, from: nil)
        if let header = header, point.y <= header.height {
            showInfoWindow()
        }
    }
    
    open var blueColor:NSColor {
        return theme.colors.accentSelect
    }
    open var grayColor:NSColor {
        return theme.colors.grayText
    }

    open func getEndText() -> String {
        return strings().callHeaderEndCall
    }
    
    public override func layout() {
        super.layout()

        let edgeInset: CGFloat = System.windowEdgeInset
        let hInset: CGFloat = edgeInset
        let topInset: CGFloat = edgeInset
        let contentHeight: CGFloat = 35
        let contentRect = NSMakeRect(hInset, topInset, frame.width - hInset * 2, contentHeight)
        backgroundView.frame = NSMakeRect(hInset, topInset, frame.width - hInset * 2, bounds.height - 10)
        container.frame = contentRect
        container.layer?.cornerRadius = contentHeight / 2
        container.layer?.masksToBounds = true
        muteControl.centerY(x:10)
        statusTextView.centerY(x: muteControl.frame.maxX + 6)
        endCall.centerY(x: frame.width - endCall.frame.width - 20 - 12)
        _ = callInfo.sizeToFit(NSZeroSize, NSMakeSize(frame.width - statusTextView.frame.width - 60 - 20 - endCall.frame.width - 10, callInfo.frame.height), thatFit: false)
        
        let rect = container.focus(callInfo.frame.size)
        callInfo.setFrameOrigin(NSMakePoint(max(statusTextView.frame.maxX + 10, min(rect.minX, endCall.frame.minX - 10 - callInfo.frame.width)), rect.minY))
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        self.backgroundColor = .clear
        endCall.set(image: theme.icons.callInlineDecline, for: .Normal)
        endCall.set(image: theme.icons.callInlineDecline, for: .Highlight)
        _ = endCall.sizeToFit(NSMakeSize(10, 10), thatFit: false)
        callInfo.set(color: .white, for: .Normal)

        needsLayout = true

    }
    
}

public class CallNavigationHeaderView: CallHeaderBasicView {
    
    public var session: PCallSession? {
        get {
            self.header?.contextObject as? PCallSession
        }
    }
    private let audioLevelDisposable = MetaDisposable()

    deinit {
        audioLevelDisposable.dispose()
    }
    
    fileprivate weak var accountPeer: Peer?
    fileprivate var state: CallState?

    public override func showInfoWindow() {
        if let session = self.session {
            showCallWindow(session)
        }
    }
    public override func hangUp() {
        self.session?.hangUpCurrentCall()
    }
    
    public override func toggleMute() {
        session?.toggleMute()
    }
    
    public override func update(with contextObject: Any) {
        super.update(with: contextObject)
        let session = contextObject as! PCallSession
        let account = session.account
        backgroundView.isFlat = session.sharedContext.isLite(.blur)
        let signal = Signal<Peer?, NoError>.single(session.peer) |> then(session.account.postbox.loadedPeerWithId(session.peerId) |> map(Optional.init) |> deliverOnMainQueue)

        let accountPeer: Signal<Peer?, NoError> =  session.sharedContext.activeAccounts |> mapToSignal { accounts in
            if accounts.accounts.count == 1 {
                return .single(nil)
            } else {
                return account.postbox.loadedPeerWithId(account.peerId) |> map(Optional.init)
            }
        }

        disposable.set(combineLatest(queue: .mainQueue(), session.state, signal, accountPeer).start(next: { [weak self] state, peer, accountPeer in
            if let peer = peer {
                self?.setInfo(peer.displayTitle)
            }
            self?.updateState(state, accountPeer: accountPeer, animated: false)
            self?.needsLayout = true
            self?.ready.set(.single(true))
        }))
        
        audioLevelDisposable.set((session.audioLevel |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.backgroundView.audioLevel = value
        }))

        hideDisposable.set((session.canBeRemoved |> deliverOnMainQueue).start(next: { [weak self] value in
            if value {
                self?.hide(true)
            }
        }))
    }
    
    private func updateState(_ state:CallState, accountPeer: Peer?, animated: Bool) {
        self.state = state
        self.status = state.state.statusText(accountPeer, state.videoState)
        var isConnected: Bool = false
        let isMuted = state.isMuted
        switch state.state {
        case .active:
            isConnected = true
        default:
            isConnected = false
        }
        self.backgroundView.speaking = (isConnected && !isMuted, isConnected, true)
        if animated {
            backgroundView.layer?.animateBackground()
        }
        setMicroIcon(!state.isMuted ? theme.icons.callInlineUnmuted : theme.icons.callInlineMuted, isMuted: state.isMuted)
        needsLayout = true
        
        switch state.state {
        case let .terminated(_, reason, _):
            if let reason = reason, reason.recall {
                
            } else {
                muteControl.removeAllHandlers()
                endCall.removeAllHandlers()
                callInfo.removeAllHandlers()
                muteControl.change(opacity: 0.8, animated: animated)
                endCall.change(opacity: 0.8, animated: animated)
                statusTextView._change(opacity: 0.8, animated: animated)
                callInfo._change(opacity: 0.8, animated: animated)
            }
        default:
            break
        }
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        if let state = state {
            self.updateState(state, accountPeer: accountPeer, animated: false)
        }
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override init(_ header: NavigationHeader) {
        super.init(header)
    }
    
    public override func hide(_ animated: Bool) {
        super.hide(animated)
    }
    
}

