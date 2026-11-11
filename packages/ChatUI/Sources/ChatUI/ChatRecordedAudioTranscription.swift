import Foundation
import SwiftSignalKit
import TelegramCore

enum ChatRecordedAudioTranscriptionError: Error, Equatable {
    case native(ChatDictationError)
    case server(AudioFileTranscriptionError)
}

enum ChatRecordedAudioTranscriptionPolicy {
    static func canTranscribe(nativeAvailable: Bool, isSecretChat: Bool) -> Bool {
        return nativeAvailable || !isSecretChat
    }

    static func showsRecorderButton(nativeAvailable: Bool, isPaused: Bool, isSecretChat: Bool) -> Bool {
        return nativeAvailable || (isPaused && !isSecretChat)
    }

    static func canUseServer(after error: ChatDictationError, isSecretChat: Bool) -> Bool {
        guard !isSecretChat else { return false }
        switch error {
        case .unsupportedLanguage, .unavailable, .failed:
            return true
        case .microphoneDenied, .speechDenied:
            return false
        }
    }
}

func finalRecordedAudioTranscript(_ signal: Signal<AudioFileTranscription, AudioFileTranscriptionError>, timeout: Double = 120) -> Signal<String, AudioFileTranscriptionError> {
    return signal
    |> filter { !$0.isPending }
    |> take(1)
    |> map { $0.text }
    |> SwiftSignalKit.timeout(timeout, queue: Queue.concurrentDefaultQueue(), alternate: .fail(.timedOut))
}

private func requireRecordedAudioText<E>(_ signal: Signal<String, E>, emptyError: E) -> Signal<String, E> {
    return Signal { subscriber in
        let hasText = Atomic(value: false)
        return signal.start(next: { text in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                subscriber.putError(emptyError)
                return
            }
            _ = hasText.swap(true)
            subscriber.putNext(text)
        }, error: subscriber.putError, completed: {
            if hasText.with({ $0 }) {
                subscriber.putCompletion()
            } else {
                subscriber.putError(emptyError)
            }
        })
    }
}

func transcribeRecordedAudio(native: (() -> Signal<String, ChatDictationError>)?, server: @escaping () -> Signal<String, AudioFileTranscriptionError>, isSecretChat: Bool) -> Signal<String, ChatRecordedAudioTranscriptionError> {
    return deferred {
        let serverResult: () -> Signal<String, ChatRecordedAudioTranscriptionError> = {
            return requireRecordedAudioText(server(), emptyError: .failed)
            |> mapError { ChatRecordedAudioTranscriptionError.server($0) }
        }
        guard let native else {
            return isSecretChat ? .fail(.native(.unavailable)) : serverResult()
        }
        return requireRecordedAudioText(native(), emptyError: .failed)
        |> mapError { ChatRecordedAudioTranscriptionError.native($0) }
        |> `catch` { error -> Signal<String, ChatRecordedAudioTranscriptionError> in
            guard case let .native(nativeError) = error,
                  ChatRecordedAudioTranscriptionPolicy.canUseServer(after: nativeError, isSecretChat: isSecretChat) else {
                return .fail(error)
            }
            return serverResult()
        }
    }
}

func deliverRecordedAudioTranscription(_ signal: Signal<String, ChatRecordedAudioTranscriptionError>, cancelled: @escaping () -> Void) -> Signal<String, ChatRecordedAudioTranscriptionError> {
    return Signal { subscriber in
        let terminal = Atomic(value: false)
        let disposable = (signal |> deliverOnMainQueue).start(next: { text in
            _ = terminal.swap(true)
            subscriber.putNext(text)
        }, error: { error in
            _ = terminal.swap(true)
            subscriber.putError(error)
        }, completed: {
            _ = terminal.swap(true)
            subscriber.putCompletion()
        })
        return ActionDisposable {
            disposable.dispose()
            if !terminal.swap(true) {
                Queue.mainQueue().async(cancelled)
            }
        }
    }
}

func nativeRecordedAudioTranscription(makeEngine: @escaping (@escaping (Result<ChatDictationEngine, ChatDictationError>) -> Void) -> Void) -> Signal<String, ChatDictationError> {
    return Signal { subscriber in
        let session = ChatRecordedAudioNativeSession(subscriber: subscriber)
        session.start(makeEngine: makeEngine)
        return ActionDisposable {
            Queue.mainQueue().async {
                session.cancel()
            }
        }
    } |> runOn(Queue.mainQueue())
}

private final class ChatRecordedAudioNativeSession {
    private let subscriber: Subscriber<String, ChatDictationError>
    private var engine: ChatDictationEngine?
    private var text = ""
    private var finished = false

    init(subscriber: Subscriber<String, ChatDictationError>) {
        self.subscriber = subscriber
    }

    func start(makeEngine: (@escaping (Result<ChatDictationEngine, ChatDictationError>) -> Void) -> Void) {
        makeEngine { [weak self] result in
            guard let self, !self.finished else {
                if case let .success(engine) = result { engine.cancel() }
                return
            }
            switch result {
            case let .failure(error):
                self.finish(error)
            case let .success(engine):
                self.engine = engine
                engine.onTranscript = { [weak self] text in
                    self?.text = text
                }
                engine.onFinish = { [weak self] error in
                    self?.finish(error)
                }
                engine.start()
            }
        }
    }

    private func finish(_ error: ChatDictationError?) {
        guard !finished else { return }
        finished = true
        let text = self.text
        tearDown()
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            subscriber.putNext(text)
            subscriber.putCompletion()
        } else {
            subscriber.putError(error ?? .failed)
        }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        tearDown()
    }

    private func tearDown() {
        let engine = self.engine
        self.engine = nil
        engine?.onTranscript = nil
        engine?.onFinish = nil
        engine?.onLanguage = nil
        engine?.onLevel = nil
        engine?.cancel()
    }
}
