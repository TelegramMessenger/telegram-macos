import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import AlertsUI
import InputTextView
import MessageTextUtils
import TelegramTheme
import TelegramUtils
import Localization
import MessageUtils
public struct SelectContainer {
    public let text:NSAttributedString
    public let range:NSRange
    public let index: Int
    public let header:String?
    public var richText: [RichText]? = nil
}

func copiedMessageHeader(_ message: Message, timeDifference: TimeInterval) -> String {
    var header: String
    if let forwardInfo = message.forwardInfo {
        header = forwardInfo.authorTitle
    } else {
        header = message.effectiveAuthor?.displayTitle ?? ""
    }
    if message.timestamp != scheduleWhenOnlineTimestamp {
        let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp) - timeDifference)
        header += ", [" + DateSelectorUtil.chatFullDateFormatter.string(from: date) + "]"
    }
    return header
}

func copiedMessageReplyLine(_ message: Message, threadId: Int64?) -> String? {
    guard let attribute = message.replyAttribute, let replied = message.associatedMessages[attribute.messageId] else {
        return nil
    }
    if ChatRowItem.hidesReply(to: attribute, in: message, threadId: threadId) {
        return nil
    }
    let quote = attribute.isQuote ? attribute.quote : nil
    var author = replied.effectiveAuthor?.displayTitle ?? ""
    if let forwardInfo = replied.forwardInfo, quote == nil {
        author = forwardInfo.authorTitle
    }
    let title = quote != nil ? strings().chatReplyQuotePanelTitle(author) : strings().chatReplyMessagePanelTitle(author)
    let source = quote.map { messageReplyQuoteText($0).text } ?? (pullText(from: replied).string as String)
    let firstLine = source.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let snippet = firstLine.count > 100 ? String(firstLine.prefix(100)) + "…" : firstLine
    return snippet.isEmpty ? title : title + ": " + snippet
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
    
    /// The selected attributed text of ONE rich message's bubble selection (fragments joined in index
    /// order), or nil when nothing in that message is selected. Drives the rich message's quote-reply
    /// menu item, mirroring `textLayout.selectedString` on plain messages.
    public func richSelectedText(for messageId: MessageId) -> NSAttributedString? {
        let parts: [NSAttributedString] = bubbleRanges.with { entries in
            entries.filter { entry in
                guard let view = entry.1.source as? ChatRichTextRowView,
                      let item = view.item as? ChatRichTextRowItem else { return false }
                return item.message?.id == messageId
            }
            .sorted(by: { $0.2.index < $1.2.index })
            .compactMap { entry in
                guard entry.2.range.location != NSNotFound, entry.2.range.length > 0 else { return nil }
                return entry.2.text.attributedSubstring(from: entry.2.range)
            }
        }
        guard !parts.isEmpty else { return nil }
        let joined = NSMutableAttributedString()
        for (i, part) in parts.enumerated() {
            if i > 0 { joined.append(NSAttributedString(string: "\n")) }
            joined.append(part)
        }
        return joined
    }

    public func richSelectedQuote(for messageId: MessageId) -> EngineMessageReplyQuote? {
        let parts: [RichText] = bubbleRanges.with { entries in
            entries.filter { entry in
                guard let view = entry.1.source as? ChatRichTextRowView,
                      let item = view.item as? ChatRichTextRowItem else { return false }
                return item.message?.id == messageId
            }
            .sorted(by: { $0.2.index < $1.2.index })
            .flatMap { $0.2.richText ?? [] }
        }
        guard !parts.isEmpty else { return nil }
        return EngineMessageReplyQuote(richText: parts, offset: nil, media: nil)
    }

    @objc public func copy(_ sender:Any) {
        
        if let window = self.chatInteraction?.interactionContext.window, let peer = self.chatInteraction?.peer, peer.isCopyProtected(cachedData: self.chatInteraction?.presentation.cachedData) {
            showProtectedCopyAlert(peer, for: window)
            return
        }
        
        let selectedText = self.selectedText
        if !selectedText.string.isEmpty {
            if !LinkHooks.shared.globalLinkExecutor().copyAttributedString(selectedText) {
                NSPasteboard.general.declareTypes([.string], owner: self)
                NSPasteboard.general.setString(selectedText.string, forType: .string)
            }
            // For a rich-message-origin copy, also carry the selection as a serialized editor Document (which,
            // unlike the flat clipboard, preserves formulas) so a paste into the composer rebuilds it in the
            // rich editor. Built now from the formatted selection (incl. formula marks).
            let isRichOrigin = bubbleRanges.with { entries in entries.contains { $0.1.isRichText } }
            if isRichOrigin, let data = try? JSONEncoder().encode(documentFromRichSelection(selectedText)) {
                NSPasteboard.general.addTypes([.kRichTextMessage], owner: nil)
                NSPasteboard.general.setData(data, forType: .kRichTextMessage)
            }
            // The flat Document can't carry media. When the source rich message has media AND (nearly) the
            // WHOLE message is selected, also carry a reference so the paste refetches the message and seeds
            // the editor with the FULL content (media included). For a PARTIAL selection we skip the ref so
            // the paste rebuilds only the selected Document (issue: a first-line copy was pasting everything).
            let mediaRefMessageId: MessageId? = bubbleRanges.with { entries in
                for entry in entries {
                    if let view = entry.1.source as? ChatRichTextRowView,
                       let item = view.item as? ChatRichTextRowItem,
                       let message = item.message,
                       let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first,
                       !rich.instantPage.media.isEmpty {
                        let selected = entry.2.text.string.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
                        let total = view.totalSelectableTextLength()
                        if total > 0, selected * 100 >= total * 90 {
                            return message.id
                        }
                    }
                }
                return nil
            }
            if let id = mediaRefMessageId {
                let ref = "\(id.peerId.toInt64()):\(id.namespace):\(id.id)"
                if let data = ref.data(using: .utf8) {
                    NSPasteboard.general.addTypes([.kRichTextMessageRef], owner: nil)
                    NSPasteboard.general.setData(data, forType: .kRichTextMessageRef)
                }
            }
        } else if let chatInteraction = self.chatInteraction {
            if let selectionState = chatInteraction.presentation.selectionState {
                let timeDifference = chatInteraction.interactionContext.timeDifference
                let threadId = chatInteraction.chatLocation.threadId
                _ = chatInteraction.interactionContext.account.postbox.messagesAtIds(Array(selectionState.selectedIds.sorted(by: <))).start(next: { messages in
                    var text: String = ""
                    for message in messages {
                        if !text.isEmpty {
                            text += "\n\n"
                        }
                        text += "> " + copiedMessageHeader(message, timeDifference: timeDifference) + ":"
                        text += "\n"
                        if let replyLine = copiedMessageReplyLine(message, threadId: threadId) {
                            text += "> " + replyLine + "\n"
                        }
                        text += pullText(from: message).string as String
                    }
                    copyToClipboard(text)
                })
            }
        }
        
    }
    
    public func selectNextChar() -> Bool {
        var result: Bool = false
        _ = ranges.modify { ranges in
            let ranges = ranges
            if let last = ranges.last {
                if last.container.range.max < last.container.text.length, let layout = last.effectiveLayout {

                    var range = last.container.range

                    switch layout.selectedRange.cursorAlignment {
                    case let .min(cursorAlignment), let .max(cursorAlignment):
                        if range.min >= cursorAlignment {
                            range.length += 1
                        } else {
                            range.location += 1
                            if range.length > 1 {
                                range.length -= 1
                            }
                        }
                    }
                    let location = min(max(0, range.location), last.container.text.length)
                    let length = max(min(range.length, last.container.text.length - location), 0)
                    range = NSMakeRange(location, length)

                    layout.selectedRange.range = range
                    last.container = SelectContainer(text: last.container.text, range: range, index: last.container.index, header: last.container.header)
                    last.textView?.needsDisplay = true
                    result = true
                    return ranges
                }
            }
            result = false
            return ranges
        }
        return result
    }
    
    public func selectPrevChar() -> Bool {
        var result: Bool = false
        _ = ranges.modify { ranges in
            let ranges = ranges
            if let first = ranges.first, first.textView == nil || first.textView?.window?.isKeyWindow == true {
                if let layout = first.effectiveLayout {

                    var range = first.container.range

                    switch layout.selectedRange.cursorAlignment {
                    case let .min(cursorAlignment), let .max(cursorAlignment):
                        if range.location >= cursorAlignment {
                            if range.length > 1 {
                                range.length -= 1
                            } else {
                                range.location -= 1
                            }
                        } else {
                            if range.location > 0 {
                                range.location -= 1
                                range.length += 1
                            }
                        }
                    }
                    
                    let location = min(max(0, range.location), first.container.text.length)
                    let length = max(min(range.length, first.container.text.length - location), 0)
                    range = NSMakeRange(location, length)
                    layout.selectedRange.range = range
                    first.container = SelectContainer(text: first.container.text, range: range, index: first.container.index, header: first.container.header)
                    first.textView?.needsDisplay = true
                    result = true
                    return ranges
                }
            }
            result = false
            return ranges
        }
        return result
    }
    
    public func find(_ stableId:AnyHashable) -> NSRange? {
        return ranges.with { ranges -> NSRange? in
            for range in ranges {
                if range.stableId == stableId {
                    return range.container.range
                }
            }
            return nil
        }
    }

    public func findAll(_ stableId:AnyHashable) -> [(NSRange, Int)] {
        return ranges.with { ranges -> [(NSRange, Int)] in
            var list: [(NSRange, Int)] = []
            for range in ranges {
                if range.stableId == stableId {
                    list.append((range.container.range, range.container.index))
                }
            }
            return list
        }
    }
    
    public override func becomeFirstResponder() -> Bool {
        return true
    }
    
    public override func resignFirstResponder() -> Bool {
        removeAll()
        return true
    }
}

