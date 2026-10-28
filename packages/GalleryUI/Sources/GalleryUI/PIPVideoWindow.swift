import Cocoa
import TGUIKit
import AVKit
import SwiftSignalKit
import TelegramMedia
import Postbox
import TelegramCore
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

 public enum PictureInPictureControlMode {
    case normal
    case pip
}

public protocol PictureInPictureControl {
    func pause()
    func play()
    func didEnter()
    func didExit()
    func isPlaying() -> Bool
    var view: NSView { get }
    var isPictureInPicture: Bool { get }
    
    func setMode(_ mode: PictureInPictureControlMode, animated: Bool)
}


private class PictureInpictureView : Control {
    private weak var __window: Window?
    public init(frame: NSRect, window: Window) {
        __window = window
        super.init(frame: frame)
        autoresizesSubviews = true
    }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseEntered(with: event)
    }
    
    public required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override var window: NSWindow? {
        set {

        }
        get {
            return __window
        }
    }
}

fileprivate class ModernPictureInPictureVideoWindow: NSPanel {
    private let saver: WindowSaver
    fileprivate let __window: Window
    fileprivate let control: PictureInPictureControl
    private var rect:NSRect
    private let restoreRect: NSRect
    private var isQuarterTurn: Bool = false
    private let rotateDisposable = MetaDisposable()
    fileprivate var forcePaused: Bool = false
    fileprivate let item: MGalleryItem
    fileprivate weak var _delegate: InteractionContentViewProtocol?
    fileprivate let _contentInteractions:(any GalleryContentInteractions)?
    fileprivate let _type: GalleryAppearType
    fileprivate let viewer: GalleryViewer
    fileprivate var eventLocalMonitor: Any?
    fileprivate var eventGlobalMonitor: Any?
    private var hideAnimated: Bool = true
    private let lookAtMessageDisposable = MetaDisposable()
    public init(_ control: PictureInPictureControl, item: MGalleryItem, viewer: GalleryViewer, origin:NSPoint, delegate:InteractionContentViewProtocol? = nil, contentInteractions:(any GalleryContentInteractions)? = nil, type: GalleryAppearType) {
        self.viewer = viewer
        self._delegate = delegate
        self._contentInteractions = contentInteractions
        self._type = type
        self.control = control
        let minSize = control.view.frame.size.aspectFilled(NSMakeSize(120, 120))
        let size = item.notFittedSize.aspectFilled(NSMakeSize(250, 250)).aspectFilled(minSize)
        let newRect = NSMakeRect(origin.x, origin.y, size.width, size.height)
        self.rect = newRect
        self.restoreRect = NSMakeRect(origin.x, origin.y, control.view.frame.width, control.view.frame.height)
        self.item = item
        __window = Window(contentRect: newRect, styleMask: [.resizable], backing: .buffered, defer: true)
        __window.name = "pip"
        self.saver = .find(for: __window)
        __window.setFrame(NSMakeRect(3000, 3000, saver.rect.width, saver.rect.height), display: true)
        super.init(contentRect: newRect, styleMask: [.resizable, .nonactivatingPanel], backing: .buffered, defer: true)

        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary];

        
        
        let view = PictureInpictureView(frame: bounds, window: __window)
        self.contentView = view
        
        view.forceMouseDownCanMoveWindow = true
        
        self.contentView?.layer?.cornerRadius = 4;

        self.backgroundColor = .clear;
        control.view.frame = NSMakeRect(0, 0, newRect.width, newRect.height)
        

        control.view.setFrameOrigin(0, 0)
        contentView?.addSubview(control.view)
        
        
        __window.set(mouseHandler: { event -> KeyHandlerResult in
            NSCursor.arrow.set()
            return .invoked
        }, with: self, for: .mouseMoved, priority: .low)
        
        __window.set(mouseHandler: { event -> KeyHandlerResult in
            NSCursor.arrow.set()
            return .invoked
        }, with: self, for: .mouseEntered, priority: .low)
        
        __window.set(mouseHandler: { event -> KeyHandlerResult in
            return .invoked
        }, with: self, for: .mouseExited, priority: .low)
        
        
        __window.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
            if event.clickCount == 2, let strongSelf = self {
                let inner = strongSelf.control.view.convert(event.locationInWindow, from: nil)                
                if NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == strongSelf.windowNumber, strongSelf.control.view.hitTest(inner) is MediaPlayerView {
                    strongSelf.hide()
                }
            }
            return .invoked
        }, with: self, for: .leftMouseDown, priority: .low)
        
        
        __window.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
            self?.findAndMoveToCorner()
            return .rejected
        }, with: self, for: .leftMouseUp, priority: .low)
        
        
        self.level = .modalPanel
        self.isMovableByWindowBackground = true

        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResized(_:)), name: NSWindow.didResizeNotification, object: self)

        
        
        eventLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .leftMouseUp], handler: { [weak self] event in
            guard let `self` = self else {return event}
            self.__window.sendEvent(event)
            return event
        })
        
        eventGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .mouseEntered, .mouseExited, .leftMouseDown, .leftMouseUp], handler: { [weak self] event in
                guard let `self` = self else {return}
                self.__window.sendEvent(event)
            })


        if let message = item.entry.message {
            let messageView = item.context.account.postbox.messageView(message.id) |> deliverOnMainQueue
            lookAtMessageDisposable.set(messageView.start(next: { [weak self] view in
                if view.message == nil {
                    self?.hideAnimated = true
                    self?.hide()
                }
            }))
        }
        
        rotateDisposable.set((item.rotate.get() |> deliverOnMainQueue).start(next: { [weak self] orientation in
            self?.updateQuarterTurn(orientation?.isQuarterTurn == true)
        }))

        self.control.setMode(.pip, animated: true)
    }
    
    private func updateQuarterTurn(_ quarter: Bool) {
        guard quarter != isQuarterTurn else {
            return
        }
        isQuarterTurn = quarter
        rect = NSMakeRect(rect.minX, rect.minY, rect.height, rect.width)
        guard isVisible, let screen = NSScreen.main else {
            return
        }
        let savedRect = NSMakeSize(screen.frame.width * 0.3, screen.frame.width * 0.3)
        self.aspectRatio = self.rect.size.fitted(savedRect)
        self.minSize = self.rect.size.aspectFitted(savedRect).aspectFilled(NSMakeSize(120, 120))
        self.maxSize = self.rect.size.aspectFitted(screen.frame.size)
        let current = self.frame
        let size = NSMakeSize(current.height, current.width)
        let origin = NSMakePoint(current.midX - size.width / 2, current.midY - size.height / 2)
        self.setFrame(NSMakeRect(origin.x, origin.y, size.width, size.height), display: true, animate: true)
    }

    public func hide() {
        

        
        if hideAnimated {
            contentView?._change(opacity: 0, animated: true, duration: 0.1, timingFunction: .linear)
            setFrame(NSMakeRect(frame.minX + (frame.width - 0) / 2, frame.minY + (frame.height - 0) / 2, 0, 0), display: true, animate: true)
        }
        
        orderOut(nil)
        window = nil
        __window.removeAllHandlers(for: self)
        if let monitor = eventLocalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = eventGlobalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        window = nil
        if control.isPictureInPicture {
            control.pause()
        }
    }

    public func openGallery() {
        setFrame(restoreRect, display: true, animate: true)
        hideAnimated = false
        hide()
        showGalleryFromPip(item: item, gallery: self.viewer, delegate: _delegate, contentInteractions: _contentInteractions, type: _type)
    }

    deinit {
        lookAtMessageDisposable.dispose()
        rotateDisposable.dispose()
        if control.isPictureInPicture {
            control.pause()
        }
        self.control.setMode(.normal, animated: true)
        NotificationCenter.default.removeObserver(self)
    }

    public override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        return 0.2
    }

    @objc public func windowDidResized(_ notification: Notification) {
    
    }

    private func findAndMoveToCorner() {
        if let screen = self.screen {
            let rect = screen.frame.offsetBy(dx: -screen.visibleFrame.minX, dy: -screen.visibleFrame.minY)
            
            let point = self.frame.offsetBy(dx: -screen.visibleFrame.minX, dy: -screen.visibleFrame.minY)
            
            var options:BorderType = []
            
            if point.maxX > rect.width && point.minX < rect.width {
                options.insert(.Right)
            }
            
            if point.minX < 0 {
                options.insert(.Left)
            }
            
            if point.minY < 0 {
                options.insert(.Bottom)
            }
            
            
            var newFrame = self.frame
            
            if options.contains(.Right) {
                newFrame.origin.x = screen.visibleFrame.maxX - newFrame.width - 30
            }
            if options.contains(.Bottom) {
                newFrame.origin.y = screen.visibleFrame.minY + 30
            }
            if options.contains(.Left) {
                newFrame.origin.x = screen.visibleFrame.minX + 30
            }
            setFrame(newFrame, display: true, animate: true)

        }
    }
    

    public override var isResizable: Bool {
        return true
    }
    public override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: flag, animate: animateFlag)
        saver.rect = frameRect
        saver.save()
    }

    public override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        if let screen = NSScreen.main {
            let savedRect: NSRect = NSMakeRect(0, 0, screen.frame.width * 0.3, screen.frame.width * 0.3)
            let convert_s = self.rect.size.aspectFilled(NSMakeSize(min(savedRect.width, 250), min(savedRect.height, 250)))
            self.aspectRatio = self.rect.size.fitted(NSMakeSize(savedRect.width, savedRect.height))
            self.minSize = self.rect.size.aspectFitted(NSMakeSize(savedRect.width, savedRect.height)).aspectFilled(NSMakeSize(120, 120))
            
            let frame = NSScreen.main?.frame ?? NSMakeRect(0, 0, 1920, 1080)
            
            self.maxSize = self.rect.size.aspectFitted(frame.size)
            
            var rect = saver.rect.size.bounds
            rect.origin = NSMakePoint(screen.frame.width - convert_s.width - 30, screen.frame.height - convert_s.height - 50)

            self.setFrame(NSMakeRect(rect.minX, rect.minY, convert_s.width, convert_s.height), display: true, animate: true)
           
        }
    }


}



