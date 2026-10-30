import Cocoa
import TGUIKit
import InputDataUI
import GeneralRows
import TelegramTheme
import Localization

final class WalletWordInputRowItem: InputDataRowItem {
    fileprivate let isMismatched: Bool
    private let displayNumber: Int

    init(_ initialSize: NSSize, stableId: AnyHashable, currentText: String, displayNumber: Int, rightItem: InputDataRightItem?, isMismatched: Bool, updated: @escaping (String) -> Void) {
        self.isMismatched = isMismatched
        self.displayNumber = displayNumber
        super.init(initialSize, stableId: stableId, mode: .plain, error: nil, viewType: .singleItem, currentText: currentText, placeholder: .init("\(displayNumber)"), inputPlaceholder: " ", rightItem: rightItem, filter: { $0.lowercased() }, updated: updated, pasteFilter: walletRecoveryPasteFilter, limit: 300, customTheme: GeneralRowItem.Theme(backgroundColor: theme.colors.grayBackground, grayTextColor: theme.colors.text))
    }

    override func viewClass() -> AnyClass {
        return WalletWordInputRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverWalletWord(displayNumber)
    }
}

private final class WalletWordInputRowView: InputDataRowView {
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        containerView.layer?.cornerRadius = containerView.cornerRadius
    }

    override func layout() {
        super.layout()
        containerView.layer?.cornerRadius = min(containerView.frame.height / 2, containerView.cornerRadius)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func shakeView() {
        containerView.shake()
    }

    override func updateColors() {
        super.updateColors()
        guard let item = item as? WalletWordInputRowItem else {
            return
        }
        containerView.layer?.borderWidth = item.isMismatched ? 1 : 0
        containerView.layer?.borderColor = theme.colors.redUI.cgColor
    }
}
