import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore

public struct SelectContainer {
    public let text:NSAttributedString
    public let range:NSRange
    public let index: Int
    public let header:String?
    public var richText: [RichText]? = nil
}
public class SelectManager : NSResponder {
    fileprivate weak var chatInteraction: ChatInteraction?
    public override init() {
        super.init()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate final class RangeEntry {
        let stableId: AnyHashable
        weak var textView: TextView?
        weak var layout: TextViewLayout?
        var container: SelectContainer
        init(stableId: AnyHashable, textView: TextView?, layout: TextViewLayout?, container: SelectContainer) {
            self.stableId = stableId
            self.textView = textView
            self.layout = layout
            self.container = container
        }
        var effectiveLayout: TextViewLayout? {
            return self.layout ?? self.textView?.textLayout
        }
    }

    private var ranges:Atomic<[RangeEntry]> = Atomic(value: [])

    fileprivate final class BubbleSourceBox {
        weak var source: AnyObject?
        let isRichText: Bool
        init(_ source: AnyObject?, isRichText: Bool? = nil) {
            self.source = source
            self.isRichText = isRichText ?? (source is ChatRichTextRowView)
        }
    }

    private final class SelectionOrder {
        var positions: [AnyHashable: Int] = [:]
    }

    private let selectionOrder = Atomic(value: SelectionOrder())

    @discardableResult private func registerSelection(_ stableId: AnyHashable) -> Bool {
        var inserted = false
        _ = selectionOrder.modify { order in
            if order.positions[stableId] == nil {
                order.positions[stableId] = order.positions.count
                inserted = true
            }
            return order
        }
        return inserted
    }
    private var bubbleRanges: Atomic<[(AnyHashable, BubbleSourceBox, SelectContainer)]> = Atomic(value: [])

    public func addBubble(fragment: ChatBubbleSelectionFragment, source: ChatBubbleCustomTextSelection, header: String?, stableId: AnyHashable) {
        let isNewRow = registerSelection(stableId)
        _ = bubbleRanges.modify { entries in
            var entries = entries
            let container = SelectContainer(text: fragment.attributedString, range: fragment.range, index: fragment.index, header: header, richText: fragment.richText)
            if !isNewRow { entries.removeAll(where: { $0.0 == stableId && $0.2.index == fragment.index }) }
            entries.append((stableId, BubbleSourceBox(source), container))
            return entries
        }
    }

    public func add(range:NSRange, textView: TextView?, layout: TextViewLayout?, text: NSAttributedString, header: String?, stableId: AnyHashable, index: Int) {

        let isNewRow = registerSelection(stableId)
        _ = ranges.modify { ranges in
            var ranges = ranges
            let value = RangeEntry(stableId: stableId, textView: textView, layout: layout, container: SelectContainer(text: text, range: range, index: index, header: header))
            if !isNewRow, let index = ranges.firstIndex(where: { $0.stableId == stableId }) {
                ranges.insert(value, at: index)
            } else {
                ranges.append(value)
            }
            return ranges
        }
    }

    fileprivate func currentRanges() -> [AnyHashable: [RangeEntry]] {
        return ranges.with { ranges in
            var result: [AnyHashable: [RangeEntry]] = [:]
            for entry in ranges {
                result[entry.stableId, default: []].append(entry)
            }
            for (stableId, entries) in result {
                result[stableId] = entries.sorted(by: { $0.container.index < $1.container.index })
            }
            return result
        }
    }

    fileprivate func currentBubbleRanges() -> [AnyHashable: [(AnyHashable, BubbleSourceBox, SelectContainer)]] {
        return bubbleRanges.with { Dictionary(grouping: $0, by: { $0.0 }) }
    }

    fileprivate func restoreBubbleRanges(_ entries: [(AnyHashable, BubbleSourceBox, SelectContainer)]) {
        for entry in entries { registerSelection(entry.0) }
        _ = bubbleRanges.modify { current in
            var current = current
            for entry in entries {
                current.removeAll(where: { $0.0 == entry.0 && $0.2.index == entry.2.index })
                current.append((entry.0, BubbleSourceBox(nil, isRichText: entry.1.isRichText), entry.2))
            }
            return current
        }
    }

    public func removeAll() {
        _ = selectionOrder.modify { order in
            order.positions.removeAll()
            return order
        }
        _ = ranges.modify { ranges in
            for selection in ranges {
                let layout = selection.effectiveLayout
                if let value = selection.textView {
                    if layout?.selectedRange.range.location != NSNotFound {
                        value.selectionWasCleared = true
                    }
                    value.canBeResponder = true
                    value.setNeedsDisplay()
                }
                layout?.clearSelect()
            }
            return []
        }
        var sourcesToClear: [ChatBubbleCustomTextSelection] = []
        var seenSources = Set<ObjectIdentifier>()
        _ = bubbleRanges.modify { entries in
            for entry in entries {
                if let source = entry.1.source as? ChatBubbleCustomTextSelection,
                   seenSources.insert(ObjectIdentifier(source)).inserted {
                    sourcesToClear.append(source)
                }
            }
            return []
        }
        for source in sourcesToClear {
            source.clearBubbleSelection()
        }
    }
    
    public func remove(for id:Int64) {
        
    }
    public var isEmpty:Bool {
        return ranges.with { $0.isEmpty } && bubbleRanges.with { $0.isEmpty }
    }
    
    
    public var selectedText: NSAttributedString {
        let string:NSMutableAttributedString = NSMutableAttributedString()

        var combined: [(AnyHashable, SelectContainer)] = []
        ranges.with { for r in $0 { combined.append((r.stableId, r.container)) } }
        bubbleRanges.with { for r in $0 { combined.append((r.0, r.2)) } }

        let positions = selectionOrder.with { $0.positions }
        combined.sort {
            let lhs = positions[$0.0] ?? Int.max
            let rhs = positions[$1.0] ?? Int.max
            if lhs != rhs { return lhs < rhs }
            return $0.1.index > $1.1.index
        }
        let addHeaders = positions.count > 1

        var stableId: AnyHashable? = combined.last?.0
        for i in stride(from: combined.count - 1, to: -1, by: -1) {
            let container = combined[i].1

            if stableId != combined[i].0 {
                _ = string.append(string: "\n\n", color: nil, font: .normal(.text))
            }

            if let header = container.header, combined.count > 1, addHeaders {
                _ = string.append(string: header + "\n", color: nil, font: .normal(.text))
            }

            if container.range.location >= 0, container.range.location <= container.text.length, container.range.length >= 0, container.range.length <= container.text.length - container.range.location {
                if container.range.location != 0, combined.count > 1, addHeaders {
                    _ = string.append(string: "...", color: nil, font: .normal(.text))
                }
                string.append(container.text.attributedSubstring(from: container.range).trimmed)
                if container.range.location + container.range.length != container.text.length, combined.count > 1, addHeaders {
                    _ = string.append(string: "...", color: nil, font: .normal(.text))
                }
            }
            let endsInNewline = string.length > 0 && string.mutableString.character(at: string.length - 1) == 10 && (string.length == 1 || string.mutableString.character(at: string.length - 2) != 13)
            if i != 0, !endsInNewline {
                string.append(string: "\n")
            }

            stableId = combined[i].0
        }
        return string
    }
    
}

func preserveBubbleSelection(_ manager: SelectManager, stableId: AnyHashable) -> () -> Void {
    let snapshot = manager.currentBubbleRanges()[stableId] ?? []
    return { manager.restoreBubbleRanges(snapshot) }
}
func bubbleSelectionSummary(_ manager: SelectManager, stableId: AnyHashable) -> [(index: Int, hasSource: Bool, rich: Bool)] {
    return (manager.currentBubbleRanges()[stableId] ?? []).map { ($0.2.index, $0.1.source != nil, $0.1.isRichText) }
}

public class LegacySelectManager : NSResponder {
    fileprivate weak var chatInteraction: ChatInteraction?
    public override init() {
        super.init()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate final class RangeEntry {
        let stableId: AnyHashable
        weak var textView: TextView?
        weak var layout: TextViewLayout?
        var container: SelectContainer
        init(stableId: AnyHashable, textView: TextView?, layout: TextViewLayout?, container: SelectContainer) {
            self.stableId = stableId
            self.textView = textView
            self.layout = layout
            self.container = container
        }
        var effectiveLayout: TextViewLayout? {
            return self.layout ?? self.textView?.textLayout
        }
    }

    private var ranges:Atomic<[RangeEntry]> = Atomic(value: [])

    private final class BubbleSourceBox {
        weak var source: AnyObject?
        init(_ source: AnyObject) { self.source = source }
    }
    private var bubbleRanges: Atomic<[(AnyHashable, BubbleSourceBox, SelectContainer)]> = Atomic(value: [])

    public func addBubble(fragment: ChatBubbleSelectionFragment, source: ChatBubbleCustomTextSelection, header: String?, stableId: AnyHashable) {
        _ = bubbleRanges.modify { entries in
            var entries = entries
            let container = SelectContainer(text: fragment.attributedString, range: fragment.range, index: fragment.index, header: header)
            entries.removeAll(where: { $0.0 == stableId && $0.2.index == fragment.index })
            entries.append((stableId, BubbleSourceBox(source), container))
            return entries
        }
    }

    public func add(range:NSRange, textView: TextView?, layout: TextViewLayout?, text: NSAttributedString, header: String?, stableId: AnyHashable, index: Int) {

        _ = ranges.modify { ranges in
            var ranges = ranges
            let value = RangeEntry(stableId: stableId, textView: textView, layout: layout, container: SelectContainer(text: text, range: range, index: index, header: header))
            if let index = ranges.firstIndex(where: { $0.stableId == stableId }) {
                ranges.insert(value, at: index)
            } else {
                ranges.append(value)
            }
            return ranges
        }
    }

    fileprivate func currentRanges() -> [AnyHashable: [RangeEntry]] {
        return ranges.with { ranges in
            var result: [AnyHashable: [RangeEntry]] = [:]
            for entry in ranges {
                result[entry.stableId, default: []].append(entry)
            }
            for (stableId, entries) in result {
                result[stableId] = entries.sorted(by: { $0.container.index < $1.container.index })
            }
            return result
        }
    }

    public func removeAll() {
        _ = ranges.modify { ranges in
            for selection in ranges {
                let layout = selection.effectiveLayout
                if let value = selection.textView {
                    if layout?.selectedRange.range.location != NSNotFound {
                        value.selectionWasCleared = true
                    }
                    value.canBeResponder = true
                    value.setNeedsDisplay()
                }
                layout?.clearSelect()
            }
            return []
        }
        var sourcesToClear: [ChatBubbleCustomTextSelection] = []
        _ = bubbleRanges.modify { entries in
            for entry in entries {
                if let source = entry.1.source as? ChatBubbleCustomTextSelection,
                   !sourcesToClear.contains(where: { $0 === source }) {
                    sourcesToClear.append(source)
                }
            }
            return []
        }
        for source in sourcesToClear {
            source.clearBubbleSelection()
        }
    }
    
    public func remove(for id:Int64) {
        
    }
    public var isEmpty:Bool {
        return ranges.with { $0.isEmpty } && bubbleRanges.with { $0.isEmpty }
    }
    
    
    public var selectedText: NSAttributedString {
        let string:NSMutableAttributedString = NSMutableAttributedString()

        var combined: [(AnyHashable, SelectContainer)] = []
        ranges.with { for r in $0 { combined.append((r.stableId, r.container)) } }
        bubbleRanges.with { for r in $0 { combined.append((r.0, r.2)) } }

        let addHeaders: Bool = combined.map { $0.0 }.uniqueElements.count > 1

        var stableId: AnyHashable? = combined.last?.0
        for i in stride(from: combined.count - 1, to: -1, by: -1) {
            let container = combined[i].1

            if stableId != combined[i].0 {
                _ = string.append(string: "\n\n", color: nil, font: .normal(.text))
            }

            if let header = container.header, combined.count > 1, addHeaders {
                _ = string.append(string: header + "\n", color: nil, font: .normal(.text))
            }

            if container.range.location != NSNotFound {
                if container.range.location != 0, combined.count > 1, addHeaders {
                    _ = string.append(string: "...", color: nil, font: .normal(.text))
                }
                string.append(container.text.attributedSubstring(from: container.range).trimmed)
                if container.range.location + container.range.length != container.text.length, combined.count > 1, addHeaders {
                    _ = string.append(string: "...", color: nil, font: .normal(.text))
                }
            }
            if i != 0, string.string.last != "\n" {
                string.append(string: "\n")
            }

            stableId = combined[i].0
        }
        return string
    }
    
}

public protocol MultipleSelectable {
    var selectableTextViews:[TextView] { get }
    var header: String? { get }
}
final class SelectionLoopHarness {
    let selectManager = SelectManager()

