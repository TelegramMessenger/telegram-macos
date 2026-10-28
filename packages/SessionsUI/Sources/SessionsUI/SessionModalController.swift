import Cocoa
import SwiftSignalKit
import TelegramCore
import TGUIKit
import DateUtils
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import AvatarUI
import LocalAnimations
import ColorPalette
import TelegramIconsTheme
import Postbox

private final class Arguments {
    public let context: any AccountContextProtocol
    public let toggleChats:(Bool)->Void
    public let toggleIncomingCalls: (Bool) -> Void
    public let openLocation: (String) -> Void
    public init(context: any AccountContextProtocol, toggleChats:@escaping(Bool)->Void, toggleIncomingCalls: @escaping(Bool) -> Void, openLocation: @escaping(String) -> Void) {
        self.context = context
        self.toggleChats = toggleChats
        self.toggleIncomingCalls = toggleIncomingCalls
        self.openLocation = openLocation
    }
}

private struct State : Equatable {
    public let session: RecentAccountSession
    public let isGeocoding: Bool
}

private final class SessionDetailRowItem: GeneralInteractedRowItem {
    let valueLayout: TextViewLayout
    let accessoryImage: CGImage?
    let accessoryTooltip: String?
    let accessoryAction: (() -> Void)?
    let accessoryLoading: Bool

    var accessoryInset: CGFloat {
        return accessoryImage.map { $0.systemSize.width + 10 } ?? 0
    }

    var valueWidth: CGFloat {
        return max(1, blockWidth - nameLayout.layoutSize.width - viewType.innerInset.right - inset.left - 10 - accessoryInset)
    }

    init(_ initialSize: NSSize, stableId: AnyHashable, name: String, value: String, viewType: GeneralViewType, accessoryImage: CGImage?, accessoryTooltip: String?, accessoryAction: (() -> Void)?, accessoryLoading: Bool) {
        self.accessoryImage = accessoryImage
        self.accessoryTooltip = accessoryTooltip
        self.accessoryAction = accessoryAction
        self.accessoryLoading = accessoryLoading
        valueLayout = TextViewLayout(.initialize(string: value, color: theme.colors.grayText, font: .normal(.title)), alignment: .right)
        let type: GeneralInteractedType
        if let accessoryImage, accessoryAction == nil {
            type = .imageContext(accessoryImage, value)
        } else {
            type = .context(value)
        }
        super.init(initialSize, stableId: stableId, name: name, type: type, viewType: viewType)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        valueLayout.measure(width: valueWidth)
        return result
    }

    override var height: CGFloat {
        return max(super.height, valueLayout.layoutSize.height + viewType.innerInset.top + viewType.innerInset.bottom)
    }

    override func viewClass() -> AnyClass {
        return SessionDetailRowView.self
    }

    override var accessibilityHelp: String? {
        return accessoryLoading ? strings().voiceOverCommonLoading : accessoryTooltip
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return accessoryAction == nil ? super.accessibilityRole : .group
    }

    override var accessibilityIncludesChildren: Bool {
        return accessoryAction != nil
    }
}

private final class SessionDetailRowView: GeneralInteractedRowView {
    private var accessoryControl: Control?
    private var accessoryProgress: ProgressIndicator?

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? SessionDetailRowItem else {
            return
        }
        if let image = item.accessoryImage {
            let control: Control
            if let current = accessoryControl {
                control = current
            } else {
                control = item.accessoryAction == nil ? OverlayControl() : ImageButton()
                control.set(handler: { control in
                    if control.controlState != .Hover {
                        dismissTooltip(for: control)
                    }
                }, for: .Other)
                if item.accessoryAction != nil {
                    control.set(handler: { [weak self] _ in
                        (self?.item as? SessionDetailRowItem)?.accessoryAction?()
                    }, for: .Click)
                }
                containerView.addSubview(control)
                accessoryControl = control
            }
            (control as? ImageButton)?.set(image: image, for: .Normal)
            control.setFrameSize(NSMakeSize(image.systemSize.width + 8, image.systemSize.height + 8))
            control.appTooltip = item.accessoryLoading ? nil : item.accessoryTooltip
            control.setAccessibilityLabel(item.accessoryTooltip)
            control.isAccessibilityDecorative = item.accessoryAction == nil
            control.isEnabled = !item.accessoryLoading
            control.isHidden = item.accessoryLoading
            if item.accessoryLoading {
                dismissTooltip(for: control)
            }
        } else {
            if let accessoryControl {
                dismissTooltip(for: accessoryControl)
            }
            accessoryControl?.removeFromSuperview()
            accessoryControl = nil
        }
        if item.accessoryLoading {
            let progress: ProgressIndicator
            if let current = accessoryProgress {
                progress = current
            } else {
                progress = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))
                progress.userInteractionEnabled = false
                progress.isAccessibilityDecorative = true
                containerView.addSubview(progress)
                accessoryProgress = progress
            }
            progress.progressColor = theme.colors.accent
        } else {
            accessoryProgress?.removeFromSuperview()
            accessoryProgress = nil
        }
    }

    override func layout() {
        super.layout()
        guard let item = item as? SessionDetailRowItem, let textView = textView else {
            return
        }
        item.valueLayout.measure(width: item.valueWidth)
        textView.update(item.valueLayout)
        textView.centerY(x: containerView.frame.width - item.viewType.innerInset.right - textView.frame.width - item.accessoryInset)
        if let accessoryControl, let image = item.accessoryImage {
            accessoryControl.centerY(x: containerView.frame.width - item.viewType.innerInset.right - image.systemSize.width - 4, addition: -1)
            accessoryProgress?.centerY(x: accessoryControl.frame.midX - 10, addition: -1)
        }
    }
}

