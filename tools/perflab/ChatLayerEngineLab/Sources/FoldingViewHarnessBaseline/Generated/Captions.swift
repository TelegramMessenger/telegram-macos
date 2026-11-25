import Cocoa
import TGUIKit
@testable import ChatLayerEngineBaseline

final class ReplacementCaptionRow: CaptionRowEnvironment {
    var captionViews: [CaptionView] = []
    override var views: [FoldingTextView] { captionViews.map { $0.view } }
    override var ids: [UInt32] { captionViews.map { $0.id } }
    override var shimmers: [Bool] { captionViews.map { $0.shim } }
    class CaptionView {
        let id: UInt32
        let shim: Bool
        let view: FoldingTextView
        init(id: UInt32, shim: Bool, view: FoldingTextView) {
            self.id = id
            self.shim = shim
            self.view = view
        }
        func isSame(to other: ChatRowItem.RowCaption) -> Bool {
            return self.id == other.id && self.view.string == other.layout.string
        }

        deinit {
        }
    }

    override func fillCaption(_ item:ChatRowItem, animated: Bool) -> Void {

        var removeIndexes:[Int] = []
        for (i, view) in captionViews.enumerated() {
            if !item.captionLayouts.contains(where: { view.isSame(to: $0) }) {
                let captionView = view.view
                performSubviewRemoval(captionView, animated: animated)
                removeIndexes.append(i)
            }
        }

        for index in removeIndexes.reversed() {
            _ = captionViews.remove(at: index)
        }
        for (i, layout) in item.captionLayouts.enumerated() {
            var view = captionViews.first(where: { $0.isSame(to: layout) })
            let messageId = layout.message.id
            if view == nil {
                view = CaptionView(id: layout.id, shim: layout.isLoading, view: FoldingTextView(frame: .zero))
                view?.view.revealBlockAtIndex = { [weak self] index in
                    if let item = self?.item as? ChatRowItem {
                        item.revealBlockAtIndex(index, messageId: messageId)
                    }
                }
                rowView.addSubview(view!.view, positioned: .below, relativeTo: contentView)
                view?.view.frame = captionFrame(item, caption: layout)
                captionViews.append(view!)
                if animated {
                    view?.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            if let index = captionViews.firstIndex(where: { $0.isSame(to: layout) }), index != i {
                captionViews.move(at: index, to: i)
            }
            view?.view.update(layout: layout.layout, animated: animated)
        }
    }
}
final class ReusedCaptionRow: CaptionRowEnvironment {
    var captionViews: [CaptionView] = []
    override var views: [FoldingTextView] { captionViews.map { $0.view } }
    override var ids: [UInt32] { captionViews.map { $0.id } }
    override var shimmers: [Bool] { captionViews.map { $0.shim } }
    class CaptionView {
        let id: UInt32
        let shim: Bool
        let view: FoldingTextView
        fileprivate var messageId: MessageId?
        fileprivate weak var context: (any AccountContextProtocol)?
        init(id: UInt32, shim: Bool, view: FoldingTextView) {
            self.id = id
            self.shim = shim
            self.view = view
        }
        func isSame(to other: ChatRowItem.RowCaption) -> Bool {
            return self.id == other.id && messageId == other.message.id
                && context === other.layout.context && self.view.string == other.layout.string
        }

        deinit {
        }
    }

    override func fillCaption(_ item: ChatRowItem, animated: Bool) {
        guard !captionViews.isEmpty || !item.captionLayouts.isEmpty else { return }
        let previous = captionViews
        var used = Array(repeating: false, count: previous.count)
        var next = Array<CaptionView?>(repeating: nil, count: item.captionLayouts.count)

        for (index, layout) in item.captionLayouts.enumerated() {
            if let match = previous.indices.first(where: { !used[$0] && previous[$0].isSame(to: layout) }) {
                next[index] = previous[match]
                used[match] = true
            }
        }

        for (index, layout) in item.captionLayouts.enumerated() {
            var current = next[index]
            var didReuseContent = false
            if current == nil, !animated {
                let matchingId = previous.indices.first(where: { !used[$0] && previous[$0].id == layout.id })
                if let match = matchingId, previous[match].view.updateForReusedContent(layout: layout.layout) {
                    current = previous[match]
                    used[match] = true
                    didReuseContent = true
                } else if let match = previous.indices.first(where: {
                    !used[$0] && $0 != matchingId && previous[$0].view.updateForReusedContent(layout: layout.layout)
                }) {
                    current = previous[match]
                    used[match] = true
                    didReuseContent = true
                }
            }

            let isNewView = current == nil
            let needsIdentity = current == nil || current?.id != layout.id || current?.shim != layout.isLoading
            if needsIdentity {
                let view = current?.view ?? FoldingTextView(frame: .zero)
                current = CaptionView(id: layout.id, shim: layout.isLoading, view: view)
                view.revealBlockAtIndex = { [weak self, weak current] blockIndex in
                    if let item = self?.item as? ChatRowItem, let messageId = current?.messageId {
                        item.revealBlockAtIndex(blockIndex, messageId: messageId)
                    }
                }
            }
            guard let current else { continue }
            current.messageId = layout.message.id
            current.context = layout.layout.context
            if isNewView {
                rowView.addSubview(current.view, positioned: .below, relativeTo: contentView)
                current.view.frame = captionFrame(item, caption: layout)
                if animated {
                    current.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            } else if didReuseContent {
                let frame = captionFrame(item, caption: layout)
                if current.view.frame != frame { current.view.frame = frame }
            }
            if !didReuseContent {
                current.view.update(layout: layout.layout, animated: animated)
            }
            next[index] = current
        }
        for index in previous.indices where !used[index] {
            performSubviewRemoval(previous[index].view, animated: animated)
        }
        captionViews = next.compactMap { $0 }
    }
}
class LayerCaptionRow: CaptionRowEnvironment {
    var captionViews: [CaptionView] = []
    private var captionBindingState: CaptionBindingState?
    override var views: [FoldingTextView] { captionViews.compactMap { $0.nativeView } }
    override var contentViews: [View] { captionViews.map { $0.view } }
    override var ids: [UInt32] { captionViews.map { $0.id } }
    override var shimmers: [Bool] { captionViews.map { $0.shim } }
    class CaptionView {
        private(set) var id: UInt32
        private(set) var shim: Bool
        let view: View
        fileprivate var messageId: MessageId?
        fileprivate weak var context: (any AccountContextProtocol)?
        fileprivate var layout: FoldingTextLayout?
        var nativeView: FoldingTextView? { view as? FoldingTextView }
        var layerView: ChatLayerMessageTextView? { view as? ChatLayerMessageTextView }

        init(id: UInt32, shim: Bool, view: View) {
            self.id = id
            self.shim = shim
            self.view = view
        }

        func isSame(to other: ChatRowItem.RowCaption) -> Bool {
            return id == other.id && messageId == other.message.id
                && context === other.layout.context && layout?.string == other.layout.string
        }

        fileprivate func canKeepRenderer(for caption: ChatRowItem.RowCaption, presentation: ChatLayerMessageTextPresentation?, animated: Bool) -> Bool {
            if layerView != nil { return presentation != nil }
            guard presentation != nil, let nativeView else { return true }
            return animated || nativeView.hasSelectedText || !nativeView.updateForReusedContent(layout: caption.layout)
        }

        fileprivate func reuse(_ caption: ChatRowItem.RowCaption, presentation: ChatLayerMessageTextPresentation?) -> Bool {
            guard context === caption.layout.context else { return false }
            if let nativeView {
                guard presentation == nil, nativeView.updateForReusedContent(layout: caption.layout) else { return false }
            } else if let layerView, let presentation {
                guard !layerView.hasActiveInput, !contextMenuOnScreen(), layerView.layer?.animationKeys()?.isEmpty != false,
                      !layerView.body.textNodes.contains(where: { $0.hasExternalTextSelection }),
                      layerView.update(presentation, identity: .init(messageId: caption.message.id, accountId: ObjectIdentifier(caption.layout.context))) else { return false }
            } else {
                return false
            }
            updateIdentity(caption)
            return true
        }

        fileprivate func updateIdentity(_ caption: ChatRowItem.RowCaption) {
            id = caption.id
            shim = caption.isLoading
            messageId = caption.message.id
            context = caption.layout.context
            layout = caption.layout
        }

        fileprivate func update(_ caption: ChatRowItem.RowCaption, presentation: ChatLayerMessageTextPresentation?, animated: Bool) {
            updateIdentity(caption)
            if let nativeView {
                nativeView.update(layout: caption.layout, animated: animated)
            } else if let layerView, let presentation {
                layerView.update(presentation, identity: .init(messageId: caption.message.id, accountId: ObjectIdentifier(caption.layout.context)))
            }
        }

        fileprivate func prepareForRemoval() {
            layerView?.prepareForRemoval()
            view.isEventLess = true
        }

        func clickInContent(point: NSPoint) -> Bool {
            return nativeView?.clickInContent(point: point) ?? layerView?.clickInContent(point: point) ?? false
        }

        func highlight(text: String, color: NSColor, range: NSRange?) {
            if let nativeView {
                nativeView.highlight(text: text, color: color, range: range)
            } else if let layerView, let layout {
                layerView.body.highlight(text: text, color: color, range: range, in: layout)
            }
        }
    }

    override func fillCaption(_ item: ChatRowItem, animated: Bool) {
        if let state = captionBindingState, state.isUpdating {
            state.pending = (item, animated)
            return
        }
        guard !captionViews.isEmpty || !item.captionLayouts.isEmpty else { return }
        let state = captionBindingState ?? CaptionBindingState()
        captionBindingState = state
        state.isUpdating = true
        var nextItem = item
        var nextAnimated = animated
        while true {
            state.pending = nil
            updateCaptions(nextItem, animated: nextAnimated)
            guard let pending = state.pending else { break }
            nextItem = pending.0
            nextAnimated = pending.1
        }
        state.isUpdating = false
        if captionViews.isEmpty { captionBindingState = nil }
    }

    private final class CaptionBindingState {
        var pending: (ChatRowItem, Bool)?
        var isUpdating = false
    }

    private func updateCaptions(_ item: ChatRowItem, animated: Bool) {
        let previous = captionViews
        let presentations = item.captionLayouts.map { ChatLayerMessageTextPresentation.simpleText($0.layout) }
        if previous.count == item.captionLayouts.count, previous.indices.allSatisfy({
            previous[$0].isSame(to: item.captionLayouts[$0]) && (previous[$0].layerView != nil) == (presentations[$0] != nil)
        }) {
            for index in previous.indices {
                previous[index].update(item.captionLayouts[index], presentation: presentations[index], animated: animated)
            }
            return
        }
        if !animated, previous.count == 1, item.captionLayouts.count == 1,
           previous[0].reuse(item.captionLayouts[0], presentation: presentations[0]) {
            let frame = captionFrame(item, caption: item.captionLayouts[0])
            if previous[0].view.frame != frame { previous[0].view.frame = frame }
            return
        }
        var used = Array(repeating: false, count: previous.count)
        var next = Array<CaptionView?>(repeating: nil, count: item.captionLayouts.count)

        for (index, caption) in item.captionLayouts.enumerated() {
            if let match = previous.indices.first(where: { !used[$0] && previous[$0].isSame(to: caption) }) {
                if previous[match].canKeepRenderer(for: caption, presentation: presentations[index], animated: animated) {
                    next[index] = previous[match]
                    used[match] = true
                } else if let layout = previous[match].layout {
                    let selections = layout.blocks.map { ($0.text.attributedString.string, $0.text.selectedRange) }
                    used[match] = true
                    previous[match].prepareForRemoval()
                    performSubviewRemoval(previous[match].view, animated: animated)
                    for (old, new) in zip(selections, caption.layout.blocks)
                    where old.0 == new.text.attributedString.string && new.text.mayItems && new.text.selectedRange.range.location == NSNotFound {
                        new.text.selectedRange = old.1
                    }
                }
            }
        }

        for (index, caption) in item.captionLayouts.enumerated() {
            let presentation = presentations[index]
            var current = next[index]
            var didReuseContent = false
            if current == nil, !animated {
                let matchingId = previous.indices.first(where: { !used[$0] && previous[$0].id == caption.id })
                if let match = matchingId, previous[match].reuse(caption, presentation: presentation) {
                    current = previous[match]
                    used[match] = true
                    didReuseContent = true
                } else if let match = previous.indices.first(where: {
                    !used[$0] && $0 != matchingId && previous[$0].reuse(caption, presentation: presentation)
                }) {
                    current = previous[match]
                    used[match] = true
                    didReuseContent = true
                }
            }

            let isNewView = current == nil
            if current == nil {
                let view: View = presentation == nil ? FoldingTextView(frame: .zero) : ChatLayerMessageTextView(frame: .zero)
                current = CaptionView(id: caption.id, shim: caption.isLoading, view: view)
                current?.nativeView?.revealBlockAtIndex = { [weak self, weak current] blockIndex in
                    if let item = self?.item as? ChatRowItem, let messageId = current?.messageId {
                        item.revealBlockAtIndex(blockIndex, messageId: messageId)
                    }
                }
            }
            guard let current else { continue }
            if isNewView {
                rowView.addSubview(current.view, positioned: .below, relativeTo: contentView)
                current.view.frame = captionFrame(item, caption: caption)
                if animated { current.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2) }
            } else if didReuseContent {
                let frame = captionFrame(item, caption: caption)
                if current.view.frame != frame { current.view.frame = frame }
            }
            if !didReuseContent { current.update(caption, presentation: presentation, animated: animated) }
            next[index] = current
        }
        captionViews = next.compactMap { $0 }
        for index in previous.indices where !used[index] {
            previous[index].prepareForRemoval()
            performSubviewRemoval(previous[index].view, animated: animated)
        }
    }

    override var textSelectionSources: ChatTextSelectionSources {
        guard captionViews.contains(where: { $0.layerView != nil }) else { return .views(selectableTextViews) }
        var sources: [ChatTextSelectionSource] = []
        for caption in captionViews {
            if let layer = caption.layerView {
                sources.append(contentsOf: layer.body.textNodes.map { .layer($0, layer) })
            } else if let native = caption.nativeView {
                sources.append(contentsOf: native.textViews.map(ChatTextSelectionSource.view))
            }
        }
        if let text = factCheckView?.textView.textView { sources.append(.view(text)) }
        return .mixed(sources)
    }

    override var selectableTextViews: [TextView] {
        var views = captionViews.flatMap { $0.nativeView?.textViews ?? [] }
        if let text = factCheckView?.textView.textView { views.append(text) }
        return views
    }

    func clickInContent(point: NSPoint) -> Bool {
        guard let item = item as? ChatRowItem, let _ = item.captionLayouts.first?.layout, let captionView = captionViews.first else {return false}
        return captionView.clickInContent(point: captionView.view.convert(point, from: self))
    }
}

extension ChatLayerMessageTextNode {
    func highlight(text: String, color: NSColor, range: NSRange? = nil, in layout: FoldingTextLayout) {
        guard textNodes.count == layout.blocks.count, zip(textNodes, layout.blocks).allSatisfy({ $0.textLayout === $1.text }) else { return }
        let string = layout.attributedString.string as NSString
        if let range, range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= string.length, range.length <= string.length - range.location, string.substring(with: range) == text {
            var highlighted = false
            for (node, pair) in zip(textNodes, zip(layout.blocks, layout.blockRanges)) {
                let (block, blockRange) = pair
                if let intersection = blockRange.intersection(range) {
                    let localRange = NSRange(location: intersection.location - blockRange.location, length: intersection.length)
                    let localString = block.text.attributedString.string as NSString
                    guard localRange.location >= 0, localRange.location <= localString.length, localRange.length <= localString.length - localRange.location else { continue }
                    node.highlight(text: localString.substring(with: localRange), color: color, range: localRange)
                    highlighted = true
                }
            }
            if highlighted { return }
        }
        for node in textNodes {
            node.highlight(text: text, color: color)
        }
    }
}

final class ChatInvoiceItemCaptionSelection: LayerCaptionRow {
    let textView = TextView()
    final class Content { let titleView = CaptionFactCheck.Content() }
    let contentNode = Content()
    override var textSelectionSources: ChatTextSelectionSources {
        return .views(selectableTextViews)
    }
    override var selectableTextViews: [TextView] {
        return [textView]
    }
}

final class ChatPollItemCaptionSelection: LayerCaptionRow {
    let textView = TextView()
    final class Content { let titleView = CaptionFactCheck.Content() }
    let contentNode = Content()
    override var textSelectionSources: ChatTextSelectionSources {
        return .views(selectableTextViews)
    }
    override var selectableTextViews: [TextView] {
        return [contentNode.titleView.textView]
    }
}

final class ChatTodoItemCaptionSelection: LayerCaptionRow {
    let textView = TextView()
    final class Content { let titleView = CaptionFactCheck.Content() }
    let contentNode = Content()
    override var textSelectionSources: ChatTextSelectionSources {
        return .views(selectableTextViews)
    }
    override var selectableTextViews: [TextView] {
        return [contentNode.titleView.textView]
    }
}
