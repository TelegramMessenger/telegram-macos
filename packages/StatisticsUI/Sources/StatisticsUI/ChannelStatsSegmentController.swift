import Foundation
import AppAnalytics
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AvatarUI
import ShortPeerRow
import LocalAnimations
import GraphUI
import DateUtils
import TelegramIconsTheme
import TelegramMediaUtils
import MessageTextUtils

private final class CenterView : TitledBarView {
    public let segment: CatalinaStyledSegmentController
    public var select:((Int)->Void)? = nil
    public init(controller: ViewController, monetization: Bool, stars: Bool, onlyMonetization: Bool) {
        self.segment = CatalinaStyledSegmentController(frame: NSMakeRect(0, 0, 240, 30))
        super.init(controller: controller)
        self.segment.fitContent = true
        self.segment.fitContentHorizontalPadding = 32

        if !onlyMonetization {
            segment.add(segment: .init(title: strings().statsStatistics, handler: { [weak self] in
                self?.select?(0)
            }))
            
            segment.add(segment: .init(title: strings().statsBoosts, handler: { [weak self] in
                self?.select?(1)
            }))
        }
        if monetization {
            let index = self.segment.count
            segment.add(segment: .init(title: strings().statsMonetization, handler: { [weak self] in
                self?.select?(index)
            }))
        }
        
        if stars {
            let index = self.segment.count
            segment.add(segment: .init(title: strings().statsStars, handler: { [weak self] in
                self?.select?(index)
            }))
        }
        
        self.addSubview(segment.view)
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        segment.theme = CatalinaSegmentTheme(backgroundColor: theme.colors.listBackground, foregroundColor: theme.colors.background, activeTextColor: theme.colors.text, inactiveTextColor: theme.colors.listGrayText)

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        let intrinsic = segment.intrinsicContentWidth
        let available = max(0, frame.width - 60)
        // Enforce a sensible minimum so a single-item segment doesn't look
        // like a tiny chip. The bar can still shrink below this floor on
        // narrow windows (`available` wins) so it never overflows.
        let target = max(180, intrinsic)
        let width = min(target, available)
        let height: CGFloat = 30
        let x = floorToScreenPixels(backingScaleFactor, (frame.width - width) / 2)
        let y = floorToScreenPixels(backingScaleFactor, (frame.height - height) / 2)
        segment.view.frame = NSRect(x: x, y: y, width: width, height: height)
    }
}

public final class ChannelStatsSegmentController : SectionViewController {
    private let stats: ViewController
    private let boosts: ViewController
    private let monetization: ViewController?
    private let stars: ViewController?
    private let context: any AccountContextProtocol
    private let peerId: PeerId
    private let onlyMonetization: Bool
    public init(_ context: any AccountContextProtocol, peerId: PeerId, isChannel: Bool, monetization: Bool = false, stars: Bool = false, onlyMonetization: Bool = false, analyticsContext: AnalyticsContext? = nil) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
        let lifetime = origin.beginPresentation()
        defer { lifetime.end() }
        self.context = context
        self.peerId = peerId
        self.onlyMonetization = onlyMonetization
        if isChannel {
            self.stats = ChannelStatsViewController(context, peerId: peerId, analyticsContext: origin)
            if monetization {
                self.monetization = StatisticsHooks.shared.makeMonetizationController(context, peerId)
            } else {
                self.monetization = nil
            }
            if stars {
                self.stars = StatisticsHooks.shared.makeStarMonetizationController(context, peerId)
            } else {
                self.stars = nil
            }
        } else {
            self.stats = GroupStatsViewController(context, peerId: peerId, analyticsContext: origin)
            self.monetization = nil
            self.stars = nil
        }
        self.boosts = StatisticsHooks.shared.makeBoostStatsController(context, peerId)

        for controller in [stats, boosts] + [self.monetization, self.stars].compactMap({ $0 }) {
            let childOrigin: AnalyticsContext
            if let current = controller.analyticsContext, current.isExcluded || current.scope?.isValid != true {
                childOrigin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: current)
            } else {
                childOrigin = origin
            }
            controller.analyticsContext = childOrigin
        }

        var items:[SectionControllerItem] = []
        if !onlyMonetization {
            items.append(SectionControllerItem(title: { "" }, controller: stats))
            items.append(SectionControllerItem(title: { "" }, controller: boosts))
        }

        if let monetization = self.monetization {
            items.append(SectionControllerItem(title: { "" }, controller: monetization))
        }
        if let stars = self.stars {
            items.append(SectionControllerItem(title: { "" }, controller: stars))
        }
        super.init(sections: items, selected: 0, hasBar: true)
        self.analyticsContext = origin

    }
    
    public override func getCenterBarViewOnce() -> TitledBarView {
        return CenterView(controller: self, monetization: self.monetization != nil, stars: self.stars != nil, onlyMonetization: onlyMonetization)
    }
    

    
    public override var enableBack: Bool {
        return true
    }
    
    public override var supportSwipes: Bool {
        return self.selectedIndex == 0
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        centerView.select = { [weak self] index in
            self?.select(index, true)
        }
        
        self.selectionUpdateHandler = { [weak self] index in
            self?.centerView.segment.set(selected: index, animated: true)
        }
    }
    
    private var centerView: CenterView {
        return self.centerBarView as! CenterView
    }
}
