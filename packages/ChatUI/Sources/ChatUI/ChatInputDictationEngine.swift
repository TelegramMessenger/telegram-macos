import Foundation
import AVFoundation
import Speech
import SwiftSignalKit
import Translate
import Localization

enum ChatDictationError: Error, Equatable {
    case microphoneDenied
    case speechDenied
    case unsupportedLanguage
    case unavailable
    case failed
}

protocol ChatDictationEngine: AnyObject {
    var onTranscript: ((String) -> Void)? { get set }
    var onLevel: ((CGFloat) -> Void)? { get set }
    var onLanguage: ((String) -> Void)? { get set }
    var onFinish: ((ChatDictationError?) -> Void)? { get set }
    func start()
    func stop()
    func cancel()
}

private protocol ChatDictationRecognizer: AnyObject {
    var identifier: String { get }
    var onUpdate: ((String, Double?) -> Void)? { get set }
    var onEnd: ((Bool) -> Void)? { get set }
    func start(inputFormat: AVAudioFormat)
    func append(_ buffer: AVAudioPCMBuffer)
    func finishAudio()
    func cancel()
}

@available(macOS 10.15, *)
func requestSpeechRecognitionPermission() -> Signal<Bool, NoError> {
    return Signal { subscriber in
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            subscriber.putNext(true)
            subscriber.putCompletion()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                subscriber.putNext(status == .authorized)
                subscriber.putCompletion()
            }
        default:
            subscriber.putNext(false)
            subscriber.putCompletion()
        }
        return EmptyDisposable
    } |> deliverOnMainQueue
}


private final class ChatDictationRecognizersBox: @unchecked Sendable {
    let value: [ChatDictationRecognizer]

    init(_ value: [ChatDictationRecognizer]) {
        self.value = value
    }
}

private final class ChatDictationCandidate {
    let recognizer: ChatDictationRecognizer
    let language: String
    let priority: Int
    var text: String = ""
    var stability = ChatInputDictationStability()
    var confidence: Double?
    var isEnded = false

    init(recognizer: ChatDictationRecognizer, priority: Int) {
        self.recognizer = recognizer
        self.language = ChatInputDictationText.languageCode(of: recognizer.identifier)
        self.priority = priority
    }

    var score: Double {
        return ChatInputDictationText.score(stability: stability.value, confidence: confidence, priority: priority)
    }
}

private final class ChatDictationSession: ChatDictationEngine {
    var onTranscript: ((String) -> Void)?
    var onLevel: ((CGFloat) -> Void)? {
        didSet {
            source.onLevel = onLevel
        }
    }
    var onLanguage: ((String) -> Void)?
    var onFinish: ((ChatDictationError?) -> Void)?

    private static let decisionDelay: CFTimeInterval = 1.5
    private static let forcedDecisionDelay: CFTimeInterval = 3.0
    private static let decisionMargin: Double = 0.12

    private let source: ChatDictationRecordingSource
    private let lock = NSLock()
    private var feeding: [ChatDictationRecognizer] = []
    private var fedFrames: AVAudioFramePosition = 0
    private var audioFinished = false
    private var candidates: [ChatDictationCandidate]
    private var leader: ChatDictationCandidate
    private var winner: ChatDictationCandidate?
    private var speechStart: CFTimeInterval?
    private var stopping = false
    private var finished = false
    private var timeout: DispatchWorkItem?

    init(recognizers: [ChatDictationRecognizer], source: ChatDictationRecordingSource) {
        precondition(!recognizers.isEmpty)
        self.source = source
        self.candidates = recognizers.enumerated().map { ChatDictationCandidate(recognizer: $0.element, priority: $0.offset) }
        self.leader = candidates[0]
        if candidates.count == 1 {
            self.winner = candidates[0]
        }
    }

