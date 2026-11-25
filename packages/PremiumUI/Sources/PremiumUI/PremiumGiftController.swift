import Cocoa
import Foundation
import TGUIKit
import TelegramMedia
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import CurrencyFormat
import SceneEffects
import InAppPurchaseManager
import InlineStickers
import ObjcUtils
import ChatModeTypes



public struct PremiumGiftOption : Equatable {
    
    public let option: PremiumGiftProduct
    public let storeProduct: InAppPurchaseManager.Product?
    public let options: [PremiumGiftProduct]
    public let storeProducts:[InAppPurchaseManager.Product]
    public let configuration: PremiumPromoConfiguration
    
    public var titleString: String {
        return strings().timerMonthsOther(Int(option.months))
    }
    
    
    public var discountString: Int {
        
        let amount = storeProduct?.priceCurrencyAndAmount.amount ?? option.giftOption.amount
        
        let amountValue: CGFloat = CGFloat(amount)
        let monthsValue: CGFloat = CGFloat(option.months)
        let optionMonthly: Int64 = Int64(amountValue / monthsValue)
        
        let highestOptionMonthly:Int64 = options.map { option in
            let store = self.storeProducts.first(where: { $0.id == option.storeProduct?.id })
            return Int64((CGFloat(store?.priceCurrencyAndAmount.amount ?? option.giftOption.amount) / CGFloat(option.months)))
        }.max()!
        
        
        let highestMonthlyValue: Float = Float(highestOptionMonthly)
        let optionMonthlyValue: Float = Float(optionMonthly)
        let discountFraction: Float = (highestMonthlyValue - optionMonthlyValue) / highestMonthlyValue
        let discountPercent: Int = Int(floor(discountFraction * 100.0))
        return discountPercent
    }
    
    public var priceString: String {
        if let storeProduct = storeProduct {
            return formatCurrencyAmount(storeProduct.priceCurrencyAndAmount.amount, currency: storeProduct.priceCurrencyAndAmount.currency)
        }
        return formatCurrencyAmount(option.giftOption.amount, currency: option.giftOption.currency)
    }
    public var priceDiscountString: String {
        if let storeProduct = storeProduct {
            
            let (currency, amount) = storeProduct.priceCurrencyAndAmount
            let optionMonthly = Int64((CGFloat(amount) / CGFloat(option.months)))
            return strings().premiumGiftMonth(formatCurrencyAmount(optionMonthly, currency: currency))
        }
        
        let optionMonthly = Int64((CGFloat(option.giftOption.amount) / CGFloat(option.months)))
        return strings().premiumGiftMonth(formatCurrencyAmount(optionMonthly, currency: option.giftOption.currency))
        
    }
    public init(option: PremiumGiftProduct, storeProduct: InAppPurchaseManager.Product?, options: [PremiumGiftProduct], storeProducts: [InAppPurchaseManager.Product], configuration: PremiumPromoConfiguration) {
        self.option = option
        self.storeProduct = storeProduct
        self.options = options
        self.storeProducts = storeProducts
        self.configuration = configuration
    }
}




