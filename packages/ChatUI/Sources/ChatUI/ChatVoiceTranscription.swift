import Cocoa
import os.log
import QuartzCore
import AppAnalytics
import TGUIKit
import SwiftSignalKit
import InputView
import AlertsUI
import Localization
import SystemPermissions
import TelegramTheme
import ChatHistoryModel
import MediaRecorderUI
import TelegramCore

private let audioFileComposerLog = OSLog(subsystem: "org.telegram.AudioFileTranscription", category: "Composer")

protocol ChatVoiceTranscriptionHost: AnyObject {
    var transcriptionTextView: NSTextView { get }
    func updateTranscriptionLevel(_ level: CGFloat)
    func animateTranscriptionButton(from origin: ChatDictationButtonOrigin)
    func showTranscriptionView(_ view: ChatVoiceTranscriptionView)
    func hideTranscriptionView(animated: Bool)
    func showDictationEnhance(_ view: ChatDictationEnhanceView)
    func hideDictationEnhance(_ view: ChatDictationEnhanceView, animated: Bool)
}

final class ChatVoiceTranscription {
    enum Audio {
        case recording(ChatRecordingAudioState)
        case clip(Data, trimRange: Range<Double>?)
    }

    enum Phase: Equatable {
        case idle
        case preparing
        case listening
        case finishing
        case finished
    }

    private weak var chatInteraction: ChatInteraction?
    private weak var host: ChatVoiceTranscriptionHost?
    private var view: ChatVoiceTranscriptionView?
    private var engine: ChatDictationEngine?
    private let permissionDisposable = MetaDisposable()
    private let clipDisposable = MetaDisposable()
    private var token: Int = 0
    private var text: String = ""
    private var language: String?
    private var chatLanguage: String?
    private var suggestedLanguages: [String] = []
    private var closeClipRecorder: (() -> Bool)?
    private var recordingStartTime: Double = 0
    private var pendingAction: ChatVoiceTranscriptionView.Action?
    private var analyticsContext: AnalyticsContext?
    private var recordingJourney: AnalyticsRecordingJourney?
    private var analyticsPresentation: AnalyticsPresentation?
    private var audio: Audio?
    private var onEnd: (() -> Void)?
    private var composerBase: ChatTextInputState?
    private var insertion: ChatInputDictationInsertion?
    private var sessionStart: Int?
    private var updatingComposer = false
    private var textEffect: ChatDictationTextEffect?
    private var enhancer: ChatDictationEnhancer?
    private var didPlayStartFeedback = false

    private(set) var phase: Phase = .idle

    init(chatInteraction: ChatInteraction, host: ChatVoiceTranscriptionHost) {
        self.chatInteraction = chatInteraction
        self.host = host
    }

    deinit {
        permissionDisposable.dispose()
        clipDisposable.dispose()
        engine?.cancel()
    }

