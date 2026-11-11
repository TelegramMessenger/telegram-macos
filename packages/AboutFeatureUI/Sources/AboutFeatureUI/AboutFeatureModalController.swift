import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import Strings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ChatUI
import PeerInfoUI
import LocalAnimations
import AppAnalytics

public struct AboutFeatureConfiguration {
    public struct Feature {
        let icon: CGImage
        let title: String
        let description: String
        let linkCallback: ((String) -> Bool)?

        public init(icon: CGImage, title: String, description: String, linkCallback: ((String) -> Bool)? = nil) {
            self.icon = icon
            self.title = title
            self.description = description
            self.linkCallback = linkCallback
        }
    }

    let headerImage: CGImage?
    let headerSticker: LocalAnimatedSticker?
    let headerBackgroundColor: NSColor
    let title: String
    let description: String
    let features: [Feature]
    let footerText: String?
    let buttonTitle: String
    let descriptionLinkCallback: ((String) -> Void)?
    let footerLinkCallback: ((String) -> Bool)?
    let buttonCallback: (() -> Void)?

    public init(
        headerImage: CGImage? = nil,
        headerSticker: LocalAnimatedSticker? = nil,
        headerBackgroundColor: NSColor = theme.colors.accent,
        title: String,
        description: String,
        features: [Feature],
        footerText: String? = nil,
        buttonTitle: String,
        descriptionLinkCallback: ((String) -> Void)? = nil,
        footerLinkCallback: ((String) -> Bool)? = nil,
        buttonCallback: (() -> Void)? = nil
    ) {
        self.headerImage = headerImage
        self.headerSticker = headerSticker
        self.headerBackgroundColor = headerBackgroundColor
        self.title = title
        self.description = description
        self.features = features
        self.footerText = footerText
        self.buttonTitle = buttonTitle
        self.descriptionLinkCallback = descriptionLinkCallback
        self.footerLinkCallback = footerLinkCallback
        self.buttonCallback = buttonCallback
    }
}

private extension AboutFeatureConfiguration {
    func preservingAnalyticsContext(_ analyticsContext: AnalyticsContext) -> AboutFeatureConfiguration {
        func guarded<Value, Result>(_ callback: ((Value) -> Result)?) -> ((Value) -> Result)? {
            callback.map { callback in
                return { value in
                    let presentation = analyticsContext.beginPresentation()
                    defer { presentation.end() }
                    return callback(value)
                }
            }
        }
        return AboutFeatureConfiguration(
            headerImage: headerImage,
            headerSticker: headerSticker,
            headerBackgroundColor: headerBackgroundColor,
            title: title,
            description: description,
            features: features.map { feature in
                Feature(icon: feature.icon, title: feature.title, description: feature.description, linkCallback: guarded(feature.linkCallback))
            },
            footerText: footerText,
            buttonTitle: buttonTitle,
            descriptionLinkCallback: guarded(descriptionLinkCallback),
            footerLinkCallback: guarded(footerLinkCallback),
            buttonCallback: buttonCallback.map { callback in
                return {
                    let presentation = analyticsContext.beginPresentation()
                    defer { presentation.end() }
                    callback()
                }
            }
        )
    }
}

private final class AboutFeatureHeaderItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let headerImage: CGImage?
    fileprivate let headerSticker: LocalAnimatedSticker?
    fileprivate let headerBackgroundColor: NSColor
    fileprivate let dismiss: () -> Void
    fileprivate let title: String
    fileprivate let stickerSize = NSMakeSize(100, 100)

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, headerImage: CGImage?, headerSticker: LocalAnimatedSticker?, headerBackgroundColor: NSColor, title: String, dismiss: @escaping () -> Void) {
        self.context = context
        self.title = title
        self.headerImage = headerImage
        self.headerSticker = headerSticker
        self.headerBackgroundColor = headerBackgroundColor
        self.dismiss = dismiss
        super.init(initialSize, stableId: stableId)
    }

    override func viewClass() -> AnyClass {
        return AboutFeatureHeaderView.self
    }

    override var accessibilityLabel: String? {
        return title
    }

    override var height: CGFloat {
        if headerSticker != nil {
            return stickerSize.height + 10
        }
        return (headerImage?.backingSize.height ?? 0) + 10
    }
}

private final class AboutFeatureHeaderView: GeneralRowView {
    private let imageView = ImageView()
    private var stickerView: GeneralRowsAnimatedItemView?
    private let backgroundView = View()
    private let dismiss = ImageButton()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(imageView)
        addSubview(dismiss)

