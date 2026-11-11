import Cocoa
import Foundation
import WebKit
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils
import KeyboardKey
import TelegramIconsTheme
import TelegramMedia
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import FilePanels
import TelegramLinks
import PremiumStatusUI
import SystemPermissions
import Svg
import LocalAuthentication
/*
 Со 193 слоя. Показывает пользователю попап с предложением установить эмоджи custom_emoji_id в качестве статуса. Если передано опциональное поле expiration_date, статус будет установлен до этой даты. expiration_date – время в unixtime. Если дата указана некорректно или некорректно указан идентификатор эмоджи, клиент должен вызвать событие emoji_status_failed. Если все параметры верны, пользователю показывается попап с подтверждением. После успешной установки статуса вызывается событие emoji_status_set. Если во время установки произошла ошибка, или пользователь закрыл попап, не установив статус, то нужно отправить событие emoji_status_failed. Если у пользователя нет премиума, предлагается все равно показывать попап с предложением установить статус от бота, а при согласии – показывать экран, что нужен премиум.
 */

import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InlineStickerLayer
import AppAnalytics

private final class HeaderItem : GeneralRowItem {
    fileprivate let state: State
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let header: TextViewLayout
    fileprivate let info: TextViewLayout
    fileprivate let close: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, state: State, context: (any AccountContextProtocol), close: @escaping()->Void) {
        self.state = state
        self.close = close
        self.context = context
        self.header = .init(.initialize(string: strings().webappSetEmojiHeader, color: theme.colors.text, font: .medium(.header)), alignment: .center)
        self.info = .init(.initialize(string: strings().webappSetEmojiInfo(state.peer._asPeer().displayTitle), color: theme.colors.text, font: .normal(.text)).detectBold(with: .medium(.text)), alignment: .center)
        super.init(initialSize, stableId: stableId)
    }
    
    public override var height: CGFloat {
        return 20 + 100 + info.layoutSize.height + 5 + header.layoutSize.height + 15 + 20 + 15
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderView.self
    }

    public override var accessibilityLabel: String? {
        return header.attributedString.string
    }

    public override var accessibilityValue: String? {
        return info.attributedString.string
    }
    
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        info.measure(width: width - 40)
        header.measure(width: width - 40)
        
        return true

    }
}

private final class HeaderView: GeneralRowView {
    
    private final class PeerView: Control {
        private let avatarView = AvatarControl(font: .avatar(10))
        private let nameView: TextView = TextView()
        private var stickerView: InlineStickerView?
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(avatarView)
            addSubview(nameView)
            
            nameView.userInteractionEnabled = false
            
            self.avatarView.setFrameSize(NSMakeSize(20, 20))
            
            layer?.cornerRadius = 10
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func set(_ peer: EnginePeer, _ context: (any AccountContextProtocol), file: TelegramMediaFile, maxWidth: CGFloat) {
            self.avatarView.setPeer(account: context.account, peer: peer._asPeer())
            
            let nameLayout = TextViewLayout(.initialize(string: peer._asPeer().displayTitle, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1)
            nameLayout.measure(width: maxWidth)
            
            nameView.update(nameLayout)
            
            if stickerView == nil {
                let current: InlineStickerView = .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: file.fileId.id, file: file, emoji: ""), size: NSMakeSize(18, 18))
                addSubview(current)
                self.stickerView = current
            }
            
            setFrameSize(NSMakeSize(avatarView.frame.width + 10 + nameLayout.layoutSize.width + 20 + 10, 20))
            
            self.background = theme.colors.grayForeground
        }
        
        public override func layout() {
            super.layout()
            nameView.centerY(x: self.avatarView.frame.maxX + 10)
            stickerView?.centerY(x: self.nameView.frame.maxX + 10)
        }
    }
    
    private var stickerView: InlineStickerView?
    private let textView: TextView = TextView()
    private let infoText: TextView = TextView()
    private let dismiss = ImageButton()
    
    private let peerView: PeerView = .init(frame: .zero)
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(infoText)
        addSubview(peerView)
        addSubview(dismiss)
        
        textView.userInteractionEnabled = false
        infoText.userInteractionEnabled = false
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
     public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        dismiss.setSingle(handler: {  [weak item] _ in
            item?.close()
        }, for: .Click)
        
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.scaleOnClick = true
        
        peerView.set(.init(item.context.myPeer!), item.context, file: item.state.file, maxWidth: item.width - 40)
        
        infoText.update(item.info)
        textView.update(item.header)
        
        if stickerView == nil {
            let current: InlineStickerView = .init(account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, emoji: .init(fileId: item.state.file.fileId.id, file: item.state.file, emoji: ""), size: NSMakeSize(100, 100))
            addSubview(current)
            self.stickerView = current
        }
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        if let stickerView {
            stickerView.centerX(y: 20)
            textView.centerX(y: stickerView.frame.maxY)
            infoText.centerX(y: textView.frame.maxY + 5)
            peerView.centerX(y: infoText.frame.maxY + 15)
            dismiss.setFrameOrigin(NSMakePoint(15, 15))
        }
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let close:()->Void
    public init(context: (any AccountContextProtocol), close:@escaping()->Void) {
        self.context = context
        self.close = close
    }
}

private struct State : Equatable {
    public let peer: EnginePeer
    public let file: TelegramMediaFile
}

private let _id_header = InputDataIdentifier("_id_header")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    let sectionId:Int32 = 0
    let index: Int32 = 0
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
//  
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, state: state, context: arguments.context, close: arguments.close)
    }))
    
    // entries
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
    
    return entries
}
 public enum EmojiSetResultStatus {
    case success
    case fail
}

public func WebbotEmojisetModal(context: (any AccountContextProtocol), bot: EnginePeer, file: TelegramMediaFile, completed:@escaping(EmojiSetResultStatus)->Void) -> InputDataModalController {

    var didComplete = false
    let complete: (EmojiSetResultStatus) -> Void = { status in
        guard !didComplete else { return }
        didComplete = true
        completed(status)
    }
    
    var close:(()->Void)? = nil

    let initialState = State(peer: bot, file: file)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let arguments = Arguments(context: context, close: {
        close?()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .botMiniAppEmojiStatusRequest
    
    controller.onDeinit = {
        complete(.fail)
    }
    
    controller.validateData = { _ in
        complete(.success)
        close?()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: "Confirm", accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true, customTheme: {
        return .init(listBackground: theme.colors.background)
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



