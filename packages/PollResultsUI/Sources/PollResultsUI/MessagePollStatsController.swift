import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import GraphCore
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
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public let loadDetailedGraph: (StatsGraph, Int64) -> Signal<StatsGraph?, NoError>
    public init(context: any AccountContextProtocol, loadDetailedGraph: @escaping (StatsGraph, Int64) -> Signal<StatsGraph?, NoError>) {
        self.context = context
        self.loadDetailedGraph = loadDetailedGraph
    }
}

private let _id_votes_graph = InputDataIdentifier("_id_votes_graph")

private func entries(_ stats: PollStats?, uiState: UIStatsState, arguments: Arguments, updateIsLoading: @escaping(InputDataIdentifier, Bool)->Void) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    guard let stats else {
        if statisticsChartStyle.usesGlass {
            entries.append(contentsOf: statisticsGraphSkeletonEntries([
                (_id_votes_graph, strings().messagePollStatsVoteTimeline, 2)
            ], sectionId: &sectionId, index: &index))
            entries.append(.sectionId(sectionId, type: .normal))
            return entries
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("loading"), equatable: nil, comparable: nil, item: { initialSize, stableId in
            return StatisticsLoadingRowItem(initialSize, stableId: stableId, context: arguments.context, text: strings().channelStatsLoading)
        }))
        return entries
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().messagePollStatsVoteTimeline), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    switch stats.votesGraph {
    case let .Loaded(_, string):
        ChartsDataManager.readChart(data: string.data(using: .utf8)!, sync: true, success: { collection in
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_votes_graph, equatable: InputDataEquatable(stats.votesGraph), comparable: nil, item: { initialSize, stableId in
                return StatisticRowItem(initialSize, stableId: stableId, context: arguments.context, collection: collection, viewType: .singleItem, type: .lines, title: strings().messagePollStatsVoteTimeline, getDetailsData: { _, _ in })
            }))
        }, failure: { error in
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_votes_graph, equatable: InputDataEquatable(stats.votesGraph), comparable: nil, item: { initialSize, stableId in
                return StatisticLoadingRowItem(initialSize, stableId: stableId, error: error.localizedDescription)
            }))
        })
        updateIsLoading(_id_votes_graph, false)
        index += 1
    case .OnDemand:
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_votes_graph, equatable: InputDataEquatable(stats.votesGraph), comparable: nil, item: { initialSize, stableId in
            return statisticsGraphPlaceholderItem(initialSize, stableId: stableId, seriesCount: 2)
        }))
        index += 1
    case let .Failed(error):
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_votes_graph, equatable: InputDataEquatable(stats.votesGraph), comparable: nil, item: { initialSize, stableId in
            return StatisticLoadingRowItem(initialSize, stableId: stableId, error: error)
        }))
        index += 1
        updateIsLoading(_id_votes_graph, false)
    case .Empty:
        break
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func MessagePollStatsController(context: any AccountContextProtocol, messageId: MessageId) -> ViewController {
    let initialState = UIStatsState(loading: [])
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((UIStatsState) -> UIStatsState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    let actionsDisposable = DisposableSet()
    let statsContext = PollStatsContext(account: context.account, messageId: messageId)

    let arguments = Arguments(context: context, loadDetailedGraph: { [weak statsContext] graph, x in
        return statsContext?.loadDetailedGraph(graph, x: x) ?? .single(nil)
    })

    let signal = combineLatest(statsContext.state, statePromise.get())
    |> deliverOnMainQueue
    |> map { statsState, uiState -> [InputDataEntry] in
        return entries(statsState.stats, uiState: uiState, arguments: arguments, updateIsLoading: { identifier, isLoading in
            updateState { state in
                if isLoading {
                    return state.withAddedLoading(identifier)
                } else {
                    return state.withRemovedLoading(identifier)
                }
            }
        })
    }
    |> map {
        return InputDataSignalValue(entries: $0)
    }
    |> afterDisposed {
        actionsDisposable.dispose()
    }

    let controller = InputDataController(dataSignal: signal, title: strings().messagePollStatsTitle, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .chatPollStats
    controller.contextObject = statsContext
    controller.didLoad = { controller, _ in
        controller.tableView.alwaysOpenRowsOnMouseUp = true
        controller.tableView.needUpdateVisibleAfterScroll = true
    }

    actionsDisposable.add((statsContext.state |> deliverOnMainQueue).start(next: { [weak statsContext] state in
        if let stats = state.stats, case .OnDemand = stats.votesGraph {
            statsContext?.loadVotesGraph()
        }
    }))

    return controller
}
