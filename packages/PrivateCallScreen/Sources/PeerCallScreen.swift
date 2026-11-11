import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit
import CallVideoLayer
import TGUIKit
import MetalEngine
import AppKit
import KeyboardKey
import Localization
import IOKit.pwr_mgt
import AppAnalytics

protocol CallViewUpdater {
    func updateState(_ state: PeerCallState, arguments: Arguments, transition: ContainedViewLayoutTransition)
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition)
}

public final class PeerCallScreen : ViewController {
    private var external: PeerCallArguments
    private let screen: Window
    
    private let actionsDisposable = DisposableSet()
    private let audioLevelDisposable = MetaDisposable()
    private let peerDisposable = MetaDisposable()
    private let stateDisposable = MetaDisposable()
    
    public var onCompletion: (()->Void)? = nil
    
    public var contextObject: Any?
    
    private var videoViewState: PeerCallVideoViewState = .init()
    
    private let isConference: Bool
    private var occlusionObserver: NSObjectProtocol?

    private var transitionSource: CallWindowSource?
    private var presentTransition: CallWindowTransition?
    private var isHostedInTransition: Bool = false
    private var animatesWindow: Bool = false

    
    private let statePromise = ValuePromise<PeerCallState>(ignoreRepeated: true)
    private let stateValue = Atomic<PeerCallState>(value: .init())
    private func updateState(_ f: (PeerCallState) -> PeerCallState) {
        statePromise.set(stateValue.modify (f))
    }
    
    
    public func update(arguments: PeerCallArguments) {
        self.external = arguments
        self.applyArguments()
    }
    
    private func applyArguments() {
        self.updateAudioLevel()
        self.updatePeers()
    }
    