    func start() {
        let format = source.inputFormat
        for candidate in candidates {
            candidate.recognizer.onUpdate = { [weak self, weak candidate] text, confidence in
                guard let self, let candidate else {
                    return
                }
                self.update(candidate, text: text, confidence: confidence)
            }
            candidate.recognizer.onEnd = { [weak self, weak candidate] failed in
                guard let self, let candidate else {
                    return
                }
                self.ended(candidate, failed: failed)
            }
        }
        lock.lock()
        feeding = candidates.map(\.recognizer)
        lock.unlock()
        for candidate in candidates {
            candidate.recognizer.start(inputFormat: format)
        }
        source.onEnded = { [weak self] in
            self?.stop()
        }
        source.start { [weak self] buffer in
            self?.feed(buffer)
        }
        onLanguage?(leader.language)
    }

    private func feed(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let feeding = self.feeding
        fedFrames += AVAudioFramePosition(buffer.frameLength)
        lock.unlock()
        for recognizer in feeding {
            recognizer.append(buffer)
        }
    }

    private func update(_ candidate: ChatDictationCandidate, text: String, confidence: Double?) {
        guard !finished else {
            return
        }
        if let winner {
            if winner === candidate {
                candidate.text = text
                onTranscript?(text)
            }
            return
        }
        candidate.stability.update(previous: candidate.text, current: text)
        candidate.text = text
        if let confidence {
            candidate.confidence = candidate.confidence.map { $0 * 0.6 + confidence * 0.4 } ?? confidence
        }
        if speechStart == nil, !text.isEmpty {
            speechStart = CACurrentMediaTime()
        }
        let previousLeader = leader
        if let best = candidates.filter({ !$0.text.isEmpty }).max(by: { $0.score < $1.score }) {
            leader = best
        }
        if leader !== previousLeader || candidate === leader {
            onTranscript?(leader.text)
        }
        if leader !== previousLeader {
            onLanguage?(leader.language)
        }
        evaluate()
    }

    private func evaluate() {
        guard winner == nil, let speechStart, candidates.count > 1 else {
            return
        }
        let elapsed = CACurrentMediaTime() - speechStart
        guard elapsed >= ChatDictationSession.decisionDelay else {
            return
        }
        let others = candidates.filter { $0 !== leader }
        let runnerUp = others.map(\.score).max() ?? 0
        if leader.score - runnerUp >= ChatDictationSession.decisionMargin || elapsed >= ChatDictationSession.forcedDecisionDelay {
            decide(leader)
        }
    }

    private func decide(_ chosen: ChatDictationCandidate) {
        guard winner == nil else {
            return
        }
        winner = chosen
        leader = chosen
        let losers = candidates.filter { $0 !== chosen }
        candidates = [chosen]
        lock.lock()
        feeding = [chosen.recognizer]
        lock.unlock()
        for loser in losers {
            loser.recognizer.onUpdate = nil
            loser.recognizer.onEnd = nil
            loser.recognizer.cancel()
        }
        onLanguage?(chosen.language)
        onTranscript?(chosen.text)
    }

    private func ended(_ candidate: ChatDictationCandidate, failed: Bool) {
        guard !finished else {
            return
        }
        if winner === candidate {
            finish(failed && !stopping && candidate.text.isEmpty ? .failed : nil)
            return
        }
        guard winner == nil else {
            return
        }
        candidate.recognizer.onUpdate = nil
        candidate.recognizer.onEnd = nil
        if audioFinished {
            candidate.isEnded = true
            guard candidates.allSatisfy({ $0.isEnded }) else {
                return
            }
            if let best = candidates.filter({ !$0.text.isEmpty }).max(by: { $0.score < $1.score }) {
                decide(best)
            }
            finish(nil)
            return
        }
        candidate.recognizer.cancel()
        candidates.removeAll(where: { $0 === candidate })
        lock.lock()
        feeding = candidates.map(\.recognizer)
        lock.unlock()
        if let remaining = candidates.first {
            leader = remaining
            decide(remaining)
        } else {
            finish(failed ? .failed : nil)
        }
    }

