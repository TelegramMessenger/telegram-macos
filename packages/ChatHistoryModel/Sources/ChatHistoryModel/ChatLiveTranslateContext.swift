import Foundation
import NaturalLanguage
import Postbox
import SwiftSignalKit
import TelegramCore
import Translate
import InAppSettings
import TGUIKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization



public struct ChatTranslationState: Codable {
    public enum CodingKeys: String, CodingKey {
        case baseLang
        case fromLang
        case toLang
        case isEnabled
        case paywall
        case tone
    }

    public var baseLang: String
    public var fromLang: String
    public var toLang: String?
    public var isEnabled: Bool?
    public var paywall: Bool
    public var tone: TranslationTone?

    public init(
        baseLang: String,
        fromLang: String,
        toLang: String?,
        isEnabled: Bool?,
        paywall: Bool,
        tone: TranslationTone? = nil
    ) {
        self.baseLang = baseLang
        self.fromLang = fromLang
        self.toLang = toLang
        self.isEnabled = isEnabled
        self.paywall = paywall
        self.tone = tone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.baseLang = try container.decode(String.self, forKey: .baseLang)
        self.fromLang = try container.decode(String.self, forKey: .fromLang)
        self.toLang = try container.decodeIfPresent(String.self, forKey: .toLang)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
        self.paywall = try container.decodeIfPresent(Bool.self, forKey: .paywall) ?? false
        if let toneRaw = try container.decodeIfPresent(String.self, forKey: .tone) {
            self.tone = TranslationTone(rawValue: toneRaw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.baseLang, forKey: .baseLang)
        try container.encode(self.fromLang, forKey: .fromLang)
        try container.encodeIfPresent(self.toLang, forKey: .toLang)
        try container.encodeIfPresent(self.isEnabled, forKey: .isEnabled)
        try container.encode(self.paywall, forKey: .paywall)
        try container.encodeIfPresent(self.tone?.rawValue, forKey: .tone)
    }
}


private func cachedChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id) -> Signal<ChatTranslationState?, NoError> {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    
    return engine.data.subscribe(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
}

private func updateChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id, state: ChatTranslationState?) -> Signal<Never, NoError> {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    
    if let state = state {
        return engine.itemCache.put(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key, item: state)
    } else {
        return engine.itemCache.remove(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key)
    }
}

public func updateChatTranslationStateInteractively(engine: TelegramEngine, peerId: EnginePeer.Id, _ f: @escaping (ChatTranslationState) -> ChatTranslationState) -> Signal<Never, NoError> {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    
    return engine.data.get(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
    |> mapToSignal { current -> Signal<Never, NoError> in
        if let current = current {
            return updateChatTranslationState(engine: engine, peerId: peerId, state: f(current))
        } else {
            return .never()
        }
    }
}



private func chatTranslationLanguageCode(_ code: String) -> String {
    let components = code.replacingOccurrences(of: "_", with: "-").lowercased().components(separatedBy: "-")
    let language = components.first ?? code
    switch language {
    case "zh":
        if components.contains("hans") {
            return "zh-CN"
        }
        if components.contains("hant") || components.contains("tw") || components.contains("hk") || components.contains("mo") {
            return "zh-TW"
        }
        return "zh-CN"
    case "iw":
        return "he"
    default:
        return Translate.normalizeLanguageCode(language)
    }
}

@available(macOS 10.14, *)
private let chatTranslationRecognizableLanguages: Set<String> = {
    var languages: [NLLanguage] = [
        .amharic, .arabic, .armenian, .bengali, .bulgarian, .burmese,
        .catalan, .cherokee, .croatian, .czech, .danish, .dutch,
        .english, .finnish, .french, .georgian, .german, .greek,
        .gujarati, .hebrew, .hindi, .hungarian, .icelandic, .indonesian,
        .italian, .japanese, .kannada, .khmer, .korean, .lao,
        .malay, .malayalam, .marathi, .mongolian, .norwegian, .oriya,
        .persian, .polish, .portuguese, .punjabi, .romanian, .russian,
        .simplifiedChinese, .sinhalese, .slovak, .spanish, .swedish,
        .tamil, .telugu, .thai, .tibetan, .traditionalChinese, .turkish,
        .ukrainian, .urdu, .vietnamese
    ]
    if #available(macOS 13.0, *) {
        languages.append(.kazakh)
    }
    return Set(languages.map { chatTranslationLanguageCode($0.rawValue) })
}()

