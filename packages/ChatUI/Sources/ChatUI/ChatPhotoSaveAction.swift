import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramMediaUtils
import MessageUtils
import FilePanels
import AlertsUI
import Localization

enum ChatPhotoSaveAction {
    struct Item {
        let message: Message
        let image: TelegramMediaImage
        let representation: TelegramMediaImageRepresentation
    }

    enum SaveError: Error {
        case unavailable
        case download
        case write
    }

    static func items(from messages: [Message], cachedData: CachedPeerData?) -> [Item] {
        var seen = Set<MessageId>()
        return messages.sorted { $0.index < $1.index }.compactMap { message in
            guard seen.insert(message.id).inserted,
                  message.adAttribute == nil,
                  !message.containsSecretMedia,
                  !message.isCopyProtected(cachedData: cachedData),
                  let image = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage,
                  let representation = image.representations.max(by: {
                      Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height)
                  }) else {
                return nil
            }
            return Item(message: message, image: image, representation: representation)
        }
    }

    private static func path(for item: Item, account: Account) -> Signal<String, SaveError> {
        return Signal { subscriber in
            let disposables = DisposableSet()
            let reference = ImageMediaReference.message(message: MessageReference(item.message), media: item.image)
            let fetch = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: reference.userLocation, userContentType: reference.userContentType, reference: reference.resourceReference(item.representation.resource), statsCategory: .image)
            disposables.add(fetch.start(error: { _ in subscriber.putError(.download) }))
            let data = account.postbox.mediaBox.resourceData(item.representation.resource)
            |> filter { $0.complete }
            |> take(1)
            disposables.add(data.start(next: { data in
                subscriber.putNext(data.path)
                subscriber.putCompletion()
            }))
            return disposables
        }
    }

    static func save(_ messages: [Message], chatInteraction: ChatInteraction) {
        let context = chatInteraction.interactionContext
        let window = context.window
        selectFolder(for: window) { directory in
            let currentItems = context.account.postbox.transaction { transaction -> [Item] in
                return messages.flatMap { message in
                    let current = transaction.getMessage(message.id) ?? message
                    return items(from: [current], cachedData: transaction.getPeerCachedData(peerId: current.id.peerId))
                }
            }
            |> castError(SaveError.self)
            |> mapToSignal { items -> Signal<[URL], SaveError> in
                guard !items.isEmpty else { return .fail(.unavailable) }
                return combineLatest(items.map { path(for: $0, account: context.account) })
                |> take(1)
                |> mapToSignal { paths -> Signal<[URL], SaveError> in
                    return Signal { subscriber in
                        let cancelled = Atomic(value: false)
                        Queue.concurrentDefaultQueue().async {
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "en_US_POSIX")
                            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                            let files = zip(items, paths).map { item, path in
                                let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.message.timestamp)))
                                return ChatPhotoBatchWriter.File(source: URL(fileURLWithPath: path), name: "photo_\(date)_\(item.message.id.id).jpg")
                            }
                            do {
                                let saved = try ChatPhotoBatchWriter.copy(files, to: URL(fileURLWithPath: directory, isDirectory: true), cancelled: { cancelled.with { $0 } })
                                if !cancelled.with({ $0 }) {
                                    subscriber.putNext(saved)
                                    subscriber.putCompletion()
                                }
                            } catch {
                                if !cancelled.with({ $0 }) { subscriber.putError(.write) }
                            }
                        }
                        return ActionDisposable { _ = cancelled.swap(true) }
                    }
                }
            }
            _ = showModalProgress(signal: currentItems, for: window).startStandalone(next: { _ in
                FilePanelsHooks.shared?.showSavedPathSuccess(directory)
            }, error: { _ in
                alert(for: window, info: strings().unknownError)
            })
        }
    }
}