    static var isLiveDictationSupported: Bool {
        if #available(macOS 10.15, *) {
            return true
        }
        return false
    }

    static func canTranscribeClip(isSecretChat: Bool) -> Bool {
        return ChatRecordedAudioTranscriptionPolicy.canTranscribe(nativeAvailable: isLiveDictationSupported, isSecretChat: isSecretChat)
    }

    var isActive: Bool {
        return phase != .idle
    }

    func animateButton(from origin: ChatDictationButtonOrigin) {
        guard phase == .preparing || phase == .listening else { return }
        host?.animateTranscriptionButton(from: origin)
    }

    private var window: Window? {
        return chatInteraction?.interactionContext.window
    }

    func transcribeToComposer(recorder: ChatRecordingAudioState, analyticsContext: AnalyticsContext, journey: AnalyticsRecordingJourney?, closeRecorder: @escaping () -> Bool) {
        let isSecretChat = chatInteraction?.presentation.peer?.isSecretChat ?? true
        guard !isActive, !recorder.isCancelled, Self.canTranscribeClip(isSecretChat: isSecretChat) else {
            return
        }
        let trimRange = recorder.pendingTrimRange
        clipDisposable.set((recorder.compressedSnapshot() |> take(1) |> deliverOnMainQueue).start(next: { [weak self] clip in
            guard let self, let clip, !clip.isEmpty, !recorder.isCancelled else { return }
            self.start(analyticsContext: analyticsContext, journey: journey, audio: .clip(clip, trimRange: trimRange), closeRecorder: closeRecorder)
        }))
    }

    func start(analyticsContext: AnalyticsContext, journey: AnalyticsRecordingJourney?, audio: Audio, onEnd: (() -> Void)? = nil, closeRecorder: (() -> Bool)? = nil) {
        switch audio {
        case .recording:
            guard Self.isLiveDictationSupported else { return }
        case .clip:
            guard Self.canTranscribeClip(isSecretChat: chatInteraction?.presentation.peer?.isSecretChat ?? true) else { return }
        }
        cancelEnhance()
        if phase != .idle {
            dismiss(animated: false)
        }
        self.audio = audio
        self.closeClipRecorder = closeRecorder
        recordingStartTime = 0
        self.onEnd = onEnd
        self.analyticsContext = analyticsContext
        self.recordingJourney = journey
        journey?.beginTranscription()
        self.analyticsPresentation = analyticsContext.beginPresentation()
        token += 1
        let token = self.token
        text = ""
        language = nil
        chatLanguage = nil
        suggestedLanguages = []
        phase = .preparing
        didPlayStartFeedback = false
        prepareComposer()
        if case .clip = audio {
            pendingAction = .edit
        } else {
            pendingAction = nil
        }
        showView()

        if case let .clip(clip, trimRange) = audio {
            startRecordedTranscription(clip, trimRange: trimRange, token: token)
            return
        }
        guard #available(macOS 10.15, *) else { return }

        let detectedLanguage: Signal<String?, NoError>
        if let chatInteraction {
            detectedLanguage = chatDictationLanguage(context: chatInteraction.context, peerId: chatInteraction.peerId)
        } else {
            detectedLanguage = .single(nil)
        }
        let suggestions = chatInteraction.map { $0.context.engine.messages.getTranscriptionLanguages(peerId: $0.peerId) } ?? .single([])
        permissionDisposable.set(combineLatest(queue: .mainQueue(), analyticsContext.preservingPresentation(requestSpeechRecognitionPermission()), detectedLanguage, suggestions).start(next: { [weak self] granted, chatLanguage, suggestions in
            guard let self, self.token == token, self.phase == .preparing else {
                return
            }
            self.recordingJourney?.permissionResolved(granted: granted)
            if granted {
                self.chatLanguage = chatLanguage
                self.suggestedLanguages = suggestions
                self.createEngine(token: token)
            } else {
                self.fail(.speechDenied)
            }
        }))
    }

    private func startRecordedTranscription(_ clip: Data, trimRange: Range<Double>?, token: Int) {
        guard let chatInteraction else {
            dismiss(animated: false)
            return
        }
        phase = .finishing
        let isSecretChat = chatInteraction.presentation.peer?.isSecretChat ?? true
        os_log("recorded session started token=%{public}ld nativeAvailable=%{public}d", log: audioFileComposerLog, type: .default, token, Self.isLiveDictationSupported ? 1 : 0)
        view?.setListening(false, animated: true)
        let native: (() -> Signal<String, ChatDictationError>)?
        if #available(macOS 10.15, *) {
            native = { [weak self] in
                let language = chatDictationLanguage(context: chatInteraction.context, peerId: chatInteraction.peerId)
                let suggestions = chatInteraction.context.engine.messages.getTranscriptionLanguages(peerId: chatInteraction.peerId)
                return combineLatest(queue: .mainQueue(), requestSpeechRecognitionPermission(), language, suggestions)
                |> castError(ChatDictationError.self)
                |> mapToSignal { [weak self] granted, language, suggestions -> Signal<String, ChatDictationError> in
                    guard let self, self.token == token, self.phase == .finishing else { return .never() }
                    self.recordingJourney?.permissionResolved(granted: granted)
                    guard granted else { return .fail(.speechDenied) }
                    self.chatLanguage = language
                    self.suggestedLanguages = suggestions
                    let source = ChatDictationRecordingSource(audio: .clip(clip, trimRange: trimRange))
                    return nativeRecordedAudioTranscription { completion in
                        ChatDictationEngineFactory.make(selection: ChatInputDictationLanguage.selected, chatLanguage: language, suggestedLanguages: suggestions, requiresOnDevice: isSecretChat, source: source, completion: completion)
                    }
                }
            }
        } else {
            native = nil
        }
        let signal = transcribeRecordedAudio(native: native, server: {
            os_log("server fallback selected", log: audioFileComposerLog, type: .default)
            let request = prepareAudioFileTranscription(clip, trimRange: trimRange)
            |> mapToSignal { data, duration in
                return chatInteraction.context.engine.messages.transcribeAudioFile(data: data, duration: duration)
            }
            return finalRecordedAudioTranscript(request)
        }, isSecretChat: isSecretChat)
        let cancellable = deliverRecordedAudioTranscription(signal, cancelled: { [weak self] in
            guard let self, self.token == token, self.phase == .finishing else { return }
            self.dismiss(animated: true, keepsRecording: true)
        })
        let progress = window.map { showModalProgress(signal: cancellable, for: $0) } ?? cancellable
        permissionDisposable.set((progress |> deliverOnMainQueue).start(next: { [weak self] text in
            guard let self, self.token == token, self.phase == .finishing else { return }
            os_log("recorded response characters=%{public}ld", log: audioFileComposerLog, type: .default, text.utf16.count)
            if let closeRecorder = self.closeClipRecorder {
                let closed = closeRecorder()
                os_log("recorder close accepted=%{public}d", log: audioFileComposerLog, type: .default, closed ? 1 : 0)
                if !closed {
                    self.dismiss(animated: false)
                    return
                }
            }
            self.closeClipRecorder = nil
            self.text = text
            self.engineFinished(nil)
            os_log("completion finished composerCharacters=%{public}ld", log: audioFileComposerLog, type: .default, chatInteraction.presentation.effectiveInput.inputText.utf16.count)
        }, error: { [weak self] error in
            guard let self, self.token == token else { return }
            self.recordedTranscriptionFailed(error)
        }))
    }

    private func recordedTranscriptionFailed(_ error: ChatRecordedAudioTranscriptionError) {
        os_log("session failed reason=%{public}@", log: audioFileComposerLog, type: .error, String(describing: error))
        let window = self.window
        let analyticsContext = self.analyticsContext ?? Analytics.shared.unresolvedContext()
        dismiss(animated: true, keepsRecording: true)
        switch error {
        case let .native(error):
            showError(error, analyticsContext: analyticsContext)
        case let .server(error):
            if let window {
                alert(for: window, info: audioFileTranscriptionErrorText(error))
            }
        }
    }

    @available(macOS 10.15, *)
    private func createEngine(token: Int) {
        guard let audio else {
            fail(.unavailable)
            return
        }
        let requiresOnDevice = chatInteraction?.presentation.peer?.isSecretChat == true
        let source = ChatDictationRecordingSource(audio: audio, recordingStartTime: recordingStartTime)
        ChatDictationEngineFactory.make(selection: ChatInputDictationLanguage.selected, chatLanguage: chatLanguage, suggestedLanguages: suggestedLanguages, requiresOnDevice: requiresOnDevice, source: source, completion: { [weak self] result in
            guard let self, self.token == token, self.phase == .preparing else {
                if case let .success(engine) = result {
                    engine.cancel()
                }
                return
            }
            switch result {
            case let .success(engine):
                self.begin(with: engine, token: token)
            case let .failure(error):
                self.fail(error)
            }
        })
    }

    private func begin(with engine: ChatDictationEngine, token: Int) {
        engine.onTranscript = { [weak self] text in
            guard let self, self.token == token else {
                return
            }
            self.text = text
            self.refresh(animated: true)
        }
        engine.onLanguage = { [weak self] language in
            guard let self, self.token == token else {
                return
            }
            self.language = language
            self.refresh(animated: true)
        }
        engine.onLevel = { [weak self] level in
            guard let self, self.token == token, self.phase == .listening else {
                return
            }
            self.view?.updateLevel(level)
            self.host?.updateTranscriptionLevel(level)
        }
        engine.onFinish = { [weak self] error in
            guard let self, self.token == token else {
                return
            }
            self.engineFinished(error)
        }
        self.engine = engine
        engine.start()
        phase = .listening
        if !didPlayStartFeedback, case let .recording(recorder)? = audio, recorder.startsDictation {
            didPlayStartFeedback = true
            ChatDictationFeedback.started()
        }
        view?.setListening(true, animated: true)
        refresh(animated: true)
    }

    private func engineFinished(_ error: ChatDictationError?) {
        let wasListening = phase == .listening
        engine = nil
        if let error, wasListening, text.isEmpty {
            fail(error)
            return
        }
        phase = .finished
        view?.setListening(false, animated: true)
        refresh(animated: true)
        if let action = pendingAction {
            pendingAction = nil
            complete(action)
        } else if text.isEmpty {
            dismiss(animated: true, keepsRecording: true)
        }
    }

    func recordingStopped() {
        guard isActive else { return }
        if case .cancel? = pendingAction { return }
        switch phase {
        case .preparing:
            token += 1
            permissionDisposable.set(nil)
            phase = .finished
            view?.setListening(false, animated: true)
            fallthrough
        case .finished:
            let action = pendingAction ?? .edit
            pendingAction = nil
            complete(action)
        case .listening:
            if pendingAction == nil {
                pendingAction = .edit
            }
            phase = .finishing
            view?.setListening(false, animated: true)
            refresh(animated: true)
            engine?.stop()
        case .idle, .finishing:
            break
        }
    }

    func perform(_ action: ChatVoiceTranscriptionView.Action) {
        pendingAction = action
        switch action {
        case .cancel:
            recordingJourney?.cancel()
            if closeClipRecorder == nil {
                restoreComposer()
                discardRecording()
            }
            dismiss(animated: true)
        case .edit:
            if closeClipRecorder != nil { return }
            discardRecording()
            recordingStopped()
        }
    }

    private func complete(_ action: ChatVoiceTranscriptionView.Action) {
        let text = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chatInteraction else {
            dismiss(animated: false)
            return
        }
        switch action {
        case .edit:
            updateComposer()
            let effect = textEffect
            let inserted = insertion.map { ChatInputDictationText.sessionRange($0.insertedRange(self.text), from: sessionStart) }
            if !text.isEmpty {
                recordingJourney?.draftInserted()
            }
            chatInteraction.focusInputField()
            dismiss(animated: true)
            if !text.isEmpty {
                if let inserted {
                    effect?.finish(range: inserted)
                }
                ChatDictationFeedback.finished()
                if let inserted {
                    offerEnhance(effect: effect, range: inserted)
                }
            }
        case .cancel:
            dismiss(animated: true)
        }
    }

    private func discardRecording() {
        if let chatInteraction, let recorder = chatInteraction.presentation.recordingState, !recorder.isCancelled {
            recorder.discard(from: chatInteraction)
        }
    }

    func stopForNavigation() {
        cancelEnhance()
        guard isActive else { return }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recordingJourney?.draftInserted()
        }
        token += 1
        phase = .idle
        discardRecording()
        dismiss(animated: false)
    }

    func dismiss(animated: Bool, keepsRecording: Bool = false) {
        cancelEnhance()
        token += 1
        permissionDisposable.set(nil)
        clipDisposable.set(nil)
        closeClipRecorder = nil
        engine?.cancel()
        engine = nil
        pendingAction = nil
        phase = .idle
        text = ""
        if view != nil {
            view = nil
            host?.hideTranscriptionView(animated: animated)
        }
        if !keepsRecording {
            recordingJourney?.discard()
        }
        recordingJourney = nil
        analyticsPresentation?.end()
        analyticsPresentation = nil
        analyticsContext = nil
        audio = nil
        composerBase = nil
        insertion = nil
        sessionStart = nil
        textEffect = nil
        let onEnd = self.onEnd
        self.onEnd = nil
        onEnd?()
    }

    private func fail(_ error: ChatDictationError) {
        let analyticsContext = self.analyticsContext ?? Analytics.shared.unresolvedContext()
        let presentation = analyticsContext.beginPresentation()
        switch error {
        case .microphoneDenied, .speechDenied:
            recordingJourney?.blocked(.permission)
        default:
            recordingJourney?.blocked(.preparation)
        }
        restoreComposer()
        dismiss(animated: true, keepsRecording: true)
        showError(error, analyticsContext: analyticsContext)
        presentation.end()
    }

    private func showView() {
        guard let host, let chatInteraction else { return }
        let view = ChatVoiceTranscriptionView(context: chatInteraction.interactionContext)
        self.view = view
        host.showTranscriptionView(view)
        textEffect = ChatDictationTextEffect(textView: host.transcriptionTextView, animationsEnabled: !chatInteraction.context.isLite(.animations))
        updateComposer()
        chatInteraction.focusInputField()
        view.setListening(true, animated: true)
    }

    func composerDidUpdate(_ input: ChatTextInputState) {
        enhancer?.inputDidChange(input)
        guard isActive, !updatingComposer, let chatInteraction else { return }
        textEffect?.cancelReveal()
        let current = chatInteraction.presentation.effectiveInput
        if input.inputText == current.inputText, input.attributes == current.attributes {
            if input.selectionRange != current.selectionRange {
                insertion = makeInsertion(input, consumedTranscript: text)
                sessionStart = nil
            }
            return
        }
        insertion = makeInsertion(input, consumedTranscript: text)
        sessionStart = nil
    }

    private func offerEnhance(effect: ChatDictationTextEffect?, range: NSRange) {
        guard let chatInteraction, let host, ChatDictationEnhancer.canOffer(chatInteraction: chatInteraction, range: range) else { return }
        let enhancer = ChatDictationEnhancer(chatInteraction: chatInteraction, host: host, effect: effect, range: range)
        enhancer.onEnd = { [weak self, weak enhancer] in
            if let self, let enhancer, self.enhancer === enhancer {
                self.enhancer = nil
            }
        }
        self.enhancer = enhancer
        enhancer.show(after: 0.35)
    }

    private func cancelEnhance() {
        let enhancer = self.enhancer
        self.enhancer = nil
        enhancer?.cancel()
    }

    private func prepareComposer() {
        composerBase = chatInteraction?.presentation.effectiveInput
        insertion = composerBase.map { makeInsertion($0) }
        sessionStart = insertion?.start
    }

    private func makeInsertion(_ input: ChatTextInputState, consumedTranscript: String = "") -> ChatInputDictationInsertion {
        return ChatInputDictationInsertion(text: input.attributedString(), selection: input.selectionRange, consumedTranscript: consumedTranscript, excludingAttribute: { key, _ in
            key == TextInputAttributes.customEmoji || key == TextInputAttributes.textMention || key == TextInputAttributes.textUrl
        })
    }

    private func updateComposer() {
        guard let insertion, let chatInteraction else { return }
        let result = insertion.compose(text)
        let state = ChatTextInputState(attributedText: result.text, selectionRange: result.selection)
        guard state != chatInteraction.presentation.effectiveInput else { return }
        let previousText = chatInteraction.presentation.effectiveInput.inputText
        updatingComposer = true
        chatInteraction.update({ $0.withUpdatedEffectiveInputState(state) })
        updatingComposer = false
        textEffect?.revealChange(from: previousText, to: state.inputText)
    }

    private func restoreComposer() {
        guard let base = composerBase, let chatInteraction else {
            return
        }
        updatingComposer = true
        chatInteraction.update({ $0.withUpdatedEffectiveInputState(base) })
        updatingComposer = false
    }

    private func refresh(animated: Bool) {
        updateComposer()
        view?.setListening(phase == .listening || phase == .preparing, animated: animated)
    }

    private func restartForLanguageChange() {
        guard #available(macOS 10.15, *), phase == .listening || phase == .preparing, case let .recording(recorder)? = audio, let chatInteraction else {
            return
        }
        let switchTime = CACurrentMediaTime()
        updateComposer()
        insertion = makeInsertion(chatInteraction.presentation.effectiveInput)
        text = ""
        language = nil
        token += 1
        let token = self.token
        engine?.cancel()
        engine = nil
        phase = .preparing
        permissionDisposable.set((combineLatest(requestSpeechRecognitionPermission(), recorder.recordingState |> take(1)) |> deliverOnMainQueue).start(next: { [weak self] granted, state in
            guard let self, self.token == token, self.phase == .preparing else {
                return
            }
            guard granted else {
                self.fail(.speechDenied)
                return
            }
            switch state {
            case let .recording(duration, durationMediaTimestamp):
                self.recordingStartTime = max(0, duration + switchTime - durationMediaTimestamp)
            case let .paused(duration):
                self.recordingStartTime = duration
            }
            self.createEngine(token: token)
        }))
    }

    private func showError(_ error: ChatDictationError, analyticsContext: AnalyticsContext) {
        guard let window = self.window else {
            return
        }
        let presentation = analyticsContext.beginPresentation()
        switch error {
        case .microphoneDenied, .speechDenied:
            let information = error == .microphoneDenied ? strings().chatInputDictationErrorMicrophone : strings().chatInputDictationErrorSpeech
            verifyAlert_button(for: window, information: information, ok: strings().modalOK, cancel: "", option: strings().requestAccesErrorConirmSettings, successHandler: { result in
                switch result {
                case .thrid:
                    openSystemSettings(error == .microphoneDenied ? .microphone : .speechRecognition)
                default:
                    break
                }
            }, onDeinit: {
                presentation.end()
            })
        case .unsupportedLanguage:
            alert(for: window, info: strings().chatInputDictationErrorLanguage, onDeinit: {
                presentation.end()
            })
        case .unavailable, .failed:
            alert(for: window, info: strings().chatInputDictationErrorUnavailable, onDeinit: {
                presentation.end()
            })
        }
    }

    func languageMenu() -> ContextMenu? {
        guard let language = languageMenuItem() else {
            return nil
        }
        let menu = ContextMenu()
        menu.addItem(language)
        menu.addItem(punctuationMenuItem())
        menu.addItem(ChatDictationShortcut.menuItem())
        return menu
    }

    func punctuationMenuItem() -> ContextMenuItem {
        let enabled = ChatDictationPunctuation.automatic
        return ContextMenuItem(strings().chatVoiceTranscriptionAutomaticPunctuation, handler: { [weak self] in
            ChatDictationPunctuation.automatic = !enabled
            if self?.isActive == true {
                self?.restartForLanguageChange()
            }
        }, state: enabled ? .on : nil)
    }

    func languageMenuItem() -> ContextMenuItem? {
        guard let (submenu, current) = languageSubmenu() else {
            return nil
        }
        let item = ContextMenuItem(strings().chatVoiceTranscriptionLanguage(current))
        item.submenu = submenu
        return item
    }

    private func languageSubmenu() -> (ContextMenu, String)? {
        guard #available(macOS 10.15, *) else {
            return nil
        }
        let selection = ChatInputDictationLanguage.selected
        let options = ChatDictationEngineFactory.languages
        let selectedIdentifier = selection.flatMap { ChatDictationEngineFactory.resolveSelection($0) }
        let option: (String) -> ChatDictationLanguageOption? = { identifier in
            let language = ChatInputDictationText.languageCode(of: identifier)
            return options.first(where: { $0.identifier == identifier }) ?? options.first(where: { ChatInputDictationText.languageCode(of: $0.identifier) == language })
        }

        var preferred: [ChatDictationLanguageOption] = []
        let preferredIdentifiers = ChatInputDictationText.automaticLocales(preferred: ChatDictationEngineFactory.automaticPreferences(chatLanguage: chatLanguage, suggestedLanguages: suggestedLanguages), supported: ChatDictationEngineFactory.supportedIdentifiers, limit: .max)
        for identifier in preferredIdentifiers {
            if let value = option(identifier), !preferred.contains(where: { $0.identifier == value.identifier }) {
                preferred.append(value)
            }
        }
        let others = options.filter { value in
            return !preferred.contains(where: { $0.identifier == value.identifier })
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let requiresOnDevice = chatInteraction?.presentation.peer?.isSecretChat == true
        let automaticNames = ChatDictationEngineFactory.automaticIdentifiers(chatLanguage: chatLanguage, suggestedLanguages: suggestedLanguages, requiresOnDevice: requiresOnDevice).compactMap { option($0)?.title }
        let automaticTitle: String
        if automaticNames.isEmpty {
            automaticTitle = strings().chatInputDictationLanguageAutomatic
        } else {
            automaticTitle = "\(strings().chatInputDictationLanguageAutomatic) (\(automaticNames.joined(separator: ", ")))"
        }

        let choose: (String?) -> Void = { [weak self] code in
            guard ChatInputDictationLanguage.selected != code else {
                return
            }
            ChatInputDictationLanguage.selected = code
            self?.restartForLanguageChange()
        }

        let menu = ContextMenu()
        let info = ContextMenuItem(strings().chatVoiceTranscriptionLanguageInfo, removeTail: false, overrideWidth: 240)
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(ContextSeparatorItem())
        menu.addItem(ContextMenuItem(automaticTitle, handler: {
            choose(nil)
        }, state: selection == nil ? .on : nil))
        let title: (ChatDictationLanguageOption) -> String = { value in
            if let flag = ChatInputDictationText.flag(for: value.identifier) {
                return "\(flag) \(value.title)"
            }
            return value.title
        }
        let item: (ChatDictationLanguageOption) -> ContextMenuItem = { value in
            return ContextMenuItem(title(value), handler: {
                choose(value.code)
            }, state: selection != nil && selectedIdentifier == value.identifier ? .on : nil)
        }
        if !preferred.isEmpty {
            menu.addItem(ContextSeparatorItem())
            for value in preferred {
                menu.addItem(item(value))
            }
        }
        if !others.isEmpty {
            menu.addItem(ContextSeparatorItem())
            for value in others {
                menu.addItem(item(value))
            }
        }
        let current: String
        if selection != nil, let value = options.first(where: { $0.identifier == selectedIdentifier }) {
            current = title(value)
        } else {
            current = strings().chatInputDictationLanguageAutomatic
        }
        return (menu, current)
    }
}