    let table: SelectionTable
    var beginInnerLocation = NSPoint.zero
    var endInnerLocation = NSPoint.zero
    var deselect = false
    var reversible = false
    init(_ table: SelectionTable) { self.table = table }
    func select(begin: NSPoint, end: NSPoint, window: Window, reversedTable: Bool = true) {
        beginInnerLocation = begin
        endInnerLocation = end
        reversible = !reversedTable
        runSelector(window: window, chatInteraction: ChatInteraction())
    }
    private func runSelector(_ selectingText:Bool = true, window: Window, chatInteraction:ChatInteraction) {
        
        
        var startIndex = table.row(at: beginInnerLocation)
        var endIndex = table.row(at: endInnerLocation)
        
                
        let reversed = endIndex < startIndex;
        
        if(endIndex < startIndex) {
            startIndex = startIndex + endIndex;
            endIndex = startIndex - endIndex;
            startIndex = startIndex - endIndex;
        }
        
        if startIndex < 0 || endIndex < 0 {
            return
        }
        
        let beginRow = table.row(at: beginInnerLocation)
        if  let view = table.item(at: beginRow).view as? ChatRowView, let item = view.item as? ChatRowItem, selectingText, table._mouseInside() {
            let rowPoint = view.convert(beginInnerLocation, from: table.documentView)
            if (!NSPointInRect(rowPoint, view.bubbleFrame(item)) && theme.bubbled) {
                if startIndex != endIndex || abs(beginInnerLocation.y - endInnerLocation.y) > 10 {
                    for i in max(0,startIndex) ... min(endIndex,table.count - 1)  {
                        let item = table.item(at: i) as? ChatRowItem
                        if let view = item?.view as? ChatRowView {
                            view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                        }
                    }
                }
                return
            }
        }

        if selectingText {

            let preserved = selectManager.currentRanges()
            let preservedBubbles = selectManager.currentBubbleRanges()

            selectManager.removeAll()

            let isMultiple = abs(endIndex - startIndex) > 0;

            for i in startIndex ... endIndex  {
                if let rowView = table.viewNecessary(at: i),
                   let bubble = rowView as? ChatBubbleCustomTextSelection {
                    let begin = rowView.convert(beginInnerLocation, from: table.documentView)
                    let end   = rowView.convert(endInnerLocation,   from: table.documentView)
                    let fragments = bubble.applyBubbleSelection(
                        begin: begin, end: end,
                        isStartRow: i == startIndex,
                        isEndRow:   i == endIndex,
                        reversed:   reversed
                    )
                    let header = (rowView as? MultipleSelectable)?.header
                    for fragment in fragments {
                        selectManager.addBubble(fragment: fragment, source: bubble, header: header, stableId: table.item(at: i).stableId)
                    }
                    continue
                }
                guard let rowView = table.viewNecessary(at: i) else {
                    let stableId = table.item(at: i).stableId
                    selectManager.restoreBubbleRanges(preservedBubbles[stableId] ?? [])
                    for entry in preserved[stableId] ?? [] {
                        entry.layout?.selectedRange.range = entry.container.range
                        selectManager.add(range: entry.container.range, textView: nil, layout: entry.layout, text: entry.container.text, header: entry.container.header, stableId: stableId, index: entry.container.index)
                    }
                    continue
                }
                let view = rowView as? MultipleSelectable
                if let views = (rowView as? ChatTextSelectionProvider)?.textSelectionSources ?? view.map({ .views($0.selectableTextViews) }) {

                    var start_j:Int? = nil
                    var end_j:Int? = nil
                    
                    inner: for j in 0 ..< views.count {
                        let selectableView = views[j]
                        let viewRect = selectableView.selectionFrame(in: table.documentView)
                        let rect = NSRect(x: viewRect.midX, y: min(beginInnerLocation.y, endInnerLocation.y), width: abs(endInnerLocation.x - beginInnerLocation.x), height: abs(endInnerLocation.y - beginInnerLocation.y))
                        
                        if rect.intersects(viewRect) {
                            if start_j == nil {
                                start_j = j
                            } else {
                                start_j = min(start_j!, j)
                            }
                            if end_j == nil {
                                end_j = j
                            } else {
                                end_j = max(end_j!, j)
                            }
                        }
                    }
                    
                    for j in 0 ..< views.count {
                        let selectableView = views[j]
                        
                        if let layout = selectableView.textLayout {
                            let beginViewLocation = selectableView.convert(beginInnerLocation, from: table.documentView)
                            let endViewLocation = selectableView.convert(endInnerLocation, from: table.documentView)
                            
                            var startPoint:NSPoint = NSZeroPoint
                            var endPoint:NSPoint = NSZeroPoint
                            
                            if i == startIndex && i == endIndex {
                                
                            }
                            
                           
                            let fillEnd = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude)
                            
                            if (i > startIndex && i < endIndex) {
                                startPoint = NSMakePoint(0, 0);
                                endPoint = fillEnd;
                            } else if(i == startIndex) {
                                if(!isMultiple) {
                                    startPoint = beginViewLocation;
                                    endPoint = endViewLocation;
                                } else {
                                    if(!reversed) {
                                        if reversible {
                                            startPoint = beginViewLocation
                                            endPoint = fillEnd;
                                        } else {
                                            startPoint = beginViewLocation
                                            endPoint = NSMakePoint(0, 0);
                                        }
                                    } else {
                                        if reversible {
                                            startPoint = fillEnd;
                                            endPoint = endViewLocation;
                                        } else {
                                            startPoint = NSMakePoint(0, 0);
                                            endPoint = endViewLocation;
                                        }
                                    }
                                }
                                
                            } else if(i == endIndex) {
                                if(!reversed) {
                                    if reversible {
                                        startPoint = .zero;
                                        endPoint = endViewLocation;
                                    } else {
                                        startPoint = fillEnd;
                                        endPoint = endViewLocation;
                                    }
                                } else {
                                    startPoint = beginViewLocation;
                                    if reversible {
                                        endPoint = .zero
                                    } else {
                                        endPoint = fillEnd;
                                    }
                                }
                            }
                            
                            
                            if let start_j, let end_j, i == endIndex || i == startIndex {

                                if j < start_j || j > end_j {
                                    continue
                                } else {
                                    if end_j - start_j > 0 {
                                        if beginInnerLocation.y > endInnerLocation.y {
                                            if j <= start_j {
                                                endPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                            } else {
                                                startPoint = .zero
                                                if j < end_j {
                                                    endPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                                }
                                            }
                                        } else if beginInnerLocation.y < endInnerLocation.y {
                                            if j > start_j {
                                                endPoint = .zero
                                                if j < end_j {
                                                    startPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                                }
                                            } else {
                                                startPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                            }
                                        }
                                    }
                                    
                                }
                            }
                            
                            
                            selectableView.select(layout: layout, start: startPoint, end: endPoint, manager: selectManager, header: j == 0 ? view?.header : nil, stableId: table.item(at: i).stableId, index: j)

                        }
                    }
                }

            }
        } else {
            if chatInteraction.presentation.state == .selecting {
                for i in max(0,startIndex) ... min(endIndex,table.count - 1)  {
                    let item = table.item(at: i) as? ChatRowItem
                    if let view = item?.view as? ChatRowView {
                        view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                    }
                }
            }
            
        }
        
    }
}
final class LegacySelectionLoopHarness {
    let selectManager = LegacySelectManager()