private func chatTranslationNeedsTranslation(_ texts: [String], toLang: String) -> Bool {
    let target = chatTranslationLanguageCode(toLang)
    guard #available(macOS 10.14, *) else {
        return false
    }
    guard chatTranslationRecognizableLanguages.contains(target) else {
        return false
    }
    let recognizer = NLLanguageRecognizer()
    for text in texts {
        var needsTranslation = false
        text.enumerateSubstrings(in: text.startIndex ..< text.endIndex, options: .bySentences) { sentence, _, _, stop in
            var remaining = (sentence ?? "")[...]
            while !remaining.isEmpty {
                let sample = String(remaining.prefix(256))
                remaining = remaining.dropFirst(sample.count)
                recognizer.processString(sample)
                let language = recognizer.languageHypotheses(withMaximum: 1).first
                recognizer.reset()
                if let language = language, language.value >= 0.9, chatTranslationLanguageCode(language.key.rawValue) != target {
                    needsTranslation = true
                    stop = true
                    break
                }
            }
        }
        if needsTranslation {
            return true
        }
    }
    return false
}

private func chatTranslationTexts(_ blocks: [InstantPageBlock]) -> [String] {
    var texts: [String] = []
    for block in blocks {
        switch block {
        case let .title(text), let .subtitle(text), let .header(text), let .subheader(text),
             let .paragraph(text), let .footer(text), let .kicker(text), let .thinking(text),
             let .heading(text, _), let .authorDate(text, _), let .preformatted(text, _):
            texts.append(text.plainText)
        case let .list(items, _):
            for item in items {
                switch item {
                case let .text(text, _, _):
                    texts.append(text.plainText)
                case let .blocks(blocks, _, _):
                    texts.append(contentsOf: chatTranslationTexts(blocks))
                case .unknown:
                    break
                }
            }
        case let .blockQuote(blocks, caption, _), let .details(caption, blocks, _):
            texts.append(caption.plainText)
            texts.append(contentsOf: chatTranslationTexts(blocks))
        case let .pullQuote(text, caption):
            texts.append(contentsOf: [text.plainText, caption.plainText])
        case let .cover(block):
            texts.append(contentsOf: chatTranslationTexts([block]))
        case let .table(title, rows, _, _, _):
            texts.append(title.plainText)
            for row in rows {
                texts.append(contentsOf: row.cells.compactMap { $0.text?.plainText })
            }
        case let .postEmbed(_, _, _, _, _, blocks, caption), let .collage(blocks, caption), let .slideshow(blocks, caption):
            texts.append(contentsOf: chatTranslationTexts(blocks))
            texts.append(contentsOf: [caption.text.plainText, caption.credit.plainText])
        case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _),
             let .audio(_, caption), let .document(_, caption), let .webEmbed(_, _, _, caption, _, _, _),
             let .map(_, _, _, _, caption):
            texts.append(contentsOf: [caption.text.plainText, caption.credit.plainText])
        case let .buttonRow(_, buttons):
            texts.append(contentsOf: buttons.map { $0.text.plainText })
        case let .relatedArticles(title, _):
            texts.append(title.plainText)
        default:
            break
        }
    }
    return texts
}

public func canTranslateChatMessage(_ message: Message, accountPeerId: PeerId?, toLang: String, transcription: Bool = false) -> Bool {
    guard let accountPeerId = accountPeerId, message.author?.id == accountPeerId || !message.effectivelyIncoming(accountPeerId) else {
        return true
    }
    if transcription {
        guard let transcription = message.audioTranscription, !transcription.isPending else {
            return false
        }
        return chatTranslationNeedsTranslation([transcription.text], toLang: toLang)
    }
    var texts = [message.text]
    if let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
        texts.append(contentsOf: chatTranslationTexts((rich.fullInstantPage ?? rich.instantPage).blocks))
    }
    if let poll = message.media.first as? TelegramMediaPoll {
        texts.append(poll.text)
        texts.append(contentsOf: poll.options.map { $0.text })
        if let solution = poll.results.solution {
            texts.append(solution.text)
        }
    }
    return chatTranslationNeedsTranslation(texts, toLang: toLang)
}

