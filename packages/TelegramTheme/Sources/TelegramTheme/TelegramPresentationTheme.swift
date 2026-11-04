import Cocoa
import Svg
import GZIP
import TGUIKit
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import TelegramIconsTheme
import ColorPalette
import ThemeSettings
#if !SHARE
#endif

public struct ActivitiesTheme : Equatable {
    public let textColor:NSColor
    public let backgroundColor:NSColor
    public init(textColor:NSColor, backgroundColor:NSColor) {
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
    
    public static func ==(lhs: ActivitiesTheme, rhs: ActivitiesTheme) -> Bool {
        return lhs.textColor.argb == rhs.textColor.argb && lhs.backgroundColor.argb == rhs.backgroundColor.argb
    }
}


public final class TelegramTabBarTheme  {
    public let color: NSColor
    public let selectedColor: NSColor
    public let badgeTextColor: NSColor
    public let badgeColor: NSColor
    private let resources: PresentationsResourceCache = PresentationsResourceCache()
    public init(color: NSColor, selectedColor: NSColor, badgeTextColor: NSColor, badgeColor: NSColor) {
        self.color = color
        self.selectedColor = selectedColor
        self.badgeTextColor = badgeTextColor
        self.badgeColor = badgeColor
    }
    
    public func icon(key:Int32, image: NSImage, selected: Bool) -> CGImage {
        let color = self.color
        let selectedColor = self.selectedColor
        return resources.image(key + (selected ? 10 : 0), { () -> CGImage in
            return image.precomposed(selected ? selectedColor : color)
        })
    }
}


public final class TelegramChatListTheme {
    public let selectedBackgroundColor: NSColor
    public let singleLayoutSelectedBackgroundColor: NSColor
    public let activeDraggingBackgroundColor: NSColor
    public let pinnedBackgroundColor: NSColor
    public let contextMenuBackgroundColor: NSColor
    
    public let textColor: NSColor
    public let grayTextColor: NSColor
    public let secretChatTextColor: NSColor
    public let peerTextColor: NSColor
    
    public let activityColor: NSColor
    public let activitySelectedColor: NSColor
    public let activityContextMenuColor: NSColor
    public let activityPinnedColor: NSColor
    
    public let badgeTextColor: NSColor
    public let badgeBackgroundColor: NSColor
    public let badgeSelectedTextColor: NSColor
    public let badgeSelectedBackgroundColor: NSColor
    public let badgeMutedTextColor: NSColor
    public let badgeMutedBackgroundColor: NSColor
    

    public init(selectedBackgroundColor: NSColor, singleLayoutSelectedBackgroundColor: NSColor, activeDraggingBackgroundColor: NSColor, pinnedBackgroundColor: NSColor, contextMenuBackgroundColor: NSColor, textColor: NSColor, grayTextColor: NSColor, secretChatTextColor: NSColor, peerTextColor: NSColor, activityColor: NSColor, activitySelectedColor: NSColor, activityContextMenuColor: NSColor, activityPinnedColor: NSColor, badgeTextColor: NSColor, badgeBackgroundColor: NSColor, badgeSelectedTextColor: NSColor, badgeSelectedBackgroundColor: NSColor,  badgeMutedTextColor: NSColor, badgeMutedBackgroundColor: NSColor) {
        
        
        
    
        
        self.selectedBackgroundColor = selectedBackgroundColor
        self.singleLayoutSelectedBackgroundColor = singleLayoutSelectedBackgroundColor
        self.activeDraggingBackgroundColor = activeDraggingBackgroundColor
        self.pinnedBackgroundColor = pinnedBackgroundColor
        self.contextMenuBackgroundColor = contextMenuBackgroundColor
        self.textColor = textColor
        self.grayTextColor = grayTextColor
        self.secretChatTextColor = secretChatTextColor
        self.peerTextColor = peerTextColor
        
        self.activityColor = activityColor
        self.activitySelectedColor = activitySelectedColor
        self.activityPinnedColor = activityPinnedColor
        self.activityContextMenuColor = activityContextMenuColor
        
        self.badgeTextColor = badgeTextColor
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeSelectedTextColor = badgeSelectedTextColor
        self.badgeSelectedBackgroundColor = badgeSelectedBackgroundColor
        self.badgeMutedTextColor = badgeMutedTextColor
        self.badgeMutedBackgroundColor = badgeMutedBackgroundColor

    }
}


extension WallpaperSettings {
    public func withUpdatedColor(_ color: UInt32?) -> WallpaperSettings {
        return WallpaperSettings(blur: self.blur, motion: self.motion, colors: color != nil ? [color!] : [], intensity: self.intensity)
    }
    
