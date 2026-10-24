import Cocoa
import CoreMedia
import SwiftSignalKit
import TelegramCore
import ColorPalette
import Postbox
import TGUIKit
import ThemeSettings
import FoundationUtils

public enum ThemeSource : Equatable {
    case local(ColorPalette, TelegramTheme?)
    case cloud(TelegramTheme)
}

private final class WallpaperCachedRecord {
    public let mode:TableBackgroundMode
    public let cost: Int
    public init(mode:TableBackgroundMode) {
        self.mode = mode
        switch mode {
        case let .background(image, _, _, _, _), let .tiled(image):
            if let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let bytes = bitmap.bytesPerRow.multipliedReportingOverflow(by: bitmap.height)
                self.cost = bytes.overflow ? Int.max : bytes.partialValue
            } else {
                self.cost = 0
            }
        default:
            self.cost = 0
        }
    }
}

private final class WeakWallpaperCachedRecord {
    public let restoreMode: () -> TableBackgroundMode?

    public init?(mode: TableBackgroundMode) {
        switch mode {
        case let .background(image, intensity, colors, rotation, metadata):
            self.restoreMode = { [weak image] in
                guard let image = image else {
                    return nil
                }
                return .background(image: image, intensity: intensity, colors: colors, rotation: rotation, metadata: metadata)
            }
        case let .tiled(image):
            self.restoreMode = { [weak image] in
                guard let image = image else {
                    return nil
                }
                return .tiled(image: image)
            }
        default:
            return nil
        }
    }
}


public enum AppearanceThumbSource : Int32 {
    case general
    case widget
}

