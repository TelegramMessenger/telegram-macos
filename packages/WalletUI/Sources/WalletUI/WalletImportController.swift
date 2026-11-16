import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Postbox
import TelegramCore
import Cocoa
import TGUIKit
import SwiftSignalKit
import WalletContext
import PasscodeCore
import AppAnalytics

public struct WalletOnboardingStep {
    public let controller: InputDataController
    public let acceptTitle: String
    public let isAcceptEnabled: () -> Bool
    public let accept: () -> Void
}

public enum WalletImportMode : Equatable {
    case importWallet
    case enterRecoveryPhrase
    case enableBackup(expectedAddress: String)
    case verify([String], keyRotation: Bool, allowsRepeatedCompletion: Bool = false)
}

private let walletWordSeparators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

private final class Arguments {
    let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    let mode: WalletImportMode
    let setWordCount: (Int) -> Void
    let applySuggestion: (Int, String) -> Void
    let pastePhrase: (TableRowItem) -> Void
    let showSecretPhraseReason: () -> Void
    let wordUpdated: () -> Void

    init(context: any AccountContextProtocol, environment: WalletUIEnvironment, mode: WalletImportMode, setWordCount: @escaping (Int) -> Void, applySuggestion: @escaping (Int, String) -> Void, pastePhrase: @escaping (TableRowItem) -> Void, showSecretPhraseReason: @escaping () -> Void, wordUpdated: @escaping () -> Void) {
        self.context = context
        self.environment = environment
        self.mode = mode
        self.setWordCount = setWordCount
        self.applySuggestion = applySuggestion
        self.pastePhrase = pastePhrase
        self.showSecretPhraseReason = showSecretPhraseReason
        self.wordUpdated = wordUpdated
    }
}

struct WalletWordSuggestions: Equatable {
    var index: Int
    var words: [String]
    var isInvalid: Bool = false
}

struct WalletImportState: Equatable {
    var words: [String]
    var displayNumbers: [Int]
    var suggestions: WalletWordSuggestions? = nil
    var isImporting: Bool = false
    var mismatchedIndices: Set<Int> = []
    var hasPasteboardText: Bool = false
}