private var window: NSWindow?


public var hasPictureInPicture: Bool {
    return window != nil
}

public func showPipVideo(control: PictureInPictureControl, viewer: GalleryViewer, item: MGalleryItem, origin: NSPoint, delegate:InteractionContentViewProtocol? = nil, contentInteractions:(any GalleryContentInteractions)? = nil, type: GalleryAppearType) {
    closePipVideo()
    window = ModernPictureInPictureVideoWindow(control, item: item, viewer: viewer, origin: origin, delegate: delegate, contentInteractions: contentInteractions, type: type)
    window?.makeKeyAndOrderFront(nil)
}


public func exitPictureInPicture() {
    if let window = window as? ModernPictureInPictureVideoWindow {
        window.openGallery()
    }
}

public func pausepip() {
    if let window = window as? ModernPictureInPictureVideoWindow {
        if window.control.isPlaying() {
            window.control.pause()
            window.forcePaused = true
        }
    }
}

public func playPipIfNeeded() {
    if let window = window as? ModernPictureInPictureVideoWindow, window.forcePaused, window.control.isPlaying()  {
        window.control.play()
        window.forcePaused = false
    }
}



public func closePipVideo() {
    if let window = window as? ModernPictureInPictureVideoWindow {
        window.hide()
        window.control.pause()
    }
    window = nil
    
}

public func closePipVideo(accountId: AccountRecordId) {
    if let window = window as? ModernPictureInPictureVideoWindow, window.viewer.accountId == accountId {
        closePipVideo()
    }
}