        imageView.isAccessibilityDecorative = true
        dismiss.scaleOnClick = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? AboutFeatureHeaderItem else {
            return
        }

        imageView.image = item.headerImage
        imageView.sizeToFit()

        if let sticker = item.headerSticker {
            let current: GeneralRowsAnimatedItemView
            if let view = stickerView {
                current = view
            } else {
                current = GeneralRowsHooks.shared.makeStickerHeaderView(item.stickerSize.bounds)
                stickerView = current
                addSubview(current, positioned: .below, relativeTo: dismiss)
            }
            current.updateStickerHeader(with: sticker.file, size: item.stickerSize, context: item.context, parent: nil, table: item.table, parameters: GeneralRowsHooks.shared.localStickerParameters(sticker), animated: animated, positionFlags: nil, approximateSynchronousValue: false)
        } else if let view = stickerView {
            view.removeFromSuperview()
            stickerView = nil
        }

        backgroundView.backgroundColor = item.headerBackgroundColor

        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)

        dismiss.removeAllHandlers()
        dismiss.setSingle(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .Click)

        needsLayout = true
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        imageView.centerX(y: 10)
        stickerView?.centerX(y: 10)
        dismiss.setFrameOrigin(NSMakePoint(10, 10))
    }
}

private final class AboutFeatureFeaturesItem: GeneralRowItem {

    struct FeatureLayout {
        let icon: CGImage
        let titleLayout: TextViewLayout
        let descriptionLayout: TextViewLayout
        let linkCallback: ((String) -> Bool)?

        var height: CGFloat {
            return max(24, titleLayout.layoutSize.height + 4 + descriptionLayout.layoutSize.height)
        }
    }

    let features: [FeatureLayout]

    init(_ initialSize: NSSize, stableId: AnyHashable, features: [AboutFeatureConfiguration.Feature], dismiss: @escaping () -> Void) {
        var featureLayouts: [FeatureLayout] = []

        for feature in features {
            let titleAttr = NSAttributedString.initialize(string: feature.title, color: theme.colors.text, font: .medium(.text))
            let titleLayout = TextViewLayout(titleAttr)
            titleLayout.measure(width: initialSize.width - 80)

            let descAttr = parseMarkdownIntoAttributedString(feature.description, attributes: MarkdownAttributes(
                body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.grayText),
                bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.colors.grayText),
                link: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.link),
                linkAttribute: { contents in
                    return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents, { _ in }))
                }
            )).detectBold(with: .medium(.text))
            let descLayout = TextViewLayout(descAttr)
            descLayout.measure(width: initialSize.width - 80)
            descLayout.interactions = .init(processURL: { link in
                if let link = link as? AboutFeatureInAppLinkValue, case let .callback(contents, _) = link.aboutFeatureInAppLink {
                    if feature.linkCallback?(contents) == true {
                        dismiss()
                    }
                }
            })

            featureLayouts.append(FeatureLayout(
                icon: feature.icon,
                titleLayout: titleLayout,
                descriptionLayout: descLayout,
                linkCallback: feature.linkCallback
            ))
        }

        self.features = featureLayouts
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    override func viewClass() -> AnyClass {
        return AboutFeatureFeaturesView.self
    }

    override var accessibilityLabel: String? {
        return features.map { $0.titleLayout.attributedString.string }.joined(separator: ", ")
    }

    override var height: CGFloat {
        var height: CGFloat = 0
        for (i, feature) in features.enumerated() {
            height += feature.height
            if i != features.count - 1 {
                height += 16
            }
        }
        return height
    }
}

private final class AboutFeatureFeaturesView: GeneralContainableRowView {

    private final class FeatureView: View {
        private let iconView = ImageView()
        private let titleView = TextView()
        private let descriptionView = TextView()

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(iconView)
            addSubview(titleView)
            addSubview(descriptionView)

            iconView.isAccessibilityDecorative = true
            titleView.userInteractionEnabled = false
            titleView.isSelectable = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(feature: AboutFeatureFeaturesItem.FeatureLayout) {
            iconView.image = feature.icon
            iconView.sizeToFit()
            titleView.update(feature.titleLayout)
            descriptionView.update(feature.descriptionLayout)
        }

        override func layout() {
            super.layout()
            iconView.setFrameOrigin(NSMakePoint(0, 0))
            titleView.setFrameOrigin(NSMakePoint(40, 0))
            descriptionView.setFrameOrigin(NSMakePoint(40, titleView.frame.maxY + 4))
        }
    }

