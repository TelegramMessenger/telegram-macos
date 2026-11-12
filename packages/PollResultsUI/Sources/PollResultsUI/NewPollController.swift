import Cocoa
import TelegramCore

import Postbox
import SwiftSignalKit
import TGUIKit
import InputView
import MapKit
import ChatHistoryModel
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import InAppSettings
import FoundationUtils
import Strings
import FilePanels
import LocalAnimations
import LocationUI
import AlertsUI
import AppAnalytics

private let maxTextLength:Int32 = 255
private let maxOptionLength: Int32 = 100

private enum NewPollMedia: Equatable {
    case file(path: String, thumbnail: CGImage?, media: Media?)
    case sticker(TelegramMediaFile, thumbnail: CGImage?)
    case cloud(Media, thumbnail: CGImage?)
    case location(TelegramMediaMap, thumbnail: CGImage?)

    public static func == (lhs: NewPollMedia, rhs: NewPollMedia) -> Bool {
        switch (lhs, rhs) {
        case let (.file(lPath, _, lMedia), .file(rPath, _, rMedia)):
            if let lMedia, let rMedia {
                if !lMedia.isEqual(to: rMedia) {
                    return false
                }
            } else if (lMedia != nil) != (rMedia != nil) {
                return false
            }
            return lPath == rPath
        case let (.sticker(lFile, _), .sticker(rFile, _)):
            return lFile.isEqual(to: rFile)
        case let (.cloud(lMedia, _), .cloud(rMedia, _)):
            return lMedia.isEqual(to: rMedia)
        case let (.location(lMap, lThumb), .location(rMap, rThumb)):
            return lMap == rMap && (lThumb != nil) == (rThumb != nil)
        default:
            return false
        }
    }

    public var thumbnail: CGImage? {
        switch self {
        case let .file(_, thumbnail, _):
            return thumbnail
        case let .sticker(_, thumbnail):
            return thumbnail
        case let .cloud(_, thumbnail):
            return thumbnail
        case let .location(_, thumbnail):
            return thumbnail
        }
    }

    public var media: Media? {
        switch self {
        case let .file(_, _, media):
            return media
        case let .sticker(file, _):
            return file
        case let .cloud(media, _):
            return media
        case let .location(map, _):
            return map
        }
    }
}

private class Arguments {
    public let context: any AccountContextProtocol
    public let deleteOption:(InputDataIdentifier) -> Void
    public let updateQuizSelected:(InputDataIdentifier) -> Void
    public let updateMode: (NewPollMode)->Void
    public let updateState:(Updated_ChatTextInputState)->Void
    public let updateOptionState:(InputDataIdentifier, Updated_ChatTextInputState)->Void
    public let toggleAllowAddingOptions: () -> Void
    public let toggleAllowRevoting: () -> Void
    public let toggleShuffleOptions: () -> Void
    public let toggleLimitDuration: () -> Void
    public let selectDeadline: () -> Void
    public let deadlineMenuItems: () -> [ContextMenuItem]
    public let toggleHideResults: () -> Void
    public let updateDescriptionState: (Updated_ChatTextInputState) -> Void
    public let attachMedia: (InputDataIdentifier, Control) -> Void
    public let attachDescriptionMedia: (Control) -> Void
    public let updateExplanationState: (Updated_ChatTextInputState) -> Void
    public let attachSolutionMedia: (Control) -> Void
    public let toggleRestrictToSubscribers: () -> Void
    public let toggleLimitByCountry: () -> Void
    public let openCountries: () -> Void

    public init(context: any AccountContextProtocol, deleteOption: @escaping (InputDataIdentifier) -> Void, updateQuizSelected: @escaping (InputDataIdentifier) -> Void, updateMode: @escaping (NewPollMode) -> Void, updateState: @escaping (Updated_ChatTextInputState) -> Void, updateOptionState: @escaping(InputDataIdentifier, Updated_ChatTextInputState)->Void, toggleAllowAddingOptions: @escaping () -> Void, toggleAllowRevoting: @escaping () -> Void, toggleShuffleOptions: @escaping () -> Void, toggleLimitDuration: @escaping () -> Void, selectDeadline: @escaping () -> Void, deadlineMenuItems: @escaping () -> [ContextMenuItem], toggleHideResults: @escaping () -> Void, updateDescriptionState: @escaping (Updated_ChatTextInputState) -> Void, attachMedia: @escaping (InputDataIdentifier, Control) -> Void, attachDescriptionMedia: @escaping (Control) -> Void, updateExplanationState: @escaping (Updated_ChatTextInputState) -> Void, attachSolutionMedia: @escaping (Control) -> Void, toggleRestrictToSubscribers: @escaping () -> Void, toggleLimitByCountry: @escaping () -> Void, openCountries: @escaping () -> Void) {
        self.context = context
        self.deleteOption = deleteOption
        self.updateQuizSelected = updateQuizSelected
        self.updateMode = updateMode
        self.updateState = updateState
        self.updateOptionState = updateOptionState
        self.toggleAllowAddingOptions = toggleAllowAddingOptions
        self.toggleAllowRevoting = toggleAllowRevoting
        self.toggleShuffleOptions = toggleShuffleOptions
        self.toggleLimitDuration = toggleLimitDuration
        self.selectDeadline = selectDeadline
        self.deadlineMenuItems = deadlineMenuItems
        self.toggleHideResults = toggleHideResults
        self.updateDescriptionState = updateDescriptionState
        self.attachMedia = attachMedia
        self.attachDescriptionMedia = attachDescriptionMedia
        self.updateExplanationState = updateExplanationState
        self.attachSolutionMedia = attachSolutionMedia
        self.toggleRestrictToSubscribers = toggleRestrictToSubscribers
        self.toggleLimitByCountry = toggleLimitByCountry
        self.openCountries = openCountries
    }
}

private func _id_input_option() -> InputDataIdentifier {
    return InputDataIdentifier("_id_input_option_\(arc4random())")
}
private let _id_input_title = InputDataIdentifier("_id_input_title")
private let _id_input_add_option = InputDataIdentifier("_id_input_add_option")

private let _id_anonymous = InputDataIdentifier("_id_anonymous")
private let _id_multiple_choice = InputDataIdentifier("_id_multiple_choice")
private let _id_quiz = InputDataIdentifier("_id_quiz")
private let _id_explanation = InputDataIdentifier("_id_explanation")
private let _id_description = InputDataIdentifier("_id_description")
private let _id_show_who_voted = InputDataIdentifier("_id_show_who_voted")
private let _id_allow_adding_options = InputDataIdentifier("_id_allow_adding_options")
private let _id_allow_revoting = InputDataIdentifier("_id_allow_revoting")
private let _id_shuffle_options = InputDataIdentifier("_id_shuffle_options")
private let _id_limit_duration = InputDataIdentifier("_id_limit_duration")
private let _id_deadline_value = InputDataIdentifier("_id_deadline_value")
private let _id_hide_results = InputDataIdentifier("_id_hide_results")
private let _id_restrict_to_subscribers = InputDataIdentifier("_id_restrict_to_subscribers")
private let _id_limit_by_country = InputDataIdentifier("_id_limit_by_country")
private let _id_allowed_countries = InputDataIdentifier("_id_allowed_countries")


private struct NewPollOption : Equatable {
    public let identifier: InputDataIdentifier
    public let textState: Updated_ChatTextInputState
    public let selected: Bool
    public let media: NewPollMedia?
    public init(identifier: InputDataIdentifier, textState: Updated_ChatTextInputState, selected: Bool, media: NewPollMedia? = nil) {
        self.identifier = identifier
        self.textState = textState
        self.selected = selected
        self.media = media
    }

    public var text: String {
        return textState.inputText.string
    }

    public func withUpdatedText(_ textState: Updated_ChatTextInputState) -> NewPollOption {
        return NewPollOption(identifier: self.identifier, textState: textState, selected: self.selected, media: self.media)
    }
    public func withUpdatedSelected(_ selected: Bool) -> NewPollOption {
        return NewPollOption(identifier: self.identifier, textState: self.textState, selected: selected, media: self.media)
    }
    public func withUpdatedMedia(_ media: NewPollMedia?) -> NewPollOption {
        return NewPollOption(identifier: self.identifier, textState: self.textState, selected: self.selected, media: media)
    }
}

private enum NewPollMode : Equatable {
    case normal(anonymous: Bool)
    case quiz(anonymous: Bool)
    case multiple(anonymous: Bool)
    
    public var isAnonymous: Bool {
        switch self {
        case let .normal(anonymous):
            return anonymous
        case let .quiz(anonymous):
            return anonymous
        case let .multiple(anonymous):
            return anonymous
        }
    }
    public func withUpdatedIsAnonymous(_ anonymous: Bool) -> NewPollMode {
        switch self {
        case .normal:
            return .normal(anonymous: anonymous)
        case .quiz:
            return .quiz(anonymous: anonymous)
        case .multiple:
            return .multiple(anonymous: anonymous)
        }
    }
    
    public var isQuiz: Bool {
        switch self {
        case .quiz:
            return true
        default:
            return false
        }
    }
    public var isMultiple: Bool {
        switch self {
        case .multiple:
            return true
        default:
            return false
        }
    }
    
