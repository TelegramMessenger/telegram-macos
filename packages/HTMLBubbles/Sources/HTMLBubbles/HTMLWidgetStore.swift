import Foundation
import Postbox
import TelegramCore
import WidgetSandbox
import Localization

public final class HTMLWidgetStore {
    private struct Key: Hashable {
        let mediaBox: ObjectIdentifier
        let messageId: MessageId
    }

    private struct Entry {
        var media: TelegramMediaWidget
        let state: HTMLBubbleState
    }

    public static let shared = HTMLWidgetStore()

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private let capacity = 48

    public func state(mediaBox: MediaBox, message: Message, widget: TelegramMediaWidget, context: HTMLWidgetContext? = nil) -> HTMLBubbleState {
        return state(mediaBoxId: ObjectIdentifier(mediaBox), message: message, widget: widget, context: context)
    }

    func state(mediaBoxId: ObjectIdentifier, message: Message, widget: TelegramMediaWidget, context: HTMLWidgetContext?) -> HTMLBubbleState {
        let key = Key(mediaBox: mediaBoxId, messageId: message.id)
        lock.lock()
        if var entry = entries[key], entry.state.widgetContext == context, entry.media.width == widget.width, entry.media.height == widget.height, entry.media.payload == widget.payload, entry.media.isCopy == widget.isCopy, entry.media.canQuery == widget.canQuery, entry.media.backgroundQuery == widget.backgroundQuery, entry.media.widgetId == widget.widgetId {
            order.removeAll { $0 == key }
            order.append(key)
            entry.media = widget
            entries[key] = entry
            lock.unlock()
            entry.state.updateWidgetData(Self.data(widget))
            return entry.state
        }
        lock.unlock()

        let state = Self.makeState(widget: widget, outgoing: !message.flags.contains(.Incoming))
        if let context {
            state.attachWidget(context)
        }
        lock.lock()
        if var entry = entries[key], entry.state.widgetContext == context, entry.media.width == widget.width, entry.media.height == widget.height, entry.media.payload == widget.payload, entry.media.isCopy == widget.isCopy, entry.media.canQuery == widget.canQuery, entry.media.backgroundQuery == widget.backgroundQuery, entry.media.widgetId == widget.widgetId {
            entry.media = widget
            entries[key] = entry
            lock.unlock()
            entry.state.updateWidgetData(Self.data(widget))
            return entry.state
        }
        var removed: [Entry] = []
        if let previous = entries.updateValue(Entry(media: widget, state: state), forKey: key) {
            removed.append(previous)
        }
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            if let entry = entries.removeValue(forKey: order.removeFirst()) {
                removed.append(entry)
            }
        }
        lock.unlock()
        withExtendedLifetime(removed) {}
        return state
    }

    private static let crashLock = NSLock()
    private static var crashes: [String: Int] = [:]
    static let crashLimit = 2

    static func recordCrash(_ key: String) -> Int {
        crashLock.lock()
        defer { crashLock.unlock() }
        let count = (crashes[key] ?? 0) + 1
        crashes[key] = count
        return count
    }

    static func resetCrashes(_ key: String) {
        crashLock.lock()
        crashes.removeValue(forKey: key)
        crashLock.unlock()
    }

    static func crashCount(_ key: String) -> Int {
        crashLock.lock()
        defer { crashLock.unlock() }
        return crashes[key] ?? 0
    }

    public static func preview(widget: TelegramMediaWidget, locale: String = "en-US") -> HTMLBubbleState {
        let state = makeState(widget: widget, outgoing: true)
        state.widgetPreview = true
        state.widgetPreviewLocale = HTMLWidgetContext.bcp47(locale)
        if widget.height == 0 {
            state.heightHint = 160
        }
        return state
    }

    static func data(_ widget: TelegramMediaWidget) -> WidgetData {
        return WidgetData(chatData: widget.isCopy ? nil : widget.chatData.flatMap { String(data: $0, encoding: .utf8) }, publicData: widget.publicData.flatMap { String(data: $0, encoding: .utf8) })
    }

    static func makeState(widget: TelegramMediaWidget, outgoing: Bool) -> HTMLBubbleState {
        let state: HTMLBubbleState
        if widget.width >= 0, widget.height >= 0, let html = HTMLWidgetPayload.decode(widget.payload) {
            state = HTMLBubbleState(html: html, outgoing: outgoing, engine: .twidget, selfContained: true)
            if widget.height > 0 {
                state.heightHint = HTMLWidgetPayload.clampedHeight(CGFloat(widget.height))
                state.fixedHeight = state.heightHint
            }
            state.isWidgetMessage = true
        } else {
            state = HTMLBubbleState(html: "<p>\(strings().htmlWidgetStoreWidgetUnavailable)</p>", outgoing: outgoing, engine: .litehtml, selfContained: true)
        }
        state.updateWidgetData(data(widget))
        state.showsStats = false
        return state
    }
}