    func stop() {
        guard !finished, !stopping else {
            return
        }
        stopping = true
        source.finish { [weak self] in
            self?.finishAudio()
        }
    }

    private func finishAudio() {
        guard !finished, !audioFinished else {
            return
        }
        audioFinished = true
        for candidate in candidates {
            candidate.recognizer.finishAudio()
        }
        lock.lock()
        let seconds = Double(fedFrames) / source.inputFormat.sampleRate
        lock.unlock()
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(nil)
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 + min(60.0, seconds * 0.25), execute: timeout)
    }

    func cancel() {
        guard !finished else {
            return
        }
        onTranscript = nil
        onFinish = nil
        onLanguage = nil
        finished = true
        teardown()
    }

    private func finish(_ error: ChatDictationError?) {
        guard !finished else {
            return
        }
        finished = true
        teardown()
        let onFinish = self.onFinish
        self.onFinish = nil
        onTranscript = nil
        onLanguage = nil
        onFinish?(error)
    }

    private func teardown() {
        timeout?.cancel()
        timeout = nil
        source.onLevel = nil
        source.onEnded = nil
        source.stop()
        lock.lock()
        feeding = []
        lock.unlock()
        for candidate in candidates {
            candidate.recognizer.onUpdate = nil
            candidate.recognizer.onEnd = nil
            candidate.recognizer.cancel()
        }
    }
}

struct ChatDictationLanguageOption {
    let title: String
    let code: String
    let identifier: String
}

@available(macOS 10.15, *)
enum ChatDictationEngineFactory {
    static var supportedIdentifiers: [String] {
        return SFSpeechRecognizer.supportedLocales().map(\.identifier)
    }

    static var languages: [ChatDictationLanguageOption] {
        let supported = supportedIdentifiers
        let preferred = systemPreferences
        var identifiers: Set<String> = []
        var result: [ChatDictationLanguageOption] = []
        for value in Translate.codes {
            guard let code = value.code.first, let identifier = ChatInputDictationText.resolveLanguage(value.code, preferred: preferred, supported: supported), identifiers.insert(identifier).inserted else {
                continue
            }
            let localized = _NSLocalizedString(value.localizationKey)
            result.append(ChatDictationLanguageOption(title: localized == value.localizationKey ? value.language : localized, code: code, identifier: identifier))
        }
        return result
    }

    static func resolveSelection(_ selection: String) -> String? {
        return ChatInputDictationText.resolveLanguage([selection], preferred: systemPreferences, supported: supportedIdentifiers)
    }

    private static var systemPreferences: [String] {
        return Locale.preferredLanguages + [Locale.current.identifier]
    }

    static func automaticPreferences(chatLanguage: String?, suggestedLanguages: [String] = []) -> [String] {
        return suggestedLanguages + ChatInputDictationText.preferences(chatLanguage: chatLanguage, system: systemPreferences)
    }