private struct State : Equatable {
    public var peer: PeerEquatable?
    public var options: [PremiumGiftProduct]
    public var option: PremiumGiftProduct
    public var premiumConfiguration: PremiumPromoConfiguration
    public var premiumProducts: [InAppPurchaseManager.Product] = []
    public var canMakePayment: Bool
    public var values: [PremiumGiftOption] {
        
        #if APP_STORE
        return self.options.compactMap { value in
            let storeProduct = self.premiumProducts.first(where: { $0.id == value.storeProduct?.id })
            if let storeProduct = storeProduct {
                return .init(option: value, storeProduct: storeProduct, options: self.options, storeProducts: self.premiumProducts, configuration: self.premiumConfiguration)
            } else {
                return nil
            }
        }
        #endif
        
        return self.options.map({ value in
            let storeProduct = self.premiumProducts.first(where: { $0.id == value.storeProduct?.id })
            return .init(option: value, storeProduct: storeProduct, options: self.options, storeProducts: self.premiumProducts, configuration: self.premiumConfiguration)
        })
    }
    public var value: PremiumGiftOption {
        let storeProduct = self.premiumProducts.first(where: { $0.id == self.option.storeProduct?.id })
        return .init(option: self.option, storeProduct: storeProduct, options: self.options, storeProducts: self.premiumProducts, configuration: self.premiumConfiguration)
    }
}


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let select:(PremiumGiftOption)->Void
    public let openInfo:(PeerId, Bool, MessageId?, ChatInitialAction?)->Void
    public let buy:(String)->Void
    public init(context: (any AccountContextProtocol), select:@escaping(PremiumGiftOption)->Void, openInfo:@escaping(PeerId, Bool, MessageId?, ChatInitialAction?)->Void, buy:@escaping(String)->Void) {
        self.select = select
        self.context = context
        self.openInfo = openInfo
        self.buy = buy
    }
}

private let _id_message = InputDataIdentifier("_id_message")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(35)))
    sectionId += 1
   
    if let peer = state.peer {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: InputDataEquatable(peer), comparable: nil, item: { initialSize, stableId in
            return PremiumGiftHeaderItem(initialSize, stableId: stableId, context: arguments.context, source: .gift(peer.peer))
        }))
        index += 1
    }
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("discount"), equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
        return PremiumGiftRowItem(initialSize, stableId: stableId, viewType: .singleItem, context: arguments.context, selectedOption: state.value, options: state.values, select: arguments.select)
    }))
    index += 1
    
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
//  
//    entries.append(.input(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_message, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: "Message", filter: { $0 }, limit: 140))
//    index += 1
//    
//    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("You can include a message with your gift."), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
//    index += 1
//    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

private final class PremiumBoardingView : View {
    
    private final class AcceptView : Control {
        private let gradient: PremiumGradientView = PremiumGradientView(frame: .zero)
        private let shimmer = ShimmerEffectView()
        private let textView = TextView()
        private let container = View()
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(gradient)
            addSubview(shimmer)
            shimmer.isStatic = true
            container.addSubview(textView)
            addSubview(container)
            scaleOnClick = true
            
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        
        public override func layout() {
            super.layout()
            
            
            gradient.frame = bounds
            shimmer.frame = bounds
            
            shimmer.updateAbsoluteRect(bounds, within: frame.size)
            shimmer.update(backgroundColor: .clear, foregroundColor: .clear, shimmeringColor: NSColor.white.withAlphaComponent(0.3), shapes: [.roundedRect(rect: bounds, cornerRadius: frame.height / 2)], horizontal: true, size: frame.size)
            
            container.center()
            textView.center()
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func update(animated: Bool, state: State) -> NSSize {
            
            
            let text: String
            if state.canMakePayment {
                text = strings().premiumGiftButtonText(state.value.priceString)
            } else {
                text = strings().premiumBoardingPaymentNotAvailalbe
            }
            
            let layout = TextViewLayout(.initialize(string: text, color: NSColor.white, font: .medium(.text)))
            layout.measure(width: .greatestFiniteMagnitude)
            textView.update(layout)
                        
            container.setFrameSize(layout.layoutSize)
            
            layer?.cornerRadius = 20
            
            let size = NSMakeSize(container.frame.width + 100, 40)

            needsLayout = true
            
            self.userInteractionEnabled = state.canMakePayment
            
            self.alphaValue = state.canMakePayment ? 1.0 : 0.7

                        
            return size
        }
    }

    
    public final class HeaderView: View {
        public let dismiss = ImageButton()
        private let container = View()
        private let titleView = TextView()
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(container)
            addSubview(dismiss)
            
            dismiss.scaleOnClick = true
            dismiss.autohighlight = false
            
            dismiss.set(image: theme.icons.glass_close, for: .Normal)
            dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
            dismiss.setGlassEffect(size: NSMakeSize(36, 36))
            dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
            
