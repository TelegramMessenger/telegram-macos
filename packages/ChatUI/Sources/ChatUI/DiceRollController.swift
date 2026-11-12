import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputView
import CurrencyFormat
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import InputTextView
import LocalAnimations
import InlineStickerLayer
import AppAnalytics

// MARK: - Arguments
private final class Arguments {
    let context: any AccountContextProtocol
    let dismiss: () -> Void
    let updateStake: (Updated_ChatTextInputState) -> Void
    let interactions: TextView_Interactions

    init(context: any AccountContextProtocol, dismiss: @escaping () -> Void, updateStake: @escaping (Updated_ChatTextInputState) -> Void, interactions: TextView_Interactions) {
        self.context = context
        self.dismiss = dismiss
        self.updateStake = updateStake
        self.interactions = interactions
    }
}

// MARK: - EmojiGameStakeConfiguration
private struct EmojiGameStakeConfiguration: Equatable {
    static var defaultValue: EmojiGameStakeConfiguration {
        return EmojiGameStakeConfiguration(
            tonUsdRate: nil,
            minStakeAmount: nil,
            maxStakeAmount: nil,
            suggestedAmounts: [
                100000000,
                1000000000,
                2000000000,
                5000000000,
                10000000000,
                20000000000
            ]
        )
    }

    let tonUsdRate: Double?
    let minStakeAmount: Int64?
    let maxStakeAmount: Int64?
    let suggestedAmounts: [Int64]

    fileprivate init(
        tonUsdRate: Double?,
        minStakeAmount: Int64?,
        maxStakeAmount: Int64?,
        suggestedAmounts: [Int64]
    ) {
        self.tonUsdRate = tonUsdRate
        self.minStakeAmount = minStakeAmount
        self.maxStakeAmount = maxStakeAmount
        self.suggestedAmounts = suggestedAmounts
    }

    static func with(appConfiguration: AppConfiguration) -> EmojiGameStakeConfiguration {
        if let data = appConfiguration.data {
            var tonUsdRate: Double?
            if let value = data["ton_usd_rate"] as? Double {
                tonUsdRate = value
            }

            var minStakeAmount: Int64?
            if let value = data["ton_stakedice_stake_amount_min"] as? Double {
                minStakeAmount = Int64(value)
            }

            var maxStakeAmount: Int64?
            if let value = data["ton_stakedice_stake_amount_max"] as? Double {
                maxStakeAmount = Int64(value)
            }

            var suggestedAmounts: [Int64] = []
            if let value = data["ton_stakedice_stake_suggested_amounts"] as? [Double] {
                suggestedAmounts = value.map { Int64($0) }
            } else {
                suggestedAmounts = EmojiGameStakeConfiguration.defaultValue.suggestedAmounts
            }

            return EmojiGameStakeConfiguration(
                tonUsdRate: tonUsdRate,
                minStakeAmount: minStakeAmount,
                maxStakeAmount: maxStakeAmount,
                suggestedAmounts: suggestedAmounts
            )
        } else {
            return .defaultValue
        }
    }
}

// MARK: - State
private struct Roll: Equatable {
    let side: Int  // 1-6
    let outcome: Double  // multiplier like 0.3, 1.3, etc.
    let isJackpot: Bool  // for the triple-dice jackpot

    static let defaultRolls: [Roll] = [
        Roll(side: 1, outcome: 0.0, isJackpot: false),
        Roll(side: 2, outcome: 0.3, isJackpot: false),
        Roll(side: 3, outcome: 0.6, isJackpot: false),
        Roll(side: 4, outcome: 1.3, isJackpot: false),
        Roll(side: 5, outcome: 1.6, isJackpot: false),
        Roll(side: 6, outcome: 2.0, isJackpot: false),
        Roll(side: 6, outcome: 20.0, isJackpot: true)
    ]

    static func fromParameters(_ parameters: [Int32]) -> [Roll] {
        guard parameters.count >= 7 else {
            return defaultRolls
        }
        return [
            Roll(side: 1, outcome: Double(parameters[0]) / 1000.0, isJackpot: false),
            Roll(side: 2, outcome: Double(parameters[1]) / 1000.0, isJackpot: false),
            Roll(side: 3, outcome: Double(parameters[2]) / 1000.0, isJackpot: false),
            Roll(side: 4, outcome: Double(parameters[3]) / 1000.0, isJackpot: false),
            Roll(side: 5, outcome: Double(parameters[4]) / 1000.0, isJackpot: false),
            Roll(side: 6, outcome: Double(parameters[5]) / 1000.0, isJackpot: false),
            Roll(side: 6, outcome: Double(parameters[6]) / 1000.0, isJackpot: true)
        ]
    }
}

private struct State: Equatable {
    var rolls: [Roll] = Roll.defaultRolls
    var stakeInput: Updated_ChatTextInputState = .init()
    var stakeConfig: EmojiGameStakeConfiguration = .defaultValue
    var tonBalance: Int64?
    var diceFiles: [TelegramMediaFile] = []
    var currentDiceFileIndex: Int = 0

