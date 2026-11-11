import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

public final class HTMLWidgetPublicData {
    private struct Key: Hashable {
        let account: ObjectIdentifier
        let messageId: MessageId
        let state: ObjectIdentifier
    }

    private final class Entry {
        weak var state: HTMLBubbleState?
        let widgetId: Int64
        let messages: TelegramEngine.Messages
        let subscription = MetaDisposable()
        var polling = false

        init(state: HTMLBubbleState, widgetId: Int64, messages: TelegramEngine.Messages) {
            self.state = state
            self.widgetId = widgetId
            self.messages = messages
        }

        deinit {
            subscription.dispose()
        }
    }

    public static let shared = HTMLWidgetPublicData()
    private var entries: [Key: Entry] = [:]

    public func attach(state: HTMLBubbleState, widget: TelegramMediaWidget, account: Account, messages: TelegramEngine.Messages, messageId: MessageId) {
        let key = Key(account: ObjectIdentifier(account), messageId: messageId, state: ObjectIdentifier(state))
        let attach = { [weak state] in
            self.entries = self.entries.filter { $0.value.state != nil }
            guard let state else { return }
            guard let widgetId = widget.widgetId else {
                self.entries.removeValue(forKey: key)
                state.widgetWatchHandler = nil
                return
            }
            if let current = self.entries[key], current.state === state, current.widgetId == widgetId {
                self.update(key)
                return
            }
            self.entries[key] = Entry(state: state, widgetId: widgetId, messages: messages)
            state.widgetWatchHandler = { self.update(key) }
            self.update(key)
        }
        if Thread.isMainThread { attach() } else { DispatchQueue.main.async(execute: attach) }
    }

    private func update(_ key: Key) {
        guard let entry = entries[key] else { return }
        guard let state = entry.state else {
            entries.removeValue(forKey: key)
            return
        }
        let polling = state.widgetVisible && state.twidgetHost?.diagnostics.watchesPublicData == true
        guard polling != entry.polling else { return }
        entry.polling = polling
        entry.subscription.set(polling ? entry.messages.pollWidgetPublicData(messageId: key.messageId, widgetId: entry.widgetId).start() : nil)
    }
}
