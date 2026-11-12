import Cocoa
import TGUIKit
import SwiftSignalKit

final class ChatLayerTextLinkState: NSObject, NSViewToolTipOwner, Disposable {
    var toolTip: String?
    private weak var node: ChatLayerTextNode?
    private weak var toolTipScene: ChatLayerSceneView?
    private var toolTipTags: [NSView.ToolTipTag] = []
    private var toolTipRects: [NSRect] = []
    private var sourceToolTipRects: [NSRect] = []
    private var geometryVersion: UInt64 = 0
    private var toolTipsRemoved = false
    private var version: UInt64 = 0
    private var timer: SwiftSignalKit.Timer?
    private var preview: Disposable?
    private var pressedText: NSAttributedString?
    private var text: NSAttributedString?
    private weak var layout: TextViewLayout?
    private var range = NSRange(location: NSNotFound, length: 0)
    private var windowId: ObjectIdentifier?

    init(node: ChatLayerTextNode) { self.node = node }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let node, let scene = node.scene, view === scene, !scene.isHiddenOrHasHiddenAncestor, node.isVisible, node.isEffectivelyEnabled else { return "" }
        if let toolTip { return toolTip }
        guard let layout = node.textLayout,
              let link = layout.link(at: node.layer.convert(point, from: scene.root.layer)),
              let resolved = layout.interactions.resolveLink(link.0)?.removingPercentEncoding else { return "" }
        return resolved.prefixWithDots(70)
    }

    func synchronizeToolTips(force: Bool) {
        guard let node, let scene = node.scene, let layout = node.textLayout else {
            removeToolTips()
            return
        }
        let sourceRects = toolTip == nil ? layout.toolTipRects : [node.layer.bounds]
        if sourceRects.isEmpty {
            if toolTipScene != nil { removeToolTips() }
            return
        }
        if toolTipScene !== scene {
            removeToolTips()
            toolTipScene = scene
            scene.registerToolTipNode(node)
        }
        guard geometryVersion != scene.geometryVersion || sourceToolTipRects != sourceRects || (force && toolTipsRemoved) else { return }
        geometryVersion = scene.geometryVersion
        sourceToolTipRects = sourceRects
        let rects = sourceRects.map { node.layer.convert($0, to: scene.root.layer) }
        guard toolTipRects != rects || (force && toolTipsRemoved) else { return }
        for tag in toolTipTags { scene.removeToolTip(tag) }
        toolTipTags.removeAll(keepingCapacity: true)
        toolTipRects = rects
        toolTipsRemoved = false
        for rect in rects { toolTipTags.append(scene.addToolTip(rect, owner: self, userData: nil)) }
    }

    func didRemoveToolTips() {
        toolTipTags.removeAll(keepingCapacity: true)
        toolTipsRemoved = true
    }

    private func removeToolTips() {
        let scene = toolTipScene, tags = toolTipTags
        toolTipScene = nil
        toolTipTags = []
        toolTipRects = []
        sourceToolTipRects = []
        toolTipsRemoved = false
        if let node { scene?.unregisterToolTipNode(node) }
        for tag in tags { scene?.removeToolTip(tag) }
    }

    func beginPress(_ layout: TextViewLayout) {
        pressedText = layout.attributedString.copy() as? NSAttributedString
    }

    func matchesPress(_ layout: TextViewLayout?) -> Bool {
        guard let pressedText, let layout else { return false }
        return pressedText === layout.attributedString || pressedText.isEqual(to: layout.attributedString)
    }

    func clearPress() { pressedText = nil }

    func cancelIfInvalid(_ next: TextViewLayout?) {
        if range.location != NSNotFound, layout !== next || !matches(next) { cancel() }
    }

    func cancelIfWindowChanged() {
        if range.location != NSNotFound, windowId != node?.scene?.window.map(ObjectIdentifier.init) { cancel() }
    }

    private func matches(_ layout: TextViewLayout?) -> Bool {
        guard let text, let layout else { return false }
        return text === layout.attributedString || text.isEqual(to: layout.attributedString)
    }

    func hover(link: Any, range: NSRange, layout: TextViewLayout) {
        guard let node, node.textLayout === layout, let scene = node.scene,
              node.isVisible, node.isEffectivelyEnabled, !scene.isHiddenOrHasHiddenAncestor else { return }
        if text === layout.attributedString, self.range == range { return }
        if let text, self.range.location != NSNotFound, self.range.location < text.length,
           let previous = text.attribute(.link, at: self.range.location, effectiveRange: nil) {
            if let previous = previous as? String, let link = link as? String, previous == link { return }
            if (previous as AnyObject) === (link as AnyObject) { return }
        }
        let version = cancel()
        guard self.version == version, node.textLayout === layout, node.scene === scene else { return }
        self.layout = layout
        self.range = range
        text = layout.attributedString.copy() as? NSAttributedString
        windowId = scene.window.map(ObjectIdentifier.init)
        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: false, completion: { [weak self, weak node, weak layout, weak scene] timer in
            guard let self, let node, let layout, let scene, self.version == version,
                  self.timer === timer, node.textLayout === layout else { return }
            guard node.scene === scene, node.isVisible, node.isEffectivelyEnabled, !scene.isHiddenOrHasHiddenAncestor,
                  self.windowId == scene.window.map(ObjectIdentifier.init), self.matches(layout), !contextMenuOnScreen() else {
                self.cancel()
                return
            }
            let disposable = layout.interactions.longHoverOnLink?(link, scene)
            guard self.version == version, self.timer === timer, node.textLayout === layout,
                  node.scene === scene, self.matches(layout) else {
                if self.version == version { self.cancel() }
                disposable?.dispose()
                return
            }
            self.preview = disposable
            self.timer = nil
        }, queue: .mainQueue())
        self.timer = timer
        timer.start()
    }

    @discardableResult
    func cancel() -> UInt64 {
        version &+= 1
        let version = version
        guard range.location != NSNotFound else { return version }
        let timer = self.timer, preview = self.preview, text = self.text
        self.timer = nil
        self.preview = nil
        self.text = nil
        layout = nil
        range = NSRange(location: NSNotFound, length: 0)
        windowId = nil
        timer?.invalidate()
        preview?.dispose()
        withExtendedLifetime(text) {}
        return version
    }

    func detach() {
        clearPress()
        let version = cancel()
        guard self.version == version else { return }
        removeToolTips()
    }

    func dispose() { detach() }
    deinit { dispose() }
}