    static func make(selection: String?, chatLanguage: String?, suggestedLanguages: [String] = [], requiresOnDevice: Bool, source: ChatDictationRecordingSource, completion: @escaping (Result<ChatDictationEngine, ChatDictationError>) -> Void) {
        let identifiers: [String]
        switch plan(selection: selection, chatLanguage: chatLanguage, suggestedLanguages: suggestedLanguages, requiresOnDevice: requiresOnDevice) {
        case let .success(value):
            identifiers = value
        case let .failure(error):
            completion(.failure(error))
            return
        }
        if #available(macOS 26.0, *) {
            Task {
                var recognizers: [ChatDictationRecognizer] = []
                for identifier in identifiers {
                    if let analyzer = await ChatDictationAnalyzerRecognizer.make(identifier: identifier) {
                        recognizers.append(analyzer)
                    } else if let recognizer = makeRecognizer(identifier: identifier, requiresOnDevice: requiresOnDevice || !recognizers.isEmpty) {
                        recognizers.append(recognizer)
                    }
                    if recognizers.count == 2 { break }
                }
                let box = ChatDictationRecognizersBox(recognizers)
                DispatchQueue.main.async {
                    let result = box.value
                    completion(result.isEmpty ? .failure(.unavailable) : .success(ChatDictationSession(recognizers: result, source: source)))
                }
            }
        } else {
            let recognizers = identifiers.compactMap { makeRecognizer(identifier: $0, requiresOnDevice: requiresOnDevice) }
            completion(recognizers.isEmpty ? .failure(.unavailable) : .success(ChatDictationSession(recognizers: recognizers, source: source)))
        }
    }

    private static func plan(selection: String?, chatLanguage: String?, suggestedLanguages: [String] = [], requiresOnDevice: Bool) -> Result<[String], ChatDictationError> {
        if let selection {
            guard let identifier = resolveSelection(selection) else {
                return .failure(.unsupportedLanguage)
            }
            return .success([identifier])
        }
        let candidates = ChatInputDictationText.automaticLocales(preferred: automaticPreferences(chatLanguage: chatLanguage, suggestedLanguages: suggestedLanguages), supported: supportedIdentifiers, limit: 4)
        guard !candidates.isEmpty else {
            return .failure(.unsupportedLanguage)
        }
        if #available(macOS 26.0, *) {
            return .success(candidates)
        }
        let chosen = automaticIdentifiers(candidates: candidates, requiresOnDevice: requiresOnDevice)
        return chosen.isEmpty ? .failure(.unavailable) : .success(chosen)
    }

    static func automaticIdentifiers(chatLanguage: String?, suggestedLanguages: [String] = [], requiresOnDevice: Bool) -> [String] {
        let candidates = ChatInputDictationText.automaticLocales(preferred: automaticPreferences(chatLanguage: chatLanguage, suggestedLanguages: suggestedLanguages), supported: supportedIdentifiers, limit: 4)
        return automaticIdentifiers(candidates: candidates, requiresOnDevice: requiresOnDevice)
    }

    private static func automaticIdentifiers(candidates: [String], requiresOnDevice: Bool) -> [String] {
        var chosen: [String] = []
        for identifier in candidates {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)), recognizer.isAvailable else {
                continue
            }
            let onDevice = recognizer.supportsOnDeviceRecognition
            if (requiresOnDevice || !chosen.isEmpty) && !onDevice {
                continue
            }
            chosen.append(identifier)
            if chosen.count == 2 {
                break
            }
        }
        return chosen
    }

    private static func makeRecognizer(identifier: String, requiresOnDevice: Bool) -> ChatDictationRecognizer? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)), recognizer.isAvailable else {
            return nil
        }
        if requiresOnDevice && !recognizer.supportsOnDeviceRecognition {
            return nil
        }
        return ChatDictationSFRecognizer(recognizer: recognizer, identifier: identifier)
    }
}

@available(macOS 10.15, *)
private final class ChatDictationSFRecognizer: NSObject, ChatDictationRecognizer, SFSpeechRecognizerDelegate {
    let identifier: String
    var onUpdate: ((String, Double?) -> Void)?
    var onEnd: ((Bool) -> Void)?

    private let recognizer: SFSpeechRecognizer
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var committed: String = ""
    private var partial: String = ""
    private var stopping = false
    private var ended = false
    private var lastRestart: CFTimeInterval = 0
    private var sampleRate: Double = 0
    private var appendedFrames: AVAudioFramePosition = 0
    private var rotating = false
    private var held: [AVAudioPCMBuffer] = []
    private static let requestLimit: Double = 50

    init(recognizer: SFSpeechRecognizer, identifier: String) {
        self.recognizer = recognizer
        self.identifier = identifier
        super.init()
        recognizer.delegate = self
        recognizer.queue = .main
    }

