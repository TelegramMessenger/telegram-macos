import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import FetchManager
import InAppSettings

public func isMessageCopyProtected(_ id: MessageId?, postbox: Postbox) -> Signal<Bool, NoError> {
    guard let id else {
        return .single(false)
    }
    return postbox.transaction { transaction -> Bool in
        guard let message = transaction.getMessage(id) else {
            return false
        }
        if message.containsSecretMedia || message.isCopyProtected() {
            return true
        }
        if let cachedData = transaction.getPeerCachedData(peerId: id.peerId) as? CachedUserData {
            return cachedData.flags.contains(.copyProtectionEnabled) || cachedData.flags.contains(.myCopyProtectionEnabled)
        }
        return false
    }
}

private final class DownloadedMediaStoreContext {
    private let queue: Queue
    private var disposable: Disposable?
    
    public init(queue: Queue) {
        self.queue = queue
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    public func start(postbox: Postbox, storeSettings: Signal<AutomaticMediaDownloadSettings, NoError>, timestamp: Int32, media: AnyMediaReference, completed: @escaping () -> Void) {
        var resource: TelegramMediaResource?
        if let image = media.media as? TelegramMediaImage {
            resource = largestImageRepresentation(image.representations)?.resource
        } else if let file = media.media as? TelegramMediaFile {
            resource = file.resource
        }
        if let resource = resource {
            var messageId: MessageId?
            if case let .message(message, _) = media {
                messageId = message.id
            }
            self.disposable = (combineLatest(storeSettings, isMessageCopyProtected(messageId, postbox: postbox))
            |> map { _, isCopyProtected -> Bool in
                return !isCopyProtected
            }
            |> take(1)
            |> mapToSignal { store -> Signal<MediaResourceData, NoError> in
                if !store {
                    return .complete()
                } else {
                    return postbox.mediaBox.resourceData(resource)
                }
            }
            |> deliverOn(queue)).start(next: { data in
                if !data.complete {
                    return
                }
                let storeAsset: () -> Void = {
                    if let file = media.media as? TelegramMediaFile {
                        if !file.isMusic && !file.isAnimated && !file.isVideo && !file.isVoice && !file.isInstantVideo && !file.isSticker {
                            _ = copyToDownloads(file, postbox: postbox).start()
                        }
                    }
                }
                
                storeAsset()

                completed()
            })
        } else {
            completed()
        }
    }
}

private final class DownloadedMediaStoreManagerPrivateImpl {
    private let queue: Queue
    private let postbox: Postbox
    
    private var storeContexts: [MediaId: DownloadedMediaStoreContext] = [:]
    
    private let storeSettings = Promise<AutomaticMediaDownloadSettings>()
    
    public init(queue: Queue, postbox: Postbox, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.queue = queue
        self.postbox = postbox
        
        self.storeSettings.set(automaticDownloadSettings(postbox: postbox))
    }
    
    deinit {
        assert(self.queue.isCurrent())
    }
    
    public func store(_ media: AnyMediaReference, timestamp: Int32) {
        guard let id = media.media.id else {
            return
        }
        
        if self.storeContexts[id] == nil {
            let context = DownloadedMediaStoreContext(queue: self.queue)
            self.storeContexts[id] = context
            context.start(postbox: self.postbox, storeSettings: self.storeSettings.get(), timestamp: timestamp, media: media, completed: { [weak self, weak context] in
                guard let strongSelf = self, let context = context else {
                    return
                }
                assert(strongSelf.queue.isCurrent())
                if strongSelf.storeContexts[id] === context {
                    strongSelf.storeContexts.removeValue(forKey: id)
                }
            })
        }
    }
}

public final class DownloadedMediaStoreManagerImpl: DownloadedMediaStoreManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<DownloadedMediaStoreManagerPrivateImpl>
    
    public init(postbox: Postbox, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return DownloadedMediaStoreManagerPrivateImpl(queue: queue, postbox: postbox, accountManager: accountManager)
        })
    }
    
    public func store(_ media: AnyMediaReference, timestamp: Int32) {
        self.impl.with { impl in
            impl.store(media, timestamp: timestamp)
        }
    }
}