func walletNormalizeWord(_ word: String) -> String {
    return word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

func walletIsPhraseValid(_ state: WalletImportState, verification: Bool, isMnemonicWord: (String) -> Bool) -> Bool {
    if verification {
        return !state.words.isEmpty && state.words.allSatisfy { !walletNormalizeWord($0).isEmpty }
    }
    if state.isImporting {
        return false
    }
    return !state.words.isEmpty && state.words.allSatisfy(isMnemonicWord)
}

let walletSecretPhraseWhyLink = "wallet://secret-phrase-why"

@available(macOS 10.15, *)
func walletSecretPhraseMismatchAlert(environment: WalletUIEnvironment, address: String, for window: Window) {
    var info = strings().walletImportControllerWrongPhraseInfo
    let formatted = walletPreviousWalletAddressText(address)
    if !formatted.isEmpty {
        info += "\n\n" + formatted
    }
    environment.alert(for: window, header: strings().walletImportControllerWrongPhraseTitle, info: info, ok: strings().walletImportControllerOk)
}

private func presentInvalidSecretWordsAlert(environment: WalletUIEnvironment, for window: Window) {
    environment.alert(for: window, header: strings().walletImportControllerInvalidPhraseTitle, info: strings().walletImportControllerInvalidPhraseInfo, ok: strings().walletImportControllerOk)
}

@available(macOS 10.15, *)
func walletCanSubmitImport(_ state: WalletImportState, walletState: WalletContext.State, isMnemonicWord: (String) -> Bool) -> Bool {
    guard walletIsPhraseValid(state, verification: false, isMnemonicWord: isMnemonicWord) else {
        return false
    }
    guard walletState.activeOperation == nil else {
        return false
    }
    switch walletState.phase {
    case .empty, .wallet, .failed:
        return true
    case .restoring, .creating:
        return false
    }
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_word_count = InputDataIdentifier("_id_word_count")

private struct WalletImportPasteButtonKey: Equatable {
    let background: NSColor
    let foreground: NSColor
    let scale: CGFloat
}

private let walletImportPasteButtonCache = Atomic<(key: WalletImportPasteButtonKey, image: CGImage)?>(value: nil)

private func walletImportPasteButtonImage() -> CGImage {
    let key = WalletImportPasteButtonKey(background: theme.colors.background, foreground: walletClassicAccent, scale: System.backingScale)
    if let cached = walletImportPasteButtonCache.with({ $0 }), cached.key == key {
        return cached.image
    }
    let textNode = TextNode.layoutText(.initialize(string: strings().walletImportControllerPaste, color: key.foreground, font: .medium(.text)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    let image = generateImage(NSMakeSize(textNode.0.size.width + 20, 22), rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.round(size, size.height / 2)
        ctx.setFillColor(key.background.cgColor)
        ctx.fill(size.bounds)
        textNode.1.draw(size.bounds.focus(textNode.0.size), in: ctx, backingScaleFactor: key.scale, backgroundColor: .clear)
    })!
    _ = walletImportPasteButtonCache.swap((key: key, image: image))
    return image
}

func walletWordIdentifier(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_word_\(index)")
}

func walletWordFieldIndex(of identifier: InputDataIdentifier) -> Int? {
    let prefix = "_id_word_"
    guard identifier.identifier.hasPrefix(prefix) else {
        return nil
    }
    return Int(identifier.identifier.dropFirst(prefix.count))
}

private final class WalletWordCountRowItem: GeneralRowItem {
    fileprivate let selected: Int
    fileprivate let callback: (Int) -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, selected: Int, callback: @escaping (Int) -> Void) {
        self.selected = selected
        self.callback = callback
        super.init(initialSize, height: 42, stableId: stableId, inset: NSEdgeInsets(left: 20, right: 20))
    }

    override func viewClass() -> AnyClass {
        return WalletWordCountRowView.self
    }

    override var accessibilityLabel: String? {
        return selected == 24 ? strings().walletImportControllerTwentyFourWords : strings().walletImportControllerTwelveWords
    }

    override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        let callback = self.callback
        return [
            NSAccessibilityCustomAction(name: strings().walletImportControllerTwelveWords, handler: {
                callback(12)
                return true
            }),
            NSAccessibilityCustomAction(name: strings().walletImportControllerTwentyFourWords, handler: {
                callback(24)
                return true
            })
        ]
    }
}

private final class WalletWordCountRowView: GeneralRowView {
    private let trackView = View()
    private let segmentControl = CatalinaStyledSegmentController(frame: NSMakeRect(0, 0, 290, 30))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        trackView.layer?.cornerRadius = 10

        segmentControl.add(segment: CatalinaSegmentedItem(title: strings().walletImportControllerTwelveWords, handler: { [weak self] in
            if let item = self?.item as? WalletWordCountRowItem {
                item.callback(12)
            }
        }))
        segmentControl.add(segment: CatalinaSegmentedItem(title: strings().walletImportControllerTwentyFourWords, handler: { [weak self] in
            if let item = self?.item as? WalletWordCountRowItem {
                item.callback(24)
            }
        }))

        addSubview(trackView)
        addSubview(segmentControl.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletWordCountRowItem else {
            return
        }
        trackView.backgroundColor = theme.colors.grayBackground
        segmentControl.theme = CatalinaSegmentTheme(backgroundColor: theme.colors.grayBackground, foregroundColor: theme.colors.background, activeTextColor: theme.colors.text, inactiveTextColor: theme.colors.listGrayText)
        segmentControl.set(selected: item.selected == 24 ? 1 : 0, animated: animated)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletWordCountRowItem else {
            return
        }
        let width = min(320, frame.width - item.inset.left - item.inset.right)
        segmentControl.view.setFrameSize(NSMakeSize(width, 30))
        segmentControl.view.center()
        trackView.frame = segmentControl.view.frame
    }
}

private func entries(_ state: WalletImportState, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    let displayNumbers = state.displayNumbers
    let isVerification: Bool
    if case .verify = arguments.mode {
        isVerification = true
    } else {
        isVerification = false
    }
    let headerNumbers: [Int] = isVerification ? displayNumbers : []
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(headerNumbers), comparable: nil, item: { initialSize, stableId in
        let title = NSMutableAttributedString()
        let info = NSMutableAttributedString()
        let sticker: WalletUIAnimation
        switch arguments.mode {
        case .importWallet:
            sticker = WalletUIAnimation.wallet_word_list
            title.append(string: strings().walletImportControllerImportWalletTitle, color: theme.colors.text, font: .medium(.header))
            info.append(string: strings().walletImportControllerImportWalletInfo, color: theme.colors.listGrayText, font: .normal(.text))
        case .enterRecoveryPhrase:
            sticker = WalletUIAnimation.wallet_word_list
            title.append(string: strings().walletImportControllerSecretPhraseTitle, color: theme.colors.text, font: .medium(.header))
            info.append(string: strings().walletImportControllerSecretPhraseInfo, color: theme.colors.listGrayText, font: .normal(.text))
            let whyRange = info.range.upperBound
            info.append(string: strings().walletImportControllerWhy, color: walletClassicAccent, font: .normal(.text))
            info.addAttribute(NSAttributedString.Key.link, value: walletSecretPhraseWhyLink, range: NSMakeRange(whyRange, info.length - whyRange))
        case .enableBackup:
            sticker = WalletUIAnimation.wallet_word_check
            title.append(string: strings().walletImportControllerEnableBackup, color: theme.colors.text, font: .medium(.header))
            info.append(string: strings().walletImportControllerEnableBackupInfo, color: theme.colors.listGrayText, font: .normal(.text))
        case .verify:
            sticker = WalletUIAnimation.wallet_word_check
            title.append(string: strings().walletImportControllerTestTimeTitle, color: theme.colors.text, font: .medium(.header))
            if displayNumbers.count == 3 {
                info.append(string: strings().walletImportControllerTestTimeInfoPrefix, color: theme.colors.listGrayText, font: .normal(.text))
                info.append(string: "\(displayNumbers[0])", color: theme.colors.text, font: .medium(.text))
                info.append(string: strings().walletImportControllerTestTimeWordsSeparator, color: theme.colors.listGrayText, font: .normal(.text))
                info.append(string: "\(displayNumbers[1])", color: theme.colors.text, font: .medium(.text))
                info.append(string: strings().walletImportControllerTestTimeWordsAnd, color: theme.colors.listGrayText, font: .normal(.text))
                info.append(string: "\(displayNumbers[2])", color: theme.colors.text, font: .medium(.text))
                info.append(string: strings().walletImportControllerTestTimeInfoSuffix, color: theme.colors.listGrayText, font: .normal(.text))
            } else {
                info.append(string: strings().walletImportControllerTestTimeInfo, color: theme.colors.listGrayText, font: .normal(.text))
            }
        }
        return arguments.environment.makeAnimatedHeader(initialSize, stableId: stableId, sticker: sticker, text: title, infoText: info, stickerSize: NSMakeSize(100, 100), image: nil, infoLinkHandler: { value in
            if value == walletSecretPhraseWhyLink {
                arguments.showSecretPhraseReason()
            }
        }, viewType: .singleItem)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(30)))
    sectionId += 1

    if !isVerification {
        let selectedCount = state.words.count
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_word_count, equatable: .init(selectedCount), comparable: nil, item: { initialSize, stableId in
            return WalletWordCountRowItem(initialSize, stableId: stableId, selected: selectedCount, callback: arguments.setWordCount)
        }))
        index += 1
    }

    struct WordTuple: Equatable {
        let word: String
        let number: Int
        let showsPaste: Bool
        let isMismatched: Bool
    }
    let showsPaste = !isVerification && state.hasPasteboardText && state.words.allSatisfy({ $0.isEmpty })
    for i in 0 ..< state.words.count {
        if i > 0 {
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1
        }
        let tuple = WordTuple(word: state.words[i], number: state.displayNumbers[i], showsPaste: i == 0 && showsPaste, isMismatched: state.mismatchedIndices.contains(i))
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: walletWordIdentifier(i), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            let rightItem: InputDataRightItem? = tuple.showsPaste ? .action(walletImportPasteButtonImage(), .custom({ item, _ in
                arguments.pastePhrase(item)
            })) : nil
            return WalletWordInputRowItem(initialSize, stableId: stableId, currentText: tuple.word, displayNumber: tuple.number, rightItem: rightItem, isMismatched: tuple.isMismatched, updated: { _ in
                arguments.wordUpdated()
            })
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
public func WalletImportPage(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, mode: WalletImportMode, frameRect: NSRect?, updateButton: @escaping () -> Void, onBack: @escaping () -> Void, onImported: @escaping () -> Void = {}, onVerified: (() -> Void)? = nil) -> WalletOnboardingStep {

    let actionsDisposable = DisposableSet()
    let operationDisposable = MetaDisposable()
    actionsDisposable.add(operationDisposable)

    let isVerification: Bool
    let verificationIndices: [Int]
    let initialDisplayNumbers: [Int]
    switch mode {
    case .importWallet, .enterRecoveryPhrase, .enableBackup:
        isVerification = false
        verificationIndices = []
        initialDisplayNumbers = Array(1 ... 12)
    case let .verify(words, keyRotation, _):
        isVerification = true
        if keyRotation, words.count == 24 {
            let anchorIndex = Int.random(in: 0 ..< 12)
            let signingIndices = Array((12 ..< 24).shuffled().prefix(2))
            verificationIndices = ([anchorIndex] + signingIndices).sorted()
        } else {
            verificationIndices = Array(words.indices.shuffled().prefix(3)).sorted()
        }
        initialDisplayNumbers = verificationIndices.map { $0 + 1 }
    }
    let isBackupEnableMode: Bool
    if case .enableBackup = mode {
        isBackupEnableMode = true
    } else {
        isBackupEnableMode = false
    }

    let initialState = WalletImportState(words: Array(repeating: "", count: initialDisplayNumbers.count), displayNumbers: initialDisplayNumbers)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletImportState) -> WalletImportState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> InputDataController?)? = nil
    var submitImpl: (() -> Void)? = nil

    var window: Window {
        return walletUIWindow(context, getController?())
    }

    let focusField: (Int) -> Void = { index in
        Queue.mainQueue().justDispatch {
            getController?()?.makeFirstResponderIfPossible(for: walletWordIdentifier(index))
        }
    }
    let focusFieldDelayed: (Int) -> Void = { index in
        delay(0.25, closure: {
            getController?()?.makeFirstResponderIfPossible(for: walletWordIdentifier(index))
        })
    }
    let resignFocus: () -> Void = {
        Queue.mainQueue().justDispatch {
            _ = getController?()?.window?.makeFirstResponder(nil)
        }
    }

    let refreshSuggestions: () -> Void = {
        let focused = getController?()?.currentFirstResponderIdentifier
        updateState { current in
            var current = current
            let focusedIndex = focused.flatMap(walletWordFieldIndex(of:))
            if let index = focusedIndex, current.words.indices.contains(index) {
                let prefix = walletNormalizeWord(current.words[index])
                if prefix.count >= 1 {
                    let matches = walletContext.mnemonicWordSuggestions(for: prefix, limit: 3)
                    if matches.isEmpty {
                        if walletContext.isMnemonicWord(prefix) {
                            current.suggestions = nil
                        } else {
                            current.suggestions = WalletWordSuggestions(index: index, words: [], isInvalid: true)
                        }
                    } else if matches.count == 1 && matches[0] == prefix {
                        current.suggestions = nil
                    } else {
                        current.suggestions = WalletWordSuggestions(index: index, words: matches)
                    }
                } else {
                    current.suggestions = nil
                }
            } else {
                current.suggestions = nil
            }
            return current
        }
    }

    let focusWordSelected: (Int) -> Void = { index in
        let focus: () -> Bool = {
            guard let controller = getController?() else {
                return true
            }
            controller.makeFirstResponderIfPossible(for: walletWordIdentifier(index))
            guard controller.currentFirstResponderIdentifier == walletWordIdentifier(index) else {
                return false
            }
            NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
            refreshSuggestions()
            return true
        }
        Queue.mainQueue().justDispatch {
            if !focus() {
                delay(0.25, closure: {
                    _ = focus()
                })
            }
        }
    }

    let markWordInvalid: (Int) -> Void = { index in
        updateState { current in
            var current = current
            guard current.words.indices.contains(index) else {
                return current
            }
            current.suggestions = WalletWordSuggestions(index: index, words: [], isInvalid: true)
            return current
        }
        getController?()?.proccessValidation(.fail(.fields([walletWordIdentifier(index) : .shake])))
    }

    let isInvalidWord: (WalletImportState, Int) -> Bool = { state, index in
        guard state.words.indices.contains(index) else {
            return false
        }
        let word = walletNormalizeWord(state.words[index])
        return !word.isEmpty && !walletContext.isMnemonicWord(word)
    }

    let arguments = Arguments(context: context, environment: environment, mode: mode, setWordCount: { count in
        guard !isVerification, count == 12 || count == 24 else {
            return
        }
        let previousCount = stateValue.with { $0.words.count }
        guard count != previousCount else {
            return
        }
        updateState { current in
            var current = current
            var words = current.words
            if count < words.count {
                words = Array(words.prefix(count))
            } else {
                words.append(contentsOf: Array(repeating: "", count: count - words.count))
            }
            current.words = words
            current.displayNumbers = Array(1 ... count)
            current.suggestions = nil
            return current
        }
        let state = stateValue.with { $0 }
        if let firstEmpty = state.words.firstIndex(where: { $0.isEmpty }) {
            focusFieldDelayed(firstEmpty)
        }
    }, applySuggestion: { index, word in
        updateState { current in
            var current = current
            guard current.words.indices.contains(index) else {
                return current
            }
            current.words[index] = word
            current.suggestions = nil
            current.mismatchedIndices.remove(index)
            return current
        }
        let count = stateValue.with { $0.words.count }
        if index + 1 < count {
            focusField(index + 1)
        } else {
            resignFocus()
        }
    }, pastePhrase: { item in
        guard !isVerification else {
            return
        }
        guard NSPasteboard.general.availableType(from: [.string]) != nil else {
            updateState { current in
                var current = current
                current.hasPasteboardText = false
                return current
            }
            return
        }
        getController?()?.makeFirstResponderIfPossible(for: walletWordIdentifier(0))
        _ = (item.view as? InputDataRowView)?.textViewDidPaste(NSPasteboard.general)
    }, showSecretPhraseReason: {
        environment.alert(for: window, header: nil, info: strings().walletImportControllerBackupDisabledInfo, ok: strings().walletImportControllerOk)
    }, wordUpdated: {
        getController?()?.updateInputValues()
    })

    let distributeWords: (Int, [String]) -> Void = { index, normalized in
        var result = WalletRecoveryPasteResult.unchanged
        updateState { current in
            var current = current
            result = walletDistributeRecoveryWords(&current, index: index, words: normalized, verification: isVerification)
            return current
        }
        switch result {
        case .unchanged:
            return
        case let .inserted(range):
            let state = stateValue.with { $0 }
            if let firstInvalid = range.first(where: { isInvalidWord(state, $0) }) {
                focusWordSelected(firstInvalid)
            } else if range.upperBound < state.words.count {
                focusField(range.upperBound)
            } else {
                resignFocus()
            }
        case .invalidCount:
            updateState { current in
                var current = current
                if current.words.indices.contains(index) {
                    current.words[index] = ""
                }
                return current
            }
            let info = isBackupEnableMode ? strings().walletImportControllerInvalidWordCountCurrentOther(normalized.count) : strings().walletImportControllerInvalidWordCountOther(normalized.count)
            environment.alert(for: window, header: strings().walletImportControllerInvalidPhraseTitle, info: info)
        }
    }

    let didCompleteVerification = Atomic<Bool>(value: false)
    let activePreparedRecoveryImport = Atomic<WalletContext.PreparedRecoveryPhraseImport?>(value: nil)
    let preparedImportWords = Atomic<[String]?>(value: nil)
    let importFlow = WalletFlowAuthorization(walletContext: walletContext, reason: walletConfirmAccessFlowReason)
    let discardPreparedRecoveryImport: () -> Void = {
        _ = preparedImportWords.swap(nil)
        if let prepared = activePreparedRecoveryImport.swap(nil) {
            _ = walletContext.discardRecoveryPhraseImport(prepared).start()
        }
    }
    let endImportFlow: () -> Void = {
        importFlow.end()
        discardPreparedRecoveryImport()
    }
    let presentOutdatedRecoveryPhrase: (Window) -> Void = { targetWindow in
        endImportFlow()
        environment.alert(for: targetWindow, header: strings().walletImportControllerPhraseChangedTitle, info: strings().walletImportControllerPhraseChangedInfo, ok: strings().walletImportControllerProceed, onClose: {
            updateState { current in
                var current = current
                current.words = Array(repeating: "", count: 24)
                current.displayNumbers = Array(1 ... 24)
                current.suggestions = nil
                return current
            }
            updateButton()
            focusFieldDelayed(0)
        })
    }
    actionsDisposable.add(ActionDisposable {
        endImportFlow()
    })

    submitImpl = {
        let state = stateValue.with { $0 }
        switch mode {
        case .enterRecoveryPhrase:
            guard walletCanSubmitImport(state, walletState: walletContext.stateValue, isMnemonicWord: walletContext.isMnemonicWord) else {
                return
            }
            let words = state.words.map(walletNormalizeWord)
            guard walletContext.isMnemonicValid(words: words) else {
                presentInvalidSecretWordsAlert(environment: environment, for: window)
                return
            }
            let setImporting: (Bool) -> Void = { value in
                updateState { current in
                    var current = current
                    current.isImporting = value
                    return current
                }
                updateButton()
            }
            setImporting(true)
            let targetWindow = window
            let handleFailure: (WalletContext.WalletError) -> Void = { error in
                setImporting(false)
                switch error {
                case .invalidMnemonic:
                    presentInvalidSecretWordsAlert(environment: environment, for: targetWindow)
                case .recoveryPhraseOutdated:
                    presentOutdatedRecoveryPhrase(targetWindow)
                case .storage:
                    environment.alert(for: targetWindow, header: strings().walletImportControllerSaveFailedTitle, info: strings().walletImportControllerSaveFailedInfo)
                default:
                    presentWalletAuthorizationError(environment: environment, error, window: targetWindow, fallbackTitle: strings().walletImportControllerRestoreFailedTitle, fallbackText: strings().walletImportControllerImportFailedInfo)
                }
            }
            let finishImport: () -> Void = {
                _ = activePreparedRecoveryImport.swap(nil)
                _ = preparedImportWords.swap(nil)
                importFlow.end()
                onImported()
            }
            let completeCurrentWallet: (WalletContext.PreparedRecoveryPhraseImport) -> Void = { prepared in
                setImporting(true)
                operationDisposable.set((importFlow.authorize()
                |> mapToSignal { session in
                    walletContext.completeRecoveryPhraseImport(prepared, password: nil, session: session)
                }
                |> deliverOnMainQueue).start(next: { _ in
                    finishImport()
                }, error: { error in
                    if error == .authorizationCancelled {
                        endImportFlow()
                    }
                    handleFailure(error)
                }))
            }
            let authorizeReplacement: (WalletContext.PreparedRecoveryPhraseImport) -> Void = { prepared in
                setImporting(true)
                operationDisposable.set(performWalletAuthorizedOperation(context: context, environment: environment, window: targetWindow, operation: { password in
                    importFlow.authorize()
                    |> mapToSignal { session in
                        walletContext.completeRecoveryPhraseImport(prepared, password: password, session: session)
                    }
                }, next: { _ in
                    finishImport()
                }, failed: { error in
                    if error == .authorizationCancelled {
                        endImportFlow()
                    }
                    handleFailure(error)
                }))
            }
            let presentReplacement: (WalletContext.PreparedRecoveryPhraseImport) -> Void = { prepared in
                setImporting(false)
                if mode == .enterRecoveryPhrase {
                    var address = ""
                    if case let .wallet(info) = walletContext.stateValue.phase {
                        address = info.address
                    }
                    walletSecretPhraseMismatchAlert(environment: environment, address: address, for: targetWindow)
                    endImportFlow()
                    return
                }
                environment.verifyAlert(for: targetWindow, header: strings().walletImportControllerReplaceWalletTitle, information: strings().walletImportControllerReplaceWalletInfo, ok: strings().walletImportControllerReplace, cancel: strings().walletImportControllerCancel, successHandler: { _ in
                    authorizeReplacement(prepared)
                }, cancelHandler: {
                    endImportFlow()
                })
            }
            if let prepared = activePreparedRecoveryImport.with({ $0 }), preparedImportWords.with({ $0 }) == words {
                switch prepared.disposition {
                case .currentWallet:
                    completeCurrentWallet(prepared)
                case .replacement:
                    authorizeReplacement(prepared)
                }
                return
            }
            discardPreparedRecoveryImport()
            operationDisposable.set((importFlow.authorize()
            |> mapToSignal { session in
                walletContext.prepareRecoveryPhraseImport(words: words, session: session)
            }
            |> deliverOnMainQueue).start(next: { prepared in
                _ = activePreparedRecoveryImport.swap(prepared)
                _ = preparedImportWords.swap(words)
                switch prepared.disposition {
                case .currentWallet:
                    completeCurrentWallet(prepared)
                case .replacement:
                    presentReplacement(prepared)
                }
            }, error: { error in
                if error == .authorizationCancelled {
                    endImportFlow()
                }
                handleFailure(error)
            }))
        case let .enableBackup(expectedAddress):
            guard walletCanSubmitImport(state, walletState: walletContext.stateValue, isMnemonicWord: walletContext.isMnemonicWord) else {
                return
            }
            let words = state.words.map(walletNormalizeWord)
            let setImporting: (Bool) -> Void = { value in
                updateState { current in
                    var current = current
                    current.isImporting = value
                    return current
                }
                updateButton()
            }
            setImporting(true)
            let targetWindow = window
            operationDisposable.set((importFlow.authorize()
            |> mapToSignal { session in
                walletContext.enableBackup(expectedAddress: expectedAddress, words: words, session: session)
            }
            |> deliverOnMainQueue).start(next: { _ in
                importFlow.end()
                onImported()
            }, error: { error in
                importFlow.end()
                setImporting(false)
                presentWalletBackupEnableError(environment: environment, error, window: targetWindow, retry: {
                    submitImpl?()
                }, enterSecretPhrase: {
                    updateState { current in
                        var current = current
                        current.words = Array(repeating: "", count: current.words.count)
                        current.displayNumbers = Array(1 ... current.words.count)
                        current.suggestions = nil
                        return current
                    }
                    updateButton()
                    focusFieldDelayed(0)
                })
            }))
        case .importWallet:
            guard walletCanSubmitImport(state, walletState: walletContext.stateValue, isMnemonicWord: walletContext.isMnemonicWord) else {
                return
            }
            let words = state.words.map(walletNormalizeWord)
            guard walletContext.isMnemonicValid(words: words) else {
                presentInvalidSecretWordsAlert(environment: environment, for: window)
                return
            }
            updateState { current in
                var current = current
                current.isImporting = true
                return current
            }
            updateButton()
            let targetWindow = window
            operationDisposable.set(performWalletAuthorizedOperation(context: context, environment: environment, window: targetWindow, operation: { password in
                importFlow.authorize()
                |> mapToSignal { session in
                    walletContext.importWallet(words: words, password: password, session: session)
                }
            }, next: { _ in
                importFlow.end()
                onImported()
            }, failed: { error in
                if error == .authorizationCancelled {
                    importFlow.end()
                }
                updateState { current in
                    var current = current
                    current.isImporting = false
                    return current
                }
                updateButton()
                switch error {
                case .invalidMnemonic:
                    presentInvalidSecretWordsAlert(environment: environment, for: targetWindow)
                case .recoveryPhraseOutdated:
                    presentOutdatedRecoveryPhrase(targetWindow)
                case .storage:
                    environment.alert(for: targetWindow, header: strings().walletImportControllerSaveFailedTitle, info: strings().walletImportControllerSaveFailedInfo)
                default:
                    presentWalletAuthorizationError(environment: environment, error, window: targetWindow, fallbackTitle: strings().walletImportControllerImportFailedTitle, fallbackText: strings().walletImportControllerImportFailedInfo)
                }
            }))
        case let .verify(phraseWords, _, allowsRepeatedCompletion):
            guard walletIsPhraseValid(state, verification: true, isMnemonicWord: walletContext.isMnemonicWord), !didCompleteVerification.with({ $0 }) else {
                return
            }
            var mismatchedIndices: [Int] = []
            for fieldIndex in state.words.indices {
                guard verificationIndices.indices.contains(fieldIndex) else {
                    mismatchedIndices.append(fieldIndex)
                    continue
                }
                let phraseIndex = verificationIndices[fieldIndex]
                guard phraseWords.indices.contains(phraseIndex), walletNormalizeWord(state.words[fieldIndex]) == walletNormalizeWord(phraseWords[phraseIndex]) else {
                    mismatchedIndices.append(fieldIndex)
                    continue
                }
            }
            updateState { current in
                var current = current
                current.mismatchedIndices = Set(mismatchedIndices)
                return current
            }
            if let firstIndex = mismatchedIndices.first {
                focusWordSelected(firstIndex)
                let shakes = Dictionary(uniqueKeysWithValues: mismatchedIndices.map { (walletWordIdentifier($0), InputDataValidationFailAction.shake) })
                getController?()?.proccessValidation(.fail(.fields(shakes)))
            } else {
                _ = didCompleteVerification.swap(true)
                onVerified?()
                if allowsRepeatedCompletion {
                    _ = didCompleteVerification.swap(false)
                }
            }
        }
    }

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().walletImportControllerTitle, hasDone: false, identifier: "wallet-import", getBackgroundColor: {
        theme.colors.background
    })
    switch mode {
    case .importWallet, .enterRecoveryPhrase:
        controller.analyticsScreen = AnalyticsScreen.walletRecoveryPhraseEntry
    case .enableBackup:
        controller.analyticsScreen = AnalyticsScreen.walletBackup
    case .verify:
        controller.analyticsScreen = AnalyticsScreen.walletRecoveryPhraseVerify
    }

    getController = { [weak controller] in
        return controller
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    controller.validateData = { _ in
        return .success(.custom {
            submitImpl?()
        })
    }

    controller.updateDatas = { data in
        let previousSuggestions = stateValue.with { $0.suggestions }
        var changedIndex: Int? = nil
        var pasted: (index: Int, words: [String])? = nil
        var pickedDigit: Int? = nil
        updateState { current in
            var current = current
            for i in current.words.indices {
                if let value = data[walletWordIdentifier(i)]?.stringValue, value != current.words[i] {
                    current.words[i] = value
                    changedIndex = i
                }
            }
            if let i = changedIndex {
                current.mismatchedIndices.remove(i)
                let value = current.words[i]
                let pastedWords = walletRecoveryWords(value)
                if pastedWords.count > 1 {
                    pasted = (i, pastedWords)
                } else {
                    if let last = value.last, last.isNumber {
                        pickedDigit = Int(String(last))
                    }
                    if value.rangeOfCharacter(from: walletWordSeparators) != nil {
                        current.words[i] = walletRecoveryWords(value).first ?? ""
                    }
                }
            }
            return current
        }
        if let pasted = pasted {
            distributeWords(pasted.index, pasted.words)
        } else if let i = changedIndex, let digit = pickedDigit, let suggested = previousSuggestions, suggested.index == i, digit >= 1, digit <= suggested.words.count {
            arguments.applySuggestion(i, suggested.words[digit - 1])
        } else if let i = changedIndex, stateValue.with({ $0.words.indices.contains(i) && !$0.words[i].isEmpty }), data[walletWordIdentifier(i)]?.stringValue?.rangeOfCharacter(from: walletWordSeparators) != nil {
            let count = stateValue.with { $0.words.count }
            if i + 1 < count {
                focusField(i + 1)
            } else {
                resignFocus()
            }
            updateState { current in
                var current = current
                current.suggestions = nil
                return current
            }
        } else {
            refreshSuggestions()
        }
        return .none
    }

    let submitIfReady: () -> Void = {
        let state = stateValue.with { $0 }
        if isVerification ? walletIsPhraseValid(state, verification: true, isMnemonicWord: walletContext.isMnemonicWord) : walletCanSubmitImport(state, walletState: walletContext.stateValue, isMnemonicWord: walletContext.isMnemonicWord) {
            submitImpl?()
        }
    }

    controller.returnKeyInvocation = { identifier, _ in
        if let identifier = identifier, let index = walletWordFieldIndex(of: identifier) {
            let state = stateValue.with { $0 }
            if let suggested = state.suggestions, suggested.index == index, let first = suggested.words.first, state.words.indices.contains(index), !state.words[index].isEmpty {
                arguments.applySuggestion(index, first)
                if index == state.words.count - 1 {
                    submitIfReady()
                }
                return .nothing
            }
            if state.words.indices.contains(index), state.words[index].isEmpty {
                getController?()?.proccessValidation(.fail(.fields([walletWordIdentifier(index) : .shake])))
                return .nothing
            }
            let submitsVerification = isVerification && index == state.words.count - 1
            if isInvalidWord(state, index), !submitsVerification {
                markWordInvalid(index)
                return .nothing
            }
            if index + 1 < state.words.count {
                return .nextResponder
            }
            resignFocus()
            submitIfReady()
            return .nothing
        }
        return .default
    }

    controller.tabKeyInvocation = { identifier in
        if let identifier = identifier, let index = walletWordFieldIndex(of: identifier) {
            let state = stateValue.with { $0 }
            if let suggested = state.suggestions, suggested.index == index, let first = suggested.words.first, !walletNormalizeWord(state.words[index]).isEmpty {
                arguments.applySuggestion(index, first)
                return .invoked
            }
            if isInvalidWord(state, index) {
                markWordInvalid(index)
                return .invoked
            }
        }
        return .default
    }

    controller.deleteKeyInvocation = { identifier in
        if let identifier = identifier, let index = walletWordFieldIndex(of: identifier) {
            let state = stateValue.with { $0 }
            if state.words.indices.contains(index), state.words[index].isEmpty, index > 0 {
                focusField(index - 1)
                return .invoked
            }
        }
        return .default
    }

    let refreshPasteboard: () -> Void = {
        guard !isVerification else {
            return
        }
        let hasPasteboardText = NSPasteboard.general.availableType(from: [.string]) != nil
        guard stateValue.with({ $0.hasPasteboardText }) != hasPasteboardText else {
            return
        }
        updateState { current in
            var current = current
            current.hasPasteboardText = hasPasteboardText
            return current
        }
    }

    controller.didAppear = { _ in
        refreshPasteboard()
    }

    let pasteboardObservation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { _ in
        refreshPasteboard()
    })

    let acceptTitle: String
    switch mode {
    case .importWallet:
        acceptTitle = strings().walletImportControllerImport
    case .enableBackup:
        acceptTitle = strings().walletImportControllerEnableBackup
    case .enterRecoveryPhrase, .verify:
        acceptTitle = strings().walletImportControllerContinue
    }

    if let frameRect = frameRect {
        controller._frameRect = frameRect
        controller.bar = .init(height: 0)
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.chatNavigationBack, handler: {
            onBack()
        }, isCloseButton: false)
    } else {
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
            onBack()
        })
    }

    let glassAppearance: LiquidGlassAppearance = theme.colors.background.lightness < 0.5 ? .forceDark : .forceLight
    let suggestionsPanel = LiquidGlassView(frame: NSMakeRect(0, 0, 100, 38), cornerRadius: 19, hasShadow: true, hasBorder: true, tintAlpha: 0.3, forceAppearance: glassAppearance)
    let suggestionsContent = View()
    suggestionsPanel.addSubview(suggestionsContent)
    var panelScrollListenerAdded = false
    var responderObservation: NSKeyValueObservation? = nil

    let hideSuggestionsPanel: () -> Void = {
        suggestionsPanel.removeFromSuperview()
    }

    let updateSuggestionsPanel: (WalletWordSuggestions?) -> Void = { suggestions in
        guard let controller = getController?(), controller.isLoaded() else {
            hideSuggestionsPanel()
            return
        }
        if responderObservation == nil, let window = controller.view.window {
            responderObservation = window.observe(\.firstResponder, options: [.new]) { _, _ in
                DispatchQueue.main.async {
                    refreshSuggestions()
                }
            }
        }
        guard let suggestions = suggestions, !suggestions.words.isEmpty || suggestions.isInvalid else {
            hideSuggestionsPanel()
            return
        }
        guard let item = controller.tableView.item(stableId: InputDataEntryId.custom(walletWordIdentifier(suggestions.index))), let rowView = controller.tableView.viewNecessary(at: item.index) else {
            hideSuggestionsPanel()
            return
        }

        if !panelScrollListenerAdded {
            panelScrollListenerAdded = true
            controller.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { _ in
                updateState { current in
                    var current = current
                    current.suggestions = nil
                    return current
                }
            }))
        }

        suggestionsContent.removeAllSubviews()
        let spacing: CGFloat = 6
        let padding: CGFloat = 6
        var buttonsWidth: CGFloat = 0
        var buttons: [TextButton] = []
        if suggestions.isInvalid {
            let button = TextButton()
            button.userInteractionEnabled = false
            button.set(font: .medium(.text), for: .Normal)
            button.set(color: theme.colors.redUI, for: .Normal)
            button.set(background: theme.colors.redUI.withAlphaComponent(0.1), for: .Normal)
            button.set(text: strings().walletImportControllerInvalidWord, for: .Normal)
            _ = button.sizeToFit(NSMakeSize(20, 0), NSMakeSize(0, 26), thatFit: false)
            button.layer?.cornerRadius = 13
            buttons.append(button)
            buttonsWidth += button.frame.width
        }
        for (position, word) in suggestions.words.enumerated() {
            let button = TextButton()
            button.scaleOnClick = true
            button.set(font: .medium(.text), for: .Normal)
            button.set(color: walletClassicAccent, for: .Normal)
            button.set(background: walletClassicAccent.withAlphaComponent(0.1), for: .Normal)
            button.set(background: walletClassicAccent.withAlphaComponent(0.2), for: .Highlight)
            button.set(text: strings().walletImportControllerSuggestion(position + 1, word), for: .Normal)
            _ = button.sizeToFit(NSMakeSize(20, 0), NSMakeSize(0, 26), thatFit: false)
            button.layer?.cornerRadius = 13
            let index = suggestions.index
            button.set(handler: { _ in
                arguments.applySuggestion(index, word)
            }, for: .Click)
            buttons.append(button)
            buttonsWidth += button.frame.width
        }
        let panelWidth = buttonsWidth + CGFloat(max(0, buttons.count - 1)) * spacing + padding * 2
        let panelHeight: CGFloat = 26 + padding * 2
        suggestionsPanel.setFrameSize(NSMakeSize(panelWidth, panelHeight))
        suggestionsContent.frame = suggestionsPanel.bounds
        var x = padding
        for button in buttons {
            suggestionsContent.addSubview(button)
            button.setFrameOrigin(NSMakePoint(x, padding))
            x += button.frame.width + spacing
        }

        let rowRect = controller.genericView.convert(rowView.bounds, from: rowView)
        let panelX = max(8, min(controller.genericView.frame.width - panelWidth - 8, rowRect.minX + 46))
        let panelSpacing: CGFloat = 4
        let tableFrame = controller.tableView.frame
        let availableMinY = tableFrame.minY + controller.tableView.contentInsets.top
        let availableMaxY = tableFrame.maxY - controller.tableView.contentInsets.bottom
        let panelBelowY = rowRect.maxY + panelSpacing
        let panelAboveY = rowRect.minY - panelHeight - panelSpacing
        let preferredPanelY = panelBelowY + panelHeight <= availableMaxY ? panelBelowY : panelAboveY
        let panelY = min(max(preferredPanelY, availableMinY), max(availableMinY, availableMaxY - panelHeight))
        suggestionsPanel.setFrameOrigin(NSMakePoint(panelX, panelY))
        if suggestionsPanel.superview == nil {
            controller.genericView.addSubview(suggestionsPanel)
        }
    }

    actionsDisposable.add((statePromise.get() |> deliverOnMainQueue).start(next: { state in
        updateSuggestionsPanel(state.suggestions)
    }))

    controller.onDeinit = {
        NotificationCenter.default.removeObserver(pasteboardObservation)
        responderObservation?.invalidate()
        responderObservation = nil
        actionsDisposable.dispose()
        submitImpl = nil
    }

    controller.afterTransaction = { _ in
        updateButton()
    }

    return WalletOnboardingStep(controller: controller, acceptTitle: acceptTitle, isAcceptEnabled: {
        stateValue.with { state in
            if isVerification {
                return walletIsPhraseValid(state, verification: true, isMnemonicWord: walletContext.isMnemonicWord)
            } else {
                return walletCanSubmitImport(state, walletState: walletContext.stateValue, isMnemonicWord: walletContext.isMnemonicWord)
            }
        }
    }, accept: {
        submitImpl?()
    })
}

