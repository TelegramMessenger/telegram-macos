import Cocoa
import TelegramCore
import ThemeSettings
import ColorPalette
import SwiftSignalKit
import Postbox
import TGUIKit
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

public func generateSingleColorImage(size: CGSize, color: NSColor) -> CGImage? {
    return generateImage(size, contextGenerator: { size, context in
        context.clear(size.bounds)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: CGPoint(), size: size))
    })
}


public func generateSettingsMenuPeerColorsLabelIcon(peer: Peer?, context: any AccountContextProtocol, isDark: Bool = theme.colors.isDark) -> CGImage {
    var colors:[PeerNameColors.Colors] = []
    if let nameColor = peer?.nameColor, let peer = peer, !peer.isGroup && !peer.isSupergroup {
        colors.append(nameColor.nameColors(context, isDark: isDark))
    }
    if let nameColor = peer?.profileColor {
        colors.append(context.peerNameColors.getProfile(nameColor, dark: isDark))
    }
    return  generateSettingsMenuPeerColorsLabelIcon(colors: colors)
}

public func generateSettingsMenuPeerColorsLabelIcon(colors: [PeerNameColors.Colors]) -> CGImage {
    let iconWidth: CGFloat = 24.0
    let iconSpacing: CGFloat = 18.0
    let borderWidth: CGFloat = 2.0
    
    if colors.isEmpty {
        return generateSingleColorImage(size: CGSize(width: iconWidth, height: iconWidth), color: .clear)!
    }

    return generateImage(CGSize(width: CGFloat(max(0, colors.count - 1)) * iconSpacing + CGFloat(colors.count == 0 ? 0 : 1) * iconWidth, height: 24.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        
        for i in 0 ..< colors.count {
            let iconFrame = CGRect(origin: CGPoint(x: CGFloat(i) * iconSpacing, y: 0.0), size: CGSize(width: iconWidth, height: iconWidth))
            context.setBlendMode(.copy)
            context.setFillColor(NSColor.clear.cgColor)
            context.fillEllipse(in: iconFrame.insetBy(dx: -borderWidth, dy: -borderWidth))
            context.setBlendMode(.normal)
            
            if let image = generatePeerNameColorImage(nameColor: colors[i], isDark: false, bounds: iconFrame.size, size: iconFrame.size) {
                context.saveGState()
                context.translateBy(x: iconFrame.midX, y: iconFrame.midY)
                context.scaleBy(x: 1.0, y: -1.0)
                context.translateBy(x: -iconFrame.midX, y: -iconFrame.midY)
                context.draw(image, in: iconFrame)
                context.restoreGState()
            }
        }
    })!
}


public func generatePeerNameColorImage(nameColor: PeerNameColors.Colors, isDark: Bool, bounds: CGSize = CGSize(width: 40.0, height: 40.0), size: CGSize = CGSize(width: 40.0, height: 40.0)) -> CGImage? {
    return generateImage(bounds, rotatedContext: { contextSize, context in
        let bounds = CGRect(origin: CGPoint(), size: contextSize)
        context.clear(bounds)
        
        let circleBounds = CGRect(origin: CGPoint(x: floorToScreenPixels((bounds.width - size.width) / 2.0), y: floorToScreenPixels((bounds.height - size.height) / 2.0)), size: size)
        context.addEllipse(in: circleBounds)
        context.clip()
        
        if let secondColor = nameColor.secondary {
            var firstColor = nameColor.main
            var secondColor = secondColor
            if isDark, nameColor.tertiary == nil {
                firstColor = secondColor
                secondColor = nameColor.main
            }
            
            context.setFillColor(secondColor.cgColor)
            context.fill(circleBounds)
            
            if let thirdColor = nameColor.tertiary {
                context.move(to: CGPoint(x: contextSize.width, y: 0.0))
                context.addLine(to: CGPoint(x: contextSize.width, y: contextSize.height))
                context.addLine(to: CGPoint(x: 0.0, y: contextSize.height))
                context.closePath()
                context.setFillColor(firstColor.cgColor)
                context.fillPath()
                
                context.setFillColor(thirdColor.cgColor)
                context.translateBy(x: contextSize.width / 2.0, y: contextSize.height / 2.0)
                context.rotate(by: .pi / 4.0)
                
                let rectSide = size.width / 40.0 * 18.0
                let rectCornerRadius = round(size.width / 40.0 * 4.0)
                
                let path = CGPath(roundedRect: CGRect(origin: CGPoint(x: -rectSide / 2.0, y: -rectSide / 2.0), size: CGSize(width: rectSide, height: rectSide)), cornerWidth: rectCornerRadius, cornerHeight: rectCornerRadius, transform: nil)
                context.addPath(path)
                context.fillPath()
            } else {
                context.move(to: .zero)
                context.addLine(to: CGPoint(x: contextSize.width, y: 0.0))
                context.addLine(to: CGPoint(x: 0.0, y: contextSize.height))
                context.closePath()
                context.setFillColor(firstColor.cgColor)
                context.fillPath()
            }
        } else {
            context.setFillColor(nameColor.main.cgColor)
            context.fill(circleBounds)
        }
    })
}