    public func isModeEqual(to mode: NewPollMode) -> Bool {
        switch self {
        case .normal:
            return !mode.isQuiz && !mode.isMultiple
        case .quiz:
            return mode.isQuiz
        case .multiple:
            return mode.isMultiple
        }
    }
    
    var publicity: TelegramMediaPollPublicity {
        if isAnonymous {
            return .anonymous
        } else {
            return .public
        }
    }
    public var kind: TelegramMediaPollKind {
        switch self {
        case .normal:
            return .poll(multipleAnswers: false)
        case .multiple:
            return .poll(multipleAnswers: true)
        case .quiz:
            return .quiz(multipleAnswers: false)
        }
    }
}

private struct NewPollState : Equatable {
    private let random: UInt32

    public var options: [NewPollOption]
    public var mode: NewPollMode
    public var isQuiz: Bool?
    public var quizExplanation: NSAttributedString
    public var textState: Updated_ChatTextInputState
    public var descriptionState: Updated_ChatTextInputState
    public var descriptionMedia: NewPollMedia?
    public var solutionMedia: NewPollMedia?
    public var allowAddingOptions: Bool
    public var allowRevoting: Bool
    public var shuffleOptions: Bool
    public var limitDuration: Bool
    public var deadlineTimeout: Int32?
    public var deadlineDate: Date?
    public var hideResults: Bool
    public var uploadingMedia: Set<String>
    public var uploadProgress: [String: Float] = [:]
    public var restrictToSubscribers: Bool = false
    public var limitByCountry: Bool = false
    public var countries: [Country] = []

    public init(options: [NewPollOption], random: UInt32, mode: NewPollMode, isQuiz: Bool?, quizExplanation: NSAttributedString, textState: Updated_ChatTextInputState, descriptionState: Updated_ChatTextInputState = .init(), descriptionMedia: NewPollMedia? = nil, solutionMedia: NewPollMedia? = nil, allowAddingOptions: Bool = false, allowRevoting: Bool = false, shuffleOptions: Bool = false, limitDuration: Bool = false, deadlineTimeout: Int32? = nil, deadlineDate: Date? = nil, hideResults: Bool = false, uploadingMedia: Set<String> = [], restrictToSubscribers: Bool = false, limitByCountry: Bool = false, countries: [Country] = []) {
        self.options = options
        self.random = random
        self.mode = mode
        self.isQuiz = isQuiz
        self.quizExplanation = quizExplanation
        self.textState = textState
        self.descriptionState = descriptionState
        self.descriptionMedia = descriptionMedia
        self.solutionMedia = solutionMedia
        self.allowAddingOptions = allowAddingOptions
        self.allowRevoting = allowRevoting
        self.shuffleOptions = shuffleOptions
        self.limitDuration = limitDuration
        self.deadlineTimeout = deadlineTimeout
        self.deadlineDate = deadlineDate
        self.hideResults = hideResults
        self.uploadingMedia = uploadingMedia
        self.restrictToSubscribers = restrictToSubscribers
        self.limitByCountry = limitByCountry
        self.countries = countries
    }

    private func copy(options: [NewPollOption]? = nil, random: UInt32? = nil, mode: NewPollMode? = nil, quizExplanation: NSAttributedString? = nil, textState: Updated_ChatTextInputState? = nil, descriptionState: Updated_ChatTextInputState? = nil, descriptionMedia: NewPollMedia?? = nil, solutionMedia: NewPollMedia?? = nil, allowAddingOptions: Bool? = nil, allowRevoting: Bool? = nil, shuffleOptions: Bool? = nil, limitDuration: Bool? = nil, deadlineTimeout: Int32?? = nil, deadlineDate: Date?? = nil, hideResults: Bool? = nil, uploadingMedia: Set<String>? = nil, restrictToSubscribers: Bool? = nil, limitByCountry: Bool? = nil, countries: [Country]? = nil) -> NewPollState {
        var state = NewPollState(options: options ?? self.options, random: random ?? self.random, mode: mode ?? self.mode, isQuiz: self.isQuiz, quizExplanation: quizExplanation ?? self.quizExplanation, textState: textState ?? self.textState, descriptionState: descriptionState ?? self.descriptionState, descriptionMedia: descriptionMedia ?? self.descriptionMedia, solutionMedia: solutionMedia ?? self.solutionMedia, allowAddingOptions: allowAddingOptions ?? self.allowAddingOptions, allowRevoting: allowRevoting ?? self.allowRevoting, shuffleOptions: shuffleOptions ?? self.shuffleOptions, limitDuration: limitDuration ?? self.limitDuration, deadlineTimeout: deadlineTimeout ?? self.deadlineTimeout, deadlineDate: deadlineDate ?? self.deadlineDate, hideResults: hideResults ?? self.hideResults, uploadingMedia: uploadingMedia ?? self.uploadingMedia, restrictToSubscribers: restrictToSubscribers ?? self.restrictToSubscribers, limitByCountry: limitByCountry ?? self.limitByCountry, countries: countries ?? self.countries)
        state.isAddOption = self.isAddOption
        return state
    }

    public func withUpdatedTitle(_ title: String) -> NewPollState {
        return copy()
    }
    public func withDeleteOption(_ identifier: InputDataIdentifier) -> NewPollState {
        if self.options.count == 1 {
            return self
        }
        var options = self.options
        options.removeAll(where: {$0.identifier == identifier})
        return copy(options: options)
    }

    public func withUnselectItems() -> NewPollState {
        return copy(options: self.options.map { $0.withUpdatedSelected(false) })
    }

    public func withUpdatedOption(_ f:(NewPollOption) -> NewPollOption, forKey identifier: InputDataIdentifier) -> NewPollState {
        var options = self.options
        if let index = options.firstIndex(where: {$0.identifier == identifier}) {
            options[index] = f(options[index])
        }
        return copy(options: options)
    }

    public func withAddedOption(_ option: NewPollOption) -> NewPollState {
        var options = self.options
        options.append(option)
        return copy(options: options)
    }
    public func withUpdatedPos(_ previous: Int, _ current: Int) -> NewPollState {
        var options = self.options
        options.move(at: previous, to: current)
        return copy(options: options)
    }

    public func indexOf(_ identifier: InputDataIdentifier) -> Int? {
        return options.firstIndex(where: { $0.identifier == identifier })
    }

    public func withUpdatedState() -> NewPollState {
        return copy(random: arc4random())
    }
    public func withUpdatedMode(_ mode: NewPollMode) -> NewPollState {
        return copy(mode: mode)
    }
    public func withUpdatedQuizExplanation(_ quizExplanation: NSAttributedString) -> NewPollState {
        return copy(quizExplanation: quizExplanation)
    }
    public func withUpdatedDescriptionState(_ descriptionState: Updated_ChatTextInputState) -> NewPollState {
        return copy(descriptionState: descriptionState)
    }
    public func withUpdatedAllowAddingOptions(_ allowAddingOptions: Bool) -> NewPollState {
        return copy(allowAddingOptions: allowAddingOptions)
    }
    public func withUpdatedAllowRevoting(_ allowRevoting: Bool) -> NewPollState {
        return copy(allowRevoting: allowRevoting)
    }
    public func withUpdatedShuffleOptions(_ shuffleOptions: Bool) -> NewPollState {
        return copy(shuffleOptions: shuffleOptions)
    }
    public func withUpdatedLimitDuration(_ limitDuration: Bool) -> NewPollState {
        return copy(limitDuration: limitDuration)
    }
    public func withUpdatedDeadlineTimeout(_ deadlineTimeout: Int32?) -> NewPollState {
        return copy(deadlineTimeout: .some(deadlineTimeout))
    }
    public func withUpdatedDeadlineDate(_ deadlineDate: Date?) -> NewPollState {
        return copy(deadlineDate: .some(deadlineDate))
    }
    public func withUpdatedHideResults(_ hideResults: Bool) -> NewPollState {
        return copy(hideResults: hideResults)
    }
    public func withUpdatedRestrictToSubscribers(_ value: Bool) -> NewPollState {
        return copy(restrictToSubscribers: value)
    }
    public func withUpdatedLimitByCountry(_ value: Bool) -> NewPollState {
        return copy(limitByCountry: value)
    }
    public func withUpdatedCountries(_ countries: [Country]) -> NewPollState {
        return copy(countries: countries)
    }
    public func withUpdatedDescriptionMedia(_ media: NewPollMedia?) -> NewPollState {
        return copy(descriptionMedia: .some(media))
    }
    public func withUpdatedSolutionMedia(_ media: NewPollMedia?) -> NewPollState {
        return copy(solutionMedia: .some(media))
    }
    public func withUpdatedOptionMedia(_ identifier: InputDataIdentifier, _ media: NewPollMedia?) -> NewPollState {
        var options = self.options
        if let index = options.firstIndex(where: { $0.identifier == identifier }) {
            options[index] = options[index].withUpdatedMedia(media)
        }
        return copy(options: options)
    }
    public func withUpdatedUploading(_ key: String, _ uploading: Bool) -> NewPollState {
        var set = self.uploadingMedia
        var state: NewPollState
        if uploading {
            set.insert(key)
        } else {
            set.remove(key)
        }
        state = copy(uploadingMedia: set)
        if !uploading {
            state.uploadProgress.removeValue(forKey: key)
        }
        return state
    }
    public func withUpdatedUploadProgress(_ key: String, _ progress: Float) -> NewPollState {
        var state = self
        state.uploadProgress[key] = progress
        return state
    }