enum ChatDictationPunctuation {
    private static let key = "kChatDictationAutomaticPunctuation"

    static var automatic: Bool {
        get {
            return UserDefaults.standard.object(forKey: key) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}

enum ChatDictationShortcut: String, CaseIterable {
    case automatic
    case record
    case dictate

    private static let key = "kChatDictationShortcut"

    static var current: ChatDictationShortcut {
        get {
            return UserDefaults.standard.string(forKey: key).flatMap(ChatDictationShortcut.init(rawValue:)) ?? .automatic
        }
        set {
            if newValue == .automatic {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(newValue.rawValue, forKey: key)
            }
        }
    }

    var title: String {
        switch self {
        case .automatic:
            return strings().chatInputDictationLanguageAutomatic
        case .record:
            return strings().chatVoiceTranscriptionRecordMessage
        case .dictate:
            return strings().chatInputDictationStart
        }
    }

    static func menuItem() -> ContextMenuItem {
        let item = ContextMenuItem("⌘R: \(current.title)")
        let submenu = ContextMenu()
        let info = ContextMenuItem(strings().chatVoiceTranscriptionShortcutInfo, removeTail: false, overrideWidth: 240)
        info.isEnabled = false
        submenu.addItem(info)
        submenu.addItem(ContextSeparatorItem())
        let selected = current
        for option in allCases {
            submenu.addItem(ContextMenuItem(option.title, handler: {
                ChatDictationShortcut.current = option
            }, state: option == selected ? .on : nil))
        }
        item.submenu = submenu
        return item
    }
}

enum ChatInputDictationLanguage {
    private static let key = "kChatInputDictationLanguage"

    static var selected: String? {
        get {
            return UserDefaults.standard.string(forKey: key)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
