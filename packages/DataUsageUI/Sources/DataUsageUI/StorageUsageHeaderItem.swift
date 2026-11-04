import Cocoa
import TGUIKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import LocalAnimations
import SwiftSignalKit
import TelegramCore
import Postbox
import AvatarUI

public final class StorageUsageHeaderItem : GeneralRowItem {
    public let progress: CGFloat
    public let textLayout: TextViewLayout
    public let headerLayout: TextViewLayout
    public init(_ initialSize: NSSize, stableId: AnyHashable, header: String, string: String, progress: CGFloat, viewType: GeneralViewType) {
        
        let progress = progress.isFinite ? min(1, max(0, progress)) : 0

        
        self.headerLayout = .init(.initialize(string: header, color: theme.colors.text, font: .medium(.header)), alignment: .center)

        
        let attr = NSMutableAttributedString()
        _ = attr.append(string: string, color: theme.colors.listGrayText, font: .normal(.text))
        attr.detectBoldColorInString(with: .medium(.text))
        self.textLayout = .init(attr, alignment: .center)
        self.progress = progress
        super.init(initialSize, stableId: stableId, viewType: viewType)
        _ = makeSize(initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.textLayout.measure(width: width - 60)
        self.headerLayout.measure(width: width - 60)
        return true
    }
    
    public override var height: CGFloat {
        return 10 + self.headerLayout.layoutSize.height + 5 + self.textLayout.layoutSize.height + (progress > 0 ? 10 : 0)
    }
    
    public override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return textLayout.attributedString.string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return StorageUsageHeaderItemView.self
    }
}


private final class StorageUsageHeaderItemView: GeneralRowView {
    private let textView = TextView()
    private let headerView = TextView()
    private let progressView = LinearProgressControl(progressHeight: 4)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(headerView)
        addSubview(textView)
        addSubview(progressView)
        progressView.roundCorners = true
        progressView.layer?.cornerRadius = 2
//        progressView.alignment = .center
        progressView.liveScrobbling = false
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        headerView.centerX(y: 10)
        textView.centerX(y: headerView.frame.maxY + 5)
        progressView.centerX(y: textView.frame.maxY + 5)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StorageUsageHeaderItem else {
            return
        }
        
        headerView.update(item.headerLayout)
        
        progressView.isHidden = item.progress == 0
        
        textView.update(item.textLayout)
        progressView.style = ControlStyle(foregroundColor: theme.colors.accent.withAlphaComponent(0.8), backgroundColor: theme.colors.accent.withAlphaComponent(0.2), highlightColor: .clear)
        textView.isHidden = item.textLayout.attributedString.length == 0
        progressView.setFrameSize(NSMakeSize(max(0, min(textView.frame.width - 40, 260)), 4))

        progressView.set(progress: item.progress, animated: animated)
        needsLayout = true
    }
}
