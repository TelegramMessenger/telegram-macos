import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import ShortPeerRow
import StatisticsUI
import InlineStickerLayer
import LocalAnimations



private struct PollResultState : Equatable {
    public let results: PollResultsState?
    public let shouldLoadMore: Data?
    public let poll: TelegramMediaPoll
    public let expandedOptions: [Data: Int]
    
    public init(results: PollResultsState?, poll: TelegramMediaPoll, shouldLoadMore: Data?, expandedOptions: [Data: Int]) {
        self.results = results
        self.poll = poll
        self.shouldLoadMore = nil
        self.expandedOptions = expandedOptions
    }
    public func withUpdatedResults(_ results: PollResultsState?) -> PollResultState {
        return PollResultState(results: results, poll: self.poll, shouldLoadMore: self.shouldLoadMore, expandedOptions: self.expandedOptions)
    }
    public func withAddedExpandedOption(_ identifier: Data) -> PollResultState {
        var expandedOptions = self.expandedOptions
        if let optionState = results?.options[identifier] {
            expandedOptions[identifier] = optionState.peers.count
        }

        return PollResultState(results: self.results, poll: self.poll, shouldLoadMore: self.shouldLoadMore, expandedOptions: expandedOptions)
    }
    public func withRemovedExpandedOption(_ identifier: Data) -> PollResultState {
        var expandedOptions = self.expandedOptions
        expandedOptions.removeValue(forKey: identifier)
        return PollResultState(results: self.results, poll: self.poll, shouldLoadMore: self.shouldLoadMore, expandedOptions: expandedOptions)
    }
}
private func _id_option(_ identifier: Data, _ peerId: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_option_\(identifier.base64EncodedString())_\(peerId.toInt64())")
}
private func _id_load_more(_ identifier: Data) -> InputDataIdentifier {
    return InputDataIdentifier("_id_load_more_\(identifier.base64EncodedString())")
}
private func _id_loading_for(_ identifier: Data) -> InputDataIdentifier {
    return InputDataIdentifier("_id_loading_for_\(identifier.base64EncodedString())")
}
private func _id_option_header(_ identifier: Data) -> InputDataIdentifier {
    return InputDataIdentifier("_id_option_header_\(identifier.base64EncodedString())")
}
private func _id_option_empty(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_option_empty_\(index)")
}

private let collapsedResultCount: Int = 10
private let collapsedInitialLimit: Int = 14


private let _id_loading = InputDataIdentifier("_id_loading")