    public func isSemanticallyEqual(to other: WallpaperSettings) -> Bool {
        return self.colors == other.colors && self.intensity == other.intensity
    }
}



public func getAverageColor(_ image: NSImage) -> NSColor {
    let context = DrawingContext(size: CGSize(width: 1.0, height: 1.0), scale: 1.0, clear: false)
    context.withFlippedContext({ [weak image] context in
        if let cgImage = image {
            context.draw(cgImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0))
        }
    })
    var color = context.colorAt(CGPoint())
    
    var hue: CGFloat = 0.0
    var saturation: CGFloat = 0.0
    var brightness: CGFloat = 0.0
    var alpha: CGFloat = 0.0
//    color = color.usingColorSpaceName(NSColorSpaceName.deviceRGB)!
    color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    saturation = min(1.0, saturation + 0.1 + 0.1 * (1.0 - saturation))
    brightness = max(0.0, brightness * 0.65)
    alpha = 0.5
    color = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    
    return color
}

public func getAverageColor(_ color: NSColor) -> NSColor {
    var hue: CGFloat = 0.0
    var saturation: CGFloat = 0.0
    var brightness: CGFloat = 0.0
    var alpha: CGFloat = 0.0
    let color = color.usingColorSpaceName(NSColorSpaceName.deviceRGB)!
    color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    saturation = min(1.0, saturation + 0.1 + 0.1 * (1.0 - saturation))
    brightness = max(0.0, brightness * 0.65)
    alpha = 0.5
    
    return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
}

public func backgroundExists(_ wallpaper: Wallpaper, palette: ColorPalette) -> Bool {
    #if !SHARE
    switch wallpaper {
    case .builtin:
        return true
    case .color:
        return true
    case .gradient(_, _, _):
        return true
    case let .image(representation, settings):
        if let resource = largestImageRepresentation(representation)?.resource {
            return FileManager.default.fileExists(atPath: wallpaperPath(resource, palette: palette, settings: settings))
        } else {
            return false
        }
        
    case let .file(_, file, settings, _, gift):
        let fileExists = FileManager.default.fileExists(atPath: wallpaperPath(file.resource, palette: palette, settings: settings, gift: gift))
        let metaDataExists: Bool
        if let gift {
            metaDataExists = FileManager.default.fileExists(atPath: wallpaperMetadataPath(file.resource, settings: settings, gift: gift))
        } else {
            metaDataExists = true
        }
        return fileExists && metaDataExists
    case .none:
        return true
    case let .custom(representation, blurred):
        return FileManager.default.fileExists(atPath: wallpaperPath(representation.resource, palette: palette, settings: WallpaperSettings(blur: blurred)))
    case .emoticon:
        return true
    }
    #else
    return false
    #endif
}

