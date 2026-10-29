import Cocoa
import Cocoa
import TGUIKit
import ComponentsUI
import TelegramCore
import InAppSettings
import Postbox
import SwiftSignalKit
import ColorPalette
import TelegramMediaResources
import ChatHistoryModel
import ChatModeTypes
import FoundationUtils
import GeneralRows
import Localization
import MessageUtils
import SceneEffects
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer


private extension TelegramMediaPoll {
    func translated(_ poll: TranslationMessageAttribute) -> TelegramMediaPoll {
        var options: [TelegramMediaPollOption] = self.options
        for (i, option) in options.enumerated() {
            options[i] = .init(text: poll.additional[i].text, entities: poll.additional[i].entities, opaqueIdentifier: option.opaqueIdentifier, media: option.media, date: option.date, addedBy: option.addedBy)
        }

        let solution: TelegramMediaPollResults.Solution?
        if let value = poll.pollSolution {
            solution = .init(text: value.text, entities: value.entities)
        } else {
            solution = self.results.solution
        }

        let result: TelegramMediaPollResults = .init(voters: self.results.voters, totalVoters: self.results.totalVoters, recentVoters: self.results.recentVoters, solution: solution, hasUnseenVotes: self.results.hasUnseenVotes, canViewStats: self.results.canViewStats)
        return .init(pollId: self.pollId, publicity: self.publicity, kind: self.kind, text: poll.text, textEntities: poll.entities, options: options, correctAnswers: self.correctAnswers, results: result, isClosed: self.isClosed, deadlineTimeout: self.deadlineTimeout, deadlineDate: self.deadlineDate, pollHash: self.pollHash, openAnswers: self.openAnswers, revotingDisabled: self.revotingDisabled, shuffleAnswers: self.shuffleAnswers, hideResultsUntilClose: self.hideResultsUntilClose, attachedMedia: self.attachedMedia)
    }
}


public func isPollEffectivelyClosed(message: Message, poll: TelegramMediaPoll) -> Bool {
    if poll.isClosed {
        return true
    } /*else if let deadlineTimeout = poll.deadlineTimeout, message.id.namespace == Namespaces.Message.Cloud {
        let startDate: Int32
        if let forwardInfo = message.forwardInfo {
            startDate = forwardInfo.date
        } else {
            startDate = message.timestamp
        }
        
        let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        if timestamp >= startDate + deadlineTimeout {
            return true
        } else {
            return false
        }
    }*/ else {
        return false
    }
}




private func isPollGalleryMedia(_ media: Media) -> Bool {
    if let file = media as? TelegramMediaFile {
        return (file.isGraphicFile || file.isVideoFile) && !file.isSticker && !file.isAnimatedSticker && !file.isVideoSticker
    } else if media is TelegramMediaImage {
        return true
    }
    return false
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        self.state = seed
    }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}




private final class PollOption : Equatable {
    let option: TelegramMediaPollOption
    let nameText: TextViewLayout
    let percent: Float?
    let voteCount: Int32
    let realPercent: Float
    let isSelected: Bool
    let voted: Bool
    let isIncoming: Bool
    let isBubbled: Bool
    let isLoading: Bool
    let presentation: TelegramPresentationTheme
    let contentSize: NSSize
    let vote:(Control)-> Void
    let isCorrect: Bool?
    let isQuiz: Bool
    let isMultipleSelected: Bool
    let isMultipleChoice: Bool
    let isTranslateLoading: Bool
    let recentVoters: [PeerId]
    let voteCountText: TextViewLayout?
    let optionMedia: Media?
    let hideResults: Bool
    init(option:TelegramMediaPollOption, nameText: TextViewLayout, percent: Float?, realPercent: Float, voteCount: Int32, isSelected: Bool, isIncoming: Bool, isBubbled: Bool, voted: Bool, isLoading: Bool, presentation: TelegramPresentationTheme, isCorrect: Bool?, isQuiz: Bool, isMultipleSelected: Bool, isMultipleChoice: Bool, optionMedia: Media? = nil, anyOptionHasMedia: Bool = false, hideResults: Bool = false, vote: @escaping(Control)->Void = { _ in }, contentSize: NSSize = NSZeroSize, isTranslateLoading: Bool, recentVoters: [PeerId] = [], voteCountText: TextViewLayout? = nil) {
        self.option = option
        self.nameText = nameText
        self.percent = percent
        self.realPercent = realPercent
        self.isSelected = isSelected
        self.voted = voted
        self.presentation = presentation
        self.isIncoming = isIncoming
        self.isBubbled = isBubbled
        self.isLoading = isLoading
        self.vote = vote
        self.voteCount = voteCount
        self.contentSize = contentSize
        self.isCorrect = isCorrect
        self.isQuiz = isQuiz
        self.isMultipleSelected = isMultipleSelected
        self.isMultipleChoice = isMultipleChoice
        self.isTranslateLoading = isTranslateLoading
        self.recentVoters = recentVoters
        self.optionMedia = optionMedia
        self.anyOptionHasMedia = anyOptionHasMedia
        self.hideResults = hideResults
        if let voteCountText = voteCountText {
            self.voteCountText = voteCountText
        } else if percent != nil && voteCount > 0 {
            let layout = TextViewLayout(.initialize(string: "\(Int(voteCount).separatedNumber)", color: presentation.chat.grayText(isIncoming, isBubbled), font: .normal(.small)))
            self.voteCountText = layout
        } else {
            self.voteCountText = nil
        }
    }

    func withUpdatedLoading(_ isLoading: Bool) -> PollOption {
        return PollOption(option: self.option, nameText: self.nameText, percent: self.percent, realPercent: self.realPercent, voteCount: self.voteCount, isSelected: self.isSelected, isIncoming: self.isIncoming, isBubbled: self.isBubbled, voted: self.voted, isLoading: isLoading, presentation: self.presentation, isCorrect: self.isCorrect, isQuiz: self.isQuiz, isMultipleSelected: self.isMultipleSelected, isMultipleChoice: self.isMultipleChoice, optionMedia: self.optionMedia, anyOptionHasMedia: self.anyOptionHasMedia, hideResults: self.hideResults, vote: self.vote, contentSize: self.contentSize, isTranslateLoading: self.isTranslateLoading, recentVoters: self.recentVoters, voteCountText: self.voteCountText)
    }
    func withUpdatedContentSize(_ contentSize: NSSize) -> PollOption {
        return PollOption(option: self.option, nameText: self.nameText, percent: self.percent, realPercent: self.realPercent, voteCount: self.voteCount, isSelected: self.isSelected, isIncoming: self.isIncoming, isBubbled: self.isBubbled, voted: self.voted, isLoading: self.isLoading, presentation: self.presentation, isCorrect: self.isCorrect, isQuiz: self.isQuiz, isMultipleSelected: self.isMultipleSelected, isMultipleChoice: self.isMultipleChoice, optionMedia: self.optionMedia, anyOptionHasMedia: self.anyOptionHasMedia, hideResults: self.hideResults, vote: self.vote, contentSize: contentSize, isTranslateLoading: self.isTranslateLoading, recentVoters: self.recentVoters, voteCountText: self.voteCountText)
    }
    func withUpdatedSelected(_ isSelected: Bool) -> PollOption {
        return PollOption(option: self.option, nameText: self.nameText, percent: self.percent, realPercent: self.realPercent, voteCount: self.voteCount, isSelected: isSelected, isIncoming: self.isIncoming, isBubbled: self.isBubbled, voted: self.voted, isLoading: self.isLoading, presentation: self.presentation, isCorrect: self.isCorrect, isQuiz: self.isQuiz, isMultipleSelected: self.isMultipleSelected, isMultipleChoice: self.isMultipleChoice, optionMedia: self.optionMedia, anyOptionHasMedia: self.anyOptionHasMedia, hideResults: self.hideResults, vote: self.vote, contentSize: self.contentSize, isTranslateLoading: self.isTranslateLoading, recentVoters: self.recentVoters, voteCountText: self.voteCountText)
    }

    static func ==(lhs: PollOption, rhs: PollOption) -> Bool {
        return lhs.option == rhs.option && lhs.percent == rhs.percent && lhs.isSelected == rhs.isSelected && lhs.isIncoming == rhs.isIncoming && lhs.isLoading == rhs.isLoading && lhs.contentSize == rhs.contentSize && lhs.voted == rhs.voted && lhs.realPercent == rhs.realPercent && lhs.voteCount == rhs.voteCount && lhs.isCorrect == rhs.isCorrect && lhs.isQuiz == rhs.isQuiz && lhs.isMultipleSelected == rhs.isMultipleSelected && lhs.isMultipleChoice == rhs.isMultipleChoice && lhs.isTranslateLoading == rhs.isTranslateLoading && lhs.recentVoters == rhs.recentVoters && lhs.anyOptionHasMedia == rhs.anyOptionHasMedia && lhs.hideResults == rhs.hideResults
    }
    
    
    var leftOptionInset: CGFloat {
        return 40 + PollOption.spaceBetweenTexts
    }
    var currentPercentImage: CGImage? {
       return presentation.chat.pollPercentAnimatedIcon(isIncoming, isBubbled, value: Int(realPercent))
    }
    
    static var spaceBetweenTexts: CGFloat {
        return 6
    }
    static var spaceBetweenOptions: CGFloat {
        return 0
    }
    static var mediaSize: CGFloat {
        return 34
    }

    let anyOptionHasMedia: Bool

    var hasMedia: Bool {
        return optionMedia != nil
    }
    
    var tooltip: String {
        var totalOptionVotes = self.isQuiz ? strings().chatQuizTooltipVotesOther(Int(self.voteCount)) : strings().chatPollTooltipVotesOther(Int(self.voteCount))
        totalOptionVotes = totalOptionVotes.replacingOccurrences(of: "\(self.voteCount)", with: Int(self.voteCount).separatedNumber)
        return self.voteCount == 0 ? (self.isQuiz ? strings().chatQuizTooltipNoVotes : strings().chatPollTooltipNoVotes) : totalOptionVotes
    }
    
    func measure(width: CGFloat) -> NSSize {
        let mediaInset: CGFloat = PollOption.mediaSize + 8
        nameText.measure(width: width - leftOptionInset - mediaInset)
        voteCountText?.measure(width: .greatestFiniteMagnitude)
        let textHeight = 10 + nameText.layoutSize.height + PollOption.spaceBetweenOptions
        let height = max(textHeight, PollOption.mediaSize + 10 + PollOption.spaceBetweenOptions)
        let contentSize = NSMakeSize(nameText.layoutSize.width + leftOptionInset + mediaInset, height)
        if isTranslateLoading {
            nameText.maskBlockImage = nameText.generateBlock(backgroundColor: .blackTransparent)
        }
        return contentSize
    }
}

public class ChatPollItem: ChatRowItem {
    private(set) fileprivate var attachedMedia: Media?
    private(set) fileprivate var attachedMediaSize: NSSize = .zero
    public func contentNodeType() -> ChatMediaContentView.Type? {
        if let media = attachedMedia {
            return ChatLayoutUtils.contentNode(for: media)
        }
        return nil
    }

    public var positionFlags: LayoutPositionFlags? = nil

    public var mediaBubbleCornerInset: CGFloat {
        return 1
    }

    public var hasUpsideSomething: Bool {
        return authorText != nil || replyModel != nil || topicLinkLayout != nil || forwardNameLayout != nil
    }

    public override var isBubbleFullFilled: Bool {
        return attachedMedia?.isInteractiveMedia == true && isBubbled
    }

    public override var bubbleFrame: NSRect {
        var frame = super.bubbleFrame
        if isBubbleFullFilled {
            frame.size.width = contentSize.width + additionBubbleInset
            if hasBubble {
                frame.size.width += self.mediaBubbleCornerInset * 2
            }
        }
        return frame
    }

    public override var contentOffset: NSPoint {
        var offset = super.contentOffset
        if hasBubble, isBubbleFullFilled, !hasUpsideSomething {
            offset.y -= defaultContentInnerInset
        } else if hasBubble, isBubbleFullFilled, hasUpsideSomething {
            offset.y += topInset
        }
        return offset
    }

