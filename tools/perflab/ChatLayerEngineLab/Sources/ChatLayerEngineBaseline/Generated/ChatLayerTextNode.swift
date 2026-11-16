import Cocoa
import TGUIKit
import InputTextView
import SwiftSignalKit

private final class ChatLayerTextMenuState: Disposable {
    private(set) var version: UInt64 = 0
    private(set) var text: NSAttributedString?
    private weak var layout: TextViewLayout?
    private var windowId: ObjectIdentifier?
    weak var presentedMenu: ContextMenu?
    private var disposable: Disposable?
    private var active = false
    private var disposed = false

    func isCurrent(_ version: UInt64) -> Bool {
        return !disposed && self.version == version
    }

    func matches(_ layout: TextViewLayout?) -> Bool {
        guard active, let layout = layout, self.layout === layout, let text = text else { return false }
        return text === layout.attributedString || text.isEqual(to: layout.attributedString)
    }

    func matchesWindow(_ window: NSWindow?) -> Bool {
        return windowId == window.map(ObjectIdentifier.init)
    }

    func cancelIfWindowChanged(_ window: NSWindow?) {
        if active && !matchesWindow(window) { cancel() }
    }

    func begin(_ layout: TextViewLayout, window: NSWindow?) -> UInt64 {
        let version = cancel()
        guard isCurrent(version) else { return version }
        self.layout = layout
        windowId = window.map(ObjectIdentifier.init)
        text = layout.attributedString.copy() as? NSAttributedString
        active = true
        return version
    }

    @discardableResult func cancel() -> UInt64 {
        version &+= 1
        let version = version
        presentedMenu = nil
        clearPending()
        return version
    }

    func cancelIfInvalid(_ layout: TextViewLayout?) {
        if active && !matches(layout) {
            cancel()
        }
    }

    func install(_ disposable: Disposable, version: UInt64) {
        guard isCurrent(version), active else {
            disposable.dispose()
            return
        }
        let previous = self.disposable
        self.disposable = disposable
        previous?.dispose()
    }

    func finish(_ version: UInt64) {
        if isCurrent(version) { clearPending() }
    }

    private func clearPending() {
        let previous = disposable
        let previousText = text
        disposable = nil
        text = nil
        layout = nil
        windowId = nil
        active = false
        previous?.dispose()
        withExtendedLifetime(previousText) {}
    }

    func dispose() {
        disposed = true
        cancel()
    }
}

final class ChatLayerTextNode: ChatLayerNode {
    private struct HeaderId: Hashable {
        let parent: AnyHashable
        let index: Int
    }

    private final class QuoteMaskLayer: SimpleShapeLayer {
        var textBounds: NSRect?
        var rounded = false
    }

    private final class FoldingDecoration {
        let background = FoldingTextQuoteLayer()
        let arrow = SimpleLayer()
        var textMask: SimpleLayer?
        var layout: FoldingTextLayout.ViewLayout

        init(_ layout: FoldingTextLayout.ViewLayout) { self.layout = layout }
    }

    private final class Highlight {
        let layer: SimpleLayer
        let text: NSAttributedString
        let size: NSSize

        init(layer: SimpleLayer, layout: TextViewLayout) {
            self.layer = layer
            self.text = layout.attributedString.copy() as! NSAttributedString
            self.size = layout.layoutSize
        }
    }

    let drawingLayer = TextViewLayer()
    private var bindingVersion: UInt64 = 0
    private var selectionStart: NSPoint?
    private var pressedLinkRange: NSRange?
    private var hoveredLinkRange: NSRange?
    private var quoteMask: QuoteMaskLayer?
    private var folding: FoldingDecoration?
    private var activeHighlight: Highlight?
    private var menuState: ChatLayerTextMenuState?
    private var linkState: ChatLayerTextLinkState?
    private var hasLinks = false
    private var didDrag = false
    private var hasExternalSelection = false
    var hasExternalTextSelection: Bool { hasExternalSelection }
    private var suppressTextClick = false
    var onTextClick: (() -> Bool)? {
        didSet {
            acceptsPointerEvents = isSelectable || hasLinks || onTextClick != nil || allowsUnselectedMenu
            acceptsKeyboardFocus = isSelectable || onTextClick != nil
            onAccessibilityPress = onTextClick
        }
    }
    var onSelectionChanged: ((NSRange) -> Void)?
    var copyText: ((NSAttributedString) -> Void)?