    var stakePresets: [[Int64]] {
        var presets: [[Int64]] = []
        var currentRow: [Int64] = []
        for amount in stakeConfig.suggestedAmounts {
            currentRow.append(amount)
            if currentRow.count == 3 {
                presets.append(currentRow)
                currentRow = []
            }
        }
        if !currentRow.isEmpty {
            presets.append(currentRow)
        }
        return presets
    }

    var currentDiceFile: TelegramMediaFile? {
        guard !diceFiles.isEmpty, currentDiceFileIndex > 0, currentDiceFileIndex < diceFiles.count else {
            return nil
        }
        return diceFiles[currentDiceFileIndex]
    }

    var amount: Int64? {
        if let doubleValue = Double(stakeInput.string) {
            if doubleValue == 0 {
                return nil
            } else {
                return Int64(doubleValue * 1_000_000_000)
            }
        } else {
            return nil
        }
    }

    var stakeError: String? {
        guard let amount = amount else {
            return nil
        }
        if let minStake = stakeConfig.minStakeAmount, amount < minStake {
            let minFormatted = formatCurrencyAmount(minStake, currency: TON).prettyCurrencyNumberUsd
            return strings().diceRollMinStake(minFormatted)
        }
        if let maxStake = stakeConfig.maxStakeAmount, amount > maxStake {
            let maxFormatted = formatCurrencyAmount(maxStake, currency: TON).prettyCurrencyNumberUsd
            return strings().diceRollMaxStake(maxFormatted)
        }
        return nil
    }

    var media: TelegramMediaDice {
        return .init(emoji: "🎲", tonAmount: amount)
    }
}

// MARK: - DiceRollHeaderItem
private final class DiceRollHeaderItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let headerLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    fileprivate let balanceLayout: TextViewLayout
    fileprivate let badge: CGImage?
    fileprivate let sticker: LocalAnimatedSticker?
    fileprivate let file: TelegramMediaFile?
    fileprivate let fileParameters: ChatAnimatedStickerMediaLayoutParameters?
    fileprivate let stickerSize: NSSize
    fileprivate let dismiss: () -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, sticker: LocalAnimatedSticker?, file: TelegramMediaFile?, fileParameters: ChatAnimatedStickerMediaLayoutParameters?, headerText: NSAttributedString, infoText: NSAttributedString, tonBalance: Int64?, stickerSize: NSSize = NSMakeSize(100, 100), badge: CGImage? = nil, dismiss: @escaping () -> Void) {
        self.context = context
        self.sticker = sticker
        self.file = file
        self.fileParameters = fileParameters
        self.stickerSize = stickerSize
        self.badge = badge
        self.dismiss = dismiss

        self.headerLayout = TextViewLayout(headerText, alignment: .center, alwaysStaticItems: true)
        self.infoLayout = TextViewLayout(infoText, alignment: .center, alwaysStaticItems: true)

        let balanceAttr = NSMutableAttributedString()
        if let tonBalance = tonBalance {
            let formattedBalance = formatCurrencyAmount(tonBalance, currency: TON).prettyCurrencyNumberUsd
            balanceAttr.append(string: strings().starPurchaseBalance("\(clown)\(TINY_SPACE)\(formattedBalance)"), color: theme.colors.text, font: .normal(.text))
            balanceAttr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.accent), for: clown)
        }
        self.balanceLayout = TextViewLayout(balanceAttr, alignment: .right)

        super.init(initialSize, stableId: stableId, viewType: .legacy, inset: NSEdgeInsets(left: 20, right: 20, top: 0, bottom: 10))
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        balanceLayout.measure(width: .greatestFiniteMagnitude)
        headerLayout.measure(width: width - inset.left - inset.right)
        infoLayout.measure(width: width - inset.left - inset.right)
        return true
    }

    override func viewClass() -> AnyClass {
        return DiceRollHeaderView.self
    }

    override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }

    override var accessibilityValue: String? {
        let text = infoLayout.attributedString.string
        return text.isEmpty ? nil : text
    }

    override var height: CGFloat {
        var height: CGFloat = 10 + stickerSize.height + 10 + headerLayout.layoutSize.height
        height += 10 + infoLayout.layoutSize.height
        height += inset.bottom
        return height
    }
}

private final class DiceRollHeaderView: GeneralRowView {
    private var animationView: MediaAnimatedStickerView?
    private let headerView = TextView()
    private let infoView = TextView()
    private let balanceView = InteractiveTextView()
    private var dismissButton: ImageButton?
    private var badgeView: ImageView?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(headerView)
        addSubview(infoView)
        addSubview(balanceView)