public enum PhotoCacheKeyEntry : Hashable {
    case avatar(PeerId, TelegramMediaImageRepresentation, PeerNameColor?, NSSize, CGFloat, Bool, Bool)
    case emptyAvatar(PeerId, String, NSColor, NSSize, CGFloat, Bool, Bool)
    case media(Media, TransformImageArguments, CGFloat, LayoutPositionFlags?)
    case slot(SlotMachineValue, TransformImageArguments, CGFloat)
    case platformTheme(TelegramThemeSettings, TransformImageArguments, CGFloat, LayoutPositionFlags?)
    case background(Wallpaper, ColorPalette, NSSize)
    case messageId(stableId: Int64, TransformImageArguments, CGFloat, LayoutPositionFlags)
    case theme(ThemeSource, Bool, AppearanceThumbSource)
    case emoji(String, CGFloat)
    public func hash(into hasher: inout Hasher) {
        
        switch self {
        case let .avatar(peerId, rep, nameColor, size, scale, isForum, isMonoforum):
            hasher.combine("avatar")
            hasher.combine(rep.resource.id.hashValue)
            hasher.combine(peerId.toInt64())
            hasher.combine(size.width)
            hasher.combine(size.height)
            hasher.combine(scale)
            hasher.combine(isForum)
            hasher.combine(isMonoforum)
            if let nameColor = nameColor {
                hasher.combine("nameColor")
                hasher.combine(nameColor.rawValue)
            }
        case let .emptyAvatar(peerId, letters, color, size, scale, isForum, _):
            hasher.combine("emptyAvatar")
            hasher.combine(peerId.toInt64())
            hasher.combine(color.hashValue)
            hasher.combine(letters)
            hasher.combine(size.width)
            hasher.combine(size.height)
            hasher.combine(scale)
            hasher.combine(isForum)
        case let .media(media, transform, scale, layout):
            hasher.combine("media")
            
            if let media = media as? TelegramMediaMap {
                hasher.combine(media.longitude)
                hasher.combine(media.latitude)
            }
            
            if let media = media as? TelegramMediaFile {
                hasher.combine(media.resource.id.stringRepresentation)
                if let size = media.resource.size {
                    hasher.combine(size)
                }
                #if !SHARE
                if let fitz = media.animatedEmojiFitzModifier {
                    hasher.combine(fitz.rawValue)
                }
                #endif
            }
            if let media = media.id {
                hasher.combine(media.id)
            }
            hasher.combine(transform)
            if let layout = layout {
                hasher.combine(layout.rawValue)
            }
            hasher.combine(scale)
        case let .slot(slot, transform, scale):
            hasher.combine("slot")
            hasher.combine(slot)
            hasher.combine(transform)
            hasher.combine(scale)
        case let .messageId(stableId, transform, scale, layout):
            hasher.combine("messageId")
            hasher.combine(stableId)
            hasher.combine(transform)
            hasher.combine(scale)
            hasher.combine(layout.rawValue)
        case let .theme(source, bubbled, thumbSource):
            hasher.combine(bubbled)
            
            switch source {
            case let .local(palette, cloud):
                hasher.combine("theme-local")
                if let settings = cloud?.effectiveSettings(for: palette) {
                    #if !SHARE
                    hasher.combine(palette.name)
                    hasher.combine(settings.desc)
                    hasher.combine(thumbSource.rawValue)
                    #endif
                } else {
                    hasher.combine(palette.name)
                    hasher.combine(palette.accent.argb)
                    hasher.combine(thumbSource.rawValue)
                }
            case let .cloud(cloud):
                hasher.combine("theme-local")
                hasher.combine(cloud.id)
                if let file = cloud.file {
                    hasher.combine(file.fileId.id)
                }
                hasher.combine(thumbSource.rawValue)
            }
        case let .platformTheme(settings, arguments, scale, layout):
            hasher.combine("platformTheme")
            #if !SHARE
            hasher.combine(settings.desc)
            hasher.combine(scale)
            hasher.combine(arguments)
            if let layout = layout {
                hasher.combine(layout.rawValue)
            }
            #endif
        case let .emoji(emoji, scale):
            hasher.combine("emoji")
            hasher.combine(emoji)
            hasher.combine(scale)
        case let .background(wallpaper, palette, size):
            hasher.combine("wallpaper")
            hasher.combine(palette.name)
            // Key by the longest side (rounded): it is what the decode cap, and therefore the cached bitmap
            // resolution, is derived from — and it avoids spurious entries from sub-pixel float differences.
            hasher.combine(Int(max(size.width, size.height).rounded()))
            switch wallpaper {
            case .none:
                hasher.combine("none")
            case .builtin:
                hasher.combine("builtin")
            case let .color(color):
                hasher.combine("color")
                hasher.combine("\(color)")
            case let .custom(rep, blurred):
                hasher.combine("custom")
                hasher.combine("\(rep.resource.id.hashValue)")
                hasher.combine("\(blurred)")
            case let .emoticon(emoticon):
                hasher.combine("emoticon")
                hasher.combine("\(emoticon)")
            case let .file(slug, file, settings, isPattern, gift):
                hasher.combine("file")
                hasher.combine("\(slug)")
                hasher.combine("\(file.fileId.id)")
                hasher.combine("\(settings.colors)")
                hasher.combine("\(settings.blur)")
                hasher.combine("\(settings.motion)")
                hasher.combine("\(String(describing: settings.rotation))")
                if let gift {
                    hasher.combine(gift.slug)
                }
                hasher.combine("\(isPattern)")
            case let .image(reps, settings):
                hasher.combine("image")
                for rep in reps {
                    hasher.combine("\(rep.resource.id.hashValue)")
                }
                hasher.combine("\(settings.colors)")
                hasher.combine("\(settings.blur)")
                hasher.combine("\(settings.motion)")
                hasher.combine("\(String(describing: settings.rotation))")
            case let .gradient(id, colors, rotation):
                hasher.combine("gradient")
                hasher.combine("\(String(describing: id))")
                hasher.combine("\(colors)")
                hasher.combine("\(String(describing: rotation))")
            }
        }
    }
    