            titleView.userInteractionEnabled = false
            titleView.isSelectable = false
            titleView.isEventLess = true
            
            container.backgroundColor = theme.colors.background
            container.border = [.Bottom]

            let layout = TextViewLayout(.initialize(string: strings().premiumBoardingTitle, color: theme.colors.text, font: .medium(.header)))
            layout.measure(width: 300)
            
            titleView.update(layout)
            container.addSubview(titleView)
        }
        
        public func update(isHidden: Bool, animated: Bool) {
            container.change(opacity: isHidden ? 0 : 1, animated: animated)
        }
        
        public override func layout() {
            super.layout()
            dismiss.centerY(x: 10)
            container.frame = bounds
            titleView.center()
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    
    private let headerView: HeaderView = HeaderView(frame: .zero)
    
    public let tableView = TableView()
    private let bottomView: View = View()
    private let acceptView = AcceptView(frame: .zero)
    private let bottomBorder = View()
    
    private let containerView = View()
    public var dismiss:(()->Void)?
    public var accept:(()->Void)?
    
    private var state: State?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        containerView.addSubview(tableView)
        containerView.addSubview(headerView)
        containerView.addSubview(bottomView)
        bottomView.addSubview(acceptView)
        bottomView.addSubview(bottomBorder)
        addSubview(containerView)
        
        tableView.getBackgroundColor = {
            theme.colors.listBackground
        }
                
        bottomBorder.backgroundColor = theme.colors.border
        
        
        tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateScroll(position, animated: true)
        }))
        
        headerView.dismiss.set(handler: { [weak self] _ in
            self?.dismiss?()
        }, for: .Click)
        
        acceptView.set(handler: { [weak self] _ in
            self?.accept?()
        }, for: .Click)
    }
    
    private func updateScroll(_ scroll: ScrollPosition, animated: Bool) {
        let offset = scroll.rect.minY - tableView.frame.height
                
        if scroll.rect.minY >= tableView.listHeight || scroll.rect.minY == 0 {
            bottomBorder.change(opacity: 0, animated: animated)
            bottomView.backgroundColor = theme.colors.listBackground
            if animated {
                bottomView.layer?.animateBackground()
            }
        } else {
            bottomBorder.change(opacity: 1, animated: animated)
            bottomView.backgroundColor = theme.colors.background
            if animated {
                bottomView.layer?.animateBackground()
            }
        }
        
        headerView.update(isHidden: offset <= 127, animated: animated)
    }
    
    public override func layout() {
        super.layout()
        updateLayout(size: self.frame.size, transition: .immediate)
        self.updateScroll(tableView.scrollPosition().current, animated: false)
    }
    
    public var bottomHeight: CGFloat {
        return 60
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: headerView, frame: NSMakeRect(0, 0, size.width, 50))
        transition.updateFrame(view: containerView, frame: bounds)
        
        transition.updateFrame(view: tableView, frame: NSMakeRect(0, 0, size.width, size.height - bottomHeight))
        transition.updateFrame(view: bottomView, frame: NSMakeRect(0, tableView.frame.maxY, size.width, bottomHeight))
                    
        transition.updateFrame(view: acceptView, frame: acceptView.centerFrame())
        transition.updateFrame(view: bottomBorder, frame: NSMakeRect(0, 0, bottomView.frame.width, .borderSize))

        
    }
    
    public func contentSize(maxSize size: NSSize) -> NSSize {
        return NSMakeSize(size.width, min(tableView.listHeight + bottomHeight, size.height))
    }
    
    public func update(animated: Bool, arguments: Arguments, state: State) {
        self.state = state
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        
        let size = acceptView.update(animated: animated, state: state)
        acceptView.setFrameSize(NSMakeSize(frame.width - 60, size.height))
        
        updateLayout(size: frame.size, transition: transition)
        
        self.updateScroll(tableView.scrollPosition().current, animated: false)
    }
        
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}