    public var title: String {
        return textState.inputText.string
    }
    
    public var isAddOption: Bool = false

    public var isEnabled: Bool {
        if isAddOption {
            return !(options.last?.text.trimmed.isEmpty ?? true)
        }
        let isEnabled = !title.trimmed.isEmpty && options.filter({!$0.text.trimmed.isEmpty}).count >= 1
        switch self.mode {
        case .quiz:
            if let option = self.options.first(where: {$0.selected }) {
                if option.text.trimmed.isEmpty {
                    return false
                }
            }
            return isEnabled
        default:
            return isEnabled
        }
    }
    
    public var shouldShowTooltipForQuiz: Bool {
        return self.mode.isQuiz && !self.options.contains(where: { $0.selected })
    }
    
    public func media(_ context: any AccountContextProtocol) -> TelegramMediaPoll {
        var options: [TelegramMediaPollOption] = []
        var answers: [Data]?
        for (i, option) in self.options.enumerated() {
            if !option.text.trimmed.isEmpty {
                var optionMedia: Media?
                if let pollMedia = option.media {
                    switch pollMedia {
                    case let .file(path, _, media):
                        if let media = media {
                            optionMedia = media
                        } else {
                            let randomId = Int64.random(in: Int64.min...Int64.max)
                            let mimeType = MIMEType(path)
                            let attrs: [TelegramMediaFileAttribute] = [.FileName(fileName: path.nsstring.lastPathComponent)]
                            optionMedia = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: randomId), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: randomId, size: fileSize(path)), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: nil, attributes: attrs, alternativeRepresentations: [])
                        }
                    case let .sticker(file, _):
                        optionMedia = file
                    case let .cloud(media, _):
                        optionMedia = media
                    case let .location(map, _):
                        optionMedia = map
                    }
                }
                options.append(TelegramMediaPollOption(text: option.text.trimmed, entities: option.textState.textInputState().messageTextEntities(), opaqueIdentifier: "\(i)".data(using: .utf8)!, media: optionMedia, date: nil, addedBy: context.peerId))
                if option.selected {
                    answers = [options.last!.opaqueIdentifier]
                }
            }
        }
        
        let solution: TelegramMediaPollResults.Solution?
        if !self.quizExplanation.string.isEmpty {
            let entities = ChatTextInputState(inputText: self.quizExplanation.string, selectionRange: 0..<0, attributes: chatTextAttributes(from: self.quizExplanation))
            var solMedia: Media?
            if let solPollMedia = self.solutionMedia {
                switch solPollMedia {
                case let .file(path, _, media):
                    if let media = media {
                        solMedia = media
                    } else {
                        let randomId = Int64.random(in: Int64.min...Int64.max)
                        let mimeType = MIMEType(path)
                        let attrs: [TelegramMediaFileAttribute] = [.FileName(fileName: path.nsstring.lastPathComponent)]
                        solMedia = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: randomId), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: randomId, size: fileSize(path)), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: nil, attributes: attrs, alternativeRepresentations: [])
                    }
                case let .sticker(file, _):
                    solMedia = file
                case let .cloud(media, _):
                    solMedia = media
                case let .location(map, _):
                    solMedia = map
                }
            }
            solution = TelegramMediaPollResults.Solution(text: self.quizExplanation.string, entities: entities.messageTextEntities(), media: solMedia)
        } else {
            solution = nil
        }
        
        var computedDeadlineTimeout: Int32? = nil
        if limitDuration {
            if let deadlineDate = deadlineDate {
                let seconds = Int32(deadlineDate.timeIntervalSince1970 - Date().timeIntervalSince1970)
                if seconds > 0 {
                    computedDeadlineTimeout = seconds
                }
            } else if let deadlineTimeout = deadlineTimeout {
                computedDeadlineTimeout = deadlineTimeout
            }
        }

        var pollAttachedMedia: Media?
        if let descMedia = self.descriptionMedia {
            switch descMedia {
            case let .file(path, _, media):
                if let media = media {
                    pollAttachedMedia = media
                } else {
                    let randomId = Int64.random(in: Int64.min...Int64.max)
                    let mimeType = MIMEType(path)
                    let attrs: [TelegramMediaFileAttribute] = [.FileName(fileName: path.nsstring.lastPathComponent)]
                    pollAttachedMedia = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: randomId), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: randomId, size: fileSize(path)), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: nil, attributes: attrs, alternativeRepresentations: [])
                }
            case let .sticker(file, _):
                pollAttachedMedia = file
            case let .cloud(media, _):
                pollAttachedMedia = media
            case let .location(map, _):
                pollAttachedMedia = map
            }
        }

        let effectiveCountries: [String] = self.limitByCountry ? self.countries.map { $0.id } : []
        return TelegramMediaPoll(pollId: MediaId(namespace: Namespaces.Media.LocalPoll, id: arc4random64()), publicity: mode.publicity, kind: mode.kind, text: title.trimmed, textEntities: self.textState.textInputState().messageTextEntities(), options: options, correctAnswers: answers, results: TelegramMediaPollResults(voters: nil, totalVoters: nil, recentVoters: [], solution: solution, hasUnseenVotes: nil, canViewStats: false), isClosed: false, deadlineTimeout: computedDeadlineTimeout, deadlineDate: deadlineDate.flatMap({ Int32($0.timeIntervalSince1970) }), pollHash: 0, openAnswers: self.allowAddingOptions, revotingDisabled: !self.allowRevoting, shuffleAnswers: self.shuffleOptions, hideResultsUntilClose: self.hideResults, attachedMedia: pollAttachedMedia, restrictToSubscribers: self.restrictToSubscribers, countries: effectiveCountries)
    }
}

private func deadlineDisplayString(_ state: NewPollState) -> String {
    if let date = state.deadlineDate {
        let formatter = DateFormatter()
        formatter.dateFormat = strings().newPollDateFormat
        return formatter.string(from: date)
    } else if let timeout = state.deadlineTimeout {
        switch timeout {
        case 3600: return strings().newPollDuration1Hour
        case 10800: return strings().newPollDuration3Hours
        case 28800: return strings().newPollDuration8Hours
        case 86400: return strings().newPollDuration24Hours
        case 259200: return strings().newPollDuration72Hours
        default: return strings().newPollDurationHoursOther(Int(timeout / 3600))
        }
    }
    return strings().newPollDuration24Hours
}