private func pollResultEntries(_ state: PollResultState, context: any AccountContextProtocol, openProfile:@escaping(PeerId)->Void, expandOption: @escaping(Data)->Void, collapseOption: @escaping(Data)->Void) -> [InputDataEntry] {
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    var entries:[InputDataEntry] = []
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    let attr = NSMutableAttributedString()
    attr.append(string: state.poll.text, color: theme.colors.listGrayText, font: .normal(.huge))
    InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: state.poll.textEntities, isPremium: true)

    let pollQuestionText = state.poll.text
    entries.append(.desc(sectionId: sectionId, index: index, text: .attributed(attr), data: InputDataGeneralTextData(color: theme.colors.text, detectBold: true, isTextSelectable: true, viewType: .modern(position: .inner, insets: NSEdgeInsetsMake(0, 0, 0, 0)), fontSize: .huge, contextMenu: {
        return [ContextMenuItem(strings().textCopy, handler: {
            copyToClipboard(pollQuestionText)
        }, itemImage: MenuAnimation.menu_copy.value)]
    }, context: context)))
    index += 1
    
    
    
    let poll = state.poll
    
    var votes:[Int] = []
    
    
    
    for option in poll.options {
        let count = Int(poll.results.voters?.first(where: {$0.opaqueIdentifier == option.opaqueIdentifier})?.count ?? 0)
        votes.append(count)
    }
    
    let percents = countNicePercent(votes: votes, total: Int(poll.results.totalVoters ?? 0))
    
    struct Option : Equatable {
        let option: TelegramMediaPollOption
        let percent: Int
        let voters:PollResultsOptionState?
        let votesCount: Int
    }
    
    
    var options:[Option] = []
    for (i, option) in poll.options.enumerated() {
        if let voters = state.results?.options[option.opaqueIdentifier], !voters.peers.isEmpty {
            let votesCount = Int(poll.results.voters?.first(where: {$0.opaqueIdentifier == option.opaqueIdentifier})?.count ?? 0)
            options.append(Option(option: option, percent: percents[i], voters: voters, votesCount: votesCount))
        } else {
            let votesCount = Int(poll.results.voters?.first(where: {$0.opaqueIdentifier == option.opaqueIdentifier})?.count ?? 0)
            options.append(Option(option: option, percent: percents[i], voters: nil, votesCount: votesCount))
        }
    }
    
    
   

    for option in options {
        if option.votesCount > 0 {
            if option == options.first {
                entries.append(.sectionId(sectionId, type: .customModern(16)))
                sectionId += 1
            } else {
                entries.append(.sectionId(sectionId, type: .normal))
                sectionId += 1
            }
            
            let text = option.option.text
            let additionText:String = " — \(option.percent)%"
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_option_header(option.option.opaqueIdentifier), equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
                
                let collapse:(()->Void)?
                if state.expandedOptions[option.option.opaqueIdentifier] != nil {
                    collapse = {
                        collapseOption(option.option.opaqueIdentifier)
                    }
                } else {
                    collapse = nil
                }
                
                let attr = NSMutableAttributedString()
                attr.append(string: text, color: theme.colors.listGrayText, font: .normal(11.5))
                InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: option.option.entities, isPremium: true)
                
                return PollResultStickItem(initialSize, stableId: stableId, left: attr, context: context, additionText: additionText, right: poll.isQuiz ? strings().chatQuizTotalVotesOther(option.votesCount) : strings().chatPollTotalVotes1Other(option.votesCount), collapse: collapse, viewType: .textTopItem)
                
            }))
            index += 1
            
            if let optionState = option.voters {
                
                let optionExpandedAtCount = state.expandedOptions[option.option.opaqueIdentifier]
                
                var peers = optionState.peers
                let count = optionState.count ?? 0
                
                let displayCount: Int
                if peers.count > collapsedInitialLimit + 1 {
                    if optionExpandedAtCount != nil {
                        displayCount = peers.count
                    } else {
                        displayCount = collapsedResultCount
                    }
                } else {
                    if let optionExpandedAtCount = optionExpandedAtCount {
                        if optionExpandedAtCount == collapsedInitialLimit + 1 && optionState.canLoadMore {
                            displayCount = collapsedResultCount
                        } else {
                            displayCount = peers.count
                        }
                    } else {
                        if !optionState.canLoadMore {
                            displayCount = peers.count
                        } else {
                            displayCount = collapsedResultCount
                        }
                    }
                }
                
                peers = Array(peers.prefix(displayCount))
                for (i, voter) in peers.enumerated() {
                    
                    guard let peer = voter.peer.peer else {
                        continue
                    }
                    
                    let renrederPeer = voter.peer
                    var viewType = bestGeneralViewType(peers, for: i)
                    if i == peers.count - 1, optionState.canLoadMore {
                        if peers.count == 1 {
                            viewType = .firstItem
                        } else {
                            viewType = .innerItem
                        }
                    }
                    entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_option(option.option.opaqueIdentifier, renrederPeer.peerId), equatable: InputDataEquatable(option), comparable: nil, item: { initialSize, stableId in
                        return ShortPeerRowItem(initialSize, peer: peer, account: context.account, context: context, stableId: stableId, height: 46, photoSize: NSMakeSize(32, 32), inset: NSEdgeInsets(left: 20, right: 20), generalType: .context(stringForMediumDate(timestamp: voter.date)), viewType: viewType, action: {
                            openProfile(renrederPeer.peerId)
                        }, highlightVerified: true)
                    }))
                    index += 1
                }
                
                let remainingCount = count - peers.count
                

                
                if remainingCount > 0 {
                    if optionState.isLoadingMore && state.expandedOptions[option.option.opaqueIdentifier] != nil {
                        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading_for(option.option.opaqueIdentifier), equatable: InputDataEquatable(option), comparable: nil, item: { initialSize, stableId in
                            return LoadingTableItem(initialSize, height: 41, stableId: stableId, viewType: .lastItem)
                        }))
                        index += 1
                    } else {
                        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_load_more(option.option.opaqueIdentifier), equatable: InputDataEquatable(option), comparable: nil, item: { initialSize, stableId in
                            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().pollResultsLoadMoreOther(remainingCount), nameStyle: blueActionButton, type: .none, viewType: .lastItem, action: {
                                expandOption(option.option.opaqueIdentifier)
                            }, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchUp, textInset: 52, thumbInset: 4))
                        }))
                        index += 1
                    }
                }
            } else {
                let displayCount: Int
                let voterCount = option.votesCount
                if voterCount > collapsedInitialLimit {
                    displayCount = collapsedResultCount
                } else {
                    displayCount = voterCount
                }
                let remainingCount: Int?
                if displayCount < voterCount {
                    remainingCount = voterCount - displayCount
                } else {
                    remainingCount = nil
                }
                
                var display:[Int] = []
                for peerIndex in 0 ..< displayCount {
                    display.append(peerIndex)
                }
                
                for peerIndex in display {
                    var viewType = bestGeneralViewType(display, for: peerIndex)
                    if peerIndex == displayCount - 1, remainingCount != nil {
                        if displayCount == 1 {
                            viewType = .firstItem
                        } else {
                            viewType = .innerItem
                        }
                    }
                    
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_option_empty(Int(index)), equatable: nil, comparable: nil, item: { initialSize, stableId in
                        return PeerEmptyHolderItem(initialSize, stableId: stableId, height: 46, photoSize: NSMakeSize(32, 32), viewType: viewType)
                    }))
                    index += 1
                }
                if let remainingCount = remainingCount {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_load_more(option.option.opaqueIdentifier), equatable: InputDataEquatable(option), comparable: nil, item: { initialSize, stableId in
                        return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().pollResultsLoadMoreOther(remainingCount), nameStyle: blueActionButton, type: .none, viewType: .lastItem, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchUpDisabled, textInset: 52, thumbInset: 4), enabled: false)
                    }))
                    index += 1
                }
            }
        }
        
        
    }
    
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func PollResultController(context: any AccountContextProtocol, message: Message, scrollToOption: Data? = nil) -> InputDataModalController {

    let poll = message.media[0] as! TelegramMediaPoll
    
    var scrollToOption = scrollToOption
    
    let resultsContext: PollResultsContext = context.engine.messages.pollResults(messageId: message.id, poll: poll) 

    let initialState = PollResultState(results: nil, poll: poll, shouldLoadMore: nil, expandedOptions: [:])
    
    let disposable = MetaDisposable()
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((PollResultState) -> PollResultState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    disposable.set(resultsContext.state.start(next: { results in
        updateState {
            $0.withUpdatedResults(results)
        }
    }))
    
    var openProfile:((PeerId)->Void)? = nil
    
    let signal = statePromise.get() |> map {
        pollResultEntries($0, context: context, openProfile: { peerId in
            openProfile?(peerId)
        }, expandOption: { identifier in
            updateState {
                $0.withAddedExpandedOption(identifier)
            }
            resultsContext.loadMore(optionOpaqueIdentifier: identifier)
        }, collapseOption: { identifier in
            updateState {
                $0.withRemovedExpandedOption(identifier)
            }
        })
    } |> map {
        InputDataSignalValue(entries: $0, animated: true)
    }
    
    let controller = InputDataController(dataSignal: signal, title: !poll.isQuiz ? strings().pollResultsTitlePoll : strings().pollResultsTitleQuiz)
    
    controller.getBackgroundColor = {
        theme.colors.background
    }
    
    controller.contextObject = resultsContext
    
    let modalController = InputDataModalController(controller)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.centerModalHeader = ModalHeaderData(title: controller.defaultBarTitle, subtitle: poll.isQuiz ? strings().chatQuizTotalVotesOther(Int(poll.results.totalVoters ?? 0)) : strings().chatPollTotalVotes1Other(Int(poll.results.totalVoters ?? 0)))
    
    controller.getBackgroundColor = {
        theme.colors.listBackground
    }
    
   
    
    openProfile = { [weak modalController] peerId in
        PollResultsHooks.shared.openPeerInfo(context, peerId)
        modalController?.close()
    }
    controller.afterTransaction = { controller in
        if let scroll = scrollToOption {
            let item = controller.tableView.item(stableId: InputDataEntryId.custom(_id_option_header(scroll)))
            
            if let item = item {
                controller.tableView.scroll(to: .top(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: -10))
                scrollToOption = nil
            }
        }
    }
    
    controller.didLoad = { controller, _ in
        controller.tableView.set(stickClass: PollResultStickItem.self, handler: { _ in
            
        })
    }
    
//    controller.didLoad = { controller, _ in
//        controller.tableView.setScrollHandler { position in
//            switch position.direction {
//            case .bottom:
//                let shouldLoadMore = stateValue.with { $0.shouldLoadMore }
//                if let shouldLoadMore = shouldLoadMore {
//                    resultsContext.loadMore(optionOpaqueIdentifier: shouldLoadMore)
//                }
//               break
//            default:
//                break
//            }
//        }
//    }
    

    
    return modalController
}
