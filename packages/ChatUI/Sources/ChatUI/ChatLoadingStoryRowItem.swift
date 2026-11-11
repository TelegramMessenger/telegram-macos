import AppKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TGUIKit
import ChatHistoryModel
import TelegramTheme
import TelegramContext
import Localization

final class ChatLoadingStoryRowItem: ChatRowItem {
    override func makeContentSize(_ width: CGFloat) -> NSSize {
        let side = max(1, min(width, 320))
        return NSSize(width: side * 9 / 16, height: side)
    }

    override func viewClass() -> AnyClass { ChatLoadingStoryRowView.self }
}

final class ChatLoadingStoryRowView: ChatRowView {
    private let placeholder = View()
    private let shimmer = ShimmerView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        placeholder.isEventLess = true
        placeholder.layer?.cornerRadius = 8
        placeholder.layer?.masksToBounds = true
        placeholder.addSubview(shimmer)
        addSubview(placeholder)
        placeholder.setAccessibilityElement(true)
        placeholder.setAccessibilityLabel(strings().messagesReplyLoadingLoading)
        placeholder.setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? ChatLoadingStoryRowItem else { return }
        placeholder.setFrameSize(item.contentSize)
        placeholder.backgroundColor = item.presentation.colors.grayForeground
        shimmer.frame = placeholder.bounds
        shimmer.update(backgroundColor: .clear, data: nil, size: placeholder.frame.size, imageSize: placeholder.frame.size)
        shimmer.updateAbsoluteRect(placeholder.bounds, within: placeholder.frame.size)
    }
}
