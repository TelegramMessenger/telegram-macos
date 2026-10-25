import Cocoa
import TelegramCore
import SwiftSignalKit
import Postbox
import Foundation
import InAppSettings

public final class Reactions {

    private let engine: TelegramEngine

    private let disposable = MetaDisposable()
    private let downloadable = DisposableSet()
    private let state: Promise<AvailableReactions?> = Promise()
    private let messageEffectsState: Promise<AvailableMessageEffects?> = Promise()
    private let messageEffectsDisposable = MetaDisposable()
    private let reactable = DisposableDict<MessageId>()
    
    public struct Interactive {
        public let messageId: MessageId
        public let reaction: MessageReaction.Reaction?
        public let rect: NSRect?
        public let isLarge: Bool
    }
    public struct InteractiveStatus {
        public let fileId: Int64?
        public let previousFileId: Int64?
        public let rect: NSRect?
    }
    
    public var checkStarsAmount:((Int, PeerId)->Signal<(Bool, Bool), NoError>)?
    public var failStarsAmount:((Int, MessageId)->Void)?
    public var successStarsAmount:((StarsAmount)->Void)?
    public var starsDisabled:(()->Void)?
    
    public var sentStarReactions: ((MessageId, Int)->Void)? = nil
    
    public var forceSendStarReactions: (()->Void)? = nil

    
    private var _available: AvailableReactions?
    public var available: AvailableReactions? {
        ensureLoaded()
        return _available
    }

    public var stateValue: Signal<AvailableReactions?, NoError> {
        ensureLoaded()
        return state.get() |> distinctUntilChanged |> deliverOnMainQueue
    }

    private var _availableMessageEffects: AvailableMessageEffects?
    public var availableMessageEffects: AvailableMessageEffects? {
        ensureLoaded()
        return _availableMessageEffects
    }

    public var messageEffectsValue: Signal<AvailableMessageEffects?, NoError> {
        ensureLoaded()
        return messageEffectsState.get() |> distinctUntilChanged |> deliverOnMainQueue
    }

    public var isPremium: Bool = false
    
    private let _isInteractive = Atomic<Interactive?>(value: nil)
    public var interactive: Interactive? {
        return _isInteractive.swap(nil)
    }
    
    private let _interactiveStatus = Atomic<InteractiveStatus?>(value: nil)
    public var interactiveStatus: InteractiveStatus? {
        return _interactiveStatus.swap(nil)
    }
    
    public init(_ engine: TelegramEngine) {
        self.engine = engine
    }

    private var hasLoaded = false
    private func ensureLoaded() {
        if hasLoaded { return }
        hasLoaded = true

        self.restartState()
        self.restartMessageEffectsState()

        disposable.set((state.get() |> distinctUntilChanged |> deliverOnMainQueue).start(next: { [weak self] state in
            self?._available = state
            if state == nil {
                Queue.mainQueue().after(5.0, {
                    self?.restartState()
                })
            }
        }))

        messageEffectsDisposable.set((messageEffectsState.get() |> distinctUntilChanged |> deliverOnMainQueue).start(next: { [weak self] state in
            self?._availableMessageEffects = state
            if state == nil {
                Queue.mainQueue().after(5.0, {
                    self?.restartMessageEffectsState()
                })
            }
        }))
    }

    private func restartState() {
        state.set(((engine.stickers.availableReactions() |> then(.complete() |> suspendAwareDelay(1 * 60 * 60, queue: .concurrentDefaultQueue()))) |> restart) |> distinctUntilChanged)
    }

    private func restartMessageEffectsState() {
        messageEffectsState.set(((engine.stickers.availableMessageEffects() |> then(.complete() |> suspendAwareDelay(1 * 60 * 60, queue: .concurrentDefaultQueue()))) |> restart) |> distinctUntilChanged)
    }
    
    public func react(_ messageId: MessageId, values: [UpdateMessageReaction], fromRect: NSRect? = nil, storeAsRecentlyUsed: Bool = false, isLarge: Bool = false) {
        _ = _isInteractive.swap(.init(messageId: messageId, reaction: nil, rect: fromRect, isLarge: isLarge))
        reactable.set(updateMessageReactionsInteractively(account: self.engine.account, messageIds: [messageId], reactions: values, isLarge: isLarge, storeAsRecentlyUsed: storeAsRecentlyUsed).start(), forKey: messageId)
    }
    
