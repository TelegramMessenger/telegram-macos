import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import SecureIdUtils
import TelegramLinks
import PhoneNumberUtils
import KeyboardKey
import TGPassportMRZ
import OCR
import FilePanels
import ObjcUtils

class PassportSettingsHeaderItem: GeneralRowItem {

    init(_ initialSize: NSSize, stableId: AnyHashable) {
        super.init(initialSize, height: theme.icons.passportSettings.backingSize.height, stableId: stableId)
    }
    
    override func viewClass() -> AnyClass {
        return PassportSettingsHeaderItemView.self
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override var accessibilityIsSpacer: Bool {
        return true
    }
}

private final class PassportSettingsHeaderItemView : TableRowView {
    private let imageView: ImageView = ImageView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        imageView.isAccessibilityDecorative = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        imageView.image = theme.icons.passportSettings
        imageView.sizeToFit()
        imageView.center()
    }
    
    
}