        headerView.isSelectable = false
        headerView.userInteractionEnabled = false
        infoView.isSelectable = false
        infoView.userInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override func updateColors() {
        super.updateColors()
        headerView.backgroundColor = backdorColor
        infoView.backgroundColor = backdorColor
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? DiceRollHeaderItem else { return }

        if let file = item.file, let params = item.fileParameters {
            let current: MediaAnimatedStickerView
            if let view = self.animationView {
                current = view
            } else {
                current = MediaAnimatedStickerView(frame: item.stickerSize.bounds)
                self.animationView = current
                addSubview(current)
            }
            current.update(with: file, size: item.stickerSize, context: item.context, parent: nil, table: item.table, parameters: params, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
        } else if let sticker = item.sticker {
            let current: MediaAnimatedStickerView
            if let view = self.animationView {
                current = view
            } else {
                current = MediaAnimatedStickerView(frame: item.stickerSize.bounds)
                self.animationView = current
                addSubview(current)
            }
            let params = sticker.parameters
            current.update(with: sticker.file, size: item.stickerSize, context: item.context, parent: nil, table: item.table, parameters: params, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
        } else {
            if let view = self.animationView {
                performSubviewRemoval(view, animated: animated)
                self.animationView = nil
            }
        }

        headerView.update(item.headerLayout)
        infoView.update(item.infoLayout)
        balanceView.set(text: item.balanceLayout, context: item.context)

        if let badge = item.badge {
            let current: ImageView
            if let view = self.badgeView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.badgeView = current
                addSubview(current)
            }
            current.image = badge
            current.sizeToFit()
        } else {
            if let view = self.badgeView {
                performSubviewRemoval(view, animated: animated)
                self.badgeView = nil
            }
        }

        let current: ImageButton
        if let view = self.dismissButton {
            current = view
        } else {
            current = ImageButton()
            current.scaleOnClick = true
            current.autohighlight = false
            current.setAccessibilityLabel(strings().voiceOverCommonClose)
            self.dismissButton = current
            addSubview(current)
        }
        current.set(image: theme.icons.glass_close, for: .Normal)
        current.setGlassEffect(size: NSMakeSize(36, 36))
        current.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        current.removeAllHandlers()
        current.set(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .Click)

        needsLayout = true
    }

    override func layout() {
        super.layout()

        dismissButton?.setFrameOrigin(NSMakePoint(10, 10))
        balanceView.setFrameOrigin(NSMakePoint(frame.width - balanceView.frame.width - 12, 10))

        if let animationView = self.animationView {
            animationView.centerX(y: 10)

            let headerY = animationView.frame.maxY + 10
            if let badgeView = self.badgeView {
                let totalWidth = headerView.frame.width + 5 + badgeView.frame.width
                let startX = (self.frame.width - totalWidth) / 2
                headerView.setFrameOrigin(NSMakePoint(startX, headerY))
                badgeView.setFrameOrigin(NSMakePoint(headerView.frame.maxX + 5, headerY + (headerView.frame.height - badgeView.frame.height) / 2 - 1))
            } else {
                headerView.centerX(y: headerY)
            }

            infoView.centerX(y: headerView.frame.maxY + 10)
        }
    }
}

// MARK: - Entry Identifiers
private let _id_header = InputDataIdentifier("_id_header")
private let _id_results_header = InputDataIdentifier("_id_results_header")
private let _id_dice_results = InputDataIdentifier("_id_dice_results")
private let _id_streak_info = InputDataIdentifier("_id_streak_info")
private let _id_stake_header = InputDataIdentifier("_id_stake_header")
private let _id_stake_input = InputDataIdentifier("_id_stake_input")
private let _id_stake_keyboard = InputDataIdentifier("_id_stake_keyboard")

// MARK: - Entries
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0


