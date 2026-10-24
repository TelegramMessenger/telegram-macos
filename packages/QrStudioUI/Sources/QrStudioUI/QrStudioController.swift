import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import ColorPalette
import TelegramTheme
import LocalAnimations
import Localization

public struct QrStudioNavigationHooks {
    public static var openPremium: ((any AccountContextProtocol) -> Void)? = nil
    public static var openGiftShop: ((any AccountContextProtocol) -> Void)? = nil
    public static var shareImage: ((any AccountContextProtocol, String, String, NSWindow) -> Void)? = nil
}

private func qrStudioLookDefaultsKey(accountPeerId: PeerId, peerId: PeerId) -> String {
    if accountPeerId == peerId {
        return "qrStudioLook_\(peerId.toInt64())"
    }
    return "qrStudioLook_\(accountPeerId.toInt64())_\(peerId.toInt64())"
}

private func qrStudioLoadSettings(accountPeerId: PeerId, peerId: PeerId) -> QrStudioLookSettings? {
    guard let data = UserDefaults.standard.data(forKey: qrStudioLookDefaultsKey(accountPeerId: accountPeerId, peerId: peerId)) else {
        return nil
    }
    return try? JSONDecoder().decode(QrStudioLookSettings.self, from: data)
}

private func qrStudioStoreSettings(_ settings: QrStudioLookSettings, accountPeerId: PeerId, peerId: PeerId) {
    if let data = try? JSONEncoder().encode(settings) {
        UserDefaults.standard.set(data, forKey: qrStudioLookDefaultsKey(accountPeerId: accountPeerId, peerId: peerId))
    }
}

private func qrStudioGift(_ gift: StarGift.UniqueGift, reference: StarGiftReference?) -> QrStudioGift? {
    var model: TelegramMediaFile?
    var pattern: TelegramMediaFile?
    var colors: (QrStudioColor, QrStudioColor, QrStudioColor, QrStudioColor)?
    for attribute in gift.attributes {
        switch attribute {
        case let .model(_, file, _, _):
            model = file
        case let .pattern(_, file, _):
            pattern = file
        case let .backdrop(_, _, innerColor, outerColor, patternColor, textColor, _):
            func color(_ value: Int32) -> QrStudioColor {
                return QrStudioColor(rgb: UInt32(bitPattern: value) & 0xffffff)
            }
            colors = (color(innerColor), color(outerColor), color(patternColor), color(textColor))
        default:
            break
        }
    }
    guard let model, let pattern, let colors else {
        return nil
    }
    return QrStudioGift(id: gift.id, gift: gift, reference: reference, model: model, pattern: pattern, inner: colors.0, outer: colors.1, patternColor: colors.2, text: colors.3)
}

private func qrStudioProfilePalettes(_ colors: PeerNameColors) -> [QrStudioPalette] {
    let ids = colors.profileDisplayOrder.isEmpty ? colors.profileColors.keys.sorted() : colors.profileDisplayOrder
    return ids.compactMap { id -> QrStudioPalette? in
        guard let value = colors.profileColors[id] else {
            return nil
        }
        return QrStudioPalette.profile(id: id, center: value.main.rgb, edge: (value.secondary ?? value.main).rgb)
    }
}

func qrStudioNormalizedEmoji(_ emoji: String, removingSkinTone: Bool = false) -> String {
    return String(String.UnicodeScalarView(emoji.unicodeScalars.filter { scalar in
        if scalar.value == 0xFE0F || scalar.value == 0xFE0E {
            return false
        }
        if removingSkinTone, (0x1F3FB ... 0x1F3FF).contains(scalar.value) {
            return false
        }
        return true
    }))
}

private let qrStudioDefaultThemeColors: [UInt32] = [0xdbddbb, 0x6ba587, 0xd5d88d, 0x88b884]

private func qrStudioThemeWallpaper(_ theme: TelegramTheme) -> TelegramWallpaper? {
    guard let settings = theme.settings, !settings.isEmpty else {
        return nil
    }
    let preferred = settings.first(where: { $0.baseTheme == .classic || $0.baseTheme == .day }) ?? settings[0]
    return preferred.wallpaper
}

private struct QrStudioPendingCodeAction {
    let action: QrStudioCodeAction
    let wasFree: Bool
    let shatterLevel: Double?
}

final class QrStudioView: View {
    private let stage = QrStudioBackgroundStage(frame: .zero)
    private let sheetView = QrStudioSheetView(frame: .zero)
    private let cardView = QrStudioCardView(frame: .zero)
    private let codePill = QrStudioCodePillView(frame: .zero)
    private let toastView = QrStudioToastView(frame: .zero)
    private let closeButton = QrStudioGlassButtonView(frame: .zero)
    private let shareButton = QrStudioGlassButtonView(frame: .zero)
    private let closeIcon = NSImage(named: "qr_studio_close")?.precomposed()
    private let shareIcon = NSImage(named: "qr_studio_share")?.precomposed()

    private var colorsTab: QrStudioColorsTabView?
    private var emojiTab: QrStudioEmojiTabView?
    private var giftsTab: QrStudioGiftsTabView?

    private var context: (any AccountContextProtocol)?
    private var peer: EnginePeer?
    private var temporary = false
    var dismiss: (() -> Void)?
    var revealed: (() -> Void)?

    var paperColor: NSColor? {
        return self.isRevealed ? self.look.backdrop.baseColor.nsColor : nil
    }

    private var look = QrStudioLook()
    private var codeState = QrStudioCodeState()
    private var paidPrice: Int64?
    private var didLoadPaidPrice = false
    private var pendingCodeAction: QrStudioPendingCodeAction?
    private var codeMenuOpenedAt: Double = 0.0

    private var noPaidToken: ExportedNoPaidMessagesToken?
    private var isRequestingNoPaidToken = false
    private var isRevokingNoPaidToken = false
    private var revokedNoPaidToken: ExportedNoPaidMessagesToken?
    private var temporaryNoPaidToken: ExportedNoPaidMessagesToken?
    private var isRequestingTemporaryNoPaidToken = false
    private var temporaryNoPaidTokenGeneration = 0
    private var lastTemporaryNoPaidTokenRequest: Double = -100.0
    private var didApplyCodeSettings = false

    private var contactToken: ExportedContactToken?
    private var contactTokenGeneration = 0
    private var contactTokenStaleAttempt = 0
    private lazy var placeholderContactLink: String = {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return "https://t.me/contact/" + String((0 ..< 32).map { _ in alphabet.randomElement()! })
    }()
    private var didRequestContactToken = false

    private let pan = QrStudioPan()
    private let drift = QrStudioDrift()
    private var tilt = SIMD2<Double>(0.0, 0.0)
    private var tiltTarget = SIMD2<Double>(0.0, 0.0)
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var displayLinkIsFullRate = false
    private var isVisible = false
    private var isUpdating = false
    private var trackingArea: NSTrackingArea?

    private var isLookLoaded = false
    private var isSetupComplete = false
    private var rawSettings: QrStudioLookSettings?
    private var customEmojiFiles: [Int64: TelegramMediaFile] = [:]
    private var unicodeEmojiFiles: [String: TelegramMediaFile] = [:]
    private var didLoadUnicodeEmoji = false
    private var resolvedCustomEmojiIds: Set<Int64> = []
    private var unicodeEmojiKeys: [String: String] = [:]
    private var isLookModified = false
    private var syncedServerLook: QrStudioServerLook?
    private var pendingServerLook: QrStudioServerLook?
    private var savedSettings: QrStudioLookSettings?
    private var giftsContext: ProfileGiftsContext?
    private var areGiftsLoaded = false
    private var didReceiveServerLook = false
    private var serverGift: QrStudioGift?
    private var localGift: QrStudioGift?
    private var loadedGifts: [QrStudioGift]?
    private var pinnedGiftId: Int64?
    private var didDecideGiftPin = false
    private var selectionRevealTab: QrStudioLook.Kind?
    private var areBackdropsLoaded = false
    private var didPickEmoji = false
    private var isRevealed = false
    private var cardRestCenter = CGPoint()
    private var cardSize = CGSize()
    private var codePillSize = CGSize()
    private var lastLayoutSize = CGSize()
    private var appliedPanelIsDark: Bool?

    private var dragStart: NSPoint?
    private var dragLast: (point: NSPoint, time: Double)?
    private var dragVelocity = CGSize()
    private var isPanning = false

    private let lookDisposable = MetaDisposable()
    private let themesDisposable = MetaDisposable()
    private let shareThemeDisposable = MetaDisposable()
    private let backdropsDisposable = MetaDisposable()
    private let emojiFilesDisposable = MetaDisposable()
    private let customEmojiDisposable = MetaDisposable()
    private let giftsDisposable = MetaDisposable()
    private let privacyDisposable = MetaDisposable()
    private let noPaidTokenDisposable = MetaDisposable()
    private let temporaryNoPaidTokenDisposable = MetaDisposable()
    private let contactTokenDisposable = MetaDisposable()
    private let saveDisposable = MetaDisposable()
    private let kindDisposable = MetaDisposable()
    private let exportDisposable = MetaDisposable()