public struct ChatTranslationSource: Equatable {
    private let text: String
    private let entities: [MessageTextEntity]
    private let richText: [InstantPageBlock]?
    private let pollTexts: [String]

    public init(_ message: Message) {
        self.text = message.text
        self.entities = message.textEntitiesAttribute?.entities ?? []
        let richText = message.attributes.compactMap { $0 as? RichTextMessageAttribute }.first
        self.richText = richText.map { ($0.fullInstantPage ?? $0.instantPage).blocks }
        if let poll = message.media.first as? TelegramMediaPoll {
            self.pollTexts = [poll.text] + poll.options.map { $0.text } + (poll.results.solution.map { [$0.text] } ?? [])
        } else {
            self.pollTexts = []
        }
    }
}

struct ChatTranslationMessages {
    let messages: [Message]
    let sources: [ChatLiveTranslateContext.State.Key: ChatTranslationSource]
    let eligibility: [ChatLiveTranslateContext.State.Key: ChatTranslationSource]

    init(_ messages: [Message], replies: [Message], accountPeerId: PeerId?, toLang: String) {
        let eligible = messages.filter { canTranslateChatMessage($0, accountPeerId: accountPeerId, toLang: toLang) }
        var ids = Set<MessageId>()
        self.messages = (eligible + replies).filter { ids.insert($0.id).inserted }.sorted(by: { $0.id < $1.id })
        var sources: [ChatLiveTranslateContext.State.Key: ChatTranslationSource] = [:]
        for message in messages + replies {
            let key = ChatLiveTranslateContext.State.Key(id: message.id, toLang: toLang)
            if sources[key] == nil {
                sources[key] = ChatTranslationSource(message)
            }
        }
        self.sources = sources
        var eligibility: [ChatLiveTranslateContext.State.Key: ChatTranslationSource] = [:]
        for message in eligible {
            let key = ChatLiveTranslateContext.State.Key(id: message.id, toLang: toLang)
            eligibility[key] = sources[key]
        }
        self.eligibility = eligibility
    }
}

public final class ChatLiveTranslateContext {

    public struct State : Equatable {

        public enum Result : Equatable {
            case loading(toLang: String)
            case complete(toLang: String)
            public var toLang: String {
                switch self {
                case let .loading(toLang):
                    return toLang
                case let .complete(toLang):
                    return toLang
                }
            }
        }

        public enum TranscriptionResult : Equatable {
            case loading(toLang: String)
            case complete(toLang: String, text: String)
            public var toLang: String {
                switch self {
                case let .loading(toLang):
                    return toLang
                case let .complete(toLang, _):
                    return toLang
                }
            }
            public var text: String? {
                switch self {
                case .loading:
                    return nil
                case let .complete(_, text):
                    return text
                }
            }
        }

        public enum SummarizeResult : Equatable {
            case loading(toLang: String?)
            case complete(toLang: String?)

            public var toLang: String? {
                switch self {
                case let .loading(toLang):
                    return toLang
                case let .complete(toLang):
                    return toLang
                }
            }
        }

        public var canTranslate: Bool
        public var translate: Bool
        public var autotranslate: Bool
        public var from: String
        public var to: String
        public var paywall: Bool
        public var tone: TranslationTone = .neutral

        public struct Key: Hashable {
            public let id: MessageId
            public let toLang: String

            public static func Key(id: MessageId, toLang: String) -> Key {
                return .init(id: id, toLang: toLang)
            }
            public init(id: MessageId, toLang: String) {
                self.id = id
                self.toLang = toLang
            }
        }

        public struct TranscriptionKey: Hashable {
            public let id: MessageId
            public let toLang: String

            public static func Key(id: MessageId, toLang: String) -> TranscriptionKey {
                return .init(id: id, toLang: toLang)
            }
            public init(id: MessageId, toLang: String) {
                self.id = id
                self.toLang = toLang
            }
        }

        public struct SummarizeKey: Hashable {
            public let id: MessageId

            public static func Key(id: MessageId) -> SummarizeKey {
                return .init(id: id)
            }
            public init(id: MessageId) {
                self.id = id
            }
        }