    // Header with animated sticker and TON balance
    struct HeaderEquatable: Equatable {
        let file: TelegramMediaFile?
        let tonBalance: Int64?
    }
    entries.append(.custom(
        sectionId: sectionId,
        index: index,
        value: .none,
        identifier: _id_header,
        equatable: .init(HeaderEquatable(file: state.currentDiceFile, tonBalance: state.tonBalance)),
        comparable: nil,
        item: { initialSize, stableId in
            let headerText = strings().diceRollEmojiStake
            let descText = strings().diceRollEmojiStakeDescription

            let headerAttr = NSMutableAttributedString()
            _ = headerAttr.append(string: headerText, color: theme.colors.text, font: .medium(.header))

            let infoAttr = NSMutableAttributedString()
            _ = infoAttr.append(string: descText, color: theme.colors.listGrayText, font: .normal(.text))

            let badge = generateTextIcon_AccentBadge(text: "BETA", bgColor: theme.colors.accent, textColor: theme.colors.underSelectedColor)

            let file = state.currentDiceFile
            let fileParameters: ChatAnimatedStickerMediaLayoutParameters?
            if let file {
                fileParameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .onceEnd, alwaysAccept: true, cache: .temporaryLZ4(.thumb), hidePlayer: true, media: file, shimmer: false, thumbAtFrame: 1)
            } else {
                fileParameters = nil
            }

            return DiceRollHeaderItem(
                initialSize,
                stableId: stableId,
                context: arguments.context,
                sticker: file == nil ? LocalAnimatedSticker.dice_roll : nil,
                file: file,
                fileParameters: fileParameters,
                headerText: headerAttr,
                infoText: infoAttr,
                tonBalance: state.tonBalance,
                stickerSize: NSMakeSize(100, 100),
                badge: badge,
                dismiss: arguments.dismiss
            )
        }
    ))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    // Results and Returns header
    entries.append(.desc(
        sectionId: sectionId,
        index: index,
        text: .plain(strings().diceRollResultsAndReturns),
        data: .init(
            color: theme.colors.listGrayText,
            viewType: .textTopItem
        )
    ))
    index += 1

    // Dice results grid
    entries.append(.custom(
        sectionId: sectionId,
        index: index,
        value: .none,
        identifier: _id_dice_results,
        equatable: .init(state.rolls),
        comparable: nil,
        item: { initialSize, stableId in
            return DiceResultsRowItem(
                initialSize,
                stableId: stableId,
                context: arguments.context,
                rolls: state.rolls,
                viewType: .singleItem
            )
        }
    ))
    index += 1

    // Streak info
    let streakAttr = NSMutableAttributedString()
    _ = streakAttr.append(string: strings().diceRollStreakResetInfo(clown), color: theme.colors.listGrayText, font: .normal(.text))
    streakAttr.insertEmbedded(.embedded(name: "dice_6", color: nil, resize: true), for: clown)

    entries.append(.desc(
        sectionId: sectionId,
        index: index,
        text: .attributed(streakAttr),
        data: .init(
            color: theme.colors.listGrayText,
            viewType: .textBottomItem,
            context: arguments.context
        )
    ))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

//    // Your stake header
//    entries.append(.desc(
//        sectionId: sectionId,
//        index: index,
//        text: .plain(strings().diceRollYourStake),
//        data: .init(
//            color: theme.colors.listGrayText,
//            viewType: .textTopItem
//        )
//    ))
//    index += 1

    // Stake input
    entries.append(.custom(
        sectionId: sectionId,
        index: index,
        value: .none,
        identifier: _id_stake_input,
        equatable: .init(state.stakeInput),
        comparable: nil,
        item: { initialSize, stableId in
            return StakeInputRowItem(
                initialSize,
                stableId: stableId,
                context: arguments.context,
                inputState: state.stakeInput,
                interactions: arguments.interactions,
                updateStake: arguments.updateStake,
                viewType: .singleItem
            )
        }
    ))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    // Stake keyboard
    entries.append(.custom(
        sectionId: sectionId,
        index: index,
        value: .none,
        identifier: _id_stake_keyboard,
        equatable: .init(state.stakePresets),
        comparable: nil,
        item: { initialSize, stableId in
            return StakeKeyboardRowItem(
                initialSize,
                stableId: stableId,
                context: arguments.context,
                stakes: state.stakePresets,
                selectStake: { value in
                    let formattedValue = formatCurrencyAmount(value, currency: TON).prettyCurrencyNumberUsd
                    arguments.updateStake(.init(inputText: .init(string: formattedValue), selectionRange: formattedValue.length ..< formattedValue.length))
                },
                viewType: .singleItem
            )
        }
    ))
    index += 1

    // Final section break
    entries.append(.sectionId(sectionId, type: .normal))

    return entries
}

// MARK: - DiceCellOption
private struct DiceCellOption {
    let images: [CGImage]
    let imageSize: CGFloat
    let textLayout: TextViewLayout

    var cellHeight: CGFloat {
        // top padding + image + spacing + text + bottom padding
        return 10 + imageSize + 6 + textLayout.layoutSize.height + 10
    }

    init(roll: Roll) {
        // Create images
        let image = NSImage(named: "dice_\(roll.side)")!.precomposed()
        if roll.isJackpot {
            self.images = [image, image, image]
            self.imageSize = 24
        } else {
            self.images = [image]
            self.imageSize = 30
        }

        // Format outcome text
        let outcomeText: String
        if roll.outcome == 0.0 {
            outcomeText = "x0"
        } else if roll.outcome == floor(roll.outcome) {
            outcomeText = "x\(Int(roll.outcome))"
        } else {
            outcomeText = "x\(String(format: "%.1f", roll.outcome))"
        }

        self.textLayout = TextViewLayout(
            .initialize(string: outcomeText, color: theme.colors.text, font: .medium(.text)),
            maximumNumberOfLines: 1,
            alignment: .center
        )
        self.textLayout.measure(width: .greatestFiniteMagnitude)
    }
}