    private func updatePeers() {
        let peer = external.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: external.peerId)) |> deliverOnMainQueue
        let accountPeer = external.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: external.engine.account.peerId)) |> deliverOnMainQueue
        
        peerDisposable.set(combineLatest(peer, accountPeer).start(next: { [weak self] peer, accountPeer in
            self?.updateState { current in
                var current = current
                current.peer = peer
                current.accountPeer = accountPeer
                return current
            }
        }))
    }
    
    
    public init(external: PeerCallArguments, isConference: Bool) {
        self.external = external
        self.isConference = isConference
        let size = isConference ? NSMakeSize(380, 600) : NSMakeSize(720, 560)
        let hostScreen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = hostScreen?.visibleFrame ?? NSMakeRect(0, 0, size.width, size.height)
        self.screen = Window(contentRect: NSMakeRect(floorToScreenPixels(screenFrame.minX + (screenFrame.width - size.width) / 2), floorToScreenPixels(screenFrame.minY + (screenFrame.height - size.height) / 2), size.width, size.height), styleMask: [.fullSizeContentView, .borderless, .resizable, .miniaturizable, .titled, .closable], backing: .buffered, defer: true, screen: hostScreen)
        self.screen.minSize = size
        self.screen.isOpaque = true
        self.screen.backgroundColor = .black
        self.screen.titlebarAppearsTransparent = true
        self.screen.isMovableByWindowBackground = true
        self.screen.isReleasedWhenClosed = false
        super.init()
        actionsDisposable.add(audioLevelDisposable)
        actionsDisposable.add(peerDisposable)
        actionsDisposable.add(stateDisposable)
        self.updateAudioLevel()
    }
    
    private func updateAudioLevel() {
        audioLevelDisposable.set((external.audioLevel() |> deliverOnMainQueue).start(next: { [weak self] level in
            self?.genericView.updateAudioLevel(level)
        }))
    }
    
    public func setState(_ signal: Signal<ExternalPeerCallState, NoError>) {
        stateDisposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] external in
            
            let actions: [PeerCallAction] = peerCallActionSpecs(external).map { spec in
                let callback: () -> Void
                switch spec.type {
                case .video:
                    callback = { self?.external.toggleCamera(external) }
                case .screencast:
                    callback = { self?.external.toggleScreencast(external) }
                case .mute:
                    callback = { self?.external.toggleMute() }
                case .accept:
                    callback = { self?.external.acceptcall() }
                case .redial:
                    callback = { self?.external.recall() }
                case .end:
                    callback = { self?.external.endcall(external) }
                }
                return makeAction(type: spec.type, text: spec.type.title, resource: spec.type.resource, active: spec.active, enabled: spec.enabled, interactive: spec.interactive, attract: spec.attract, action: callback)
            }
            
            self?.updateState { current in
                return peerCallState(current, applying: external, actions: actions)
            }
        }))
    }
    
    public override func viewClass() -> AnyClass {
        return PeerCallScreenView.self
    }
    
    private var genericView: PeerCallScreenView {
        return self.view as! PeerCallScreenView
    }
    
    public override var window: Window? {
        return screen
    }
        
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let updateState: ((PeerCallState) -> PeerCallState) -> Void = { [weak self] f in
            guard let self else {
                return
            }
            self.statePromise.set(self.stateValue.modify (f))
        }
        
        
        let arguments = Arguments(toggleSecretKey: {
            updateState { current in
                var current = current
                if current.secretKey != nil {
                    current.secretKeyViewState = current.secretKeyViewState.rev
                } else {
                    current.secretKeyViewState = .concealed
                }
                return current
            }
        }, makeAvatar: { [weak self] view, peerId in
            return self?.external.makeAvatar(view, peerId)
        }, makeParticipants: { [weak self] view, participants in
            return self?.external.makeParticipants(view, participants) ?? NSView()
        }, openSettings: { [weak self] in
            guard let self else {
                return
            }
            let isClosed = self.stateValue.with { $0.externalState.canBeRemoved == true }
            if !isClosed {
                self.external.openSettings(self.screen)
            }
        }, addMembers: { [weak self] in
            if let window = self?.window as? Window {
                self?.external.upgradeToConference(window)
            }
        })
        
        
        var first: Bool = true
        
        actionsDisposable.add((statePromise.get() |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.applyState(state, arguments: arguments, animated: !first)
            first = false
        }))
        
        struct TooltipTuple : Equatable {
            let lowSignal: Bool
            let lowBattery: Bool
            
            init(_ flags: PeerCallStatusTooltipFlags) {
                self.lowSignal = flags.lowSignal
                self.lowBattery = flags.lowBattery
            }
            
            var isEmpty: Bool {
                return !lowSignal && !lowBattery
            }
            
            func take(_ index: Int, state: PeerCallState) -> String {
                
                if index == 0 {
                    return L10n.callToastWeakNetwork
                }
                if index == 1 {
                    return L10n.callToastLowBattery(state.compactTitle) 
                }
                return ""
            }
            var indexes: [Int] {
                var indexes: [Int] = []
                if lowSignal {
                    indexes.append(0)
                }
                if lowBattery {
                    indexes.append(1)
                }
                return indexes
            }
        }
        
        let statusTooltip: Signal<TooltipTuple, NoError> =  statePromise.get() |> map {
            TooltipTuple(peerCallStatusTooltipFlags($0))
        } |> distinctUntilChanged
        
        
        let recursiveDisposable = MetaDisposable()
        
        actionsDisposable.add(recursiveDisposable)
        
        actionsDisposable.add(statusTooltip.start(next: { tooltip in
            DispatchQueue.main.async {
                if tooltip.isEmpty {
                    updateState { current in
                        var current = current
                        current.statusTooltip = nil
                        return current
                    }
                    recursiveDisposable.set(nil)
                } else {
                    let recursive = Signal<Void, NoError>.single(Void()) |> then(.single(Void()) |> suspendAwareDelay(4, queue: .mainQueue()) |> restart)
                    
                    
                    let indexes: [Int] = tooltip.indexes
                    var index: Int = 0

                    
                    recursiveDisposable.set(recursive.start(next: {
                        updateState { current in
                            var current = current
                            current.statusTooltip = tooltip.take(indexes[index], state: current)
                            return current
                        }
                        
                        index += 1
                        if index == indexes.count {
                            index = 0
                        }
                    }))
                }
                
            }
        }))
        
        self.updatePeers()
        
        let invokeEsc:(NSEvent)->KeyHandlerResult = { [weak self] event in
            guard let self else {
                return .rejected
            }
            let (keyIsShown, hasKey) = self.stateValue.with { ($0.secretKeyViewState == .revealed, $0.secretKey != nil) }
            if keyIsShown {
                arguments.toggleSecretKey()
                return .invoked
            } else if hasKey, event.keyCode == KeyboardKey.Space.rawValue || event.keyCode == KeyboardKey.Return.rawValue {
                arguments.toggleSecretKey()
                return .invoked
            }
            
            
            return .rejected
        }
        
        screen.set(handler: invokeEsc, with: self, for: .Escape)
        screen.set(handler: invokeEsc, with: self, for: .Space)
        screen.set(handler: invokeEsc, with: self, for: .Return)
        
        
        let updateMouse:(NSEvent)->KeyHandlerResult = { [weak self] event in
            guard let self else {
                return .rejected
            }
            let mouseInside = self.stateValue.with { $0.mouseInside }
            let screenLocation = self.screen.convertToScreen(CGRect(origin: event.locationInWindow, size: self.screen.frame.size))
            let updatedMouseInside = NSWindow.windowNumber(at: screenLocation.origin, belowWindowWithWindowNumber: 0) == self.screen.windowNumber
            
            if mouseInside != updatedMouseInside {
                self.updateState({ current in
                    var current = current
                    current.mouseInside = updatedMouseInside
                    return current
                })
            }
            
            return .rejected
        }
        
        screen.set(mouseHandler: updateMouse, with: self, for: .mouseMoved)
        screen.set(mouseHandler: updateMouse, with: self, for: .mouseExited)
        screen.set(mouseHandler: updateMouse, with: self, for: .mouseEntered)
        
        self.occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: screen, queue: .main, using: { [weak self] _ in
            self?.updateWindowVisibility()
        })
        self.updateWindowVisibility()

    }
    
    private var previousState: PeerCallState?
    private var nativeVideoRequests = PeerCallVideoRequests()
    
    private func configureVideoView(_ view: CallVideoView, isIncoming: Bool, arguments: Arguments, animated: Bool) {
        view.videoMetricsDidUpdate = { [weak self] _ in
            guard let self else {
                return
            }
            self.applyState(self.stateValue.with { $0 }, arguments: arguments, animated: animated)
        }
        view.set(handler: { [weak self] _ in
            self?.updateState { current in
                var current = current
                current.smallVideo = isIncoming ? .outgoing : .incoming
                return current
            }
        }, for: .Up)
    }
    
    private func makeVideoView(isIncoming: Bool, arguments: Arguments, animated: Bool) -> CallVideoView? {
        if isMetalVideoRenderingAvailable {
            guard let video = external.video(isIncoming) else {
                return nil
            }
            let view = MetalVideoMakeView(videoSource: video)
            self.configureVideoView(view, isIncoming: isIncoming, arguments: arguments, animated: animated)
            return view
        }
        if let request = self.nativeVideoRequests.begin(isIncoming: isIncoming) {
            external.nativeVideo(isIncoming, { [weak self] view in
                guard let self, self.nativeVideoRequests.complete(isIncoming: isIncoming, token: request) else {
                    return
                }
                guard let view else {
                    return
                }
                self.configureVideoView(view, isIncoming: isIncoming, arguments: arguments, animated: true)
                if isIncoming {
                    self.videoViewState.incomingView = view
                } else {
                    self.videoViewState.outgoingView = view
                }
                self.applyState(self.stateValue.with { $0 }, arguments: arguments, animated: true)
            })
        }
        return nil
    }
    
    private func updateWindowVisibility() {
        if self.isLoaded() {
            self.genericView.setWindowVisible(self.isHostedInTransition || self.screen.occlusionState.contains(.visible))
        }
    }
    
    private func applyState(_ state: PeerCallState, arguments: Arguments, animated: Bool) {
        
        
        var videoViewState: PeerCallVideoViewState = self.videoViewState
        switch state.externalState.remoteVideoState {
        case .active:
            if videoViewState.incomingView == nil {
                videoViewState.incomingView = self.makeVideoView(isIncoming: true, arguments: arguments, animated: animated)
            }
        default:
            videoViewState.incomingView = nil
            self.nativeVideoRequests.cancel(isIncoming: true)
        }
        
        switch state.externalState.videoState {
        case .active:
            if videoViewState.outgoingView == nil {
                videoViewState.outgoingView = self.makeVideoView(isIncoming: false, arguments: arguments, animated: animated)
            }
            if let native = videoViewState.outgoingView as? NativeCallVideoView {
                native.isMirrored = !state.externalState.isScreenCapture
            }
        default:
            videoViewState.outgoingView = nil
            self.nativeVideoRequests.cancel(isIncoming: false)
        }
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .spring) : .immediate
        genericView.updateState(state, videoViewState: videoViewState, arguments: arguments, transition: transition)
        genericView.updateLayout(size: self.frame.size, transition: transition)
        
        if state.externalState.canBeRemoved, self.onCompletion != nil {
            closeAllModals(window: screen)
            let isFullScreen = screen.isFullScreen
            if isFullScreen {
                let window = self.screen
                window._windowDidExitFullScreen = {
                    window.orderOut(nil)
                }
                screen.toggleFullScreen(nil)
            }
            closeAllModals(window: self.screen)
            self.presentTransition?.cancel()
            self.presentTransition = nil
            if !isFullScreen && !self.animatesWindow {
                self.screen.orderOut(nil)
            } else if !isFullScreen {
                self.isHostedInTransition = true
                CallWindowTransition.dismiss(window: self.screen, content: self.view, source: self.transitionSource, cornerRadius: CallWindowTransition.windowCornerRadius)
            }
            _ = self.enableScreenSleep()
            Analytics.shared.screens.hide(ObjectIdentifier(self))

            self.onCompletion?()
            self.onCompletion = nil
        }
        
        self.videoViewState = videoViewState
        self.previousState = state
    }
    
    public func show(source: CallWindowSource? = nil, animated: Bool = false) {
        
        _ = disableScreenSleep()
        
        Analytics.shared.screens.show(ObjectIdentifier(self), screen: isConference ? AnalyticsScreen.callConferenceIncoming : AnalyticsScreen.callActive)
        
        if self.presentTransition != nil {
            return
        }
        
        if view.window !== screen {
            self.animatesWindow = animated
        }
        
        if !self.animatesWindow || view.window === screen {
            if !screen.isOnActiveSpace {
                self.screen.alphaValue = 0
                self.screen.makeKeyAndOrderFront(self)
                self.screen.orderFrontRegardless()
                
                NSAnimationContext.runAnimationGroup({ ctx in
                    self.screen.animator().alphaValue = 1
                }, completionHandler: { })
            } else {
                self.screen.makeKeyAndOrderFront(self)
                self.screen.orderFrontRegardless()
            }
            
            screen.contentView = view
            
            self.genericView.updateLayout(size: screen.frame.size, transition: .immediate)
            return
        }
        
        self.screen.animationBehavior = .none
        self.transitionSource = source
        self.view.frame = NSMakeRect(0, 0, screen.frame.width, screen.frame.height)
        self.genericView.updateLayout(size: screen.frame.size, transition: .immediate)
        self.isHostedInTransition = true
        self.updateWindowVisibility()
        
        self.presentTransition = CallWindowTransition.present(window: screen, content: view, source: source, cornerRadius: CallWindowTransition.windowCornerRadius, attach: { [weak self] in
            guard let self else {
                return
            }
            self.screen.contentView = self.view
            self.genericView.updateLayout(size: self.screen.frame.size, transition: .immediate)
        }, completion: { [weak self] in
            guard let self else {
                return
            }
            self.presentTransition = nil
            self.isHostedInTransition = false
            self.updateWindowVisibility()
        })
    }
    
    
    private var assertionID: IOPMAssertionID = 0
    private var success: IOReturn?
    
    private func disableScreenSleep() -> Bool? {
        guard success == nil else { return nil }
        success = IOPMAssertionCreateWithName( kIOPMAssertionTypeNoDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Phone Call" as CFString,
                                               &assertionID )
        return success == kIOReturnSuccess
    }
    
    private func  enableScreenSleep() -> Bool {
        if success != nil {
            success = IOPMAssertionRelease(assertionID)
            success = nil
            return true
        }
        return false
    }
    
    deinit {
        if let occlusionObserver = self.occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
        actionsDisposable.dispose()
        _ = enableScreenSleep()
    }
}