        public var result:[Key : Result]
        public var translationEligibility: [Key: ChatTranslationSource] = [:]
        public var transcriptionResult:[TranscriptionKey : TranscriptionResult]
        public var summarizeResult:[SummarizeKey : SummarizeResult]

        public static var `default`: State {
            return .init(canTranslate: false, translate: false, autotranslate: false, from: "", to: "", paywall: false, tone: .neutral, result: [:], transcriptionResult: [:], summarizeResult: [:])
        }

        public func translationResult(for message: Message, accountPeerId: PeerId?) -> Result? {
            guard canTranslate, translate, canTranslateChatMessage(message, accountPeerId: accountPeerId, toLang: to) else {
                return nil
            }
            if message.hasTranslationAttribute(toLang: to) {
                return .complete(toLang: to)
            }
            return result[.Key(id: message.id, toLang: to)]
        }

        public func replyTranslationResult(for message: Message) -> Result? {
            if canTranslate, translate, message.hasTranslationAttribute(toLang: to) {
                return .complete(toLang: to)
            }
            return result[.Key(id: message.id, toLang: to)]
        }

        mutating func updateTranslation(_ batch: ChatTranslationMessages, toLang: String) {
            guard canTranslate, translate, to == toLang else {
                return
            }
            for (key, source) in batch.sources {
                if let previous = translationEligibility[key], previous != source {
                    result.removeValue(forKey: key)
                    queued.removeAll(where: { $0.id == key.id })
                }
            }
            for message in batch.messages {
                let key = Key(id: message.id, toLang: toLang)
                if message.hasTranslationAttribute(toLang: toLang) {
                    result[key] = .complete(toLang: toLang)
                } else if result[key] == .complete(toLang: toLang) {
                    result.removeValue(forKey: key)
                    queued.removeAll(where: { $0.id == message.id })
                }
            }
            translationEligibility = batch.eligibility
        }

        public func transcriptionTranslationResult(for message: Message, accountPeerId: PeerId?) -> TranscriptionResult? {
            guard canTranslate, translate, canTranslateChatMessage(message, accountPeerId: accountPeerId, toLang: to, transcription: true) else {
                return nil
            }
            return transcriptionResult[.Key(id: message.id, toLang: to)]
        }

        public struct Transcription : Equatable {
            public var messageId: MessageId
            public var string: String
            public init(messageId: MessageId, string: String) {
                self.messageId = messageId
                self.string = string
            }
        }

        fileprivate var queued:[Message] = []
        fileprivate var queuedTranscriptions:[Transcription] = []
        fileprivate var queuedSummarizes:[Message] = []
        public init(canTranslate: Bool, translate: Bool, autotranslate: Bool, from: String, to: String, paywall: Bool, tone: TranslationTone = .neutral, result: [Key : Result], transcriptionResult: [TranscriptionKey : TranscriptionResult], summarizeResult: [SummarizeKey : SummarizeResult]) {
            self.canTranslate = canTranslate
            self.translate = translate
            self.autotranslate = autotranslate
            self.from = from
            self.to = to
            self.paywall = paywall
            self.tone = tone
            self.result = result
            self.transcriptionResult = transcriptionResult
            self.summarizeResult = summarizeResult
        }
    }
    
    private let peerId: PeerId
    private let context: any AccountContextProtocol
    
    
    
    private let statePromise = ValuePromise<State>(ignoreRepeated: true)
    private let stateValue = Atomic(value: State.default)

    private func updateState(_ f: (State) -> State) -> Void {
        statePromise.set(stateValue.modify (f))
    }

    private let shouldDisposable = MetaDisposable()
    private let actionsDisposable = DisposableSet()
    private let holderDisposable = MetaDisposable()

    private let summarizeCompletedPipe = ValuePipe<MessageId>()
    public var summarizeCompleted: Signal<MessageId, NoError> {
        return summarizeCompletedPipe.signal()
    }
    private var pendingSummarizeScrollMessageId: MessageId?
    deinit {
        shouldDisposable.dispose()
        actionsDisposable.dispose()
        holderDisposable.dispose()
    }
    
