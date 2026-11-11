import Cocoa
import TelegramCore
import ThemeSettings
import Postbox
import TGUIKit
import SwiftSignalKit
import InAppSettings
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import FilePanels
import AppAnalytics

public final class ThemeGridControllerInteraction {
    public let openWallpaper: (Wallpaper, TelegramWallpaper?) -> Void
    public let deleteWallpaper: (Wallpaper, TelegramWallpaper) -> Void
    public init(openWallpaper: @escaping (Wallpaper, TelegramWallpaper?) -> Void, deleteWallpaper: @escaping (Wallpaper, TelegramWallpaper) -> Void) {
        self.openWallpaper = openWallpaper
        self.deleteWallpaper = deleteWallpaper
    }
}

private let _id_wallpaper_row = InputDataIdentifier("_id_wallpaper_row")
private func _id_wallpaper_row_at(_ i: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_wallpaper_row_\(i)")
}

private struct WallpaperEntry: Equatable {
    public let index: Int
    public let wallpaper: Wallpaper
    public let telegramWallpaper: TelegramWallpaper?
    public let selected: Bool

    public static func == (lhs: WallpaperEntry, rhs: WallpaperEntry) -> Bool {
        return lhs.index == rhs.index
            && lhs.selected == rhs.selected
            && lhs.wallpaper == rhs.wallpaper
            && lhs.telegramWallpaper == rhs.telegramWallpaper
    }
}

private final class ChatWallpaperRowItem: GeneralRowItem {

    fileprivate let entries: [WallpaperEntry]
    fileprivate let context: any AccountContextProtocol
    fileprivate let perRowCount: Int
    fileprivate let interaction: ThemeGridControllerInteraction
    fileprivate let itemHeight: CGFloat

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, entries: [WallpaperEntry], perRowCount: Int = 3, interaction: ThemeGridControllerInteraction, insets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10), itemHeight: CGFloat = 163) {
        self.entries = entries
        self.context = context
        self.perRowCount = perRowCount
        self.interaction = interaction
        self.itemHeight = itemHeight
        super.init(initialSize, stableId: stableId, viewType: .legacy, inset: insets)
    }

    public override var hasBorder: Bool {
        return false
    }

    public override var height: CGFloat {
        return itemHeight
    }

    public override func viewClass() -> AnyClass {
        return ChatWallpaperRowView.self
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonWallpaper
    }

    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        let insets = self.inset
        let count = CGFloat(self.perRowCount)
        let space = self.width - insets.left - insets.right - (10 * (count - 1))
        let itemSize = NSMakeSize(floor(space / count), self.height)
        var x: CGFloat = insets.left
        for entry in entries {
            if location.x >= x && location.x < x + itemSize.width + 10 {
                if let telegramWallpaper = entry.telegramWallpaper, !entry.selected {
                    switch entry.wallpaper {
                    case .builtin, .none:
                        return .single([])
                    default:
                        let interaction = self.interaction
                        let wallpaper = entry.wallpaper
                        let item = ContextMenuItem(strings().messageContextDelete, handler: {
                            interaction.deleteWallpaper(wallpaper, telegramWallpaper)
                        }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)
                        return .single([item])
                    }
                }
                return .single([])
            }
            x += itemSize.width + 10
        }
        return .single([])
    }
}

private final class ChatWallpaperRowView: GeneralContainableRowView {

    private final class Cell: Control {
        fileprivate let wallpaperView = SettingsThemeWallpaperView()
        private let checkmark = ImageView()

        fileprivate var entry: WallpaperEntry?
        private var context: (any AccountContextProtocol)?

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(wallpaperView)
            addSubview(checkmark)
            checkmark.image = theme.icons.chatGroupToggleSelected
            checkmark.sizeToFit()
            checkmark.isAccessibilityDecorative = true
            setAccessibilityLabel(strings().voiceOverCommonWallpaper)
            scaleOnClick = true
            wallpaperView.layer?.cornerRadius = 10
            wallpaperView.layer?.masksToBounds = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func set(entry: WallpaperEntry, context: any AccountContextProtocol) {
            self.entry = entry
            self.context = context
            wallpaperView.setWallpaper(account: context.account, wallpaper: entry.wallpaper, size: frame.size)
            checkmark.isHidden = !entry.selected
            setAccessibilityValue(entry.selected ? strings().voiceOverCommonSelected : nil)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            wallpaperView.frame = bounds
            if let context, let entry {
                wallpaperView.setWallpaper(account: context.account, wallpaper: entry.wallpaper, size: bounds.size)
            }
            checkmark.setFrameOrigin(frame.width - checkmark.frame.width - 10, 10)
        }
    }