    public override var elementsContentInset: CGFloat {
        if hasBubble && isBubbleFullFilled {
            return bubbleContentInset
        }
        return super.elementsContentInset
    }

    public var mediaParameters: ChatMediaLayoutParameters?
    fileprivate var explanationLayout: WPLayout?
    fileprivate var solutionRevealed: Bool = false

    private(set) fileprivate var descriptionText:TextViewLayout?
    private(set) fileprivate var titleText:TextViewLayout!
    private(set) fileprivate var titleTypeText:TextViewLayout!

    private(set) fileprivate var options:[PollOption] = []
    private(set) fileprivate var totalVotesText:TextViewLayout?

    fileprivate let poll: TelegramMediaPoll
    fileprivate var canAddOption: Bool {
        let hasVoted = options.contains(where: { $0.isSelected })
        return poll.openAnswers && !isClosed && !hasVoted
    }
    
    public var actionButtonText: String? {
        if isBotQuiz {
            return nil
        }
        let totalCount = poll.results.totalVoters ?? 0
        let viewVotesText = strings().chatPollViewVotesOther(Int(totalCount))
        if self.isClosed {
            if totalCount == 0 {
                return nil
            }
            if poll.publicity != .anonymous {
                return viewVotesText
            } else {
                return nil
            }
        }
        let hasSelected = options.contains(where: { $0.isSelected })
        if poll.isMultiple {
            if !hasSelected {
                return strings().chatPollSubmitVote
            } else {
                if poll.publicity != .anonymous {
                    if hasSelected {
                        return viewVotesText
                    }
                }
            }
        } else {
            if poll.publicity != .anonymous {
                if hasSelected {
                    return viewVotesText
                }
            }
        }
        return nil
    }
    
    public var actionButtonIsEnabled: Bool {
        guard let message = message else {
            return false
        }
        if message.flags.contains(.Failed) || message.flags.contains(.Sending) || message.flags.contains(.Unsent) {
            return false
        }
        let hasSelected = options.contains(where: { $0.isMultipleSelected }) || options.contains(where: { $0.isSelected })
        if poll.isMultiple {
            return hasSelected
        } else {
            return true
        }
    }
    
    public var isClosed: Bool {
       return isPollEffectivelyClosed(message: message!, poll: poll)
    }

    public var showResultsIn: Bool {
        guard let _ = poll.deadlineTimeout else { return false }
        if isClosed { return false }
        let hasVoted = options.contains(where: { $0.isSelected })
        if poll.hideResultsUntilClose {
            return true
        }
        return !hasVoted
    }

    public var deadlineEndDate: Int32? {
        guard let deadlineTimeout = poll.deadlineTimeout, let message = message else { return nil }
        let startDate: Int32
        if let forwardInfo = message.forwardInfo {
            startDate = forwardInfo.date
        } else {
            startDate = message.timestamp
        }
        return startDate + deadlineTimeout
    }

    public struct GalleryMediaInfo {
        public var medias: [Media]
        public var attachedMediaIndex: Int?
        public var galleryToOptionIndex: [Int: Int]
    }

    public func allGalleryMedias() -> GalleryMediaInfo {
        var medias: [Media] = []
        var galleryToOption: [Int: Int] = [:]
        var attachedMediaIndex: Int? = nil

        if let media = attachedMedia, isPollGalleryMedia(media) {
            attachedMediaIndex = medias.count
            medias.append(media)
        }

        for (i, option) in options.enumerated() {
            if let m = option.optionMedia, isPollGalleryMedia(m) {
                galleryToOption[medias.count] = i
                medias.append(m)
            }
        }

        return GalleryMediaInfo(medias: medias, attachedMediaIndex: attachedMediaIndex, galleryToOptionIndex: galleryToOption)
    }

    public func openGallery(firstIndex: Int) {
        guard let message = message else { return }
        let info = allGalleryMedias()
        if let view = self.table?.item(stableId: self.stableId)?.view as? ChatPollItemView {
            view.galleryIndexToOptionIndex = info.galleryToOptionIndex
            view.attachedMediaGalleryIndex = info.attachedMediaIndex
        }
        showGalleryMedia(context: context, medias: info.medias, parent: message, firstIndex: firstIndex, firstStableId: ChatHistoryEntryId.mediaId(firstIndex, message), self.table, nil)
    }

    public var isBotQuiz: Bool {
        if let message = message {
            if self.poll.isQuiz {
                return coreMessageMainPeer(message)?.isBot == true
            }
        }
        return false
    }
    
    public let isTranslateLoading: Bool

    fileprivate var canCopyText: Bool {
        guard let message = message, !message.flags.contains(.CopyProtected) else {
            return false
        }
        let peer = chatInteraction.peer.flatMap { $0.id == message.id.peerId ? $0 : nil } ?? message.peers[message.id.peerId]
        return peer.map { !$0.isCopyProtected(cachedData: chatInteraction.presentation.cachedData) } ?? false
    }
    