    private var allowsUnselectedMenu: Bool { textLayout?.mayItems == true && textLayout?.alwaysStaticItems == false && textLayout?.interactions.menuItems != nil }

    var toolTip: String? {
        get { linkState?.toolTip }
        set {
            guard linkState?.toolTip != newValue else { return }
            if linkState == nil { linkState = ChatLayerTextLinkState(node: self) }
            linkState?.toolTip = newValue
            linkState?.synchronizeToolTips(force: true)
        }
    }

    var textLayout: TextViewLayout? { drawingLayer.textLayout }
    var isSelectable: Bool {
        get { drawingLayer.isTextSelectable }
        set {
            guard drawingLayer.isTextSelectable != newValue else { return }
            let version = bindingVersion
            menuState?.cancel()
            guard bindingVersion == version else { return }
            drawingLayer.isTextSelectable = newValue
            acceptsKeyboardFocus = newValue || onTextClick != nil
            guard bindingVersion == version else { return }
            acceptsPointerEvents = newValue || hasLinks || onTextClick != nil || allowsUnselectedMenu
        }
    }

    override var frame: NSRect {
        get { super.frame }
        set {
            let oldSize = super.frame.size
            super.frame = newValue
            if super.frame.size != oldSize { updateDrawingGeometry() }
        }
    }