public func generatePeerNameColorImage(colors: PeerNameColors, peer: Peer?) -> CGImage {
    let attr = NSMutableAttributedString()
    let color = peer?.namePeerColor ?? .blue
    
    
    let main = colors.get(color).main
    
    _ = attr.append(string: (peer?.compactDisplayTitle ?? "").prefixWithDots(15), color: colors.get(color).main, font: .avatar(.short))
    let textNode = TextNode.layoutText(attr, nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    
    var size = textNode.0.size
    size.width += 16
    size.height += 8
    return generateImage(size, rotatedContext: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)
        ctx.round(rect.size, size.height / 2)
        ctx.setFillColor(main.withAlphaComponent(0.1).cgColor)
        ctx.fill(rect)
        textNode.1.draw(rect.focus(textNode.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })!
}

private extension TelegramBuiltinTheme {
    var baseTheme: TelegramBaseTheme {
        switch self {
        case .dark:
            return .night
        case .nightAccent:
            return .tinted
        case .day:
            return .day
        case .dayClassic:
            return .classic
        default:
            if !palette.isDark {
                return .classic
            } else {
                return .tinted
            }
        }
    }
}

public struct SmartThemeCachedData : Equatable {
    
    public enum Source : Equatable {
        case local(ColorPalette)
        case cloud(TelegramTheme)
    }
    public struct Data : Equatable {
        public let appTheme: TelegramPresentationTheme
        public let previewIcon: CGImage
        public let emoticon: String
    }
    public let source: Source
    public let data: Data

    public init(source: Source, data: Data) {
        self.source = source
        self.data = data
    }
}

public struct CloudThemesCachedData {
    
    public struct Key : Hashable {
        public let base: TelegramBaseTheme
        public let bubbled: Bool
        
        var colors: ColorPalette {
            return base.palette
        }
        
        static var all: [Key] {
            return [.init(base: .classic, bubbled: true),
                    .init(base: .day, bubbled: true),
                    .init(base: .night, bubbled: true),
                    .init(base: .classic, bubbled: false),
                    .init(base: .day, bubbled: false),
                    .init(base: .night, bubbled: false)]
        }
    }
    
    public let themes: [TelegramTheme]
    public let list: [Key : [SmartThemeCachedData]]
    public let `default`: SmartThemeCachedData?
    public let custom: SmartThemeCachedData?

    public init(themes: [TelegramTheme], list: [Key : [SmartThemeCachedData]], default: SmartThemeCachedData?, custom: SmartThemeCachedData?) {
        self.themes = themes
        self.list = list
        self.default = `default`
        self.custom = custom
    }
}


public struct AppearanceAccentColor : Equatable {
    public let accent: PaletteAccentColor
    public let cloudTheme: TelegramTheme?
    public let cachedTheme: InstallCloudThemeCachedData?
    public init(accent: PaletteAccentColor, cloudTheme: TelegramTheme?, cachedTheme: InstallCloudThemeCachedData? = nil) {
        self.accent = accent
        self.cloudTheme = cloudTheme
        self.cachedTheme = cachedTheme
    }
    public func withUpdatedCachedTheme(_ cachedTheme: InstallCloudThemeCachedData?) -> AppearanceAccentColor {
        return .init(accent: self.accent, cloudTheme: self.cloudTheme, cachedTheme: cachedTheme)
    }
}

public enum ThemeSettingsEntryTag: ItemListItemTag {
    case fontSize
    case theme
    case autoNight
    case chatMode
    case accentColor
    public func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? ThemeSettingsEntryTag, self == other {
            return true
        } else {
            return false
        }
    }
    
    public var stableId: InputDataEntryId {
        switch self {
        case .fontSize:
            return .custom(_id_theme_text_size)
        case .theme:
            return .custom(_id_theme_list)
        case .autoNight:
            return .general(_id_theme_auto_night)
        case .chatMode:
            return .general(_id_theme_chat_mode)
        case .accentColor:
            return .custom(_id_theme_accent_list)
        }
    }
}


public struct InstallCloudThemeCachedData : Equatable {
    public let palette: ColorPalette
    public let wallpaper: Wallpaper
    public let cloudWallpaper: TelegramWallpaper?

    public init(palette: ColorPalette, wallpaper: Wallpaper, cloudWallpaper: TelegramWallpaper?) {
        self.palette = palette
        self.wallpaper = wallpaper
        self.cloudWallpaper = cloudWallpaper
    }
}
public enum InstallThemeSource : Equatable {
    case local(ColorPalette)
    case cloud(TelegramTheme, InstallCloudThemeCachedData?)
}