    public override init(_ initialSize: NSSize, _ chatInteraction: ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        
        
        var poll = object.message!.media[0] as! TelegramMediaPoll
        
        let isTranslateLoading: Bool
        if let translate = object.additionalData.translate {
            switch translate {
            case .loading:
                isTranslateLoading = true
            case let .complete(toLang: toLang):
                if let attribute = object.message!.translationAttribute(toLang: toLang) {
                    poll = poll.translated(attribute)
                }
                isTranslateLoading = false
            }
        } else {
            isTranslateLoading = false
        }
        self.poll = poll
        self.isTranslateLoading = isTranslateLoading
        super.init(initialSize, chatInteraction, context, object, theme: theme)

        self.attachedMedia = poll.attachedMedia

        if let map = poll.attachedMedia as? TelegramMediaMap {
            let resource = MapSnapshotMediaResource(latitude: map.latitude, longitude: map.longitude, width: 320 * 2, height: 120 * 2, zoom: 15)
            self.mediaParameters = ChatMediaMapLayoutParameters(map: map, resource: resource, presentation: .make(for: object.message!, account: context.account, renderType: object.renderType, theme: theme), automaticDownload: true, execute: { [weak self] in
                guard let message = self?.message else { return }
                ChatNavigationHooks.shared.showLocationPreview(context, map, message.effectiveAuthor, message.id, context.window)
            })
        } else if let file = poll.attachedMedia as? TelegramMediaFile, !file.isVideo {
            let presentation: ChatMediaPresentation = .make(for: object.message!, account: context.account, renderType: object.renderType, theme: theme)
            self.mediaParameters = ChatMediaLayoutParameters.layout(for: file, isWebpage: false, chatInteraction: chatInteraction, presentation: presentation, automaticDownload: downloadSettings.isDownloable(object.message!), isIncoming: object.message!.isIncoming(context.account, object.renderType == .bubble), isFile: true, autoplayMedia: object.autoplayMedia, isChatRelated: true, isCopyProtected: object.message!.isCopyProtected(cachedData: chatInteraction.presentation.cachedData))
        } else if let media = poll.attachedMedia {
            self.mediaParameters = ChatMediaGalleryParameters(showMedia: { [weak self] message in
                guard let self = self else { return }
                if let idx = self.allGalleryMedias().attachedMediaIndex {
                    self.openGallery(firstIndex: idx)
                }
            }, isWebpage: false, presentation: .make(for: object.message!, account: context.account, renderType: object.renderType, theme: theme), media: media, automaticDownload: true)
        }
        self.mediaParameters?.bubbleCorners = { [weak self] in
            guard let self else {
                return nil
            }
            return self.mediaBubbleCorners(inset: self.mediaBubbleCornerInset)
        }

        self.solutionRevealed = object.additionalData.solutionRevealed
        if solutionRevealed, let solution = poll.results.solution {
            let image = solution.media as? TelegramMediaImage
            let file = solution.media as? TelegramMediaFile
            let fakeContent = TelegramMediaWebpageLoadedContent(url: "", displayUrl: "", hash: 0, type: nil, websiteName: strings().chatPollExplanation, title: nil, text: solution.text, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: image, file: file, story: nil, attributes: [], instantPage: nil)
            if file != nil || image != nil {
                self.explanationLayout = WPMediaLayout(with: fakeContent, context: context, chatInteraction: chatInteraction, parent: object.message!, fontSize: theme.fontSize, presentation: wpPresentation, approximateSynchronousValue: false, downloadSettings: downloadSettings, autoplayMedia: object.autoplayMedia, theme: theme, mayCopyText: true, entities: solution.entities)
            } else {
                self.explanationLayout = WPArticleLayout(with: fakeContent, context: context, chatInteraction: chatInteraction, parent: object.message!, fontSize: theme.fontSize, presentation: wpPresentation, approximateSynchronousValue: false, downloadSettings: downloadSettings, autoplayMedia: object.autoplayMedia, theme: theme, mayCopyText: true, entities: solution.entities)
            }
        }

        var options: [PollOption] = []
        let anyOptionHasMedia = poll.options.contains(where: { $0.media != nil })

        var displayOptions = poll.options
        var displayIndices = Array(0..<poll.options.count)
        if poll.shuffleAnswers {
            var rng = SeededRandomNumberGenerator(seed: UInt64(bitPattern: poll.pollId.id))
            let shuffled = displayIndices.shuffled(using: &rng)
            displayOptions = shuffled.map { poll.options[$0] }
            displayIndices = shuffled
        }

        var votes:[Int] = []
        for option in displayOptions {
            let count = Int(poll.results.voters?.first(where: {$0.opaqueIdentifier == option.opaqueIdentifier})?.count ?? 0)
            votes.append(count)
        }

        let percents = countNicePercent(votes: votes, total: Int(poll.results.totalVoters ?? 0))
        let maximum: Int = percents.max() ?? 0

        let hideResults = poll.hideResultsUntilClose && !self.isClosed

        for (i, option) in displayOptions.enumerated() {

            let percent: Float?
            let realPercent: Float
            let isSelected: Bool
            let isCorrect: Bool?
            let voted = poll.results.voters?.first(where: {$0.selected}) != nil

            var votedCount: Int32 = 0
            var optionRecentVoters: [PeerId] = []
            if hideResults {
                if let vote = poll.results.voters?.first(where: {$0.opaqueIdentifier == option.opaqueIdentifier}) {
                    isSelected = vote.selected
                } else {
                    isSelected = false
                }
                percent = nil
                realPercent = 0
                isCorrect = nil
            } else if let vote = poll.results.voters?.first(where: {$0.opaqueIdentifier == option.opaqueIdentifier}), let totalVoters = poll.results.totalVoters, (voted || self.isClosed) {
                percent = maximum == 0 ? 0 : (Float(percents[i]) / Float(maximum))
                realPercent = totalVoters == 0 ? 0 : Float(percents[i])
                isSelected = vote.selected
                votedCount = vote.count ?? 0
                optionRecentVoters = vote.recentVoters
                if poll.isQuiz {
                    isCorrect = vote.isCorrect
                } else {
                   isCorrect = nil
                }
            } else {
                percent = poll.results.totalVoters == nil || poll.results.totalVoters == 0 ? (isClosed ? 0 : nil) : voted ? 0 : (isClosed ? 0 : nil)
                realPercent = 0
                isSelected = false
                isCorrect = nil
            }

            let nameFont: NSFont = .normal(.text)

            let optionText = NSMutableAttributedString()
            optionText.append(string: option.text, color: self.presentation.chat.textColor(isIncoming, renderType == .bubble), font: nameFont)
            InlineStickerItem.apply(to: optionText, associatedMedia: message?.associatedMedia ?? [:], entities: option.entities, isPremium: context.isPremium)

            let nameLayout = TextViewLayout(optionText, selectText: self.presentation.chat.selectText(isIncoming, renderType == .bubble), alwaysStaticItems: true, mayItems: canCopyText)
            nameLayout.interactions.copyAttributedString = LinkHooks.shared.globalLinkExecutor().copyAttributedString
            nameLayout.interactions.copy = { [weak self] in
                return self?.canCopyText != true
            }

            let wrapper = PollOption(option: option, nameText: nameLayout, percent: percent, realPercent: realPercent, voteCount: votedCount, isSelected: isSelected, isIncoming: isIncoming, isBubbled: renderType == .bubble, voted: voted, isLoading: object.additionalData.pollStateData.identifiers.contains(option.opaqueIdentifier) && object.additionalData.pollStateData.isLoading, presentation: self.presentation, isCorrect: isCorrect, isQuiz: poll.isQuiz, isMultipleSelected: object.additionalData.pollStateData.identifiers.contains(option.opaqueIdentifier), isMultipleChoice: poll.isMultiple, optionMedia: option.media, anyOptionHasMedia: anyOptionHasMedia, hideResults: hideResults && (voted || object.additionalData.pollStateData.isLoading), vote: { [weak self] control in
                self?.voteOption(option, for: control)
            }, isTranslateLoading: isTranslateLoading, recentVoters: optionRecentVoters)

            options.append(wrapper)
        }
        self.options = options
        

        let totalCount = poll.results.totalVoters ?? 0
        
        var totalText = poll.isQuiz ? strings().chatQuizTotalVotesOther(Int(totalCount)) : strings().chatPollTotalVotes1Other(Int(totalCount))
        totalText = totalText.replacingOccurrences(of: "\(totalCount)", with: Int(totalCount).separatedNumber)
        
        if actionButtonText == nil && !isBotQuiz {
            let text: String
            if totalCount > 0 {
                text = totalText
            } else {
                if poll.isQuiz {
                    text = self.isClosed ? strings().chatQuizTotalVotesResultEmpty : strings().chatQuizTotalVotesEmpty
                } else {
                    text = self.isClosed ? strings().chatPollTotalVotesResultEmpty : strings().chatPollTotalVotesEmpty
                }
            }
            self.totalVotesText = TextViewLayout(.initialize(string: text, color: self.presentation.chat.grayText(isIncoming, renderType == .bubble), font: .normal(12)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        } else {
            self.totalVotesText = nil
        }
        

        if let message = message, !message.text.isEmpty {
            let descAttr = ChatMessageItem.applyMessageEntities(with: message.attributes, for: message.text, message: message, context: context, fontSize: theme.fontSize, openInfo: { [weak chatInteraction] peerId, toChat, postId, action in
                chatInteraction?.openInfo(peerId, toChat, postId, action)
            }, botCommand: { [weak chatInteraction] command in
                chatInteraction?.sendPlainText(command)
            }, hashtag: { [weak chatInteraction] tag in
                chatInteraction?.hashtag(tag)
            }, applyProxy: { [weak chatInteraction] proxy in
                chatInteraction?.applyProxy(proxy)
            }, textColor: self.presentation.chat.textColor(isIncoming, renderType == .bubble), linkColor: self.presentation.chat.linkColor(isIncoming, renderType == .bubble), openBank: { [weak chatInteraction] bank in
                chatInteraction?.openBank(bank)
            }, isDark: theme.colors.isDark, bubbled: renderType == .bubble, openPhoneNumber: { [weak chatInteraction] phone in
                chatInteraction?.openPhoneNumberContextMenu(phone)
            }, openTonAddress: { [weak chatInteraction] address in
                chatInteraction?.openTonAddressContextMenu(address)
            }, ignoreLinks: !object.additionalData.canHighlightLinks && isIncoming).mutableCopy() as! NSMutableAttributedString
            let layout = TextViewLayout(descAttr, selectText: self.presentation.chat.selectText(isIncoming, renderType == .bubble), strokeLinks: renderType == .bubble, alwaysStaticItems: true, disableTooltips: false, mayItems: canCopyText)
            layout.interactions = LinkHooks.shared.globalLinkExecutor()
            layout.interactions.copy = { [weak self] in
                return self?.canCopyText != true
            }
            layout.interactions.topWindow = { [weak self] in
                return self?.menuAdditionView ?? .single(nil)
            }
            layout.interactions.menuItems = { [weak self] type in
                if let strongSelf = self, let message = strongSelf.message {
                    return chatMenuItems(for: message, entry: strongSelf.entry, textLayout: (strongSelf.descriptionText, type), chatInteraction: strongSelf.chatInteraction)
                }
                return .complete()
            }
            let processURL = layout.interactions.processURL
            let makeLinkType = layout.interactions.makeLinkType
            layout.interactions.processURL = { [weak self] link in
                if case .code = makeLinkType((link, "")), self?.canCopyText != true {
                    return
                }
                processURL(link)
            }
            self.descriptionText = layout
        }

        let titleAttr = NSMutableAttributedString()
        titleAttr.append(string: poll.text, color: self.presentation.chat.textColor(isIncoming, renderType == .bubble), font: .medium(.text))

        InlineStickerItem.apply(to: titleAttr, associatedMedia: message?.associatedMedia ?? [:], entities: poll.textEntities, isPremium: context.isPremium)


        self.titleText = TextViewLayout(titleAttr, selectText: self.presentation.chat.selectText(isIncoming, renderType == .bubble), alwaysStaticItems: true, mayItems: canCopyText)
        self.titleText.interactions.copyAttributedString = LinkHooks.shared.globalLinkExecutor().copyAttributedString
        self.titleText.interactions.copy = { [weak self] in
            return self?.canCopyText != true
        }
        
        
        let typeText: String = self.isBotQuiz ? strings().chatQuizTextType : poll.title
        
        self.titleTypeText = TextViewLayout(.initialize(string: typeText, color: self.presentation.chat.grayText(isIncoming, renderType == .bubble), font: .normal(12)), maximumNumberOfLines: 1, alwaysStaticItems: true)

        if isBubbleFullFilled {
            var positionFlags: LayoutPositionFlags = []
            if !hasUpsideSomething {
                positionFlags.insert(.top)
                positionFlags.insert(.left)
                positionFlags.insert(.right)
            }
            self.positionFlags = positionFlags
        }
    }
    
    public override var isForceRightLine: Bool {
        var size: NSSize = .zero
        if let action = self.actionButtonText {
            size = TextButton.size(with: action, font: .normal(.text))
        } else if let totalVotesText = self.totalVotesText {
            size = totalVotesText.layoutSize
        }
        
        if size.width > 0 {
            let dif = contentSize.width - (contentSize.width / 2 + size.width / 2)
            if dif < (rightSize.width + insetBetweenContentAndDate) {
                return true
            }
            
        }
        
        if isBotQuiz {
            return true
        }
        return super.isForceRightLine
    }
    
        
    private func voteOption(_ option: TelegramMediaPollOption, for control: Control) {
        if canInvokeVote, !self.options.contains(where: { $0.isSelected }) {
            guard let message = message else { return }
            var identifiers = self.entry.additionalData.pollStateData.identifiers
            if let index = identifiers.firstIndex(of: option.opaqueIdentifier) {
                identifiers.remove(at: index)
            } else {
                identifiers.append(option.opaqueIdentifier)
            }
            chatInteraction.vote(message.id, identifiers, !self.poll.isMultiple)
        } else if poll.hideResultsUntilClose && !isClosed && self.options.contains(where: { $0.isSelected }) {
            showModalText(for: context.window, text: strings().chatPollResultsAfterEnd)
        } else {
            if self.options.contains(where: { $0.isSelected }) || self.isClosed, self.poll.publicity == .public {
                guard let message = message else {
                    return
                }
                if message.flags.contains(.Failed) || message.flags.contains(.Unsent) || message.flags.contains(.Sending) || self.options.contains(where: { $0.isLoading }) {
                    return
                }
                self.invokeAction(fromOption: option.opaqueIdentifier)
            }
        }
    }

    
    private var canInvokeVote: Bool {
        guard let message = message else {
            return false
        }
        if message.flags.contains(.Failed) || message.flags.contains(.Unsent) || message.flags.contains(.Sending) {
            return false
        }
        if self.isClosed {
            return false
        }
        if self.options.contains(where: { $0.isLoading }) {
            return false
        }
        
        return true
    }
    
    fileprivate func invokeAction(fromOption: Data? = nil) {
        
        guard let message = message else { return }
        let hasSelected = self.options.contains(where: { $0.isSelected })
        if canInvokeVote, !hasSelected {
            let identifiers = self.entry.additionalData.pollStateData.identifiers
            chatInteraction.vote(message.id, identifiers, true)
        } else {
            if !isBotQuiz, let totalVoters = self.poll.results.totalVoters, totalVoters > 0 {
                ChatNavigationHooks.shared.showPollResult(context, message, fromOption, context.window)
            }
        }
    }
    
    public override func viewClass() -> AnyClass {
        return ChatPollItemView.self
    }
    
    public override var instantlyResize: Bool {
        return true
    }

    private func optionsOffset() -> CGFloat {
        var offset: CGFloat = 0
        if attachedMedia != nil {
            offset += attachedMediaSize.height + defaultContentInnerInset
        }
        if let descriptionText = descriptionText {
            offset += descriptionText.layoutSize.height + defaultContentInnerInset
        }
        offset += titleText.layoutSize.height + defaultContentInnerInset
        offset += titleTypeText.layoutSize.height + defaultContentInnerInset
        return offset
    }

    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        if let message = message, !context.isFrozen {
            let source: ChatMenuItemSource
            let offset = optionsOffset()
            var y = offset
            var foundIndex: Int?
            for (i, option) in options.enumerated() {
                let optionY = y - (i > 0 ? PollOption.spaceBetweenOptions : 0)
                let rect = NSMakeRect(0, optionY, contentSize.width, option.contentSize.height)
                if NSPointInRect(location, rect) {
                    foundIndex = i
                    break
                }
                y += option.contentSize.height
                if i != options.count - 1 {
                    y += PollOption.spaceBetweenOptions
                }
            }
            if let index = foundIndex {
                source = .pollOption(opaqueIdentifier: options[index].option.opaqueIdentifier)
            } else {
                source = .general
            }
            return chatMenuItems(for: message, entry: entry, textLayout: foundIndex == nil ? ((view as? ChatPollItemView)?.menuTextLayout(at: location), nil) : nil, chatInteraction: chatInteraction, source: source)
        }
        return super.menuItems(in: location)
    }

    public override func makeContentSize(_ width: CGFloat) -> NSSize {

        let width = min(width, 300)
        let textWidth = width


        var rightInset: CGFloat = 0

        if let _ = poll.results.solution, options.contains(where: { $0.isSelected }) || self.isClosed {
            rightInset += 10
        }
        _ = poll.deadlineTimeout
        _ = !options.contains(where: { $0.isSelected })



        if let media = attachedMedia {
            let mediaWidth = isBubbleFullFilled ? width : textWidth
            var mediaSize = ChatLayoutUtils.contentSize(for: media, with: mediaWidth)
            if ChatLayoutUtils.contentNode(for: media) == ChatInteractiveContentView.self {
                mediaSize = NSMakeSize(mediaWidth, min(mediaSize.height, 150))
            }
            if let fileParams = mediaParameters as? ChatFileLayoutParameters {
                let optionalWidth = fileParams.makeLabelsForWidth(mediaWidth - bubbleContentInset)
                mediaSize.width = max(mediaSize.width, optionalWidth)
            }
            self.attachedMediaSize = mediaSize
        }
        descriptionText?.measure(width: textWidth - bubbleContentInset - rightInset)
        titleText.measure(width: textWidth - bubbleContentInset - rightInset)
        titleTypeText.measure(width: textWidth - bubbleContentInset - rightInset)
        totalVotesText?.measure(width: textWidth - bubbleContentInset)

        if isTranslateLoading {
            titleText.maskBlockImage = titleText.generateBlock(backgroundColor: .blackTransparent)
        }

        var maxOptionNameWidth: CGFloat = 0
        for (i, option) in options.enumerated() {
            let size = option.measure(width: textWidth)
            self.options[i] = option.withUpdatedContentSize(size)
            if maxOptionNameWidth < size.width {
                maxOptionNameWidth = size.width
            }
        }


        var contentWidth:CGFloat = max(max(maxOptionNameWidth, titleText.layoutSize.width), titleTypeText.layoutSize.width)
        if let descriptionText = descriptionText {
            contentWidth = max(contentWidth, descriptionText.layoutSize.width)
        }
        if attachedMedia != nil {
            contentWidth = max(contentWidth, attachedMediaSize.width)
        }

        var contentHeight: CGFloat = 0

        if let explanationLayout = explanationLayout {
            explanationLayout.measure(width: width - defaultContentInnerInset * 2)
            contentHeight += explanationLayout.size.height + defaultContentInnerInset
        }

        if attachedMedia != nil {
            contentHeight += attachedMediaSize.height + defaultContentInnerInset
        }
        if let descriptionText = descriptionText {
            contentHeight += descriptionText.layoutSize.height + defaultContentInnerInset
        }
        contentHeight += titleText.layoutSize.height + defaultContentInnerInset
        contentHeight += titleTypeText.layoutSize.height + defaultContentInnerInset
        contentHeight += options.reduce(0, { $0 + $1.contentSize.height }) + (CGFloat(options.count - 1) * PollOption.spaceBetweenOptions)

        if canAddOption {
            let addOptionHeight = options.first?.contentSize.height ?? 33
            contentHeight += addOptionHeight
        }

        if let totalVotesText = totalVotesText {
            contentHeight += defaultContentInnerInset
            contentHeight += totalVotesText.layoutSize.height
        }
        if showResultsIn {
            contentHeight += 16
        }
        if let _ = self.actionButtonText {
            contentHeight += defaultContentInnerInset
            contentHeight += 15
        }

        return NSMakeSize(max(textWidth, contentWidth), contentHeight)
    }
    
}


public final class ChatPollItemView : ChatRowView {
    private var contentNode:PollView = PollView(frame: NSZeroRect)
    fileprivate var galleryIndexToOptionIndex: [Int: Int] = [:]
    fileprivate var attachedMediaGalleryIndex: Int?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(contentNode)
    }
    
    
    public override func contentFrameModifier(_ item: ChatRowItem) -> NSRect {
        return bubbleFilledContentFrame(item, base: super.contentFrameModifier(item))
    }
    
    
    public func doAfterAnswer() {
        guard let item = item as? ChatPollItem else { return }

        let selected = item.options.first(where: { $0.isSelected })
        
        if let selected = selected {
            if item.poll.isQuiz {
                if let isCorrect = selected.isCorrect {
                    if isCorrect {
                        doWhenCorrectAnswer()
                    } else {
                       doWhenIncorrectAnswer()
                    }
                }
            }
        }
    }
    