    public init(peerId: PeerId, context: any AccountContextProtocol) {
        self.peerId = peerId
        self.context = context
        
        let cachedData = getCachedDataView(peerId: peerId, postbox: context.account.postbox) |> map {
            $0
        }
        
        let translationState = chatTranslationState(context: context, peerId: peerId)
        
        let autoTranslate = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.AutoTranslateEnabled(id: peerId))


        
        let should: Signal<(ChatTranslationState?, Appearance, Bool, Bool), NoError> = combineLatest(queue: prepareQueue, cachedData, translationState, baseAppSettings(accountManager: context.sharedContext.accountManager), appearanceSignal, getPeerView(peerId: context.peerId, postbox: context.account.postbox), autoTranslate) |> map { cachedData, translationState, settings, appearance, peer, autoTranslate in
            
            var isHidden: Bool
            if let cachedData = cachedData as? CachedChannelData {
                isHidden = cachedData.flags.contains(.translationHidden)
            } else if let cachedData = cachedData as? CachedGroupData {
                isHidden = cachedData.flags.contains(.translationHidden)
            } else if let cachedData = cachedData as? CachedUserData {
                isHidden = cachedData.flags.contains(.translationHidden)
            } else {
                isHidden = true
            }
            
            var translationState = translationState
            if let peer = peer {
                if !peer.isPremium {
                    let showPaywall = settings.paywall?.show ?? true
                    translationState?.paywall = showPaywall
                    isHidden = isHidden || !showPaywall
                } else {
                    translationState?.paywall = false
                }
            }
            
            let translateConfig = AppConfigTranslateState(rawValue: context.appConfiguration.getStringValue("translations_auto_enabled", orElse: "enabled")) ?? .disabled

            if !isHidden, !translateConfig.canTranslate {
                isHidden = true
            }
            
            if !isHidden && translationState?.fromLang != translationState?.toLang  {
                return (translationState, appearance, peer?.isPremium == true, autoTranslate)
            } else {
                return (nil, appearance, peer?.isPremium == true, autoTranslate)
            }
            
        } |> deliverOnPrepareQueue
        
