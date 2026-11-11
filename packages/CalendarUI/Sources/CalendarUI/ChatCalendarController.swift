import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import Localization
import AlertsUI

private final class ChatCalendarDayPreview: View {
    private let imageView = TransformImageView()
    private let shadeView = View()

    init(context: any AccountContextProtocol, message: Message, size: NSSize) {
        super.init(frame: size.bounds)
        isEventLess = true
        layer?.cornerRadius = size.width / 2
        layer?.masksToBounds = true
        backgroundColor = theme.colors.grayBackground
        imageView.frame = bounds
        shadeView.frame = bounds
        shadeView.isEventLess = true
        shadeView.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        addSubview(imageView)
        addSubview(shadeView)

        let signal: Signal<ImageDataTransformation, NoError>
        let dimensions: NSSize
        let isSpoiler = message.attributes.contains { $0 is MediaSpoilerMessageAttribute }
        if let image = message.media.compactMap({ $0 as? TelegramMediaImage }).first {
            let reference = ImageMediaReference.message(message: MessageReference(message), media: image)
            dimensions = image.representations.last?.dimensions.size ?? size
            if isSpoiler {
                signal = chatSecretPhoto(account: context.account, imageReference: reference, scale: System.backingScale)
            } else {
                signal = chatMessagePhoto(account: context.account, imageReference: reference, toRepresentationSize: NSMakeSize(80, 80), scale: System.backingScale, autoFetchFullSize: true)
            }
        } else if let file = message.media.compactMap({ $0 as? TelegramMediaFile }).first(where: { $0.isVideo }) {
            let reference = FileMediaReference.message(message: MessageReference(message), media: file)
            dimensions = file.dimensions?.size ?? file.previewRepresentations.last?.dimensions.size ?? size
            if isSpoiler {
                signal = chatSecretMessageVideo(account: context.account, fileReference: reference, scale: System.backingScale)
            } else {
                signal = chatMessageVideo(account: context.account, fileReference: reference, scale: System.backingScale)
            }
        } else {
            return
        }
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        imageView.animatesAlphaOnFirstTransition = animated
        imageView.setSignal(signal, animate: animated)
        imageView.set(arguments: TransformImageArguments(corners: ImageCorners(radius: size.width / 2), imageSize: dimensions.aspectFilled(size), boundingSize: size, intrinsicInsets: NSEdgeInsets(), resizeMode: .none))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ChatCalendarMedia {
    private let context: any AccountContextProtocol
    let source: SparseMessageCalendar
    private let disposable = DisposableSet()
    private var messagesByDay: [Int: Message] = [:]

    init(context: any AccountContextProtocol, peerId: PeerId) {
        self.context = context
        self.source = context.engine.messages.sparseMessageCalendar(peerId: peerId, threadId: nil, tag: .photoOrVideo, displayMedia: true)
    }

    func start(updated: @escaping () -> Void) {
        disposable.add((source.state |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else { return }
            let calendar = Calendar(identifier: .gregorian)
            var messages: [Int: Message] = [:]
            for entry in state.messagesByDay.values {
                let message = entry.message
                guard !message.containsSecretMedia, message.media.contains(where: { media in
                    return media is TelegramMediaImage || (media as? TelegramMediaFile)?.isVideo == true
                }) else { continue }
                let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp) - self.context.timeDifference)
                let timestamp = Int(calendar.startOfDay(for: date).timeIntervalSince1970)
                if let existing = messages[timestamp], existing.index >= message.index {
                    continue
                }
                messages[timestamp] = message
            }
            self.messagesByDay = messages
            updated()
        }))
        disposable.add((source.isLoadingMore |> distinctUntilChanged |> filter { !$0 } |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.source.loadMore()
        }))
    }

    func preview(timestamp: Int, size: NSSize = NSMakeSize(36, 36)) -> NSView? {
        guard let message = messagesByDay[timestamp] else { return nil }
        return ChatCalendarDayPreview(context: context, message: message, size: size)
    }

    deinit {
        disposable.dispose()
    }
}