// MARK: - DiceResultsRowItem
private final class DiceResultsRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let rolls: [Roll]
    fileprivate let cellOptions: [DiceCellOption]
    fileprivate let cellHeight: CGFloat

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, rolls: [Roll], viewType: GeneralViewType) {
        self.context = context
        self.rolls = rolls
        self.cellOptions = rolls.map { DiceCellOption(roll: $0) }
        // Calculate max cell height from all options
        self.cellHeight = cellOptions.map { $0.cellHeight }.max() ?? 70
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override func viewClass() -> AnyClass {
        return DiceResultsRowView.self
    }

    override var accessibilityLabel: String? {
        let texts = cellOptions.map { $0.textLayout.attributedString.string }.filter { !$0.isEmpty }
        return texts.isEmpty ? nil : texts.joined(separator: ", ")
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override var height: CGFloat {
        // Two rows of cells
        return cellHeight * 2
    }
}

private final class DiceResultsRowView: GeneralRowView {
    private var cellViews: [DiceCellView] = []
    private let outerBorderLayer = CAShapeLayer()
    private var separatorLayers: [CALayer] = []

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        outerBorderLayer.fillColor = NSColor.clear.cgColor
        outerBorderLayer.strokeColor = theme.colors.border.cgColor
        outerBorderLayer.lineWidth = 1.0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? DiceResultsRowItem else { return }

        // Remove old cells
        for cell in cellViews {
            cell.removeFromSuperview()
        }
        cellViews.removeAll()

        // Remove old separators
        for sep in separatorLayers {
            sep.removeFromSuperlayer()
        }
        separatorLayers.removeAll()

        // Create cells for each option
        for option in item.cellOptions {
            let cellView = DiceCellView(frame: NSZeroRect)
            cellView.update(with: option)
            self.addSubview(cellView)
            cellViews.append(cellView)
        }

        // Add outer border layer
        self.layer?.addSublayer(outerBorderLayer)

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? DiceResultsRowItem else { return }

        let insets = item.inset
        let availableWidth = self.frame.width - insets.left - insets.right

        let cellHeight = item.cellHeight

        // First row: 4 cells (equal width)
        let firstRowCellWidth = availableWidth / 4
        // Second row: 3 cells (equal width)
        let secondRowCellWidth = availableWidth / 3

        // Layout first row (4 cells - sides 1-4)
        for i in 0..<min(4, cellViews.count) {
            let x = insets.left + CGFloat(i) * firstRowCellWidth
            let y: CGFloat = 0
            cellViews[i].frame = NSRect(x: x, y: y, width: firstRowCellWidth, height: cellHeight)
        }

        // Layout second row (3 cells - sides 5, 6, jackpot)
        for i in 4..<min(7, cellViews.count) {
            let localIndex = i - 4
            let x = insets.left + CGFloat(localIndex) * secondRowCellWidth
            let y = cellHeight
            cellViews[i].frame = NSRect(x: x, y: y, width: secondRowCellWidth, height: cellHeight)
        }

        // Update outer border
        let totalHeight = cellHeight * 2
        let borderRect = NSRect(x: insets.left, y: 0, width: availableWidth, height: totalHeight)
        let path = NSBezierPath(roundedRect: borderRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        outerBorderLayer.path = path._cgPath
        outerBorderLayer.frame = self.bounds

        // Remove old separators
        for sep in separatorLayers {
            sep.removeFromSuperlayer()
        }
        separatorLayers.removeAll()

        // Add vertical separators for first row (between cells)
        for i in 1..<4 {
            let sep = CALayer()
            sep.backgroundColor = theme.colors.border.cgColor
            let x = insets.left + CGFloat(i) * firstRowCellWidth
            sep.frame = CGRect(x: x, y: 0, width: 1, height: cellHeight)
            self.layer?.addSublayer(sep)
            separatorLayers.append(sep)
        }

        // Add vertical separators for second row (between cells)
        for i in 1..<3 {
            let sep = CALayer()
            sep.backgroundColor = theme.colors.border.cgColor
            let x = insets.left + CGFloat(i) * secondRowCellWidth
            sep.frame = CGRect(x: x, y: cellHeight, width: 1, height: cellHeight)
            self.layer?.addSublayer(sep)
            separatorLayers.append(sep)
        }

        // Add horizontal separator between rows
        let hSep = CALayer()
        hSep.backgroundColor = theme.colors.border.cgColor
        hSep.frame = CGRect(x: insets.left, y: cellHeight, width: availableWidth, height: 1)
        self.layer?.addSublayer(hSep)
        separatorLayers.append(hSep)
    }

    override func updateColors() {
        super.updateColors()
        outerBorderLayer.strokeColor = theme.colors.border.cgColor
        for sep in separatorLayers {
            sep.backgroundColor = theme.colors.border.cgColor
        }
    }
}

private final class DiceCellView: View {
    private var diceImageViews: [ImageView] = []
    private let outcomeLabel = TextView()
    private var option: DiceCellOption?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        outcomeLabel.isSelectable = false
        outcomeLabel.userInteractionEnabled = false
        addSubview(outcomeLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with option: DiceCellOption) {
        self.option = option

        // Clear old dice images
        for imageView in diceImageViews {
            imageView.removeFromSuperview()
        }
        diceImageViews.removeAll()

        // Create image views from pre-calculated images
        for image in option.images {
            let imageView = ImageView()
            imageView.isAccessibilityDecorative = true
            imageView.image = image
            imageView.setFrameSize(NSSize(width: option.imageSize, height: option.imageSize))
            addSubview(imageView)
            diceImageViews.append(imageView)
        }

        // Use pre-calculated text layout
        outcomeLabel.update(option.textLayout)

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let option = option else { return }

        let imageSize = option.imageSize
        let totalImagesWidth = CGFloat(diceImageViews.count) * imageSize + CGFloat(max(0, diceImageViews.count - 1)) * 4

        // Center images horizontally
        var x = (bounds.width - totalImagesWidth) / 2
        let y: CGFloat = 10

        for imageView in diceImageViews {
            imageView.frame = NSRect(x: x, y: y, width: imageSize, height: imageSize)
            x += imageSize + 4
        }

        let layout = option.textLayout
        let labelY = y + imageSize + 6
        outcomeLabel.frame = NSRect(
            x: (bounds.width - layout.layoutSize.width) / 2,
            y: labelY,
            width: layout.layoutSize.width,
            height: layout.layoutSize.height
        )
    }
}

// MARK: - StakeInputRowItem
private final class StakeInputRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let inputState: Updated_ChatTextInputState
    fileprivate let interactions: TextView_Interactions
    fileprivate let updateStake: (Updated_ChatTextInputState) -> Void
    fileprivate let usdLayout: TextViewLayout

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, inputState: Updated_ChatTextInputState, interactions: TextView_Interactions, updateStake: @escaping (Updated_ChatTextInputState) -> Void, viewType: GeneralViewType) {
        self.context = context
        self.inputState = inputState
        self.interactions = interactions
        self.updateStake = updateStake

        let usd_rate = context.appConfiguration.getGeneralValueDouble("ton_usd_rate", orElse: 3)
        let value = Double(inputState.string) ?? 0
        self.usdLayout = .init(.initialize(string: "~\("\(value * usd_rate)".prettyCurrencyNumberUsd)", color: theme.colors.grayText, font: .normal(.short)))
        self.usdLayout.measure(width: .greatestFiniteMagnitude)

        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    

    override func viewClass() -> AnyClass {
        return StakeInputRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().diceRollEnterStakePlaceholder
    }

    override var accessibilityValue: String? {
        return usdLayout.attributedString.string
    }

    override var height: CGFloat {
        return 40
    }
}