        shouldDisposable.set(should.start(next: { [weak self] state, appearance, isPremium, autoTranslate in
            self?.updateState { current in
                var current = current
                let to = Translate.normalizeLanguageCode(state?.toLang ?? appearance.languageCode)
                let toUpdated = current.to != to
                current.tone = state?.tone ?? .neutral
                if let state = state, state.fromLang != to, state.fromLang != "" {
                    current.from = state.fromLang
                    current.to = to
                    current.canTranslate = true
                } else {
                    current.canTranslate = false
                }
                if let isEnabled = state?.isEnabled {
                    current.translate = isEnabled && isPremium
                } else if autoTranslate {
                    current.translate = true
                } else {
                    current.translate = false
                }
                
                
                current.autotranslate = autoTranslate
                current.paywall = isPremium ? false : (state?.paywall ?? false)
                if !current.canTranslate || !current.translate || toUpdated {
                    current.result = [:]
                    current.translationEligibility = [:]
                    current.queued = []
                    current.queuedTranscriptions = []
                    self?.holder.removeAll()
                    //current.transcriptionResult = [:]
                }
                return current
            }
        }))
        actionsDisposable.add(state.start(next: { [weak self] state in
            prepareQueue.justDispatch {
                if !state.queued.isEmpty {
                    var textCount: Int = 0
                    var count: Int = 0
                    let messages = state.queued.reversed().filter { state.result[.Key(id: $0.id, toLang: state.to)] == nil }.prefix(while: { msg in
                        textCount += msg.text.count
                        count += 1
                        return textCount < 25000 && count < 21
                    }).uniqueElements

                    let messageIds = messages.map { $0.id }.uniqueElements.sorted(by: >)
                    if !messageIds.isEmpty {
                        self?.activateTranslation(for: messageIds, state: state)
                    }
                }
                if !state.queuedTranscriptions.isEmpty {
                    let transcriptions = state.queuedTranscriptions.filter { state.transcriptionResult[.Key(id: $0.messageId, toLang: state.to)] == nil }
                    for transcription in transcriptions {
                        self?.activateTranscriptionTranslation(for: transcription.messageId, text: transcription.string, state: state)
                    }
                }
                if !state.queuedSummarizes.isEmpty {
                    let summarizes = state.queuedSummarizes.filter { state.summarizeResult[.Key(id: $0.id)] == nil }
                    for message in summarizes {
                        self?.activateSummarization(for: message, state: state)
                    }
                }
            }
        }))
    }
        
    private func activateTranslation(for msgIds: [MessageId], state: State) -> Void {
        let signal = context.engine.messages.translateMessages(messageIds: msgIds, fromLang: nil, toLang: state.to, enableLocalIfPossible: false, tone: state.tone)

        actionsDisposable.add(signal.start(error: { [weak self] error in
            self?.updateState { current in
                var current = current
                for id in msgIds {
                    current.result.removeValue(forKey: .Key(id: id, toLang: current.to))
                }
                return current
            }
        }))

        self.updateState { current in
            var current = current
            current.queued.removeAll()
            for id in msgIds {
                current.result[.Key(id: id, toLang: current.to)] = .loading(toLang: current.to)
            }
            return current
        }
    }

    private func activateTranscriptionTranslation(for messageId: MessageId, text: String, state: State) -> Void {
        let signal = context.engine.messages.translate(text: text, toLang: state.to, entities: [], tone: state.tone)
        |> deliverOn(prepareQueue)

        actionsDisposable.add(signal.start(next: { [weak self] result in
            self?.updateState { current in
                var current = current
                if let translatedText = result?.0 {
                    current.transcriptionResult[.Key(id: messageId, toLang: current.to)] = .complete(toLang: current.to, text: translatedText)
                } else {
                    current.transcriptionResult.removeValue(forKey: .Key(id: messageId, toLang: current.to))
                }
                return current
            }
        }, error: { [weak self] error in
            self?.updateState { current in
                var current = current
                current.transcriptionResult.removeValue(forKey: .Key(id: messageId, toLang: current.to))
                return current
            }
        }))

        self.updateState { current in
            var current = current
            current.queuedTranscriptions.removeAll(where: { $0.messageId == messageId })
            current.transcriptionResult[.Key(id: messageId, toLang: current.to)] = .loading(toLang: current.to)
            return current
        }
    }

    private func activateSummarization(for message: Message, state: State) -> Void {
        let toLang: String? = state.to
        let context = self.context
        let signal = context.engine.messages.summarizeMessage(messageId: message.id, translateToLang: toLang)
        |> deliverOn(prepareQueue)

        actionsDisposable.add(signal.start(error: { [weak self] error in
            self?.updateState { current in
                var current = current
                current.summarizeResult.removeValue(forKey: .Key(id: message.id))
                return current
            }
            if self?.pendingSummarizeScrollMessageId == message.id {
                self?.pendingSummarizeScrollMessageId = nil
            }
            DispatchQueue.main.async {
                switch error {
                case .limitExceeded:
                    showModalText(for: context.window, text: strings().loginFloodWait)
                case .generic, .invalidMessageId, .invalidLanguage:
                    showModalText(for: context.window, text: strings().unknownError)
                case .limitExceededPremium:
                    showModalText(for: context.window, text: strings().unknownError)
                }
            }
        }, completed: { [weak self] in
            self?.updateState { current in
                var current = current
                current.summarizeResult[.Key(id: message.id)] = .complete(toLang: toLang)
                return current
            }
            if self?.pendingSummarizeScrollMessageId == message.id {
                self?.pendingSummarizeScrollMessageId = nil
                self?.summarizeCompletedPipe.putNext(message.id)
            }
        }))

        self.updateState { current in
            var current = current
            current.queuedSummarizes.removeAll(where: { $0.id == message.id })
            current.summarizeResult[.Key(id: message.id)] = .loading(toLang: toLang)
            return current
        }
    }

    public func summarize(_ message: Message) {
        prepareQueue.justDispatch { [weak self] in
            guard let self = self else {
                return
            }
            let existingResult = self.stateValue.with { $0.summarizeResult[.Key(id: message.id)] }
            if existingResult != nil {
                return
            }

            let toLang: String? = self.stateValue.with { $0.to }
            if let summarizeAttribute = message.summarizeAttribute, summarizeAttribute.summaryForLang(toLang) != nil {
                self.updateState { current in
                    var current = current
                    current.summarizeResult[.Key(id: message.id)] = .complete(toLang: toLang)
                    return current
                }
                self.summarizeCompletedPipe.putNext(message.id)
                return
            }

            self.pendingSummarizeScrollMessageId = message.id
            self.updateState { current in
                var current = current
                if !current.queuedSummarizes.contains(where: { $0.id == message.id }) {
                    current.queuedSummarizes.append(message)
                }
                return current
            }
        }
    }

    public func clearSummarize(_ messageId: MessageId) {
        prepareQueue.justDispatch { [weak self] in
            self?.updateState { current in
                var current = current
                current.summarizeResult.removeValue(forKey: .Key(id: messageId))
                current.queuedSummarizes.removeAll(where: { $0.id == messageId })
                return current
            }
            self?.summarizeCompletedPipe.putNext(messageId)
        }
    }

    public func toggleTranslate() {
        
        let state = stateValue.with { $0 }
        
        _ = updateChatTranslationStateInteractively(engine: context.engine, peerId: peerId, { current in
            var current = current
            if let isEnabled = current.isEnabled {
                current.isEnabled = !isEnabled
            } else {
                current.isEnabled = !state.autotranslate
            }
            return current
        }).start()
    }
    
    public var state: Signal<State, NoError> {
        return statePromise.get()
    }
    
    private var holder: [MessageId: ChatTranslationSource] = [:]
    
    public func translate(_ message: [Message], replies: [Message] = []) {
        prepareQueue.justDispatch { [weak self] in
            guard let `self` = self else {
                return
            }
            let toLang = self.stateValue.with { $0.to }
            let isEnabled = self.stateValue.with { $0.canTranslate && $0.translate }
            if !isEnabled {
                return
            }
            let batch = ChatTranslationMessages(message, replies: replies, accountPeerId: self.context.peerId, toLang: toLang)
            let msgs = batch.messages.filter { !$0.hasTranslationAttribute(toLang: toLang) }

            self.updateState { current in
                var current = current
                current.updateTranslation(batch, toLang: toLang)
                return current
            }
            let sources = Dictionary(uniqueKeysWithValues: msgs.map { ($0.id, ChatTranslationSource($0)) })
            if self.holder != sources {
                self.holder = sources
                let signal = Signal<Void, NoError>.complete() |> delay(0.01, queue: prepareQueue)
                
                self.holderDisposable.set(signal.start(completed: { [weak self] in
                    guard let `self` = self else {
                        return
                    }
                //    self.holder.removeAll()
                    self.updateState { current in
                        var current = current
                        if current.canTranslate, current.translate, current.to == toLang {
                            for msg in msgs {
                                if current.result[.Key(id: msg.id, toLang: current.to)] == nil {
                                    current.queued.append(msg)
                                }
                            }
                        }
                        return current
                    }
                }))
            }
        }
    }
    
    public func hideTranslation() {
        _ = context.engine.messages.togglePeerMessagesTranslationHidden(peerId: self.peerId, hidden: true).start()
        _ = updateChatTranslationStateInteractively(engine: context.engine, peerId: peerId, { current in
            var current = current
            current.isEnabled = false
            return current
        }).start()
    }
    public func translate(toLang: String) -> Void {
        _ = updateChatTranslationStateInteractively(engine: context.engine, peerId: peerId, { current in
            var current = current
            current.toLang = toLang
            current.isEnabled = true
            return current
        }).start()
    }

    public func setTone(_ tone: TranslationTone) {
        _ = updateChatTranslationStateInteractively(engine: context.engine, peerId: peerId, { current in
            var current = current
            current.tone = tone
            return current
        }).start()
    }

    public func translateTranscription(_ messages: [Message]) {
        prepareQueue.justDispatch { [weak self] in
            guard let `self` = self else {
                return
            }
            let isEnabled = self.stateValue.with { $0.canTranslate && $0.translate }
            if !isEnabled {
                return
            }
            let toLang = self.stateValue.with { $0.to }

            let messagesToQueue = messages.compactMap { message -> State.Transcription? in
                guard canTranslateChatMessage(message, accountPeerId: self.context.peerId, toLang: toLang, transcription: true), let transcription = message.audioTranscription, !transcription.text.isEmpty else {
                    return nil
                }
                let existingResult = self.stateValue.with { $0.transcriptionResult[.Key(id: message.id, toLang: toLang)] }
                if existingResult != nil {
                    return nil
                }
                return State.Transcription(messageId: message.id, string: transcription.text)
            }

            if messagesToQueue.isEmpty {
                return
            }

            self.updateState { current in
                var current = current
                if current.translate {
                    for transcription in messagesToQueue {
                        if !current.queuedTranscriptions.contains(where: { $0.messageId == transcription.messageId }) {
                            current.queuedTranscriptions.append(transcription)
                        }
                    }
                }
                return current
            }
        }
    }
    
    public func enablePaywall() -> Void {
        _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, {
            $0.withUpdatedPaywall($0.paywall?.increase() ?? .initialize())
        }).start()
    }
    public func disablePaywall() -> Void {
        _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, {
            $0.withUpdatedPaywall($0.paywall?.flush())
        }).start()
    }
}

