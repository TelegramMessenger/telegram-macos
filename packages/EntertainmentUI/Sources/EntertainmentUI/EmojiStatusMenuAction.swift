import Foundation
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TGUIKit
import Localization

final class EmojiStatusMenuAction {
    private let disposable = MetaDisposable()
    private var operationId: UUID?

    func reset() {
        self.operationId = nil
        self.disposable.set(nil)
    }

    func perform(context: any AccountContextProtocol, file: TelegramMediaFile, window: Window, canPresent: @escaping () -> Bool) {
        guard self.operationId == nil, context.isPremium, file.isCustomEmoji, canPresent(), self.operationId == nil else { return }
        let operationId = UUID()
        self.operationId = operationId
        let pending = MetaDisposable()
        self.disposable.set(pending)
        let applied = ValuePromise<Bool>(false, ignoreRepeated: true)
        _ = context.engine.accountData.setEmojiStatus(file: file, expirationDate: nil).startStandalone(completed: {
            applied.set(true)
        })
        let signal = applied.get()
        |> filter { $0 }
        |> take(1)
        |> ignoreValues
        |> deliverOnMainQueue
        |> afterDisposed { [weak self] in
            Queue.mainQueue().justDispatch { [weak self] in
                guard let self, self.operationId == operationId else { return }
                self.reset()
            }
        }
        pending.set(showModalProgress(signal: signal, for: window, shouldPresent: canPresent).start(error: { [weak self, weak window] _ in
            self?.finish(operationId, window: window, canPresent: canPresent, success: false)
        }, completed: { [weak self, weak window] in
            self?.finish(operationId, window: window, canPresent: canPresent, success: true)
        }))
    }

    private func finish(_ operationId: UUID, window: Window?, canPresent: () -> Bool, success: Bool) {
        guard self.operationId == operationId else { return }
        defer {
            if self.operationId == operationId {
                self.operationId = nil
            }
        }
        self.disposable.set(nil)
        guard self.operationId == operationId, canPresent(), self.operationId == operationId, let window else { return }
        showModalText(for: window, text: success ? strings().emojiContextSetStatusSuccess : strings().unknownError)
    }

    deinit {
        self.disposable.dispose()
    }
}