    public func doWhenCorrectAnswer() {
        guard let item = item as? ChatPollItem else { return }
        PlayConfetti(for: item.context.window)
        if FastSettings.inAppSounds {
            playSoundEffect(.confetti)
        }
    }
    public func doWhenIncorrectAnswer() {
        shakeContentView()
        
        if FastSettings.inAppSounds {
            NSSound.beep()
        }
        self.contentNode.showSolution()
    }
    
    private func optionHighlight(for optionView: PollOptionView, item: ChatPollItem) -> (color: NSColor, frame: NSRect, superview: NSView) {
        let hasVoted = item.options.contains(where: { $0.isSelected })
        if item.hasBubble {
            let converted = optionView.convert(optionView.bounds, to: self.bubbleView)
            var frame = NSMakeRect(0, converted.origin.y, self.bubbleFrame(item).width, converted.height)
            if hasVoted {
                frame.origin.y -= 4
            }
            let color = item.isIncoming ? item.presentation.colors.bubbleBackground_incoming.darker().withAlphaComponent(0.5) : item.presentation.colors.blendedOutgoingColors.darker().withAlphaComponent(0.5)
            return (color, frame, self.bubbleView)
        } else {
            let converted = optionView.convert(optionView.bounds, to: self.rowView)
            var frame = NSMakeRect(0, converted.origin.y, self.frame.width, converted.height)
            if hasVoted {
                frame.origin.y -= 4
            }
            let color = item.presentation.colors.accentIcon.withAlphaComponent(0.15)
            return (color, frame, self.rowView)
        }
    }

    public override func focusAnimation(_ innerId: AnyHashable?, text: String?) {
        if let data = innerId?.base as? Data {
            guard let item = item as? ChatPollItem else { return }
            guard let optionIndex = item.options.firstIndex(where: { $0.option.opaqueIdentifier == data }) else {
                super.focusAnimation(innerId, text: text)
                return
            }
            guard optionIndex < contentNode.options.count else { return }

            let data = optionHighlight(for: contentNode.options[optionIndex], item: item)
            let bg = CornerView()
            bg.isDynamicColorUpdateLocked = true
            bg.frame = data.frame
            bg.backgroundColor = data.color
            data.superview.addSubview(bg)

            let animation: CABasicAnimation = makeSpringAnimation("opacity")
            animation.fromValue = 0
            animation.toValue = 1
            animation.duration = 0.5
            animation.isRemovedOnCompletion = false
            animation.delegate = CALayerAnimationDelegate(completion: { [weak bg] completed in
                if let bg = bg {
                    performSubviewRemoval(bg, animated: true, duration: 0.35, timingFunction: .spring)
                }
            })
            bg.layer?.add(animation, forKey: "opacity")
        } else {
            super.focusAnimation(innerId, text: text)
        }
    }

    private var selectionBackground: CornerView?

    public override func onShowContextMenu() {
        guard let window = window as? Window else { return }
        guard let item = item as? ChatPollItem else { return }

        let point = contentNode.optionsContainerView.convert(window.mouseLocationOutsideOfEventStream, from: nil)

        if let selectionBackground = selectionBackground {
            performSubviewRemoval(selectionBackground, animated: true)
            self.selectionBackground = nil
        }

        var selected = false
        for i in 0 ..< contentNode.options.count {
            let optionView = contentNode.options[i]
            if NSPointInRect(point, optionView.frame) {
                let highlight = optionHighlight(for: optionView, item: item)
                let bg = CornerView()
                bg.isDynamicColorUpdateLocked = true
                bg.frame = highlight.frame
                bg.backgroundColor = highlight.color
                highlight.superview.addSubview(bg)
                self.selectionBackground = bg
                bg.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)

                selected = true
                break
            }
        }

        if !selected {
            super.onShowContextMenu()
        }
    }

    public override func onCloseContextMenu() {
        super.onCloseContextMenu()
        if let selectionBackground = selectionBackground {
            performSubviewRemoval(selectionBackground, animated: true)
            self.selectionBackground = nil
        }
    }

    public override func set(item: TableRowItem, animated: Bool) {

        guard let item = item as? ChatPollItem else { return }
        super.set(item: item, animated: animated)

        contentNode.change(size: NSMakeSize(contentFrameModifier(item).width, item.contentSize.height), animated: animated)
        contentNode.update(with: item, animated: animated)
        updateTextSelection(updatePermissions: true)

        contentNode.updateLayout(item: item, size: contentNode.frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }
        
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool) -> NSView {
        if let stableId = innerId.base as? ChatHistoryEntryId {
            switch stableId {
            case let .mediaId(index, _):
                if let galleryIdx = index.base as? Int {
                    if galleryIdx == attachedMediaGalleryIndex, let mediaView = contentNode.mediaContentView {
                        return mediaView
                    }
                    if let optionIdx = galleryIndexToOptionIndex[galleryIdx], optionIdx < contentNode.options.count {
                        if let mediaView = contentNode.options[optionIdx].optionMediaView {
                            return mediaView
                        }
                    }
                }
            default:
                return contentNode.mediaContentView?.interactionContentView(for: innerId, animateIn: animateIn) ?? self.contentNode.explanationView?.interactionContentView(for: innerId, animateIn: animateIn) ?? contentView
            }
        }
        return contentView
    }
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    

    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func notify(with value: Any, oldValue: Any, animated: Bool) {
        super.notify(with: value, oldValue: oldValue, animated: animated)
        updateTextSelection()
    }

    private func updateTextSelection(updatePermissions: Bool = false) {
        guard let item = item as? ChatPollItem else { return }
        let canCopy = item.canCopyText
        if !canCopy, selectManager.find(item.stableId) != nil {
            selectManager.removeAll()
        }
        var views: [TextView] = [contentNode.titleView.textView] + contentNode.options.map { $0.nameView.textView }
        if let descriptionView = contentNode.descriptionView {
            views.append(descriptionView)
        }
        for view in views {
            if updatePermissions || view.textLayout?.mayItems != canCopy {
                view.isSelectable = canCopy
                view.textLayout?.mayItems = canCopy
            }
            if !canCopy, let layout = view.textLayout, layout.selectedRange.range.location != NSNotFound || !layout.additionalSelections.isEmpty {
                layout.clearSelect()
                layout.additionalSelections = []
                view.needsDisplay = true
            }
        }
    }

    func menuTextLayout(at location: NSPoint) -> TextViewLayout? {
        let views: [TextView] = [contentNode.titleView.textView] + [contentNode.descriptionView].compactMap { $0 }
        for view in views {
            let point = view.convert(location, from: contentView)
            if view.bounds.contains(point) {
                return view.textLayout
            }
        }
        return nil
    }

    public override func canStartTextSelecting(_ event: NSEvent) -> Bool {
        for view in selectableTextViews {
            let point = view.convert(event.locationInWindow, from: nil)
            if NSPointInRect(point, view.bounds) {
                return true
            }
        }
        return false
    }

    override var textSelectionSources: ChatTextSelectionSources {
        return .views(selectableTextViews)
    }

    public override var selectableTextViews: [TextView] {
        guard let item = item as? ChatPollItem, item.canCopyText else {
            return []
        }
        var views: [TextView] = [contentNode.titleView.textView]
        if let descriptionView = contentNode.descriptionView {
            views.append(descriptionView)
        }
        for option in contentNode.options {
            views.append(option.nameView.textView)
        }
        return views
    }
    
    public override func canMultiselectTextIn(_ location: NSPoint) -> Bool {
        return true
    }
    
    public override var needsDisplay: Bool {
        get {
            return super.needsDisplay
        }
        set {
            super.needsDisplay = true
            contentNode.needsDisplay = true
        }
    }
    
    public override var backgroundColor: NSColor {
        didSet {
            
            contentNode.backgroundColor = .clear//contentColor
        }
    }
    
    public override func shakeView() {
        contentNode.shake()
    }
    
    
    public override func updateColors() {
        super.updateColors()
         contentNode.backgroundColor = .clear//contentColor
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let item = item as? ChatPollItem else {
            return
        }
        contentNode.updateLayout(item: item, size: contentNode.frame.size, transition: transition)
    }

}


private final class PollOptionView : Control {
    private var percentView: ImageView?
    fileprivate let nameView: InteractiveTextView = InteractiveTextView(frame: .zero)
    private var selectingView:ImageView?
    private let progressBackgroundView: View = View(frame: NSZeroRect)
    private let progressView: LinearProgressControl = LinearProgressControl(progressHeight: 5)
    private var progressIndicator: ProgressIndicator?
    private let borderView: View = View(frame: NSZeroRect)
    private var optionAvatarsView: MergedAvatarsView?
    private var voteCountView: TextView?
    fileprivate var optionMediaView: TransformImageView?
    private var optionStickerView: InlineStickerView?
    private var optionMediaOverlay: Control?

    private var selectedImageView: ImageView?

    private var startMouseDownPoint: NSPoint?
    private var didDrag: Bool = false