private func entries(_ state: NewPollState, arguments: Arguments, canBePublic: Bool, isChannel: Bool = false, source: NewPollSource = .new) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    let optionsLimit = Int(arguments.context.appConfiguration.getGeneralValue("poll_answers_max", orElse: 10))

    if case let .addOption(_, existingOptions) = source {
        let attachIcon = TelegramThemeHooks.shared.image(.iconChatAttach).precomposed(theme.colors.grayIcon)

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().newPollOptionsHeader), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))
        index += 1

        for (i, optionText) in existingOptions.enumerated() {
            let viewType: GeneralViewType = i == 0 ? .firstItem : .innerItem
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("existing_\(i)"), data: InputDataGeneralData(name: optionText, color: theme.colors.grayText, viewType: viewType)))
            index += 1
        }

        let option = state.options[0]
        let placeholder = InputDataInputPlaceholder(nil, icon: theme.icons.pollAddOption, hasLimitationText: true)

        let rightItem: InputDataRightItem
        let isUploading = state.uploadingMedia.contains(option.identifier.identifier)
        let hasPreview: Bool
        if let file = option.media?.media as? TelegramMediaFile {
            hasPreview = !file.previewRepresentations.isEmpty || file.immediateThumbnailData != nil || file.isSticker || file.isAnimatedSticker || file.isVideoSticker || file.isVideo
        } else {
            hasPreview = option.media?.media != nil
        }
        if let media = option.media?.media, hasPreview {
            let progress = state.uploadProgress[option.identifier.identifier] ?? 0
            rightItem = .media(media, arguments.context, isUploading, progress, .custom({ _, control in
                arguments.attachMedia(option.identifier, control)
            }))
        } else {
            let icon = option.media?.thumbnail ?? attachIcon
            rightItem = .action(icon, .custom({ _, control in
                arguments.attachMedia(option.identifier, control)
            }))
        }

        struct AddOptionTuple: Equatable {
            let option: NewPollOption
            let rightItem: InputDataRightItem
        }
        let tuple = AddOptionTuple(option: option, rightItem: rightItem)

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: option.identifier, equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: tuple.option.textState, viewType: .lastItem, placeholder: placeholder, inputPlaceholder: strings().newPollOptionsPlaceholder, rightItem: tuple.rightItem, filter: { text in
                return text.trimmingCharacters(in: CharacterSet.newlines)
            }, updateState: { state in
                arguments.updateOptionState(option.identifier, state)
            }, limit: maxOptionLength, hasEmoji: arguments.context.isPremium)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        return entries
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.title.length > maxTextLength / 3 * 2 ? strings().newPollQuestionHeaderLimit(Int(maxTextLength) - state.title.length) : strings().newPollQuestionHeader), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))
    index += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_input_title, equatable: .init(state.textState), comparable: nil, item: { initialSize, stableId in
        return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: state.textState, viewType: .firstItem, placeholder: nil, inputPlaceholder: strings().newPollQuestionPlaceholder, filter: { text in
            var text = text
            while text.contains("\n\n\n") {
                text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            }
            if !text.isEmpty {
                while text.range(of: "\n")?.lowerBound == text.startIndex {
                    text = String(text[text.index(after: text.startIndex)...])
                }
            }
            return text
        }, updateState: arguments.updateState, limit: maxTextLength, hasEmoji: arguments.context.isPremium)
    }))
    index += 1

    let attachIcon = TelegramThemeHooks.shared.image(.iconChatAttach).precomposed(theme.colors.grayIcon)

    struct DescTuple: Equatable {
        let state: Updated_ChatTextInputState
        let media: NewPollMedia?
        let rightItem: InputDataRightItem
    }
    let descRightItem: InputDataRightItem
    let descUploading = state.uploadingMedia.contains("description")
    let descHasPreview: Bool
    if let file = state.descriptionMedia?.media as? TelegramMediaFile {
        descHasPreview = !file.previewRepresentations.isEmpty || file.immediateThumbnailData != nil || file.isSticker || file.isAnimatedSticker || file.isVideoSticker || file.isVideo
    } else {
        descHasPreview = state.descriptionMedia?.media != nil
    }
    if let media = state.descriptionMedia?.media, descHasPreview {
        let descProgress = state.uploadProgress["description"] ?? 0
        descRightItem = .media(media, arguments.context, descUploading, descProgress, .custom({ _, control in
            arguments.attachDescriptionMedia(control)
        }))
    } else {
        let icon = state.descriptionMedia?.thumbnail ?? attachIcon
        descRightItem = .action(icon, .custom({ _, control in
            arguments.attachDescriptionMedia(control)
        }))
    }
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_description, equatable: .init(DescTuple(state: state.descriptionState, media: state.descriptionMedia, rightItem: descRightItem)), comparable: nil, item: { initialSize, stableId in
        return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: state.descriptionState, viewType: .lastItem, placeholder: nil, inputPlaceholder: strings().newPollDescriptionPlaceholder, rightItem: descRightItem, filter: { $0 }, updateState: arguments.updateDescriptionState, limit: 255, hasEmoji: arguments.context.isPremium)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().newPollOptionsHeader), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))
    index += 1

    let sorted = state.options

    for (i, option) in sorted.enumerated() {

        var viewType: GeneralViewType = bestGeneralViewType(sorted, for: i)
        if i == sorted.count - 1, state.options.count < optionsLimit {
            if i == 0 {
                viewType = .firstItem
            } else {
                viewType = .innerItem
            }
        }
        let placeholder: InputDataInputPlaceholder?
        switch state.mode {
        case .quiz:
            placeholder = InputDataInputPlaceholder(nil, icon: option.selected ? theme.icons.chatToggleSelected : theme.icons.poll_quiz_unselected, drawBorderAfterPlaceholder: true, hasLimitationText: true, action: {
                arguments.updateQuizSelected(option.identifier)
            })
        default:
            placeholder = InputDataInputPlaceholder(nil, icon: theme.icons.resort, hasLimitationText: true)
        }
        let rightItem: InputDataRightItem
        let isUploading = state.uploadingMedia.contains(option.identifier.identifier)
        let hasPreview: Bool
        if let file = option.media?.media as? TelegramMediaFile {
            hasPreview = !file.previewRepresentations.isEmpty || file.immediateThumbnailData != nil || file.isSticker || file.isAnimatedSticker || file.isVideoSticker || file.isVideo
        } else {
            hasPreview = option.media?.media != nil
        }
        if let media = option.media?.media, hasPreview {
            let progress = state.uploadProgress[option.identifier.identifier] ?? 0
            rightItem = .media(media, arguments.context, isUploading, progress, .custom({ _, control in
                arguments.attachMedia(option.identifier, control)
            }))
        } else {
            let icon = option.media?.thumbnail ?? attachIcon
            rightItem = .action(icon, .custom({ _, control in
                arguments.attachMedia(option.identifier, control)
            }))
        }

        struct Tuple : Equatable {
            let option: NewPollOption
            let placeholder: InputDataInputPlaceholder?
            let viewType: GeneralViewType
            let rightItem: InputDataRightItem
        }
        let tuple = Tuple(option: option, placeholder: placeholder, viewType: viewType, rightItem: rightItem)

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: option.identifier, equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: tuple.option.textState, viewType: tuple.viewType, placeholder: tuple.placeholder, inputPlaceholder: strings().newPollOptionsPlaceholder, rightItem: tuple.rightItem, filter: { text in
                return text.trimmingCharacters(in: CharacterSet.newlines)
            }, updateState: { state in
                arguments.updateOptionState(option.identifier, state)
            }, limit: maxOptionLength, hasEmoji: arguments.context.isPremium)
        }))
    }
    if state.options.count < optionsLimit {
        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .string(nil), error: nil, identifier: _id_input_add_option, data: InputDataGeneralData(name: strings().newPollOptionsAddOption, color: theme.colors.accent, icon: theme.icons.pollAddOption, type: .none, viewType: state.options.isEmpty ? .singleItem : .lastItem, action: nil)))
        index += 1
    }

    index = 50

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.options.count < 2 ? strings().newPollOptionsDescriptionMinimumOther(2) : optionsLimit == state.options.count ? strings().newPollOptionsDescriptionLimitReached : strings().newPollOptionsDescriptionOther(optionsLimit - state.options.count)), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    // MARK: - Settings Section

    var hideMultiple: Bool = false
    var hideQuiz: Bool = false
    if let isQuiz = state.isQuiz {
        hideMultiple = isQuiz
        hideQuiz = true
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().newPollSettingsHeader), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))
    index += 1

    struct SettingRow {
        let identifier: InputDataIdentifier
        let name: String
        let iconName: String
        let iconColor: NSColor
        let description: String
        let isOn: Bool
        let enabled: Bool
        let action: () -> Void
        let disabledAction: (() -> Void)?
    }

    var settingRows: [SettingRow] = []

    if canBePublic {
        settingRows.append(SettingRow(
            identifier: _id_show_who_voted,
            name: strings().newPollShowWhoVoted,
            iconName: "Icon_Poll_eye",
            iconColor: theme.colors.accent,
            description: strings().newPollShowWhoVotedDesc,
            isOn: !state.mode.isAnonymous,
            enabled: true,
            action: {
                arguments.updateMode(state.mode.withUpdatedIsAnonymous(!state.mode.isAnonymous))
            },
            disabledAction: nil
        ))
    }

    if !hideMultiple {
        settingRows.append(SettingRow(
            identifier: _id_multiple_choice,
            name: strings().newPollAllowMultipleAnswers,
            iconName: "Icon_Poll_multiple",
            iconColor: theme.colors.redUI,
            description: strings().newPollAllowMultipleDesc,
            isOn: state.mode.isMultiple,
            enabled: true,
            action: {
                if state.mode.isMultiple {
                    arguments.updateMode(.normal(anonymous: state.mode.isAnonymous))
                } else {
                    arguments.updateMode(.multiple(anonymous: state.mode.isAnonymous))
                }
            },
            disabledAction: nil
        ))
    }

    settingRows.append(SettingRow(
        identifier: _id_allow_adding_options,
        name: strings().newPollAllowAddingOptions,
        iconName: "Icon_Poll_plus",
        iconColor: theme.colors.accent,
        description: strings().newPollAllowAddingDesc,
        isOn: state.allowAddingOptions,
        enabled: true,
        action: { arguments.toggleAllowAddingOptions() },
        disabledAction: nil
    ))

    settingRows.append(SettingRow(
        identifier: _id_allow_revoting,
        name: strings().newPollAllowRevoting,
        iconName: "Icon_Poll_rotate",
        iconColor: theme.colors.greenUI,
        description: strings().newPollAllowRevotingDesc,
        isOn: state.allowRevoting,
        enabled: true,
        action: { arguments.toggleAllowRevoting() },
        disabledAction: nil
    ))

    settingRows.append(SettingRow(
        identifier: _id_shuffle_options,
        name: strings().newPollShuffleOptions,
        iconName: "Icon_Poll_shuffle",
        iconColor: NSColor.systemOrange,
        description: strings().newPollShuffleDesc,
        isOn: state.shuffleOptions,
        enabled: true,
        action: { arguments.toggleShuffleOptions() },
        disabledAction: nil
    ))

    if !hideQuiz {
        settingRows.append(SettingRow(
            identifier: _id_quiz,
            name: strings().newPollSetCorrectAnswer,
            iconName: "Icon_Poll_checkbox",
            iconColor: theme.colors.greenUI,
            description: state.mode.isMultiple ? strings().newPollCorrectAnswerDescMultiple : strings().newPollCorrectAnswerDescSingle,
            isOn: state.mode.isQuiz,
            enabled: true,
            action: {
                if state.mode.isQuiz {
                    arguments.updateMode(.normal(anonymous: state.mode.isAnonymous))
                } else {
                    arguments.updateMode(.quiz(anonymous: state.mode.isAnonymous))
                }
            },
            disabledAction: nil
        ))
    }

    settingRows.append(SettingRow(
        identifier: _id_limit_duration,
        name: strings().newPollLimitDuration,
        iconName: "Icon_Poll_stopwatch",
        iconColor: theme.colors.redUI,
        description: strings().newPollLimitDurationDesc,
        isOn: state.limitDuration,
        enabled: true,
        action: { arguments.toggleLimitDuration() },
        disabledAction: nil
    ))

    if isChannel {
        settingRows.append(SettingRow(
            identifier: _id_restrict_to_subscribers,
            name: strings().newPollRestrictToSubscribers,
            iconName: "Icon_Poll_Subscribers",
            iconColor: theme.colors.accent,
            description: strings().newPollRestrictToSubscribersDesc,
            isOn: state.restrictToSubscribers,
            enabled: true,
            action: { arguments.toggleRestrictToSubscribers() },
            disabledAction: nil
        ))

        settingRows.append(SettingRow(
            identifier: _id_limit_by_country,
            name: strings().newPollLimitByCountry,
            iconName: "Icon_Poll_Country",
            iconColor: NSColor.systemOrange,
            description: strings().newPollLimitByCountryDesc,
            isOn: state.limitByCountry,
            enabled: true,
            action: { arguments.toggleLimitByCountry() },
            disabledAction: nil
        ))
    }

    for (i, row) in settingRows.enumerated() {
        let isFirst = i == 0
        let isLast: Bool
        if row.identifier == _id_limit_duration {
            isLast = i == settingRows.count - 1 && !state.limitDuration
        } else if row.identifier == _id_limit_by_country {
            isLast = !state.limitByCountry
        } else {
            isLast = i == settingRows.count - 1
        }
        let viewType: GeneralViewType = isFirst ? (isLast ? .singleItem : .firstItem) : (isLast ? .lastItem : .innerItem)

        let icon = NSImage(named: row.iconName)!.precomposed(flipVertical: true)

        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .string(nil), error: nil, identifier: row.identifier, data: InputDataGeneralData(name: row.name, color: theme.colors.text, icon: icon, type: .switchable(row.isOn), viewType: viewType, enabled: row.enabled, description: row.description, descTextColor: theme.colors.grayText, justUpdate: arc4random64(), action: row.action, disabledAction: row.disabledAction)))
        index += 1

        if row.identifier == _id_limit_by_country && state.limitByCountry {
            let spacerIcon = generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
                ctx.clear(CGRect(origin: .zero, size: size))
            })
            let countrySummary: String
            if state.countries.isEmpty {
                countrySummary = strings().newPollCountriesNone
            } else if state.countries.count == 1 {
                countrySummary = state.countries[0].name
            } else {
                countrySummary = strings().newPollCountriesCountOther(state.countries.count)
            }
            entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .string(nil), error: nil, identifier: _id_allowed_countries, data: InputDataGeneralData(name: strings().newPollAllowedCountries, color: theme.colors.text, icon: spacerIcon, type: .nextContext(countrySummary), viewType: .lastItem, justUpdate: arc4random64(), action: { arguments.openCountries() })))
            index += 1
        }
    }

    if state.limitDuration {
        let deadlineString = deadlineDisplayString(state)

        let spacerIcon = generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
            ctx.clear(CGRect(origin: .zero, size: size))
        })

        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .string(nil), error: nil, identifier: _id_deadline_value, data: InputDataGeneralData(name: state.deadlineDate != nil ? strings().newPollPollEnds : strings().newPollDuration, color: theme.colors.text, icon: spacerIcon, type: .contextSelector(deadlineString, arguments.deadlineMenuItems()), viewType: .innerItem, justUpdate: arc4random64())))
        index += 1

        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .string(nil), error: nil, identifier: _id_hide_results, data: InputDataGeneralData(name: strings().newPollHideResults, color: theme.colors.text, icon: spacerIcon, type: .switchable(state.hideResults), viewType: .lastItem, justUpdate: arc4random64(), action: {
            arguments.toggleHideResults()
        })))
        index += 1

        entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().newPollHideResultsDesc), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

    // MARK: - Quiz Explanation Section

    switch state.mode {
    case .quiz:
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().newPollExplanationHeader), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        struct SolTuple: Equatable {
            let text: NSAttributedString
            let media: NewPollMedia?
            let rightItem: InputDataRightItem
        }
        let solRightItem: InputDataRightItem
        let solUploading = state.uploadingMedia.contains("solution")
        let solHasPreview: Bool
        if let file = state.solutionMedia?.media as? TelegramMediaFile {
            solHasPreview = !file.previewRepresentations.isEmpty || file.immediateThumbnailData != nil || file.isSticker || file.isAnimatedSticker || file.isVideoSticker || file.isVideo
        } else {
            solHasPreview = state.solutionMedia?.media != nil
        }
        if let media = state.solutionMedia?.media, solHasPreview {
            let solProgress = state.uploadProgress["solution"] ?? 0
            solRightItem = .media(media, arguments.context, solUploading, solProgress, .custom({ _, control in
                arguments.attachSolutionMedia(control)
            }))
        } else {
            let icon = state.solutionMedia?.thumbnail ?? attachIcon
            solRightItem = .action(icon, .custom({ _, control in
                arguments.attachSolutionMedia(control)
            }))
        }
        let explanationInputState = Updated_ChatTextInputState(inputText: state.quizExplanation, selectionRange: 0..<state.quizExplanation.length)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_explanation, equatable: .init(SolTuple(text: state.quizExplanation, media: state.solutionMedia, rightItem: solRightItem)), comparable: nil, item: { initialSize, stableId in
            return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: explanationInputState, viewType: .singleItem, placeholder: nil, inputPlaceholder: strings().newPollExplanationPlaceholder, rightItem: solRightItem, filter: { text in
                return text.trimmingCharacters(in: CharacterSet.newlines)
            }, updateState: arguments.updateExplanationState, limit: 200, hasEmoji: arguments.context.isPremium)
        }))
        index += 1

        entries.append(InputDataEntry.desc(sectionId: sectionId, index: index, text: .plain(strings().newPollExplanationDesc), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    default:
        break
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

private func generateLocationPollThumbnail(latitude: Double, longitude: Double, completion: @escaping (CGImage?) -> Void) {
    let size = NSMakeSize(48, 48)
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(center: CLLocationCoordinate2DMake(latitude, longitude), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
    options.size = size
    options.showsPointsOfInterest = false
    let snapshotter = MKMapSnapshotter(options: options)
    snapshotter.start(with: .global()) { result, _ in
        DispatchQueue.main.async {
            guard let snapshot = result?.image else {
                completion(nil)
                return
            }
            let thumb = generateImage(NSMakeSize(24, 24), contextGenerator: { thumbSize, ctx in
                ctx.clear(CGRect(origin: .zero, size: thumbSize))
                ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: thumbSize), cornerWidth: 4, cornerHeight: 4, transform: nil))
                ctx.clip()
                if let cgImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    ctx.draw(cgImage, in: CGRect(origin: .zero, size: thumbSize))
                }
                let pin = TelegramThemeHooks.shared.image(.iconLocationPin).precomposed(.white)
                let pinBg: CGFloat = 10
                let pinBgRect = CGRect(x: (thumbSize.width - pinBg) / 2, y: (thumbSize.height - pinBg) / 2, width: pinBg, height: pinBg)
                ctx.setFillColor(theme.colors.accent.cgColor)
                ctx.fillEllipse(in: pinBgRect)
                let scale: CGFloat = 0.35
                let pinSize = NSMakeSize(pin.backingSize.width * scale, pin.backingSize.height * scale)
                let pinRect = CGRect(x: (thumbSize.width - pinSize.width) / 2, y: (thumbSize.height - pinSize.height) / 2, width: pinSize.width, height: pinSize.height)
                ctx.draw(pin, in: pinRect)
            })
            completion(thumb)
        }
    }
}

