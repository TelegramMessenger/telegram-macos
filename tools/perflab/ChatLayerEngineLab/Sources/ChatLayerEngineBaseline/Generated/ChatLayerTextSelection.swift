import Cocoa
import CoreText
import TGUIKit

extension ChatLayerSceneView: ChatBubbleCustomTextSelection {
    func clearBubbleSelection() {
        for id in selectableTextNodeIds {
            (node(id: id) as? ChatLayerTextNode)?.clearExternalSelection()
        }
    }

    func applyBubbleSelection(begin: NSPoint, end: NSPoint, isStartRow: Bool, isEndRow: Bool, reversed: Bool) -> [ChatBubbleSelectionFragment] {
        guard !isHiddenOrHasHiddenAncestor, begin.x.isFinite, begin.y.isFinite, end.x.isFinite, end.y.isFinite else {
            clearBubbleSelection()
            return []
        }
        var fragments: [ChatBubbleSelectionFragment] = []
        var seen = Set<AnyHashable>()
        let top = min(begin.y, end.y), bottom = max(begin.y, end.y)
        for (index, id) in selectableTextNodeIds.enumerated() where seen.insert(id).inserted {
            guard let text = node(id: id) as? ChatLayerTextNode else { continue }
            guard text.isSelectable, text.isVisible, text.isEffectivelyEnabled,
                  let layout = text.textLayout, layout.mayItems, !layout.lines.isEmpty else {
                text.clearExternalSelection()
                continue
            }
            let frame = text.layer.convert(text.layer.bounds, to: root.layer)
            guard bottom >= frame.minY, top <= frame.maxY else {
                text.clearExternalSelection()
                continue
            }
            let range: NSRange
            if top < frame.minY && bottom > frame.maxY {
                range = NSRange(location: 0, length: layout.attributedString.length)
            } else if top < frame.minY || bottom > frame.maxY {
                func endpoint(_ point: NSPoint) -> Int {
                    if point.y < frame.minY { return 0 }
                    if point.y > frame.maxY { return layout.attributedString.length }
                    let local = text.layer.convert(point, from: root.layer)
                    let line = layout.lines[layout.findIndex(location: local)]
                    let offset = CGFloat(CTLineGetPenOffsetForFlush(line.line, line.penFlush, Double(layout.layoutSize.width))) + line.frame.minX
                    let index = CTLineGetStringIndexForPosition(line.line, NSPoint(x: local.x - offset, y: 0))
                    guard index != kCFNotFound else { return line.range.location }
                    return min(layout.attributedString.length, max(0, index - CTLineGetStringRange(line.line).location + line.range.location))
                }
                let a = endpoint(begin), b = endpoint(end)
                range = NSRange(location: min(a, b), length: abs(b - a))
            } else {
                func local(_ point: NSPoint) -> NSPoint {
                    if point.y < frame.minY { return .zero }
                    if point.y > frame.maxY { return NSPoint(x: layout.layoutSize.width, y: .greatestFiniteMagnitude) }
                    var value = text.layer.convert(point, from: root.layer)
                    if value.x == -1 { value.x = value.x.nextDown }
                    if value.y == -1 { value.y = value.y.nextDown }
                    return value
                }
                range = layout.selectedRange(startPoint: local(begin), currentPoint: local(end))
            }
            guard range.location != NSNotFound, range.length > 0 else {
                text.clearExternalSelection()
                continue
            }
            text.setExternalSelection(range)
            let selected = layout.selectedRange.range
            guard text.scene === self, text.textLayout === layout, text.isVisible, text.isEffectivelyEnabled, layout.mayItems,
                  selected.location != NSNotFound, selected.length > 0, selected.location <= layout.attributedString.length,
                  selected.length <= layout.attributedString.length - selected.location else { continue }
            fragments.append(ChatBubbleSelectionFragment(attributedString: layout.attributedString, range: selected, index: index))
        }
        guard fragments.count > 1 else { return fragments }
        let text = NSMutableAttributedString()
        var endIndex = 0
        for fragment in fragments {
            if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
            endIndex = text.length + NSMaxRange(fragment.range)
            text.append(fragment.attributedString)
        }
        let startIndex = fragments[0].range.location
        return [ChatBubbleSelectionFragment(attributedString: text, range: NSRange(location: startIndex, length: endIndex - startIndex), index: 0)]
    }
}