    private let content = View()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(content)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? ChatWallpaperRowItem else { return }

        while content.subviews.count > item.entries.count {
            content.subviews.last?.removeFromSuperview()
        }
        while content.subviews.count < item.entries.count {
            let cell = Cell(frame: .zero)
            cell.set(handler: { [weak self, weak cell] _ in
                guard let rowItem = self?.item as? ChatWallpaperRowItem, let entry = cell?.entry else { return }
                rowItem.interaction.openWallpaper(entry.wallpaper, entry.telegramWallpaper)
            }, for: .Click)
            content.addSubview(cell)
        }

        layout()

        for (i, subview) in content.subviews.enumerated() {
            (subview as? Cell)?.set(entry: item.entries[i], context: item.context)
        }
    }

    public override func layout() {
        super.layout()

        guard let item = item as? ChatWallpaperRowItem else { return }

        content.frame = containerView.bounds

        let insets = item.inset
        let count = CGFloat(item.perRowCount)
        let space = content.frame.width - insets.left - insets.right - (10 * (count - 1))
        let itemSize = NSMakeSize(floor(space / count), content.frame.height)

        var x: CGFloat = insets.left
        for subview in content.subviews {
            subview.setFrameSize(itemSize)
            subview.setFrameOrigin(x, 0)
            x += subview.frame.width + 10
        }
    }
}

private struct State: Equatable {
    public var entries: [WallpaperEntry] = []
}

private func entries(_ state: State, context: any AccountContextProtocol, interaction: ThemeGridControllerInteraction) -> [InputDataEntry] {
    var result: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    result.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    let chunks = state.entries.chunks(3)

    for (i, chunk) in chunks.enumerated() {
        result.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_wallpaper_row_at(i), equatable: .init(chunk), comparable: nil, item: { initialSize, stableId in
            return ChatWallpaperRowItem(initialSize, stableId: stableId, context: context, entries: chunk, perRowCount: 3, interaction: interaction)
        }))
        index += 1
        result.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1
    }

    return result
}