    let table: SelectionTable
    var beginInnerLocation = NSPoint.zero
    var endInnerLocation = NSPoint.zero
    var deselect = false
    var reversible = false
    init(_ table: SelectionTable) { self.table = table }
    func select(begin: NSPoint, end: NSPoint, window: Window, reversedTable: Bool = true) {
        beginInnerLocation = begin
        endInnerLocation = end
        reversible = !reversedTable
        runSelector(window: window, chatInteraction: ChatInteraction())
    }
    private func runSelector(_ selectingText:Bool = true, window: Window, chatInteraction:ChatInteraction) {
        
        
        var startIndex = table.row(at: beginInnerLocation)
        var endIndex = table.row(at: endInnerLocation)
        
                
        let reversed = endIndex < startIndex;
        
        if(endIndex < startIndex) {
            startIndex = startIndex + endIndex;
            endIndex = startIndex - endIndex;
            startIndex = startIndex - endIndex;
        }
        
        if startIndex < 0 || endIndex < 0 {
            return
        }
        
        let beginRow = table.row(at: beginInnerLocation)
        if  let view = table.item(at: beginRow).view as? ChatRowView, let item = view.item as? ChatRowItem, selectingText, table._mouseInside() {
            let rowPoint = view.convert(beginInnerLocation, from: table.documentView)
            if (!NSPointInRect(rowPoint, view.bubbleFrame(item)) && theme.bubbled) {
                if startIndex != endIndex || abs(beginInnerLocation.y - endInnerLocation.y) > 10 {
                    for i in max(0,startIndex) ... min(endIndex,table.count - 1)  {
                        let item = table.item(at: i) as? ChatRowItem
                        if let view = item?.view as? ChatRowView {
                            view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                        }
                    }
                }
                return
            }
        }

        if selectingText {

            let preserved = selectManager.currentRanges()

            selectManager.removeAll()

            let isMultiple = abs(endIndex - startIndex) > 0;

            for i in startIndex ... endIndex  {
                if let rowView = table.viewNecessary(at: i),
                   let bubble = rowView as? ChatBubbleCustomTextSelection {
                    let begin = rowView.convert(beginInnerLocation, from: table.documentView)
                    let end   = rowView.convert(endInnerLocation,   from: table.documentView)
                    let fragments = bubble.applyBubbleSelection(
                        begin: begin, end: end,
                        isStartRow: i == startIndex,
                        isEndRow:   i == endIndex,
                        reversed:   reversed
                    )
                    let header = (rowView as? MultipleSelectable)?.header
                    for fragment in fragments {
                        selectManager.addBubble(fragment: fragment, source: bubble, header: header, stableId: table.item(at: i).stableId)
                    }
                    continue
                }
                guard let rowView = table.viewNecessary(at: i) else {
                    let stableId = table.item(at: i).stableId
                    for entry in preserved[stableId] ?? [] {
                        entry.layout?.selectedRange.range = entry.container.range
                        selectManager.add(range: entry.container.range, textView: nil, layout: entry.layout, text: entry.container.text, header: entry.container.header, stableId: stableId, index: entry.container.index)
                    }
                    continue
                }
                let view = rowView as? MultipleSelectable
                if let views = view?.selectableTextViews {

                    var start_j:Int? = nil
                    var end_j:Int? = nil
                    
                    inner: for j in 0 ..< views.count {
                        let selectableView = views[j]
                        var viewRect: NSRect
                        if let view = selectableView.superview, view.frame.height < selectableView.frame.height {
                            viewRect = view.convert(CGRect(origin: .zero, size: view.frame.size), to: table.documentView)
                        } else {
                            viewRect = selectableView.convert(CGRect(origin: .zero, size: selectableView.frame.size), to: table.documentView)
                        }
                        let rect = NSRect(x: viewRect.midX, y: min(beginInnerLocation.y, endInnerLocation.y), width: abs(endInnerLocation.x - beginInnerLocation.x), height: abs(endInnerLocation.y - beginInnerLocation.y))
                        
                        if rect.intersects(viewRect) {
                            if start_j == nil {
                                start_j = j
                            } else {
                                start_j = min(start_j!, j)
                            }
                            if end_j == nil {
                                end_j = j
                            } else {
                                end_j = max(end_j!, j)
                            }
                        }
                    }
                    
                    for j in 0 ..< views.count {
                        let selectableView = views[j]
                        
                        if let layout = selectableView.textLayout {
                            let beginViewLocation = selectableView.convert(beginInnerLocation, from: table.documentView)
                            let endViewLocation = selectableView.convert(endInnerLocation, from: table.documentView)
                            
                            var startPoint:NSPoint = NSZeroPoint
                            var endPoint:NSPoint = NSZeroPoint
                            
                            if i == startIndex && i == endIndex {
                                
                            }
                            
                           
                            let fillEnd = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude)
                            
                            if (i > startIndex && i < endIndex) {
                                startPoint = NSMakePoint(0, 0);
                                endPoint = fillEnd;
                            } else if(i == startIndex) {
                                if(!isMultiple) {
                                    startPoint = beginViewLocation;
                                    endPoint = endViewLocation;
                                } else {
                                    if(!reversed) {
                                        if reversible {
                                            startPoint = beginViewLocation
                                            endPoint = fillEnd;
                                        } else {
                                            startPoint = beginViewLocation
                                            endPoint = NSMakePoint(0, 0);
                                        }
                                    } else {
                                        if reversible {
                                            startPoint = fillEnd;
                                            endPoint = endViewLocation;
                                        } else {
                                            startPoint = NSMakePoint(0, 0);
                                            endPoint = endViewLocation;
                                        }
                                    }
                                }
                                
                            } else if(i == endIndex) {
                                if(!reversed) {
                                    if reversible {
                                        startPoint = .zero;
                                        endPoint = endViewLocation;
                                    } else {
                                        startPoint = fillEnd;
                                        endPoint = endViewLocation;
                                    }
                                } else {
                                    startPoint = beginViewLocation;
                                    if reversible {
                                        endPoint = .zero
                                    } else {
                                        endPoint = fillEnd;
                                    }
                                }
                            }
                            
                            
                            if let start_j, let end_j, i == endIndex || i == startIndex {

                                if j < start_j || j > end_j {
                                    continue
                                } else {
                                    if end_j - start_j > 0 {
                                        if beginInnerLocation.y > endInnerLocation.y {
                                            if j <= start_j {
                                                endPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                            } else {
                                                startPoint = .zero
                                                if j < end_j {
                                                    endPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                                }
                                            }
                                        } else if beginInnerLocation.y < endInnerLocation.y {
                                            if j > start_j {
                                                endPoint = .zero
                                                if j < end_j {
                                                    startPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                                }
                                            } else {
                                                startPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                            }
                                        }
                                    }
                                    
                                }
                            }
                            
                            
                            selectableView.canBeResponder = false
                            layout.selectedRange.range = layout.selectedRange(startPoint:startPoint, currentPoint:endPoint)
                            layout.selectedRange.cursorAlignment = startPoint.x > endPoint.x ? .min(layout.selectedRange.range.max) : .max(layout.selectedRange.range.min)
                            selectManager.add(range: layout.selectedRange.range, textView: selectableView, layout: layout, text:layout.attributedString, header: j == 0 ? view?.header : nil, stableId: table.item(at: i).stableId, index: j)
                            selectableView.setNeedsDisplayLayer()

                        }
                    }
                }

            }
        } else {
            if chatInteraction.presentation.state == .selecting {
                for i in max(0,startIndex) ... min(endIndex,table.count - 1)  {
                    let item = table.item(at: i) as? ChatRowItem
                    if let view = item?.view as? ChatRowView {
                        view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                    }
                }
            }
            
        }
        
    }

}
final class ReferenceEmbeddedSelectionLoopHarness {
    let selectManager = SelectManager()