    func start(inputFormat: AVAudioFormat) {
        sampleRate = inputFormat.sampleRate
        startTask()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if rotating {
            held.append(buffer)
            lock.unlock()
            return
        }
        let request = self.request
        appendedFrames += AVAudioFramePosition(buffer.frameLength)
        let rotate = request?.requiresOnDeviceRecognition == false && sampleRate > 0 && Double(appendedFrames) >= ChatDictationSFRecognizer.requestLimit * sampleRate
        rotating = rotate
        request?.append(buffer)
        lock.unlock()
        if rotate {
            request?.endAudio()
        }
    }

    private func startTask() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        if #available(macOS 13.0, *) {
            request.addsPunctuation = ChatDictationPunctuation.automatic
        }
        lock.lock()
        self.request = request
        let held = self.held
        self.held = []
        rotating = false
        appendedFrames = 0
        for buffer in held {
            appendedFrames += AVAudioFramePosition(buffer.frameLength)
            request.append(buffer)
        }
        lock.unlock()
        let identifier = ObjectIdentifier(request)
        task = recognizer.recognitionTask(with: request, resultHandler: { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handle(result: result, error: error, request: identifier)
            }
        })
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, request identifier: ObjectIdentifier) {
        guard !ended, let current = request, ObjectIdentifier(current) == identifier else {
            return
        }
        if let result {
            partial = result.bestTranscription.formattedString
            let confidences = result.bestTranscription.segments.map { Double($0.confidence) }.filter { $0 > 0 }
            let confidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Double(confidences.count)
            onUpdate?(transcript, confidence)
            if result.isFinal {
                lock.lock()
                let carrying = rotating
                lock.unlock()
                if stopping && !carrying {
                    end(failed: false)
                } else {
                    committed = transcript
                    partial = ""
                    startTask()
                    if stopping {
                        request?.endAudio()
                    }
                }
                return
            }
        }
        if let error = error as NSError? {
            if !stopping, error.code == 1110, CACurrentMediaTime() - lastRestart > 1 {
                lastRestart = CACurrentMediaTime()
                committed = transcript
                partial = ""
                startTask()
            } else {
                end(failed: !stopping && transcript.isEmpty && ![203, 216, 301, 1110].contains(error.code))
            }
        }
    }

    private var transcript: String {
        return ChatInputDictationText.join(committed, partial)
    }

    func finishAudio() {
        guard !ended, !stopping else {
            return
        }
        stopping = true
        lock.lock()
        let rotating = self.rotating
        lock.unlock()
        if !rotating {
            request?.endAudio()
        }
    }

    func cancel() {
        guard !ended else {
            return
        }
        ended = true
        onUpdate = nil
        onEnd = nil
        teardown()
    }

    private func end(failed: Bool) {
        guard !ended else {
            return
        }
        ended = true
        teardown()
        let onEnd = self.onEnd
        self.onEnd = nil
        onUpdate = nil
        onEnd?(failed)
    }

    private func teardown() {
        task?.cancel()
        task = nil
        lock.lock()
        request = nil
        held = []
        lock.unlock()
    }

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            end(failed: transcript.isEmpty)
        }
    }
}

@available(macOS 26.0, *)
private final class ChatDictationAnalyzerRecognizer: ChatDictationRecognizer, @unchecked Sendable {
    let identifier: String
    var onUpdate: ((String, Double?) -> Void)?
    var onEnd: ((Bool) -> Void)?

    private let transcriber: DictationTranscriber
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let stream: AsyncStream<AnalyzerInput>
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converterLock = NSLock()
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?
    private var finalized: String = ""
    private var volatile: String = ""
    private var stopping = false
    private var ended = false

    private static let assetsLock = NSLock()
    private static var installing: Set<String> = []

    private static func beginAssetsInstall(_ identifier: String) -> Bool {
        assetsLock.lock()
        defer {
            assetsLock.unlock()
        }
        return installing.insert(identifier).inserted
    }

