import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import LocalAnimations
import GeneralRows
import SidebarUI

public struct ForumSettingsHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem
    public let sidebarImage: (SidebarImage) -> NSImage
    public let sidebarPreviewImage: () -> NSImage

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, CGImage?) -> TableRowItem,
                sidebarImage: @escaping (SidebarImage) -> NSImage,
                sidebarPreviewImage: @escaping () -> NSImage) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
        self.sidebarImage = sidebarImage
        self.sidebarPreviewImage = sidebarPreviewImage
    }

    private static var _shared: ForumSettingsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ForumSettingsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ForumSettingsHooks.install must be called before the forum settings screen is used")
        return .placeholder
    }

    public static func install(_ hooks: ForumSettingsHooks) {
        assert(Thread.isMainThread, "ForumSettingsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ForumSettingsHooks(
        makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
            GeneralRowItem(initialSize, stableId: stableId) },
        sidebarImage: { _ in NSImage() },
        sidebarPreviewImage: { NSImage() }
    )
}
