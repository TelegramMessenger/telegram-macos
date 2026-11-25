import Cocoa
import TGUIKit
@testable import ChatLayerEngineBaseline

final class LayerChatTextRow: ChatTextRow {
    var textContentView: NSView? { layerText ?? text }
    override func bind(_ next: ChatMessageItem, animated: Bool = false) {
        textBindingVersion &+= 1
        let previous = item as? ChatMessageItem
        item = next
        updateText(for: next, previous: previous, animated: animated)
    }
    private func updateText(for item: ChatMessageItem, previous: ChatMessageItem?, animated: Bool) {
        let version = textBindingVersion
        let presentation = item.papercutLayout == nil ? ChatLayerMessageTextPresentation.simpleText(item.textLayout) : nil
        var useLayers = presentation != nil
        if useLayers, let text {
            if animated || text.hasSelectedText {
                useLayers = false
            } else {
                useLayers = text.updateForReusedContent(layout: item.textLayout)
                guard textBindingVersion == version else { return }
            }
        }
        if useLayers, let presentation {
            let current = layerText ?? ChatLayerMessageTextView(frame: textFrame(item))
            let identity = ChatLayerMessageTextView.Identity(messageId: item.stableId, accountId: ObjectIdentifier(item.textLayout.context))
            guard current.update(presentation, identity: identity), textBindingVersion == version else { return }
            let isNew = layerText !== current
            if let text {
                self.text = nil
                text.removeFromSuperview()
                guard textBindingVersion == version else { return }
            }
            layerText = current
            if isNew || !animated {
                let frame = textFrame(item)
                if current.frame != frame { current.frame = frame }
            }
            if isNew {
                addSubview(current)
                if animated { current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2) }
            }
        } else {
            if let layerText {
                guard layerText.prepareForRemoval(), textBindingVersion == version else { return }
                self.layerText = nil
                performSubviewRemoval(layerText, animated: animated)
                guard textBindingVersion == version else { return }
            }
            updateNativeText(for: item, previous: previous, animated: animated)
        }
    }

    private func updateNativeText(for item: ChatMessageItem, previous: ChatMessageItem?, animated: Bool) {
        let isEqual = previous?.stableId == item.stableId
            && previous?.textLayout.context === item.textLayout.context
            && previous?.textLayout.string == item.textLayout.string
        if item.papercutLayout != nil {
            if let view = self.text {
                performSubviewRemoval(view, animated: animated)
                self.text = nil
            }
        } else if isEqual, let view = self.text {
            view.update(layout: item.textLayout, animated: animated)
        } else if !animated, let view = self.text, view.updateForReusedContent(layout: item.textLayout) {
            let frame = textFrame(item)
            if view.frame != frame { view.frame = frame }
        } else {

            let appendingAnimationView = self.text?.appendingAnimationView

            if let view = self.text {
                performSubviewRemoval(view, animated: animated)
            }
            let current: FoldingTextView = FoldingTextView(frame: textFrame(item))
            current.update(layout: item.textLayout, animated: false, appendingAnimationView: appendingAnimationView)

            current.revealBlockAtIndex = { [weak self] index in
                if let item = self?.item as? ChatMessageItem {
                    item.revealBlockAtIndex(index)
                }
            }
            current.streamingVisibleHeightChanged = { [weak self] in
                guard let self, let item = self.item as? ChatMessageItem, let table = item.table else {
                    return
                }
                let oldHeight = item.height
                item.previousBlockWidth = 0
                _ = item.makeSize(item.width, oldWidth: 0)
                let newHeight = item.height
                if oldHeight != newHeight {
                    table.noteHeightOfRow(item.index, true)
                }
            }

            self.text = current
            addSubview(current)

            if animated, !item.textLayout.appendingAnimation {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        }
    }

    func firstTextBaseline(in view: NSView) -> NSPoint? {
        if let layerText { return layerText.firstTextBaseline(in: view) }
        guard let textView = text?.textViews.first, let line = textView.textLayout?.lines.first else { return nil }
        return textView.convert(NSPoint(x: line.frame.minX, y: line.frame.minY), to: view)
    }

    public override var selectableTextViews: [TextView] {
        var views:[TextView] = super.selectableTextViews + (text?.textViews ?? [])
        if let webpage = webpageContent {
            views += webpage.selectableTextViews
        }
        return views
    }

    override var textSelectionSources: ChatTextSelectionSources {
        let hasLayerCaptions = captionViews.contains(where: { $0.layerView != nil })
        guard layerText != nil || hasLayerCaptions else { return .views(selectableTextViews) }
        var sources: [ChatTextSelectionSource]
        if hasLayerCaptions, case let .mixed(values) = super.textSelectionSources {
            sources = values
        } else {
            sources = super.selectableTextViews.map(ChatTextSelectionSource.view)
        }
        if let layerText {
            sources.append(contentsOf: layerText.body.textNodes.map { .layer($0, layerText) })
        } else if let text {
            sources.append(contentsOf: text.textViews.map(ChatTextSelectionSource.view))
        }
        if let webpageContent { sources.append(contentsOf: webpageContent.selectableTextViews.map(ChatTextSelectionSource.view)) }
        return .mixed(sources)
    }
}