public func ChatWallpaperModalController(_ context: any AccountContextProtocol, selected: Wallpaper = theme.wallpaper.wallpaper, source: WallpaperSource = .none, onComplete: ((TelegramWallpaper?) -> Void)? = nil) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    var close: (() -> Void)? = nil

    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let deleted: ValuePromise<[Wallpaper]> = ValuePromise([], ignoreRepeated: false)
    let deletedValue: Atomic<[Wallpaper]> = Atomic(value: [])
    let updateDeleted: (([Wallpaper]) -> [Wallpaper]) -> Void = { f in
        deleted.set(deletedValue.modify(f))
    }

    let interaction = ThemeGridControllerInteraction(openWallpaper: { wallpaper, telegramWallpaper in
        switch wallpaper {
        case .image, .file, .color, .gradient:
            var src = source
            if let wallpaper = telegramWallpaper {
                src = src.withWallpaper(wallpaper)
            }
            showModal(with: WallpaperPreviewController(context, wallpaper: wallpaper, source: src, onComplete: onComplete), for: context.window)
        default:
            close?()
            switch source {
            case let .chat(peer, _):
                _ = context.engine.themes.setChatWallpaper(peerId: peer.id, wallpaper: nil, forBoth: false).start()
            default:
                delay(0.2, closure: {
                    _ = updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                        return settings.updateWallpaper { $0.withUpdatedWallpaper(wallpaper) }.saveDefaultWallpaper()
                    }).start()
                })
            }
        }
    }, deleteWallpaper: { wallpaper, telegramWallpaper in
        if wallpaper.isSemanticallyEqual(to: selected) {
            _ = updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                return settings.updateWallpaper({ $0.withUpdatedWallpaper(settings.palette.wallpaper.wallpaper) }).saveDefaultWallpaper()
            }).start()
        }
        _ = deleteWallpaper(account: context.account, wallpaper: telegramWallpaper).start()
        updateDeleted { current in current + [wallpaper] }
    })

    let wallpapersSignal = combineLatest(queue: prepareQueue, context.engine.themes.wallpapers(), deleted.get(), appearanceSignal)
        |> map { wallpapers, deletedWallpapers, _ -> [WallpaperEntry] in
            var entries: [WallpaperEntry] = []
            var index = 0

            entries.append(WallpaperEntry(index: index, wallpaper: .none, telegramWallpaper: nil, selected: selected.isSemanticallyEqual(to: .none)))
            index += 1

            let matchedTelegramWallpaper: TelegramWallpaper? = wallpapers.first(where: { wallpaper -> Bool in
                let wallpaper: Wallpaper = Wallpaper(wallpaper)
                return wallpaper.isSemanticallyEqual(to: selected)
            })

            switch selected {
            case .gradient:
                entries.append(WallpaperEntry(index: index, wallpaper: selected, telegramWallpaper: nil, selected: true))
            default:
                let wallpaper: Wallpaper
                if theme.colors.accent != theme.colors.basicAccent {
                    wallpaper = .color(theme.colors.basicAccent.argb)
                } else {
                    wallpaper = .color(theme.colors.basicAccent.lighter(amount: 0.25).argb)
                }
                entries.append(WallpaperEntry(index: index, wallpaper: wallpaper, telegramWallpaper: nil, selected: selected.isSemanticallyEqual(to: wallpaper)))
            }
            index += 1

            switch selected {
            case .none, .color, .gradient:
                break
            default:
                entries.append(WallpaperEntry(index: index, wallpaper: selected, telegramWallpaper: matchedTelegramWallpaper, selected: true))
                index += 1
            }

            for item in wallpapers {
                let wallpaper = Wallpaper(item)
                if !deletedWallpapers.contains(where: { $0.isSemanticallyEqual(to: wallpaper) }) {
                    switch item {
                    case let .file(file):
                        if file.isPattern, file.settings.colors.isEmpty {
                            continue
                        }
                    default:
                        break
                    }
                    if selected.isSemanticallyEqual(to: wallpaper) {
                        continue
                    }
                    entries.append(WallpaperEntry(index: index, wallpaper: wallpaper, telegramWallpaper: item, selected: false))
                    index += 1
                }
            }

            return entries
        }

    actionsDisposable.add((wallpapersSignal |> deliverOnMainQueue).start(next: { entries in
        updateState { current in
            var current = current
            current.entries = entries
            return current
        }
    }))

    let signal = statePromise.get() |> filter { !$0.entries.isEmpty } |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, context: context, interaction: interaction))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().chatWPBackgroundTitle)
    if case .chat = source {
        controller.analyticsScreen = .chatWallpaper
    } else {
        controller.analyticsScreen = .settingsAppearanceWallpaper
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().chatWPSelectFromFile, accept: {
        filePanel(with: photoExts, allowMultiple: false, for: context.window, completion: { paths in
            if let path = paths?.first {
                let size = fs(path)
                if let size = size, size < 10 * 1024 * 1024, let image = NSImage(contentsOf: URL(fileURLWithPath: path))?.cgImage(forProposedRect: nil, context: nil, hints: nil), image.size.width > 500 && image.size.height > 500 {

                    let options = NSMutableDictionary()
                    options.setValue(90 as NSNumber, forKey: kCGImageDestinationImageMaxPixelSize as String)
                    var representations: [TelegramMediaImageRepresentation] = []
                    let colorQuality: Float = 0.1
                    options.setObject(colorQuality as NSNumber, forKey: kCGImageDestinationLossyCompressionQuality as NSString)
                    let mutableData: CFMutableData = NSMutableData() as CFMutableData

                    if let colorDestination = CGImageDestinationCreateWithData(mutableData, kUTTypeJPEG, 1, nil) {
                        CGImageDestinationAddImage(colorDestination, image, options as CFDictionary)
                        if CGImageDestinationFinalize(colorDestination) {
                            let thumdResource = LocalFileMediaResource(fileId: arc4random64())
                            context.account.postbox.mediaBox.storeResourceData(thumdResource.id, data: mutableData as Data)
                            representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(image.size.aspectFitted(NSMakeSize(90, 90))), resource: thumdResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
                        }
                    }

                    let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                    guard let data = data else {
                        return
                    }
                    let resource = LocalFileMediaResource(fileId: arc4random64(), size: Int64(data.count))
                    context.account.postbox.mediaBox.storeResourceData(resource.id, data: data)

                    representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(image.size), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))

                    showModal(with: WallpaperPreviewController(context, wallpaper: .image(representations, settings: WallpaperSettings()), source: source, onComplete: onComplete), for: context.window)

                } else {
                    alert(for: context.window, header: appName, info: strings().appearanceCustomBackgroundFileError)
                }
            }
        })
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(380, 400))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
