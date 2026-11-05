import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramMedia
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils

private var reactions: ReactionsWindowController?

public final class ReactionsWindowController : NSObject {
    
    
    private class V : View {
        private let visualView: NSVisualEffectView
        private let glassView: NSView?
        private let contentView: NSView
        private let backgroundView = View()
        private let container = View()
        private let theme: TelegramPresentationTheme
        private var tintGlass: NSView?
        private var morphTimer: Foundation.Timer?
        private var isMorphing = false
        init(_ content: NSView, theme: TelegramPresentationTheme) {
            
            self.theme = theme
            self.contentView = content
            self.visualView = NSVisualEffectView(frame: content.bounds)
            if #available(macOS 26.0, *), System.liquidGlass, System.liquidGlassAvailable, !TelegramUtilsHooks.shared.isLite(.blur) {
                let glass = NSGlassEffectView(frame: .zero)
                glass.style = .regular
                glass.cornerRadius = 20
                glass.tintColor = nil
                glass.wantsLayer = true
                glass.appearance = NSAppearance.themed(isDark: theme.colors.isDark)
                self.glassView = glass
            } else {
                self.glassView = nil
            }
            super.init(frame: content.bounds)
            if let glassView {
                container.addSubview(glassView)
                backgroundView.backgroundColor = .clear
            } else if #available(macOS 11.0, *), !TelegramUtilsHooks.shared.isLite(.blur) {
                container.addSubview(visualView)
                backgroundView.backgroundColor = .menuFallbackVeil(isDark: theme.colors.isDark)
            } else {
                backgroundView.backgroundColor = theme.colors.background
            }
            container.addSubview(backgroundView)
            container.addSubview(contentView)

            
            addSubview(container)
            

            if !TelegramUtilsHooks.shared.isLite(.blur) {
                self.visualView.wantsLayer = true
                self.visualView.state = .active
                self.visualView.blendingMode = .behindWindow
                self.visualView.autoresizingMask = []
                self.visualView.material = .menu
                self.visualView.appearance = NSAppearance.themed(isDark: theme.colors.isDark)
            }
            
            self.autoresizesSubviews = false

            
            self.layer?.isOpaque = false
            