private final class AppAppearanceViewArguments {
    public let context: any AccountContextProtocol
    public let togglePalette:(InstallThemeSource)->Void
    public let toggleBubbles:(Bool)->Void
    public let toggleFontSize:(CGFloat)->Void
    public let selectAccentColor:(AppearanceAccentColor?)->Void
    public let selectChatBackground:()->Void
    public let openAutoNightSettings:()->Void
    public let removeTheme:(TelegramTheme)->Void
    public let editTheme:(TelegramTheme)->Void
    public let shareTheme:(TelegramTheme)->Void
    public let shareLocal:(ColorPalette)->Void
    public let toggleDarkMode:(Bool)->Void
    public let toggleRevealThemes:()->Void
    public let userNameColor:()->Void
    public let selectAppIcon:(TelegramApplicationIcons.Icon)->Void
    public init(context: any AccountContextProtocol, togglePalette: @escaping(InstallThemeSource)->Void, toggleBubbles: @escaping(Bool)->Void, toggleFontSize: @escaping(CGFloat)->Void, selectAccentColor: @escaping(AppearanceAccentColor?)->Void, selectChatBackground:@escaping()->Void, openAutoNightSettings:@escaping()->Void, removeTheme:@escaping(TelegramTheme)->Void, editTheme: @escaping(TelegramTheme)->Void, shareTheme:@escaping(TelegramTheme)->Void, shareLocal:@escaping(ColorPalette)->Void, toggleDarkMode: @escaping(Bool)->Void, toggleRevealThemes:@escaping()->Void, userNameColor:@escaping()->Void, selectAppIcon:@escaping(TelegramApplicationIcons.Icon)->Void) {
        self.context = context
        self.togglePalette = togglePalette
        self.toggleBubbles = toggleBubbles
        self.toggleFontSize = toggleFontSize
        self.selectAccentColor = selectAccentColor
        self.selectChatBackground = selectChatBackground
        self.openAutoNightSettings = openAutoNightSettings
        self.removeTheme = removeTheme
        self.editTheme = editTheme
        self.shareTheme = shareTheme
        self.shareLocal = shareLocal
        self.toggleDarkMode = toggleDarkMode
        self.toggleRevealThemes = toggleRevealThemes
        self.userNameColor = userNameColor
        self.selectAppIcon = selectAppIcon
    }
}


private let _id_theme_preview = InputDataIdentifier("_id_theme_preview")
private let _id_theme_list = InputDataIdentifier("_id_theme_list")
private let _id_theme_accent_list = InputDataIdentifier("_id_theme_accent_list")
private let _id_theme_chat_mode = InputDataIdentifier("_id_theme_chat_mode")
private let _id_theme_wallpaper1 = InputDataIdentifier("_id_theme_wallpaper")
private let _id_theme_text_size = InputDataIdentifier("_id_theme_text_size")
private let _id_theme_auto_night = InputDataIdentifier("_id_theme_auto_night")
private let _id_theme_night_mode = InputDataIdentifier("_id_theme_night_mode")

private let _id_cloud_themes = InputDataIdentifier("_id_cloud_themes")

private let _id_name_color = InputDataIdentifier("_id_name_color")

private let _id_dock_icon = InputDataIdentifier("_id_dock_icon")

