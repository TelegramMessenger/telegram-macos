import Cocoa
import ThemeSettings
import TGUIKit
import TelegramCore
import ColorPalette
import Postbox
import SwiftSignalKit
import InAppSettings
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import FoundationUtils
import TelegramMediaUtils
import TelegramLinks
import ChatHistoryModel
import FilePanels
import WallpaperUI
import AppAnalytics


public enum ThemePreviewSource {
    case localTheme(TelegramPresentationTheme, name: String?)
    case cloudTheme(TelegramTheme)
}


private final class ThemeChatPreviewRowItem: GeneralRowItem {
    public let previewTheme: TelegramPresentationTheme
    public let context: any AccountContextProtocol
    public let bubbled: Bool
    public let toggleBubbled: (Bool) -> Void
    public let applyTheme: () -> Void
    public let dismiss: () -> Void
    public let share: (() -> Void)?
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, previewTheme: TelegramPresentationTheme, bubbled: Bool, toggleBubbled: @escaping (Bool) -> Void, applyTheme: @escaping () -> Void, dismiss: @escaping () -> Void, share: (() -> Void)?) {
        self.previewTheme = previewTheme
        self.context = context
        self.bubbled = bubbled
        self.toggleBubbled = toggleBubbled
        self.applyTheme = applyTheme
        self.dismiss = dismiss
        self.share = share
        super.init(initialSize, height: 350, stableId: stableId)
    }
    public override func viewClass() -> AnyClass {
        return ThemeChatPreviewRowView.self
    }
    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonTheme
    }
}

private final class ThemeChatPreviewRowView: TableRowView {
    private let backgroundView = BackgroundView(frame: .zero)
    private let tableView = TableView(frame: .zero, isFlipped: false)
    private let bubblesCheckbox = WallpaperCheckboxView(frame: NSMakeRect(0, 0, 100, 28), title: strings().appearanceSettingsChatViewBubbles)
    private let applyButton = TextButton()
    private let dismissButton = ImageButton()
    private let shareButton = ImageButton()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backgroundView.useSharedAnimationPhase = false
        backgroundView.checkDarkPattern = false
        addSubview(backgroundView)
        backgroundView.addSubview(tableView)
        addSubview(bubblesCheckbox)

        applyButton.set(font: .medium(.text), for: .Normal)
        applyButton.set(color: .white, for: .Normal)
        applyButton.set(text: strings().modalSet, for: .Normal)
        applyButton.layer?.cornerRadius = 10
        applyButton.setGlassEffect(tintColor: theme.colors.accent)
        addSubview(applyButton)

        dismissButton.set(image: theme.icons.glass_close, for: .Normal)
        dismissButton.setGlassEffect()
        dismissButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismissButton.setAccessibilityLabel(strings().voiceOverCommonClose)
        addSubview(dismissButton)

        shareButton.set(image: TelegramThemeHooks.shared.image(.iconShareStickerPack).precomposed(theme.colors.text), for: .Normal)
        shareButton.setGlassEffect()
        shareButton.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        shareButton.setAccessibilityLabel(strings().voiceOverCommonShare)
        addSubview(shareButton)

        tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] _ in
            self?.tableView.enumerateVisibleViews(with: { view in
                if let view = view as? AppearanceChatPreviewRowView {
                    view.updateBackground(animated: false, item: view.item)
                }
            })
        }))
        tableView.afterSetupItem = { view, item in
            if let view = view as? AppearanceChatPreviewRowView {
                view.updateBackground(animated: false, item: view.item)
            }
        }
    }

    public required init?(coder: NSCoder) {
        fatalError()
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? ThemeChatPreviewRowItem else { return }
        let previewTheme = item.previewTheme
        let context = item.context

        bubblesCheckbox.isSelected = item.bubbled
        bubblesCheckbox.set(handler: { [weak item] _ in
            guard let item else { return }
            item.toggleBubbled(!item.bubbled)
        }, for: .Click)

        applyButton.removeAllHandlers()
        applyButton.set(handler: { [weak item] control in
            item?.applyTheme()
        }, for: .Click)

        dismissButton.removeAllHandlers()
        dismissButton.set(handler: { [weak item] control in
            item?.dismiss()
        }, for: .Click)

        shareButton.removeAllHandlers()
        shareButton.isHidden = item.share == nil
        shareButton.set(handler: { [weak item] control in
            item?.share?()
        }, for: .Click)

        backgroundView.backgroundMode = previewTheme.controllerBackgroundMode

        tableView.getBackgroundColor = {
            previewTheme.bubbled ? .clear : previewTheme.chatBackground
        }
        tableView.removeAll()
        tableView.updateLocalizationAndTheme(theme: previewTheme)
        tableView.backgroundColor = previewTheme.colors.background
        _ = tableView.addItem(item: GeneralRowItem(frame.size, height: 10, stableId: 0, backgroundColor: .clear))

        let chatInteraction = SettingsHooks.shared.makeChatPreviewContext(context, PeerId(0), false)
        chatInteraction.getGradientOffsetRect = { [weak self] in
            guard let self else { return .zero }
            let offset = self.tableView.scrollPosition().current.rect.origin
            return CGRect(origin: offset, size: NSMakeSize(350, 350))
        }

        let fromUser1 = TelegramUser(id: PeerId(1), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName1, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)

        let fromUser2 = TelegramUser(id: PeerId(2), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName2, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)

        let peers = SimpleDictionary([fromUser2.id: fromUser2, fromUser1.id: fromUser1] as [PeerId: Peer])

        let firstMessage = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 18 + 60*60*18, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser1, text: strings().appearanceSettingsChatPreview1, attributes: [], media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])

        let secondMessage = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 0), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 20 + 60*60*18, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser2, text: strings().appearanceSettingsChatPreview2, attributes: [ReplyMessageAttribute(messageId: firstMessage.id, threadMessageId: nil, quote: nil, isQuote: false, innerSubject: nil)], media: [], peers: peers, associatedMessages: SimpleDictionary([firstMessage.id: firstMessage]), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])

        let thirdMessage = Message(stableId: 2, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: 60 * 22 + 60*60*18, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser1, text: strings().appearanceSettingsChatPreview3, attributes: [], media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])

        let renderType: ChatItemRenderType = previewTheme.bubbled ? .bubble : .list
        let firstEntry: ChatHistoryEntry = .MessageEntry(firstMessage, MessageIndex(firstMessage), true, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        let secondEntry: ChatHistoryEntry = .MessageEntry(secondMessage, MessageIndex(secondMessage), true, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))
        let thirdEntry: ChatHistoryEntry = .MessageEntry(thirdMessage, MessageIndex(thirdMessage), true, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))

        let item1 = SettingsHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, firstEntry, previewTheme)
        let item2 = SettingsHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, secondEntry, previewTheme)
        let item3 = SettingsHooks.shared.makeChatPreviewItem(frame.size, chatInteraction, thirdEntry, previewTheme)

        _ = item1.makeSize(frame.width, oldWidth: 0)
        _ = item2.makeSize(frame.width, oldWidth: 0)
        _ = item3.makeSize(frame.width, oldWidth: 0)

        tableView.beginTableUpdates()
        _ = tableView.addItem(item: item3)
        _ = tableView.addItem(item: item2)
        _ = tableView.addItem(item: item1)
        tableView.endTableUpdates()

        tableView.enumerateVisibleViews(with: { view in
            if let view = view as? AppearanceChatPreviewRowView {
                view.updateBackground(animated: false, item: view.item)
            }
        })

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        backgroundView.frame = bounds
        tableView.frame = bounds
        bubblesCheckbox.centerX(y: 12 + (36 - bubblesCheckbox.frame.height) / 2)

        let applyWidth = frame.width - 24
        applyButton.setFrameSize(NSMakeSize(applyWidth, 40))
        applyButton.centerX(y: frame.height - applyButton.frame.height - 12)

        tableView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: applyButton.frame.height + 24, right: 0)

        dismissButton.setFrameOrigin(NSMakePoint(12, 12))
        shareButton.setFrameOrigin(NSMakePoint(frame.width - shareButton.frame.width - 12, 12))
    }
}


