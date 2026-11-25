import Foundation
import TelegramMedia
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AlertsUI
import LocalAnimations
import DateUtils
import TelegramIconsTheme
import Postbox
import InlineStickerLayer
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public let close:()->Void
    public init(context: any AccountContextProtocol, close:@escaping()->Void) {
        self.context = context
        self.close = close
    }
}

private struct State : Equatable {
    public var session: NewSessionReview
    public var timeout: Int
    public var closable: Bool = false
}

private final class RevokeRowItem : TableRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let timeout: Int
    fileprivate let session: NewSessionReview
    fileprivate let header: TextViewLayout
    fileprivate let title: TextViewLayout
    fileprivate let text: TextViewLayout
    fileprivate let close:()->Void
    public init(_ initialSize: NSSize, session: NewSessionReview, timeout: Int, context: any AccountContextProtocol, close: @escaping()->Void) {
        self.context = context
        self.session = session
        self.timeout = timeout
        self.close = close
        self.header = .init(.initialize(string: strings().newSessionReviewModalHeader, color: theme.colors.redUI, font: .medium(.title)), alignment: .center)
        self.title = .init(.initialize(string: strings().newSessionReviewModalTitle, color: theme.colors.text, font: .medium(.header)), alignment: .center)
        self.text = .init(.initialize(string: strings().newSessionReviewModalText(session.location, session.device), color: theme.colors.text, font: .normal(.text)), alignment: .center)

        super.init(initialSize)
        _ = makeSize(initialSize.width)
    }
    
    public override var stableId: AnyHashable {
        return 0
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        header.measure(width: width - 40)
        title.measure(width: width - 40)
        text.measure(width: width - 40)

        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 20
                
        height += header.layoutSize.height + 20
        height += 20
        
        height += 80 //icon
        height += 20

        height += title.layoutSize.height
        height += 10
        
        height += text.layoutSize.height
        height += 20

        height += 40 //button
        height += 20
        
        return height
    }
    
    public override func viewClass() -> AnyClass {
        return RevokeRowItemView.self
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        return "\(header.attributedString.string). \(text.attributedString.string)"
    }
}

private final class RevokeRowItemView : TableRowView {
    private let headerBg = View()
    private let header = TextView()
    private let title = TextView()
    private let text = TextView()
    private let iconBg = View()
    private let button = TextButton()
    
    private var handLayer: InlineStickerItemLayer?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(headerBg)
        headerBg.addSubview(header)
        addSubview(title)
        addSubview(text)
        addSubview(iconBg)
        addSubview(button)
        
        
        title.userInteractionEnabled = false
        title.isSelectable = false
        
        text.userInteractionEnabled = false
        text.isSelectable = false

        header.userInteractionEnabled = false
        header.isSelectable = false

        
        iconBg.setFrameSize(NSMakeSize(80, 80))
        
        button.set(handler: { [weak self] _ in
            if let item = self?.item as? RevokeRowItem {
                item.close()
            }
        }, for: .Click)
        
        button.scaleOnClick = true
        button.autohighlight = false
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? RevokeRowItem else {
            return
        }
        title.update(item.title)
        header.update(item.header)
        text.update(item.text)
        
        if self.handLayer == nil {
            let layer = InlineStickerItemLayer.init(account: item.context.account, file: LocalAnimatedSticker.hand_animation.file, size: NSMakeSize(70, 70), playPolicy: .onceEnd, getColors: { _ in
                return [.init(keyPath: "", color: theme.colors.underSelectedColor)]
            })
            layer.isPlayable = true
            layer.frame = iconBg.focus(layer.frame.size)
            self.iconBg.layer?.addSublayer(layer)
            
            self.handLayer = layer
        }
        
        headerBg.setFrameSize(header.frame.size + NSMakeSize(20, 20))

        headerBg.backgroundColor = theme.colors.redUI.withAlphaComponent(0.2)
        headerBg.layer?.cornerRadius = 10
        
        iconBg.backgroundColor = theme.colors.accent
        iconBg.layer?.cornerRadius = iconBg.frame.height / 2
        
        if item.timeout == 0 {
            button.layer?.opacity = 1.0
        } else {
            button.layer?.opacity = 0.6
        }
        button.set(background: theme.colors.accent, for: .Normal)
        button.set(color: theme.colors.underSelectedColor, for: .Normal)
        button.set(font: .medium(.title), for: .Normal)
        if item.timeout > 0 {
            button.set(text: strings().newSessionReviewModalButtonTimeout("\(item.timeout)"), for: .Normal)
        } else {
            button.set(text: strings().newSessionReviewModalButton, for: .Normal)
        }
        button.sizeToFit(.zero, NSMakeSize(frame.width - 40, 40), thatFit: true)
        button.layer?.cornerRadius = 10
        
        button.isEnabled = item.timeout == 0
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        headerBg.centerX(y: 20)
        header.center()
        
        iconBg.centerX(y: headerBg.frame.maxY + 20)
        title.centerX(y: iconBg.frame.maxY + 20)
        text.centerX(y: title.frame.maxY + 10)
        
        button.centerX(y: text.frame.maxY + 20)
    }
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    entries.append(.custom(sectionId: 0, index: 0, value: .none, identifier: .init("whole"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return RevokeRowItem(initialSize, session: state.session, timeout: state.timeout, context: arguments.context, close: arguments.close)
    }))
    
    return entries
}

public func SuspiciousRevokeModal(context: any AccountContextProtocol, session: NewSessionReview) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(session: session, timeout: 5, closable: false)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    var close:(()->Void)? = nil
    
    let arguments = Arguments(context: context, close: {
        updateState { current in
            var current = current
            current.closable = true
            return current
        }
        close?()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .appLoginPrevented
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    let timer = SwiftSignalKit.Timer(timeout: 1, repeat: true, completion: {
        updateState { current in
            var current = current
            current.timeout = max(current.timeout - 1, 0)
            return current
        }
    }, queue: .mainQueue())
    
    timer.start()
    
    controller.contextObject = timer

    let modalController = InputDataModalController(controller, modalInteractions: nil, closeHandler: { f in
        let closable = stateValue.with { $0.closable }
        if closable {
            f()
        } else {
            NSSound.beep()
        }
    })
    

    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
}


/*

 */




