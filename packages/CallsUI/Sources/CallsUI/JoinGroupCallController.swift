
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import AlertsUI
import AvatarUI
import GeneralRows
import InputDataUI
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import ColorPalette
import TelegramIconsTheme
import AppAnalytics

private func formattedJoinedMessage(from names: [String]) -> String {
    switch names.count {
    case 0:
        return strings().groupCallJoinNone
    case 1:
        return strings().groupCallJoinSingle(names[0])
    case 2:
        return strings().groupCallJoinDouble(names[0], names[0])
    default:
        let nameList = names.prefix(2)
        let othersCount = names.count - 2
        let othersWord = strings().groupCallJoinMultipleOthersOther(othersCount)
        return strings().groupCallJoinMultiple(nameList[0], nameList[1], othersWord)
    }
}

private final class HeaderItem : GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let headerLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    fileprivate let usersInfoLayout: TextViewLayout
    fileprivate let participants: [EnginePeer]
    fileprivate let dismiss: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, inviter: EnginePeer, participants: [EnginePeer], context: any AccountContextProtocol, dismiss: @escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        self.participants = participants
        self.headerLayout = .init(.initialize(string: strings().callGroupCall, color: theme.colors.text, font: .medium(.header)), alignment: .center)
        self.infoLayout = .init(.initialize(string: strings().groupCallInviteLinksInvited, color: theme.colors.text, font: .normal(.text)).detectBold(with: .medium(.text)), alignment: .center)
        

        self.usersInfoLayout = .init(.initialize(string: formattedJoinedMessage(from: participants.map { $0._asPeer().compactDisplayTitle }), color: theme.colors.text, font: .normal(.text)).detectBold(with: .medium(.text)))
        
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.headerLayout.measure(width: width - 40)
        self.infoLayout.measure(width: width - 40)
        
        self.usersInfoLayout.measure(width: width - 40)

        return true
    }
    
    public override var height: CGFloat {
        return 80 + 20 + headerLayout.layoutSize.height + 10 + infoLayout.layoutSize.height + 20 + 20 + 20 + usersInfoLayout.layoutSize.height + (participants.count > 0 ? 55 : 0) + 10
    }

    public override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return infoLayout.attributedString.string
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }
}

private final class HeaderItemView: GeneralRowView {
    
    private let dismiss = ImageButton()
    private let headerView = TextView()
    private let infoView = TextView()
    private let separator = View()
    
    private let iconView = View(frame: NSMakeRect(0, 0, 80, 80))
    private let gradient = SimpleGradientLayer()
    private let stickerView = ImageView()

    private var avatars:[AvatarContentView] = []
    private let avatarsContainer = View(frame: NSMakeRect(0, 0, 30 * 3, 30))

    private var peers:[Avatar] = []

    
    private let usersInfoView = TextView()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(dismiss)
        addSubview(headerView)
        addSubview(infoView)
        addSubview(separator)
        addSubview(usersInfoView)
        
        addSubview(avatarsContainer)
        avatarsContainer.isEventLess = true
        
        
        headerView.userInteractionEnabled = false
        infoView.userInteractionEnabled = false
        headerView.isSelectable = false
        infoView.isSelectable = false
        
        usersInfoView.userInteractionEnabled = false
        usersInfoView.isSelectable = false
        
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        stickerView.isAccessibilityDecorative = true
        
        addSubview(iconView)
        gradient.frame = iconView.bounds
        iconView.layer?.addSublayer(gradient)
        iconView.addSubview(stickerView)
        
        stickerView.image = TelegramThemeHooks.shared.image(.iconJoinGroupCall).precomposed(theme.colors.underSelectedColor)
        stickerView.sizeToFit()
        stickerView.center()


        iconView.layer?.cornerRadius = iconView.frame.height / 2
        

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        self.iconView.backgroundColor = theme.colors.accent
        self.headerView.update(item.headerLayout)
        self.infoView.update(item.infoLayout)
        
        self.usersInfoView.update(item.usersInfoLayout)
        
        self.separator.backgroundColor = theme.colors.border
        
        dismiss.setSingle(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .SingleClick)
        
        
        
        
        let peers:[Avatar] = item.participants.prefix(3).reduce([], { current, value in
            var current = current
            current.append(.init(peer: value._asPeer(), index: current.count))
            return current
        })
                
        let photoSize = NSMakeSize(35, 35)

        applyAvatarStack(peers, current: &self.peers, avatars: &avatars, avatarsContainer: avatarsContainer, photoSize: photoSize, animated: animated, makeControl: { avatar in
            AvatarContentView(context: item.context, peer: avatar.peer, message: nil, synchronousLoad: false, size: photoSize, inset: 15)
        })
        
    }
    
    public override func layout() {
        super.layout()
        iconView.centerX(y: 20)
        dismiss.setFrameOrigin(NSMakePoint(10, 10))
        
        self.headerView.centerX(y: iconView.frame.maxY + 20)
        self.infoView.centerX(y: self.headerView.frame.maxY + 10)
        
        separator.frame = NSMakeRect(20, self.infoView.frame.maxY + 10, frame.width - 40, .borderSize)
        
        usersInfoView.centerX(y: frame.height - 20 - usersInfoView.frame.height)
        
        
        var avatarRect = self.focus(NSMakeSize(avatarsContainer.subviews.max(by: { $0.frame.maxX < $1.frame.maxX })?.frame.maxX ?? 0, avatarsContainer.subviewsWidthSize.height))
        avatarRect.origin.y = usersInfoView.frame.minY - avatarRect.height - 20
        self.avatarsContainer.frame = avatarRect
        
    }
}

private final class Arguments {
    public let context: any AccountContextProtocol
    public let dismiss:()->Void
    public init(context: any AccountContextProtocol, dismiss:@escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
    }
}

private struct State : Equatable {
    public var inviter: EnginePeer?
    public var participants: [EnginePeer]
    public var summary: GroupCallSummary
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    let sectionId:Int32 = 0
    let index: Int32 = 0
    
    if let inviter = state.inviter {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return HeaderItem(initialSize, stableId: stableId, inviter: inviter, participants: state.participants, context: arguments.context, dismiss: arguments.dismiss)
        }))
    }
   
  
    // entries
//    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
    
    return entries
}

public func JoinGroupCallController(context: any AccountContextProtocol, summary: GroupCallSummary, reference: InternalGroupCallReference) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(inviter: context.myPeer.flatMap(EnginePeer.init), participants: summary.topParticipants.compactMap { $0.peer }, summary: summary)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }

    let arguments = Arguments(context: context, dismiss: {
        close?()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .groupCallConferenceInvitation
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    controller.validateData = { _ in
        
        _ = GroupCallUIHooks.shared.requestOrJoinConferenceCall(context, summary.info, reference).startStandalone(next: { result in
            switch result {
            case let .samePeer(callContext), let .success(callContext):
                GroupCallUIHooks.shared.applyGroupCallResult(context.sharedContext, callContext)
            default:
                alert(for: context.window, info: strings().errorAnError)
            }
        })
        
        close?()
        
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().groupCallJoinTitle, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true, customTheme: {
        .init(background: theme.colors.listBackground, listBackground: theme.colors.background)
    })
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}


/*

 */