private final class Arguments {
    public let context: any AccountContextProtocol
    public let toggleBubbled: (Bool) -> Void
    public let applyTheme: () -> Void
    public let dismiss: () -> Void
    public let share: (() -> Void)?
    public init(context: any AccountContextProtocol, toggleBubbled: @escaping (Bool) -> Void, applyTheme: @escaping () -> Void, dismiss: @escaping () -> Void, share: (() -> Void)?) {
        self.context = context
        self.toggleBubbled = toggleBubbled
        self.applyTheme = applyTheme
        self.dismiss = dismiss
        self.share = share
    }
}

private struct State: Equatable {
    public var previewTheme: TelegramPresentationTheme
    public var bubbled: Bool

    public static func == (lhs: State, rhs: State) -> Bool {
        return lhs.previewTheme === rhs.previewTheme && lhs.bubbled == rhs.bubbled
    }
}

private let _id_preview = InputDataIdentifier("preview")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    let sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_preview, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return ThemeChatPreviewRowItem(initialSize, stableId: stableId, context: arguments.context, previewTheme: state.previewTheme, bubbled: state.bubbled, toggleBubbled: arguments.toggleBubbled, applyTheme: arguments.applyTheme, dismiss: arguments.dismiss, share: arguments.share)
    }))
    index += 1

    return entries
}


public func ThemePreviewModalController(context: any AccountContextProtocol, source: ThemePreviewSource) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let baseTheme: TelegramPresentationTheme
    let shareLink: String?

    switch source {
    case let .localTheme(t, _):
        baseTheme = t.withUpdatedChatMode(true).withUpdatedBackgroundSize(NSMakeSize(350, 350))
        shareLink = nil
    case let .cloudTheme(t):
        baseTheme = theme
        shareLink = context.meUrlPrefix + "addtheme/\(t.slug)"
    }

    let initialState = State(previewTheme: baseTheme, bubbled: true)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)? = nil

    let applyTheme: () -> Void = {
        let state = stateValue.with { $0 }
        let currentTheme = state.previewTheme
        let colors = currentTheme.colors

        let cloudTheme: TelegramTheme?
        if case let .cloudTheme(t) = source {
            cloudTheme = t
        } else {
            cloudTheme = nil
        }

        _ = updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
            var settings = settings
                .withUpdatedPalette(colors)
                .updateWallpaper { _ in currentTheme.wallpaper }
                .withUpdatedCloudTheme(cloudTheme)
                .withUpdatedBubbled(currentTheme.bubbled)

            let defaultTheme: DefaultTheme
            if let cloudTheme = cloudTheme {
                defaultTheme = DefaultTheme(local: colors.parent, cloud: DefaultCloudTheme(cloud: cloudTheme, palette: colors, wallpaper: currentTheme.wallpaper.associated ?? AssociatedWallpaper(cloud: currentTheme.wallpaper.associated?.cloud, wallpaper: currentTheme.wallpaper.wallpaper)))
            } else {
                defaultTheme = DefaultTheme(local: colors.parent, cloud: nil)
            }

            if colors.isDark {
                settings = settings.withUpdatedDefaultDark(defaultTheme)
            } else {
                settings = settings.withUpdatedDefaultDay(defaultTheme)
            }
            settings = settings.withUpdatedDefaultIsDark(colors.isDark)
                .saveDefaultAccent(color: PaletteAccentColor(colors.accent, colors.bubbleBackground_outgoing))
                .saveDefaultWallpaper()
                .withSavedAssociatedTheme()
            return settings
        }).start()

        close?()
    }

    let shareAction: (() -> Void)? = shareLink != nil ? {
        if let link = shareLink {
            SettingsHooks.shared.shareLink(context, link)
        }
    } : nil

    let arguments = Arguments(context: context, toggleBubbled: { bubbled in
        updateState { state in
            var state = state
            state.bubbled = bubbled
            state.previewTheme = state.previewTheme.withUpdatedChatMode(bubbled).withUpdatedBackgroundSize(NSMakeSize(350, 350))
            return state
        }
    }, applyTheme: {
        applyTheme()
    }, dismiss: {
        close?()
    }, share: shareAction)

    if case let .cloudTheme(cloudTheme) = source {
        if let settings = cloudTheme.effectiveSettings {
            let palette = settings.palette
            let wallpaper: Wallpaper
            let cloud = settings.wallpaper
            if let cloud = cloud {
                wallpaper = Wallpaper(cloud)
            } else {
                wallpaper = settings.baseTheme == .classic ? .builtin : .none
            }
            actionsDisposable.add(moveWallpaperToCache(postbox: context.account.postbox, wallpaper: wallpaper).start(next: { wallpaper in
                updateState { state in
                    var state = state
                    state.previewTheme = theme
                        .withUpdatedColors(palette)
                        .withUpdatedWallpaper(ThemeWallpaper(wallpaper: wallpaper, associated: AssociatedWallpaper(cloud: cloud, wallpaper: wallpaper)))
                        .withUpdatedChatMode(state.bubbled)
                        .withUpdatedBackgroundSize(WallpaperDimensions.aspectFilled(NSMakeSize(600, 600)))
                    return state
                }
            }))
        } else if let file = cloudTheme.file {
            let signal = loadCloudPaletteAndWallpaper(context: context, file: file)
            actionsDisposable.add((signal |> deliverOnMainQueue).start(next: { data in
                if let (palette, wallpaper, cloud) = data {
                    updateState { state in
                        var state = state
                        state.previewTheme = theme
                            .withUpdatedColors(palette)
                            .withUpdatedWallpaper(ThemeWallpaper(wallpaper: wallpaper, associated: AssociatedWallpaper(cloud: cloud, wallpaper: wallpaper)))
                            .withUpdatedChatMode(state.bubbled)
                        return state
                    }
                } else {
                    close?()
                    alert(for: context.window, info: strings().unknownError)
                }
            }))
            actionsDisposable.add(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.media(media: AnyMediaReference.standalone(media: file), resource: file.resource)).start())
        }
    }

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .settingsAppearanceThemePreview
    controller.bar = .init(height: 0)

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalController = InputDataModalController(controller, size: NSMakeSize(350, 400))
    modalController._hasBorder = false

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}