    override func mouseDown(with event: NSEvent) {
        startMouseDownPoint = event.locationInWindow
        didDrag = false
        if !event.modifierFlags.contains(.control) {
            selectManager.removeAll()
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let start = startMouseDownPoint {
            if chatTextSelectionDidDrag(from: start, to: event.locationInWindow) {
                didDrag = true
            }
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let start = startMouseDownPoint {
            if chatTextSelectionDidDrag(from: start, to: event.locationInWindow) {
                didDrag = true
            }
        }
        defer {
            startMouseDownPoint = nil
            didDrag = false
        }
        super.mouseUp(with: event)
    }

    override func accessibilityPerformPress() -> Bool {
        startMouseDownPoint = nil
        didDrag = false
        return super.accessibilityPerformPress()
    }

    private var option: PollOption?
    private weak var pollItem: ChatPollItem?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameView.userInteractionEnabled = false
        nameView.textView.isSelectable = true
        progressView.hasMinumimVisibility = true
        progressBackgroundView.layer?.cornerRadius = 2.5
        addSubview(nameView)
        addSubview(progressBackgroundView)
        addSubview(progressView)
        addSubview(borderView)
        borderView.userInteractionEnabled = false
        progressView.userInteractionEnabled = false
        progressBackgroundView.userInteractionEnabled = false
        progressView.roundCorners = true

        layer?.masksToBounds = false

        progressView.isEventLess = true
        progressBackgroundView.isEventLess = true

        set(handler: { [weak self] control in
            guard let self = self else { return }
            if self.startMouseDownPoint != nil && (self.didDrag || !selectManager.isEmpty) {
                return
            }
            self.option?.vote(control)
        }, for: .Click)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func currentProgressY() -> CGFloat {
        return frame.height - progressView.progressHeight
    }

    private func currentProgressFrame() -> NSRect {
        guard let option = self.option else { return .zero }
        let progressRightInset: CGFloat = option.anyOptionHasMedia ? PollOption.mediaSize + 8 + defaultInset : defaultInset
        let progressWidth = frame.width - option.leftOptionInset - progressRightInset
        return NSMakeRect(option.leftOptionInset, currentProgressY(), progressWidth, progressView.progressHeight)
    }
    
    var defaultInset: CGFloat {
        return 13
    }
    
    func update(with option: PollOption, context: any AccountContextProtocol, animated: Bool, item: ChatPollItem? = nil, message: Message? = nil, optionIndex: Int = 0) {
        let animated = animated && self.option != option
        let previousOption = self.option
        self.pollItem = item

        let previousPercent = self.option?.realPercent

        self.option = option

                
        let duration: Double = 0.4
        let timingFunction: CAMediaTimingFunctionName = .spring
        
        nameView.set(text: option.nameText, context: context)

        nameView.textView.setIsShimmering(option.isTranslateLoading, animated: animated)

        borderView.backgroundColor = option.presentation.chat.pollOptionBorder(option.isIncoming, option.isBubbled)
        borderView.change(opacity: option.percent != nil ? 0 : 1, animated: animated, duration: duration, timingFunction: timingFunction)
        progressView.change(opacity: option.percent == nil ? 0 : 1, animated: animated, duration: duration, timingFunction: timingFunction)
        progressBackgroundView.change(opacity: option.percent == nil ? 0 : 1, animated: animated, duration: duration, timingFunction: timingFunction)

        let votedColor: NSColor
        
        
        if option.isSelected && !option.hideResults {
            let current: ImageView
            var justAdded = false
            if let view = self.selectedImageView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.selectedImageView = current
                addSubview(current)
                justAdded = true
            }

            if option.isQuiz, let isCorrect = option.isCorrect {
                current.image = isCorrect ? option.presentation.chat.pollSelectedCorrect(option.isIncoming, option.isBubbled, icons: option.presentation.icons) : option.presentation.chat.pollSelectedIncorrect(option.isIncoming, option.isBubbled, icons: option.presentation.icons)
            } else {
                current.image = option.isMultipleChoice ? option.presentation.chat.pollSquareSelected(option.isIncoming, option.isBubbled, icons: option.presentation.icons) : option.presentation.chat.pollSelected(option.isIncoming, option.isBubbled, icons: option.presentation.icons)
            }
            current.setFrameSize(NSMakeSize(12, 12))
            if justAdded {
                let pf = currentProgressFrame()
                current.setFrameOrigin(NSMakePoint(pf.minX - 12 - 4, floorToScreenPixels(backingScaleFactor, pf.midY - 6)))
            }

            if justAdded && animated {
                current.layer?.animateScaleSpring(from: 0.2, to: 1.0, duration: duration)
                current.layer?.animateAlpha(from: 0, to: 1, duration: duration, timingFunction: timingFunction)
            }
        } else {
            if option.isQuiz, let isCorrect = option.isCorrect, isCorrect {
                let current: ImageView
                var justAdded = false
                if let view = self.selectedImageView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    self.selectedImageView = current
                    addSubview(current)
                    justAdded = true
                }

                current.image = option.isMultipleChoice ? option.presentation.chat.pollSquareSelected(option.isIncoming, option.isBubbled, icons: option.presentation.icons) : option.presentation.chat.pollSelected(option.isIncoming, option.isBubbled, icons: option.presentation.icons)
                current.setFrameSize(NSMakeSize(12, 12))
                if justAdded {
                    let pf = currentProgressFrame()
                    current.setFrameOrigin(NSMakePoint(pf.minX - 12 - 4, floorToScreenPixels(backingScaleFactor, pf.midY - 6)))
                }

                if justAdded && animated {
                    current.layer?.animateScaleSpring(from: 0.2, to: 1.0, duration: duration)
                    current.layer?.animateAlpha(from: 0, to: 1, duration: duration, timingFunction: timingFunction)
                }

            } else {
                if let view = self.selectedImageView {
                    self.selectedImageView = nil
                    if animated {
                        view.layer?.animateScaleSpring(from: 1, to: 0.2, duration: duration, removeOnCompletion: false)
                    }
                    performSubviewRemoval(view, animated: animated, duration: duration)
                }
            }
            
            
            
        }
        
        if option.isSelected, let isCorrect = option.isCorrect {
            votedColor = isCorrect ? option.presentation.chat.greenUI(option.isIncoming, option.isBubbled) : option.presentation.chat.redUI(option.isIncoming, option.isBubbled)
        } else {
            votedColor = option.presentation.chat.activityColor(option.isIncoming, option.isBubbled)
        }
        progressView.style = ControlStyle(foregroundColor: votedColor, backgroundColor: .clear)
        if !option.isIncoming && option.isBubbled {
            progressBackgroundView.background = votedColor.withAlphaComponent(0.2)
        } else {
            progressBackgroundView.background = option.presentation.chat.grayText(option.isIncoming, option.isBubbled).withAlphaComponent(0.2)
        }

        if let progress = option.percent {
            progressView.set(progress: CGFloat(progress), animated: animated, duration: duration / 2, timingFunction: .spring, bounce: true)
            
            let current: ImageView
            if let view = percentView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                percentView = current
                addSubview(current)
                current.setFrameSize(36, 16)
                current.setFrameOrigin(NSMakePoint(option.leftOptionInset - 36 - PollOption.spaceBetweenTexts, nameView.frame.minY + 1))
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: duration / 2)
                }
            }

            current.animates = animated
            current.image = option.currentPercentImage
            current.setFrameSize(36, 16)
            
            if previousPercent != option.realPercent, animated {
                let images = option.presentation.chat.pollPercentAnimatedIcons(option.isIncoming, option.isBubbled, from: CGFloat(previousPercent ?? 0), to: CGFloat(option.realPercent), duration: duration / 2)
                if !images.isEmpty {
                    let animation = CAKeyframeAnimation(keyPath: "contents")
                    animation.values = images
                    animation.duration = duration / 2
                    animation.calculationMode = .discrete
                    percentView?.layer?.add(animation, forKey: "image")
                }
                
            }
            
            if let view = selectingView {
                self.selectingView = nil
                performSubviewRemoval(view, animated: animated, duration: duration / 2)
            }
            if let view = progressIndicator {
                self.progressIndicator = nil
                performSubviewRemoval(view, animated: animated, duration: duration / 2)
            }
        } else {
            toolTip = nil
            if let view = self.percentView {
                self.percentView = nil
                if animated, previousPercent != 0 {
                    let images = option.presentation.chat.pollPercentAnimatedIcons(option.isIncoming, option.isBubbled, from: CGFloat(previousPercent ?? 0), to: CGFloat(0), duration: duration / 2)
                    if !images.isEmpty {
                        let animation = CAKeyframeAnimation(keyPath: "contents")
                        animation.values = images
                        animation.duration = duration / 2
                        animation.calculationMode = .discrete
                        view.layer?.add(animation, forKey: "image")
                    }
                }
                performSubviewRemoval(view, animated: animated, duration: duration / 2)
            }
            
            progressView.set(progress: 0, animated: animated)
            
            if option.isLoading {
                if let view = selectingView {
                    self.selectingView = nil
                    performSubviewRemoval(view, animated: animated, duration: duration / 2)
                }
                let pi: ProgressIndicator
                if let view = progressIndicator {
                    pi = view
                } else {
                    let piSize: CGFloat = option.hideResults ? 18 : 18
                    let piOrigin: NSPoint = NSMakePoint(defaultInset, floorToScreenPixels((option.contentSize.height - piSize) / 2))
                    pi = ProgressIndicator(frame: NSMakeRect(piOrigin.x, piOrigin.y, piSize, piSize))
                    progressIndicator = pi
                    addSubview(pi)
                    if animated {
                        pi.layer?.animateAlpha(from: 0, to: 1, duration: duration / 2)
                    }
                }
                pi.progressColor = option.presentation.chat.activityColor(option.isIncoming, option.isBubbled)

            } else if option.hideResults {
                if let view = progressIndicator {
                    self.progressIndicator = nil
                    performSubviewRemoval(view, animated: animated, duration: duration / 2)
                }
                if option.isSelected {
                    let sv: ImageView
                    var isNew: Bool = false
                    if let view = selectingView {
                        sv = view
                    } else {
                        sv = ImageView(frame: NSMakeRect(0, 0, 22, 22))
                        selectingView = sv
                        sv.isAccessibilityDecorative = true
                        addSubview(sv)
                        isNew = true
                    }
                    sv.image = option.isMultipleChoice ? option.presentation.chat.pollSquareSelection(option.isIncoming, option.isBubbled, icons: option.presentation.icons) : option.presentation.chat.pollSelection(option.isIncoming, option.isBubbled, icons: option.presentation.icons)
                    sv.sizeToFit()
                    
                    if isNew {
                        sv.centerY(x: defaultInset)
                        if animated {
                            sv.layer?.animateAlpha(from: 0, to: 1, duration: duration / 2)
                        }
                    }
                } else {
                    if let view = selectingView {
                        self.selectingView = nil
                        performSubviewRemoval(view, animated: animated, duration: duration / 2)
                    }
                }
            } else {
                if let view = progressIndicator {
                    self.progressIndicator = nil
                    performSubviewRemoval(view, animated: animated, duration: duration / 2)
                }

                let sv: ImageView
                var isNew: Bool = false
                if let view = selectingView {
                    sv = view
                } else {
                    sv = ImageView(frame: NSMakeRect(0, 0, 22, 22))
                    selectingView = sv
                        sv.isAccessibilityDecorative = true
                    addSubview(sv)
                    isNew = true
                }
                sv.animates = animated || (previousOption != nil && previousOption?.isMultipleSelected != option.isMultipleSelected)
                if option.isMultipleSelected {
                    sv.image = option.isMultipleChoice ? option.presentation.chat.pollSquareSelection(option.isIncoming, option.isBubbled, icons: option.presentation.icons) : option.presentation.chat.pollSelection(option.isIncoming, option.isBubbled, icons: option.presentation.icons)
                } else {
                    sv.image = option.isMultipleChoice ? option.presentation.chat.pollSquareUnselected(option.isIncoming, option.isBubbled) : option.presentation.chat.pollOptionUnselectedImage(option.isIncoming, option.isBubbled)
                }
                sv.sizeToFit()
                
                if isNew {
                    sv.centerY(x: defaultInset)
                    if animated {
                        sv.layer?.animateAlpha(from: 0, to: 1, duration: duration / 2)
                    }
                }
            }

        }

        if let message = message, !option.recentVoters.isEmpty {
            var avatarPeers: [Peer] = []
            for peerId in option.recentVoters {
                if let peer = message.peers[peerId] {
                    avatarPeers.append(peer)
                }
            }
            if !avatarPeers.isEmpty {
                var isNew = false
                if self.optionAvatarsView == nil {
                    self.optionAvatarsView = MergedAvatarsView()
                    addSubview(self.optionAvatarsView!)
                    isNew = true
                }
                if let avatarsView = self.optionAvatarsView {
                    let avatarWidth = avatarsView.mergedImageSpacing * CGFloat(avatarPeers.count) + 2
                    avatarsView.setFrameSize(NSMakeSize(avatarWidth, avatarsView.mergedImageSize))
                    avatarsView.update(context: context, peers: avatarPeers, message: message, synchronousLoad: false)
                    if isNew {
                        var re = frame.width - defaultInset
                        if option.anyOptionHasMedia {
                            re -= PollOption.mediaSize + 8
                        }
                        avatarsView.setFrameOrigin(NSMakePoint(re - avatarWidth, floorToScreenPixels(backingScaleFactor, (frame.height - PollOption.spaceBetweenOptions - avatarsView.frame.height) / 2)))
                    }
                }
            } else {
                self.optionAvatarsView?.removeFromSuperview()
                self.optionAvatarsView = nil
            }
        } else {
            self.optionAvatarsView?.removeFromSuperview()
            self.optionAvatarsView = nil
        }

        if let voteCountText = option.voteCountText {
            var isNew = false
            if self.voteCountView == nil {
                self.voteCountView = TextView()
                self.voteCountView!.userInteractionEnabled = false
                self.voteCountView!.isSelectable = false
                addSubview(self.voteCountView!)
                isNew = true
            }
            self.voteCountView?.update(voteCountText)
            if isNew {
                var re = frame.width - defaultInset
                if option.anyOptionHasMedia {
                    re -= PollOption.mediaSize + 8
                }
                if let avatarsView = self.optionAvatarsView {
                    re -= avatarsView.frame.width + 4
                }
                let voteCountX = min(progressView.frame.maxX, re) - voteCountText.layoutSize.width
                let voteCountY = floorToScreenPixels(backingScaleFactor, (frame.height - PollOption.spaceBetweenOptions - voteCountText.layoutSize.height) / 2) + 3
                self.voteCountView?.setFrameOrigin(NSMakePoint(voteCountX, voteCountY))
            }
        } else {
            self.voteCountView?.removeFromSuperview()
            self.voteCountView = nil
        }

        if let media = option.optionMedia {
            let boundingSize = NSMakeSize(PollOption.mediaSize, PollOption.mediaSize)
            let mediaX = frame.width - boundingSize.width - defaultInset
            let mediaY = floorToScreenPixels(backingScaleFactor, (frame.height - PollOption.spaceBetweenOptions - boundingSize.height) / 2) 
            let isSticker = (media as? TelegramMediaFile).map { $0.isSticker || $0.isAnimatedSticker || $0.isVideoSticker } ?? false

            if isSticker {
                if self.optionMediaView != nil {
                    self.optionMediaView?.removeFromSuperview()
                    self.optionMediaView = nil
                }
                self.optionStickerView?.removeFromSuperview()
                let stickerView = InlineStickerView(account: context.account, file: media as! TelegramMediaFile, size: boundingSize)
                stickerView.frame = NSMakeRect(mediaX, mediaY, boundingSize.width, boundingSize.height)
                self.optionStickerView = stickerView
                addSubview(stickerView)
            } else {
                if self.optionStickerView != nil {
                    self.optionStickerView?.removeFromSuperview()
                    self.optionStickerView = nil
                }
                if self.optionMediaView == nil {
                    self.optionMediaView = TransformImageView(frame: NSMakeRect(mediaX, mediaY, boundingSize.width, boundingSize.height))
                    addSubview(self.optionMediaView!)
                }
                self.optionMediaView?.setFrameSize(boundingSize)
                updateMediaSignal(media: media, mediaView: self.optionMediaView!, boundingSize: boundingSize, context: context, message: message)
            }

            if self.optionMediaOverlay == nil {
                self.optionMediaOverlay = Control(frame: NSMakeRect(mediaX, mediaY, boundingSize.width, boundingSize.height))
                self.optionMediaOverlay?.setAccessibilityLabel(strings().voiceOverCommonOpen)
                addSubview(self.optionMediaOverlay!)
            }
            self.optionMediaOverlay?.removeAllHandlers()
            self.optionMediaOverlay?.set(handler: { [weak self] _ in
                self?.openOptionMedia(context: context, item: item, message: message, optionIndex: optionIndex)
            }, for: .Click)
        } else {
            self.optionMediaView?.removeFromSuperview()
            self.optionMediaView = nil
            self.optionStickerView?.removeFromSuperview()
            self.optionStickerView = nil
            self.optionMediaOverlay?.removeFromSuperview()
            self.optionMediaOverlay = nil
            self.videoPlayIcon?.removeFromSuperview()
            self.videoPlayIcon = nil
        }
        
        self.updateLayout(size: self.frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        
    }

    private func openOptionMedia(context: any AccountContextProtocol, item: ChatPollItem?, message: Message?, optionIndex: Int) {
        guard let media = self.option?.optionMedia, let message = message else { return }
        if let file = media as? TelegramMediaFile {
            if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
                if let table = findTable(), let window = window as? Window {
                    startModalPreviewHandle(table, window: window, context: context)
                }
            } else if file.isGraphicFile || file.isVideoFile {
                openGalleryForOption(context: context, item: item, message: message, optionIndex: optionIndex)
            } else {
                ChatMediaUIHooks.shared.showQuickLookPreview(context, file, message.chatStableId, nil)
            }
        } else if media is TelegramMediaImage {
            openGalleryForOption(context: context, item: item, message: message, optionIndex: optionIndex)
        } else if let map = media as? TelegramMediaMap {
            ChatNavigationHooks.shared.showLocationPreview(context, map, message.peers[message.id.peerId], message.id, context.window)
        }
    }

    private func openGalleryForOption(context: any AccountContextProtocol, item: ChatPollItem?, message: Message, optionIndex: Int) {
        guard let item = item else { return }
        let info = item.allGalleryMedias()
        var galleryIndex = 0
        for (galleryIdx, optIdx) in info.galleryToOptionIndex {
            if optIdx == optionIndex {
                galleryIndex = galleryIdx
                break
            }
        }
        item.openGallery(firstIndex: galleryIndex)
    }

    private var videoPlayIcon: ImageView?

    private func updateMediaSignal(media: Media, mediaView: TransformImageView, boundingSize: NSSize, context: any AccountContextProtocol, message: Message?) {
        if let file = media as? TelegramMediaFile {
            let reference: FileMediaReference = message != nil ? .message(message: MessageReference(message!), media: file) : .standalone(media: file)
            let imageSize = file.dimensions?.size ?? boundingSize
            let arguments = TransformImageArguments(corners: ImageCorners(radius: 8), imageSize: imageSize, boundingSize: boundingSize, intrinsicInsets: NSEdgeInsets())
            if file.isVideo {
                mediaView.setSignal(chatMessageVideo(account: context.account, fileReference: reference, scale: backingScaleFactor))
            } else {
                mediaView.setSignal(chatMessageSticker(postbox: context.account.postbox, file: reference, small: true, scale: backingScaleFactor, fetched: true), cacheImage: { [weak file] result in
                    if let media = file {
                        cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale)
                    }
                })
            }
            mediaView.set(arguments: arguments)

            if file.isVideo {
                if self.videoPlayIcon == nil {
                    let icon = ImageView()
                    icon.isAccessibilityDecorative = true
                    let playImage = generateImage(NSMakeSize(20, 20), rotatedContext: { size, ctx in
                        ctx.clear(size.bounds)
                        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
                        ctx.fillEllipse(in: size.bounds)
                        ctx.setFillColor(NSColor.white.cgColor)
                        ctx.move(to: NSMakePoint(8, 5))
                        ctx.addLine(to: NSMakePoint(8, 15))
                        ctx.addLine(to: NSMakePoint(15, 10))
                        ctx.closePath()
                        ctx.fillPath()
                    })
                    icon.image = playImage
                    icon.sizeToFit()
                    mediaView.addSubview(icon)
                    self.videoPlayIcon = icon
                }
                self.videoPlayIcon?.center()
            } else {
                self.videoPlayIcon?.removeFromSuperview()
                self.videoPlayIcon = nil
            }
        } else if let image = media as? TelegramMediaImage {
            let reference: ImageMediaReference = message != nil ? .message(message: MessageReference(message!), media: image) : .standalone(media: image)
            let imageSize = largestImageRepresentation(image.representations)?.dimensions.size ?? boundingSize
            let arguments = TransformImageArguments(corners: ImageCorners(radius: 8), imageSize: imageSize, boundingSize: boundingSize, intrinsicInsets: NSEdgeInsets())
            mediaView.setSignal(chatMessagePhoto(account: context.account, imageReference: reference, scale: backingScaleFactor, synchronousLoad: false, autoFetchFullSize: true))
            mediaView.set(arguments: arguments)
        } else if let map = media as? TelegramMediaMap {
            let resource = MapSnapshotMediaResource(latitude: map.latitude, longitude: map.longitude, width: Int32(boundingSize.width) * 2, height: Int32(boundingSize.height) * 2, zoom: 15)
            let arguments = TransformImageArguments(corners: ImageCorners(radius: 8), imageSize: boundingSize, boundingSize: boundingSize, intrinsicInsets: NSEdgeInsets())
            mediaView.setSignal(chatMapSnapshotImage(account: context.account, resource: resource))
            mediaView.set(arguments: arguments)
        }
    }

    private func findTable() -> TableView? {
        var current: NSView? = self
        while let view = current {
            if let table = view as? TableView {
                return table
            }
            current = view.superview
        }
        return nil
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        guard let option = self.option else { return }


        transition.updateFrame(view: nameView, frame: nameView.centerFrameY(x: option.leftOptionInset))

        let progressY = size.height - progressView.frame.height
        let progressRightInset: CGFloat = option.anyOptionHasMedia ? PollOption.mediaSize + 8 + defaultInset : defaultInset
        let progressWidth = size.width - nameView.frame.minX - progressRightInset
        transition.updateFrame(view: progressView, frame: NSMakeRect(nameView.frame.minX, progressY, progressWidth, progressView.frame.height))

        let borderFrame = NSMakeRect(nameView.frame.minX, progressY - .borderSize + progressView.progressHeight, size.width - nameView.frame.minX - defaultInset, .borderSize)
        transition.updateFrame(view: borderView, frame: borderFrame)

        transition.updateFrame(view: progressBackgroundView, frame: NSMakeRect(nameView.frame.minX, progressY, progressWidth, progressView.progressHeight))

        if let selectedImageView = self.selectedImageView {
            transition.updateFrame(view: selectedImageView, frame: NSMakeRect(progressView.frame.minX - selectedImageView.frame.width - 4, floorToScreenPixels(backingScaleFactor, progressView.frame.midY - selectedImageView.frame.height / 2), selectedImageView.frame.width, selectedImageView.frame.height))
        }
        if let percentView = self.percentView {
            transition.updateFrame(view: percentView, frame: NSMakeRect(nameView.frame.minX - percentView.frame.width - PollOption.spaceBetweenTexts, nameView.frame.minY + 1, percentView.frame.width, percentView.frame.height))
        }
        if let selectingView = self.selectingView {
            transition.updateFrame(view: selectingView, frame: selectingView.centerFrameY(x: defaultInset))
        }
        if let progressIndicator = self.progressIndicator {
            transition.updateFrame(view: progressIndicator, frame: progressIndicator.centerFrameY(x: defaultInset))
        }

        let boundingSize = NSMakeSize(PollOption.mediaSize, PollOption.mediaSize)
        let mediaX = size.width - boundingSize.width - defaultInset
        let mediaY = floorToScreenPixels(backingScaleFactor, (size.height - PollOption.spaceBetweenOptions - boundingSize.height) / 2)

        if let mediaView: NSView = self.optionStickerView ?? self.optionMediaView {
            transition.updateFrame(view: mediaView, frame: NSMakeRect(mediaX, mediaY, boundingSize.width, boundingSize.height))
            if let overlay = self.optionMediaOverlay {
                transition.updateFrame(view: overlay, frame: NSMakeRect(mediaX, mediaY, boundingSize.width, boundingSize.height))
            }
        }
        
        var rightEdge = size.width - defaultInset
        if option.anyOptionHasMedia {
            rightEdge -= PollOption.mediaSize
        }
        if let avatarsView = self.optionAvatarsView {
            if option.anyOptionHasMedia {
                rightEdge -= 8
            }
            
            let avatarWidth = avatarsView.frame.width
            let avatarY = floorToScreenPixels(backingScaleFactor, (size.height - PollOption.spaceBetweenOptions - avatarsView.frame.height) / 2)
            transition.updateFrame(view: avatarsView, frame: NSMakeRect(rightEdge - avatarWidth, avatarY, avatarWidth, avatarsView.frame.height))
            rightEdge -= avatarWidth + 4
        }

        if let voteCountView = self.voteCountView, let voteCountText = option.voteCountText {
            let voteCountX = min(progressView.frame.maxX, rightEdge) - voteCountText.layoutSize.width
            let voteCountY = floorToScreenPixels(backingScaleFactor, (size.height - PollOption.spaceBetweenOptions - voteCountText.layoutSize.height) / 2) + 3
            transition.updateFrame(view: voteCountView, frame: NSMakeRect(voteCountX, voteCountY, voteCountText.layoutSize.width, voteCountText.layoutSize.height))
        }
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

}