private func appAppearanceEntries(appearance: Appearance, state: State, settings: ThemePaletteSettings, cloudThemes: [TelegramTheme], generated:  CloudThemesCachedData, autoNightSettings: AutoNightThemePreferences, animatedEmojiStickers: [String: StickerPackItem], dockIcons: TelegramApplicationIcons, dockSettings: DockSettings, arguments: AppAppearanceViewArguments) -> [InputDataEntry] {
    
    var entries:[InputDataEntry] = []
    var sectionId: Int32 = 0
    var index:Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().appearanceSettingsColorThemeHeader), data: .init(viewType: .textTopItem)))
    index += 1
    
    struct Tuple: Equatable {
        let peer: PeerEquatable?
        let appearance: Appearance
    }
    let tuple = Tuple(peer: .init(state.myPeer), appearance: appearance)

    entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_theme_preview, equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
        return ThemePreviewRowItem(initialSize, stableId: stableId, context: arguments.context, theme: appearance.presentation, viewType: .firstItem)
    }))

    var accentList = appearance.presentation.cloudTheme == nil || appearance.presentation.cloudTheme?.settings != nil ? appearance.presentation.colors.accentList.map { AppearanceAccentColor(accent: $0, cloudTheme: nil) } : []

    var cloudThemes = cloudThemes
    if let cloud = appearance.presentation.cloudTheme {
        if !cloudThemes.contains(where: {$0.id == cloud.id}) {
            cloudThemes.append(cloud)
        }
    }
   
    
    if appearance.presentation.cloudTheme == nil || appearance.presentation.cloudTheme?.settings != nil {
        let copy = cloudThemes
        var cloudAccents:[AppearanceAccentColor] = []
        for cloudTheme in copy {
            if let settings = cloudTheme.effectiveSettings(for: appearance.presentation.colors) {
                cloudAccents.append(AppearanceAccentColor(accent: settings.accent, cloudTheme: cloudTheme))
            }
        }
        accentList.append(contentsOf: cloudAccents)
    }


    cloudThemes.removeAll(where:{ $0.settings != nil })

    struct ListEquatable : Equatable {
        let theme: TelegramPresentationTheme
        let cloudThemes:[TelegramTheme]
    }
    
    entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_theme_list, equatable: InputDataEquatable(ListEquatable(theme: appearance.presentation, cloudThemes: cloudThemes)), comparable: nil, item: { initialSize, stableId in

        let selected: ThemeSource
        if let cloud = appearance.presentation.cloudTheme {
            if let _ = cloud.settings {
               selected = .local(appearance.presentation.colors, cloud)
            } else {
                selected = .cloud(cloud)
            }
        } else {
            selected = .local(appearance.presentation.colors, nil)
        }

        let dayClassicCloud = settings.associated.first(where: { $0.local == dayClassicPalette.parent })?.cloud?.cloud
        let dayCloud = settings.associated.first(where: { $0.local == whitePalette.parent })?.cloud?.cloud
        let nightAccentCloud = settings.associated.first(where: { $0.local == nightAccentPalette.parent })?.cloud?.cloud

        var locals: [LocalPaletteWithReference] = [LocalPaletteWithReference(palette: dayClassicPalette, cloud: dayClassicCloud),
                                                   LocalPaletteWithReference(palette: whitePalette, cloud: dayCloud),
                                                   LocalPaletteWithReference(palette: nightAccentPalette, cloud: nightAccentCloud),
                                                   LocalPaletteWithReference(palette: systemPalette, cloud: nil)]

        for (i, local) in locals.enumerated() {
            if let accent = settings.accents.first(where: { $0.name == local.palette.parent }), accent.color.accent != local.palette.basicAccent {
                locals[i] = local.withAccentColor(accent.color)
            }
        }

        return ThemeListRowItem(initialSize, stableId: stableId, context: arguments.context, theme: appearance.presentation, selected: selected, local: locals, cloudThemes: cloudThemes, viewType: accentList.isEmpty ? .lastItem : .innerItem, togglePalette: arguments.togglePalette, menuItems: { source in
            var items:[ContextMenuItem] = []
            var cloud: TelegramTheme?

            switch source {
            case let .cloud(c):
                cloud = c
            case let .local(_, c):
                cloud = c
            }

            if let cloud = cloud {
                if cloud.isCreator {
                    items.append(ContextMenuItem(strings().appearanceThemeEdit, handler: {
                        arguments.editTheme(cloud)
                    }, itemImage: MenuAnimation.menu_edit.value))
                }
                items.append(ContextMenuItem(strings().appearanceThemeShare, handler: {
                    arguments.shareTheme(cloud)
                }, itemImage: MenuAnimation.menu_share.value))
                
                items.append(ContextSeparatorItem())
                
                items.append(ContextMenuItem(strings().appearanceThemeRemove, handler: {
                    arguments.removeTheme(cloud)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }

            return items
        })
    }))

    if !accentList.isEmpty {

        struct ALEquatable : Equatable {
            let accentList: [AppearanceAccentColor]
            let theme: TelegramPresentationTheme
        }


        entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_theme_accent_list, equatable: InputDataEquatable(ALEquatable(accentList: accentList, theme: appearance.presentation)), comparable: nil, item: { initialSize, stableId in
            

            
            return AccentColorRowItem(initialSize, stableId: stableId, context: arguments.context, list: accentList, isNative: true, theme: appearance.presentation, viewType: .lastItem, selectAccentColor: arguments.selectAccentColor, menuItems: { accent in
                var items:[ContextMenuItem] = []
                if let cloud = accent.cloudTheme {
                    items.append(ContextMenuItem(strings().appearanceThemeShare, handler: {
                        arguments.shareTheme(cloud)
                    }, itemImage: MenuAnimation.menu_share.value))
                    items.append(ContextSeparatorItem())
                    items.append(ContextMenuItem(strings().appearanceThemeRemove, handler: {
                        arguments.removeTheme(cloud)
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
                return items
            })
        }))
        index += 1
        
        
        
        
        
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
  
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_theme_night_mode, data: InputDataGeneralData(name: strings().appearanceSettingsDarkMode, color: appearance.presentation.colors.text, type: .switchable(appearance.presentation.dark), viewType: .firstItem, action: {
        arguments.toggleDarkMode(!appearance.presentation.dark)
    })))
    index += 1
    
   
    
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_theme_chat_mode, data: InputDataGeneralData(name: strings().appearanceSettingsBubblesMode, color: appearance.presentation.colors.text, type: .switchable(appearance.presentation.bubbled), viewType: .innerItem, action: {
        arguments.toggleBubbles(!appearance.presentation.bubbled)
    })))
    index += 1
    
   
    if appearance.presentation.bubbled {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_theme_wallpaper1, data: InputDataGeneralData(name: strings().generalSettingsChatBackground, color: appearance.presentation.colors.text, type: .next, viewType: .innerItem, action: arguments.selectChatBackground)))
        index += 1
    }
    
    let icon = generateSettingsMenuPeerColorsLabelIcon(peer: state.myPeer, context: arguments.context, isDark: appearance.presentation.colors.isDark)
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_name_color, data: InputDataGeneralData(name: strings().appearanceYourNameColor, color: appearance.presentation.colors.text, type: .imageContext(icon, ""), viewType: .lastItem, action: arguments.userNameColor)))
    index += 1

    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().appearanceSettingsTextSizeHeader), data: .init(viewType: .textTopItem)))
    index += 1

    entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_theme_text_size, equatable: InputDataEquatable(appearance), comparable: nil, item: { initialSize, stableId in
        let sizes:[Int32] = [11, 12, 13, 14, 15, 16, 17, 18]
        return SelectSizeRowItem(initialSize, stableId: stableId, current: Int32(appearance.presentation.fontSize), sizes: sizes, hasMarkers: true, viewType: .singleItem, selectAction: { index in
            arguments.toggleFontSize(CGFloat(sizes[index]))
        })
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().appearanceSettingsAutoNightHeader), data: .init(viewType: .textTopItem)))
    index += 1

    let autoNightText: String
    if autoNightSettings.systemBased {
        autoNightText = strings().autoNightSettingsSystemBased
    } else if let _ = autoNightSettings.schedule {
        autoNightText = strings().autoNightSettingsScheduled
    } else {
        autoNightText = strings().autoNightSettingsDisabled
    }
    
    sectionId += 1

    

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_theme_auto_night, data: InputDataGeneralData(name: strings().appearanceSettingsAutoNight, color: appearance.presentation.colors.text, type: .nextContext(autoNightText), viewType: .singleItem, action: arguments.openAutoNightSettings)))
    index += 1

    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    #if BETA || STABLE
    
    if !dockIcons.icons.isEmpty {
        struct DockTuple : Equatable {
            let icons: TelegramApplicationIcons
            let settings: DockSettings
        }
        let dockTuple = DockTuple(icons: dockIcons, settings: dockSettings)
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().appearanceSettingsDockIcon), data: .init(viewType: .textTopItem)))
        index += 1
        entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_dock_icon, equatable: InputDataEquatable(dockTuple), comparable: nil, item: { initialSize, stableId in
            return DockIconRowItem(initialSize, stableId: stableId, viewType: .singleItem, context: arguments.context, dockIcons: dockIcons.icons, selected: dockTuple.settings.iconSelected, action: arguments.selectAppIcon)
        }))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }
    
    #endif
    
    return entries
}