public func loadCloudPaletteAndWallpaper(context: any AccountContextProtocol, file: TelegramMediaFile) -> Signal<(ColorPalette, Wallpaper, TelegramWallpaper?)?, NoError> {
    return context.account.postbox.mediaBox.resourceData(file.resource)
        |> filter { $0.complete }
        |> take(1)
        |> map { importPalette($0.path) }
        |> mapToSignal { palette -> Signal<(ColorPalette, Wallpaper, TelegramWallpaper?)?, NoError> in
            if let palette = palette {
                switch palette.wallpaper {
                case .builtin:
                    return .single((palette, Wallpaper.builtin, nil))
                case .none:
                    return .single((palette, Wallpaper.none, nil))
                case let .color(color):
                    return .single((palette, Wallpaper.color(color.argb), nil))
                case let .url(url):
                    let link = SettingsHooks.shared.inAppLink(url as NSString, context)
                    switch link {
                    case let .wallpaper(_, _, preview):
                        switch preview {
                        case let .slug(slug, settings):
                            return getWallpaper(network: context.account.network, slug: slug)
                                |> mapToSignal { cloud in
                                    return moveWallpaperToCache(postbox: context.account.postbox, wallpaper: Wallpaper(cloud).withUpdatedSettings(settings)) |> map { wallpaper in
                                        return (palette, wallpaper, cloud)
                                    } |> castError(GetWallpaperError.self)
                                }
                                |> `catch` { _ in
                                    return .single((palette, .none, nil))
                            }
                        default:
                            break
                        }
                    default:
                        break
                    }
                    return .single(nil)
                }
            } else {
                return .single(nil)
            }
    }
}