    private static let defaultEmoji: [String] = ["❤", "🔥", "🎉"]

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.masksToBounds = true

        self.addSubview(self.stage)
        self.addSubview(self.cardView)
        self.addSubview(self.closeButton)
        self.addSubview(self.shareButton)
        self.addSubview(self.sheetView)

        self.stage.makeContent = { [weak self] backdrop in
            guard let self, let context = self.context else {
                return QrStudioMeshBackgroundView(palette: QrStudioPalette.fallback)
            }
            switch backdrop {
            case let .color(palette):
                return QrStudioMeshBackgroundView(palette: palette)
            case let .emoji(items, palette):
                return QrStudioEmojiPatternView(context: context, files: items.map { $0.file }, palette: palette)
            case let .gift(gift):
                return QrStudioGiftPatternView(context: context, gift: gift)
            case let .theme(theme):
                return QrStudioThemeBackgroundView(context: context, theme: theme)
            }
        }
        self.stage.updateContent = { content, backdrop in
            if case let .emoji(items, _) = backdrop, let content = content as? QrStudioEmojiPatternView {
                content.updateFiles(items.map { $0.file }, at: QrStudioClock.now)
            }
        }

        self.codePill.tapPaid = { [weak self] in
            guard let self else {
                return
            }
            self.codePill.animatePourBump()
            self.performCodeAction(.expire)
        }
        self.codePill.openMenu = { [weak self] sourceView in
            self?.openCodeMenu(sourceView: sourceView)
        }
        self.codePill.needsNextCode = { [weak self] in
            guard let self, let context = self.context else {
                return
            }
            self.requestTemporaryNoPaidToken(context: context, revoke: false)
        }

        self.sheetView.requestOpenTab = { [weak self] kind in
            self?.openTab(kind)
        }
        self.sheetView.progressUpdated = { [weak self] in
            self?.applySheetProgress()
        }

