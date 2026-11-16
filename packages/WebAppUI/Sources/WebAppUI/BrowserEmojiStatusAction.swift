import Foundation
import CoreFoundation
import SwiftSignalKit
import TelegramContext
import TelegramCore
import Postbox
import TGUIKit
import InputDataUI
import InAppSettings
import Localization

final class BrowserEmojiStatusAction {
    enum Failure: String, Error {
        case invalidEmoji = "SUGGESTED_EMOJI_INVALID"
        case invalidDuration = "DURATION_INVALID"
        case userDeclined = "USER_DECLINED"
        case serverError = "SERVER_ERROR"
        case unknownError = "UNKNOWN_ERROR"
    }

    struct Parameters {
        let fileId: Int64
        let duration: Int32?

        func expirationDate(timestamp: Int32) -> Result<Int32?, Failure> {
            guard let duration, duration != 0 else {
                return .success(nil)
            }
            guard let date = Int32(exactly: Int64(timestamp) + Int64(duration)) else {
                return .failure(.invalidDuration)
            }
            return .success(date)
        }
    }

    static func parse(_ data: [String: Any]?, timestamp: Int32) -> Result<Parameters, Failure> {
        guard let text = data?["custom_emoji_id"] as? String, let fileId = Int64(text), fileId != 0 else {
            return .failure(.invalidEmoji)
        }
        var duration: Int32?
        if let value = data?["duration"] {
            let integer: Int64?
            if let text = value as? String {
                integer = Int64(text)
            } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                integer = Int64(exactly: number.doubleValue)
            } else {
                integer = nil
            }
            guard let integer, integer >= 0, let seconds = Int32(exactly: integer) else {
                return .failure(.invalidDuration)
            }
            duration = seconds == 0 ? nil : seconds
        }
        let parameters = Parameters(fileId: fileId, duration: duration)
        switch parameters.expirationDate(timestamp: timestamp) {
        case .success:
            return .success(parameters)
        case let .failure(error):
            return .failure(error)
        }
    }

    private final class Request {
        private enum Phase {
            case loading
            case prompt
            case applying
            case settings
            case finished
        }

        private let context: any AccountContextProtocol
        private let bot: Peer
        private let parameters: Parameters
        private weak var window: Window?
        private let canPresent: () -> Bool
        private let completion: (Failure?) -> Void
        private let finished: (Request) -> Void
        private let disposable = MetaDisposable()
        private var phase = Phase.loading
        private var cancelled = false
        private var dismissPrompt: (() -> Void)?

        init(context: any AccountContextProtocol, bot: Peer, parameters: Parameters, window: Window, canPresent: @escaping () -> Bool, completion: @escaping (Failure?) -> Void, finished: @escaping (Request) -> Void) {
            self.context = context
            self.bot = bot
            self.parameters = parameters
            self.window = window
            self.canPresent = canPresent
            self.completion = completion
            self.finished = finished
        }

        func cancel() {
            self.cancelled = true
            self.phase = .finished
            self.disposable.dispose()
            let dismiss = self.dismissPrompt
            self.dismissPrompt = nil
            dismiss?()
        }

        private func isCurrent(_ phase: Phase) -> Bool {
            guard self.phase == phase else { return false }
            guard self.canPresent(), self.window != nil else {
                self.cancel()
                self.finished(self)
                return false
            }
            return !self.cancelled && self.phase == phase
        }

        private func finish(_ error: Failure?, openPremium: Bool = false) {
            guard self.phase != .finished else { return }
            self.phase = .finished
            defer { self.finished(self) }
            self.disposable.dispose()
            let dismiss = self.dismissPrompt
            self.dismissPrompt = nil
            dismiss?()
            guard !self.cancelled, self.canPresent(), let window = self.window else { return }
            if openPremium {
                BrowserHooks.shared.openPremiumBoarding(self.context, window)
            } else if error == nil {
                showModalText(for: window, text: strings().emojiContextSetStatusSuccess)
            }
            guard !self.cancelled, self.canPresent() else { return }
            self.completion(error)
        }

        func start() {
            guard self.isCurrent(.loading), let window = self.window else { return }
            let pending = MetaDisposable()
            self.disposable.set(pending)
            var received = false
            let signal = self.context.inlinePacksContext.load(fileId: self.parameters.fileId)
            |> take(1)
            |> deliverOnMainQueue
            |> afterDisposed { [weak self] in
                Queue.mainQueue().justDispatch { [weak self] in
                    guard let self, self.isCurrent(.loading) else { return }
                    self.finish(.userDeclined)
                }
            }
            pending.set(showModalProgress(signal: signal, for: window).start(next: { [weak self] file in
                received = true
                guard let self, self.isCurrent(.loading) else { return }
                guard let file, file.fileId.id == self.parameters.fileId, file.isCustomEmoji else {
                    self.finish(.invalidEmoji)
                    return
                }
                self.askPermission(file)
            }, completed: { [weak self] in
                guard !received, let self, self.isCurrent(.loading) else { return }
                self.finish(.invalidEmoji)
            }))
        }

        private func askPermission(_ file: TelegramMediaFile) {
            guard self.isCurrent(.loading), let window = self.window else { return }
            self.phase = .prompt
            let modal = WebbotEmojisetModal(context: self.context, bot: .init(self.bot), file: file, completed: { [weak self] result in
                guard let self, self.isCurrent(.prompt) else { return }
                switch result {
                case .success:
                    self.apply(file)
                case .fail:
                    self.finish(.userDeclined)
                }
            })
            guard self.isCurrent(.prompt) else {
                modal.close()
                return
            }
            self.dismissPrompt = { [weak modal] in modal?.close() }
            showModal(with: modal, for: window)
        }

        private func apply(_ file: TelegramMediaFile) {
            guard self.isCurrent(.prompt) else { return }
            guard self.context.isPremium else {
                self.finish(.userDeclined, openPremium: true)
                return
            }
            let expirationDate: Int32?
            switch self.parameters.expirationDate(timestamp: self.context.timestamp) {
            case let .success(date):
                expirationDate = date
            case let .failure(error):
                self.finish(error)
                return
            }
            self.phase = .applying
            let pending = MetaDisposable()
            self.disposable.set(pending)
            guard self.isCurrent(.applying) else { return }
            pending.set((self.context.engine.accountData.setEmojiStatusWithResult(file: file, expirationDate: expirationDate)
            |> deliverOnMainQueue).start(error: { [weak self] _ in
                guard let self, self.isCurrent(.applying) else { return }
                self.finish(.serverError)
            }, completed: { [weak self] in
                guard let self, self.isCurrent(.applying) else { return }
                self.updateSettings()
            }))
        }

        private func updateSettings() {
            self.phase = .settings
            let pending = MetaDisposable()
            self.disposable.set(pending)
            guard self.isCurrent(.settings) else { return }
            pending.set((updateSomeSettingsInteractively(postbox: self.context.account.postbox) { current in
                var current = current
                current.focusIntentStatusFallback = nil
                current.focusIntentStatusEnabled = false
                return current
            } |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let self, self.isCurrent(.settings) else { return }
                self.finish(nil)
            }))
        }

        deinit {
            self.disposable.dispose()
            self.dismissPrompt?()
        }
    }

    private var request: Request?
    var isPending: Bool { self.request != nil }

    func open(context: any AccountContextProtocol, bot: Peer, parameters: Parameters, window: Window, canPresent: @escaping () -> Bool, completion: @escaping (Failure?) -> Void) {
        guard self.request == nil, canPresent() else { return }
        let request = Request(context: context, bot: bot, parameters: parameters, window: window, canPresent: canPresent, completion: completion, finished: { [weak self] request in
            if self?.request === request { self?.request = nil }
        })
        self.request = request
        request.start()
    }

    func reset() {
        let request = self.request
        self.request = nil
        request?.cancel()
    }

    deinit {
        self.request?.cancel()
    }
}