    private let featuresView = View()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(featuresView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? AboutFeatureFeaturesItem else {
            return
        }

        while featuresView.subviews.count > item.features.count {
            featuresView.subviews.last?.removeFromSuperview()
        }
        while featuresView.subviews.count < item.features.count {
            featuresView.addSubview(FeatureView(frame: .zero))
        }

        var y: CGFloat = 0
        for (i, feature) in item.features.enumerated() {
            let view = featuresView.subviews[i] as! FeatureView
            view.update(feature: feature)
            view.setFrameSize(NSMakeSize(frame.width - 40, feature.height))
            view.setFrameOrigin(NSMakePoint(0, y))
            y += feature.height
            if i != item.features.count - 1 {
                y += 16
            }
        }

        featuresView.setFrameSize(NSMakeSize(frame.width - 40, y))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        featuresView.centerX(y: 0)
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let dismiss: () -> Void
    let configuration: AboutFeatureConfiguration

    init(context: any AccountContextProtocol, dismiss: @escaping () -> Void, configuration: AboutFeatureConfiguration) {
        self.context = context
        self.dismiss = dismiss
        self.configuration = configuration
    }
}

private struct State: Equatable {
    static func == (lhs: State, rhs: State) -> Bool {
        return true
    }
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    let config = arguments.configuration

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return AboutFeatureHeaderItem(initialSize, stableId: stableId, context: arguments.context, headerImage: config.headerImage, headerSticker: config.headerSticker, headerBackgroundColor: config.headerBackgroundColor, title: config.title, dismiss: arguments.dismiss)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(15)))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("**\(config.title)**"), data: .init(color: theme.colors.text, detectBold: true, viewType: .plain(.single), fontSize: 18, centerViewAlignment: true, alignment: .center)))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(config.description, linkHandler: { link in
        config.descriptionLinkCallback?(link)
    }), data: .init(color: theme.colors.grayText, viewType: .plain(.single), fontSize: .text, centerViewAlignment: true, alignment: .center)))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    if !config.features.isEmpty {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("features"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return AboutFeatureFeaturesItem(initialSize, stableId: stableId, features: config.features, dismiss: arguments.dismiss)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(15)))
        sectionId += 1
    }

    if let footerText = config.footerText {
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(footerText, linkHandler: { link in
            if config.footerLinkCallback?(link) == true {
                arguments.dismiss()
            }
        }), data: .init(color: theme.colors.grayText, viewType: .plain(.single), centerViewAlignment: true, alignment: .center)))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    return entries
}

public func AboutFeatureModalController(context: any AccountContextProtocol, configuration: AboutFeatureConfiguration, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {

    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let configuration = configuration.preservingAnalyticsContext(origin)
    let actionsDisposable = DisposableSet()

    let initialState = State()

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    _ = updateState

    var close: (() -> Void)? = nil

    let arguments = Arguments(context: context, dismiss: {
        close?()
    }, configuration: configuration)

    let signal = origin.preservingPresentation(statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsContext = origin
    controller.analyticsScreen = .appFeatureInfo

    controller.onDeinit = {
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        actionsDisposable.dispose()
    }
    
    controller.validateData = { _ in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        close?()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: configuration.buttonTitle, accept: { [weak controller] in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        configuration.buttonCallback?()
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    modalController.analyticsContext = origin
    modalController._hasBorder = false

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        modalController?.close()
    })

    close = { [weak modalController] in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        modalController?.modal?.close()
    }

    return modalController
}

public func showAboutCocoonModal<Context: AccountContextProtocol>(context: Context, analyticsContext: AnalyticsContext? = nil) {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let openLink: (String) -> Bool = { link in
        let current = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: origin)
        let presentation = current.beginPresentation()
        defer { presentation.end() }
        let parsed = ChatHistoryLink.inApp(for: link.nsstring, context: context, openInfo: { peerId, toChat, messageId, initialAction in
            let destination = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: current)
            let presentation = destination.beginPresentation()
            defer { presentation.end() }
            if toChat || initialAction != nil {
                let controller = ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: .init(messageId: messageId), initialAction: initialAction)
                controller.inheritAnalyticsContext(destination)
                context.bindings.rootNavigation().push(controller)
            } else {
                PeerInfoController<Context>.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId, analyticsContext: destination)
            }
            context.window.makeKeyAndOrderFront(nil)
        }, confirm: false)
        ChatHistoryLink.execute(inapp: parsed, analyticsContext: current)
        if case .external = parsed.chatHistoryInAppLink {
            return false
        }
        return true
    }
    let configuration = AboutFeatureConfiguration(
        headerImage: TelegramThemeHooks.shared.image(.cocoon120).precomposed(),
        headerBackgroundColor: .clear,
        title: strings().aboutCocoonTitle,
        description: strings().aboutCocoonDescription,
        features: [
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionLock).precomposed(theme.colors.accent),
                title: strings().aboutCocoonFeaturePrivateTitle,
                description: strings().aboutCocoonFeaturePrivateDescription
            ),
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionStatistics).precomposed(theme.colors.accent),
                title: strings().aboutCocoonFeatureEfficientTitle,
                description: strings().aboutCocoonFeatureEfficientDescription
            ),
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionGift).precomposed(theme.colors.accent),
                title: strings().aboutCocoonFeatureForEveryoneTitle,
                description: strings().aboutCocoonFeatureForEveryoneDescription,
                linkCallback: openLink
            )
        ],
        footerText: strings().aboutCocoonFooter,
        buttonTitle: strings().monetizationIntroUnderstood,
        footerLinkCallback: openLink
    )

    showModal(with: AboutFeatureModalController(context: context, configuration: configuration, analyticsContext: origin), for: context.window)
}