private func chatCalendarCanClearRange(_ peer: EnginePeer) -> Bool {
    switch peer {
    case .user, .legacyGroup:
        return true
    case let .channel(channel):
        if channel.flags.contains(.isMonoforum) {
            return false
        }
        if case .broadcast = channel.info {
            return channel.hasPermission(.deleteAllMessages)
        }
        return true
    case .secretChat, .community:
        return false
    }
}

private func chatCalendarMessageIds(context: any AccountContextProtocol, peerId: PeerId, fromId: PeerId?, minTimestamp: Int32, maxTimestamp: Int32) -> Signal<[MessageId], NoError> {
    let location: SearchMessagesLocation = .peer(peerId: peerId, fromId: fromId, tags: nil, reactions: nil, threadId: nil, minDate: minTimestamp - 1, maxDate: maxTimestamp)
    func load(_ state: SearchMessagesState?) -> Signal<[MessageId], NoError> {
        return context.engine.messages.searchMessages(location: location, query: "", state: state, limit: 100)
        |> mapToSignal { result, nextState -> Signal<[MessageId], NoError> in
            if result.completed || state == nextState {
                var ids = Set<MessageId>()
                return .single(result.messages.filter { message in
                    guard message.id.peerId == peerId, message.id.namespace == Namespaces.Message.Cloud else {
                        return false
                    }
                    guard message.timestamp >= minTimestamp, message.timestamp < maxTimestamp else {
                        return false
                    }
                    if let fromId, message.author?.id != fromId {
                        return false
                    }
                    return ids.insert(message.id).inserted
                }.map(\.id))
            }
            return load(nextState)
        }
    }
    return load(nil)
}

private func chatCalendarClearMessages(context: any AccountContextProtocol, peer: EnginePeer, minTimestamp: Int32, maxTimestamp: Int32, days: Int, done: @escaping () -> Void) {
    let window = context.window
    let information: String
    var option: String?
    var fromId: PeerId?
    switch peer {
    case let .channel(channel):
        if channel.hasPermission(.deleteAllMessages) {
            information = strings().messageCalendarDeleteForAllAlertTextOther(days)
        } else {
            information = strings().messageCalendarDeleteOwnAlertTextOther(days)
            fromId = context.peerId
        }
    case let .legacyGroup(group):
        information = strings().messageCalendarDeleteAlertTextOther(days)
        switch group.role {
        case .creator, .admin:
            option = strings().deleteChatDeleteGroupForAll
        case .member:
            break
        }
    default:
        return
    }
    let isChannel = peer.id.namespace == Namespaces.Peer.CloudChannel
    verifyAlert(for: window, header: days == 1 ? strings().messageCalendarClearHistoryForThisDay : strings().messageCalendarClearHistoryForTheseDays, information: information, ok: strings().modalDelete, option: option, optionIsSelected: false, successHandler: { result in
        let type: InteractiveMessagesDeletionType = isChannel || result == .thrid ? .forEveryone : .forLocalPeer
        let signal = chatCalendarMessageIds(context: context, peerId: peer.id, fromId: fromId, minTimestamp: minTimestamp, maxTimestamp: maxTimestamp)
        _ = (showModalProgress(signal: signal, for: window) |> deliverOnMainQueue).start(next: { ids in
            guard !ids.isEmpty else {
                showModalText(for: window, text: strings().messageCalendarNothingToDelete)
                return
            }
            _ = context.engine.messages.deleteMessagesInteractively(messageIds: ids, type: type).start()
            done()
            showModalText(for: window, text: strings().chatMessageRangeDeletedMessagesOther(ids.count))
        })
    })
}