public enum NewPollSource {
    case new
    case addOption(messageId: MessageId, existingOptions: [String])
}

public func NewPollController(chatInteraction: any NewPollChatInteraction, isQuiz: Bool? = nil, source: NewPollSource = .new) -> InputDataModalController {
    
    
    let context = chatInteraction.pollContext
    
    let mode: NewPollMode
    if let isQuiz = isQuiz, isQuiz {
        mode = .quiz(anonymous: true)
    } else {
        mode = .normal(anonymous: true)
    }
    
    let initialOptions: [NewPollOption]
    if case .addOption = source {
        initialOptions = [NewPollOption(identifier: _id_input_option(), textState: .init(), selected: false)]
    } else {
        initialOptions = [NewPollOption(identifier: _id_input_option(), textState: .init(), selected: false), NewPollOption(identifier: _id_input_option(), textState: .init(), selected: false)]
    }
    var initialState = NewPollState(options: initialOptions, random: arc4random(), mode: mode, isQuiz: isQuiz, quizExplanation: NSAttributedString(), textState: .init())
    if case .addOption = source {
        initialState.isAddOption = true
    }
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((NewPollState) -> NewPollState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let optionsLimit = Int(context.appConfiguration.getGeneralValue("poll_answers_max", orElse: 10))
    
    var shouldMakeNextResponderAfterTransition: (InputDataIdentifier, Bool, InputDataIdentifier?, Bool)? = nil
    var shouldMakeNearResponderAfterTransition: (InputDataIdentifier, Int)? = nil

    let animated: Atomic<Bool> = Atomic(value: false)
    
    var showTooltipForQuiz:(()->Void)? = nil

    let uploadDisposables = DisposableDict<String>()

    var stickerCallback: ((TelegramMediaFile) -> Void)?
    let stickersController = PollResultsHooks.shared.makeStickersPicker(context, chatInteraction.pollPeerId, chatInteraction, { file in
        stickerCallback?(file)
    })

    let uploadPollMedia: (Media, String, CGImage?, InputDataIdentifier?) -> Void = { preparedMedia, slotKey, thumb, optionId in
        updateState { s in s.withUpdatedUploading(slotKey, true) }
        let uploadSignal: Signal<StandaloneUploadMediaEvent, StandaloneUploadMediaError>

        if let image = preparedMedia as? TelegramMediaImage,
           let rep = largestImageRepresentation(image.representations),
           let resource = rep.resource as? LocalFileReferenceMediaResource,
           let data = try? Data(contentsOf: URL(fileURLWithPath: resource.localFilePath)) {
            var thumbnailData: Data?
            if let smallRep = firstImageRepresentation(image.representations) {
                let path = context.account.postbox.mediaBox.resourcePath(smallRep.resource)
                thumbnailData = try? Data(contentsOf: URL(fileURLWithPath: path))
            }
            uploadSignal = standaloneUploadedImage(
                postbox: context.account.postbox,
                network: context.account.network,
                peerId: chatInteraction.pollPeerId,
                text: "",
                source: .data(data),
                thumbnailData: thumbnailData,
                dimensions: rep.dimensions
            )
        } else if let file = preparedMedia as? TelegramMediaFile {
            var thumbnailData: Data?
            if let smallRep = firstImageRepresentation(file.previewRepresentations) {
                let path = context.account.postbox.mediaBox.resourcePath(smallRep.resource)
                thumbnailData = try? Data(contentsOf: URL(fileURLWithPath: path))
            }
            thumbnailData = thumbnailData ?? file.immediateThumbnailData
            uploadSignal = standaloneUploadedFile(
                postbox: context.account.postbox,
                network: context.account.network,
                peerId: chatInteraction.pollPeerId,
                text: "",
                source: .resource(.standalone(resource: file.resource)),
                thumbnailData: thumbnailData,
                mimeType: file.mimeType,
                attributes: file.attributes,
                hintFileIsLarge: (file.size ?? 0) > 10 * 1024 * 1024
            )
        } else {
            updateState { s in
                if let optionId = optionId {
                    return s.withUpdatedOptionMedia(optionId, nil).withUpdatedUploading(slotKey, false)
                } else if slotKey == "solution" {
                    return s.withUpdatedSolutionMedia(nil).withUpdatedUploading(slotKey, false)
                } else {
                    return s.withUpdatedDescriptionMedia(nil).withUpdatedUploading(slotKey, false)
                }
            }
            return
        }

        let disposable = (uploadSignal |> deliverOnMainQueue).start(next: { event in
            switch event {
            case let .progress(value):
                updateState { s in s.withUpdatedUploadProgress(slotKey, value) }
            case let .result(result):
                switch result {
                case let .media(mediaRef):
                    let cloudMedia = mediaRef.media
                    updateState { s in
                        let pollMedia: NewPollMedia = .cloud(cloudMedia, thumbnail: thumb)
                        if let optionId = optionId {
                            return s.withUpdatedOptionMedia(optionId, pollMedia).withUpdatedUploading(slotKey, false)
                        } else if slotKey == "solution" {
                            return s.withUpdatedSolutionMedia(pollMedia).withUpdatedUploading(slotKey, false)
                        } else {
                            return s.withUpdatedDescriptionMedia(pollMedia).withUpdatedUploading(slotKey, false)
                        }
                    }
                }
            }
        }, error: { _ in
            updateState { s in
                if let optionId = optionId {
                    return s.withUpdatedOptionMedia(optionId, nil).withUpdatedUploading(slotKey, false)
                } else if slotKey == "solution" {
                    return s.withUpdatedSolutionMedia(nil).withUpdatedUploading(slotKey, false)
                } else {
                    return s.withUpdatedDescriptionMedia(nil).withUpdatedUploading(slotKey, false)
                }
            }
        })

        uploadDisposables.set(disposable, forKey: slotKey)
    }

    let generateAndUpload: (String, Bool, String, InputDataIdentifier?) -> Void = { path, isFile, slotKey, optionId in
  
        let container = MediaSenderContainer(path: path, isFile: isFile)
        let signal = PollResultsHooks.shared.generateMedia(container, context.account, false)
        |> deliverOnMainQueue

        let disposable = signal.start(next: { media, _ in
            if let optionId = optionId {
                updateState { $0.withUpdatedOptionMedia(optionId, .file(path: path, thumbnail: nil, media: media)) }
            } else if slotKey == "solution" {
                updateState { $0.withUpdatedSolutionMedia(.file(path: path, thumbnail: nil, media: media)) }
            } else {
                updateState { $0.withUpdatedDescriptionMedia(.file(path: path, thumbnail: nil, media: media)) }
            }
            uploadPollMedia(media, slotKey, nil, optionId)
        })
        uploadDisposables.set(disposable, forKey: slotKey + "_gen")
    }

    let showAttachMenu: (InputDataIdentifier?, Control) -> Void = { [stickersController] optionId, control in
        let menu = ContextMenu()
        let slotKey = optionId?.identifier ?? "description"
        let state = stateValue.with { $0 }

        let hasMedia: Bool
        if let optionId = optionId {
            hasMedia = state.options.first(where: { $0.identifier == optionId })?.media != nil
        } else {
            hasMedia = state.descriptionMedia != nil
        }
        
        menu.addItem(ContextMenuItem(strings().newPollAttachPhotoVideo, handler: {
            filePanel(with: mediaExts, allowMultiple: false, for: context.window) { paths in
                guard let path = paths?.first else { return }
                let ext = path.nsstring.pathExtension.lowercased()
                if photoExts.contains(ext), let image = NSImage(contentsOfFile: path) {
                    _ = (putToTemp(image: image, compress: true) |> deliverOnMainQueue).start(next: { tempPath in
                        generateAndUpload(tempPath, false, slotKey, optionId)
                    })
                } else {
                    generateAndUpload(path, false, slotKey, optionId)
                }
            }
        }, itemImage: MenuAnimation.menu_shared_media.value))

        if optionId == nil {
            menu.addItem(ContextMenuItem(strings().newPollAttachFile, handler: {
                filePanel(with: nil, allowMultiple: false, for: context.window) { paths in
                    guard let path = paths?.first else { return }
                    generateAndUpload(path, true, slotKey, optionId)
                }
            }, itemImage: MenuAnimation.menu_file.value))
        }

        if optionId != nil {
            menu.addItem(ContextMenuItem(strings().newPollAttachSticker, handler: { [weak stickersController] in
                stickerCallback = { file in
                    let media: NewPollMedia = .sticker(file, thumbnail: nil)
                    if let optionId = optionId {
                        updateState { $0.withUpdatedOptionMedia(optionId, media) }
                    }
                }
                if let stickersController = stickersController {
                    showPopover(for: control, with: stickersController, edge: .maxY, static: true)
                }
            }, itemImage: MenuAnimation.menu_smile.value))
        }

        menu.addItem(ContextMenuItem(strings().newPollAttachLocation, handler: {
            let locationController = LocationModalController(chatInteraction, destination: .select)
            locationController.selectCallback = { map in
                let media: NewPollMedia = .location(map, thumbnail: nil)
                updateState { s in
                    if let optionId = optionId {
                        return s.withUpdatedOptionMedia(optionId, media)
                    } else {
                        return s.withUpdatedDescriptionMedia(media)
                    }
                }
                generateLocationPollThumbnail(latitude: map.latitude, longitude: map.longitude) { thumb in
                    let media: NewPollMedia = .location(map, thumbnail: thumb)
                    updateState { s in
                        if let optionId = optionId {
                            return s.withUpdatedOptionMedia(optionId, media)
                        } else {
                            return s.withUpdatedDescriptionMedia(media)
                        }
                    }
                }
            }
            showModal(with: locationController, for: context.window)
        }, itemImage: MenuAnimation.menu_location.value))

        if hasMedia {
            menu.addItem(ContextSeparatorItem())
            menu.addItem(ContextMenuItem(strings().newPollAttachDelete, handler: {
                uploadDisposables.set(nil, forKey: slotKey)
                uploadDisposables.set(nil, forKey: slotKey + "_gen")
                updateState { s in
                    if let optionId = optionId {
                        return s.withUpdatedOptionMedia(optionId, nil).withUpdatedUploading(slotKey, false)
                    } else {
                        return s.withUpdatedDescriptionMedia(nil).withUpdatedUploading(slotKey, false)
                    }
                }
            }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
        }

        if let event = NSApp.currentEvent {
            AppMenu.show(menu: menu, event: event, for: control)
        }
    }

    let arguments = Arguments(context: context, deleteOption: { identifier in
        let state = stateValue.with { $0 }
        updateState { state in
            return state.withDeleteOption(identifier)
        }
        shouldMakeNearResponderAfterTransition = (identifier, state.indexOf(identifier)!)
    }, updateQuizSelected: { identifier in
        updateState { state in
            return state.withUnselectItems().withUpdatedOption({ option -> NewPollOption in
                return option.withUpdatedSelected(true)
            }, forKey: identifier)
        }
    }, updateMode: { mode in
        let oldMode = stateValue.with { $0.mode }

        updateState { state in
            if state.mode.isModeEqual(to: mode) {
                return state.withUpdatedMode(mode)
            } else {
                return state.withUnselectItems().withUpdatedMode(mode)
            }
        }
        if mode.isQuiz && !oldMode.isQuiz {
            showTooltipForQuiz?()
        }
    }, updateState: { state in
        updateState { current in
            var current = current
            current.textState = state
            return current
        }
    }, updateOptionState: { identifier, state in
        updateState { current in
            var current = current
            if let index = current.options.firstIndex(where: { $0.identifier == identifier }) {
                current.options[index] = current.options[index].withUpdatedText(state)
            }
            return current
        }
    }, toggleAllowAddingOptions: {
        updateState { s in
            var state = s.withUpdatedAllowAddingOptions(!s.allowAddingOptions)
            if state.allowAddingOptions && state.mode.isAnonymous {
                state = state.withUpdatedMode(state.mode.withUpdatedIsAnonymous(false))
            }
            return state
        }
    }, toggleAllowRevoting: {
        updateState { s in s.withUpdatedAllowRevoting(!s.allowRevoting) }
    }, toggleShuffleOptions: {
        updateState { s in s.withUpdatedShuffleOptions(!s.shuffleOptions) }
    }, toggleLimitDuration: {
        updateState { s in
            var s = s.withUpdatedLimitDuration(!s.limitDuration)
            if s.limitDuration && s.deadlineTimeout == nil && s.deadlineDate == nil {
                s = s.withUpdatedDeadlineTimeout(86400)
            }
            return s
        }
    }, selectDeadline: {
        FeatureNavigationHooks.shared.selectDate(context, context.window, Date(timeIntervalSince1970: Date().timeIntervalSince1970 + 86400), nil, .date(title: strings().newPollDeadline, doneTitle: strings().newPollSetDeadline), { date, _ in
            updateState { s in s.withUpdatedDeadlineDate(date).withUpdatedDeadlineTimeout(nil) }
        })
    }, deadlineMenuItems: {
        return [
            ContextMenuItem(strings().newPollDuration1Hour, handler: {
                updateState { s in s.withUpdatedDeadlineTimeout(3600).withUpdatedDeadlineDate(nil) }
            }),
            ContextMenuItem(strings().newPollDuration3Hours, handler: {
                updateState { s in s.withUpdatedDeadlineTimeout(10800).withUpdatedDeadlineDate(nil) }
            }),
            ContextMenuItem(strings().newPollDuration8Hours, handler: {
                updateState { s in s.withUpdatedDeadlineTimeout(28800).withUpdatedDeadlineDate(nil) }
            }),
            ContextMenuItem(strings().newPollDuration24Hours, handler: {
                updateState { s in s.withUpdatedDeadlineTimeout(86400).withUpdatedDeadlineDate(nil) }
            }),
            ContextMenuItem(strings().newPollDuration72Hours, handler: {
                updateState { s in s.withUpdatedDeadlineTimeout(259200).withUpdatedDeadlineDate(nil) }
            }),
            ContextMenuItem(strings().newPollCustom, handler: {
                FeatureNavigationHooks.shared.selectDate(context, context.window, Date(timeIntervalSince1970: Date().timeIntervalSince1970 + 86400), nil, .date(title: strings().newPollDeadline, doneTitle: strings().newPollSetDeadline), { date, _ in
                    updateState { s in s.withUpdatedDeadlineDate(date).withUpdatedDeadlineTimeout(nil) }
                })
            })
        ]
    }, toggleHideResults: {
        updateState { s in s.withUpdatedHideResults(!s.hideResults) }
    }, updateDescriptionState: { state in
        updateState { s in s.withUpdatedDescriptionState(state) }
    }, attachMedia: { identifier, control in
        showAttachMenu(identifier, control)
    }, attachDescriptionMedia: { control in
        showAttachMenu(nil, control)
    }, updateExplanationState: { state in
        updateState { s in s.withUpdatedQuizExplanation(state.inputText) }
    }, attachSolutionMedia: { control in
        let menu = ContextMenu()
        let state = stateValue.with { $0 }

        menu.addItem(ContextMenuItem(strings().newPollAttachPhotoVideo, handler: {
            filePanel(with: mediaExts, allowMultiple: false, for: context.window) { paths in
                guard let path = paths?.first else { return }
                let ext = path.nsstring.pathExtension.lowercased()
                if photoExts.contains(ext), let image = NSImage(contentsOfFile: path) {
                    _ = (putToTemp(image: image, compress: true) |> deliverOnMainQueue).start(next: { tempPath in
                        generateAndUpload(tempPath, false, "solution", nil)
                    })
                } else {
                    generateAndUpload(path, false, "solution", nil)
                }
            }
        }, itemImage: MenuAnimation.menu_shared_media.value))
        menu.addItem(ContextMenuItem(strings().newPollAttachFile, handler: {
            filePanel(with: nil, allowMultiple: false, for: context.window) { paths in
                guard let path = paths?.first else { return }
                generateAndUpload(path, true, "solution", nil)
            }
        }, itemImage: MenuAnimation.menu_file.value))

        menu.addItem(ContextMenuItem(strings().newPollAttachLocation, handler: {
            let locationController = LocationModalController(chatInteraction, destination: .select)
            locationController.selectCallback = { map in
                updateState { s in s.withUpdatedSolutionMedia(.location(map, thumbnail: nil)) }
                generateLocationPollThumbnail(latitude: map.latitude, longitude: map.longitude) { thumb in
                    updateState { s in s.withUpdatedSolutionMedia(.location(map, thumbnail: thumb)) }
                }
            }
            showModal(with: locationController, for: context.window)
        }, itemImage: MenuAnimation.menu_location.value))

        if state.solutionMedia != nil {
            menu.addItem(ContextSeparatorItem())
            menu.addItem(ContextMenuItem(strings().newPollAttachDelete, handler: {
                uploadDisposables.set(nil, forKey: "solution")
                uploadDisposables.set(nil, forKey: "solution_gen")
                updateState { s in s.withUpdatedSolutionMedia(nil).withUpdatedUploading("solution", false) }
            }, itemImage: MenuAnimation.menu_delete.value))
        }

        if let event = NSApp.currentEvent {
            AppMenu.show(menu: menu, event: event, for: control)
        }
    }, toggleRestrictToSubscribers: {
        updateState { s in s.withUpdatedRestrictToSubscribers(!s.restrictToSubscribers) }
    }, toggleLimitByCountry: {
        updateState { s in
            var updated = s.withUpdatedLimitByCountry(!s.limitByCountry)
            if !updated.limitByCountry {
                updated = updated.withUpdatedCountries([])
            }
            return updated
        }
    }, openCountries: {
        let current = stateValue.with { $0.countries }
        if let controller = FeatureNavigationHooks.shared.makeSelectCountriesController(context, current, { selected in
            updateState { s in s.withUpdatedCountries(selected) }
        }) { showModal(with: controller, for: context.window) }
    })


    let addOption:(Bool)-> InputDataValidation = { byClick in
        let option = NewPollOption(identifier: _id_input_option(), textState: .init(), selected: false)
        updateState { state in
            if state.options.count < optionsLimit {
                return state.withAddedOption(option)
            } else {
                return state
            }
        }
        shouldMakeNextResponderAfterTransition = (option.identifier, false, byClick ? _id_input_add_option : nil, true)
        
        return .none
    }
    
    var close: (() -> Void)? = nil
    
    
    
    let checkAndSend:() -> Void = {
        let state = stateValue.with { $0 }
    
        if state.isEnabled && !state.shouldShowTooltipForQuiz {
            chatInteraction.sendPollMedias([state.media(context)], state.descriptionState.textInputState(), false, nil, false, nil, false, nil, false)
            close?()
        } else if state.shouldShowTooltipForQuiz {
            showTooltipForQuiz?()
        }
    }


    let isAddOption: Bool
    if case .addOption = source {
        isAddOption = true
    } else {
        isAddOption = false
    }

    let interactions = ModalInteractions(acceptTitle: isAddOption ? strings().newPollAdd : strings().modalSend, accept: {
        let state = stateValue.with { $0 }
        if !state.uploadingMedia.isEmpty {
            showModalText(for: context.window, text: strings().newPollMediaUploading)
            return
        }
        if case let .addOption(messageId, existingOptions) = source {
            guard let opt = state.options.first else { return }
            let text = opt.text.trimmed
            if text.isEmpty { return }
            let entities = opt.textState.textInputState().messageTextEntities()
            let opaqueId = "\(existingOptions.count)".data(using: .utf8) ?? Data()
            let pollOption = TelegramMediaPollOption(text: text, entities: entities, opaqueIdentifier: opaqueId, media: opt.media?.media, date: context.timestamp, addedBy: context.peerId)
            chatInteraction.appendPollOption(messageId, pollOption)
            close?()
        } else {
            checkAndSend()
        }
    }, singleButton: true)
    interactions.contentFlowsBehind = true


    let canBePublic: Bool
    let isChannel: Bool
    if let peer = chatInteraction.pollMainPeer {
        canBePublic = !peer.isChannel
        isChannel = peer.isChannel
    } else {
        canBePublic = true
        isChannel = false
    }


    let signal: Signal<InputDataSignalValue, NoError> = statePromise.get() |> deliverOnMainQueue |> map { value in
        return InputDataSignalValue(entries: entries(value, arguments: arguments, canBePublic: canBePublic, isChannel: isChannel, source: source), animated: animated.swap(true))
    }


    let controller = InputDataController(dataSignal: signal, title: isAddOption ? strings().newPollAddOptionTitle : (isQuiz == true ? strings().newPollTitleQuiz : strings().newPollTitle), validateData: { data -> InputDataValidation in
        
        if let _ = data[_id_input_add_option] {
            return addOption(true)
        }
        
        let state = stateValue.with { $0 }
        
        var fails: [InputDataIdentifier : InputDataValidationFailAction] = [:]
        if state.textState.string.trimmed.isEmpty {
            fails[_id_input_title] = .shake
        }
        for value in state.options {
            if value.text.trimmed.isEmpty {
                fails[value.identifier] = .shake
            }
        }
        
        if !fails.isEmpty {
            
            let state = stateValue.with { $0 }
            
            if fails.contains(where: {$0.key == _id_input_title}) {
                shouldMakeNextResponderAfterTransition = (_id_input_title, true, nil, true)
            } else {
                for option in state.options {
                    if fails.contains(where: {$0.key == option.identifier}) {
                        shouldMakeNextResponderAfterTransition = (option.identifier, true, nil, true)
                        break
                    }
                }
            }
        }
        
        return .fail(.doSomething { f in
            
            f(.fail(.fields(fails)))
            
            var addedOptions: Int? = nil
            updateState { state in
                var state = state
                if fails.isEmpty {
                    if state.options.count < 2 {
                        state = state.withAddedOption(NewPollOption(identifier: _id_input_option(), textState: .init(), selected: false))
                        if addedOptions == nil {
                            addedOptions = state.options.count - 1
                        }
                    }
                }
                return state.withUpdatedState()
            }
            
            if let addedOptions = addedOptions {
                let state = stateValue.with { $0 }
                shouldMakeNextResponderAfterTransition = (state.options[addedOptions].identifier, false, nil, true)
            }
        })
        
    }, updateDatas: { data in
        return .none
    }, afterDisappear: {
        uploadDisposables.dispose()
    }, updateDoneValue: { data in
        return { f in
            f(.disabled(strings().navigationDone))
        }
    }, removeAfterDisappear: true, hasDone: true, identifier: "new-poll", afterTransaction: { controller in
        
        if let (identifier, checkEmptyCurrent, focusIdentifier, scrollIfNeeded) = shouldMakeNextResponderAfterTransition {
            var markResponder: Bool = true
            let state = stateValue.with { $0 }
            if let current = controller.currentFirstResponderIdentifier, checkEmptyCurrent {
                if current == _id_input_title, state.title.trimmed.isEmpty  {
                    markResponder = false
                }
                if let option = state.options.first(where: {$0.identifier == current}), option.text.trimmed.isEmpty {
                    markResponder = false
                }
            }
            if markResponder {
                controller.makeFirstResponderIfPossible(for: identifier, focusIdentifier: focusIdentifier, scrollIfNeeded: scrollIfNeeded)
            }
            shouldMakeNextResponderAfterTransition = nil
        }
        
        if let (_, index) = shouldMakeNearResponderAfterTransition {
            
            let state = stateValue.with { $0 }
            if !state.options.isEmpty {
                if controller.currentFirstResponderIdentifier == nil {
                    if index == 0 {
                        if !state.options.isEmpty {
                            controller.makeFirstResponderIfPossible(for: state.options[0].identifier)
                        }
                    } else {
                        controller.makeFirstResponderIfPossible(for: state.options[index - 1].identifier)
                    }
                }
            } else {
                controller.makeFirstResponderIfPossible(for: _id_input_title)
            }
            
            
            
            shouldMakeNearResponderAfterTransition = nil
        }
        
        var range: NSRange = NSMakeRange(NSNotFound, 0)
        let state = stateValue.with { $0 }

        controller.tableView.enumerateItems(with: { item -> Bool in
            if let identifier = (item.stableId.base as? InputDataEntryId)?.identifier {
                if let _ = state.indexOf(identifier) {
                    if range.location == NSNotFound {
                        range.location = item.index
                    }
                    range.length += 1
                }
            }

            return true
        })

        if range.location != NSNotFound {
            let hasAddOption = state.options.count < optionsLimit
            let totalCount = range.length + (hasAddOption ? 1 : 0)

            let resortController = TableResortController(resortRange: range, start: { _ in }, resort: { _ in }, complete: { from, to in
                let fromIdx = from - range.location
                let toIdx = to - range.location
                _ = animated.swap(false)
                updateState { $0.withUpdatedPos(fromIdx, toIdx) }
            }, updateItems: { [weak controller] resortView, items in
                guard let resortController = controller?.tableView.resortController,
                      let holeIndex = resortController.currentHoleIndex else { return }

                let holePos = holeIndex - range.location
                let count = totalCount

                for item in items {
                    guard let view = item.view as? GeneralContainableRowView else { continue }
                    let pos = item.index - range.location
                    let isDragged = view === resortView

                    let visualPos: Int
                    if isDragged {
                        visualPos = holePos
                    } else if let resortRow = resortController.resortRow {
                        let origPos = resortRow - range.location
                        if origPos < holePos {
                            if pos > origPos && pos <= holePos {
                                visualPos = pos - 1
                            } else {
                                visualPos = pos
                            }
                        } else if origPos > holePos {
                            if pos >= holePos && pos < origPos {
                                visualPos = pos + 1
                            } else {
                                visualPos = pos
                            }
                        } else {
                            visualPos = pos
                        }
                    } else {
                        visualPos = pos
                    }

                    let corners: GeneralViewItemCorners
                    if count == 1 {
                        corners = .all
                    } else if visualPos == 0 {
                        corners = [.topLeft, .topRight]
                    } else if visualPos == count - 1 {
                        corners = [.bottomLeft, .bottomRight]
                    } else {
                        corners = []
                    }
                    view.containerView.setCorners(corners, animated: true)
                    let isLast = visualPos == count - 1
                    view.borderView.isHidden = isLast || isDragged
                }
            })
            resortController.completeDelay = 0
            controller.tableView.resortController = resortController
        } else {
            controller.tableView.resortController = nil
        }

        interactions.updateDone { done in
            done.isEnabled = state.isEnabled
        }
        
    }, returnKeyInvocation: { identifier, event in
        
        if FastSettings.checkSendingAbility(for: event) {
            checkAndSend()
            return .default
        } else {
            let state = stateValue.with { $0 }
            
            
            if identifier == _id_input_title || identifier == _id_description {
                if state.options.isEmpty {
                    _ = addOption(false)
                    return .nothing
                }
                return .invokeEvent
            }
            
            if let identifier = identifier {
                
                let index: Int? = state.indexOf(identifier)
                let isLast = index == state.options.count - 1
                
                if isLast {
                    if state.options.count == optionsLimit {
                        return .nothing
                    } else {
                        _ = addOption(false)
                        return .nothing
                    }
                } else {
                    return .nextResponder
                }
            }
        }
        

        return .nothing
    }, deleteKeyInvocation: { identifier in
        
        let state = stateValue.with { $0 }
        if let index = state.options.firstIndex(where: { $0.identifier == identifier}) {
            if state.options[index].text.isEmpty {
                arguments.deleteOption(state.options[index].identifier)
                return .invoked
            }
        }
        
        return .default
    })
    if isAddOption {
        controller.analyticsScreen = .chatPollAddOption
    } else {
        controller.analyticsScreen = .chatPollCreate
    }
    
    
    let modalController = InputDataModalController(controller, modalInteractions: interactions, closeHandler: { f in
        let state = stateValue.with { $0 }
        
        if !state.title.isEmpty || !state.descriptionState.string.isEmpty || !state.options.filter({!$0.text.isEmpty}).isEmpty {
            verifyAlert_button(for: context.window, header: strings().newPollDisacardConfirmHeader, information: strings().newPollDisacardConfirm, ok: strings().newPollDisacardConfirmYes, cancel: strings().newPollDisacardConfirmNo, successHandler: { _ in
                f()
            })
        } else {
            f()
        }
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    showTooltipForQuiz = { [weak controller] in
        let options = stateValue.with({ $0.options })
        for option in options {
            let view = controller?.tableView.item(stableId: InputDataEntryId.custom(option.identifier))?.view as? InputTextDataRowView
            if view?.visibleRect.height == view?.frame.height {
                delay(0.2, closure: { [weak view] in
                    view?.showPlaceholderActionTooltip(strings().newPollQuizTooltip)
                })
                break
            }
            
        }
        
    }
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: close)
    
    
    chatInteraction.pollContext.window.set(handler: { [weak controller] _ -> KeyHandlerResult in
        if let controller = controller {
            let state = stateValue.with {$0}
            
            let id = controller.currentFirstResponderIdentifier
            
            if let id = id, let index = state.indexOf(id) {
                let option = state.options[index]
                if state.options.count - 1 == index, state.options.count < 10 {
                    if !option.text.isEmpty {
                        _ = addOption(false)
                        return .invoked
                    }
                }
            }
            
        }
        return .rejected
    }, with: controller, for: .Tab, priority: .supreme)
    
    return modalController
    
}
