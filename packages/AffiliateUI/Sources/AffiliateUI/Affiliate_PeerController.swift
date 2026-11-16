import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import SceneEffects
import ObjcUtils
import AppAnalytics


private final class AffiliateRowItem: GeneralRowItem {
    fileprivate let arguments: Arguments
    fileprivate let item: AffiliateProgram
    
    fileprivate let titleLayout: TextViewLayout
    fileprivate let commissionLayout: TextViewLayout
    fileprivate let durationLayout: TextViewLayout
    
    fileprivate let commission2Layout: TextViewLayout?
    fileprivate let plusLayout: TextViewLayout?

    public init(_ initialSize: NSSize, stableId: AnyHashable, item: AffiliateProgram, arguments: Arguments, viewType: GeneralViewType) {
        self.arguments = arguments
        self.item = item
        
        self.titleLayout = .init(.initialize(string: item.peer._asPeer().displayTitle, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        self.commissionLayout = .init(.initialize(string: "\(item.commission.decemial.string)%", color: theme.colors.underSelectedColor, font: .menlo(.small)), alignment: .center)
        self.commissionLayout.measure(width: .greatestFiniteMagnitude)
        
        let localizedDuration = item.duration == .max ? strings().affiliateProgramDurationLifetime : item.duration < 12 ? strings().timerMonthsOther(Int(item.duration)) : strings().timerYearsOther(Int(item.duration / 12))

        
        self.durationLayout = .init(.initialize(string: localizedDuration, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        
        
        if item.commission2 > 0 {
            self.commission2Layout = .init(.initialize(string: "\(item.commission2)%", color: theme.colors.underSelectedColor, font: .menlo(.small)), alignment: .center)
            self.commission2Layout?.measure(width: .greatestFiniteMagnitude)
            
            self.plusLayout = .init(.initialize(string: "+", color: theme.colors.grayText, font: .menlo(.small)), alignment: .center)
            self.plusLayout?.measure(width: .greatestFiniteMagnitude)

        } else {
            self.commission2Layout = nil
            self.plusLayout = nil
        }
        
        super.init(initialSize, height: 50, stableId: stableId, viewType: viewType)
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items: [ContextMenuItem] = []
        
        
        items.append(.init(strings().affiliateSetupProgramMenuOpenApp, handler: { [weak self] in
            if let item = self?.item {
                self?.arguments.openApp(item)
            }
        }, itemImage: MenuAnimation.menu_folder_bot.value))
        
        if item.connected != nil {
            items.append(.init(strings().affiliateSetupProgramMenuCopyLink, handler: { [weak self] in
                if let item = self?.item {
                    self?.arguments.copyToClipboard(item)
                }
            }, itemImage: MenuAnimation.menu_copy_link.value))
            
            items.append(.init(strings().affiliateSetupProgramMenuLeave, handler: { [weak self] in
                if let item = self?.item {
                    self?.arguments.leave(item)
                }
            }, itemMode: .destruct, itemImage: MenuAnimation.menu_clear_history.value))
            
        }
        
 
        return .single(items)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.titleLayout.measure(width: blockWidth - 60)
        self.durationLayout.measure(width: blockWidth - 60 - commissionLayout.layoutSize.width - 10)
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return AffiliateRowView.self
    }

    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    override var accessibilityValue: String? {
        var commission = commissionLayout.attributedString.string
        if let commission2Layout {
            commission += " + " + commission2Layout.attributedString.string
        }
        return [commission, durationLayout.attributedString.string].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class AffiliateRowView : GeneralContainableRowView {
    private let avatar = AvatarControl(font: .avatar(15))
    private let title = TextView()
    private let commission = TextView()
    
    private var commission2: TextView?
    private var plus: TextView?
    
    private var linkBadge: ImageView?

    
    private let duration = TextView()
    private let next = ImageView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        avatar.setFrameSize(NSMakeSize(36, 36))
        
        commission.userInteractionEnabled = false
        commission.isSelectable = false
        
        duration.userInteractionEnabled = false
        duration.isSelectable = false
        
        title.userInteractionEnabled = false
        title.isSelectable = false
        
        addSubview(avatar)
        addSubview(commission)
        addSubview(duration)
        addSubview(next)
        addSubview(title)
        next.isAccessibilityDecorative = true
        
        
        containerView.setStateChangeHandler { [weak self] in
            self?.updateColors()
        }
        
        containerView.scaleOnClick = true
        
        containerView.set(handler: { [weak self] _ in
            guard let item = self?.item as? AffiliateRowItem else {
                return
            }
            if item.item.connected != nil {
                item.arguments.openConnected(item.item)
            } else {
                item.arguments.open(item.item)
            }
        }, for: .Click)
    }
    
    public override func updateColors() {
        super.updateColors()
        if let item = item as? AffiliateRowItem {
            self.background = item.viewType.rowBackground
            let highlighted = isSelect ? self.backdorColor : theme.colors.grayHighlight
            containerView.set(background: self.backdorColor, for: .Normal)
            containerView.set(background: highlighted, for: .Highlight)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? AffiliateRowItem else {
            return
        }
        
        self.commission.update(item.commissionLayout)
        self.duration.update(item.durationLayout)
        self.title.update(item.titleLayout)
        
        
        commission.backgroundColor = theme.colors.accent
        commission.setFrameSize(NSMakeSize(commission.frame.width + 4, commission.frame.height + 2))
        commission.layer?.cornerRadius = 4
        
        avatar.setPeer(account: item.arguments.context.account, peer: item.item.peer._asPeer())
        avatar.userInteractionEnabled = false
        
        next.image = theme.icons.generalNext
        next.sizeToFit()
        
        if let commission2Layout = item.commission2Layout {
            let current: TextView
            if let view = self.commission2 {
                current = view
            } else {
                current = TextView()
                self.addSubview(current)
                self.commission2 = current
                current.userInteractionEnabled = false
                current.isSelectable = false
            }
            current.update(commission2Layout)
            
            current.backgroundColor = theme.colors.greenUI
            current.setFrameSize(NSMakeSize(current.frame.width + 4, current.frame.height + 2))
            current.layer?.cornerRadius = 4

            
        } else if let view = self.commission2 {
            performSubviewRemoval(view, animated: animated)
            self.commission2 = nil
        }
        
        if let plusLayout = item.plusLayout {
            let current: TextView
            if let view = self.plus {
                current = view
            } else {
                current = TextView()
                self.addSubview(current)
                self.plus = current
                current.userInteractionEnabled = false
                current.isSelectable = false
            }
            current.update(plusLayout)
        } else if let view = self.plus {
            performSubviewRemoval(view, animated: animated)
            self.plus = nil
        }
        
        if let _ = item.item.connected {
            let current: ImageView
            if let view = self.linkBadge {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                addSubview(current)
                self.linkBadge = current
            }
            
            current.image = generateImage(NSMakeSize(20, 20), contextGenerator: { size, ctx in
                ctx.clear(size.bounds)
                ctx.round(size, size.width / 2)
                ctx.setFillColor(theme.colors.background.cgColor)
                ctx.fill(size.bounds)
                ctx.setFillColor(theme.colors.accent.cgColor)
                ctx.fillEllipse(in: size.bounds.insetBy(dx: 2, dy: 2))
                
                let image = TelegramThemeHooks.shared.image(.iconAffiliateLinkSmallBadge).precomposed(theme.colors.underSelectedColor)
                ctx.draw(image, in: size.bounds.focus(image.systemSize))
                
            })
            
            current.sizeToFit()
        } else if let view = self.linkBadge {
            performSubviewRemoval(view, animated: animated)
            self.linkBadge = nil
        }
        
        needsLayout = true
    }
    public override var additionBorderInset: CGFloat {
        return 36 + 10
    }
    
    
    public override func layout() {
        super.layout()
        avatar.centerY(x: 10)
        
        self.title.setFrameOrigin(NSMakePoint(avatar.frame.maxX + 10, 5))
        self.commission.setFrameOrigin(NSMakePoint(avatar.frame.maxX + 10, frame.height - 7 - self.commission.frame.height))
        
        if let commission2, let plus {
            
            plus.setFrameOrigin(NSMakePoint(commission.frame.maxX + 5, frame.height - 7 - plus.frame.height))
            commission2.setFrameOrigin(NSMakePoint(plus.frame.maxX + 5, frame.height - 7 - commission2.frame.height))

            self.duration.setFrameOrigin(NSMakePoint(commission2.frame.maxX + 5, frame.height - 7 - self.duration.frame.height))
        } else {
            self.duration.setFrameOrigin(NSMakePoint(self.commission.frame.maxX + 5, frame.height - 7 - self.duration.frame.height))
        }
        
        if let linkBadge {
            linkBadge.setFrameOrigin(NSMakePoint(avatar.frame.maxX - linkBadge.frame.width + 4, avatar.frame.maxY - linkBadge.frame.height))
        }
        
        next.centerY(x: containerView.frame.width - 12 - next.frame.width)
    }
}


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let toggleSort:(State.Sort)->Void
    public let open:(AffiliateProgram)->Void
    public let openConnected:(AffiliateProgram)->Void
    public let openApp:(AffiliateProgram)->Void
    public let copyToClipboard:(AffiliateProgram)->Void
    public let leave: (AffiliateProgram) ->Void
    public init(context: (any AccountContextProtocol), toggleSort:@escaping(State.Sort)->Void, open:@escaping(AffiliateProgram)->Void, openConnected:@escaping(AffiliateProgram)->Void, openApp:@escaping(AffiliateProgram)->Void, copyToClipboard:@escaping(AffiliateProgram)->Void, leave: @escaping(AffiliateProgram)->Void) {
        self.context = context
        self.toggleSort = toggleSort
        self.open = open
        self.openConnected = openConnected
        self.openApp = openApp
        self.copyToClipboard = copyToClipboard
        self.leave = leave
    }
}

private struct State : Equatable {
    
    public enum Sort {
        case date
        case profitability
        case revenue
        
        public var string: String {
            switch self {
            case .date:
                return strings().affiliateProgramSortSelectorDate
            case .profitability:
                return strings().affiliateProgramSortSelectorProfitability
            case .revenue:
                return strings().affiliateProgramSortSelectorRevenue
            }
        }
        public var value: EngineSuggestedStarRefBotsContext.SortMode {
            switch self {
            case .date:
                return .date
            case .profitability:
                return .profitability
            case .revenue:
                return .revenue
            }
        }
    }
    public var list: [EngineSuggestedStarRefBotsContext.SortMode : [AffiliateProgram]] = [:]
    public var listState: [EngineSuggestedStarRefBotsContext.SortMode : EngineSuggestedStarRefBotsContext.State] = [:]
    
    public var connectedState: EngineConnectedStarRefBotsContext.State?
    public var connectedList: [AffiliateProgram] = []

    public var sort: Sort = .profitability
    
    
    public var sorted: [AffiliateProgram] {
        return list[self.sort.value] ?? []
    }
}


private func _id_peer_id(_ peerId: PeerId) -> InputDataIdentifier {
    return .init("_id_peer_id_\(peerId.toInt64())")
}

private func _id_peer_id_connected(_ peerId: PeerId, link: String) -> InputDataIdentifier {
    return .init("_id_peer_id_connected_\(peerId.toInt64())_\(link)")
}

private let _id_promo = InputDataIdentifier("_id_promo")
private let _id_empty = InputDataIdentifier("_id_empty")

private func entries(_ state: State, arguments: Arguments, onlyDemo: Bool) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    if !onlyDemo {
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return Affiliate_HeaderItem(initialSize, stableId: stableId, context: arguments.context, presentation: theme, peer: nil, title: strings().affiliateSetupTitleJoin, info: strings().affiliateSetupTextJoin, detectBold: true, viewType: .legacy)
        }))
       
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_promo, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return Affiliate_PromoItem(initialSize, stableId: stableId, context: arguments.context, options: [
                .init(image: TelegramThemeHooks.shared.image(.iconBotAffiliateShield).precomposed(theme.colors.accent), title: strings().affiliateSetupIntroJoinTitle1, text: strings().affiliateSetupIntroJoinText1),
                .init(image: TelegramThemeHooks.shared.image(.iconBotAffiliateEye).precomposed(theme.colors.accent), title: strings().affiliateSetupIntroJoinTitle2, text: strings().affiliateSetupIntroJoinText2),
                .init(image: TelegramThemeHooks.shared.image(.iconBotAffiliateThumb).precomposed(theme.colors.accent), title: strings().affiliateSetupIntroJoinTitle3, text: strings().affiliateSetupIntroJoinText3)
            ])
        }))
        
        if !state.connectedList.isEmpty {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }
            
        if !state.connectedList.isEmpty {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().affiliateSetupConnectedSectionTitle), data: .init(viewType: .textTopItem)))
            index += 1
            
            struct Tuple : Equatable {
                var peer: AffiliateProgram
                var viewType: GeneralViewType
            }
          
            var tuples: [Tuple] = []
            for (i, peer) in state.connectedList.enumerated() {
                tuples.append(.init(peer: peer, viewType: bestGeneralViewType(state.connectedList, for: i)))
            }
            
            for tuple in tuples {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer_id_connected(tuple.peer.peer.id, link: tuple.peer.connected!.url), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                    return AffiliateRowItem(initialSize, stableId: stableId, item: tuple.peer, arguments: arguments, viewType: tuple.viewType)
                }))
            }
        }
    }
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    let rightItem: InputDataGeneralTextRightData
    if !onlyDemo && !state.list.isEmpty {
        
        let sortString = NSMutableAttributedString()
        sortString.append(string: strings().affiliateSetupSortSectionHeader, color: theme.colors.listGrayText, font: .normal(.text))
        sortString.append(string: " ", color: theme.colors.listGrayText, font: .normal(.text))
        sortString.append(string: state.sort.string.uppercased(), color: theme.colors.accent, font: .normal(.text))
        
        rightItem = .init(isLoading: false, text: sortString, contextMenu: {
            var items: [ContextMenuItem] = []
            
            let sortAll: [State.Sort] = [.date, .revenue, .profitability]
            
            for sort in sortAll {
                items.append(ContextMenuItem(sort.string, handler: {
                    arguments.toggleSort(sort)
                }))
            }
            return items
        }, afterImage: TelegramThemeHooks.shared.image(.iconAffiliateExpand).precomposed(theme.colors.accent))
    } else {
        rightItem = .init(isLoading: false, text: nil)
    }
    

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().affiliateSetupSuggestedSectionTitle), data: .init(viewType: .textTopItem, rightItem: rightItem)))
    index += 1
    
    
    struct Tuple : Equatable {
        var peer: AffiliateProgram
        var viewType: GeneralViewType
    }
  
    var tuples: [Tuple] = []
    for (i, peer) in state.sorted.enumerated() {
        tuples.append(.init(peer: peer, viewType: bestGeneralViewType(state.sorted, for: i)))
    }
    
    for tuple in tuples {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer_id(tuple.peer.peer.id), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            return AffiliateRowItem(initialSize, stableId: stableId, item: tuple.peer, arguments: arguments, viewType: tuple.viewType)
        }))
    }
    
    if state.list.isEmpty {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_empty, equatable: .init(state.list), comparable: nil, item: { initialSize, stableId in
            return GeneralBlockTextRowItem(initialSize, stableId: stableId, viewType: .singleItem, text: strings().affiliateProgramsEmpty, font: .normal(.text), color: theme.colors.grayText, centerViewAlignment: true)
        }))
        
    }
    
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func Affiliate_PeerController(context: (any AccountContextProtocol), peerId: PeerId, onlyDemo: Bool = false) -> InputDataController {

    let actionsDisposable = DisposableSet()
    let loadDisposable = MetaDisposable()
    actionsDisposable.add(loadDisposable)

    let initialState = State()
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    
    class ContextObject {
        let connected: EngineConnectedStarRefBotsContext?
        var sorted: [EngineSuggestedStarRefBotsContext.SortMode : EngineSuggestedStarRefBotsContext]
        init(connected: EngineConnectedStarRefBotsContext?, list: [EngineSuggestedStarRefBotsContext.SortMode : EngineSuggestedStarRefBotsContext]) {
            self.connected = connected
            self.sorted = list
        }
    }
    
    let contextObject = ContextObject(connected: onlyDemo ? nil : context.engine.peers.connectedStarRefBots(id: peerId), list: [
        .date: context.engine.peers.suggestedStarRefBots(id: peerId, sortMode: .date),
        .profitability: context.engine.peers.suggestedStarRefBots(id: peerId, sortMode: .profitability),
        .revenue: context.engine.peers.suggestedStarRefBots(id: peerId, sortMode: .revenue)
    ])
    
    let connectedState: Signal<EngineConnectedStarRefBotsContext.State?, NoError>
    if let connected = contextObject.connected {
        connectedState = connected.state |> map(Optional.init)
    } else {
        connectedState = .single(nil)
    }
    
    actionsDisposable.add(combineLatest(connectedState, contextObject.sorted[.date]!.state, contextObject.sorted[.profitability]!.state, contextObject.sorted[.revenue]!.state).startStrict(next: { connected, date, profability, revenue in
        updateState { current in
            var current = current
            
            current.connectedState = connected
            if let connected {
                current.connectedList = connected.items.map {
                    .init(peer: $0.peer, commission: $0.commissionPermille, commission2: 0, duration: $0.durationMonths ?? .max, date: context.timestamp, revenue: .zero, connected: .init(url: $0.url, revenue: $0.revenue, participants: $0.participants))
                }
            }
            
            var list: [(EngineSuggestedStarRefBotsContext.SortMode, EngineSuggestedStarRefBotsContext.State)] = []
            list.append((.date, date))
            list.append((.profitability, profability))
            list.append((.revenue, revenue))

            for item in list {
                current.listState[item.0] = item.1
                current.list[item.0] = item.1.items.map {
                    .init($0)
                }
            }
            
            return current
        }
    }))
    

    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, toggleSort: { sort in
        updateState { current in
            var current = current
            current.sort = sort
            return current
        }
    }, open: { program in
        if onlyDemo {
            AffiliateHooks.shared.openPeerInfo(context, program.peer.id)
        } else {
            let connected = stateValue.with { $0.connectedList.first(where: { $0.peer.id == program.peer.id })}
            if let connected {
                showModal(with: Affiliate_LinkPreview(context: context, program: connected, peerId: peerId), for: window, morphSource: {
                    ((getController?() as? InputDataController)?.tableView.item(stableId: InputDataEntryId.custom(_id_peer_id(program.peer.id)))?.view as? GeneralContainableRowView)?.containerView
                })
            } else {
                showModal(with: Affiliate_ProgramPreview(context: context, peerId: peerId, program: program, joined: { program in
                    updateState { current in
                        var current = current
                        current.connectedList.insert(program, at: 0)
                        return current
                    }
                }), for: window, morphSource: {
                    ((getController?() as? InputDataController)?.tableView.item(stableId: InputDataEntryId.custom(_id_peer_id(program.peer.id)))?.view as? GeneralContainableRowView)?.containerView
                })
            }
        }
    }, openConnected: { program in
        showModal(with: Affiliate_LinkPreview(context: context, program: program, peerId: peerId), for: window, morphSource: {
            guard let url = program.connected?.url else { return nil }
            return ((getController?() as? InputDataController)?.tableView.item(stableId: InputDataEntryId.custom(_id_peer_id_connected(program.peer.id, link: url)))?.view as? GeneralContainableRowView)?.containerView
        })
    }, openApp: { progam in
        AffiliateHooks.shared.openPeerInfo(context, progam.peer.id)
    }, copyToClipboard: { program in
        copyToClipboard(program.connected!.url)
        showModalText(for: window, text: strings().shareLinkCopied)
    }, leave: { [weak contextObject] program in
        if let connected = program.connected {
            verifyAlert(for: window, header: strings().affiliateSetupTitleNew, information: strings().affiliateProgramsConfirmAlert, ok: strings().affiliateProgramsConfirmAlertOK, successHandler: { _ in
                _ = contextObject?.connected?.remove(url: connected.url)
                updateState { current in
                    var current = current
                    current.connectedList.removeAll(where: { $0.connected?.url == connected.url })
                    return current
                }
            })
        }
                
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments, onlyDemo: onlyDemo))
    }
    
    let controller = InputDataController(dataSignal: signal, title: onlyDemo ? strings().affiliateProgramsExistingPrograms : strings().affiliateSetupTitleJoin, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = onlyDemo ? AnalyticsScreen.affiliateProgramsExisting : AnalyticsScreen.affiliatePrograms
    
    controller.contextObject = contextObject
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    controller.didLoad = { [weak contextObject] controller, _ in
        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                contextObject?.sorted[stateValue.with { $0.sort.value }]?.loadMore()
            default:
                break
            }
        }
    }

    return controller
    
}


/*
 let modalInteractions = ModalInteractions(acceptTitle: "PAY", accept: { [weak controller] in
     _ = controller?.returnKeyAction()
 }, singleButton: true)
 
 let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
 
 controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
     modalController?.close()
 })
 
 close = { [weak modalController] in
     modalController?.modal?.close()
 }
 
 return modalController
 */