    public func sendStarsReaction(_ messageId: MessageId, count: Int, privacy: TelegramPaidReactionPrivacy = .default, fromRect: NSRect? = nil) {
        if let signal = checkStarsAmount?(count, messageId.peerId) {
            _ = signal.start(next: { [weak self] value, starsAllowed in
                if value && starsAllowed {
                    _ = self?._isInteractive.swap(.init(messageId: messageId, reaction: .stars, rect: fromRect, isLarge: false))
                    _ = self?.engine.messages.sendStarsReaction(id: messageId, count: count, privacy: privacy).startStandalone()
                    self?.successStarsAmount?(.init(value: -Int64(count), nanos: 0))
                    self?.sentStarReactions?(messageId, count)
                } else {
                    if !value {
                        self?.failStarsAmount?(count, messageId)
                    } else {
                        self?.starsDisabled?()
                    }
                }
            })
        }
    }
    
    public func updateQuick(_ value: MessageReaction.Reaction) {
        _ = self.engine.stickers.updateQuickReaction(reaction: value).start()
    }
    
    public func setStatus(_ file: TelegramMediaFile, peer: Peer, timestamp: Int32, timeout: Int32?, fromRect: NSRect?, handleInteractive: Bool = true, starGift: StarGift.UniqueGift? = nil) {
        let emojiStatus: PeerEmojiStatus?
        if let channel = peer as? TelegramChannel {
            emojiStatus = channel.emojiStatus
        } else if let user = peer as? TelegramUser, user.id == self.engine.account.peerId {
            emojiStatus = user.emojiStatus
        } else {
            return
        }

        let expiryDate: Int32?
        if let timeout, timeout != 0 {
            guard timeout > 0, let date = Int32(exactly: Int64(timestamp) + Int64(timeout)) else {
                return
            }
            expiryDate = date
        } else {
            expiryDate = nil
        }

        let isSameStatus: Bool
        if let starGift {
            if case let .starGift(id, _, _, _, _, _, _, _, _)? = emojiStatus?.content {
                isSameStatus = id == starGift.id
            } else {
                isSameStatus = false
            }
        } else if case let .emoji(fileId)? = emojiStatus?.content {
            isSameStatus = fileId == file.fileId.id
        } else {
            isSameStatus = false
        }
        let isClearItem = starGift == nil && file.mimeType.hasPrefix("bundle")
        let shouldClear = isClearItem || isSameStatus

        if let channel = peer as? TelegramChannel {
            if shouldClear {
                _ = engine.peers.updatePeerEmojiStatus(peerId: channel.id, fileId: nil, expirationDate: nil).start()
            } else if let starGift {
                _ = engine.peers.updatePeerStarGiftStatus(peerId: channel.id, starGift: starGift, expirationDate: expiryDate).start()
            } else {
                _ = engine.peers.updatePeerEmojiStatus(peerId: channel.id, fileId: file.fileId.id, expirationDate: expiryDate).start()
            }
            return
        }

        if handleInteractive {
            if shouldClear {
                if isClearItem, emojiStatus != nil {
                    _ = _interactiveStatus.swap(.init(fileId: nil, previousFileId: emojiStatus?.fileId, rect: fromRect))
                } else {
                    _ = _interactiveStatus.swap(nil)
                }
            } else {
                _ = _interactiveStatus.swap(.init(fileId: file.fileId.id, previousFileId: emojiStatus?.fileId, rect: fromRect))
            }
        }
        if shouldClear {
            _ = engine.accountData.setEmojiStatus(file: nil, expirationDate: nil).start()
        } else if let starGift {
            _ = engine.accountData.setStarGiftStatus(starGift: starGift, expirationDate: expiryDate).start()
        } else {
            _ = engine.accountData.setEmojiStatus(file: file, expirationDate: expiryDate).start()
        }
        _ = updateSomeSettingsInteractively(postbox: self.engine.account.postbox, { current in
            var current = current
            current.focusIntentStatusFallback = nil
            current.focusIntentStatusEnabled = false
            return current
        }).startStandalone()
    }

    deinit {
        downloadable.dispose()
        disposable.dispose()
        messageEffectsDisposable.dispose()
        reactable.dispose()
    }
    
}