private func chatCalendarClearRange(context: any AccountContextProtocol, peerId: PeerId, range: ClosedRange<Date>, days: Int, media: ChatCalendarMedia, done: @escaping () -> Void) {
    let calendar = Calendar(identifier: .gregorian)
    let lower = calendar.startOfDay(for: range.lowerBound)
    guard days > 0, let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: range.upperBound)) else {
        return
    }
    let minTimestamp = Int32(lower.timeIntervalSince1970)
    let maxTimestamp = Int32(upper.timeIntervalSince1970)
    let window = context.window
    _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue).start(next: { peer in
        guard let peer else {
            return
        }
        guard case .user = peer else {
            chatCalendarClearMessages(context: context, peer: peer, minTimestamp: minTimestamp, maxTimestamp: maxTimestamp, days: days, done: done)
            return
        }
        var forEveryone: String?
        if peerId != context.peerId, case let .user(user) = peer, user.botInfo == nil {
            forEveryone = strings().chatMessageDeleteForMeAndPerson(peer._asPeer().compactDisplayTitle)
        }
        verifyAlert(for: window, header: days == 1 ? strings().messageCalendarClearHistoryForThisDay : strings().messageCalendarClearHistoryForTheseDays, information: strings().messageCalendarDeleteAlertTextOther(days), ok: strings().modalDelete, option: forEveryone, optionIsSelected: false, successHandler: { result in
            let type: InteractiveHistoryClearingType = result == .thrid ? .forEveryone : .forLocalPeer
            _ = media.source.removeMessagesInRange(minTimestamp: minTimestamp, maxTimestamp: maxTimestamp, type: type, completion: {
                withExtendedLifetime(media) {}
            })
            done()
            showModalText(for: window, text: type == .forEveryone ? strings().chatMessageRangeDeletedForBothSidesOther(days) : strings().chatMessageRangeDeletedForMeOther(days))
        })
    })
}

public func ChatCalendarController(context: any AccountContextProtocol, peerId: PeerId, current: Date, select: @escaping (Date) -> Void) -> ModalViewController {
    let media = ChatCalendarMedia(context: context, peerId: peerId)
    var close: (() -> Void)?
    let calendar = CalendarController(NSMakeRect(0, 0, CalendarModalController.calendarSize.width, CalendarModalController.calendarSize.height), context.window, current: current, selectHandler: { date in
        select(date)
        close?()
    }, autoclose: false)
    calendar.dayPreview = { timestamp in
        return media.preview(timestamp: timestamp)
    }
    let modal = CalendarModalController(calendar: calendar, title: strings().messageCalendarTitle, selectable: peerId.namespace == Namespaces.Peer.CloudUser)
    if peerId.namespace != Namespaces.Peer.CloudUser {
        _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue).start(next: { [weak modal] peer in
            modal?.canSelect = peer.map(chatCalendarCanClearRange) ?? false
        })
    }
    close = { [weak modal] in
        modal?.close()
    }
    modal.clearRange = { [weak modal, weak calendar] range in
        chatCalendarClearRange(context: context, peerId: peerId, range: range, days: calendar?.selectedDaysCount ?? 0, media: media, done: {
            modal?.close()
        })
    }
    media.start(updated: { [weak calendar] in
        calendar?.updateDayPreviews()
    })
    return modal
}

public func PlainCalendarModalController(window: Window, current: Date, select: @escaping (Date) -> Void) -> ModalViewController {
    var close: (() -> Void)?
    let calendar = CalendarController(NSMakeRect(0, 0, CalendarModalController.calendarSize.width, CalendarModalController.calendarSize.height), window, current: current, selectHandler: { date in
        select(date)
        close?()
    }, autoclose: false)
    let modal = CalendarModalController(calendar: calendar, title: strings().messageCalendarTitle)
    close = { [weak modal] in
        modal?.close()
    }
    return modal
}

public func ChatCalendarSearchController(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64?, current: Date, select: @escaping (Date) -> Void) -> ModalViewController {
    let controller = CalendarSearchController(current: current, select: select)
    guard threadId == nil, peerId.namespace != Namespaces.Peer.SecretChat else {
        return controller
    }
    let media = ChatCalendarMedia(context: context, peerId: peerId)
    controller.dayPreview = { timestamp, size in
        return media.preview(timestamp: timestamp, size: size)
    }
    media.start(updated: { [weak controller] in
        controller?.updateDayPreviews()
    })
    return controller
}