    let table: SelectionTable
    var beginInnerLocation = NSPoint.zero
    var endInnerLocation = NSPoint.zero
    var deselect = false
    var reversible = false
    init(_ table: SelectionTable) { self.table = table }
    func select(begin: NSPoint, end: NSPoint, window: Window, reversedTable: Bool = true) {
        beginInnerLocation = begin
        endInnerLocation = end
        reversible = !reversedTable
        runSelector(window: window, chatInteraction: ChatInteraction())
    }
    private func runSelector(_ selectingText:Bool = true, window: Window, chatInteraction:ChatInteraction) {
        
        
        var startIndex = table.row(at: beginInnerLocation)
        var endIndex = table.row(at: endInnerLocation)
        
                
        let reversed = endIndex < startIndex;
        
        if(endIndex < startIndex) {
            startIndex = startIndex + endIndex;
            endIndex = startIndex - endIndex;
            startIndex = startIndex - endIndex;
        }
        
        if startIndex < 0 || endIndex < 0 {
            return
        }
        
        let beginRow = table.row(at: beginInnerLocation)
        if  let view = table.item(at: beginRow).view as? ChatRowView, let item = view.item as? ChatRowItem, selectingText, table._mouseInside() {
            let rowPoint = view.convert(beginInnerLocation, from: table.documentView)
            if (!NSPointInRect(rowPoint, view.bubbleFrame(item)) && theme.bubbled) {
                if startIndex != endIndex || abs(beginInnerLocation.y - endInnerLocation.y) > 10 {
                    for i in max(0,startIndex) ... min(endIndex,table.count - 1)  {
                        let item = table.item(at: i) as? ChatRowItem
                        if let view = item?.view as? ChatRowView {
                            view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                        }
                    }
                }
                return
            }
        }

        if selectingText {

            let preserved = selectManager.currentRanges()
            let preservedBubbles = selectManager.currentBubbleRanges()

            selectManager.removeAll()

            let isMultiple = abs(endIndex - startIndex) > 0;

            for i in startIndex ... endIndex  {
                if let rowView = table.viewNecessary(at: i),
                   let bubble = rowView as? ChatBubbleCustomTextSelection {
                    let begin = rowView.convert(beginInnerLocation, from: table.documentView)
                    let end   = rowView.convert(endInnerLocation,   from: table.documentView)
                    let fragments = bubble.applyBubbleSelection(
                        begin: begin, end: end,
                        isStartRow: i == startIndex,
                        isEndRow:   i == endIndex,
                        reversed:   reversed
                    )
                    let header = (rowView as? MultipleSelectable)?.header
                    for fragment in fragments {
                        selectManager.addBubble(fragment: fragment, source: bubble, header: header, stableId: table.item(at: i).stableId)
                    }
                    continue
                }
                guard let rowView = table.viewNecessary(at: i) else {
                    let stableId = table.item(at: i).stableId
                    selectManager.restoreBubbleRanges(preservedBubbles[stableId] ?? [])
                    for entry in preserved[stableId] ?? [] {
                        entry.layout?.selectedRange.range = entry.container.range
                        selectManager.add(range: entry.container.range, textView: nil, layout: entry.layout, text: entry.container.text, header: entry.container.header, stableId: stableId, index: entry.container.index)
                    }
                    continue
                }
                let view = rowView as? MultipleSelectable
                if let views = view?.selectableTextViews {

                    var start_j:Int? = nil
                    var end_j:Int? = nil
                    
                    inner: for j in 0 ..< views.count {
                        let selectableView = views[j]
                        var viewRect: NSRect
                        if let view = selectableView.superview, view.frame.height < selectableView.frame.height {
                            viewRect = view.convert(CGRect(origin: .zero, size: view.frame.size), to: table.documentView)
                        } else {
                            viewRect = selectableView.convert(CGRect(origin: .zero, size: selectableView.frame.size), to: table.documentView)
                        }
                        let rect = NSRect(x: viewRect.midX, y: min(beginInnerLocation.y, endInnerLocation.y), width: abs(endInnerLocation.x - beginInnerLocation.x), height: abs(endInnerLocation.y - beginInnerLocation.y))
                        
                        if rect.intersects(viewRect) {
                            if start_j == nil {
                                start_j = j
                            } else {
                                start_j = min(start_j!, j)
                            }
                            if end_j == nil {
                                end_j = j
                            } else {
                                end_j = max(end_j!, j)
                            }
                        }
                    }
                    
                    for j in 0 ..< views.count {
                        let selectableView = views[j]
                        
                        if let layout = selectableView.textLayout {
                            let beginViewLocation = selectableView.convert(beginInnerLocation, from: table.documentView)
                            let endViewLocation = selectableView.convert(endInnerLocation, from: table.documentView)
                            
                            var startPoint:NSPoint = NSZeroPoint
                            var endPoint:NSPoint = NSZeroPoint
                            
                            if i == startIndex && i == endIndex {
                                
                            }
                            
                           
                            let fillEnd = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude)
                            
                            if (i > startIndex && i < endIndex) {
                                startPoint = NSMakePoint(0, 0);
                                endPoint = fillEnd;
                            } else if(i == startIndex) {
                                if(!isMultiple) {
                                    startPoint = beginViewLocation;
                                    endPoint = endViewLocation;
                                } else {
                                    if(!reversed) {
                                        if reversible {
                                            startPoint = beginViewLocation
                                            endPoint = fillEnd;
                                        } else {
                                            startPoint = beginViewLocation
                                            endPoint = NSMakePoint(0, 0);
                                        }
                                    } else {
                                        if reversible {
                                            startPoint = fillEnd;
                                            endPoint = endViewLocation;
                                        } else {
                                            startPoint = NSMakePoint(0, 0);
                                            endPoint = endViewLocation;
                                        }
                                    }
                                }
                                
                            } else if(i == endIndex) {
                                if(!reversed) {
                                    if reversible {
                                        startPoint = .zero;
                                        endPoint = endViewLocation;
                                    } else {
                                        startPoint = fillEnd;
                                        endPoint = endViewLocation;
                                    }
                                } else {
                                    startPoint = beginViewLocation;
                                    if reversible {
                                        endPoint = .zero
                                    } else {
                                        endPoint = fillEnd;
                                    }
                                }
                            }
                            
                            
                            if let start_j, let end_j, i == endIndex || i == startIndex {

                                if j < start_j || j > end_j {
                                    continue
                                } else {
                                    if end_j - start_j > 0 {
                                        if beginInnerLocation.y > endInnerLocation.y {
                                            if j <= start_j {
                                                endPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                            } else {
                                                startPoint = .zero
                                                if j < end_j {
                                                    endPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                                }
                                            }
                                        } else if beginInnerLocation.y < endInnerLocation.y {
                                            if j > start_j {
                                                endPoint = .zero
                                                if j < end_j {
                                                    startPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                                }
                                            } else {
                                                startPoint = NSMakePoint(layout.layoutSize.width, .greatestFiniteMagnitude);
                                            }
                                        }
                                    }
                                    
                                }
                            }
                            
                            
                            selectableView.canBeResponder = false
                            layout.selectedRange.range = layout.selectedRange(startPoint:startPoint, currentPoint:endPoint)
                            layout.selectedRange.cursorAlignment = startPoint.x > endPoint.x ? .min(layout.selectedRange.range.max) : .max(layout.selectedRange.range.min)
                            selectManager.add(range: layout.selectedRange.range, textView: selectableView, layout: layout, text:layout.attributedString, header: j == 0 ? view?.header : nil, stableId: table.item(at: i).stableId, index: j)
                            selectableView.setNeedsDisplayLayer()

                        }
                    }
                }

            }
        } else {
            if chatInteraction.presentation.state == .selecting {
                for i in max(0,startIndex) ... min(endIndex,table.count - 1)  {
                    let item = table.item(at: i) as? ChatRowItem
                    if let view = item?.view as? ChatRowView {
                        view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                    }
                }
            }
            
        }
        
    }
}