private final class StakeInputRowView: GeneralContainableRowView {

    private final class StakeInput: View {
        private weak var item: StakeInputRowItem?
        let inputView: UITextView = UITextView(frame: NSMakeRect(0, 0, 100, 40))
        private let tonView = InteractiveTextView()

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(tonView)
            addSubview(inputView)
            layer?.cornerRadius = 10
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(item: StakeInputRowItem, animated: Bool) {
            self.item = item
            self.backgroundColor = theme.colors.background

            let attr = NSMutableAttributedString()
            attr.append(string: clown)
            attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.accent), for: clown)

            let layout = TextViewLayout(attr)
            layout.measure(width: .greatestFiniteMagnitude)

            self.tonView.set(text: layout, context: item.context)

            inputView.placeholder = strings().diceRollEnterStakePlaceholder

            inputView.context = item.context
            inputView.interactions.max_height = 500
            inputView.interactions.min_height = 13
            inputView.interactions.emojiPlayPolicy = .onceEnd
            inputView.interactions.canTransform = false

            item.interactions.min_height = 13
            item.interactions.max_height = 500
            item.interactions.emojiPlayPolicy = .onceEnd
            item.interactions.canTransform = false

            item.interactions.filterEvent = { event in
                if let chars = event.characters {
                    return chars.trimmingCharacters(in: CharacterSet(charactersIn: "1234567890.\u{7f}")).isEmpty
                } else {
                    return false
                }
            }

            self.inputView.set(item.interactions.presentation.textInputState())
            self.inputView.interactions = item.interactions

            item.interactions.inputDidUpdate = { [weak self] state in
                guard let self = self else { return }
                self.set(state)
                self.inputDidUpdateLayout(animated: true)
            }
        }

        var textWidth: CGFloat {
            return frame.width - 20
        }

        func textViewSize() -> (NSSize, CGFloat) {
            return inputTextViewSize(inputView, width: textWidth)
        }

        private func inputDidUpdateLayout(animated: Bool) {
            self.updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        }

        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            let (textSize, textHeight) = textViewSize()

            transition.updateFrame(view: tonView, frame: tonView.centerFrameY(x: 10))
            transition.updateFrame(view: inputView, frame: CGRect(origin: CGPoint(x: tonView.frame.maxX + 10, y: 7), size: textSize))
            inputView.updateLayout(size: textSize, textHeight: textHeight, transition: transition)
        }

        private func set(_ state: Updated_ChatTextInputState) {
            guard let item = item else { return }
            item.updateStake(state)
            item.redraw(animated: true)
        }

        override func layout() {
            super.layout()
            updateLayout(size: frame.size, transition: .immediate)
        }
    }
    
    override func shakeView() {
        super.shakeView()
        inputView.shake(beep: true)
    }

    private let inputView = StakeInput(frame: NSMakeRect(0, 0, 100, 40))
    private let usdView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(inputView)
        addSubview(usdView)
        usdView.userInteractionEnabled = false
        usdView.isSelectable = false
    }
    
    override var firstResponder: NSResponder? {
        return inputView.inputView.inputView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? StakeInputRowItem else { return }

        inputView.update(item: item, animated: animated)
        usdView.update(item.usdLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? StakeInputRowItem else { return }

        let usdWidth = item.usdLayout.layoutSize.width + 10
        inputView.frame = NSRect(x: 0, y: 0, width: containerView.frame.width - usdWidth, height: item.height)
        usdView.centerY(x: containerView.frame.width - usdView.frame.width - 10)
    }
}