extension MessageTextEntityType {
    public var isCode: Bool {
        switch self {
        case .Code, .Pre:
            return true
        default:
            return false
        }
    }
}

public func chatTranslationState(context: any AccountContextProtocol, peerId: EnginePeer.Id) -> Signal<ChatTranslationState?, NoError> {
    let baseLang = appAppearance.languageCode
    return baseAppSettings(accountManager: context.sharedContext.accountManager)
    |> mapToSignal { settings in
        if !settings.translateChats {
            return .single(nil)
        }
        
        var dontTranslateLanguages: [String] = []
        if !settings.doNotTranslate.isEmpty {
            dontTranslateLanguages = Array(settings.doNotTranslate)
        } else {
            dontTranslateLanguages = [baseLang]
        }
        
        return cachedChatTranslationState(engine: context.engine, peerId: peerId)
        |> mapToSignal { cached in
            if let cached = cached, cached.baseLang == baseLang {
                if !dontTranslateLanguages.contains(cached.fromLang) {
                    return .single(cached)
                } else {
                    return .single(nil)
                }
            } else {
                return .single(nil)
                |> then(
                    context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 32, fixedCombinedReadStates: nil)
                    |> filter { messageHistoryView -> Bool in
                        return messageHistoryView.0.entries.count > 10
                    }
                    |> take(1)
                    |> map { messageHistoryView, _, _ -> ChatTranslationState? in
                        let messages = messageHistoryView.entries.map(\.message)

                        var fromLangs: [String: Int] = [:]
                        var count = 0
                        for message in messages {
                            if message.text.count > 10 {
                                var text = String(message.text.prefix(256))
                                if var entities = message.textEntitiesAttribute?.entities.filter({ $0.type.isCode }) {
                                    entities = entities.sorted(by: { $0.range.lowerBound > $1.range.lowerBound })
                                    var ranges: [Range<String.Index>] = []
                                    for entity in entities {
                                        if entity.range.lowerBound > text.count || entity.range.upperBound > text.count {
                                            continue
                                        }
                                        ranges.append(text.index(text.startIndex, offsetBy: entity.range.lowerBound) ..< text.index(text.startIndex, offsetBy: entity.range.upperBound))
                                    }
                                    for range in ranges {
                                        text.removeSubrange(range)
                                    }
                                }
                                if text.count < 10 {
                                    continue
                                }

                                let fromLang = Translate.detectLanguage(for: text)
                                if let fromLang = fromLang {
                                    fromLangs[fromLang] = (fromLangs[fromLang] ?? 0) + 1
                                    count += 1
                                }
                            }
                            if count >= 16 {
                                break
                            }
                        }

                        var mostFrequent: (String, Int)?
                        if count >= 5 {
                            for (lang, count) in fromLangs {
                                if let current = mostFrequent {
                                    if count > current.1 {
                                        mostFrequent = (lang, count)
                                    }
                                } else {
                                    mostFrequent = (lang, count)
                                }
                            }
                        }
                        if let fromLang = mostFrequent?.0 {
                            let state = ChatTranslationState(baseLang: baseLang, fromLang: fromLang, toLang: nil, isEnabled: nil, paywall: false)
                            let _ = updateChatTranslationState(engine: context.engine, peerId: peerId, state: state).start()
                            if !dontTranslateLanguages.contains(fromLang) {
                                return state
                            } else {
                                return nil
                            }
                        } else {
                            return nil
                        }
                    }
                )
            }
        }
    }
}

