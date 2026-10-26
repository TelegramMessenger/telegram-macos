import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import ThemeSettings

import AppKit
import AlertsUI
import Localization
import StarsUI
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils


public struct ThemeTuple : Comparable, Identifiable {
    public static func < (lhs: ThemeTuple, rhs: ThemeTuple) -> Bool {
        return lhs.index < rhs.index
    }
    
    public var chatTheme: ChatTheme?
    public var image: CGImage?
    public var theme: TelegramPresentationTheme
    public var index: Int
    public var selected: Bool = false
    
    public init(chatTheme: ChatTheme? = nil, image: CGImage? = nil, theme: TelegramPresentationTheme, index: Int, selected: Bool = false) {
        self.chatTheme = chatTheme
        self.image = image
        self.theme = theme
        self.index = index
        self.selected = selected
    }
    
    public var stableId: AnyHashable {
        return chatTheme
    }
    
    var isLoading: Bool {
        return chatTheme != nil && image == nil
    }
}




final class ChatThemeSelectorView : View {

    static let containerInset: CGFloat = 12

    private let bgView = View()
    private let glassView = LiquidGlassView(frame: NSZeroRect, cornerRadius: 20, hasShadow: true, hasBorder: true, forceBlur: true)

    let tableView: HorizontalTableView = HorizontalTableView(frame: .zero)

    private let controls:View = View()

    fileprivate var accept: TextButton?

    fileprivate let cancel = ImageButton()

    private let headerView = TextView()
    private let headerInfoView = TextView()

    private let headerContainer = View()

    fileprivate let selectBackground = TextButton()
    fileprivate var resetBackground: TextButton?

    fileprivate var resetBg:(()->Void)? = nil
    fileprivate var acceptTheme:(()->Void)? = nil

    private let bubblesTitle = TextView()
    private let bubblesSwitch = SwitchView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bgView.backgroundColor = presentation.colors.background
        bgView.layer?.cornerRadius = 20
        bgView.layer?.masksToBounds = true
        headerContainer.layer?.masksToBounds = false
        addSubview(bgView)
        addSubview(glassView)
        addSubview(tableView)
        addSubview(controls)
        addSubview(headerContainer)
        headerContainer.addSubview(headerView)
        headerContainer.addSubview(headerInfoView)
        headerContainer.addSubview(bubblesTitle)
        headerContainer.addSubview(bubblesSwitch)
        
        tableView.getBackgroundColor = {
            .clear
        }

        self.border = []

        headerContainer.addSubview(cancel)


        addSubview(selectBackground)
        
        selectBackground.autohighlight = false
        selectBackground.scaleOnClick = true
        
        cancel.autohighlight = false
        cancel.scaleOnClick = true
        cancel.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        
        
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
        
        headerInfoView.userInteractionEnabled = false
        headerInfoView.isSelectable = false
        
        bubblesTitle.userInteractionEnabled = false
        bubblesTitle.isSelectable = false
        