// MARK: - StakeKeyboardRowItem
private final class StakeKeyboardRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let stakes: [[Int64]]
    fileprivate let selectStake: (Int64) -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, stakes: [[Int64]], selectStake: @escaping (Int64) -> Void, viewType: GeneralViewType) {
        self.context = context
        self.stakes = stakes
        self.selectStake = selectStake
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override func viewClass() -> AnyClass {
        return StakeKeyboardRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverChatStakeAmounts
    }

    override var height: CGFloat {
        let rowCount = CGFloat(stakes.count)
        let buttonHeight: CGFloat = 30
        let spacing: CGFloat = 5
        // rows * height + (rows - 1) * spacing + top/bottom padding
        return rowCount * buttonHeight + max(0, rowCount - 1) * spacing + 10
    }
}

// MARK: - StakeKeyboardRowView
private final class StakeKeyboardRowView: GeneralRowView {

    private final class StakeButton: Control {
        private let textView = InteractiveTextView()
        private var stakeValue: Int64 = 0
        var onSelect: ((Int64) -> Void)?

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(textView)
            scaleOnClick = true
            textView.isSelected = false
            textView.userInteractionEnabled = false
            textView.isEventLess = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(stake: Int64, context: any AccountContextProtocol) {
            self.stakeValue = stake
            self.set(background: theme.colors.background.withAlphaComponent(0.6), for: .Normal)
            self.layer?.cornerRadius = 4

            let formattedStake = formatCurrencyAmount(stake, currency: TON).prettyCurrencyNumberUsd
            self.setAccessibilityLabel("\(formattedStake) \(TON)")

            let attr = NSMutableAttributedString()
            attr.append(string: "\(formattedStake) \(clown)", color: theme.colors.accent, font: .medium(.text))
            attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.ton_logo.file, color: theme.colors.accent), for: clown)

            let layout = TextViewLayout(attr)
            layout.measure(width: .greatestFiniteMagnitude)

            textView.set(text: layout, context: context)

            self.removeAllHandlers()
            self.set(handler: { [weak self] _ in
                guard let self = self else { return }
                self.onSelect?(self.stakeValue)
            }, for: .Click)

            needsLayout = true
        }

        override func layout() {
            super.layout()
            textView.center()
        }
    }

    private var buttons: [[StakeButton]] = []

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? StakeKeyboardRowItem else { return }

        // Remove old buttons
        for row in buttons {
            for button in row {
                button.removeFromSuperview()
            }
        }
        buttons.removeAll()

        // Create buttons for each stake
        for row in item.stakes {
            var buttonRow: [StakeButton] = []
            for stake in row {
                let button = StakeButton(frame: NSZeroRect)
                button.update(stake: stake, context: item.context)
                button.onSelect = { [weak item] value in
                    item?.selectStake(value)
                }
                self.addSubview(button)
                buttonRow.append(button)
            }
            buttons.append(buttonRow)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? StakeKeyboardRowItem else { return }

        let insets = item.inset
        let availableWidth = self.frame.width - insets.left - insets.right
        let columns = 3
        let spacing: CGFloat = 5
        let buttonWidth = (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let buttonHeight: CGFloat = 30

        for (rowIndex, row) in buttons.enumerated() {
            for (colIndex, button) in row.enumerated() {
                let x = insets.left + CGFloat(colIndex) * (buttonWidth + spacing)
                let y = 5 + CGFloat(rowIndex) * (buttonHeight + spacing)
                button.frame = NSRect(x: x, y: y, width: buttonWidth, height: buttonHeight)
                button.layer?.cornerRadius = 4
            }
        }
    }
}

