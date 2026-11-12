import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import ColorPalette
import GeneralRows
import TelegramCallsCore
import TelegramContext
import TelegramTheme
import CallVideoLayer
import AppAnalytics


public func makeGroupWindow(isStream: Bool) -> Window {
    
    
    let size = isStream ? GroupCallTheme.minFullScreenSize : GroupCallTheme.minSize
    var rect: NSRect = .init(origin: .init(x: 100, y: 100), size: size)
    if let screen = NSScreen.main {
        let x = floorToScreenPixels(System.backingScale, (screen.frame.width - size.width) / 2)
        let y = floorToScreenPixels(System.backingScale, (screen.frame.height - size.height) / 2)
        rect = .init(origin: .init(x: x, y: y), size: size)
    }

    let window = Window(contentRect: rect, styleMask: [.fullSizeContentView, .borderless, .miniaturizable, .closable, .titled, .resizable], backing: .buffered, defer: true)

    window.minSize = isStream ? GroupCallTheme.minFullScreenSize : GroupCallTheme.minSize
    window.name = "GroupCallWindow5"
    window.acceptFirstMouse = false
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.animationBehavior = .alertPanel
    window.isReleasedWhenClosed = false
    window.isMovableByWindowBackground = true
    window.level = .normal
    window.appearance = darkPalette.appearance
    
    window.initSaver()
    
    if window.frame.width < rect.width || window.frame.height < rect.height {
        window.setFrame(rect, display: true)
    }
    
    return window
}

public final class GroupCallWindow {
    
    
    public var navigation: NavigationViewController?
    public var window: Window
    public init(window: Window) {
        self.window = window
        
        window.isOpaque = true
        window.level = .normal
        window.applyChrome(.standard)
    }
        
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
}




public final class GroupCallContext {
    private let controller: GroupCallUIController
    private let navigation: MajorNavigationController

    public let window: GroupCallWindow
    
    
    public let call: PresentationGroupCall
    public let peerMemberContextsManager: PeerChannelMemberCategoriesContextsManager
    private let presentDisposable = MetaDisposable()
    private let removeDisposable = MetaDisposable()
    private var source: CallWindowSource?
    private var presentTransition: CallWindowTransition?
    private let analyticsJoinTime: TimeInterval = Analytics.shared.now
    private var analyticsLeft: Bool = false
    public init(call: PresentationGroupCall, peerMemberContextsManager: PeerChannelMemberCategoriesContextsManager, window: Window) {
        Analytics.shared.send(AnalyticsEvents.groupCallJoin(kind: call.isConference ? .conference : call.isStream ? .liveStream : .voiceChat))
        self.call = call
        self.peerMemberContextsManager = peerMemberContextsManager
        self.window = .init(window: window)
        self.controller = GroupCallUIController(.init(call: call, peerMemberContextsManager: peerMemberContextsManager), size: window.frame.size)
        self.navigation = MajorNavigationController(GroupCallUIController.self, controller, window)
        self.navigation._frameRect = NSMakeRect(0, 0, window.frame.width, window.frame.height)
        self.navigation.alwaysAnimate = true
        self.navigation.cleanupAfterDeinit = true
        self.navigation.viewWillAppear(false)
        
        window.animationBehavior = .none
        let content = self.navigation.view
        if window.isVisible {
            self.attachContent(content)
        }
                        
        self.window.navigation = navigation
        self.navigation.viewDidAppear(false)
        removeDisposable.set((self.call.canBeRemoved |> deliverOnMainQueue).start(next: { [weak self] value in
            if value {
                if let self, !self.analyticsLeft {
                    self.analyticsLeft = true
                    Analytics.shared.send(AnalyticsEvents.groupCallLeave(duration: AnalyticsValues.CallDuration(bucketing: Int(Analytics.shared.now - self.analyticsJoinTime))))
                }
                self?.readyClose(last: value)
            }
        }))

        self.window.window.closeInterceptor = { [weak self] in
            self?.readyClose()
            return true
        }
    }
    
    deinit {
        presentDisposable.dispose()
        removeDisposable.dispose()
    }
    
    public func present(source: CallWindowSource? = nil) {

        presentDisposable.set((self.controller.ready.get() |> take(1)).start(completed: { [weak self] in
            guard let `self` = self else {
                return
            }
            self.readyPresent(source: source)
        }))
    }
    
    private func attachContent(_ newView: NSView) {
        let window = self.window.window
        newView.layer?.cornerRadius = 20
        if #available(macOS 10.15, *) {
            newView.layer?.cornerCurve = .continuous
        }
        newView.alphaValue = 1.0
        newView.frame = window.contentView?.frame ?? .zero
        window.contentView = newView
    }
    
    private func readyClose(last: Bool = false) {
        if window.window.isFullScreen {
            window.window.toggleFullScreen(nil)
            window.window._windowDidExitFullScreen = { [weak self] in
                self?.invikeClose(last: last)
            }
        } else {
            invikeClose(last: last || GroupCallScreenUIHooks.shared.getCrossAccountGroupCall(call.sharedContext) == nil)
        }
        
    }
    private func invikeClose(last: Bool) {
        if last {
            GroupCallScreenUIHooks.shared.updateCurrentGroupCallValue(call.sharedContext, nil)
        }
        closeAllModals(window: window.window)
        self.navigation.viewWillDisappear(false)
        self.presentTransition?.cancel()
        self.presentTransition = nil
        var window: GroupCallWindow? = self.window
        if self.window.window.isVisible {
            CallWindowTransition.dismiss(window: self.window.window, content: self.navigation.view, source: last ? self.source : nil, cornerRadius: 20, completion: {
                if last {
                    window?.window.contentView?.removeFromSuperview()
                    window?.window.contentView = nil
                    window?.navigation = nil
                }
                window = nil
            })
        } else if last {
            window?.window.contentView?.removeFromSuperview()
            window?.window.contentView = nil
            window?.navigation = nil
        }
        self.navigation.viewDidDisappear(false)
    }
    
    public func close() {
        _ = call.sharedContext.endGroupCall(terminate: false).start()
        self.readyClose()
    }
    public func leave() {
        _ = call.sharedContext.endGroupCall(terminate: false).start()
    }
    public func leaveSignal() -> Signal<Bool, NoError> {
        self.controller.disableSounds = true
        return call.sharedContext.endGroupCall(terminate: false)
    }
    
    private func readyPresent(source: CallWindowSource?) {
        GroupCallScreenUIHooks.shared.updateCurrentGroupCallValue(self.call.sharedContext, self)
        if self.presentTransition != nil {
            return
        }
        let window = self.window.window
        let content = self.navigation.view
        if content.window !== window {
            self.source = source
        }
        window.alphaValue = 1
        self.presentTransition = CallWindowTransition.present(window: window, content: content, source: source, cornerRadius: 20, attach: { [weak self] in
            self?.attachContent(content)
        }, completion: { [weak self] in
            self?.presentTransition = nil
        })
    }
    
}


public func applyGroupCallResult(_ sharedContext: any SharedAccountContextProtocol, _ result:GroupCallContext) {
    assertOnMainThread()
    GroupCallScreenUIHooks.shared.showGroupCall(result.call.sharedContext, result)
    result.present(source: CallWindowSource.underCursor())
}