public func generateBackgroundMode(_ wallpaper: Wallpaper, palette: ColorPalette, maxSize: NSSize = NSMakeSize(1040, 1580), emoticonThemes: [(ChatTheme, TelegramPresentationTheme)], scaleFactor: CGFloat = System.backingScale) -> TableBackgroundMode {
    #if !SHARE
    var backgroundMode: TableBackgroundMode
    // Cap the decoded wallpaper at the on-screen pixel size instead of holding the full native bitmap:
    // the layer never shows more than maxSize points at the backing scale, so a larger source is pure memory.
    let maxPixelSize = max(maxSize.width, maxSize.height) * scaleFactor
    switch wallpaper {
    case .builtin:
        backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
    case let.color(color):
        backgroundMode = .color(color: NSColor(color))
    case let .gradient(_, colors, rotation):
        backgroundMode = .gradient(colors: colors.map({ NSColor(argb: $0).withAlphaComponent(1.0) }), rotation: rotation)
    case let .image(representation, settings):
        if let resource = largestImageRepresentation(representation)?.resource, let image = downsampledImage(contentsOfFile: wallpaperPath(resource, palette: palette, settings: settings), maxPixelSize: maxPixelSize) {
            backgroundMode = .background(image: image, intensity: settings.intensity, colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation, metadata: nil)
        } else {
            backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
        }
        
    case let .file(_, file, settings, _, gift):
        if let image = downsampledImage(contentsOfFile: wallpaperPath(file.resource, palette: palette, settings: settings, gift: gift), maxPixelSize: maxPixelSize) {
            let svg_metadata: SVG_SlotsMetadata?
            if let gift {
                svg_metadata = try? loadSlotsMetadata(from:URL(fileURLWithPath: wallpaperMetadataPath(file.resource, settings: settings, gift: gift)))
            } else {
                svg_metadata = nil
            }
            backgroundMode = .background(image: image, intensity: settings.intensity, colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation, metadata: svg_metadata)
        } else {
            backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
        }
    case .none:
        backgroundMode = .color(color: palette.listBackground)
    case let .custom(representation, blurred):
        if let image = downsampledImage(contentsOfFile: wallpaperPath(representation.resource, palette: palette, settings: WallpaperSettings(blur: blurred)), maxPixelSize: maxPixelSize) {
            backgroundMode = .background(image: image, intensity: nil, colors: nil, rotation: nil, metadata: nil)
        } else {
            backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
        }
    case let .emoticon(emoticon):
        if let first = emoticonThemes.first(where: { $0.0.id == emoticon.strippedEmoji }) {
            backgroundMode = first.1.backgroundMode
        } else {
            backgroundMode = .plain
        }
    }
    return backgroundMode
    #else
    return .plain
    #endif
}
#if !SHARE
private let builtinBackgroundLock = NSLock()
// The builtin wallpaper depends only on isDark (the dark variant is a palette-independent black overlay),
// so render it at most once per variant instead of re-parsing the SVG on every thumbnail/fallback call.
private var builtinBackgroundCache: [Bool: NSImage] = [:]
private func builtinBackgound(_ palette: ColorPalette) -> NSImage {
    builtinBackgroundLock.lock()
    if let cached = builtinBackgroundCache[palette.isDark] {
        builtinBackgroundLock.unlock()
        return cached
    }
    builtinBackgroundLock.unlock()
    let data = try? Data(contentsOf: Bundle.main.url(forResource: "builtin-wallpaper-svg", withExtension: nil)!)
    if let data = data {
        var image = drawSvgImageNano(TGGUnzipData(data, 8 * 1024 * 1024)!, NSMakeSize(400, 800), nil)!

        let intense = CGFloat(0.5)
        if palette.isDark {
            image = generateImage(image.size, contextGenerator: { size, ctx in
                ctx.clear(size.bounds)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(size.bounds)
                ctx.clip(to: size.bounds, mask: image._cgImage!)
                
                ctx.clear(size.bounds)
                ctx.setFillColor(NSColor.black.withAlphaComponent(1 - intense).cgColor)
                ctx.fill(size.bounds)
            })!._NSImage
        }
        builtinBackgroundLock.lock()
        builtinBackgroundCache[palette.isDark] = image
        builtinBackgroundLock.unlock()
        return image
    } else {
        return generateImage(NSMakeSize(400, 800), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
            ctx.setFillColor(palette.background.cgColor)
        })!._NSImage
    }
}
#endif
open class TelegramPresentationTheme : PresentationTheme {
    public let chatList:TelegramChatListTheme
    #if !SHARE
    public let chat: TelegramChatColors
    #endif
    public let cloudTheme: TelegramTheme?
    public let tabBar:TelegramTabBarTheme
    public let icons: TelegramIconsTheme
    public let bubbled: Bool
    public let wallpaper: ThemeWallpaper
    public let emoticonThemes: [(ChatTheme, TelegramPresentationTheme)]
    public let liquidGlass: Bool
    public let liteMode: LiteMode
    public let scaleFactor: CGFloat
    
    
    #if !SHARE
    public static func defaultBackground(_ palette: ColorPalette)-> TableBackgroundMode {
        return .background(image: builtinBackgound(palette), intensity: nil, colors: [0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884].map { .init(argb: $0) }, rotation: nil, metadata: nil)
    }
    #endif
    

   
    private var _emptyChatNavigationPrev: CGImage?
    private var _emptyChatNavigationNext: CGImage?
    open var emptyChatNavigationPrev: CGImage {
        if let icon = _emptyChatNavigationPrev {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconGeneralNext).precomposed(self.chatServiceItemTextColor, flipHorizontal: true)
            _emptyChatNavigationPrev = new
            return new
        }
    }
    open var emptyChatNavigationNext: CGImage {
        if let icon = _emptyChatNavigationNext {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconGeneralNext).precomposed(self.chatServiceItemTextColor)
            _emptyChatNavigationNext = new
            return new
        }
    }
    
    private var _chatReadMarkServiceOverlayBubble1: CGImage?
    private var _chatReadMarkServiceOverlayBubble2: CGImage?
    open var chatReadMarkServiceOverlayBubble1: CGImage {
        if let icon = _chatReadMarkServiceOverlayBubble1 {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconMessageCheckMark1).precomposed(self.chatServiceItemTextColor)
            _chatReadMarkServiceOverlayBubble1 = new
            return new
        }
    }
    open var chatReadMarkServiceOverlayBubble2: CGImage {
        if let icon = _chatReadMarkServiceOverlayBubble2 {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconMessageCheckmark2).precomposed(self.chatServiceItemTextColor)
            _chatReadMarkServiceOverlayBubble2 = new
            return new
        }
    }
    
    private var _chatSendingOverlayServiceFrame: CGImage?
    private var _chatSendingOverlayServiceHour: CGImage?
    private var _chatSendingOverlayServiceMin: CGImage?
    open var chatSendingOverlayServiceFrame: CGImage {
        if let icon = _chatSendingOverlayServiceFrame {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.sendingFrame(self.chatServiceItemTextColor)
            _chatSendingOverlayServiceFrame = new
            return new
        }
    }
    open var chatSendingOverlayServiceHour: CGImage {
        if let icon = _chatSendingOverlayServiceHour {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.clockMinImage(self.chatServiceItemTextColor)
            _chatSendingOverlayServiceHour = new
            return new
        }
    }
    open var chatSendingOverlayServiceMin: CGImage {
        if let icon = _chatSendingOverlayServiceMin {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.clockMinImage(self.chatServiceItemTextColor)
            _chatSendingOverlayServiceMin = new
            return new
        }
    }
    
    private var _chatChannelViewsOverlayServiceBubble: CGImage?
    open var chatChannelViewsOverlayServiceBubble: CGImage {
        if let icon = _chatChannelViewsOverlayServiceBubble {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconChannelViews).precomposed(self.chatServiceItemTextColor)
            _chatChannelViewsOverlayServiceBubble = new
            return new
        }
    }
    
    private var _chatPaidMessageOverlayServiceBubble: CGImage?
    open var chatPaidMessageOverlayServiceBubble: CGImage {
        if let icon = _chatPaidMessageOverlayServiceBubble {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconPaidMessageStatus).precomposed(self.chatServiceItemTextColor)
            _chatPaidMessageOverlayServiceBubble = new
            return new
        }
    }

    private var _chatDiceStakeOverlayServiceBubble: CGImage?
    open var chatDiceStakeOverlayServiceBubble: CGImage {
        if let icon = _chatDiceStakeOverlayServiceBubble {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconTonCurrency).precomposed(self.chatServiceItemTextColor, zoom: 0.8)
            _chatDiceStakeOverlayServiceBubble = new
            return new
        }
    }

    private var _chat_pinned_message_overlay_service_bubble: CGImage?
    open var chat_pinned_message_overlay_service_bubble: CGImage {
        if let icon = _chat_pinned_message_overlay_service_bubble {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconChatPinnedMessage).precomposed(self.chatServiceItemTextColor)
            _chat_pinned_message_overlay_service_bubble = new
            return new
        }
    }
    
    
    private var _chat_reply_count_overlay_service_bubble: CGImage?
    open var chat_reply_count_overlay_service_bubble: CGImage {
        if let icon = _chat_reply_count_overlay_service_bubble {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconChatRepliesCount).precomposed(self.chatServiceItemTextColor)
            _chat_reply_count_overlay_service_bubble = new
            return new
        }
    }
    
    
    private var _chat_comments_overlay: CGImage?
    open var chat_comments_overlay: CGImage {
        if let icon = _chat_comments_overlay {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.image(.iconChannelCommentsOverlay).precomposed(self.chatServiceItemTextColor)
            _chat_comments_overlay = new
            return new
        }
    }
    private var _chat_toggle_selected: CGImage?
    open var chat_toggle_selected: CGImage {
        if let icon = _chat_toggle_selected {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.chatGroupToggleSelected(colors.accentIcon, colors.underSelectedColor)
            _chat_toggle_selected = new
            return new
        }
    }
    private var _chat_toggle_unselected: CGImage?
    open var chat_toggle_unselected: CGImage {
        if let icon = _chat_toggle_unselected {
            return icon
        } else {
            let new = TelegramThemeHooks.shared.chatGroupToggleUnselected(chatBackground ==  chatServiceItemColor ? colors.grayIcon.withAlphaComponent(0.6) : chatServiceItemColor, NSColor.black.withAlphaComponent(0.05))
            _chat_toggle_unselected = new
            return new
        }
    }
    
    private var _empty_chat_showtips: CGImage?
    open var empty_chat_showtips: CGImage {
        if let icon = _empty_chat_showtips {
            return icon
        } else {
            _empty_chat_showtips = TelegramThemeHooks.shared.image(.iconEmptyShowTips).precomposed(chatServiceItemTextColor)
            return _empty_chat_showtips!
        }
    }
    private var _empty_chat_hidetips: CGImage?
    open var empty_chat_hidetips: CGImage {
        if let icon = _empty_chat_hidetips {
            return icon
        } else {
            _empty_chat_hidetips = TelegramThemeHooks.shared.image(.iconEmptyCloseTips).precomposed(chatServiceItemTextColor)
            return _empty_chat_hidetips!
        }
    }

    open var blurServiceColor: NSColor {
        return NSColor.black.withAlphaComponent(colors.isDark ? 0.5 : 0.25)
    }
    
    private var _chatServiceItemColor: NSColor?
    open var chatServiceItemColor: NSColor {
        if let value = _chatServiceItemColor {
            return value
        } else {
            let chatServiceItemColor: NSColor
            if bubbled {
                switch backgroundMode {
                case let .background(image, _, colors, _, _):
                    if let colors = colors, colors.count > 0 {
                        let blended = NSColor.average(of: colors).withAlphaComponent(0.6)
                        if self.colors.isDark {
                            chatServiceItemColor = NSColor.average(of: [getAverageColor(image), getAverageColor(blended)])
                        } else {
                            chatServiceItemColor = getAverageColor(blended)
                        }
                    } else {
                        chatServiceItemColor = getAverageColor(image)
                    }
                case let .color(color):
                    if color != colors.background {
                        chatServiceItemColor = color
                    } else {
                        chatServiceItemColor = color
                    }
                case let .gradient(colors, _):
                    let blended = colors.reduce(colors.first!, { color, with in
                        return color.blended(withFraction: 0.5, of: with)!
                    })
                    chatServiceItemColor = getAverageColor(blended)

                case let .tiled(image):
                    chatServiceItemColor = getAverageColor(image)
                case .plain:
                    chatServiceItemColor = colors.chatBackground
                }
            } else {
                chatServiceItemColor = colors.chatBackground
            }
           
            self._chatServiceItemColor = chatServiceItemColor
            return chatServiceItemColor
        }
    }
    private var _chatServiceItemTextColor: NSColor?
    open var chatServiceItemTextColor: NSColor {
        if let value = _chatServiceItemTextColor {
            return value
        } else {
            let chatServiceItemTextColor: NSColor
            if bubbled {
                switch backgroundMode {
                case .background:
                    chatServiceItemTextColor = NSColor(rgb: 0xffffff)
                case let .color(color):
                    if color != colors.background {
                        chatServiceItemTextColor = chatServiceItemColor.brightnessAdjustedColor
                    } else {
                        chatServiceItemTextColor = colors.grayText
                    }
                case .gradient:
                    chatServiceItemTextColor = chatServiceItemColor.brightnessAdjustedColor
                case .tiled:
                    chatServiceItemTextColor = chatServiceItemColor.brightnessAdjustedColor
                case .plain:
                    chatServiceItemTextColor = colors.grayText
                }
            } else {
                chatServiceItemTextColor = colors.grayText
            }
            
            self._chatServiceItemTextColor = chatServiceItemTextColor
            return chatServiceItemTextColor
        }
    }
    
    public let fontSize: CGFloat
    
    open var hasWallpaper: Bool {
        if !self.bubbled {
            return false
        } else {
            switch self.wallpaper.wallpaper {
            case .color:
                return false
            case .builtin:
                return true
            case .none:
                return false
            default:
                return true
            }
        }
    }
    open var shouldBlurService: Bool {
        
        if #available(macOS 10.14, *) {
            return false
        } else {
            return false
        }
    }
    
    open var controllerBackgroundMode: TableBackgroundMode {
        if self.bubbled {
            return self.backgroundMode
        } else {
            return .color(color: colors.chatBackground)
        }
    }
    
    open var chatBackground: NSColor {
        return self.colors.chatBackground
    }
    
    // private(set): backgroundSize now drives the wallpaper decode resolution, so an external mutation would
    // blur the chat background (see withUpdatedBackgroundSize, which returns a copy instead of mutating).
    public private(set) var backgroundSize: NSSize = NSMakeSize(1040, 1580)
    
    private let backgroundModeLock = NSLock()
    private var _backgroundMode: TableBackgroundMode?
    open var backgroundMode: TableBackgroundMode {
        backgroundModeLock.lock()
        defer { backgroundModeLock.unlock() }
        if let value = _backgroundMode {
            return value
        }

        let computed: TableBackgroundMode
        switch wallpaper.wallpaper {
        case .emoticon:
            computed = generateBackgroundMode(wallpaper.wallpaper, palette: colors, maxSize: backgroundSize, emoticonThemes: self.emoticonThemes, scaleFactor: scaleFactor)
        default:
            if let cached = cachedBackground(wallpaper.wallpaper, palette: colors, size: backgroundSize, scaleFactor: scaleFactor) {
                computed = cached
            } else {
                computed = generateBackgroundMode(wallpaper.wallpaper, palette: colors, maxSize: backgroundSize, emoticonThemes: self.emoticonThemes, scaleFactor: scaleFactor)
                cacheBackground(wallpaper.wallpaper, palette: colors, size: backgroundSize, background: computed, scaleFactor: scaleFactor)
            }
        }
        self._backgroundMode = computed
        return computed
    }
    public init(colors: ColorPalette, cloudTheme: TelegramTheme?, search: SearchTheme, chatList: TelegramChatListTheme, tabBar: TelegramTabBarTheme, icons: TelegramIconsTheme, bubbled: Bool, fontSize: CGFloat, wallpaper: ThemeWallpaper, generated: Bool = false, emoticonThemes: [(ChatTheme, TelegramPresentationTheme)] = [], backgroundSize: NSSize = NSMakeSize(1040, 1580), liquidGlass: Bool = System.liquidGlassAvailable, liteMode: LiteMode = TelegramPresentationTheme.currentLiteMode(), scaleFactor: CGFloat = System.backingScale) {
        self.chatList = chatList
        #if !SHARE
            self.chat = TelegramChatColors(colors, bubbled)
        #endif
        self.backgroundSize = backgroundSize
        self.tabBar = tabBar
        self.icons = icons
        self.wallpaper = wallpaper
        self.bubbled = bubbled
        self.emoticonThemes = emoticonThemes
        self.fontSize = fontSize
        self.cloudTheme = cloudTheme
        self.liquidGlass = liquidGlass && System.liquidGlassAvailable
        self.liteMode = liteMode
        self.scaleFactor = scaleFactor
        let inputSelectingColor = colors.isDark ? colors.accentSelect : colors.accentSelect.withAlphaComponent(0.65)
        super.init(colors: colors, search: search, inputTheme: .init(quote: .init(foreground: .init(main: colors.accent), icon: TelegramThemeHooks.shared.image(.iconQuote), collapse: TelegramThemeHooks.shared.image(.iconQuoteCollapse), expand: TelegramThemeHooks.shared.image(.iconQuoteExpand)), indicatorColor: colors.accent, backgroundColor: colors.background, selectingColor: inputSelectingColor, textColor: colors.text, accentColor: colors.accent, grayTextColor: colors.grayText, fontSize: fontSize))
        if !Thread.isMainThread && generated {
            _ = self.backgroundMode
        }
    }
    
    public static func currentLiteMode() -> LiteMode {
        return TelegramThemeHooks.shared.liteMode()
    }

    open var dark: Bool {
        return colors.isDark
    }
    #if !SHARE
    open var insantPageThemeType: InstantPageThemeType {
        if colors.isDark {
            return .dark
        } else {
            return .light
        }
    }
    #endif
    
    
    deinit {

    }

    /// Value-based equality on the params that drive the theme. Overrides
    /// `PresentationTheme.isEqual(_:)` (NOT `static func ==`) — the parent
    /// class's `static func ==` shadows any subclass static, so dispatching
    /// from generic code that sees the parent type would never reach a
    /// subclass static. The parent's `==` now calls `isEqual(_:)` so this
    /// override is what runs.
    /// Each branch returns false on its own line so a debugger breakpoint
    /// pinpoints which field caused inequality. Derived fields
    /// (chatList / tabBar / icons) are skipped — they're regenerated from
    /// `colors + bubbled`, so equal inputs ⇒ equal outputs.
    open override func isEqual(_ other: PresentationTheme) -> Bool {
        if self === other { return true }
        guard let other = other as? TelegramPresentationTheme else {
            return false
        }
        if self.colors != other.colors {
            return false
        }
        if self.bubbled != other.bubbled {
            return false
        }
        if self.fontSize != other.fontSize {
            return false
        }
        if self.wallpaper != other.wallpaper {
            return false
        }
        if self.backgroundSize != other.backgroundSize {
            return false
        }
        if self.liquidGlass != other.liquidGlass {
            return false
        }
        if self.liteMode != other.liteMode {
            return false
        }
        if self.scaleFactor != other.scaleFactor {
            return false
        }
        if self.cloudTheme != other.cloudTheme {
            return false
        }
        if self.emoticonThemes.count != other.emoticonThemes.count {
            return false
        }
        for (l, r) in zip(self.emoticonThemes, other.emoticonThemes) where l.0 != r.0 {
            return false
        }
        return true
    }

    open func withUpdatedColors(_ colors: ColorPalette) -> TelegramPresentationTheme {
        return TelegramPresentationTheme(colors: colors, cloudTheme: self.cloudTheme, search: self.search, chatList: self.chatList, tabBar: self.tabBar, icons: TelegramThemeHooks.shared.icons(colors, self.bubbled), bubbled: self.bubbled, fontSize: self.fontSize, wallpaper: self.wallpaper, emoticonThemes: self.emoticonThemes, backgroundSize: self.backgroundSize, liquidGlass: self.liquidGlass, liteMode: self.liteMode, scaleFactor: self.scaleFactor)
    }
    
    open func withUpdatedEmoticonThemes(_ emoticonThemes: [(ChatTheme, TelegramPresentationTheme)]) -> TelegramPresentationTheme {
        return TelegramPresentationTheme(colors: colors, cloudTheme: self.cloudTheme, search: self.search, chatList: self.chatList, tabBar: self.tabBar, icons: self.icons, bubbled: self.bubbled, fontSize: self.fontSize, wallpaper: self.wallpaper, emoticonThemes: emoticonThemes, backgroundSize: self.backgroundSize, liquidGlass: self.liquidGlass, liteMode: self.liteMode, scaleFactor: self.scaleFactor)
    }
    
    open func withUpdatedChatMode(_ bubbled: Bool) -> TelegramPresentationTheme {
        return TelegramPresentationTheme(colors: colors, cloudTheme: self.cloudTheme, search: self.search, chatList: self.chatList, tabBar: self.tabBar, icons: TelegramThemeHooks.shared.icons(colors, bubbled), bubbled: bubbled, fontSize: self.fontSize, wallpaper: self.wallpaper, emoticonThemes: self.emoticonThemes, backgroundSize: self.backgroundSize, liquidGlass: self.liquidGlass, liteMode: self.liteMode, scaleFactor: self.scaleFactor)
    }
    open func new() -> TelegramPresentationTheme {
        return TelegramPresentationTheme(colors: self.colors, cloudTheme: self.cloudTheme, search: self.search, chatList: self.chatList, tabBar: self.tabBar, icons: self.icons, bubbled: self.bubbled, fontSize: self.fontSize, wallpaper: self.wallpaper, emoticonThemes: self.emoticonThemes, backgroundSize: self.backgroundSize, liteMode: TelegramPresentationTheme.currentLiteMode(), scaleFactor: System.backingScale)
    }

    
    open func withUpdatedBackgroundSize(_ size: NSSize) -> TelegramPresentationTheme {
        // Return a copy rather than mutating self: a preview (Appearance/color pickers) derives a small
        // backgroundSize from the LIVE theme, and now that backgroundSize drives the wallpaper decode
        // resolution, mutating self would shrink the real chat wallpaper on the next theme derivation.
        return TelegramPresentationTheme(colors: self.colors, cloudTheme: self.cloudTheme, search: self.search, chatList: self.chatList, tabBar: self.tabBar, icons: self.icons, bubbled: self.bubbled, fontSize: self.fontSize, wallpaper: self.wallpaper, emoticonThemes: self.emoticonThemes, backgroundSize: size, liquidGlass: self.liquidGlass, liteMode: self.liteMode, scaleFactor: self.scaleFactor)
    }
    
    open func withUpdatedWallpaper(_ wallpaper: ThemeWallpaper) -> TelegramPresentationTheme {
        return TelegramPresentationTheme(colors: self.colors, cloudTheme: self.cloudTheme, search: self.search, chatList: self.chatList, tabBar: self.tabBar, icons: self.icons, bubbled: self.bubbled, fontSize: self.fontSize, wallpaper: wallpaper, emoticonThemes: self.emoticonThemes, backgroundSize: self.backgroundSize, liquidGlass: self.liquidGlass, liteMode: self.liteMode, scaleFactor: self.scaleFactor)
    }
    
    open func activity(key:Int32, foregroundColor: NSColor, backgroundColor: NSColor) -> ActivitiesTheme {
        return activityResources.object(key, { () -> Any in
            return ActivitiesTheme(textColor: foregroundColor, backgroundColor: backgroundColor)
        }) as! ActivitiesTheme
    }
    
    private let activityResources: PresentationsResourceCache = PresentationsResourceCache()
    
}

public let _themeSignal:ValuePromise<TelegramPresentationTheme> = ValuePromise(ignoreRepeated: true)

public var themeSignal:Signal<TelegramPresentationTheme, NoError> {
    return _themeSignal.get() |> distinctUntilChanged |> deliverOnMainQueue
}

extension ColorPalette {
    public var transparentBackground: NSColor {
        return NSColor(patternImage: NSImage(cgImage: theme.icons.transparentBackground, size: theme.icons.transparentBackground.backingSize))
    }
    public var lottieTransparentBackground: NSColor {
        return NSColor(patternImage: NSImage(cgImage: theme.icons.lottieTransparentBackground, size: theme.icons.lottieTransparentBackground.backingSize))
    }
}