        tableView.needUpdateVisibleAfterScroll = true
        
        
        updateLayout(size: frameRect.size, transition: .immediate)
    }
    
    var colorful: Bool {
        return bubblesSwitch.isOn
    }
    
    fileprivate var wallpaper: ThemeWallpaper?
    private var first: Bool = true
    
    private var items: [ThemeTuple] = []

    private var selected: ChatTheme?

    private var pendingSnapButtons: Set<TextButton> = []
    
    
    fileprivate func updateThemes(_ peer: Peer?, _ themes: [ThemeTuple], installedTheme: ChatTheme?, wallpaper: ThemeWallpaper, bubbled: Bool, emojies: [String: StickerPackItem], context: any AccountContextProtocol, chatTheme: (ChatTheme?, TelegramPresentationTheme)?, previewCurrent: @escaping((ChatTheme?, TelegramPresentationTheme)?) -> Void, updateBubbled:@escaping(Bool)->Void) {
        
        let animated = !first
        first = false
        bubblesSwitch.autoswitch = false
        bubblesSwitch.setIsOn(bubbled)
        
        
        
        self.wallpaper = wallpaper
        
        
        var themes = [.init(theme: theme, index: -1)] + themes
//        
//        if let firstIndex = themes.firstIndex(where: { $0.chatTheme == chatTheme?.0}) {
//            themes.move(at: firstIndex, to: 0)
//        }
        
        themes = themes.map {
            .init(chatTheme: $0.chatTheme, image: $0.image, theme: $0.theme, index: $0.index, selected: chatTheme?.0 == $0.chatTheme)
        }
        

        bubblesSwitch.stateChanged = {
            let updatedValue = !bubbled
            updateBubbled(updatedValue)
        }
        
        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.items, rightList: themes)
        
        tableView.beginTableUpdates()

        for rdx in deleteIndices.reversed() {
            tableView.remove(at: rdx, animation: animated ? .effectFade : .none)
            self.items.remove(at: rdx)
        }
                
        for (idx, entry, _) in indicesAndItems {
            let item = SmartThemePreviewRowItem(frame.size, context: context, stableId: entry.chatTheme, bubbled: bubbled, emojies: emojies, theme: entry, selected: entry.selected, loading: entry.isLoading, select: previewCurrent)
            _ = tableView.insert(item: item, at: idx, animation: animated ? .effectFade : .none)
            self.items.insert(entry, at: idx)
        }
        for (idx, entry, _) in updateIndices {
            let item = SmartThemePreviewRowItem(frame.size, context: context, stableId: entry.chatTheme, bubbled: bubbled, emojies: emojies, theme: entry, selected: entry.selected, loading: entry.isLoading, select: previewCurrent)
            tableView.replace(item: item, at: idx, animated: animated)
            self.items[idx] = entry
        }
        tableView.endTableUpdates()

        let index = self.items.firstIndex(where: { $0.chatTheme == chatTheme?.0 })

        if selected != chatTheme?.0, let index {
            if chatTheme?.0 != nil {
                let item = tableView.item(at: index)
                tableView.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0), toVisible: true)
            } else {
                tableView.scroll(to: .center(id: tableView.item(at: 0).stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0), toVisible: true)
            }
        }
        
        self.selected = themes.first(where: { $0.selected })?.chatTheme
        
        if chatTheme?.0 != installedTheme {
            let accept: TextButton
            if let view = self.accept {
                accept = view
            } else {
                accept = TextButton()
                accept.autohighlight = false
                accept.scaleOnClick = true
                accept.layer?.cornerRadius = .cornerRadius
                addSubview(accept)
                
                accept.set(handler: { [weak self] _ in
                    self?.acceptTheme?()
                }, for: .SingleClick)
                self.accept = accept
                pendingSnapButtons.insert(accept)
                if animated {
                    accept.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            accept.set(color: theme.colors.underSelectedColor, for: .Normal)
            accept.set(background: .clear, for: .Normal)
            accept.set(font: .medium(.text), for: .Normal)
            accept.set(text: strings().chatChatThemeApplyTheme, for: .Normal)
            accept.sizeToFit(NSMakeSize(20, 0), NSMakeSize(0, 36), thatFit: false)
            accept.setFrameSize(NSMakeSize(accept.frame.width, 36))
            accept.setGlassEffect(size: accept.frame.size, tintColor: theme.colors.accent)
        } else if let view = self.accept {
            performSubviewRemoval(view, animated: animated)
            self.accept = nil
        }
        
        cancel.set(image: theme.icons.glass_close, for: .Normal)
        cancel.setGlassEffect(size: NSMakeSize(36, 36))
        cancel.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        
        
        selectBackground.set(color: theme.colors.accent, for: .Normal)
        selectBackground.set(background: .clear, for: .Normal)
        selectBackground.set(font: .medium(.text), for: .Normal)
        selectBackground.set(text: strings().chatChatThemeSelectBackground, for: .Normal)
        selectBackground.sizeToFit(NSMakeSize(20, 0), NSMakeSize(0, 36), thatFit: false)
        selectBackground.setFrameSize(NSMakeSize(selectBackground.frame.width, 36))
        selectBackground.setGlassEffect(size: selectBackground.frame.size)
        
        let header = TextViewLayout(.initialize(string: strings().chatThemeTheme, color: theme.colors.text, font: .medium(.header)))
        header.measure(width: .greatestFiniteMagnitude)
        headerView.update(header)
        
        let headerInfo = TextViewLayout(.initialize(string: strings().chatThemeThemeInfo(peer?.compactDisplayTitle ?? ""), color: theme.colors.grayText, font: .normal(.short)))
        headerInfo.measure(width: frame.width - 100)
        headerInfoView.update(headerInfo)
        
        let switchLayout = TextViewLayout(.initialize(string: strings().chatThemeColorful, color: theme.colors.text, font: .normal(.text)))
        switchLayout.measure(width: .greatestFiniteMagnitude)
        bubblesTitle.update(switchLayout)
        
        
        
        var isBespokeWallpaper: Bool = false
        if let chatTheme = chatTheme {
            if let found = themes.first(where: { $0.chatTheme == chatTheme.0 }) {
                isBespokeWallpaper = found.theme.wallpaper != wallpaper
            } else {
                isBespokeWallpaper = theme.wallpaper != wallpaper
            }
        } else {
            isBespokeWallpaper = theme.wallpaper != wallpaper
        }
        
        if isBespokeWallpaper {
            let current: TextButton
            if let view = self.resetBackground {
                current = view
            } else {
                current = TextButton()
                current.autohighlight = false
                current.scaleOnClick = true
                addSubview(current)
                self.resetBackground = current
                
                current.set(handler: { [weak self] _ in
                    self?.resetBg?()
                }, for: .Click)
                
                current.set(color: theme.colors.redUI, for: .Normal)
                current.set(background: .clear, for: .Normal)
                current.set(font: .medium(.text), for: .Normal)
                current.set(text: strings().chatChatThemeResetToDefault, for: .Normal)
                current.sizeToFit(NSMakeSize(20, 0), NSMakeSize(0, 36), thatFit: false)
                current.setFrameSize(NSMakeSize(current.frame.width, 36))
                current.setGlassEffect(size: current.frame.size)
                pendingSnapButtons.insert(current)

                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            
        } else if let view = self.resetBackground {
            performSubviewRemoval(view, animated: animated)
            self.resetBackground = nil
        }
        
        if animated {
            self.updateLayout(size: self.frame.size, transition: .animated(duration: 0.2, curve: .easeOut))
        } else {
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        bgView.backgroundColor = theme.colors.background
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {

        let inset = ChatThemeSelectorView.containerInset
        let glassRect = bounds.insetBy(dx: inset, dy: inset)
        transition.updateFrame(view: bgView, frame: glassRect)
        transition.updateFrame(view: glassView, frame: glassRect)
        glassView.updateLayout(size: glassRect.size, transition: transition)

        let innerWidth = size.width - inset * 2
        let originX = inset
        let originY = inset

        transition.updateFrame(view: headerContainer, frame: NSMakeRect(originX, originY, innerWidth, 50))
        transition.updateFrame(view: headerView, frame: CGRect(origin: NSMakePoint(54, headerContainer.frame.height / 2 - headerView.frame.height + 4), size: headerView.frame.size))

        transition.updateFrame(view: headerInfoView, frame: CGRect(origin: NSMakePoint(54, headerContainer.frame.height / 2 + 4), size: headerInfoView.frame.size))

        transition.updateFrame(view: cancel, frame: cancel.centerFrameY(x: 6))
        transition.updateFrame(view: bubblesSwitch, frame: bubblesSwitch.centerFrameY(x: headerContainer.frame.width - bubblesSwitch.frame.width - 12))
        transition.updateFrame(view: bubblesTitle, frame: bubblesTitle.centerFrameY(x: bubblesSwitch.frame.minX - bubblesTitle.frame.width - 8))
        transition.updateFrame(view: tableView, frame:  NSMakeRect(originX, originY + 50, innerWidth, 90))

        let buttonGap: CGFloat = 10
        var bottomButtons: [TextButton] = []
        if let accept = accept {
            bottomButtons.append(accept)
        }
        if let view = resetBackground {
            bottomButtons.append(view)
        }
        bottomButtons.append(selectBackground)

        let totalWidth = bottomButtons.reduce(0) { $0 + $1.frame.width } + CGFloat(max(0, bottomButtons.count - 1)) * buttonGap
        let regionTop = tableView.frame.maxY
        let regionBottom = bounds.height - inset
        let regionMidY = (regionTop + regionBottom) / 2

        var x = originX + (innerWidth - totalWidth) / 2
        for button in bottomButtons {
            let y = regionMidY - button.frame.height / 2
            let target = NSMakeRect(x, y, button.frame.width, button.frame.height)
            if pendingSnapButtons.contains(button) {
                button.frame = target
            } else {
                transition.updateFrame(view: button, frame: target)
            }
            x += button.frame.width + buttonGap
        }
        pendingSnapButtons.removeAll()
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ChatThemeSelectorController<Context: AccountContextProtocol> : TelegramGenericViewController<ChatThemeSelectorView, Context> {
    override var defaultBarTitle: String {
        return localizedString("Telegram.ChatThemeSelectorController")
    }
    private let chatInteraction: ChatInteraction
    private let readyDisposable = MetaDisposable()
    private let disposable = MetaDisposable()
    
    private let giftsContext: UniqueGiftChatThemesContext
    
    private let chatTheme: Signal<(ChatTheme?, TelegramPresentationTheme), NoError>
    private var currentSelected: (ChatTheme?, TelegramPresentationTheme)? {
        didSet {
            currentSelectedValue.set(.single(currentSelected))
        }
    }
    
    private let currentSelectedValue: Promise<(ChatTheme?, TelegramPresentationTheme)?> = Promise(nil)
    
    var onReady:(ChatThemeSelectorController)->Void = { _ in }
    var close: (Bool)->Void = { _ in }

    var previewCurrent: ((ChatTheme?, TelegramPresentationTheme?)) -> Void = { _ in }
    
    private let bubbled = ValuePromise(theme.bubbled, ignoreRepeated: true)
    private let installedTheme: ChatTheme?
    init(_ context: Context, installedTheme: ChatTheme?, chatTheme: Signal<(ChatTheme?, TelegramPresentationTheme), NoError>, chatInteraction: ChatInteraction) {
        self.chatTheme = chatTheme
        self.installedTheme = installedTheme
        self.chatInteraction = chatInteraction
        self.giftsContext = UniqueGiftChatThemesContext(account: context.account)

        super.init(context)
        self.bar = .init(height: 0)
    }
    
    deinit {
        disposable.dispose()
        readyDisposable.dispose()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let context = self.context
        let peerId = chatInteraction.peerId
        let installedTheme = self.installedTheme

        guard let peer = chatInteraction.peer else {
            return
        }
        
        
        let readySignal = self.ready.get() |> take(1) |> deliverOnMainQueue
        
        
        let themesAndThumbs: Signal<([ThemeTuple], Bool), NoError> = combineLatest(queue: resourcesQueue, context.chatThemes, bubbled.get(), giftsContext.state) |> mapToSignal { themes, bubbled, uniqueThemes in
            var signals:[Signal<ThemeTuple, NoError>] = []
            
            let index = Atomic(value: 0)
            let getIndex:()->Int = {
                return index.modify {
                    $0 + 1
                }
            }
            
           
           
            for theme in uniqueThemes.themes {
                
                let index = getIndex()
                
                switch theme {
                case let .gift(gift, settings):
                    let setting = settings.first(where: { $0.baseTheme.palette.isDark == appAppearance.presentation.colors.isDark })
                    if let unique = gift.unique, let setting, let wallpaper = setting.wallpaper {
                        let general = appAppearance.presentation.withUpdatedWallpaper(ThemeWallpaper(wallpaper: wallpaper.uiWallpaper(unique), associated: nil)).withUpdatedColors(setting.palette)
                        
                        if backgroundExists(general.wallpaper.wallpaper, palette: general.colors) {
                            signals.append(generateChatThemeThumb(palette: general.colors, bubbled: bubbled, backgroundMode: bubbled ? general.backgroundMode : .color(color: general.chatBackground)) |> map {
                                return ThemeTuple(chatTheme: theme, image: $0, theme: general, index: index)
                            })
                        } else {
                            signals.append(.single(ThemeTuple(chatTheme: theme, theme: general, index: index)) |> then(moveWallpaperToCache(postbox: context.account.postbox, wallpaper: general.wallpaper.wallpaper) |> mapToSignal { value in
                                return generateChatThemeThumb(palette: general.colors, bubbled: bubbled, backgroundMode: bubbled ? general.backgroundMode : .color(color: general.chatBackground)) |> map {
                                    return ThemeTuple(chatTheme: theme, image: $0, theme: general, index: index)
                                }
                            }))
                        }
                    }
                default:
                    break
                }
            }
            if case .ready(canLoadMore: false) = uniqueThemes.dataState {
                for theme in themes {
                    let index = getIndex()

                    signals.append(generateChatThemeThumb(palette: theme.1.colors, bubbled: bubbled, backgroundMode: bubbled ? theme.1.backgroundMode : .color(color: theme.1.colors.chatBackground)) |> map {
                        ThemeTuple(chatTheme: theme.0, image: $0, theme: theme.1, index: index)
                    })
                }
            }
            
            return combineLatest(signals) |> map { ($0, bubbled) }
        } |> deliverOnMainQueue
        
        
        currentSelectedValue.set(chatTheme |> take(1) |> map { $0 })
        var temprorary: (ChatTheme?, TelegramPresentationTheme)? = nil

        _ = (currentSelectedValue.get() |> take(1)).start(next: { [weak self] value in
            self?.currentSelected = value
            temprorary = value
        })
        
        let animatedEmojiStickers = context.diceCache.animatedEmojies
        disposable.set(combineLatest(queue: .mainQueue(), themesAndThumbs, chatTheme, currentSelectedValue.get(), animatedEmojiStickers).start(next: { [weak self] themes, chatTheme, currentSelected, emojies in
            
            let selected: (ChatTheme?, TelegramPresentationTheme)? = temprorary
            let bubbled = themes.1
                        
            self?.genericView.updateThemes(peer, themes.0, installedTheme: installedTheme, wallpaper: chatTheme.1.wallpaper, bubbled: bubbled, emojies: emojies, context: context, chatTheme: selected, previewCurrent: { preview in
                temprorary = preview
                self?.previewCurrent((preview?.0, (preview?.1 ?? theme).withUpdatedChatMode(bubbled)))
                self?.currentSelected = preview
            }, updateBubbled: { value in
                self?.bubbled.set(value)
                self?.previewCurrent((currentSelected?.0, (currentSelected?.1 ?? theme).withUpdatedChatMode(value)))
            })
            
            self?.readyOnce()
        }))
        
        readyDisposable.set(readySignal.start(next: { [weak self] _ in
            guard let controller = self else {
                return
            }
            self?.onReady(controller)
        }))
        
        genericView.cancel.set(handler: { [weak self] _ in
            self?.close(true)
        }, for: .Click)
        
        genericView.selectBackground.set(handler: { [weak self] _ in
            if let wallpaper = self?.genericView.wallpaper {
                ChatNavigationHooks.shared.showChatWallpaperSelector(context, wallpaper.wallpaper, peer, { [weak self] in
                    self?.close(true)
                }, context.window)
            }
        }, for: .Click)
        
        genericView.resetBg = { [weak self] in
            _ = context.engine.themes.setChatWallpaper(peerId: peerId, wallpaper: nil, forBoth: false).start()
            self?.close(true)
        }
        genericView.acceptTheme = { [weak self] in
            
            let isBubbled = self?.genericView.colorful ?? theme.bubbled
            let current = self?.currentSelected?.0

            let set:()->Void = {
                
                
                let signal = context.engine.themes.setChatTheme(peerId: peerId, chatTheme: current)
                
                let updateSignal = signal
                |> deliverOnMainQueue
                _ = updateSignal.start(next: { [weak self] in
                    self?.close(true)
                })
                self?.close(false)
                
                if theme.bubbled != isBubbled {
                    delay(0.5, closure: {
                        _ = updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings -> ThemePaletteSettings in
                            return settings.withUpdatedBubbled(isBubbled)
                        }).start()
                    })
                }
            }
            
            if let current {
                switch current {
                case .emoticon:
                    set()
                case let .gift(starGift, _):
                    switch starGift {
                    case let .unique(gift):
                        if let themePeerId = gift.themePeerId, themePeerId != peerId {
                            let signal =  context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: themePeerId))
                            |> deliverOnMainQueue
                            
                            _ = signal.start(next: { peer in
                                if let peer {
                                    return verifyAlert(
                                        for: context.window,
                                        header: "",
                                        information: strings().chatThemeUniqueGiftReplaceConfirm(peer._asPeer().displayTitle),
                                        ok: strings().modalYes,
                                        successHandler: { _ in
                                            set()
                                        },
                                        headerItem: ModalAlertData.Header(id: "header", value: { initialSize, stableId, theme in
                                            return TransferUniqueGiftHeaderItem(
                                                initialSize,
                                                stableId: stableId,
                                                gift: gift,
                                                toPeer: peer,
                                                context: context,
                                                transferType: .resetTheme
                                            )
                                        })
                                    )

                                }
                            })
                        } else {
                            set()
                        }
                    default:
                        set()
                    }
                }
            } else {
                set()
            }
            
            
        }
        
        genericView.tableView.setScrollHandler({ [weak self] position in
            switch position.direction {
            case .bottom:
                self?.giftsContext.loadMore()
            default:
                break
            }
        })

    }
    
}