        self.closeButton.action = { [weak self] _ in
            self?.dismiss?()
        }
        self.shareButton.action = { [weak self] sourceView in
            self?.openShareMenu(sourceView: sourceView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.lookDisposable.dispose()
        self.themesDisposable.dispose()
        self.shareThemeDisposable.dispose()
        self.backdropsDisposable.dispose()
        self.emojiFilesDisposable.dispose()
        self.customEmojiDisposable.dispose()
        self.giftsDisposable.dispose()
        self.privacyDisposable.dispose()
        self.noPaidTokenDisposable.dispose()
        self.temporaryNoPaidTokenDisposable.dispose()
        self.contactTokenDisposable.dispose()
        self.saveDisposable.dispose()
        self.kindDisposable.dispose()
        self.exportDisposable.dispose()
    }

    func setup(context: any AccountContextProtocol, peer: EnginePeer, temporary: Bool) {
        self.context = context
        self.peer = peer
        self.temporary = temporary
        self.loadLook(context: context)
        self.loadShareTheme(context: context, peer: peer)
        self.loadGifts(context: context, peer: peer)
        self.loadPaidPrice(context: context, peer: peer)
        if temporary && !self.didRequestContactToken {
            self.didRequestContactToken = true
            self.requestContactToken(context: context)
        }
        self.requestUpdate(transition: .immediate)
        self.isSetupComplete = true
        self.revealIfReady()
    }

    private var canEdit: Bool {
        guard let context = self.context, let peer = self.peer else {
            return false
        }
        if peer.id == context.peerId {
            return true
        }
        guard case let .channel(channel) = peer, let addressName = channel.addressName, !addressName.isEmpty else {
            return false
        }
        return channel.flags.contains(.isCreator) || channel.hasPermission(.changeInfo)
    }

    private func storeLookSettings(_ settings: QrStudioLookSettings) {
        guard let context = self.context, let peer = self.peer, self.canEdit else {
            return
        }
        qrStudioStoreSettings(settings, accountPeerId: context.peerId, peerId: peer.id)
    }

    private static let unpinnedGiftCount = 6
    private static let giftsFirstPageSize = 30

    private var rememberedGiftId: Int64? {
        if case let .gift(giftId) = self.pendingServerLook {
            return giftId
        }
        return self.rawSettings?.giftId ?? self.look.giftId
    }

    private func mergedGifts(_ loadedGifts: [QrStudioGift], isComplete: Bool) -> [QrStudioGift] {
        var gifts = loadedGifts
        for extra in isComplete ? [] : [self.localGift, self.serverGift] {
            if let extra, !gifts.contains(where: { $0.id == extra.id }) {
                gifts.append(extra)
            }
        }
        if let pinnedGiftId = self.pinnedGiftId, let index = gifts.firstIndex(where: { $0.id == pinnedGiftId }), index != 0 {
            gifts.insert(gifts.remove(at: index), at: 0)
        }
        return gifts
    }

    private func pinGiftIfNeeded(_ giftId: Int64?) {
        guard !self.didDecideGiftPin, self.isLookLoaded, let giftId, let loadedGifts = self.loadedGifts else {
            return
        }
        self.didDecideGiftPin = true
        if let index = loadedGifts.firstIndex(where: { $0.id == giftId }), index < QrStudioView.unpinnedGiftCount {
            return
        }
        self.pinnedGiftId = giftId
    }

    private func applyExtraGifts() {
        if self.loadedGifts != nil {
            self.applyLoadedGifts()
            return
        }
        let gifts = self.mergedGifts([], isComplete: false)
        if !gifts.isEmpty, self.look.gifts != gifts {
            self.look.gifts = gifts
        }
    }

    private func applyLoadedGifts() {
        guard let loadedGifts = self.loadedGifts else {
            return
        }
        self.pinGiftIfNeeded(self.rememberedGiftId)
        let gifts = self.mergedGifts(loadedGifts, isComplete: self.canEdit && loadedGifts.count < QrStudioView.giftsFirstPageSize)
        let wasLoaded = self.areGiftsLoaded
        self.areGiftsLoaded = true
        if self.look.gifts != gifts {
            let previousBackdrop = self.look.backdrop
            self.look.gifts(gifts)
            let backdropChanged = previousBackdrop != self.look.backdrop
            self.requestUpdate(transition: (backdropChanged && !self.isLookModified) || !self.isRevealed ? .immediate : .animated(duration: 0.45, curve: .easeInOut))
        } else if !wasLoaded {
            self.requestUpdate(transition: !self.isRevealed ? .immediate : .animated(duration: 0.45, curve: .easeInOut))
        }
        if !wasLoaded {
            self.revealIfReady()
            self.applyServerLookIfNeeded()
        }
    }

    private var isEmojiPlaceholder: Bool {
        return !self.didPickEmoji && self.look.emoji.map { qrStudioNormalizedEmoji($0.unicode ?? "") } == QrStudioView.defaultEmoji.map { qrStudioNormalizedEmoji($0) }
    }

    private func unicodeEmojiItem(_ emoji: String) -> QrStudioEmojiItem? {
        for candidate in [qrStudioNormalizedEmoji(emoji), qrStudioNormalizedEmoji(emoji, removingSkinTone: true)] {
            if let key = self.unicodeEmojiKeys[candidate], let file = self.unicodeEmojiFiles[key] {
                return QrStudioEmojiItem(file: file, unicode: key)
            }
        }
        return nil
    }

    private func ensureEmojiSelection() {
        guard self.look.emoji.isEmpty else {
            return
        }
        self.look.emoji = QrStudioView.defaultEmoji.compactMap { self.unicodeEmojiItem($0) }
    }

    private func applyRawSettings(context: any AccountContextProtocol) {
        guard let settings = self.rawSettings, !self.isLookModified else {
            return
        }
        let hasPremium = context.isPremium || !self.canEdit
        let allowedCustomFiles = self.customEmojiFiles.filter { hasPremium || !$0.value.isPremiumEmoji }
        var unicodeFiles = self.unicodeEmojiFiles
        for value in settings.emojiUnicode where !value.isEmpty && unicodeFiles[value] == nil {
            if let item = self.unicodeEmojiItem(value) {
                unicodeFiles[value] = item.file
            }
        }
        let resolved = settings.resolve(unicodeFiles: unicodeFiles, customFiles: allowedCustomFiles, giftIds: nil, hasPremium: true)
        var look = self.look
        look.colorId = settings.colorId
        look.backdropId = settings.backdropId
        look.emoji = resolved.emoji.map { setting, file -> QrStudioEmojiItem in
            if case let .unicode(unicode) = setting {
                return QrStudioEmojiItem(file: file, unicode: unicode)
            }
            return QrStudioEmojiItem(file: file, unicode: nil)
        }
        look.giftId = resolved.giftId
        look.themeId = nil
        look.kind = QrStudioLook.Kind(rawValue: resolved.kind) ?? .color
        if look.kind == .gift, !look.gifts.isEmpty, look.selectedGift == nil {
            look.giftId = nil
            look.kind = .color
        }
        self.look = look
        if self.look.kind == .emoji {
            self.ensureEmojiSelection()
        }
        if !self.didApplyCodeSettings, let codeRemoveFee = settings.codeRemoveFee, codeRemoveFee {
            self.codeState.removeFee = true
            self.codeState.expires = self.temporary || (settings.codeExpires ?? false)
            self.codeState.issuedAt = QrStudioClock.now
            self.codeState.pourFrom = 0.0
        }
        self.didApplyCodeSettings = true
        self.savedSettings = self.currentSettings()
    }

    private func loadLook(context: any AccountContextProtocol) {
        self.look.palettes = qrStudioProfilePalettes(context.peerNameColors)

        self.backdropsDisposable.set((context.engine.peers.shareThemeBackdrops()
        |> deliverOnMainQueue).start(next: { [weak self] backdrops in
            guard let self else {
                return
            }
            func rgb(_ value: Int32) -> UInt32 {
                return UInt32(bitPattern: value) & 0xffffff
            }
            let palettes = backdrops.map { QrStudioPalette.backdrop(id: $0.id, center: rgb($0.centerColor), edge: rgb($0.edgeColor), pattern: rgb($0.patternColor), text: rgb($0.textColor)) }
            let wasLoaded = self.areBackdropsLoaded
            self.areBackdropsLoaded = true
            if self.look.backdrops != palettes {
                self.look.backdrops = palettes
                self.requestUpdate(transition: !self.isRevealed ? .immediate : .animated(duration: 0.45, curve: .easeInOut))
            }
            if !wasLoaded {
                self.applyServerLookIfNeeded()
                self.revealIfReady()
            }
        }))

        let settings: QrStudioLookSettings?
        if self.canEdit, let peer = self.peer {
            settings = qrStudioLoadSettings(accountPeerId: context.peerId, peerId: peer.id)
        } else {
            settings = nil
        }
        let localCustomFiles: Signal<[Int64: TelegramMediaFile], NoError>
        if let settings, !settings.customFileIds.isEmpty {
            localCustomFiles = context.engine.stickers.resolveInlineStickersLocal(fileIds: settings.customFileIds) |> take(1)
        } else {
            localCustomFiles = .single([:])
        }
        self.lookDisposable.set((localCustomFiles |> deliverOnMainQueue).start(next: { [weak self] customFiles in
            guard let self else {
                return
            }
            self.rawSettings = settings
            self.customEmojiFiles = customFiles
            if let settings, let gift = settings.gift, gift.id == settings.giftId {
                self.localGift = qrStudioGift(gift, reference: settings.giftReference)
                self.applyExtraGifts()
            }
            self.applyRawSettings(context: context)
            self.isLookLoaded = true
            self.applyExtraGifts()
            self.requestUpdate(transition: .immediate)
            self.revealIfReady()
            self.resolveMissingCustomEmoji(context: context)
            self.applyServerLookIfNeeded()
        }))

        let animatedEmoji = context.diceCache.animatedEmojies
        |> filter { !$0.isEmpty }
        |> map { stickers in
            stickers.mapValues { $0.file._parse() }
        }
        self.emojiFilesDisposable.set((animatedEmoji |> deliverOnMainQueue).start(next: { [weak self] files in
            guard let self else {
                return
            }
            self.didLoadUnicodeEmoji = true
            let wasEmpty = self.unicodeEmojiFiles.isEmpty
            self.unicodeEmojiFiles = files
            var keys: [String: String] = [:]
            for key in files.keys {
                keys[qrStudioNormalizedEmoji(key)] = key
            }
            self.unicodeEmojiKeys = keys
            self.emojiTab?.updateAvailableEmoji(Set(keys.keys))
            if wasEmpty && self.isLookLoaded {
                self.applyRawSettings(context: context)
                if self.look.kind == .emoji {
                    self.ensureEmojiSelection()
                }
                self.requestUpdate(transition: !self.isRevealed ? .immediate : .animated(duration: 0.45, curve: .easeInOut))
            }
            self.revealIfReady()
        }))
    }

    private func loadThemes(context: any AccountContextProtocol) {
        let defaultWallpaper = TelegramWallpaper.gradient(TelegramWallpaper.Gradient(id: nil, colors: qrStudioDefaultThemeColors, settings: WallpaperSettings()))
        self.look.themes = [QrStudioTheme(id: QrStudioTheme.defaultId, wallpaper: defaultWallpaper, colors: qrStudioWallpaperColors(defaultWallpaper))]
        self.themesDisposable.set((context.engine.themes.getChatThemes(accountManager: context.sharedContext.accountManager)
        |> deliverOnMainQueue).start(next: { [weak self] cloudThemes in
            guard let self else {
                return
            }
            var themes = [self.look.themes[0]]
            for cloudTheme in cloudThemes {
                guard let emoticon = cloudTheme.emoticon, emoticon != QrStudioTheme.defaultId, let wallpaper = qrStudioThemeWallpaper(cloudTheme) else {
                    continue
                }
                themes.append(QrStudioTheme(id: emoticon, wallpaper: wallpaper, colors: qrStudioWallpaperColors(wallpaper)))
            }
            if themes != self.look.themes {
                self.look.themes = themes
                self.requestUpdate(transition: !self.isRevealed || !self.isLookModified ? .immediate : .animated(duration: 0.35, curve: .easeInOut))
                self.revealIfReady()
            }
        }))
    }

    private func loadShareTheme(context: any AccountContextProtocol, peer: EnginePeer) {
        let isReadOnly = !self.canEdit
        self.shareThemeDisposable.set((context.engine.peers.getShareTheme(peerId: peer.id)
        |> deliverOnMainQueue).start(next: { [weak self] theme in
            guard let self else {
                return
            }
            guard let theme else {
                if isReadOnly {
                    self.didReceiveServerLook = true
                    self.revealIfReady()
                }
                return
            }
            let serverLook: QrStudioServerLook
            switch theme {
            case .default:
                serverLook = .default
            case let .emojiBackdrop(reactions, backdropId):
                let emoji = (reactions ?? []).compactMap { reaction -> QrStudioLookSettings.Emoji? in
                    switch reaction {
                    case let .builtin(value):
                        return .unicode(value)
                    case let .custom(fileId):
                        return .custom(fileId)
                    case .stars:
                        return nil
                    }
                }
                if emoji.isEmpty && backdropId == nil {
                    serverLook = .default
                } else {
                    serverLook = .emojiBackdrop(emoji: emoji.isEmpty ? nil : emoji, backdropId: backdropId)
                }
            case let .gift(gift):
                if case let .unique(uniqueGift) = gift {
                    serverLook = .gift(uniqueGift.id)
                    self.serverGift = qrStudioGift(uniqueGift, reference: nil)
                    if isReadOnly {
                        self.loadedGifts = []
                    } else if !self.isLookModified {
                        self.pinGiftIfNeeded(uniqueGift.id)
                    }
                    self.applyExtraGifts()
                } else {
                    serverLook = .default
                }
            }
            self.didReceiveServerLook = true
            self.syncedServerLook = serverLook
            self.pendingServerLook = serverLook
            self.applyLoadedGifts()
            self.applyServerLookIfNeeded()
        }))
    }

    private func applyServerLookIfNeeded() {
        guard let context = self.context, let serverLook = self.pendingServerLook, self.isLookLoaded else {
            return
        }
        defer {
            self.revealIfReady()
        }
        if case let .gift(giftId) = serverLook, !self.areGiftsLoaded, !self.look.gifts.contains(where: { $0.id == giftId }) {
            return
        }
        if case .emojiBackdrop(_, .some) = serverLook, !self.areBackdropsLoaded {
            return
        }
        self.pendingServerLook = nil
        guard !self.isLookModified else {
            return
        }
        let current = self.currentSettings()
        guard current.serverLook(hasPremium: context.isPremium) != serverLook else {
            return
        }
        let settings = current.applying(serverLook)
        self.rawSettings = settings
        self.applyRawSettings(context: context)
        if self.look.kind == .emoji {
            self.ensureEmojiSelection()
        }
        self.resolveMissingCustomEmoji(context: context)
        let storedSettings = self.currentSettings()
        self.savedSettings = storedSettings
        self.storeLookSettings(storedSettings)
        self.requestUpdate(transition: !self.isRevealed ? .immediate : .animated(duration: 0.45, curve: .easeInOut))
    }

    private func resolveMissingCustomEmoji(context: any AccountContextProtocol) {
        guard let settings = self.rawSettings else {
            return
        }
        let missingFileIds = settings.customFileIds.filter { self.customEmojiFiles[$0] == nil && !self.resolvedCustomEmojiIds.contains($0) }
        guard !missingFileIds.isEmpty else {
            return
        }
        self.customEmojiDisposable.set((context.engine.stickers.resolveInlineStickers(fileIds: missingFileIds)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] files in
            guard let self else {
                return
            }
            self.resolvedCustomEmojiIds.formUnion(missingFileIds)
            for (id, file) in files {
                self.customEmojiFiles[id] = file
            }
            self.applyRawSettings(context: context)
            self.requestUpdate(transition: !self.isRevealed ? .immediate : .animated(duration: 0.45, curve: .easeInOut))
            self.revealIfReady()
        }))
    }

    func pushShareThemeIfNeeded() {
        guard let context = self.context, let peer = self.peer, self.canEdit, self.isLookLoaded, self.isRevealed else {
            return
        }
        let settings = self.currentSettings()
        let local = settings.serverLook(hasPremium: context.isPremium)
        guard local != self.syncedServerLook else {
            return
        }
        let update: TelegramShareThemeUpdate
        switch local {
        case .default:
            update = .default
        case let .emojiBackdrop(emoji, backdropId):
            update = .emojiBackdrop(emojis: emoji?.map { item -> MessageReaction.Reaction in
                switch item {
                case let .unicode(value):
                    return .builtin(value)
                case let .custom(fileId):
                    return .custom(fileId)
                }
            }, backdropId: backdropId)
        case let .gift(giftId):
            guard let gift = self.look.gifts.first(where: { $0.id == giftId }) else {
                return
            }
            update = .gift(gift.reference ?? .slug(slug: gift.gift.slug))
        }
        self.syncedServerLook = local
        self.pendingServerLook = nil
        let _ = context.engine.peers.setShareTheme(peerId: peer.id, theme: update).start()
        self.flushSave()
    }

    private func loadGifts(context: any AccountContextProtocol, peer: EnginePeer) {
        guard self.giftsContext == nil, self.canEdit else {
            return
        }
        let giftsContext = QrStudioPrefetch.shared.giftsContext(context: context, peerId: peer.id)
        self.giftsContext = giftsContext
        self.giftsDisposable.set((giftsContext.state
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else {
                return
            }
            var gifts: [QrStudioGift] = []
            for item in state.filteredGifts {
                guard case let .unique(gift) = item.gift, let studioGift = qrStudioGift(gift, reference: item.reference) else {
                    continue
                }
                gifts.append(studioGift)
            }
            guard case .ready = state.dataState else {
                return
            }
            self.loadedGifts = gifts
            self.applyLoadedGifts()
        }))
    }

    private func currentSettings() -> QrStudioLookSettings {
        var settings = self.look.settings
        settings.codeRemoveFee = self.codeState.removeFee
        settings.codeExpires = self.codeState.expires
        return settings
    }

    private func scheduleSaveLook(context: any AccountContextProtocol) {
        guard self.isLookLoaded else {
            return
        }
        let settings = self.currentSettings()
        guard settings != self.savedSettings else {
            return
        }
        self.savedSettings = settings
        self.rawSettings = settings
        self.saveDisposable.set((Signal<Void, NoError>.single(Void()) |> delay(0.5, queue: .mainQueue())).start(next: { [weak self] in
            self?.storeLookSettings(settings)
        }))
    }

    private func flushSave() {
        guard let settings = self.savedSettings else {
            return
        }
        self.saveDisposable.set(nil)
        self.storeLookSettings(settings)
    }

    private func loadPaidPrice(context: any AccountContextProtocol, peer: EnginePeer) {
        guard peer.id == context.peerId else {
            return
        }
        let _ = context.engine.privacy.updateGlobalPrivacySettings().start()
        self.privacyDisposable.set((context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.GlobalPrivacy())
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else {
                return
            }
            var price: Int64?
            if case let .paidMessages(amount) = settings.nonContactChatsPrivacy, amount.value > 0 {
                price = amount.value
            }
            let wasLoaded = self.didLoadPaidPrice
            self.didLoadPaidPrice = true
            if self.paidPrice != price {
                self.paidPrice = price
                self.requestUpdate(transition: !self.isRevealed ? .immediate : .animated(duration: 0.35, curve: .easeInOut))
            }
            if !wasLoaded {
                self.revealIfReady()
            }
        }))
    }

    private func syncNoPaidToken(context: any AccountContextProtocol) {
        guard self.codeState.removeFee, self.paidPrice != nil else {
            return
        }
        if self.codeState.expires {
            if self.temporaryNoPaidToken == nil {
                self.requestTemporaryNoPaidToken(context: context, revoke: false)
            }
            return
        }
        guard self.noPaidToken == nil, !self.isRequestingNoPaidToken, !self.isRevokingNoPaidToken else {
            return
        }
        if let token = self.revokedNoPaidToken {
            self.revokedNoPaidToken = nil
            self.noPaidToken = token
            return
        }
        self.requestNoPaidToken(context: context, revoke: false)
    }

    private func requestNoPaidToken(context: any AccountContextProtocol, revoke: Bool) {
        guard !self.temporary else {
            self.requestTemporaryNoPaidToken(context: context, revoke: revoke)
            return
        }
        self.isRequestingNoPaidToken = true
        self.noPaidTokenDisposable.set((context.engine.peers.exportNoPaidMessagesToken(revoke: revoke, temporary: false)
        |> deliverOnMainQueue).start(next: { [weak self] token in
            guard let self else {
                return
            }
            self.isRequestingNoPaidToken = false
            if let token {
                self.noPaidToken = token
            } else if self.noPaidToken == nil {
                self.codeState.perform(.restore, at: QrStudioClock.now)
                self.presentNoPaidTokenError()
            }
            self.requestUpdate(transition: !self.isRevealed ? .immediate : .animated(duration: 0.3, curve: .easeInOut))
            self.revealIfReady()
        }))
    }

    private func requestTemporaryNoPaidToken(context: any AccountContextProtocol, revoke: Bool) {
        guard !self.isRevokingNoPaidToken else { return }
        let time = QrStudioClock.now
        guard revoke || (!self.isRequestingTemporaryNoPaidToken && time - self.lastTemporaryNoPaidTokenRequest >= 2.0) else {
            return
        }
        self.isRequestingTemporaryNoPaidToken = true
        self.lastTemporaryNoPaidTokenRequest = time
        self.temporaryNoPaidTokenGeneration += 1
        let generation = self.temporaryNoPaidTokenGeneration
        let network = context.account.network
        self.temporaryNoPaidTokenDisposable.set((context.engine.peers.exportNoPaidMessagesToken(revoke: revoke, temporary: true)
        |> deliverOnMainQueue).start(next: { [weak self] token in
            guard let self, self.temporaryNoPaidTokenGeneration == generation else {
                return
            }
            self.isRequestingTemporaryNoPaidToken = false
            guard self.codeState.removeFee, self.codeState.expires else {
                return
            }
            guard let token, let expires = token.expires else {
                if self.temporaryNoPaidToken == nil {
                    self.codeState.perform(.restore, at: QrStudioClock.now)
                    self.presentNoPaidTokenError()
                    self.requestUpdate(transition: .animated(duration: 0.3, curve: .easeInOut))
                    self.revealIfReady()
                }
                return
            }
            let now = QrStudioClock.now
            let remaining = Double(expires) - Double(network.getApproximateRemoteTimestamp())
            if let current = self.temporaryNoPaidToken, current.token == token.token, current.expires == token.expires {
                return
            }
            self.temporaryNoPaidToken = token
            self.codeState.adopt(deadline: now + max(1.0, remaining), at: now)
            self.requestUpdate(transition: !self.isRevealed ? .immediate : .animated(duration: 0.3, curve: .easeInOut))
            self.revealIfReady()
        }))
    }

    private func revokeNoPaidToken(context: any AccountContextProtocol) {
        self.isRevokingNoPaidToken = true
        self.revokedNoPaidToken = nil
        let _ = (context.engine.peers.exportNoPaidMessagesToken(revoke: true, temporary: self.temporary)
        |> deliverOnMainQueue).start(next: { [weak self] token in
            guard let self else {
                return
            }
            self.isRevokingNoPaidToken = false
            self.revokedNoPaidToken = token
            if token == nil {
                self.presentNoPaidTokenError()
            }
            self.requestUpdate(transition: .animated(duration: 0.3, curve: .easeInOut))
        })
    }

    private func requestContactToken(context: any AccountContextProtocol) {
        self.contactTokenGeneration += 1
        let generation = self.contactTokenGeneration
        self.contactTokenDisposable.set((context.engine.peers.exportContactToken()
        |> deliverOnMainQueue).start(next: { [weak self] token in
            guard let self, self.contactTokenGeneration == generation else {
                return
            }
            let now = Double(context.account.network.getApproximateRemoteTimestamp())
            let delay: Double
            if let token, !qrStudioTokenIsExpired(expires: Double(token.expires), now: now) {
                self.contactTokenStaleAttempt = 0
                if self.contactToken?.url != token.url || self.contactToken?.expires != token.expires {
                    self.contactToken = token
                    self.requestUpdate(transition: .animated(duration: 0.3, curve: .easeInOut))
                }
                delay = qrStudioTokenRefreshDelay(expires: Double(token.expires), now: now, staleAttempt: 0)
            } else {
                if self.contactToken == nil, let token {
                    self.contactToken = token
                    self.requestUpdate(transition: .animated(duration: 0.3, curve: .easeInOut))
                }
                delay = qrStudioTokenRefreshDelay(expires: Double(token?.expires ?? 0), now: now, staleAttempt: self.contactTokenStaleAttempt)
                self.contactTokenStaleAttempt += 1
            }
            Queue.mainQueue().after(delay, { [weak self] in
                guard let self, self.contactTokenGeneration == generation, let context = self.context else {
                    return
                }
                self.requestContactToken(context: context)
            })
        }))
    }

    private func presentNoPaidTokenError() {
        self.showToast("info", strings().qrStudioControllerSomethingWentWrong)
    }

    private func showToast(_ icon: String, _ text: String, action: QrStudioToast.Action? = nil) {
        if self.toastView.isShowingProgress {
            return
        }
        self.addSubview(self.toastView, positioned: .above, relativeTo: self.sheetView)
        self.toastView.show(QrStudioToast(icon: icon, text: text, action: action), ink: self.look.ink, isLight: self.look.backdrop.isLight)
        self.layoutToast()
    }

    private func presentPremiumEmojiToast() {
        guard let context = self.context else {
            return
        }
        self.showToast("stars", strings().qrStudioControllerPremiumEmoji, action: QrStudioToast.Action(title: strings().qrStudioControllerSubscribe, perform: {
            QrStudioNavigationHooks.openPremium?(context)
        }))
    }

    private func openGiftShop() {
        guard let context = self.context else {
            return
        }
        QrStudioNavigationHooks.openGiftShop?(context)
    }

    private func layoutToast() {
        guard self.toastView.superview != nil else {
            return
        }
        let size = self.toastView.sizeThatFits(width: self.bounds.width - 32.0)
        var y = self.shareButton.frame.minY - 16.0 - size.height
        if self.sheetView.isOpen, let geometry = self.sheetView.geometry {
            y = min(y, geometry.sheet.minY - 16.0 - size.height)
        }
        self.toastView.frame = CGRect(x: floor((self.bounds.width - size.width) * 0.5), y: y, width: size.width, height: size.height)
    }

    private func applyCodeActionState(_ action: QrStudioCodeAction, transition: ContainedViewLayoutTransition = .immediate) -> QrStudioPendingCodeAction {
        let action = action.constrained(toTemporary: self.temporary)
        let time = QrStudioClock.now
        let shatterLevel: Double? = QrStudioBurn.shatters(self.codeState, action: action) ? QrStudioBurn.level(self.codeState, at: time) : nil
        let wasFree = self.codeState.removeFee
        self.codeState.perform(action, at: time)
        self.requestUpdate(transition: transition)
        return QrStudioPendingCodeAction(action: action, wasFree: wasFree, shatterLevel: shatterLevel)
    }

    private func finishPendingCodeAction() {
        guard let pending = self.pendingCodeAction else {
            return
        }
        self.pendingCodeAction = nil
        self.finishCodeAction(pending)
    }

    private func performCodeAction(_ action: QrStudioCodeAction) {
        self.finishCodeAction(self.applyCodeActionState(action, transition: .animated(duration: 0.45, curve: .easeInOut)))
    }

    private func finishCodeAction(_ pending: QrStudioPendingCodeAction) {
        guard let context = self.context else {
            return
        }
        let action = pending.action
        let time = QrStudioClock.now
        if self.codeState.expires {
            self.codeState.issuedAt = time
        }
        if let level = pending.shatterLevel {
            self.codePill.startShatter(at: time, level: level)
        }
        self.codePill.setTaken(false, animated: false)
        switch action {
        case .expire:
            if pending.wasFree {
                self.showToast("timer", strings().qrStudioControllerCodeExpiresInMinute)
            } else {
                self.showToast("stars", strings().qrStudioControllerCodeFree)
            }
        case .permanent:
            self.showToast("timer", strings().qrStudioControllerCodePermanent)
        case .renew:
            self.showToast("reload", strings().qrStudioControllerCodeReset)
        case .restore:
            self.showToast("stars", strings().qrStudioControllerFeeRestored)
        }
        switch action {
        case .expire:
            self.temporaryNoPaidToken = nil
            self.requestTemporaryNoPaidToken(context: context, revoke: false)
        case .permanent:
            self.temporaryNoPaidToken = nil
            self.temporaryNoPaidTokenDisposable.set(nil)
            self.isRequestingTemporaryNoPaidToken = false
            self.syncNoPaidToken(context: context)
        case .renew:
            if self.codeState.expires {
                self.requestTemporaryNoPaidToken(context: context, revoke: true)
            } else if !self.isRevokingNoPaidToken {
                self.requestNoPaidToken(context: context, revoke: true)
            }
        case .restore:
            self.temporaryNoPaidToken = nil
            self.temporaryNoPaidTokenDisposable.set(nil)
            self.isRequestingTemporaryNoPaidToken = false
            self.noPaidToken = nil
            self.isRequestingNoPaidToken = false
            self.noPaidTokenDisposable.set(nil)
            self.revokeNoPaidToken(context: context)
        }
        self.requestUpdate(transition: .animated(duration: 0.45, curve: .easeInOut))
    }

    private var panelIsDark: Bool {
        return theme.colors.isDark
    }

    private var menuPresentation: AppMenu.Presentation {
        return .current(QrStudioGlass.isDark(self.look.backdrop) ? darkPalette : dayClassicPalette)
    }

    private func openCodeMenu(sourceView: NSView) {
        guard let event = NSApp.currentEvent else {
            return
        }
        let menu = ContextMenu(presentation: self.menuPresentation, betterInside: true)
        let sections = QrStudioBurn.menu(for: self.codeState, allowsPermanent: !self.temporary)
        for (index, section) in sections.enumerated() {
            if index != 0 {
                menu.addItem(ContextSeparatorItem())
            }
            for action in section {
                let title: String
                let image: MenuAnimation
                switch action {
                case .renew:
                    title = strings().qrStudioControllerMenuResetCode
                    image = .menu_reload
                case .permanent:
                    title = strings().qrStudioControllerMenuDisableTimer
                    image = .menu_autodelete_never
                case .expire:
                    title = strings().qrStudioControllerMenuExpireAfterMinute
                    image = .menu_autodelete_1m
                case .restore:
                    title = strings().qrStudioControllerMenuRestoreFee
                    image = .menu_paid
                }
                menu.addItem(ContextMenuItem(title, handler: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.pendingCodeAction = self.applyCodeActionState(action)
                    self.finishPendingCodeAction()
                }, itemImage: image.value))
            }
        }
        menu.onClose = { [weak self] in
            guard let self else {
                return
            }
            if self.pendingCodeAction == nil {
                self.codePill.setTaken(false, animated: true)
            }
        }
        self.codePill.setTaken(true, animated: true)
        self.codeMenuOpenedAt = QrStudioClock.now
        self.pendingCodeAction = nil
        AppMenu.show(menu: menu, event: event, for: sourceView)
    }

    private func openShareMenu(sourceView: NSView) {
        guard let event = NSApp.currentEvent else {
            return
        }
        let menu = ContextMenu(presentation: self.menuPresentation, betterInside: true)
        menu.addItem(ContextMenuItem(strings().qrStudioControllerMenuShare, handler: { [weak self] in
            self?.shareImage()
        }, itemImage: MenuAnimation.menu_share.value))
        menu.addItem(ContextMenuItem(strings().qrStudioControllerMenuCopyLink, handler: { [weak self] in
            self?.copyLink()
        }, itemImage: MenuAnimation.menu_copy_link.value))
        menu.addItem(ContextMenuItem(strings().qrStudioControllerMenuSaveImage, handler: { [weak self] in
            self?.saveImage()
        }, itemImage: MenuAnimation.menu_save_as.value))
        //TODOLANG
        menu.addItem(ContextMenuItem("Copy Image", handler: { [weak self] in
            self?.copyImage()
        }, itemImage: MenuAnimation.menu_copy_media.value))
        AppMenu.show(menu: menu, event: event, for: sourceView)
    }

    private func link() -> String {
        guard let peer = self.peer else {
            return ""
        }
        if self.codeState.removeFee && self.paidPrice != nil {
            let token: ExportedNoPaidMessagesToken?
            if self.temporary {
                token = self.temporaryNoPaidToken
            } else if self.codeState.expires {
                token = self.temporaryNoPaidToken ?? self.noPaidToken
            } else {
                token = self.noPaidToken
            }
            if let token {
                if !token.url.isEmpty {
                    return token.url
                }
                if !self.temporary {
                    if let addressName = peer.addressName, !addressName.isEmpty {
                        return "https://t.me/\(addressName)?free=\(token.token)"
                    }
                    if case let .user(user) = peer, let phone = user.phone, !phone.isEmpty {
                        return "https://t.me/+\(phone)?free=\(token.token)"
                    }
                }
            }
        }
        if self.temporary {
            return self.contactToken?.url ?? ""
        }
        if let addressName = peer.addressName, !addressName.isEmpty {
            return "https://t.me/\(addressName)"
        } else if case let .user(user) = peer {
            return "https://t.me/+\(user.phone ?? "")"
        } else if case .channel = peer {
            return "https://t.me/c/\(peer.id.id._internalGetInt64Value())"
        }
        return ""
    }

    private func copyLink() {
        let link = self.link()
        guard !link.isEmpty else {
            return
        }
        copyToClipboard(link)
        self.showToast("link", strings().qrStudioControllerLinkCopied)
    }

    private func exportCardImage(scale: CGFloat) -> (image: CGImage, screenCard: CGRect)? {
        guard let image = self.cardView.exportImage(scale: scale) else {
            return nil
        }
        let size = self.cardSize
        let center = self.cardRestCenter
        return (image, CGRect(x: center.x - size.width * 0.5, y: center.y - size.height * 0.5, width: size.width, height: size.height))
    }

    private func makeExportScene(canvas: QrStudioExportCanvas, completion: @escaping (QrStudioExportScene?) -> Void) -> Disposable {
        guard let context = self.context, let (cardImage, screenCard) = self.exportCardImage(scale: canvas.scale * 1.5) else {
            completion(nil)
            return EmptyDisposable
        }
        let screenSize = self.bounds.size
        let backdrop = self.look.backdrop
        let isLight = backdrop.isLight
        let ink = self.look.ink.nsColor
        switch backdrop {
        case let .color(palette):
            completion(QrStudioExportScene(background: .mesh(palette.colors), card: cardImage, screenSize: screenSize, screenCard: screenCard, isLight: isLight))
            return EmptyDisposable
        case .theme:
            var snapshot: CGImage?
            self.stage.forEachContent { content in
                if let view = content as? QrStudioThemeBackgroundView {
                    snapshot = view.snapshotImage(scale: canvas.scale)
                }
            }
            guard let snapshot else {
                completion(nil)
                return EmptyDisposable
            }
            completion(QrStudioExportScene(background: .image(snapshot), card: cardImage, screenSize: screenSize, screenCard: screenCard, isLight: isLight))
            return EmptyDisposable
        case let .emoji(items, palette):
            let side = Int(56.0 * canvas.scale)
            let patternItems = QrStudioEmojiPatternView.canonicalExportItems(size: screenSize, fileCount: items.count)
            let signals = items.map { qrStudioDecodeExportSticker(context: context, file: $0.file, pixelSide: side, tint: $0.isTemplate ? ink : nil, firstFrameOnly: true) }
            return (combineLatest(signals)
            |> take(1)
            |> deliverOnMainQueue).start(next: { stickers in
                let loaded = stickers.map { $0 ?? QrStudioExportSticker(frames: [], period: 0.0) }
                completion(QrStudioExportScene(background: .emoji(colors: palette.colors, stickers: loaded, items: patternItems), card: cardImage, screenSize: screenSize, screenCard: screenCard, isLight: isLight))
            })
        case let .gift(gift):
            let symbol = qrStudioDecodeExportSticker(context: context, file: gift.pattern, pixelSide: Int(28.0 * canvas.scale), tint: gift.patternColor.nsColor.withAlphaComponent(0.42), firstFrameOnly: true)
            let model = qrStudioDecodeExportSticker(context: context, file: gift.model, pixelSide: Int(94.0 * canvas.scale), tint: nil, firstFrameOnly: true)
            let patternItems = QrStudioGiftPatternView.canonicalExportItems(size: screenSize)
            return (combineLatest(symbol, model)
            |> take(1)
            |> deliverOnMainQueue).start(next: { symbol, model in
                completion(QrStudioExportScene(background: .gift(inner: gift.inner, outer: gift.outer, symbol: symbol?.frames.first, model: model, items: patternItems), card: cardImage, screenSize: screenSize, screenCard: screenCard, isLight: isLight))
            })
        }
    }

    private func renderExportImage(canvas: QrStudioExportCanvas, completion: @escaping (CGImage?) -> Void) {
        self.exportDisposable.set(self.makeExportScene(canvas: canvas, completion: { scene in
            guard let scene else {
                do {
                    completion(nil)
                }
                return
            }
            let signal = Signal<CGImage?, NoError> { subscriber in
                subscriber.putNext(qrStudioExportImage(scene, canvas: canvas))
                subscriber.putCompletion()
                return EmptyDisposable
            }
            |> runOn(.concurrentDefaultQueue())
            |> deliverOnMainQueue
            let _ = signal.start(next: { image in
                do {
                    completion(image)
                }
            })
        }))
    }

    private func shareImage() {
        guard let context = self.context else {
            return
        }
        let link = self.link()
        let canvas = QrStudioExportCanvas.screen(size: self.bounds.size, scale: max(1.0, self.window?.backingScaleFactor ?? 2.0))
        self.renderExportImage(canvas: canvas, completion: { [weak self] image in
            guard let self, let window = self.window else {
                return
            }
            guard let image, let url = qrStudioWriteTemporaryImage(image, name: "qr-code-\(UInt32.random(in: 0 ... UInt32.max)).jpg") else {
                self.showToast("info", strings().qrStudioControllerSomethingWentWrong)
                return
            }
            QrStudioNavigationHooks.shareImage?(context, url.path, link, window)
        })
    }

    private func saveImage() {
        guard let window = self.window else {
            return
        }
        self.renderExportImage(canvas: .story, completion: { [weak self] image in
            guard let self else {
                return
            }
            guard let image else {
                self.showToast("info", strings().qrStudioControllerSomethingWentWrong)
                return
            }
            qrStudioSaveImage(image, window: window, suggestedName: "qr-code", completion: { [weak self] success in
                if !success {
                    self?.showToast("info", strings().qrStudioControllerSomethingWentWrong)
                }
            })
        })
    }

    private func copyImage() {
        self.renderExportImage(canvas: .story, completion: { [weak self] image in
            guard let self else {
                return
            }
            guard let image else {
                self.showToast("info", strings().qrStudioControllerSomethingWentWrong)
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([NSImage(cgImage: image, size: NSMakeSize(CGFloat(image.width), CGFloat(image.height)))])
            //TODOLANG
            self.showToast("image", "Image copied to clipboard.")
        })
    }

    private var isLookReady: Bool {
        guard self.isSetupComplete, self.isLookLoaded else {
            return false
        }
        if !self.canEdit, !self.didReceiveServerLook || self.pendingServerLook != nil {
            return false
        }
        if !self.canEdit, self.look.kind == .emoji {
            if !self.didLoadUnicodeEmoji {
                return false
            }
            if let settings = self.rawSettings, settings.customFileIds.contains(where: { self.customEmojiFiles[$0] == nil && !self.resolvedCustomEmojiIds.contains($0) }) {
                return false
            }
        }
        if self.look.themeId != nil && self.look.selectedTheme == nil && self.look.kind == .color {
            return false
        }
        if self.look.kind == .gift, self.look.selectedGift == nil, !self.areGiftsLoaded {
            return false
        }
        if self.rawSettings?.kind == QrStudioLook.Kind.gift.rawValue, !self.areGiftsLoaded, self.look.selectedGift == nil, self.canEdit {
            return false
        }
        if self.look.kind != .gift, self.look.backdropId != nil, !self.areBackdropsLoaded {
            return false
        }
        if let context = self.context, let peer = self.peer, peer.id == context.peerId, self.codeState.removeFee {
            if !self.didLoadPaidPrice {
                return false
            }
            if self.paidPrice != nil {
                let hasToken: Bool
                if self.temporary {
                    hasToken = self.temporaryNoPaidToken != nil
                } else if self.codeState.expires {
                    hasToken = self.temporaryNoPaidToken != nil || self.noPaidToken != nil
                } else {
                    hasToken = self.noPaidToken != nil
                }
                if !hasToken {
                    return false
                }
            }
        }
        return true
    }

    private func revealIfReady() {
        guard !self.isRevealed, self.isLookReady else {
            return
        }
        self.reveal()
    }

    private func reveal() {
        guard !self.isRevealed else {
            return
        }
        self.isRevealed = true
        self.requestUpdate(transition: .immediate)
        self.revealed?()
    }

    func updateVisibility(_ isVisible: Bool) {
        guard self.isVisible != isVisible else {
            return
        }
        self.isVisible = isVisible
        self.stage.setVisible(isVisible)
        if isVisible {
            if self.temporary, let token = self.contactToken, let context = self.context, qrStudioTokenIsExpired(expires: Double(token.expires), now: Double(context.account.network.getApproximateRemoteTimestamp())) {
                self.requestContactToken(context: context)
            }
        } else {
            self.pushShareThemeIfNeeded()
        }
        self.updateDisplayLink()
    }

    private func requestUpdate(transition: ContainedViewLayoutTransition) {
        guard !self.isUpdating else {
            return
        }
        self.update(transition: transition)
    }

    private func updateDisplayLink() {
        guard self.isVisible else {
            self.displayLink = nil
            return
        }
        let isFullRate = self.pan.isActive(at: QrStudioClock.now) || self.stage.isRevealing || self.stage.wantsFullFrameRate
        if self.displayLink != nil && self.displayLinkIsFullRate == isFullRate {
            return
        }
        self.displayLinkIsFullRate = isFullRate
        self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: isFullRate ? .fps(60) : .fps(30), { [weak self] _ in
            self?.tick()
        })
    }

    private func tick() {
        let time = QrStudioClock.now
        self.tilt += (self.tiltTarget - self.tilt) * 0.08
        self.stage.tick(time: time, pan: self.pan, drift: self.drift, tilt: self.tilt)
        self.updateDisplayLink()
    }

    private func openTab(_ kind: QrStudioLook.Kind) {
        let wasOpen = self.sheetView.isOpen
        self.sheetView.open(tab: kind)
        self.selectionRevealTab = kind
        self.requestUpdate(transition: .immediate)
        self.kindDisposable.set(nil)
        guard self.look.kind != kind else {
            return
        }
        self.kindDisposable.set((Signal<Void, NoError>.single(Void()) |> delay(wasOpen ? 0.16 : 0.45, queue: .mainQueue())).start(next: { [weak self] in
            guard let self, self.sheetView.isOpen, self.sheetView.currentTab == kind else {
                return
            }
            self.isLookModified = true
            self.look.select(kind)
            if kind == .emoji {
                self.ensureEmojiSelection()
            }
            self.requestUpdate(transition: .animated(duration: 0.45, curve: .easeInOut))
        }))
    }

    private func updateTabs(context: any AccountContextProtocol, transition: ContainedViewLayoutTransition) {
        let sheetSize = self.sheetView.sheetSize
        guard sheetSize.width > 0.0, sheetSize.height > 0.0 else {
            return
        }
        let isDark = self.panelIsDark
        let fadesTheme = transition.isAnimated && self.appliedPanelIsDark != nil && self.appliedPanelIsDark != isDark
        self.appliedPanelIsDark = isDark
        if fadesTheme {
            QrStudioSheetView.addAppearanceFade(self.colorsTab?.layer)
            QrStudioSheetView.addAppearanceFade(self.giftsTab?.layer)
        }

        let colorsTab: QrStudioColorsTabView
        if let current = self.colorsTab {
            colorsTab = current
        } else {
            colorsTab = QrStudioColorsTabView(frame: .zero)
            colorsTab.selected = { [weak self] id in
                guard let self else {
                    return
                }
                self.isLookModified = true
                self.look.selectPalette(id: id)
                self.requestUpdate(transition: .animated(duration: 0.35, curve: .easeInOut))
            }
            colorsTab.selectedTheme = { [weak self] id in
                guard let self else {
                    return
                }
                self.isLookModified = true
                self.look.selectTheme(id: id)
                self.requestUpdate(transition: .animated(duration: 0.35, curve: .easeInOut))
            }
            self.colorsTab = colorsTab
            self.sheetView.setContent(colorsTab, for: .color)
        }
        let revealTab = self.selectionRevealTab
        self.selectionRevealTab = nil
        let shownTab: QrStudioLook.Kind? = self.sheetView.isOpen || revealTab != nil ? self.sheetView.currentTab : nil
        let colorsSelection: QrStudioColorsSelection?
        if self.look.kind == .color {
            if let theme = self.look.selectedTheme {
                colorsSelection = .theme(theme.id)
            } else {
                colorsSelection = self.look.palette.id.map { .palette($0) }
            }
        } else if shownTab == .color, let backdropId = self.look.backdropId, self.look.backdrops.contains(where: { $0.id == .backdrop(backdropId) }) {
            colorsSelection = .palette(.backdrop(backdropId))
        } else if shownTab == .color, self.look.themeId == nil, let paletteId = self.look.palette.id {
            colorsSelection = .palette(paletteId)
        } else {
            colorsSelection = nil
        }
        colorsTab.update(size: sheetSize, themes: self.look.themes, palettes: self.look.backdrops, selection: colorsSelection, revealSelection: revealTab == .color, isDark: isDark)

        let emojiTab: QrStudioEmojiTabView
        if let current = self.emojiTab {
            emojiTab = current
        } else {
            emojiTab = QrStudioEmojiTabView(context: context)
            if !self.unicodeEmojiKeys.isEmpty {
                emojiTab.updateAvailableEmoji(Set(self.unicodeEmojiKeys.keys))
            }
            emojiTab.resolveUnicode = { [weak self] emoji in
                return self?.unicodeEmojiItem(emoji)
            }
            emojiTab.premiumRequired = { [weak self] in
                self?.presentPremiumEmojiToast()
            }
            emojiTab.toggle = { [weak self] item in
                guard let self else {
                    return false
                }
                if self.isEmojiPlaceholder {
                    self.look.emoji = [item]
                    self.look.kind = .emoji
                } else {
                    guard self.look.toggleEmoji(item) else {
                        return false
                    }
                }
                self.didPickEmoji = true
                self.isLookModified = true
                self.requestUpdate(transition: .animated(duration: 0.35, curve: .easeInOut))
                return true
            }
            self.emojiTab = emojiTab
            self.sheetView.setContent(emojiTab, for: .emoji)
        }
        emojiTab.update(size: sheetSize, selected: self.isEmojiPlaceholder ? [] : self.look.emoji, isDark: isDark)

        let giftsTab: QrStudioGiftsTabView
        if let current = self.giftsTab {
            giftsTab = current
        } else {
            giftsTab = QrStudioGiftsTabView(frame: .zero)
            giftsTab.selected = { [weak self] id in
                guard let self else {
                    return
                }
                self.isLookModified = true
                self.look.selectGift(id: id)
                self.requestUpdate(transition: .animated(duration: 0.35, curve: .easeInOut))
            }
            giftsTab.loadMore = { [weak self] in
                self?.giftsContext?.loadMore()
            }
            giftsTab.browse = { [weak self] in
                self?.openGiftShop()
            }
            self.giftsTab = giftsTab
            self.sheetView.setContent(giftsTab, for: .gift)
        }
        giftsTab.update(size: sheetSize, context: context, gifts: self.look.gifts, isLoaded: self.areGiftsLoaded, selectedId: self.look.kind == .gift || shownTab == .gift ? self.look.giftId : nil, revealSelection: revealTab == .gift, scrollsToSelection: self.pinnedGiftId == nil || self.look.giftId != self.pinnedGiftId, isDark: isDark)
    }

    private struct SheetFollow {
        var cardCenter: CGPoint
        var cardScale: CGFloat
        var pillCenter: CGPoint
        var buttonsAlpha: CGFloat
    }

    private func sheetFollow() -> SheetFollow? {
        guard let geometry = self.sheetView.geometry, self.cardSize.height > 0.0 else {
            return nil
        }
        let openness = self.sheetView.openness
        let groupY = self.cardRestCenter.y - self.cardSize.height * 0.5 + (self.cardSize.height + QrStudioCardMetrics.pillReserve) * 0.5
        let rest = QrStudioSheetGeometry.raise(card: self.cardSize.height, groupY: groupY, panelTop: geometry.sheet.minY, gap: 35.0)
        let scale = 1.0 + (rest.fit - 1.0) * openness
        let cardCenter = CGPoint(x: self.cardRestCenter.x, y: self.cardRestCenter.y + rest.lift * openness + self.cardSize.height * (1.0 - scale) * 0.5)
        let pillCenter = CGPoint(x: cardCenter.x, y: cardCenter.y + self.cardSize.height * scale * 0.5 + 16.0 + QrStudioCodePillView.height * 0.5)
        let t = min(1.0, max(0.0, openness / 0.55))
        return SheetFollow(cardCenter: cardCenter, cardScale: scale, pillCenter: pillCenter, buttonsAlpha: 1.0 - t * t * (3.0 - 2.0 * t))
    }

    private func applySheetProgress() {
        guard let follow = self.sheetFollow() else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cardSize = self.cardSize
        self.cardView.frame = CGRect(x: follow.cardCenter.x - cardSize.width * 0.5, y: follow.cardCenter.y - cardSize.height * 0.5, width: cardSize.width, height: cardSize.height)
        if let layer = self.cardView.layer {
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, cardSize.width * 0.5, cardSize.height * 0.5, 0.0)
            transform = CATransform3DScale(transform, follow.cardScale, follow.cardScale, 1.0)
            transform = CATransform3DTranslate(transform, -cardSize.width * 0.5, -cardSize.height * 0.5, 0.0)
            layer.transform = transform
        }
        if self.codePillSize.width > 0.0 {
            self.codePill.frame = CGRect(x: follow.pillCenter.x - self.codePillSize.width * 0.5, y: follow.pillCenter.y - self.codePillSize.height * 0.5, width: self.codePillSize.width, height: self.codePillSize.height)
            self.codePill.isActive = self.paidPrice != nil
        }
        self.shareButton.alphaValue = follow.buttonsAlpha
        self.shareButton.isHidden = follow.buttonsAlpha <= 0.01
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        if self.lastLayoutSize != self.bounds.size {
            self.lastLayoutSize = self.bounds.size
            self.requestUpdate(transition: .immediate)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        if let result, result === self.stage || result.isDescendant(of: self.stage) || result === self.cardView || result.isDescendant(of: self.cardView) {
            return self
        }
        return result
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = self.trackingArea {
            self.removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(rect: self.bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = self.convert(event.locationInWindow, from: nil)
        let halfWidth = max(1.0, self.bounds.width * 0.5)
        let halfHeight = max(1.0, self.bounds.height * 0.5)
        let x = Double(max(-1.0, min(1.0, (point.x - self.bounds.midX) / halfWidth)))
        let y = Double(max(-1.0, min(1.0, (point.y - self.bounds.midY) / halfHeight)))
        self.tiltTarget = SIMD2<Double>(y * 0.35, x * 0.35)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        self.tiltTarget = SIMD2<Double>(0.0, 0.0)
    }

    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        self.dragStart = point
        self.dragLast = (point, QrStudioClock.now)
        self.dragVelocity = CGSize()
        self.isPanning = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = self.dragStart else {
            return
        }
        let point = self.convert(event.locationInWindow, from: nil)
        let time = QrStudioClock.now
        let translation = CGSize(width: point.x - start.x, height: point.y - start.y)
        if !self.isPanning {
            guard abs(translation.width) > 3.0 || abs(translation.height) > 3.0 else {
                return
            }
            self.isPanning = true
            self.pan.begin(at: time)
        }
        if let last = self.dragLast, time > last.time {
            let dt = CGFloat(time - last.time)
            self.dragVelocity = CGSize(width: (point.x - last.point.x) / dt, height: (point.y - last.point.y) / dt)
        }
        self.dragLast = (point, time)
        self.pan.update(translation: translation)
        self.updateDisplayLink()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            self.dragStart = nil
            self.dragLast = nil
            self.isPanning = false
        }
        guard let start = self.dragStart else {
            return
        }
        let point = self.convert(event.locationInWindow, from: nil)
        if self.isPanning {
            self.pan.end(translation: CGSize(width: point.x - start.x, height: point.y - start.y), velocity: self.dragVelocity, at: QrStudioClock.now)
            self.updateDisplayLink()
        } else if self.sheetView.isOpen {
            self.sheetView.close()
        }
    }

    func handleEscape() -> Bool {
        if self.sheetView.isOpen {
            self.sheetView.close()
            return true
        }
        return false
    }

    func update(transition: ContainedViewLayoutTransition) {
        guard let context = self.context, let peer = self.peer else {
            return
        }
        self.isUpdating = true
        defer {
            self.isUpdating = false
        }
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }

        self.syncNoPaidToken(context: context)

        let backdrop = self.look.backdrop
        let controlAppearance = QrStudioGlass.appearance(for: backdrop)
        let ink = self.look.ink
        var link = self.link()
        if link.isEmpty && self.temporary {
            link = self.placeholderContactLink
        }

        self.layer?.backgroundColor = backdrop.baseColor.cgColor

        var username: String?
        if let addressName = peer.addressName, !addressName.isEmpty {
            username = addressName
        }

        let cardCenter = CGPoint(x: size.width * 0.5, y: QrStudioCardMetrics.cardCenterY(screenHeight: size.height, showsUsername: username != nil))
        self.cardRestCenter = cardCenter

        let rowInset: CGFloat = 24.0
        let bottomInset = rowInset
        self.sheetView.frame = CGRect(origin: CGPoint(), size: size)
        self.sheetView.isHidden = !self.canEdit
        self.sheetView.update(size: size, safeBottom: bottomInset, bottomCornerRadius: 20.0, kinds: self.look.availableKinds, appearance: controlAppearance, panelIsDark: self.panelIsDark, transition: transition)

        self.stage.frame = CGRect(origin: CGPoint(), size: size)
        var controlReveal: QrStudioAppearanceReveal?
        if self.isLookLoaded {
            controlReveal = self.stage.update(backdrop: backdrop, size: size, revealCenter: cardCenter, animated: transition.isAnimated && self.isRevealed)
            self.scheduleSaveLook(context: context)
            let inkColor = ink.nsColor
            self.stage.forEachContent { content in
                (content as? QrStudioEmojiPatternView)?.templateTintColor = inkColor
            }
        }

        var fillColors: [QrStudioColor]?
        if case let .theme(theme) = backdrop, !theme.colors.isEmpty {
            fillColors = theme.colors
        }
        let cardSize = self.cardView.update(link: link, username: username, ink: ink, isLight: backdrop.isLight, bounceToken: backdrop.cardSignature + link, fillColors: fillColors, transition: self.isRevealed ? transition : .immediate)
        self.cardSize = cardSize

        let buttonSide: CGFloat = 40.0
        let closeTop: CGFloat = 16.0
        transition.updateFrame(view: self.closeButton, frame: CGRect(x: 16.0, y: closeTop, width: buttonSide, height: buttonSide))
        self.closeButton.update(size: CGSize(width: buttonSide, height: buttonSide), appearance: controlAppearance, icon: self.closeIcon, reveal: controlReveal, transition: transition)

        let bottomRowY = size.height - bottomInset - buttonSide - 2.0
        transition.updateFrame(view: self.shareButton, frame: CGRect(x: rowInset, y: bottomRowY, width: buttonSide, height: buttonSide))
        self.shareButton.update(size: CGSize(width: buttonSide, height: buttonSide), appearance: controlAppearance, icon: self.shareIcon, reveal: controlReveal, transition: transition)

        if self.isLookLoaded {
            self.updateTabs(context: context, transition: self.isRevealed ? transition : .immediate)
        }

        if let price = self.paidPrice {
            let isAppearing = self.codePill.superview == nil
            let codePillSize = self.codePill.update(
                state: self.codeState,
                price: price,
                ink: ink,
                isLight: backdrop.isLight,
                texts: QrStudioCodePillView.Texts(
                    free: strings().qrStudioControllerPillFree,
                    removeFee: strings().qrStudioControllerPillRemoveFee("%@"),
                    permanent: strings().qrStudioControllerPillPermanent,
                    expiresIn: { value in
                        return strings().qrStudioControllerPillExpiresIn(value)
                    }
                ),
                transition: isAppearing ? .immediate : transition
            )
            if isAppearing {
                self.addSubview(self.codePill, positioned: .below, relativeTo: self.sheetView)
                self.codePill.layer?.opacity = transition.isAnimated ? 0.0 : 1.0
            }
            transition.updateAlpha(view: self.codePill, alpha: 1.0)
            self.codePillSize = codePillSize
        } else if self.codePill.superview != nil {
            transition.updateAlpha(view: self.codePill, alpha: 0.0)
        }
        self.applySheetProgress()
        self.layoutToast()
        self.updateDisplayLink()
    }
}