private final class PollView : Control {
    fileprivate var mediaContentView: ChatMediaContentView?
    fileprivate var descriptionView: TextView?
    fileprivate let titleView: InteractiveTextView = InteractiveTextView(frame: .zero)
    private let typeView: TextView = TextView()
    private var actionButton: TextButton?
    private var totalVotesTextView: TextView?
    private var resultsInView: TextView?
    private var resultsInTimer: SwiftSignalKit.Timer?
    private(set) var explanationView: WPContentView?
    private var explanationCloseButton: ImageButton?
    fileprivate weak var currentItem: ChatPollItem?

    private var mergedAvatarsView: MergedAvatarsView?

    private var solutionButton: ImageButton?
    private var timerView: PollBubbleTimerView?
    private var addOptionButton: Control?
    private var addOptionIcon: ImageView?
    private var addOptionLabel: TextView?

    fileprivate let optionsContainerView: View = View()
    fileprivate var options:[PollOptionView] = []
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        typeView.isSelectable = false
        typeView.userInteractionEnabled = false
        optionsContainerView.layer?.masksToBounds = false
        addSubview(titleView)
        addSubview(typeView)
        addSubview(optionsContainerView)

        titleView.textView.isSelectable = true
    }

    deinit {
        resultsInTimer?.invalidate()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            resultsInTimer?.invalidate()
            resultsInTimer = nil
        }
    }
    
    
    
    func update(with item: ChatPollItem, animated: Bool) {

        if let media = item.attachedMedia, let nodeType = item.contentNodeType() {
            let mediaX: CGFloat = (item.isBubbleFullFilled && item.hasBubble) ? item.mediaBubbleCornerInset : 0
            if self.mediaContentView == nil || !self.mediaContentView!.isKind(of: nodeType) {
                if let view = self.mediaContentView {
                    performSubviewRemoval(view, animated: animated)
                }
                self.mediaContentView = nodeType.init(frame: NSMakeRect(mediaX, 0, item.attachedMediaSize.width, item.attachedMediaSize.height))
                addSubview(self.mediaContentView!)
            }
            self.mediaContentView?.update(with: media, size: item.attachedMediaSize, context: item.context, parent: item.message, table: item.table, parameters: item.mediaParameters, animated: animated, positionFlags: item.positionFlags)
            self.mediaContentView?.setFrameSize(item.attachedMediaSize)
        } else {
            if let view = self.mediaContentView {
                performSubviewRemoval(view, animated: animated)
                self.mediaContentView = nil
            }
        }

        if let descriptionText = item.descriptionText {
            let descView: TextView
            if let existing = self.descriptionView {
                descView = existing
            } else {
                descView = TextView()
                descView.isSelectable = true
                self.descriptionView = descView
                addSubview(descView)
            }
            descView.isSelectable = item.canCopyText
            descView.update(descriptionText)
        } else {
            self.descriptionView?.removeFromSuperview()
            self.descriptionView = nil
        }

        titleView.set(text: item.titleText, context: item.context)
        typeView.update(item.titleTypeText)

        titleView.textView.setIsShimmering(item.isTranslateLoading, animated: animated)

        if let explanationLayout = item.explanationLayout {
            let viewClass: WPContentView.Type = explanationLayout is WPMediaLayout ? WPMediaContentView.self : WPArticleContentView.self
            if self.explanationView == nil || !self.explanationView!.isKind(of: viewClass) {
                self.explanationView?.removeFromSuperview()
                let contentView = viewClass.init(frame: NSMakeRect(item.bubbleContentInset, 0, explanationLayout.size.width, explanationLayout.size.height))
                addSubview(contentView)
                self.explanationView = contentView
                if animated {
                    contentView.layer?.animateAlpha(from: 0, to: 1, duration: 0.3)
                }
            }
            explanationLayout.table = item.table
            self.explanationView?.update(with: explanationLayout, animated: animated)
            self.explanationView?.setFrameSize(explanationLayout.size)
            self.explanationView?.needsLayout = true

            if self.explanationCloseButton == nil {
                let button = ImageButton()
                button.autohighlight = false
                button.scaleOnClick = true
                button.setAccessibilityLabel(strings().voiceOverCommonClose)
                addSubview(button)
                self.explanationCloseButton = button
                button.setFrameOrigin(NSMakePoint(item.bubbleContentInset + explanationLayout.size.width - button.frame.width - 4, 4))
            }
            if let closeButton = self.explanationCloseButton {
                closeButton.set(image: TelegramThemeHooks.shared.image(.iconBrowserCloseTab).precomposed(item.wpPresentation.activity.main), for: .Normal)
                closeButton.sizeToFit()
                closeButton.removeAllHandlers()
                closeButton.set(handler: { [weak item] _ in
                    if let messageId = item?.message?.id {
                        item?.chatInteraction.togglePollSolution(messageId)
                    }
                }, for: .Click)
            }
        } else {
            if let view = self.explanationView {
                self.explanationView = nil
                performSubviewRemoval(view, animated: animated, scaleVertical: true)
                self.explanationCloseButton?.removeFromSuperview()
                self.explanationCloseButton = nil
            }
        }
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        if options.count < item.options.count {
            var optY: CGFloat = 0
            if let layout = item.explanationLayout {
                optY += layout.size.height + item.defaultContentInnerInset
            }
            var localY: CGFloat = 0
            for existingOpt in item.options.prefix(options.count) {
                localY += existingOpt.contentSize.height
                localY += PollOption.spaceBetweenOptions
            }
            while options.count < item.options.count {
                let idx = options.count
                let optionSize = item.options[idx].contentSize
                let option = PollOptionView(frame: NSMakeRect(0, localY - (idx > 0 ? PollOption.spaceBetweenOptions : 0), frame.width, optionSize.height))
                options.append(option)
                optionsContainerView.addSubview(option)
                localY += optionSize.height + PollOption.spaceBetweenOptions
                if animated {
                    option.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
        }
        while options.count > item.options.count {
            let option = options.removeLast()
            performSubviewRemoval(option, animated: animated)
        }
        for (i, option) in item.options.enumerated() {
            self.options[i].update(with: option, context: item.context, animated: animated, item: item, message: item.message, optionIndex: i)
        }

        do {
            var containerY: CGFloat = 0
            if let layout = item.explanationLayout {
                containerY += layout.size.height + item.defaultContentInnerInset
            }
            if let mediaContentView = self.mediaContentView {
                containerY += mediaContentView.frame.height + item.defaultContentInnerInset
            }
            if let descriptionView = self.descriptionView {
                containerY += descriptionView.frame.height + item.defaultContentInnerInset
            }
            containerY += titleView.frame.height + item.defaultContentInnerInset
            containerY += typeView.frame.height
            var containerH: CGFloat = 0
            for opt in item.options {
                containerH += opt.contentSize.height
            }
            containerH += CGFloat(max(0, item.options.count - 1)) * PollOption.spaceBetweenOptions
            if item.canAddOption {
                containerH += item.options.first?.contentSize.height ?? 33
            }
            transition.updateFrame(view: optionsContainerView, frame: NSMakeRect(0, containerY, frame.width, containerH))
        }

        if item.canAddOption {
            let isEnabled = item.poll.publicity == .public
            let textColor = isEnabled ? item.presentation.chat.grayText(item.isIncoming, item.isBubbled) : item.presentation.chat.grayText(item.isIncoming, item.isBubbled).withAlphaComponent(0.5)
            let iconColor = isEnabled ? item.presentation.chat.grayText(item.isIncoming, item.isBubbled) : item.presentation.chat.grayText(item.isIncoming, item.isBubbled).withAlphaComponent(0.5)

            if self.addOptionButton == nil {
                let button = Control()
                button.scaleOnClick = true
                button.setAccessibilityLabel(strings().chatPollAddOption)
                optionsContainerView.addSubview(button)
                self.addOptionButton = button

                let icon = ImageView()
                icon.isAccessibilityDecorative = true
                button.addSubview(icon)
                self.addOptionIcon = icon

                let label = TextView()
                label.userInteractionEnabled = false
                label.isSelectable = false
                button.addSubview(label)
                self.addOptionLabel = label
            }
            if let addOptionButton = self.addOptionButton {
                addOptionButton.removeAllHandlers()
                addOptionButton.set(handler: { [weak item] _ in
                    guard let item = item, let message = item.message else { return }
                    if message.flags.contains(.Failed) || message.flags.contains(.Unsent) || message.flags.contains(.Sending) {
                        return
                    }
                    let existingOptions = item.poll.options.map { $0.text }
                    let source: ChatPollSource = .addOption(messageId: message.id, existingOptions: existingOptions)
                    ChatNavigationHooks.shared.showNewPoll(item.chatInteraction, source, item.context.window, { [weak self] in self?.addOptionButton })
                }, for: .Click)
            }
            self.addOptionIcon?.image = TelegramThemeHooks.shared.image(.menuAdd).precomposed(iconColor)
            self.addOptionIcon?.sizeToFit()

            let layout = TextViewLayout(.initialize(string: strings().chatPollAddOption, color: textColor, font: .normal(.text)), maximumNumberOfLines: 1)
            layout.measure(width: frame.width - 46 - 13)
            self.addOptionLabel?.update(layout)
        } else if let view = addOptionButton {
            performSubviewRemoval(view, animated: animated)
            self.addOptionButton = nil
            self.addOptionIcon = nil
            self.addOptionLabel = nil
        }

        if let totalVotesText = item.totalVotesText {
            let current: TextView
            var isNew = false
            if let view = totalVotesTextView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                totalVotesTextView = current
                addSubview(current)
                isNew = true
            }
            current.update(totalVotesText)
            if isNew {
                let votesY = optionsContainerView.frame.maxY + item.defaultContentInnerInset
                current.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - totalVotesText.layoutSize.width) / 2), votesY))
            }
        } else if let view = totalVotesTextView {
            totalVotesTextView = nil
            performSubviewRemoval(view, animated: animated)
        }

        self.currentItem = item
        if item.showResultsIn {
            var isNew = false
            if resultsInView == nil {
                let current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                resultsInView = current
                addSubview(current)
                isNew = true
            }
            updateResultsIn()
            if isNew, let resultsInView = self.resultsInView {
                let resultsY = (totalVotesTextView?.frame.maxY ?? typeView.frame.maxY) + 5
                resultsInView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - resultsInView.frame.width) / 2), resultsY))
            }
            if resultsInTimer == nil {
                resultsInTimer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
                    self?.updateResultsIn()
                }, queue: Queue.mainQueue())
                resultsInTimer?.start()
            }
        } else {
            if let view = resultsInView {
                resultsInView = nil
                performSubviewRemoval(view, animated: animated)
            }
            resultsInTimer?.invalidate()
            resultsInTimer = nil
        }

        if let actionText = item.actionButtonText {
            let current: TextButton
            var isNew = false
            if let view = self.actionButton {
                current = view
            } else {
                current = TextButton()
                self.actionButton = current
                addSubview(current)
                isNew = true
            }
            current.isEnabled = item.actionButtonIsEnabled
            current.removeAllHandlers()
            current.set(handler: { [weak item] _ in
                item?.invokeAction()
            }, for: .SingleClick)
            current.set(font: .normal(.text), for: .Normal)
            current.set(color: item.presentation.chat.activityColor(item.isIncoming, item.isBubbled), for: .Normal)
            current.set(text: actionText, for: .Normal)
            _ = current.sizeToFit(NSMakeSize(10, 4), thatFit: false)
            if isNew {
                var actionY = optionsContainerView.frame.maxY
                if let totalVotesTextView = self.totalVotesTextView {
                    actionY = totalVotesTextView.frame.maxY
                }
                actionY += item.defaultContentInnerInset - 4
                current.centerX(y: actionY)
            }
        } else if let view = self.actionButton {
            self.actionButton = nil
            performSubviewRemoval(view, animated: animated)
        }


        guard let message = item.message else {
            return
        }
        
        var avatarPeers: [Peer] = []
        if !item.isBotQuiz {
            for peerId in item.poll.results.recentVoters {
                if let peer = message.peers[peerId] {
                    avatarPeers.append(peer)
                }
            }
        }

        if !avatarPeers.isEmpty {
            let current: MergedAvatarsView
            if let view = self.mergedAvatarsView {
                current = view
            } else {
                current = MergedAvatarsView()
                self.mergedAvatarsView = current
                addSubview(current)
            }
            let avatarWidth = current.mergedImageSpacing * CGFloat(avatarPeers.count) + 2
            current.setFrameSize(NSMakeSize(avatarWidth, current.mergedImageSize))
            current.frame = CGRect(origin: NSMakePoint(typeView.frame.maxX + 6, typeView.frame.minY), size: current.frame.size)
            current.update(context: item.context, peers: avatarPeers, message: message, synchronousLoad: false)
            current.removeAllHandlers()
            current.set(handler: { [weak item] _ in
                if let text = item?.actionButtonText, text != strings().chatPollSubmitVote, item?.actionButtonIsEnabled == true {
                    item?.invokeAction()
                }
            }, for: .Click)
        } else if let view = self.mergedAvatarsView {
            self.mergedAvatarsView = nil
            performSubviewRemoval(view, animated: animated)
        }

        if let _ = item.poll.results.solution, item.options.contains(where: { $0.isSelected }) || item.isClosed {
            var mayApplyAnimation = false
            if solutionButton == nil {
                solutionButton = ImageButton()
                solutionButton?.setAccessibilityLabel(strings().chatPollExplanation)
                addSubview(solutionButton!)
                mayApplyAnimation = animated
            }
            if let solutionButton = self.solutionButton {
                solutionButton.set(image: item.presentation.chat.quizSolution(item), for: .Normal)
                solutionButton.style = ControlStyle(font: nil, foregroundColor: theme.colors.accent, highlightColor: theme.colors.accent.withAlphaComponent(0.7))
                _ = solutionButton.sizeToFit()

                if mayApplyAnimation {
                    solutionButton.layer?.animateScaleSpring(from: 0.2, to: 1.0, duration: 0.3)
                }
                solutionButton.isHidden = item.solutionRevealed
            }
            solutionButton?.removeAllHandlers()

            solutionButton?.set(handler: { [weak item] _ in
                guard let item = item, let messageId = item.message?.id else { return }
                item.chatInteraction.togglePollSolution(messageId)
            }, for: .Click)

        } else {
            solutionButton?.removeFromSuperview()
            solutionButton = nil
        }
        
        let deadlineTimeout = item.poll.deadlineTimeout
        var displayDeadline = true
        if let voters = item.poll.results.voters {
            for voter in voters {
                if voter.selected {
                    displayDeadline = false
                    break
                }
            }
        }

        
        if let deadlineTimeout = deadlineTimeout, displayDeadline, !item.isClosed, !item.showResultsIn {
            let timerView: PollBubbleTimerView
            if let current = self.timerView {
                timerView = current
            } else {
                timerView = PollBubbleTimerView(frame: NSMakeRect(frame.width - 70 - 8, typeView.frame.minY, 70, 22))
                self.addSubview(timerView)
                self.timerView = timerView
                
                if animated {
                    timerView.layer?.animateScaleSpring(from: 0.2, to: 1.0, duration: 0.3)
                    timerView.layer?.animateAlpha(from: 0, to: 1, duration: 0.3)
                }
            }
            
            timerView.reachedTimeout = { [weak item] in
                item?.copyAndUpdate(animated: true)
            }
            var endDate: Int32?
            if message.id.namespace == Namespaces.Message.Cloud {
                let startDate: Int32
                if let forwardInfo = message.forwardInfo {
                    startDate = forwardInfo.date
                } else {
                    startDate = message.timestamp
                }
                endDate = startDate + deadlineTimeout
            }
            timerView.update(regularColor: item.presentation.chat.textColor(item.isIncoming, item.isBubbled), proximityColor: item.presentation.chat.redUI(item.isIncoming, item.isBubbled), timeout: deadlineTimeout, deadlineTimestamp: endDate)
            
        } else if let timerView = self.timerView {
            self.timerView = nil
            if animated {
                timerView.layer?.animateScaleSpring(from: 1, to: 0, duration: 0.3, removeOnCompletion: false, completion: { [weak timerView] _ in
                    timerView?.removeFromSuperview()
                })
                timerView.layer?.animateAlpha(from: 1, to: 0.2, duration: 0.3)
            } else {
                timerView.removeFromSuperview()
            }
        }
        
        
        
        updateLayout(item: item, size: frame.size, transition: transition)
        
    }
    
    
    func updateLayout(item: ChatPollItem, size: NSSize, transition: ContainedViewLayoutTransition) {
        var y: CGFloat = 0

        if let explanationView = self.explanationView, let layout = item.explanationLayout {
            transition.updateFrame(view: explanationView, frame: NSMakeRect(item.bubbleContentInset, y, layout.size.width, layout.size.height))
            if let closeButton = self.explanationCloseButton {
                transition.updateFrame(view: closeButton, frame: NSMakeRect(item.bubbleContentInset + layout.size.width - closeButton.frame.width - 4, y + 4, closeButton.frame.width, closeButton.frame.height))
            }
            y += layout.size.height + item.defaultContentInnerInset
        }

        if let mediaContentView = self.mediaContentView {
            let mediaX: CGFloat
            if item.isBubbleFullFilled && item.hasBubble {
                mediaX = item.mediaBubbleCornerInset
            } else if mediaContentView is ChatFileContentView {
                mediaX = item.bubbleContentInset
            } else {
                mediaX = 0
            }
            transition.updateFrame(view: mediaContentView, frame: NSMakeRect(mediaX, y, mediaContentView.frame.width, mediaContentView.frame.height))
            y += mediaContentView.frame.height + item.defaultContentInnerInset
        }
        transition.updateFrame(view: titleView, frame: NSMakeRect(item.bubbleContentInset, y, titleView.frame.width, titleView.frame.height))
        y += titleView.frame.height + item.defaultContentInnerInset
        if let descriptionView = self.descriptionView {
            transition.updateFrame(view: descriptionView, frame: NSMakeRect(item.bubbleContentInset, y, descriptionView.frame.width, descriptionView.frame.height))
            y += descriptionView.frame.height + item.defaultContentInnerInset
        }
        transition.updateFrame(view: typeView, frame: NSMakeRect(item.bubbleContentInset, y, typeView.frame.width, typeView.frame.height))
        y += typeView.frame.height

        var optionsHeight: CGFloat = 0
        for (i, option) in item.options.enumerated() {
            let optionY = optionsHeight - (i > 0 ? PollOption.spaceBetweenOptions : 0)
            transition.updateFrame(view: self.options[i], frame: NSMakeRect(0, optionY, size.width, option.contentSize.height))
            optionsHeight += option.contentSize.height
            if i != item.options.count - 1 {
                optionsHeight += PollOption.spaceBetweenOptions
            }
        }

        if let addOptionButton = self.addOptionButton {
            let buttonHeight = item.options.first?.contentSize.height ?? 33
            transition.updateFrame(view: addOptionButton, frame: NSMakeRect(0, optionsHeight, size.width, buttonHeight))
            if let icon = self.addOptionIcon {
                icon.setFrameOrigin(NSMakePoint(13 + (22 - icon.frame.width) / 2, (buttonHeight - icon.frame.height) / 2))
            }
            if let label = self.addOptionLabel {
                label.setFrameOrigin(NSMakePoint(46, (buttonHeight - label.frame.height) / 2))
            }
            optionsHeight += buttonHeight
        }

        transition.updateFrame(view: optionsContainerView, frame: NSMakeRect(0, y, size.width, optionsHeight))
        y += optionsHeight

        if let totalVotesTextView = self.totalVotesTextView, let totalVotesText = item.totalVotesText {
            y += item.defaultContentInnerInset + 3
            transition.updateFrame(view: totalVotesTextView, frame: NSMakeRect(floorToScreenPixels(backingScaleFactor, (size.width - totalVotesText.layoutSize.width) / 2), y, totalVotesText.layoutSize.width, totalVotesText.layoutSize.height))
            y += totalVotesText.layoutSize.height
        }

        if let actionButton = self.actionButton {
            y += item.defaultContentInnerInset - 1
            transition.updateFrame(view: actionButton, frame: NSMakeRect(floorToScreenPixels(backingScaleFactor, (size.width - actionButton.frame.width) / 2), y, actionButton.frame.width, actionButton.frame.height))
        }

        if let solutionButton = self.solutionButton {
            transition.updateFrame(view: solutionButton, frame: NSMakeRect(size.width - solutionButton.frame.width - 6, typeView.frame.minY - 8, solutionButton.frame.width, solutionButton.frame.height))
        }

        if let mergedAvatarsView = self.mergedAvatarsView {
            transition.updateFrame(view: mergedAvatarsView, frame: NSMakeRect(typeView.frame.maxX + 6, typeView.frame.minY, mergedAvatarsView.frame.width, mergedAvatarsView.frame.height))
        }
    }

    func showSolution() {
        self.solutionButton?.send(event: .Click)
    }

    private func updateResultsIn() {
        guard let item = currentItem, let endDate = item.deadlineEndDate, let resultsInView = self.resultsInView else {
            return
        }
        let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        let remaining = max(0, Int(endDate - timestamp))
        if remaining == 0 {
            resultsInTimer?.invalidate()
            resultsInTimer = nil
            item.copyAndUpdate(animated: true)
            return
        }
        let timeString: String
        if remaining >= 86400 {
            timeString = strings().messageTimerShortDays("\(remaining / 86400)")
        } else {
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            let seconds = remaining % 60
            if hours > 0 {
                timeString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                timeString = String(format: "%02d:%02d", minutes, seconds)
            }
        }
        let text = strings().chatPollResultsIn(timeString)
        let layout = TextViewLayout(.initialize(string: text, color: item.presentation.chat.grayText(item.isIncoming, item.isBubbled), font: .normal(.small)))
        layout.measure(width: frame.width)
        resultsInView.update(layout, origin: NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - layout.layoutSize.width) / 2), (totalVotesTextView?.frame.maxY ?? typeView.frame.maxY) + 2))
    }

    override func layout() {
        super.layout()
        guard let item = self.currentItem else {
            return
        }
        updateLayout(item: item, size: self.frame.size, transition: .immediate)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