public func showDisableSharingModal(context: any AccountContextProtocol, peerId: PeerId, toggle: @escaping(Bool) -> Void) {
    let isPremium = context.isPremium
    let configuration = AboutFeatureConfiguration(
        headerImage: TelegramThemeHooks.shared.image(.hand120).precomposed(),
        headerBackgroundColor: .clear,
        title: strings().aboutFeatureDisableSharingTitle,
        description: "",
        features: [
            .init(icon: TelegramThemeHooks.shared.image(.iconOptionNoScreenshots).precomposed(theme.colors.accent), title: strings().aboutFeatureDisableSharingNoScreenshots, description: strings().aboutFeatureDisableSharingNoScreenshotsDesc),
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionNoForwarding).precomposed(theme.colors.accent),
                title: strings().aboutFeatureDisableSharingNoForwarding,
                description: strings().aboutFeatureDisableSharingNoForwardingDesc
            ),
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionNoSaving).precomposed(theme.colors.accent),
                title: strings().aboutFeatureDisableSharingNoSaving,
                description: strings().aboutFeatureDisableSharingNoSavingDesc
            )
        ],
        buttonTitle: isPremium ? strings().aboutFeatureDisableSharingDisableButton : strings().aboutFeatureDisableSharingUnlockButton,
        buttonCallback: {
            if !isPremium {
                FeatureNavigationHooks.shared.showPremiumBoarding(context, context.window, .noforwards, true, nil)
                return
            }
            toggle(true)
        }
    )

    let controller = AboutFeatureModalController(context: context, configuration: configuration)
    showModal(with: controller, for: context.window)
    if !isPremium {
        controller.modal?.interactions?.updateDone { button in
            let lockIcon = TelegramThemeHooks.shared.image(.iconPremiumLock).precomposed(.white)
            button.set(image: lockIcon, for: .Normal)
            button.autohighlight = false
            button.buttonImageInset = -5
        }
    }
}

public func showFirstGramsModal(context: any AccountContextProtocol, window: Window) {
    let description: String
    if let rate = context.appConfiguration.data?["ton_usd_rate"] as? Double, rate.isFinite, rate > 0 {
        let rateText = "\(rate)".prettyCurrencyNumberUsd
        description = strings().aboutFeatureModalControllerFirstGramsRate(rateText)
    } else {
        description = strings().aboutFeatureModalControllerFirstGramsYouCan
    }
    let configuration = AboutFeatureConfiguration(
        headerSticker: LocalAnimatedSticker.diamond,
        headerBackgroundColor: .clear,
        title: strings().aboutFeatureModalControllerFirstGramsTitle,
        description: description,
        features: [
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionTelegram).precomposed(theme.colors.accent),
                title: strings().aboutFeatureModalControllerFirstGramsSend,
                description: strings().aboutFeatureModalControllerFirstGramsSendInfo
            ),
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionCash).precomposed(theme.colors.accent),
                title: strings().aboutFeatureModalControllerFirstGramsTrade,
                description: strings().aboutFeatureModalControllerFirstGramsTradeInfo
            ),
            .init(
                icon: TelegramThemeHooks.shared.image(.iconOptionGram).precomposed(theme.colors.accent),
                title: strings().aboutFeatureModalControllerFirstGramsStore,
                description: strings().aboutFeatureModalControllerFirstGramsStoreInfo
            )
        ],
        buttonTitle: strings().aboutFeatureModalControllerFirstGramsGotIt
    )

    showModal(with: AboutFeatureModalController(context: context, configuration: configuration), for: window)
}