private func sessionDetailEntry(sectionId: Int32, index: Int32, identifier: InputDataIdentifier, name: String, value: String, viewType: GeneralViewType, accessoryImage: CGImage? = nil, accessoryTooltip: String? = nil, accessoryAction: (() -> Void)? = nil, accessoryLoading: Bool = false) -> InputDataEntry {
    let type: GeneralInteractedType = accessoryLoading ? .loading : accessoryImage.map { .imageContext($0, value) } ?? .context(value)
    let data = InputDataGeneralData(name: name, color: theme.colors.text, type: type, viewType: viewType, description: accessoryTooltip)
    return .custom(sectionId: sectionId, index: index, value: .none, identifier: identifier, equatable: InputDataEquatable(data), comparable: nil, item: { initialSize, stableId in
        return SessionDetailRowItem(initialSize, stableId: stableId, name: name, value: value, viewType: viewType, accessoryImage: accessoryImage, accessoryTooltip: accessoryTooltip, accessoryAction: accessoryAction, accessoryLoading: accessoryLoading)
    })
}

private func sessionVerifiedIcon() -> CGImage {
    return generateImage(NSMakeSize(16, 16), contextGenerator: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        context.setFillColor(theme.colors.underSelectedColor.cgColor)
        context.fillEllipse(in: NSMakeRect(4, 4, size.width - 8, size.height - 8))
        context.draw(TelegramThemeHooks.shared.image(.iconVerifyDialog).precomposed(theme.colors.accent), in: CGRect(origin: .zero, size: size))
    })!
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
//
    let icon = iconForSession(state.session)
    if let sticker = icon.1 {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: nil, comparable: nil, item: { initialSize, stableId in
            
            let attr: NSMutableAttributedString = .init()
            
            _ = attr.append(string: state.session.deviceModel, color: theme.colors.text, font: .medium(.title))
            _ = attr.append(string: "\n", color: theme.colors.text, font: .medium(.title))
            _ = attr.append(string: DateUtils.string(forLastSeen: state.session.activityDate), color: theme.colors.listGrayText, font: .normal(.text))

            return SessionsHooks.shared.makeStickerHeaderItem(initialSize, stableId, arguments.context, sticker, attr, NSMakeSize(60, 60), icon.2, icon.3)
        }))
        index += 1

    }
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().sessionPreviewDeviceHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let isOfficial = state.session.flags.contains(.isOfficial)
    entries.append(sessionDetailEntry(sectionId: sectionId, index: index, identifier: .init("application"), name: strings().sessionPreviewApp, value: state.session.appName, viewType: .firstItem, accessoryImage: isOfficial ? sessionVerifiedIcon() : nil, accessoryTooltip: isOfficial ? strings().sessionPreviewOfficialAppTooltip : nil))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("version"), data: InputDataGeneralData(name: strings().sessionPreviewVersion, color: theme.colors.text, type: .context(state.session.appVersion), viewType: .innerItem, enabled: true)))
    index += 1

    let system = [state.session.platform, state.session.systemVersion].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("os"), data: InputDataGeneralData(name: strings().sessionPreviewOS, color: theme.colors.text, type: .context(system), viewType: .lastItem, enabled: true)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().sessionPreviewConnectionHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let ip = state.session.ip.trimmingCharacters(in: .whitespacesAndNewlines)
    let location = [state.session.country, state.session.region].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")

    if !ip.isEmpty {
        entries.append(sessionDetailEntry(sectionId: sectionId, index: index, identifier: .init("ip"), name: strings().sessionPreviewIp, value: ip, viewType: .firstItem))
        index += 1
    }

    if !location.isEmpty {
        entries.append(sessionDetailEntry(sectionId: sectionId, index: index, identifier: .init("location"), name: strings().sessionPreviewLocation, value: location, viewType: ip.isEmpty ? .firstItem : .innerItem, accessoryImage: theme.icons.chatAttachLocation, accessoryTooltip: strings().locationPreviewTitle, accessoryAction: {
            arguments.openLocation(location)
        }, accessoryLoading: state.isGeocoding))
        index += 1
    }

    let dateFormatter = DateFormatter()
    dateFormatter.locale = .current
    dateFormatter.timeZone = .current
    dateFormatter.dateStyle = .medium
    dateFormatter.timeStyle = .medium
    dateFormatter.doesRelativeDateFormatting = false

    entries.append(sessionDetailEntry(sectionId: sectionId, index: index, identifier: .init("first_signed_at"), name: strings().sessionPreviewFirstSignedAt, value: dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(state.session.creationDate))), viewType: ip.isEmpty && location.isEmpty ? .firstItem : .innerItem))
    index += 1

    entries.append(sessionDetailEntry(sectionId: sectionId, index: index, identifier: .init("last_signed_at"), name: strings().sessionPreviewLastSignedAt, value: dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(state.session.activityDate))), viewType: .lastItem))
    index += 1

    if !location.isEmpty {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().sessionPreviewIpDesc), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().sessionPreviewAcceptHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1


    
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("secret"), data: InputDataGeneralData(name: strings().sessionPreviewAcceptSecret, color: theme.colors.text, type: .switchable(state.session.flags.contains(.acceptsSecretChats)), viewType: .firstItem, enabled: true, action: {
        arguments.toggleChats(!state.session.flags.contains(.acceptsSecretChats))
    })))
    index += 1
    
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("calls"), data: InputDataGeneralData(name: strings().sessionPreviewAcceptCalls, color: theme.colors.text, type: .switchable(state.session.flags.contains(.acceptsIncomingCalls)), viewType: .lastItem, enabled: true, action: {
        arguments.toggleIncomingCalls(!state.session.flags.contains(.acceptsIncomingCalls))
    })))
    index += 1
    
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func SessionModalController(context: any AccountContextProtocol, session: RecentAccountSession) -> InputDataModalController {

    var close:(()->Void)? = nil
    var isUpdating = false
    let locationDisposable = MetaDisposable()
    let geocodingPromise = ValuePromise(false, ignoreRepeated: true)
    var isGeocoding = false

    let updateSession: (Signal<Never, UpdateSessionError>) -> Void = { signal in
        guard !isUpdating else {
            return
        }
        isUpdating = true
        var finished = false
        let signal = signal |> afterDisposed {
            Queue.mainQueue().async {
                if !finished {
                    isUpdating = false
                    context.activeSessionsContext.loadMore()
                }
            }
        }
        _ = showModalProgress(signal: signal, for: context.window).start(error: { _ in
            finished = true
            isUpdating = false
            context.activeSessionsContext.loadMore()
            alert(for: context.window, info: strings().unknownError)
        }, completed: {
            finished = true
            isUpdating = false
        })
    }

    let arguments = Arguments(context: context, toggleChats: { updated in
        updateSession(context.activeSessionsContext.updateSessionAcceptsSecretChats(session, accepts: updated))
    }, toggleIncomingCalls: { updated in
        updateSession(context.activeSessionsContext.updateSessionAcceptsIncomingCalls(session, accepts: updated))
    }, openLocation: { location in
        guard !isGeocoding else {
            return
        }
        isGeocoding = true
        geocodingPromise.set(true)
        let signal = FeatureNavigationHooks.shared.makeLocationPreviewController(context, location)
        |> deliverOnMainQueue
        |> afterDisposed {
            Queue.mainQueue().async {
                isGeocoding = false
                geocodingPromise.set(false)
            }
        }
        locationDisposable.set(signal.start(next: { controller in
            if let controller {
                showModal(with: controller, for: context.window)
            } else {
                alert(for: context.window, info: strings().sessionPreviewLocationError)
            }
        }))
    })
    
    let signal = combineLatest(context.activeSessionsContext.state, geocodingPromise.get())
    |> map { state, isGeocoding in
        return State(session: state.sessions.first(where: { $0.hash == session.hash }) ?? session, isGeocoding: isGeocoding)
    }
    |> distinctUntilChanged
    |> deliverOnPrepareQueue
    |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().sessionPreviewTitle)
    controller.onDeinit = {
        locationDisposable.dispose()
    }
    
    let modalInteractions: ModalInteractions
    if session.isCurrent {
        modalInteractions = ModalInteractions(acceptTitle: strings().modalOK, accept: {
            close?()
        }, drawBorder: false, height: 50, singleButton: true)
    } else {
        modalInteractions = ModalInteractions(acceptTitle: strings().sessionPreviewTerminateSession, accept: {
            verifyAlert_button(for: context.window, information: strings().recentSessionsConfirmRevoke, successHandler: { _ in
                _ = showModalProgress(signal: context.activeSessionsContext.remove(hash: session.hash), for: context.window).start(error: { error in
                    let text: String
                    switch error {
                    case .freshReset:
                        text = strings().recentSessionsErrorFreshReset
                    case .generic:
                        text = strings().unknownError
                    }
                    alert(for: context.window, info: text)
                }, completed: {
                    close?()
                })
            })
        }, singleButton: true)
    }
    
    DispatchQueue.main.async {
        modalInteractions.updateDone { button in
            if session.isCurrent {
                button.set(background: theme.colors.accent, for: .Normal)
            } else {
                button.set(background: theme.colors.redUI, for: .Normal)
            }
        }
    }
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(440, 300))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    /*

     */
    
    return modalController
    
}


/*
 
 */