    private static func endAssetsInstall(_ identifier: String) {
        assetsLock.lock()
        installing.remove(identifier)
        assetsLock.unlock()
    }

    static func make(identifier: String) async -> ChatDictationAnalyzerRecognizer? {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
            return nil
        }
        let transcriber = DictationTranscriber(locale: locale, contentHints: [], transcriptionOptions: ChatDictationPunctuation.automatic ? [.punctuation] : [], reportingOptions: [.volatileResults], attributeOptions: [.transcriptionConfidence])
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status == .installed else {
            if status == .supported, beginAssetsInstall(locale.identifier) {
                Task.detached {
                    try? await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
                    endAssetsInstall(locale.identifier)
                }
            }
            return nil
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            return nil
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.prepareToAnalyze(in: format)
        } catch {
            await analyzer.cancelAndFinishNow()
            return nil
        }
        return ChatDictationAnalyzerRecognizer(identifier: identifier, transcriber: transcriber, analyzer: analyzer, format: format)
    }

    private init(identifier: String, transcriber: DictationTranscriber, analyzer: SpeechAnalyzer, format: AVAudioFormat) {
        self.identifier = identifier
        self.transcriber = transcriber
        self.format = format
        self.analyzer = analyzer
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.stream = stream
        self.input = input
    }

    func start(inputFormat: AVAudioFormat) {
        converterLock.lock()
        converter = AVAudioConverter(from: inputFormat, to: format)
        converterLock.unlock()

        let transcriber = self.transcriber
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    let confidence = ChatDictationAnalyzerRecognizer.confidence(of: result.text)
                    DispatchQueue.main.async {
                        self?.handle(text: text, isFinal: isFinal, confidence: confidence)
                    }
                }
                DispatchQueue.main.async {
                    self?.end(failed: false)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.end(failed: true)
                }
            }
        }

        let analyzer = self.analyzer
        let stream = self.stream
        Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                DispatchQueue.main.async {
                    self?.end(failed: true)
                }
            }
        }
    }

    private static func confidence(of text: AttributedString) -> Double? {
        var values: [Double] = []
        for run in text.runs {
            if let value = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] {
                values.append(value)
            }
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        converterLock.lock()
        let converter = self.converter
        let converted = ChatDictationAnalyzerRecognizer.convert(buffer, with: converter, to: format)
        converterLock.unlock()
        if let converted {
            input.yield(AnalyzerInput(buffer: converted))
        }
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else {
            return buffer.format == format ? buffer : nil
        }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error, withInputFrom: { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        })
        guard status != .error, error == nil, output.frameLength > 0 else {
            return nil
        }
        return output
    }

    private func handle(text: String, isFinal: Bool, confidence: Double?) {
        guard !ended else {
            return
        }
        if isFinal {
            finalized = ChatInputDictationText.join(finalized, text)
            volatile = ""
        } else {
            volatile = text
        }
        onUpdate?(ChatInputDictationText.join(finalized, volatile), confidence)
    }

    func finishAudio() {
        guard !ended, !stopping else {
            return
        }
        stopping = true
        input.finish()
        let analyzer = self.analyzer
        Task {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
    }

    func cancel() {
        guard !ended else {
            return
        }
        ended = true
        onUpdate = nil
        onEnd = nil
        teardown(cancelAnalysis: true)
    }

    private func end(failed: Bool) {
        guard !ended else {
            return
        }
        ended = true
        teardown(cancelAnalysis: !stopping)
        let onEnd = self.onEnd
        self.onEnd = nil
        onUpdate = nil
        onEnd?(failed && finalized.isEmpty && volatile.isEmpty)
    }

    private func teardown(cancelAnalysis: Bool) {
        input.finish()
        resultsTask?.cancel()
        resultsTask = nil
        if cancelAnalysis {
            let analyzer = self.analyzer
            Task {
                await analyzer.cancelAndFinishNow()
            }
        }
    }
}