public func DiceRollController(context: any AccountContextProtocol, interactions chatInteraction: ChatInteraction) -> InputDataModalController {
    let actionsDisposable = DisposableSet()

    // State management
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)? = nil
    var getController: (() -> InputDataController?)? = nil

    let interactions = TextView_Interactions()

    // Arguments
    let arguments = Arguments(
        context: context,
        dismiss: {
            close?()
        },
        updateStake: { [weak interactions] state in
            let currentState = stateValue.with { $0 }
            let config = currentState.stakeConfig

            // Parse the input amount
            var validatedState = state
            if let doubleValue = Double(state.string), doubleValue > 0 {
                let amount = Int64(doubleValue * 1_000_000_000)

                // Validate min stake
                if let minStake = config.minStakeAmount, amount < minStake {
                    let minFormatted = formatCurrencyAmount(minStake, currency: TON).prettyCurrencyNumberUsd
                    let result = InputDataValidation.fail(.fields([_id_stake_input : .shake]))
                    getController?()?.proccessValidation(result)
                    showModalText(for: context.window, text: strings().diceRollMinStake(minFormatted))
                    // Clamp to min value
                    validatedState = .init(inputText: .init(string: minFormatted), selectionRange: minFormatted.length ..< minFormatted.length)
                }

                // Validate max stake
                if let maxStake = config.maxStakeAmount, amount > maxStake {
                    let maxFormatted = formatCurrencyAmount(maxStake, currency: TON).prettyCurrencyNumberUsd
                    let result = InputDataValidation.fail(.fields([_id_stake_input : .shake]))
                    getController?()?.proccessValidation(result)
                    showModalText(for: context.window, text: strings().diceRollMaxStake(maxFormatted))
                    // Clamp to max value
                    validatedState = .init(inputText: .init(string: maxFormatted), selectionRange: maxFormatted.length ..< maxFormatted.length)
                }
            }

            updateState { current in
                var current = current
                current.stakeInput = validatedState
                return current
            }
            interactions?.update { _ in
                return validatedState
            }
        },
        interactions: interactions
    )

    // Load TON balance
    actionsDisposable.add(context.tonContext.state.startStrict(next: { tonState in
        updateState { current in
            var current = current
            current.tonBalance = tonState?.balance.value
            return current
        }
    }))

    // Load stake configuration from appConfiguration
    let stakeConfig = EmojiGameStakeConfiguration.with(appConfiguration: context.appConfiguration)
    updateState { current in
        var current = current
        current.stakeConfig = stakeConfig
        return current
    }

    // Load dice files
    actionsDisposable.add(context.diceCache.interactiveSymbolData(baseSymbol: "🎲", synchronous: false).startStrict(next: { data in
        let files = data.map { $0.2 }
        updateState { current in
            var current = current
            current.diceFiles = files
            if files.count > 1 {
                current.currentDiceFileIndex = Int.random(in: 1..<files.count)
            }
            return current
        }
    }))

    // Timer to cycle through dice files every 3 seconds
    let diceTimer = SwiftSignalKit.Timer(timeout: 6, repeat: true, completion: {
        updateState { current in
            var current = current
            if current.diceFiles.count > 1 {
                var newIndex = Int.random(in: 1..<current.diceFiles.count)
                while newIndex == current.currentDiceFileIndex && current.diceFiles.count > 2 {
                    newIndex = Int.random(in: 1..<current.diceFiles.count)
                }
                current.currentDiceFileIndex = newIndex
            }
            return current
        }
    }, queue: .mainQueue())
    diceTimer.start()
    actionsDisposable.add(ActionDisposable {
        diceTimer.invalidate()
    })

    let gameInfo = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Configuration.EmojiGame()) |> deliverOnMainQueue
    actionsDisposable.add(gameInfo.startStrict(next: { [weak interactions] emojiGameInfo in
        updateState { current in
            var current = current
            if case let .available(info) = emojiGameInfo {
                current.rolls = Roll.fromParameters(info.parameters)
                current.stakeInput = .init(inputText: .initialize(string: "\(formatCurrencyAmount(info.previousStake, currency: TON).prettyCurrencyNumberUsd )"))
            }
            return current
        }
        let stake = stateValue.with { $0.stakeInput }
        interactions?.update { _ in
            return stake
        }
    }))

    // Reactive signal
    let signal = statePromise.get()
        |> deliverOnPrepareQueue
        |> map { state in
            return InputDataSignalValue(entries: entries(state, arguments: arguments))
        }

    // Create controller
    let controller = InputDataController(
        dataSignal: signal,
        title: "",
        hasDone: false
    )
    controller.analyticsScreen = .chatDiceStake

    getController = { [weak controller] in
        return controller
    }

    controller.validateData = { [weak chatInteraction] _ in
        let state = stateValue.with { $0 }

        // Check if amount is valid (within min/max range)
        if let error = state.stakeError {
            showModalText(for: context.window, text: error)
            return .none
        }

        // Check if we have enough balance
        if let amount = state.amount, let balance = state.tonBalance, balance < amount {
            // Not enough balance, show top-up controller
            ChatNavigationHooks.shared.showAddTonBalance(context, amount - balance, context.window)
            return .none
        }

        // Send the dice media
        chatInteraction?.sendMedias([state.media], ChatTextInputState(), false, nil, false, nil, false, nil, false)
        close?()
        return .none
    }

    // Cleanup
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(
        acceptTitle: strings().diceRollSaveAndRoll,
        accept: { [weak controller] in
            // Handle save and roll action
            controller?.validateInputValues()
        },
        singleButton: true
    )

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