private struct State : Equatable {
    public var revealed: Bool
    public var myPeer: TelegramUser?
}

public func AppAppearanceViewController(context: any AccountContextProtocol, focusOnItemTag: ThemeSettingsEntryTag? = nil) -> InputDataController {
    
    let applyCloudThemeDisposable = MetaDisposable()
    let updateDisposable = MetaDisposable()
    
    
    let actionsDisposable = DisposableSet()
    
    
    let initialState = State(revealed: false)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    actionsDisposable.add(getPeerView(peerId: context.peerId, postbox: context.account.postbox).start(next: { peer in
        updateState { current in
            var current = current
            current.myPeer = peer as? TelegramUser
            return current
        }
    }))
    
    let applyTheme:(InstallThemeSource)->Void = { source in
        switch source {
        case let .local(palette):
            updateDisposable.set(updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                var settings = settings
                settings = settings.withUpdatedPalette(palette).withUpdatedCloudTheme(nil)
                
                let defaultTheme = DefaultTheme(local: palette.parent, cloud: nil)
                if palette.isDark {
                    settings = settings.withUpdatedDefaultDark(defaultTheme)
                } else {
                    settings = settings.withUpdatedDefaultDay(defaultTheme)
                }
                return settings.installDefaultWallpaper().installDefaultAccent().withUpdatedDefaultIsDark(palette.isDark).withSavedAssociatedTheme()
            }).start())
        case let .cloud(cloud, cached):
            if let cached = cached {
                updateDisposable.set(updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                    var settings = settings
                    settings = settings.withUpdatedPalette(cached.palette)
                    settings = settings.withUpdatedCloudTheme(cloud)
                    settings = settings.updateWallpaper { _ in
                        return ThemeWallpaper(wallpaper: cached.wallpaper, associated: AssociatedWallpaper(cloud: cached.cloudWallpaper, wallpaper: cached.wallpaper))
                    }
                    let defaultTheme = DefaultTheme(local: cached.palette.parent, cloud: DefaultCloudTheme(cloud: cloud, palette: cached.palette, wallpaper: AssociatedWallpaper(cloud: cached.cloudWallpaper, wallpaper: cached.wallpaper)))
                    if cached.palette.isDark {
                        settings = settings.withUpdatedDefaultDark(defaultTheme)
                    } else {
                        settings = settings.withUpdatedDefaultDay(defaultTheme)
                    }
                    return settings
                        .saveDefaultWallpaper()
                        .withUpdatedDefaultIsDark(cached.palette.isDark)
                        .withSavedAssociatedTheme()
                }).start(completed: {
                    applyCloudThemeDisposable.set(SettingsHooks.shared.downloadAndApplyCloudTheme(context, cloud, cached.palette, true).start())
                }))
                
            } else if cloud.file != nil {
                applyCloudThemeDisposable.set(showModalProgress(signal: SettingsHooks.shared.downloadAndApplyCloudTheme(context, cloud, nil, true), for: context.window).start())
            } else {
                showEditThemeModalController(context: context, theme: cloud)
            }
        }
    }
    
    
    var getController:(()->InputDataController?)? = nil

    let arguments = AppAppearanceViewArguments(context: context, togglePalette: { source in
        
        let nightSettings = autoNightSettings(accountManager: context.sharedContext.accountManager) |> take(1) |> deliverOnMainQueue
        
        let targetIsDark: Bool?
        switch source {
        case let .local(palette):
            targetIsDark = palette.isDark
        case let .cloud(_, cached):
            targetIsDark = cached?.palette.isDark
        }
        
        _ = nightSettings.start(next: { settings in
            let reportThemeMode = {
                if let targetIsDark = targetIsDark, settings.systemBased || targetIsDark != theme.colors.isDark {
                    sendThemeModeChange(dark: targetIsDark)
                }
            }
            if settings.systemBased || settings.schedule != nil {
                verifyAlert_button(for: context.window, header: strings().darkModeConfirmNightModeHeader, information: strings().darkModeConfirmNightModeText, ok: strings().darkModeConfirmNightModeOK, successHandler: { _ in
                    reportThemeMode()
                    let disableNightMode = context.sharedContext.accountManager.transaction { transaction -> Void in
                        transaction.updateSharedData(ApplicationSharedPreferencesKeys.autoNight, { entry in
                            let settings: AutoNightThemePreferences = entry?.get(AutoNightThemePreferences.self) ?? AutoNightThemePreferences.defaultSettings
                            return PreferencesEntry(settings.withUpdatedSystemBased(false).withUpdatedSchedule(nil))
                        })
                    } |> deliverOnMainQueue
                    _ = disableNightMode.start(next: {
                        applyTheme(source)
                    })
                })
            } else {
                reportThemeMode()
                applyTheme(source)
            }
        })
        
       
    }, toggleBubbles: { value in
        updateDisposable.set(updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
            return settings.withUpdatedBubbled(value)
        }).start())
    }, toggleFontSize: { value in
        updateDisposable.set(updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
            return settings.withUpdatedFontSize(value)
        }).start())
    }, selectAccentColor: { value in
        let updateColor:(AppearanceAccentColor)->Void = { color in
            if let cloudTheme = color.cloudTheme {
                applyTheme(.cloud(cloudTheme, color.cachedTheme))
            } else {
                updateDisposable.set(updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                    let clearPalette = settings.palette.withoutAccentColor()
                    var settings = settings
                    if color.accent.accent == settings.palette.basicAccent {
                        settings = settings.withUpdatedPalette(clearPalette)
                    } else {
                        settings = settings.withUpdatedPalette(clearPalette.withAccentColor(color.accent))
                    }
                    
                    let defaultTheme = DefaultTheme(local: settings.palette.parent, cloud: nil)
                    if settings.palette.isDark {
                        settings = settings.withUpdatedDefaultDark(defaultTheme)
                    } else {
                        settings = settings.withUpdatedDefaultDay(defaultTheme)
                    }
                    
                    return settings.withUpdatedCloudTheme(nil).saveDefaultAccent(color: color.accent).installDefaultWallpaper().withSavedAssociatedTheme()
                }).start())
            }
        }
        if let color = value {
           updateColor(color)
        } else {
            showModal(with: CustomAccentColorModalController(context: context, updateColor: { accent in
                updateColor(AppearanceAccentColor(accent: accent, cloudTheme: nil))
            }), for: context.window)
        }
    }, selectChatBackground: {
        showModal(with: ChatWallpaperModalController(context), for: context.window, morphSource: {
            (getController?()?.tableView.item(stableId: InputDataEntryId.general(_id_theme_wallpaper1))?.view as? GeneralContainableRowView)?.containerView
        })
    }, openAutoNightSettings: {
        context.bindings.rootNavigation().push(AutoNightSettingsController(context: context))
    }, removeTheme: { cloudTheme in
        verifyAlert_button(for: context.window, header: strings().appearanceConfirmRemoveTitle, information: strings().appearanceConfirmRemoveText, ok: strings().appearanceConfirmRemoveOK, successHandler: { _ in
            var signals:[Signal<Void, NoError>] = []
            if theme.cloudTheme?.id == cloudTheme.id {
                signals.append(updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                    var settings = settings.withUpdatedCloudTheme(nil)
                        .withUpdatedToDefault(dark: settings.defaultIsDark, onlyLocal: true)
                    let defaultTheme = DefaultTheme(local: settings.palette.parent, cloud: nil)
                    if settings.defaultIsDark {
                        settings = settings.withUpdatedDefaultDark(defaultTheme)
                    } else {
                        settings = settings.withUpdatedDefaultDay(defaultTheme)
                    }
                    return settings.withSavedAssociatedTheme()
                    
                }))
            }
            signals.append(deleteThemeInteractively(account: context.account, accountManager: context.sharedContext.accountManager, theme: cloudTheme))
            updateDisposable.set(combineLatest(signals).start())
        })
    }, editTheme: { value in
        showEditThemeModalController(context: context, theme: value)
    }, shareTheme: { value in
        SettingsHooks.shared.shareLink(context, context.meUrlPrefix + "addtheme/\(value.slug)")
    }, shareLocal: { palette in
        
    }, toggleDarkMode: { _ in
        toggleDarkMode(context: context)
    }, toggleRevealThemes: {
        updateState { current in
            var current = current
            current.revealed = !current.revealed
            return current
        }
    }, userNameColor: {
        context.bindings.rootNavigation().push(SettingsHooks.shared.makeSelectColorController(context, context.myPeer!))
    }, selectAppIcon: { icon in
        
        if icon.isPremium, !context.isPremium {
            SettingsNavigationHooks.shared.showPremiumBoarding(context, .settings, false, context.window, nil)
            return
        }
        
        _ = updateDockSettings(accountManager: context.sharedContext.accountManager, { settings in
            return settings.withUpdatedIcon(icon.file.fileName)
        }).startStandalone()
    })
    
    
    let nightSettings = autoNightSettings(accountManager: context.sharedContext.accountManager)
    
    
    let animatedEmojiStickers = context.engine.stickers.loadedStickerPack(reference: .animatedEmoji, forceActualized: false)
        |> map { result -> [String: StickerPackItem] in
            switch result {
            case let .result(_, items, _):
                var animatedEmojiStickers: [String: StickerPackItem] = [:]
                for case let item in items {
                    if let emoji = item.getStringRepresentationsOfIndexKeys().first {
                        animatedEmojiStickers[emoji] = item
                    }
                }
                return animatedEmojiStickers
            default:
                return [:]
            }
    } |> deliverOnMainQueue
    
    let signal:Signal<InputDataSignalValue, NoError> = combineLatest(queue: prepareQueue, themeUnmodifiedSettings(accountManager: context.sharedContext.accountManager), SettingsHooks.shared.cloudThemes(context), nightSettings, appearanceSignal, animatedEmojiStickers, statePromise.get(), context.engine.resources.applicationIcons(), dockSettings(accountManager: context.sharedContext.accountManager)) |> map { themeSettings, themes, autoNightSettings, appearance, animatedEmojiStickers, state, dockIcons, dockSettings in
        return appAppearanceEntries(appearance: appearance, state: state, settings: themeSettings, cloudThemes: themes.themes.reversed(), generated: themes, autoNightSettings: autoNightSettings, animatedEmojiStickers: animatedEmojiStickers, dockIcons: dockIcons, dockSettings: dockSettings, arguments: arguments)
    }
    |> map { entries in
         return InputDataSignalValue(entries: entries, animated: true)
    } |> deliverOnMainQueue
    
    
    
    
    let controller = InputDataController(dataSignal: signal, title: strings().telegramAppearanceViewController, removeAfterDisappear:false, identifier: "app_appearance", customRightButton: { controller in
        
        let view = ImageBarView(controller: controller, theme.icons.chatActions)
        
        
        view.button.contextMenu = {
            var items:[ContextMenuItem] = []
            if theme.colors.parent != .system {
                items.append(ContextMenuItem(strings().appearanceNewTheme, handler: {
                    showModal(with: NewThemeController(context: context, palette: theme.colors.withUpdatedWallpaper(theme.wallpaper.paletteWallpaper)), for: context.window)
                }, itemImage: MenuAnimation.menu_change_colors.value))
                items.append(ContextMenuItem(strings().appearanceExportTheme, handler: {
                    exportPalette(palette: theme.colors.withUpdatedName(theme.cloudTheme?.title ?? theme.colors.name).withUpdatedWallpaper(theme.wallpaper.paletteWallpaper))
                }, itemImage: MenuAnimation.menu_save_as.value))
                if let cloudTheme = theme.cloudTheme {
                    items.append(ContextMenuItem(strings().appearanceThemeShare, handler: {
                        SettingsHooks.shared.shareLink(context, context.meUrlPrefix + "addtheme/\(cloudTheme.slug)")
                    }, itemImage: MenuAnimation.menu_share.value))
                }
                
                if theme.cloudTheme != nil || theme.colors.accent != theme.colors.basicAccent {
                    items.append(ContextMenuItem(strings().appearanceReset, handler: {
                         _ = updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                            var settings = settings
                            if settings.defaultIsDark {
                                settings = settings.withUpdatedDefaultDark(DefaultTheme(local: TelegramBuiltinTheme.nightAccent, cloud: nil)).saveDefaultAccent(color: PaletteAccentColor(nightAccentPalette.accent))
                            } else {
                                settings = settings.withUpdatedDefaultDay(DefaultTheme(local: TelegramBuiltinTheme.dayClassic, cloud: nil)).saveDefaultAccent(color: PaletteAccentColor(dayClassicPalette.accent))
                            }
                            
                            return settings.installDefaultAccent().withUpdatedCloudTheme(nil).updateWallpaper({ _ -> ThemeWallpaper in
                                return ThemeWallpaper(wallpaper: settings.palette.wallpaper.wallpaper, associated: nil)
                            }).installDefaultWallpaper()
                         }).start()
                    }, itemImage: MenuAnimation.menu_reset.value))
                }
                
                let menu = ContextMenu()
                for item in items {
                    menu.addItem(item)
                }
                return menu
            }
            return nil
        }
      
        view.button.set(image: theme.icons.chatActions, for: .Normal)
        return view
        
    })
    
    controller.updateRightBarView = { view in
        if let view = view as? ImageBarView {
            view.button.set(image: theme.icons.chatActions, for: .Normal)
        }
    }
    
    controller.didLoad = { controller, _ in
        if let focusOnItemTag = focusOnItemTag {
            controller.genericView.tableView.scroll(to: .center(id: focusOnItemTag.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets())
        }
        controller.genericView.tableView.needUpdateVisibleAfterScroll = true
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    getController = { [weak controller] in controller }

    return controller
}




public func toggleDarkMode(context: any AccountContextProtocol) {
    let nightSettings = autoNightSettings(accountManager: context.sharedContext.accountManager) |> take(1) |> deliverOnMainQueue
    
    _ = nightSettings.start(next: { settings in
        if settings.systemBased || settings.schedule != nil {
            verifyAlert_button(for: context.window, header: strings().darkModeConfirmNightModeHeader, information: strings().darkModeConfirmNightModeText, ok: strings().darkModeConfirmNightModeOK, successHandler: { _ in
                sendThemeModeChange(dark: !theme.colors.isDark)
                _ = context.sharedContext.accountManager.transaction { transaction -> Void in
                    transaction.updateSharedData(ApplicationSharedPreferencesKeys.autoNight, { entry in
                        let settings: AutoNightThemePreferences = entry?.get(AutoNightThemePreferences.self) ?? AutoNightThemePreferences.defaultSettings
                        return PreferencesEntry(settings.withUpdatedSystemBased(false).withUpdatedSchedule(nil))
                    })
                    transaction.updateSharedData(ApplicationSharedPreferencesKeys.themeSettings, { entry in
                        let settings = entry?.get(ThemePaletteSettings.self) ?? ThemePaletteSettings.defaultTheme
                        return PreferencesEntry(settings.withUpdatedToDefault(dark: !theme.colors.isDark).withUpdatedDefaultIsDark(!theme.colors.isDark))
                    })
                }.start()
            })
        } else {
            sendThemeModeChange(dark: !theme.colors.isDark)
            _ = updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings -> ThemePaletteSettings in
                return settings.withUpdatedToDefault(dark: !theme.colors.isDark).withUpdatedDefaultIsDark(!theme.colors.isDark)
            }).start()
        }
    })
}

func sendThemeModeChange(dark: Bool) {
}

func sendThemeModeSystem() {
}