@available(macOS 10.15, *)
public func WalletImportController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, mode: WalletImportMode = .importWallet, onImported: @escaping () -> Void) -> InputDataModalController {
    var getModalController: (() -> InputDataModalController?)? = nil
    var updateButtonImpl: (() -> Void)? = nil

    let step = WalletImportPage(context: context, environment: environment, walletContext: walletContext, mode: mode, frameRect: nil, updateButton: {
        updateButtonImpl?()
    }, onBack: {
        getModalController?()?.close()
    }, onImported: {
        switch mode {
        case .enterRecoveryPhrase, .enableBackup:
            getModalController?()?.close()
        case .importWallet, .verify:
            break
        }
        onImported()
    })

    let modalInteractions = ModalInteractions(acceptTitle: step.acceptTitle, accept: {
        step.accept()
    }, singleButton: true, customTheme: { walletModalTheme })

    let modalController = WalletModalController(step.controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 0))

    getModalController = { [weak modalController] in
        modalController
    }

    let acceptTitle = step.acceptTitle
    let isAcceptEnabled = step.isAcceptEnabled
    updateButtonImpl = { [weak modalInteractions] in
        modalInteractions?.updateDone { button in
            button.set(text: acceptTitle, for: .Normal)
            button.isEnabled = isAcceptEnabled()
        }
    }

    return modalController
}