public let selectManager:SelectManager = SelectManager()

public func initializeSelectManager() {
    _ = selectManager.isEmpty
}

public protocol MultipleSelectable {
    var selectableTextViews:[TextView] { get }
    var header: String? { get }
}

func chatTextSelectionDidDrag(from start: NSPoint, to location: NSPoint) -> Bool {
    let dx = location.x - start.x
    let dy = location.y - start.y
    return dx * dx + dy * dy > 4 * 4
}

public class ChatSelectText : NSObject {

    private var beginInnerLocation:NSPoint = NSMakePoint(-1, -1)
    private var endInnerLocation:NSPoint = NSMakePoint(-1, -1)
    private let table:TableView
    private var scrollListeners: [TableScrollListener] = []
    private var deselect:Bool = false
    private var started:Bool = false
    private var startMessageId:MessageId? = nil
    private var lastPressureEventStage = 0
    private var inPressedState = false
    private var locationInWindow: NSPoint? = nil
    private var reversible: Bool = false
    private var isDragConfirmed: Bool = false

    private func confirmDragIfNeeded(_ location: NSPoint) -> Bool {
        if isDragConfirmed {
            return true
        }
        guard let start = locationInWindow else {
            return false
        }
        if chatTextSelectionDidDrag(from: start, to: location) {
            isDragConfirmed = true
        }
        return isDragConfirmed
    }
    