            let layers = [self.layer, contentView.layer, self.visualView.layer, self.backgroundView.layer, self.container.layer]
            for layer in layers {
                layer?.cornerRadius = 20
                if #available(macOS 10.15, *) {
                    layer?.cornerCurve = .continuous
                }
            }
            contentView.layer?.opacity = 0
        }
        
        func appearAnimated(from bar: NSRect) {
            contentView.layer?.opacity = 1
            tintGlass?.alphaValue = 1
            let target = bounds
            let swell = bar.insetBy(dx: -2, dy: -1.5)
            let start = CACurrentMediaTime()
            morphTimer?.invalidate()
            let timer = Foundation.Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                let seconds = CACurrentMediaTime() - start
                if seconds >= 0.3 {
                    self.finishMorph()
                    return
                }
                let anticipation = CGFloat(sin(min(1, seconds / 0.05) * .pi / 2))
                let from = NSMakeRect(bar.minX + (swell.minX - bar.minX) * anticipation, bar.minY + (swell.minY - bar.minY) * anticipation, bar.width + (swell.width - bar.width) * anticipation, bar.height + (swell.height - bar.height) * anticipation)
                let eased = min(1, max(0, (seconds - 0.03) / 0.25))
                let progress = CGFloat(1 - pow(1 - eased, 3))
                let rect = NSMakeRect(from.minX + (target.minX - from.minX) * progress, from.minY + (target.minY - from.minY) * progress, from.width + (target.width - from.width) * progress, from.height + (target.height - from.height) * progress)
                self.applyMorph(rect)
                let linear = min(1, seconds / 0.3)
                let material = linear * linear * (3 - 2 * linear)
                self.glassView?.alphaValue = min(1, material / 0.4)
                self.tintGlass?.alphaValue = 1 - max(0, (material - 0.25) / 0.75)
            }
            RunLoop.main.add(timer, forMode: .common)
            morphTimer = timer
        }

        deinit {
            morphTimer?.invalidate()
        }

        private func finishMorph() {
            morphTimer?.invalidate()
            morphTimer = nil
            isMorphing = false
            tintGlass?.removeFromSuperview()
            tintGlass = nil
            glassView?.alphaValue = 1
            applyMorph(bounds)
            if glassView == nil {
                let shadow = NSShadow()
                shadow.shadowBlurRadius = 2
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
                shadow.shadowOffset = NSMakeSize(0, 0)
                self.shadow = shadow
                self.layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 20, cornerHeight: 20, transform: nil)
            }
            needsLayout = true
        }

        var usesGlass: Bool {
            return glassView != nil
        }

        func initFake(_ bar: NSRect) {
            isMorphing = true
            if #available(macOS 26.0, *), let glassView {
                let tint = NSGlassEffectView(frame: .zero)
                tint.style = .regular
                tint.cornerRadius = 20
                tint.tintColor = theme.colors.background.withAlphaComponent(0.3)
                tint.appearance = NSAppearance.themed(isDark: theme.colors.isDark)
                container.addSubview(tint, positioned: .above, relativeTo: glassView)
                tintGlass = tint
                tint.alphaValue = 0
                glassView.alphaValue = 0
            }
            applyMorph(bar)
        }

        private func applyMorph(_ rect: NSRect) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            container.frame = rect
            let inner = rect.size.bounds
            glassView?.frame = inner
            tintGlass?.frame = inner
            visualView.frame = inner
            backgroundView.frame = inner
            contentView.frame = NSRect(origin: NSMakePoint(-rect.minX, -rect.minY), size: bounds.size)
            CATransaction.commit()
        }
        
        override func layout() {
            super.layout()
            if isMorphing {
                return
            }
            self.container.frame = bounds
            self.contentView.frame = bounds
            self.visualView.frame = bounds
            self.glassView?.frame = bounds
            self.backgroundView.frame = bounds
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        required init(frame frameRect: NSRect) {
            fatalError("init(frame:) has not been implemented")
        }
    }
    
    private let emojies: ReactionsEmojiesController
    private let context: any AccountContextProtocol
    
    private var panel: Window?
    private let overlay = OverlayControl()
    
    private var initialPlayers:[Int: LottiePlayerView] = [:]
    private var isRevealed: Bool = false
    private var pendingAppearance: [TableRowItem]?

    
    private var keyDisposable: Disposable?
    private var panelKeyDisposable: Disposable?

    private func makeView(_ content: NSView, _ initialView: NSView, _ initialRect: NSRect, animated: Bool, theme: TelegramPresentationTheme, moveTop: Bool) -> (Window, V) {
        
        let v = V(content, theme: theme)
        
        var wAdd: CGFloat = 0
        var initialAdd: CGFloat = 0
        if initialView.frame.height != 60 {
            let offset = initialView.subviews[1].frame.minY - 8
            wAdd = (initialView.frame.height - 60) + offset // (18 is reaction offset y in parent)
            initialAdd = offset // (18 is reaction offset y in parent)
            
            if moveTop {
                wAdd += 46
                initialAdd += 46
            }
        }
        
        let panel = MenuPanelWindow(contentRect: NSMakeRect(initialRect.minX - 21, initialRect.maxY - 320 + (initialRect.height + 20) - 32 + 36 - wAdd, 390, 340), styleMask: [.fullSizeContentView], backing: .buffered, defer: false)
        panel._canBecomeMain = false
        panel._canBecomeKey = false
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.name = self.name
        
        let contentView = FlippableView(frame: .zero)
        panel.contentView = contentView

        contentView.backgroundColor = .clear
        contentView.flip = false
        contentView.layer?.isOpaque = false
        
        
        v.frame = v.frame.offsetBy(dx: 20, dy: 20)
        contentView.addSubview(v)
        
        initialView.frame = NSMakeRect(v.frame.minX + 1, v.frame.maxY - initialView.frame.height - (48 + 36) + initialAdd, initialView.frame.width, initialView.frame.height)
       // initialView.background = .red
//        initialView.layer?.opacity = 0.5
        initialView.removeFromSuperview()
        contentView.addSubview(initialView)
        
        return (panel, v)
        
    }

    private var onClose:(()->Void)?
    private let presentation: TelegramPresentationTheme
    private let name: String
    private let moveTop: Bool
    private var skipAppearAnimation = false
    
    private let parentWindow: Window
    public init<Context: AccountContextProtocol>(_ context: Context, peerId: PeerId, selectedItems: [EmojiesSectionRowItem.SelectedItem], react: @escaping(StickerPackItem, NSRect?)->Void, reactLarge: ((StickerPackItem, NSRect?)->Void)? = nil, onClose:(()->Void)? = nil, presentation: TelegramPresentationTheme = theme, name: String = "", moveTop: Bool = false, mode: EmojiesController.Mode = .reactions, parentWindow: Window? = nil, orderedTags: [RecentReactionItem]? = nil) {
        self.parentWindow = parentWindow ?? context.window
        self.context = context
        self.presentation = presentation
        self.onClose = onClose
        self.name = name
        self.moveTop = moveTop
        self.emojies = EmojiesController(context, mode: context.peerId == peerId ? .defaultTags : mode, selectedItems: selectedItems, presentation: presentation, orderedTags: orderedTags)
        self.emojies.loadViewIfNeeded()
        super.init()
        
        let interactions = EntertainmentInteractions(.emoji, peerId: peerId)
        
        interactions.sendAnimatedEmoji = { [weak self] sticker, _, _, _, fromRect in
            react(sticker, fromRect)
            self?.close(animated: true)
        }
        if let reactLarge {
            interactions.sendLargeReaction = { [weak self] sticker, fromRect in
                reactLarge(sticker, fromRect)
                self?.close(animated: true)
            }
        }
        emojies.update(with: interactions, chatInteraction: EntertainmentUIHooks.shared.makeChatInteraction(context, peerId))

        
        emojies.closeCurrent = { [weak self] in
            self?.close(animated: true)
        }
        emojies.animateAppearance = { [weak self] items in
            guard let self else {
                return
            }
            if self.isRevealed {
                self.animateAppearanceItems(items, initialPlayers: self.initialPlayers)
            } else {
                self.pendingAppearance = items
            }
        }
    }
    
    private func animateAppearanceItems(_ items: [TableRowItem], initialPlayers:[Int: LottiePlayerView]) {
        
        if skipAppearAnimation {
            return
        }
        let sections = items.compactMap {
            $0 as? EmojiesSectionRowItem
        }
        let tabs = items.compactMap {
            $0 as? StickerPackRowItem
        }
        let firstTab = items.compactMap {
            $0 as? ETabRowItem
        }
        
        let duration: Double = 0.35
        let itemDelay: Double = duration / Double(sections.count)
        var delay: Double = itemDelay
        
        firstTab.first?.animateAppearance(delay: 0.1, duration: duration, ignoreCount: 0)
        
        for tab in tabs {
            tab.animateAppearance(delay: 0.1, duration: duration, ignoreCount: 0)
        }
        
        for (i, section) in sections.enumerated() {
            section.animateAppearance(delay: delay, duration: duration, initialPlayers: i == 0 ? initialPlayers : [:])
            delay += itemDelay
        }
    }
    
    public func show(_ initialView: NSView & StickerFramesCollector, animated: Bool = true) {
        reactions?.panel?.orderOut(nil)
        if let previous = reactions {
        }
        
        reactions = self
        
        self.ready(initialView, animated: animated)
       
    }
    
    private func ready(_ initialView: NSView & StickerFramesCollector, animated: Bool) {
        
        guard NSScreen.main != nil else {
            return
        }
        
        let initialWindow = initialView.window!
        let initialScreenRect = initialWindow.convertToScreen(initialView.convert(initialView.bounds, to: nil))
        
                
        
        self.emojies.view.frame = self.emojies.view.bounds
        let (panel, view) = makeView(self.emojies.view, initialView, initialScreenRect, animated: animated, theme: self.presentation, moveTop: moveTop)
        
        panel.makeKeyAndOrderFront(nil)
        
        panel.order(.below, relativeTo: initialWindow.windowNumber)
        
        self.panel = panel
        let context = self.context
                
        
        

        panel.set(handler: { [weak self] _ in
            self?.close(animated: true)
            return .invoked
        }, with: self, for: .Escape, priority: .modal)
        
        panel.set(handler: { [weak self] _ in
            self?.close(animated: true)
            return .invoked
        }, with: self, for: .Escape, priority: .modal)
        
        panel.set(mouseHandler: { [weak view, weak self] _ in
            if view?.mouseInside() == false {
                self?.close(animated: true)
            }
            return .rejected
        }, with: self, for: .leftMouseUp, priority: .supreme)
        
        parentWindow.set(handler: { [weak self] _ in
            self?.close(animated: true)
            return .invoked
        }, with: self, for: .Escape, priority: .supreme)
        
        var isInteracted: Bool = false

        
        parentWindow.set(mouseHandler: { event in
            isInteracted = true
            return .rejected
        }, with: self, for: .leftMouseDown, priority: .supreme)
        
        parentWindow.set(mouseHandler: { [weak self] event in
            if isInteracted {
                self?.close(animated: true)
            }
            let was = isInteracted
            isInteracted = true
            return !was ? .rejected : .invoked
        }, with: self, for: .leftMouseUp, priority: .supreme)

        parentWindow.set(mouseHandler: { event in
            isInteracted = true
            return .rejected
        }, with: self, for: .rightMouseDown, priority: .supreme)

        parentWindow.set(mouseHandler: { [weak self] event in
            if isInteracted {
                self?.close(animated: true)
            }
            let was = isInteracted
            isInteracted = true
            return !was ? .rejected : .invoked
        }, with: self, for: .rightMouseUp, priority: .supreme)
        
        var skippedFirst: Bool = false
        
        self.keyDisposable = context.window.keyWindowUpdater.start(next: { [weak self] value in
            if !value && skippedFirst, self?.panel?._canBecomeKey == false {
                self?.close()
            }
            skippedFirst = true
        })
        
        self.panelKeyDisposable = panel.keyWindowUpdater.start(next: { [weak self] value in
            if self?.panel?.canBecomeKey == true, !value {
                DispatchQueue.main.async {
                    self?.close(animated: context.window.isKeyWindow == true)
                }
            }
        })
        
        let barInInitial = NSMakeRect(10, 5, initialView.frame.width - 20, initialView.frame.height - 20)
        let barRect = view.convert(barInInitial, from: initialView)
        view.initFake(barRect)

        overlay.frame = context.window.bounds
        context.window.contentView?.addSubview(overlay)

        
        let ready = emojies.ready.get() |> take(1)
        _ = ready.start(next: { [weak view, weak initialView, weak self] _ in
            guard let view = view, let initialView = initialView, let `self` = self else {
                return
            }
            AppMenu.closeAll()
            initialView.revealDidStart()
            CATransaction.begin()
            initialView.removeFromSuperview()
            CATransaction.commit()

            self.initialPlayers = initialView.collect()
            self.isRevealed = true
            CATransaction.begin()
            view.appearAnimated(from: barRect)
            CATransaction.commit()
            if let pending = self.pendingAppearance {
                self.pendingAppearance = nil
                self.animateAppearanceItems(pending, initialPlayers: self.initialPlayers)
            }
            
            if initialScreenRect.origin.y - 200 < 0, let panel = self.panel {
                self.skipAppearAnimation = true
                panel.setFrame(NSMakeRect(panel.frame.minX, panel.frame.minY + 100, panel.frame.width, panel.frame.height), display: true, animate: true)
            }
                        
            if self.moveTop {
                if let menu = contextOnScreen() {
                    menu.setFrame(menu.frame.offsetBy(dx: 0, dy: -216), display: true, animate: false)
                }
            }
            
        })
        
    }
    
    deinit {
        panelKeyDisposable?.dispose()
        keyDisposable?.dispose()
    }
    
    private func close(animated: Bool = false) {
        
        self.onClose?()
        
        self.overlay.removeFromSuperview()
        self.context.window.removeAllHandlers(for: self)
        self.parentWindow.removeAllHandlers(for: self)
        self.panel?.removeAllHandlers(for: self)
        AppMenu.closeAll()
        
        var panel: Window? = self.panel
        if animated {
            if let v = panel?.contentView?.subviews.first(where: { $0 is V }) as? V, !v.usesGlass {
                v.layer?.rasterizationScale = System.backingScale
                v.layer?.shouldRasterize = true
            }
            panel?.contentView?.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { _ in
                panel?.orderOut(nil)
                panel = nil
            })
        } else {
            self.panel?.orderOut(nil)
        }
        reactions = nil
    }
}