    public static func ==(lhs:PhotoCacheKeyEntry, rhs: PhotoCacheKeyEntry) -> Bool {
        switch lhs {
        case let .avatar(lhsPeerId, lhsRepresentation, lhsNameColor, lhsSize, lhsScale, lhsIsForum, lhsIsMonoforum):
            if case let .avatar(rhsPeerId, rhsRepresentation, rhsNameColor, rhsSize, rhsScale, rhsIsForum, rhsIsMonoforum) = rhs {
                if lhsPeerId != rhsPeerId {
                    return false
                }
                if lhsSize != rhsSize {
                    return false
                }
                if lhsScale != rhsScale {
                    return false
                }
                if lhsNameColor != rhsNameColor {
                    return false
                }
                if lhsIsMonoforum != rhsIsMonoforum {
                    return false
                }
                if lhsRepresentation.resource.id == rhsRepresentation.resource.id  {
                    return false
                }
                if lhsIsForum != rhsIsForum {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .emptyAvatar(peerId, symbol, color, size, scale, isForum, isMonoforum):
            if case .emptyAvatar(peerId, symbol, color, size, scale, isForum, isMonoforum) = rhs {
                return true
            } else {
                return false
            }
        case let .media(lhsMedia, lhsSize, lhsScale, lhsPositionFlags):
            if case let .media(rhsMedia, rhsSize, rhsScale, rhsPositionFlags) = rhs {
                if lhsMedia.id != rhsMedia.id {
                    return false
                }
                if let lhsMedia = lhsMedia as? TelegramMediaMap, let rhsMedia = rhsMedia as? TelegramMediaMap {
                    if lhsMedia.latitude != rhsMedia.latitude || lhsMedia.longitude != rhsMedia.longitude {
                        return false
                    }
                }
                if lhsSize != rhsSize {
                    return false
                }
                if lhsPositionFlags != rhsPositionFlags {
                    return false
                }
                if lhsScale != rhsScale {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .slot(value, size, scale):
            if case .slot(value, size, scale) = rhs {
                return true
            } else {
                return false
            }
        case let .messageId(stableId, size, scale, positionFlags):
            if case .messageId(stableId, size, scale, positionFlags) = rhs {
                return true
            } else {
                return false
            }
        case let .theme(source, bubbled, thumbSource):
            if case .theme(source, bubbled, thumbSource) = rhs {
                return true
            } else {
                return false
            }
        case let .platformTheme(settings, arguments, scale, position):
            if case .platformTheme(settings, arguments, scale, position) = rhs {
                return true
            } else {
                return false
            }
        case let .emoji(emoji, scale):
            if case .emoji(emoji, scale) = rhs {
                return true
            } else {
                return false
            }
        case let .background(wallpaper, colors, size):
            if case .background(wallpaper, colors, size) = rhs {
                return true
            } else {
                return false
            }
        }
    }
}


private class WallpaperCache {
    public let memoryLimit:Int
    private var values:NSCache<NSNumber, WallpaperCachedRecord> = NSCache()
    private let weakValues = NSCache<NSNumber, WeakWallpaperCachedRecord>()
    private let lock = NSLock()
    
    public init(_ memoryLimit:Int = 100, byteLimit: Int = 64 * 1024 * 1024) {
        self.memoryLimit = memoryLimit
        self.values.countLimit = memoryLimit
        self.values.totalCostLimit = byteLimit
        self.weakValues.countLimit = memoryLimit
    }
    
    fileprivate func cacheImage(_ mode: TableBackgroundMode, for key:PhotoCacheKeyEntry) {
        let record = WallpaperCachedRecord(mode: mode)
        let cacheKey = NSNumber(value: key.hashValue)
        self.lock.lock()
        defer { self.lock.unlock() }
        if let weakRecord = WeakWallpaperCachedRecord(mode: mode) {
            self.weakValues.setObject(weakRecord, forKey: cacheKey)
        } else {
            self.weakValues.removeObject(forKey: cacheKey)
        }
        guard record.cost <= self.values.totalCostLimit else {
            self.values.removeObject(forKey: cacheKey)
            return
        }
        self.values.setObject(record, forKey: cacheKey, cost: record.cost)
    }
    
    public func cachedImage(for key:PhotoCacheKeyEntry) -> TableBackgroundMode? {
        let cacheKey = NSNumber(value: key.hashValue)
        self.lock.lock()
        defer { self.lock.unlock() }
        if let mode = self.values.object(forKey: cacheKey)?.mode {
            return mode
        }
        if let mode = self.weakValues.object(forKey: cacheKey)?.restoreMode() {
            return mode
        }
        self.weakValues.removeObject(forKey: cacheKey)
        return nil
    }
    
    public func clearAll() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.values.removeAllObjects()
        self.weakValues.removeAllObjects()
    }
}


private extension ScopedImageCache {
    func cacheImage(_ image: CGImage, sampleBuffer: CMSampleBuffer?, for key: PhotoCacheKeyEntry) {
        setImage(image, sampleBuffer: sampleBuffer, forKey: key.hashValue)
    }

    func cachedImage(for key: PhotoCacheKeyEntry) -> (CGImage, CMSampleBuffer?)? {
        return image(forKey: key.hashValue)
    }

    func clearAll() {
        removeAll()
    }
}


private let megabyte = 1024 * 1024

private let minute: TimeInterval = 60

private let closedScreenGrace: TimeInterval = 15

private let peerPhotoCache = ScopedImageCache(countLimit: 200, byteLimit: 8 * megabyte, idleTimeout: 10 * minute, closedScopeGrace: closedScreenGrace)
private let photosCache = ScopedImageCache(countLimit: 200, byteLimit: 24 * megabyte, idleTimeout: 5 * minute, closedScopeGrace: closedScreenGrace)
private let photoThumbsCache = ScopedImageCache(countLimit: 200, byteLimit: 6 * megabyte, idleTimeout: 5 * minute, closedScopeGrace: closedScreenGrace)
private let themeThums = ScopedImageCache(countLimit: 200, byteLimit: 3 * megabyte, idleTimeout: 5 * minute, closedScopeGrace: closedScreenGrace)
private let wallpaperCache = WallpaperCache(20)

private let stickersCache = ScopedImageCache(countLimit: 200, byteLimit: 8 * megabyte, idleTimeout: 10 * minute, closedScopeGrace: closedScreenGrace)
private let emojiCache = ScopedImageCache(countLimit: 10000, byteLimit: 8 * megabyte, idleTimeout: 10 * minute, closedScopeGrace: closedScreenGrace)


public func purgeImageCachesForMemoryPressure() {
    peerPhotoCache.clearAll()
    photosCache.clearAll()
    photoThumbsCache.clearAll()
    themeThums.clearAll()
    stickersCache.clearAll()
    emojiCache.clearAll()
    wallpaperCache.clearAll()
    clearMessageBubbleImageCache()
}

public func cachedPeerPhoto(_ peerId:PeerId, representation: TelegramMediaImageRepresentation, peerNameColor: PeerNameColor?, size: NSSize, scale: CGFloat, isForum: Bool, isMonoforum: Bool) -> Signal<CGImage?, NoError> {
    let entry:PhotoCacheKeyEntry = .avatar(peerId, representation, peerNameColor, size, scale, isForum, isMonoforum)
    return .single(peerPhotoCache.cachedImage(for: entry)?.0)
}

public func cachePeerPhoto(image:CGImage, peerId:PeerId, representation: TelegramMediaImageRepresentation, peerNameColor: PeerNameColor?, size: NSSize, scale: CGFloat, isForum: Bool, isMonoforum: Bool) -> Signal <Void, NoError> {
    let entry:PhotoCacheKeyEntry = .avatar(peerId, representation, peerNameColor, size, scale, isForum, isMonoforum)
    return .single(peerPhotoCache.cacheImage(image, sampleBuffer: nil, for: entry))
}

public func cachedEmptyPeerPhoto(_ peerId:PeerId, symbol: String, color: NSColor, size: NSSize, scale: CGFloat, isForum: Bool, isMonoforum: Bool) -> Signal<CGImage?, NoError> {
    let entry:PhotoCacheKeyEntry = .emptyAvatar(peerId, symbol, color, size, scale, isForum, isMonoforum)
    return .single(peerPhotoCache.cachedImage(for: entry)?.0)
}

public func cacheEmptyPeerPhoto(image:CGImage, peerId:PeerId, symbol: String, color: NSColor, size: NSSize, scale: CGFloat, isForum: Bool, isMonoforum: Bool) -> Signal <Void, NoError> {
    let entry:PhotoCacheKeyEntry = .emptyAvatar(peerId, symbol, color, size, scale, isForum, isMonoforum)
    return .single(peerPhotoCache.cacheImage(image, sampleBuffer: nil, for: entry))
}
public func cachedMedia(media: Media, arguments: TransformImageArguments, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Signal<TransformImageResult?, NoError> {
    let entry:PhotoCacheKeyEntry = .media(media, arguments, scale, positionFlags)
    let value: (CGImage, CMSampleBuffer?)?
    var full: Bool = false
    
    if arguments.imageSize.width <= 60, let media = media as? TelegramMediaFile, media.isStaticSticker || media.isAnimatedSticker {
        value = stickersCache.cachedImage(for: entry)
        full = true
    } else if let image = photosCache.cachedImage(for: entry) {
        value = image
        full = true
    } else {
        value = photoThumbsCache.cachedImage(for: entry)
    }
    if let value = value {
        return .single(TransformImageResult(value.0, full, value.1))
    } else {
        return .single(nil)
    }
}

public func cachedSlot(value: SlotMachineValue, arguments: TransformImageArguments, scale: CGFloat) -> Signal<TransformImageResult?, NoError> {
    let entry:PhotoCacheKeyEntry = .slot(value, arguments, scale)
    let value: CGImage? = stickersCache.cachedImage(for: entry)?.0
    let full: Bool = value != nil
    if let value = value {
        return .single(TransformImageResult(value, full))
    } else {
        return .single(nil)
    }
}

public func cachedMedia(media: TelegramThemeSettings, arguments: TransformImageArguments, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Signal<TransformImageResult?, NoError> {
    let entry:PhotoCacheKeyEntry = .platformTheme(media, arguments, scale, positionFlags)
    let value: (CGImage, CMSampleBuffer?)?
    var full: Bool = false
    
    if let image = photosCache.cachedImage(for: entry) {
        value = image
        full = true
    } else {
        value = nil
    }
    if let value = value {
        return .single(TransformImageResult(value.0, full, value.1))
    } else {
        return .single(nil)
    }
}

public func cachedMedia(messageId: Int64, arguments: TransformImageArguments, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Signal<TransformImageResult?, NoError> {
    let entry:PhotoCacheKeyEntry = .messageId(stableId: messageId, arguments, scale, positionFlags ?? [])
    let value: (CGImage, CMSampleBuffer?)?
    var full: Bool = false
    if let image = photosCache.cachedImage(for: entry) {
        value = image
        full = true
    } else {
        value = photoThumbsCache.cachedImage(for: entry)
    }
    if let value = value {
        return .single(TransformImageResult(value.0, full, value.1))
    } else {
        return .single(nil)
    }
}

public func cacheMedia(_ result: TransformImageResult, media: Media, arguments: TransformImageArguments, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Void {
    if let image = result.image {
        let entry:PhotoCacheKeyEntry = .media(media, arguments, scale, positionFlags)
        if arguments.imageSize.width <= 60, result.highQuality, let media = media as? TelegramMediaFile,  media.isStaticSticker || media.isAnimatedSticker {
            stickersCache.cacheImage(image, sampleBuffer: result.sampleBuffer, for: entry)
        } else if !result.highQuality {
            photoThumbsCache.cacheImage(image, sampleBuffer: result.sampleBuffer, for: entry)
        } else {
            photosCache.cacheImage(image, sampleBuffer: result.sampleBuffer, for: entry)
        }
    }
}

public func cacheSlot(_ result: TransformImageResult, value: SlotMachineValue, arguments: TransformImageArguments, scale: CGFloat) -> Void {
    if let image = result.image {
        stickersCache.cacheImage(image, sampleBuffer: nil, for: .slot(value, arguments, scale))
    }
}

public func cacheEmoji(_ image: CGImage, emoji: String, scale: CGFloat) -> Void {
    emojiCache.cacheImage(image, sampleBuffer: nil, for: .emoji(emoji, scale))
}
public func cachedEmoji(emoji: String, scale: CGFloat) -> CGImage? {
    return emojiCache.cachedImage(for: .emoji(emoji, scale))?.0
}

public func cacheMedia(_ result: TransformImageResult, media: TelegramThemeSettings, arguments: TransformImageArguments, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Void {
    if let image = result.image {
        let entry:PhotoCacheKeyEntry = .platformTheme(media, arguments, scale, positionFlags)
        photosCache.cacheImage(image, sampleBuffer: result.sampleBuffer, for: entry)
    }
}


public func cacheBackground(_ result: Wallpaper, palette: ColorPalette, size: NSSize, background: TableBackgroundMode) -> Void {
    let entry:PhotoCacheKeyEntry = .background(result, palette, size)
    wallpaperCache.cacheImage(background, for: entry)
}
public func cachedBackground(_ wallpaper: Wallpaper, palette: ColorPalette, size: NSSize) -> TableBackgroundMode? {
    return wallpaperCache.cachedImage(for: .background(wallpaper, palette, size))
}


public func cacheMedia(_ result: TransformImageResult, messageId: Int64, arguments: TransformImageArguments, scale: CGFloat, positionFlags: LayoutPositionFlags? = nil) -> Void {
    
    if let image = result.image {
        let entry:PhotoCacheKeyEntry = .messageId(stableId: messageId, arguments, scale, positionFlags ?? [])
        if !result.highQuality {
            photoThumbsCache.cacheImage(image, sampleBuffer: result.sampleBuffer, for: entry)
        } else {
            photosCache.cacheImage(image, sampleBuffer: result.sampleBuffer, for: entry)
        }
    }
}

public func cachedThemeThumb(source: ThemeSource, bubbled: Bool, thumbSource: AppearanceThumbSource = .general) -> Signal<TransformImageResult?, NoError> {
    let entry:PhotoCacheKeyEntry = .theme(source, bubbled, thumbSource)
    if let value = themeThums.cachedImage(for: entry) {
        return .single(TransformImageResult(value.0, true, value.1))
    } else {
        return .single(nil)
    }
}

public func cacheThemeThumb(_ result: TransformImageResult, source: ThemeSource, bubbled: Bool, thumbSource: AppearanceThumbSource = .general) -> Void {
    let entry:PhotoCacheKeyEntry = .theme(source, bubbled, thumbSource)
    
    if let image = result.image {
        themeThums.cacheImage(image, sampleBuffer: result.sampleBuffer, for: entry)
    }
}