    override func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        let previousSize = self.frame.size
        super.updateFrame(frame, transition: transition)
        if self.frame.size != previousSize { updateDrawingGeometry() }
    }

    init(id: AnyHashable, selectable: Bool) {
        super.init(id: id)
        layer.masksToBounds = false
        layer.addSublayer(drawingLayer)
        isSelectable = selectable
        accessibilityRole = .staticText
        onPointer = { [weak self] event in self?.handle(event) ?? false }
        onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        onCommand = { [weak self] command in self?.handleCommand(command) ?? false }
        onWindowKeyChanged = { [weak self] isKey in
            guard let self else { return }
            self.drawingLayer.isKeyWindow = isKey
            self.menuState?.cancelIfWindowChanged(self.scene?.window)
            self.linkState?.cancelIfWindowChanged()
        }
        onFocusChanged = { [weak self] focused in
            if !focused, self?.hasExternalSelection == false { self?.setSelection(NSRange(location: NSNotFound, length: 0)) }
        }
    }

    func update(_ layout: TextViewLayout?, size: NSSize? = nil, knownHasLinks: Bool? = nil, frame: NSRect? = nil, preservingSelectionGesture: Bool = false) {
        bindingVersion &+= 1
        let version = bindingVersion
        linkState?.cancelIfInvalid(layout)
        guard bindingVersion == version else { return }
        menuState?.cancelIfInvalid(layout)
        guard bindingVersion == version else { return }
        if let highlight = activeHighlight, layout?.layoutSize != highlight.size || layout?.attributedString.isEqual(to: highlight.text) != true {
            clearHighlight()
        }
        if layout !== textLayout {
            for child in children {
                (child as? ChatLayerButtonNode)?.resetInteraction()
                guard bindingVersion == version else { return }
            }
            let keepSelectionGesture = preservingSelectionGesture && (selectionStart != nil || hasExternalSelection)
                && layout?.layoutSize == textLayout?.layoutSize
                && layout?.attributedString.string == textLayout?.attributedString.string
                && (pressedLinkRange == nil || didDrag || linkState?.matchesPress(layout) == true)
            if !keepSelectionGesture {
                clearExternalSelection()
                guard bindingVersion == version else { return }
                selectionStart = nil
                pressedLinkRange = nil
                linkState?.clearPress()
            }
            cursor = isSelectable ? .iBeam : .arrow
            suppressTextClick = false
            leaveLink()
            guard bindingVersion == version else { return }
        }
        hasLinks = knownHasLinks ?? false
        if knownHasLinks == nil, let text = layout?.attributedString {
            text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, stop in
                if value != nil { hasLinks = true; stop.pointee = true }
            }
        }
        drawingLayer.update(layout, size: frame?.size ?? size)
        accessibilityValue = layout?.attributedString.string
        accessibilityRole = accessibilityValue?.isEmpty == false ? .staticText : nil
        if let frame { self.frame = frame }
        else { self.frame.size = drawingLayer.textSize }
        if folding != nil { updateDrawingGeometry() }
        acceptsPointerEvents = isSelectable || hasLinks || onTextClick != nil || allowsUnselectedMenu
        if linkState?.toolTip != nil || (hasLinks && (layout?.toolTipRects.isEmpty == false || (linkState != nil && (layout?.interactions.longHoverOnLink != nil || pressedLinkRange != nil)))) {
            if linkState == nil { linkState = ChatLayerTextLinkState(node: self) }
            linkState?.synchronizeToolTips(force: true)
        } else if let state = linkState {
            state.detach()
            guard bindingVersion == version else { return }
            linkState = nil
        }
    }

    func synchronizeLinkToolTips(force: Bool) { linkState?.synchronizeToolTips(force: force) }
    func didRemoveLinkToolTips() { linkState?.didRemoveToolTips() }
    func refreshLinkHover(at point: NSPoint) {
        if hasLinks { updateCursor(at: point) }
    }

    func resetInteraction() {
        bindingVersion &+= 1
        let version = bindingVersion
        linkState?.clearPress()
        linkState?.cancel()
        guard bindingVersion == version else { return }
        menuState?.cancel()
        guard bindingVersion == version else { return }
        clearHighlight()
        for child in children {
            (child as? ChatLayerButtonNode)?.resetInteraction()
            guard bindingVersion == version else { return }
        }
        clearExternalSelection()
        guard bindingVersion == version else { return }
        setSelection(NSRange(location: NSNotFound, length: 0))
        guard bindingVersion == version else { return }
        selectionStart = nil
        pressedLinkRange = nil
        didDrag = false
        suppressTextClick = false
        leaveLink()
        guard bindingVersion == version, hoveredLinkRange == nil else { return }
        cursor = isSelectable ? .iBeam : .arrow
    }

    func updateCodeHeaders() throws {
        guard let textLayout else {
            try setChildren([])
            return
        }
        var headers: [ChatLayerNode] = []
        for (quoteIndex, quote) in textLayout.blockQuotes.enumerated() where quote.header != nil {
            let index = headers.count
            let id = HeaderId(parent: id, index: quoteIndex)
            let header = index < children.count ? children[index] as? ChatLayerButtonNode : nil
            let button: ChatLayerButtonNode
            if let header, header.id == AnyHashable(id) { button = header }
            else {
                button = ChatLayerButtonNode(id: id, label: localizedString("Text.Copy"), action: { [weak self] in self?.copyBlockQuote(at: quoteIndex) })
            }
            button.frame = NSRect(x: quote.frame.minX, y: quote.frame.minY, width: quote.frame.width, height: quote.headerInset + 2)
            headers.append(button)
        }
        try setChildren(headers)
    }

    private func copyBlockQuote(at index: Int) {
        guard let layout = textLayout, layout.blockQuotes.indices.contains(index), let text = layout.blockQuoteText(startingWith: layout.blockQuotes[index].range) else { return }
        if let copy = layout.interactions.copyToClipboard { _ = copy(text) }
        else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        if let window = scene?.window as? Window {
            showModalText(for: window, text: localizedString("Share.Link.Copied"))
        }
    }

    override func updateOwnScale(_ scale: CGFloat) {
        super.updateOwnScale(scale)
        if drawingLayer.contentsScale != scale {
            drawingLayer.contentsScale = scale
            drawingLayer.setNeedsDisplay()
        }
        if let folding {
            for layer in [folding.background, folding.arrow, folding.textMask].compactMap({ $0 }) where layer.contentsScale != scale {
                layer.contentsScale = scale
                layer.setNeedsDisplay()
            }
        }
        if let quoteMask, quoteMask.contentsScale != scale {
            quoteMask.contentsScale = scale
            quoteMask.setNeedsDisplay()
        }
        activeHighlight?.layer.contentsScale = scale
    }

    override func attach(to scene: ChatLayerSceneView?) {
        super.attach(to: scene)
        if scene == nil {
            let version = bindingVersion
            linkState?.detach()
            guard self.scene == nil, bindingVersion == version else { return }
            menuState?.cancel()
            guard self.scene == nil, bindingVersion == version else { return }
            clearExternalSelection()
            guard self.scene == nil, bindingVersion == version else { return }
            clearHighlight()
        } else if self.scene === scene {
            linkState?.synchronizeToolTips(force: true)
        }
    }

    private func updateDrawingGeometry() {
        let bounds = NSRect(origin: .zero, size: folding?.layout.layoutSize ?? layer.bounds.size)
        drawingLayer.textSize = bounds.size
        drawingLayer.bounds = bounds.insetBy(dx: -2, dy: -3)
        drawingLayer.position = NSPoint(x: bounds.midX, y: bounds.midY)
        updateQuoteMask()
    }

    func setQuoteClipping(_ enabled: Bool, rounded: Bool = false) {
        clipsChildren = enabled
        if enabled {
            if quoteMask == nil {
                quoteMask = QuoteMaskLayer()
                quoteMask?.contentsScale = layer.contentsScale
                layer.mask = quoteMask
            }
            if quoteMask?.rounded != rounded {
                quoteMask?.rounded = rounded
                quoteMask?.textBounds = nil
            }
            updateQuoteMask()
        } else if quoteMask != nil {
            layer.mask = nil
            quoteMask = nil
        }
    }

    private func updateQuoteMask() {
        guard let quoteMask, quoteMask.textBounds != layer.bounds else { return }
        let path = CGMutablePath()
        path.addRoundedRect(in: layer.bounds, cornerWidth: quoteMask.rounded ? min(layer.bounds.width / 2, 4) : 0, cornerHeight: quoteMask.rounded ? min(layer.bounds.height / 2, 4) : 0)
        quoteMask.path = path
        quoteMask.textBounds = layer.bounds
    }

    func updateFolding(_ layout: FoldingTextLayout.ViewLayout?) {
        guard let layout else {
            if let folding {
                folding.background.removeFromSuperlayer()
                folding.arrow.removeFromSuperlayer()
                drawingLayer.mask = nil
                self.folding = nil
                drawingLayer.canDrawBlocks = true
                updateDrawingGeometry()
            }
            return
        }
        let decoration: FoldingDecoration
        if let folding { decoration = folding }
        else {
            decoration = FoldingDecoration(layout)
            folding = decoration
            layer.insertSublayer(decoration.background, below: drawingLayer)
            layer.addSublayer(decoration.arrow)
        }
        decoration.layout = layout
        decoration.background.mask = quoteMask
        decoration.background.blockQuotes = layout.text.blockQuotes
        decoration.background.frame = NSRect(origin: .zero, size: layout.layoutSize)
        decoration.arrow.frame = NSRect(x: layout.size.width - 15, y: layout.size.height - 13, width: 10, height: 7)
        decoration.arrow.contents = layout.isRevealed ? layout.arrowUp : layout.arrowDown
        drawingLayer.canDrawBlocks = false
        if layout.isRevealed {
            drawingLayer.mask = nil
            decoration.textMask = nil
        } else {
            let mask = decoration.textMask ?? SimpleLayer()
            mask.contents = layout.mask
            mask.contentsGravity = .bottom
            mask.frame = NSRect(origin: .zero, size: layout.size)
            decoration.textMask = mask
            drawingLayer.mask = mask
        }
        updateOwnScale(layer.contentsScale)
        updateDrawingGeometry()
    }

    func highlight(text: String, color: NSColor, range: NSRange? = nil) {
        clearHighlight()
        guard let layout = textLayout else { return }
        let string = layout.attributedString.string as NSString
        let effectiveRange: NSRange
        if let range, range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= string.length, range.length <= string.length - range.location, string.substring(with: range) == text {
            effectiveRange = range
        } else {
            effectiveRange = string.range(of: text)
        }
        guard effectiveRange.location != NSNotFound else { return }
        let image = layout.generateBlock(for: effectiveRange, backgroundColor: color)
        guard let contents = image.1 else { return }
        let imageLayer = SimpleLayer(frame: NSRect(origin: image.0, size: contents.backingSize))
        imageLayer.contents = contents
        imageLayer.contentsScale = layer.contentsScale
        imageLayer.opacity = 0.5
        layer.insertSublayer(imageLayer, below: drawingLayer)
        activeHighlight = Highlight(layer: imageLayer, layout: layout)
        _ = delaySignal(3.0).start(completed: { [weak self, weak imageLayer] in
            guard let self, let imageLayer, self.activeHighlight?.layer === imageLayer else { return }
            performSublayerRemoval(imageLayer, animated: true)
            self.activeHighlight = nil
        })
    }

    private func clearHighlight() {
        activeHighlight?.layer.removeFromSuperlayer()
        activeHighlight = nil
    }

    func setSelection(_ range: NSRange) {
        guard let layout = textLayout else { return }
        let validated: NSRange
        if range.location == NSNotFound {
            validated = NSRange(location: NSNotFound, length: 0)
        } else {
            let start = min(max(0, range.location), layout.attributedString.length)
            validated = NSRange(location: start, length: min(max(0, range.length), layout.attributedString.length - start))
        }
        guard layout.selectedRange.range != validated else { return }
        layout.selectedRange = TextSelectedRange(range: validated, color: layout.selectedRange.color, def: true)
        selectionChanged()
    }

    func setExternalSelection(_ range: NSRange) {
        hasExternalSelection = true
        setSelection(range)
    }

    func clearExternalSelection() {
        guard hasExternalSelection else { return }
        hasExternalSelection = false
        if onTextClick != nil, textLayout?.selectedRange.hasSelectText == true { suppressTextClick = true }
        setSelection(NSRange(location: NSNotFound, length: 0))
    }

    private func selectionChanged() {
        drawingLayer.setNeedsDisplay()
        if let range = textLayout?.selectedRange.range { onSelectionChanged?(range) }
    }

    private func leaveLink(cancelPreview: Bool = true) {
        let version = bindingVersion
        if cancelPreview { linkState?.cancel() }
        guard bindingVersion == version, hoveredLinkRange != nil else { return }
        hoveredLinkRange = nil
        cursor = isSelectable ? .iBeam : .arrow
        textLayout?.interactions.hoverOnLink(.exited)
    }

    private func updateCursor(at point: NSPoint) {
        let version = bindingVersion
        let layout = textLayout
        let link = layout?.link(at: point)
        guard bindingVersion == version else { return }
        if hoveredLinkRange != link?.2 {
            leaveLink(cancelPreview: link == nil)
            guard bindingVersion == version, hoveredLinkRange == nil else { return }
            hoveredLinkRange = link?.2
            if let link { layout?.interactions.hoverOnLink(.entered(link.0)) }
            guard bindingVersion == version, hoveredLinkRange == link?.2 else { return }
        }
        if let link, let layout, layout.interactions.longHoverOnLink != nil {
            if linkState == nil { linkState = ChatLayerTextLinkState(node: self) }
            linkState?.synchronizeToolTips(force: false)
            linkState?.hover(link: link.0, range: link.2, layout: layout)
        } else {
            linkState?.cancel()
        }
        guard bindingVersion == version else { return }
        cursor = link == nil ? (isSelectable ? .iBeam : .arrow) : .pointingHand
        cursor?.set()
    }

    private func handle(_ event: ChatLayerPointerEvent) -> Bool {
        guard let layout = textLayout else { return false }
        switch event.kind {
        case .entered, .moved:
            updateCursor(at: event.location)
            return false
        case .exited:
            leaveLink()
            return false
        case .cancelled:
            suppressTextClick = false
            selectionStart = nil
            pressedLinkRange = nil
            linkState?.clearPress()
            return true
        case .down:
            if event.button == 1 || (event.button == 0 && event.modifiers.contains(.control)) {
                guard let native = event.nativeEvent else { return false }
                return requestMenu(at: event.location, event: native)
            }
            guard event.button == 0 else { return false }
            suppressTextClick = suppressTextClick || layout.selectedRange.hasSelectText
            clearExternalSelection()
            let index = layout.findIndex(location: event.location)
            guard onTextClick != nil || (index >= 0 && (event.location.x <= layout.lines[index].frame.maxX || !isSelectable)) else { return false }
            guard isSelectable || onTextClick != nil || layout.link(at: event.location) != nil else { return false }
            selectionStart = event.location
            didDrag = false
            pressedLinkRange = layout.link(at: event.location)?.2
            if pressedLinkRange != nil {
                if linkState == nil { linkState = ChatLayerTextLinkState(node: self) }
                linkState?.beginPress(layout)
            } else {
                linkState?.clearPress()
            }
            if isSelectable && !event.modifiers.contains(.shift) { setSelection(NSRange(location: NSNotFound, length: 0)) }
            return true
        case .dragged:
            guard let start = selectionStart else { return false }
            guard abs(ceil(start.x) - ceil(event.location.x)) > 1 || abs(ceil(start.y) - round(event.location.y)) > 1 else { return true }
            didDrag = true
            if isSelectable {
                setSelection(layout.selectedRange(startPoint: start, currentPoint: event.location, byWord: event.clickCount == 2))
                layout.selectedRange.cursorAlignment = start.x > event.location.x ? .min(NSMaxRange(layout.selectedRange.range)) : .max(layout.selectedRange.range.location)
            }
            return true
        case .up:
            guard selectionStart != nil, event.button == 0 else { return false }
            let matchesPressedLink = linkState?.matchesPress(layout) == true
            linkState?.clearPress()
            defer { selectionStart = nil; pressedLinkRange = nil; suppressTextClick = false }
            if isSelectable && event.clickCount == 3 {
                layout.selectAll(at: event.location)
                layout.selectedRange.cursorAlignment = .max(layout.selectedRange.range.location)
                selectionChanged()
            } else if isSelectable && event.clickCount == 2 {
                layout.selectWord(at: event.location)
                layout.selectedRange.cursorAlignment = .max(layout.selectedRange.range.location)
                selectionChanged()
            } else if isSelectable && event.modifiers.contains(.shift), layout.selectedRange.hasSelectText {
                let index = layout.findCharacterIndex(at: event.location)
                if index >= 0 {
                    let range = layout.selectedRange.range
                    let start = min(range.location, index)
                    setSelection(NSRange(location: start, length: max(NSMaxRange(range), index) - start))
                }
            } else if !didDrag, matchesPressedLink, let link = layout.link(at: event.location), link.2 == pressedLinkRange {
                if let scene, let window = scene.window {
                    let rect = layer.convert(link.3, to: scene.root.layer)
                    if rect.width >= 1, rect.height >= 1, let image = ModalMorphTransition.controlImage(scene, rect: rect) {
                        ModalMorphContextSource.register(image: image, screenRect: window.convertToScreen(scene.convert(rect, to: nil)))
                    }
                }
                layout.interactions.processURL(link.0)
            } else if !didDrag, !suppressTextClick, event.clickCount == 1, !layout.selectedRange.hasSelectText, layer.bounds.contains(event.location) {
                _ = onTextClick?()
            }
            return true
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if (event.keyCode == 36 || event.keyCode == 49), event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty, let onTextClick {
            return onTextClick()
        }
        guard isSelectable, let layout = textLayout else { return false }
        if event.keyCode == 53 {
            setSelection(NSRange(location: NSNotFound, length: 0))
            return true
        }
        if event.modifierFlags.intersection([.shift, .command, .option, .control]) == .shift && layout.selectedRange.hasSelectText {
            if event.keyCode == 123 { layout.selectPrevChar(); selectionChanged(); return true }
            if event.keyCode == 124 { layout.selectNextChar(); selectionChanged(); return true }
        }
        return false
    }

    private func handleCommand(_ command: Selector) -> Bool {
        guard isSelectable, let layout = textLayout else { return false }
        if command == #selector(ChatLayerSceneView.selectAll(_:)) {
            setSelection(NSRange(location: 0, length: layout.attributedString.length))
            return true
        }
        if command == #selector(ChatLayerSceneView.copy(_:)) {
            guard layout.mayItems else { return false }
            if layout.interactions.copy?() == true { return true }
            let range = layout.selectedRange.range
            guard range.location != NSNotFound, range.length > 0, range.location <= layout.attributedString.length, range.length <= layout.attributedString.length - range.location else { return false }
            let text = layout.attributedString.attributedSubstring(from: range)
            if let copyText { copyText(text) }
            else if !layout.interactions.copyAttributedString(text) {
                if let copy = layout.interactions.copyToClipboard { copy(text.string) }
                else { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text.string, forType: .string) }
            }
            return true
        }
        return false
    }

    private func acceptsMenuRequest(_ state: ChatLayerTextMenuState, version: UInt64) -> Bool {
        guard menuState === state, state.isCurrent(version) else { return false }
        guard let scene, !scene.isHiddenOrHasHiddenAncestor, isVisible, isEffectivelyEnabled, textLayout?.mayItems == true, state.matchesWindow(scene.window), state.matches(textLayout) else {
            state.cancel()
            return false
        }
        return true
    }

    private func presentTextMenu(_ menu: ContextMenu, event: NSEvent, state: ChatLayerTextMenuState, version: UInt64) {
        guard acceptsMenuRequest(state, version: version) else { return }
        state.presentedMenu = menu
        menu.onClose = { [weak state, weak menu] in
            guard let state = state, let menu = menu, state.isCurrent(version), state.presentedMenu === menu else { return }
            state.cancel()
        }
        guard let scene else { return }
        AppMenu.show(menu: menu, event: event, for: scene)
    }

    @discardableResult func requestMenu(at location: NSPoint, event: NSEvent) -> Bool {
        let previousState = menuState
        let cancelledVersion = previousState?.cancel()
        guard menuState === previousState, previousState?.version == cancelledVersion else { return true }
        if let layout = textLayout, let scene, !scene.isHiddenOrHasHiddenAncestor, isVisible, isEffectivelyEnabled, layout.mayItems, layer.bounds.contains(location) {
            if !layout.selectedRange.hasSelectText && (!layout.alwaysStaticItems || layout.link(at: location) != nil) {
                layout.selectWord(at: location)
            }
            self.selectionChanged()
            if (layout.selectedRange.hasSelectText && isSelectable) || !layout.alwaysStaticItems {
                guard textLayout === layout, menuState === previousState, previousState?.version == cancelledVersion else { return true }
                let state: ChatLayerTextMenuState
                if let current = menuState {
                    state = current
                } else {
                    state = ChatLayerTextMenuState()
                    menuState = state
                }
                let version = state.begin(layout, window: scene.window)
                guard acceptsMenuRequest(state, version: version) else { return true }
                let link = layout.link(at: location)
                guard acceptsMenuRequest(state, version: version) else { return true }
                let items = layout.interactions.menuItems?(link?.1)
                guard acceptsMenuRequest(state, version: version) else { return true }
                let window = layout.interactions.topWindow?() ?? .single(nil)
                guard acceptsMenuRequest(state, version: version) else { return true }
                let disposable: Disposable
                if let items = items {
                    disposable = combineLatest(queue: .mainQueue(), items, window).start(next: { [weak self, weak state] items, topWindow in
                        guard let self = self, let state = state, self.acceptsMenuRequest(state, version: version) else { return }
                        let menu = ContextMenu()
                        for item in items { menu.addItem(item) }
                        menu.topWindow = topWindow
                        self.presentTextMenu(menu, event: event, state: state, version: version)
                    }, completed: { [weak state] in state?.finish(version) })
                } else {
                    disposable = (window |> deliverOnMainQueue).start(next: { [weak self, weak state, weak layout] topWindow in
                        guard let self = self, let state = state, let layout = layout, self.acceptsMenuRequest(state, version: version), let text = state.text else { return }
                        let link = layout.link(at: location)
                        let resolved = link.flatMap { layout.interactions.resolveLink($0.0) }
                        guard self.acceptsMenuRequest(state, version: version) else { return }
                        let title = link.map { layout.interactions.localizeLinkCopy($0.1) } ?? localizedString("Text.Copy")
                        guard self.acceptsMenuRequest(state, version: version) else { return }
                        let copyAction: () -> Void
                        if let resolved = resolved {
                            copyAction = { [weak self] in
                                guard let self = self else { return }
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.declareTypes([.string], owner: self)
                                pb.setString(resolved, forType: .string)
                            }
                        } else {
                            let selection = layout.selectedRange.range
                            let selectedText: NSAttributedString?
                            if selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
                               selection.location <= text.length, selection.length <= text.length - selection.location {
                                selectedText = text.attributedSubstring(from: selection)
                            } else {
                                selectedText = nil
                            }
                            let copySelection = layout.interactions.copy
                            let copyAttributedString = layout.interactions.copyAttributedString
                            let copyText = self.copyText
                            let copyToClipboard = layout.interactions.copyToClipboard
                            copyAction = { [weak self] in
                                guard let self = self else { return }
                                if copySelection?() != true, let selectedText = selectedText {
                                    if let copyText { copyText(selectedText); return }
                                    if copyAttributedString(selectedText) { return }
                                    if let copyToClipboard { copyToClipboard(selectedText.string); return }
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.declareTypes([.string], owner: self)
                                    pb.setString(selectedText.string, forType: .string)
                                }
                            }
                        }
                        let menu = ContextMenu()
                        let copy = ContextMenuItem(title, handler: copyAction, itemImage: TextView.context_copy_animation)
                        menu.addItem(copy)
                        if resolved == nil, let window = self.scene?.window as? Window {
                            if let translate = layout.interactions.translate?(self.effectiveMenuText(layout, snapshot: text), window) {
                                menu.addItem(translate)
                            }
                        }
                        menu.topWindow = topWindow
                        self.presentTextMenu(menu, event: event, state: state, version: version)
                    }, completed: { [weak state] in state?.finish(version) })
                }
                state.install(disposable, version: version)
                return true
            } else {
                layout.selectedRange.range = NSMakeRange(NSNotFound, 0)
                selectionChanged()
                return false
            }
        } else {
            return false
        }
    }

    private func effectiveMenuText(_ layout: TextViewLayout, snapshot: NSAttributedString) -> String {
        let range = layout.selectedRange.range
        if range.location != NSNotFound, range.location >= 0, range.length >= 0, range.location <= snapshot.length, range.length <= snapshot.length - range.location {
            return snapshot.attributedSubstring(from: range).string
        }
        return snapshot.string
    }

    deinit { menuState?.dispose() }
}
