import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TGUIKit

final class GiftWearAction {
    enum Outcome {
        case applied
        case failed
        case premiumRequired
        case boostRequired(TelegramChannel, ChannelBoostStatus, MyBoostStatus?)
    }

    private let disposable = MetaDisposable()
    private var operationId: UUID?
    private(set) var isActive = true

    func setActive(_ active: Bool) {
        self.isActive = active
        if !active {
            self.reset()
        }
    }

    func reset() {
        self.operationId = nil
        self.disposable.set(nil)
    }

    private static func acknowledged<E>(_ signal: Signal<Never, E>) -> Signal<Outcome, NoError> {
        return signal
        |> map { _ in Outcome.applied }
        |> then(.single(.applied))
        |> `catch` { _ in .single(.failed) }
    }

    func perform(context: any AccountContextProtocol, peer: EnginePeer, gift: StarGift.UniqueGift, window: Window, canPresent: @escaping () -> Bool, completion: @escaping (Outcome) -> Void) {
        guard self.isActive, self.operationId == nil, canPresent(), self.isActive, self.operationId == nil else { return }
        let operationId = UUID()
        self.operationId = operationId
        let pending = MetaDisposable()
        self.disposable.set(pending)
        let signal: Signal<Outcome, NoError>
        let ownerId = gift.owner?.peerId ?? gift.hostPeerId
        if ownerId != peer.id {
            signal = .single(.failed)
        } else if let channel = peer._asPeer() as? TelegramChannel {
            if (channel.approximateBoostLevel ?? 0) < StarsHooks.shared.wearGiftBoostLevel(context) {
                signal = combineLatest(context.engine.peers.getChannelBoostStatus(peerId: channel.id), context.engine.peers.getMyBoostStatus())
                |> take(1)
                |> map { stats, myStatus -> Outcome in
                    guard let stats else { return .failed }
                    return .boostRequired(channel, stats, myStatus)
                }
                |> then(.single(.failed))
                |> take(1)
            } else {
                signal = Self.acknowledged(context.engine.peers.updatePeerStarGiftStatus(peerId: channel.id, starGift: gift, expirationDate: nil))
            }
        } else if peer._asPeer() is TelegramUser, peer.id == context.peerId {
            if context.isPremium {
                signal = Self.acknowledged(context.engine.accountData.setStarGiftStatusWithResult(starGift: gift, expirationDate: nil))
            } else {
                signal = .single(.premiumRequired)
            }
        } else {
            signal = .single(.failed)
        }
        pending.set(showModalProgress(signal: signal |> deliverOnMainQueue |> afterDisposed { [weak self] in
            Queue.mainQueue().justDispatch { [weak self] in
                guard let self, self.operationId == operationId else { return }
                self.reset()
            }
        }, for: window, shouldPresent: canPresent).start(next: { [weak self] outcome in
            guard let self, self.isActive, self.operationId == operationId else { return }
            defer {
                if self.operationId == operationId {
                    self.operationId = nil
                }
            }
            self.disposable.set(nil)
            guard self.isActive, self.operationId == operationId, canPresent(), self.isActive, self.operationId == operationId else { return }
            completion(outcome)
        }))
    }

    deinit {
        self.disposable.dispose()
    }
}