public final class QrStudioController: ModalViewController {
    private let context: any AccountContextProtocol
    private let peer: EnginePeer
    private let temporary: Bool

    public init(context: any AccountContextProtocol, peer: EnginePeer, temporary: Bool) {
        self.context = context
        self.peer = peer
        self.temporary = temporary
        super.init(frame: NSMakeRect(0, 0, 400, 740))
        self.bar = .init(height: 0)
    }

    private var genericView: QrStudioView {
        return self.view as! QrStudioView
    }

    public override func viewClass() -> AnyClass {
        return QrStudioView.self
    }

    public override var containerBackground: NSColor {
        guard self.isLoaded() else {
            return .clear
        }
        return self.genericView.paperColor ?? .clear
    }

    public override var hasBorder: Bool {
        return false
    }

    public override var cornerRadius: CGFloat {
        return 20.0
    }

    public override var dynamicSize: Bool {
        return true
    }

    public override func measure(size: NSSize) {
        if let contentSize = self.modal?.window.contentView?.frame.size {
            self.modal?.resize(with: NSMakeSize(400, min(760, max(560, contentSize.height - 80))), animated: false)
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.genericView.dismiss = { [weak self] in
            self?.close()
        }
        self.genericView.revealed = { [weak self] in
            self?.readyOnce()
        }
        self.genericView.setup(context: self.context, peer: self.peer, temporary: self.temporary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.readyOnce()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.genericView.updateVisibility(true)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.genericView.pushShareThemeIfNeeded()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.genericView.updateVisibility(false)
    }

    public override func escapeKeyAction() -> KeyHandlerResult {
        if self.genericView.handleEscape() {
            return .invoked
        }
        return super.escapeKeyAction()
    }
}

public func showQrStudio(context: any AccountContextProtocol, peerId: PeerId, morphSource: (() -> NSView?)? = nil) {
    let window = context.window
    guard findModal(QrStudioController.self)?.modal?.window !== window else {
        return
    }
    let _ = (QrStudioPrefetch.shared.makeController(context: context, peerId: peerId)
    |> deliverOnMainQueue).start(next: { controller in
        guard let controller, findModal(QrStudioController.self)?.modal?.window !== window else {
            return
        }
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
        }
        showModal(with: controller, for: window, morphSource: morphSource)
    })
}