    public init(_ table:TableView) {
        self.table = table
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    public func initializeHandlers(for window:Window, chatInteraction:ChatInteraction) {
        
        self.reversible = chatInteraction.mode.isSavedMode
        
        selectManager.chatInteraction = chatInteraction
        
        removeScrollListeners()
        
        let mouseListener = TableScrollListener (dispatchWhenVisibleRangeUpdated: false, { [weak table] _ in
            table?.enumerateVisibleViews(with: { view in
                view.updateMouse(animated: true)
            })
        })

        let selectionListener = TableScrollListener (dispatchWhenVisibleRangeUpdated: false, { [weak self, weak chatInteraction, weak window] _ in
            guard let self, let chatInteraction, let window, self.started, self.isDragConfirmed, !self.inPressedState else {
                return
            }
            guard window.firstResponder == selectManager else {
                return
            }
            guard self.beginInnerLocation != NSZeroPoint, NSEvent.pressedMouseButtons & 1 != 0 else {
                return
            }
            guard chatInteraction.presentation.state != .selecting, !hasPopover(window), !hasModals(window) else {
                return
            }
            guard let documentView = self.table.documentView else {
                return
            }
            self.endInnerLocation = documentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            self.runSelector(window: window, chatInteraction: chatInteraction)
        })
        
        scrollListeners = [mouseListener, selectionListener]
        table.addScroll(listener: mouseListener)
        table.addScroll(listener: selectionListener)

        window.set(mouseHandler: { [weak table] event -> KeyHandlerResult in
            
            table?.enumerateVisibleViews(with: { view in
                view.updateMouse(animated: true)
            })
            
            return .rejected
        }, with: self, for: .mouseMoved, priority:.medium)
        
        window.set(mouseHandler: { [weak self, weak chatInteraction] event -> KeyHandlerResult in

            guard let chatInteraction = chatInteraction else { return .rejected }

            self?.started = false
            self?.inPressedState = false
            self?.isDragConfirmed = false
            self?.locationInWindow = event.locationInWindow

            if let table = self?.table, let superview = table.superview, let documentView = table.documentView {
                let point = superview.convert(event.locationInWindow, from: nil)
                let documentPoint = documentView.convert(event.locationInWindow, from: nil)
                let row = table.row(at: documentPoint)
                
                func isCurrentTableView(_ view: NSView?) -> Bool {
                    if view === table {
                        return true
                    } else if let superview = view?.superview {
                        if superview is TableView, view is TableRowView || view is NSClipView {
                            return isCurrentTableView(superview)
                        } else if superview is TableView {
                            return false
                        } else {
                            return isCurrentTableView(superview)
                        }
                    } else {
                        return false
                    }
                }
                
                if row < 0 || (!NSPointInRect(point, table.frame) || hasModals(window) || (!table.item(at: row).canMultiselectTextIn(event.locationInWindow) && chatInteraction.presentation.state != .selecting)) || !isCurrentTableView(window.contentView?.hitTest(event.locationInWindow)) {
                    self?.beginInnerLocation = NSZeroPoint
                } else {
                    self?.beginInnerLocation = documentPoint
                }
                
                
                if row != -1, let item = table.item(at: row) as? ChatRowItem, let view = item.view as? ChatRowView {
                    if chatInteraction.presentation.state == .selecting || (theme.bubbled && !NSPointInRect(view.convert(event.locationInWindow, from: nil), view.bubbleFrame(item))) {
                        if self?.startMessageId == nil {
                            self?.startMessageId = item.message?.id
                        }
                        self?.deselect = !view.isSelectInGroup(event.locationInWindow)
                    }
                }
                
                self?.started = self?.beginInnerLocation != NSZeroPoint
                if self?.started == true, row != -1 {
                    if chatInteraction.presentation.state == .selecting, let deselect = self?.deselect {
                        let item = table.item(at: row) as? ChatRowItem
                        if let view = item?.view as? ChatRowView {
                            view.toggleSelected(deselect, in: window.mouseLocationOutsideOfEventStream)
                        }
                    }
                }
            }
            
            return .invokeNext
        }, with: self, for: .leftMouseDown, priority:.medium)
        
        window.set(mouseHandler: { [weak self, weak chatInteraction] event -> KeyHandlerResult in

            self?.beginInnerLocation = NSZeroPoint
            self?.locationInWindow = nil
            self?.isDragConfirmed = false

            Queue.mainQueue().justDispatch { [weak chatInteraction] in
                guard let table = self?.table else {return}
                guard let documentView = table.documentView else {return}
                guard let chatInteraction = chatInteraction else { return }
                
                var cleanStartId: Bool = false
                let documentPoint = documentView.convert(event.locationInWindow, from: nil)
                let row = table.row(at: documentPoint)
                 if chatInteraction.presentation.state != .selecting {
                    if let view = table.viewNecessary(at: row) as? ChatRowView, !view.canStartTextSelecting(event) {
                        self?.beginInnerLocation = NSZeroPoint
                    }
                    cleanStartId = true
                }
               
                
                let point = self?.table.documentView?.convert(event.locationInWindow, from: nil) ?? NSZeroPoint
                if let index = self?.table.row(at: point), index > 0, let item = self?.table.item(at: index), let view = item.view as? ChatRowView {
                    
                    if event.clickCount > 1, selectManager.isEmpty {
                        if !view.isAllowedToDoubleAction(view.convert(event.locationInWindow, from: nil)) {
                            view.textSelectionSources.restoreFocus(in: window)
                        }
                    }

                    if chatInteraction.presentation.reportMode == nil {
                        if view.canDropSelection(in: event.locationInWindow) {
                            if let result = chatInteraction.presentation.selectionState?.selectedIds.isEmpty, result {
                                self?.startMessageId = nil
                                chatInteraction.update({$0.withoutSelectionState()})
                            }
                        }
                    }
                } else {
                    if chatInteraction.presentation.reportMode == nil {
                        if let result = chatInteraction.presentation.selectionState?.selectedIds.isEmpty, result {
                            self?.startMessageId = nil
                            chatInteraction.update({$0.withoutSelectionState()})
                        }
                    }
                }
                if cleanStartId {
                    self?.startMessageId = nil
                }
            }
            return .invokeNext
        }, with: self, for: .leftMouseUp, priority:.medium)
        
        window.set(mouseHandler: { [weak self, weak chatInteraction] event -> KeyHandlerResult in

            guard let `self` = self else {return .rejected}
            guard let chatInteraction = chatInteraction else { return .rejected }

            self.endInnerLocation = self.table.documentView?.convert(window.mouseLocationOutsideOfEventStream, from: nil) ?? NSZeroPoint

            if self.started {
                self.started = !hasPopover(window) && self.beginInnerLocation != NSZeroPoint
            }
            if event.clickCount > 1 {
                self.started = false
            }

            if self.started, !self.confirmDragIfNeeded(event.locationInWindow) {
                return chatInteraction.presentation.state != .selecting ? .invoked : .invokeNext
            }

            if self.started {
                self.table.clipView.autoscroll(with: event)
                if chatInteraction.presentation.state != .selecting {
                    if !self.inPressedState {
                        self.runSelector(window: window, chatInteraction: chatInteraction)
                        if window.firstResponder != selectManager {
                            _ = window.makeFirstResponder(selectManager)
                        }
                    }
                    return .invoked
                    
                } else if chatInteraction.presentation.state == .selecting {
                    self.runSelector(false, window: window, chatInteraction: chatInteraction)
                    return .invokeNext
                }
            }
            return .invokeNext
        }, with: self, for: .leftMouseDragged, priority:.medium)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            guard let `self` = self else { return .rejected }
            if event.stage == 2 && self.lastPressureEventStage < 2 {
                self.inPressedState = true
            }
            self.lastPressureEventStage = event.stage
            return .rejected
        }, with: self, for: .pressure, priority: .medium)
        
        window.set(handler: { _ -> KeyHandlerResult in
            
            return .rejected
        }, with: self, for: .A, priority: .medium, modifierFlags: [.command])
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
    
    public func removeHandlers(for window:Window) {
        window.removeAllHandlers(for: self)
        removeScrollListeners()
    }
    
    private func removeScrollListeners() {
        for listener in scrollListeners {
            table.removeScroll(listener: listener)
        }
        scrollListeners.removeAll()
    }
    
}
