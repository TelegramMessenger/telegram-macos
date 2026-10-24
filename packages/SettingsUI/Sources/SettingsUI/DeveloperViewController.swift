import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import ApiCredentials
import MtProtoKit
import Postbox
import ThemeSettings
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
import FilePanels


private final class Arguments {
    public let context: any AccountContextProtocol
    public let importColors: () -> Void
    public let exportColors: () -> Void
    public let toggleLogs: (Bool) -> Void
    public let navigateToLogs: () -> Void
    public let addAccount: () -> Void
    public let toggleMenu: (Bool) -> Void
    public let toggleAnimatedInputEmoji: () -> Void
    public let toggleNativeGraphicContext: () -> Void
    public let toggleDebugWebApp: () -> Void
    public let toggleNetwork: () -> Void
    public let selectNetworkEngine: (NetworkEngineKind) -> Void
    public let toggleDownloads: () -> Void
    public let toggleCanViewPeerId: () -> Void
    public let crash: () -> Void
    public let memoryReport: () -> Void
    public let toggleAccessibilityTree: () -> Void
    public let accessibilityAudit: () -> Void
    public let toggleForceRLottieBackend: () -> Void
    public init(context: any AccountContextProtocol,
         importColors: @escaping () -> Void,
         exportColors: @escaping () -> Void,
         toggleLogs: @escaping (Bool) -> Void,
         navigateToLogs: @escaping () -> Void,
         addAccount: @escaping () -> Void,
         toggleMenu: @escaping (Bool) -> Void,
         toggleAnimatedInputEmoji: @escaping () -> Void,
         toggleNativeGraphicContext: @escaping () -> Void,
         toggleDebugWebApp: @escaping () -> Void,
         toggleNetwork: @escaping () -> Void,
         selectNetworkEngine: @escaping (NetworkEngineKind) -> Void,
         toggleDownloads: @escaping () -> Void,
         toggleCanViewPeerId: @escaping () -> Void,
         crash: @escaping () -> Void,
         memoryReport: @escaping () -> Void,
         toggleAccessibilityTree: @escaping () -> Void,
         accessibilityAudit: @escaping () -> Void,
         toggleForceRLottieBackend: @escaping () -> Void) {
        self.context = context
        self.importColors = importColors
        self.exportColors = exportColors
        self.toggleLogs = toggleLogs
        self.navigateToLogs = navigateToLogs
        self.addAccount = addAccount
        self.toggleMenu = toggleMenu
        self.toggleAnimatedInputEmoji = toggleAnimatedInputEmoji
        self.toggleNativeGraphicContext = toggleNativeGraphicContext
        self.toggleDebugWebApp = toggleDebugWebApp
        self.toggleNetwork = toggleNetwork
        self.selectNetworkEngine = selectNetworkEngine
        self.toggleDownloads = toggleDownloads
        self.toggleCanViewPeerId = toggleCanViewPeerId
        self.crash = crash
        self.memoryReport = memoryReport
        self.toggleAccessibilityTree = toggleAccessibilityTree
        self.accessibilityAudit = accessibilityAudit
        self.toggleForceRLottieBackend = toggleForceRLottieBackend
    }
}

private struct State: Equatable {
    public var logToFile: Bool = false
    public var legacyMenu: Bool = false
    public var animateInputEmoji: Bool = false
    public var useNativeGraphicContext: Bool = false
    public var debugWebApp: Bool = false
    public var useNetworkFramework: Bool = false
    public var networkEngine: NetworkEngineKind = .mtProtoKit
    public var activeNetworkEngine: NetworkEngineKind = .mtProtoKit
    public var useExperimentalDownload: Bool = false
    public var canViewPeerId: Bool = false
    public var accessibilityTree: Bool = true
    public var forceRLottieBackend: Bool = false
}

private let _id_add_account = InputDataIdentifier("_id_add_account")
private let _id_import_colors = InputDataIdentifier("_id_import_colors")
private let _id_export_colors = InputDataIdentifier("_id_export_colors")
private let _id_toggle_logs = InputDataIdentifier("_id_toggle_logs")
private let _id_open_logs = InputDataIdentifier("_id_open_logs")
private let _id_toggle_menu = InputDataIdentifier("_id_toggle_menu")
private let _id_animate_input_emoji = InputDataIdentifier("_id_animate_input_emoji")
private let _id_native_graphic_context = InputDataIdentifier("_id_native_graphic_context")
private let _id_debug_web_app = InputDataIdentifier("_id_debug_web_app")
private let _id_network = InputDataIdentifier("_id_network")
private let _id_network_engine = InputDataIdentifier("_id_network_engine")
private let _id_downloads = InputDataIdentifier("_id_downloads")
private let _id_show_peer_id = InputDataIdentifier("_id_show_peer_id")
private let _id_crash = InputDataIdentifier("_id_crash")
private let _id_memory_report = InputDataIdentifier("_id_memory_report")
private let _id_accessibility_tree = InputDataIdentifier("_id_accessibility_tree")
private let _id_accessibility_audit = InputDataIdentifier("_id_accessibility_audit")
private let _id_force_rlottie = InputDataIdentifier("_id_force_rlottie")


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().developerAccounts), data: .init(viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add_account, data: InputDataGeneralData(name: strings().editAccountAddAccount, color: theme.colors.text, type: .next, viewType: .singleItem, action: arguments.addAccount)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().developerLogs), data: .init(viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_toggle_logs, data: InputDataGeneralData(name: strings().developerEnableLogs, color: theme.colors.text, type: .switchable(state.logToFile), viewType: .firstItem, action: {
        arguments.toggleLogs(!state.logToFile)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_open_logs, data: InputDataGeneralData(name: strings().developerOpenLogs, color: theme.colors.text, type: .next, viewType: .lastItem, action: arguments.navigateToLogs)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().generalSettingsInterfaceHeader), data: .init(viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_toggle_menu, data: InputDataGeneralData(name: strings().developerNativeContextMenu, color: theme.colors.text, type: .switchable(state.legacyMenu), viewType: .firstItem, action: {
        arguments.toggleMenu(!state.legacyMenu)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_native_graphic_context, data: InputDataGeneralData(name: strings().developerNativeGraphicContext, color: theme.colors.text, type: .switchable(state.useNativeGraphicContext), viewType: .innerItem, action: arguments.toggleNativeGraphicContext)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_show_peer_id, data: InputDataGeneralData(name: strings().developerShowPeerId, color: theme.colors.text, type: .switchable(state.canViewPeerId), viewType: .lastItem, action: arguments.toggleCanViewPeerId)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().developerAnimations), data: .init(viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_animate_input_emoji, data: InputDataGeneralData(name: strings().developerAnimateEmojiInput, color: theme.colors.text, type: .switchable(state.animateInputEmoji), viewType: .firstItem, action: arguments.toggleAnimatedInputEmoji)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_force_rlottie, data: InputDataGeneralData(name: strings().developerForceRLottie, color: theme.colors.text, type: .switchable(state.forceRLottieBackend), viewType: .lastItem, action: arguments.toggleForceRLottieBackend)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().developerNetwork), data: .init(viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_network, data: InputDataGeneralData(name: strings().developerExperimentalNetwork, color: theme.colors.text, type: .switchable(state.useNetworkFramework), viewType: .firstItem, action: arguments.toggleNetwork)))
    index += 1

    let networkEngineTitle: (NetworkEngineKind) -> String = { engine in
        switch engine {
        case .mtProtoKit:
            return "MtProtoKit"
        case .rust:
            return "Rust"
        }
    }
    var networkEngineValue = networkEngineTitle(state.networkEngine)
    if state.networkEngine != state.activeNetworkEngine {
        networkEngineValue = strings().developerNetworkEngineActive(networkEngineValue, networkEngineTitle(state.activeNetworkEngine))
    }
    let networkEngineItems: [ContextMenuItem] = [
        ContextMenuItem("MtProtoKit", handler: {
            arguments.selectNetworkEngine(.mtProtoKit)
        }),
        ContextMenuItem(strings().developerNetworkEngineRustRestartRequired, handler: {
            arguments.selectNetworkEngine(.rust)
        })
    ]
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_network_engine, data: InputDataGeneralData(name: strings().developerNetworkEngine, color: theme.colors.text, type: .contextSelector(networkEngineValue, networkEngineItems), viewType: .innerItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_downloads, data: InputDataGeneralData(name: strings().developerExperimentalDownloads, color: theme.colors.text, type: .switchable(state.useExperimentalDownload), viewType: .lastItem, action: arguments.toggleDownloads)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().developerDebugging), data: .init(viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_debug_web_app, data: InputDataGeneralData(name: strings().developerDebugWebApp, color: theme.colors.text, type: .switchable(state.debugWebApp), viewType: .firstItem, action: arguments.toggleDebugWebApp)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_memory_report, data: InputDataGeneralData(name: strings().developerMemoryReportToLog, color: theme.colors.text, type: .none, viewType: .innerItem, action: arguments.memoryReport)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_accessibility_tree, data: InputDataGeneralData(name: strings().developerAccessibilityTree, color: theme.colors.text, type: .switchable(state.accessibilityTree), viewType: .innerItem, action: arguments.toggleAccessibilityTree)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_accessibility_audit, data: InputDataGeneralData(name: strings().developerAccessibilityAuditToClipboard, color: theme.colors.text, type: .none, viewType: .innerItem, action: arguments.accessibilityAudit)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_crash, data: InputDataGeneralData(name: strings().developerCrash, color: theme.colors.redUI, type: .none, viewType: .lastItem, action: arguments.crash)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func DeveloperViewController(context: any AccountContextProtocol) -> InputDataController {

    let actionsDisposable = DisposableSet()

    let initialState = State(
        logToFile: false,
        legacyMenu: System.legacyMenu,
        animateInputEmoji: FastSettings.animateInputEmoji,
        useNativeGraphicContext: FastSettings.useNativeGraphicContext,
        debugWebApp: FastSettings.debugWebApp,
        useNetworkFramework: false,
        networkEngine: .mtProtoKit,
        activeNetworkEngine: context.account.network.engineKind,
        useExperimentalDownload: false,
        canViewPeerId: FastSettings.canViewPeerId,
        accessibilityTree: FastSettings.accessibilityTreeEnabled,
        forceRLottieBackend: DeveloperHooks.shared.forceRLottieBackend()
    )

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let arguments = Arguments(context: context, importColors: {
        filePanel(with: ["palette"], allowMultiple: false, for: context.window, completion: { list in
            if let path = list?.first {
                if let palette = importPalette(path) {
                    let palettesDir = ApiEnvironment.containerURL!.appendingPathComponent("Palettes").path
                    try? FileManager.default.createDirectory(atPath: palettesDir, withIntermediateDirectories: true, attributes: nil)
                    try? FileManager.default.removeItem(atPath: palettesDir + "/" + path.nsstring.lastPathComponent)
                    try? FileManager.default.copyItem(atPath: path, toPath: palettesDir + "/" + path.nsstring.lastPathComponent)
                    _ = updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
                        return settings.withUpdatedPalette(palette).withUpdatedCloudTheme(nil)
                    }).start()
                } else {
                    alert(for: context.window, info: strings().developerPaletteParsingError)
                }
            }
        })
    }, exportColors: {
        exportPalette(palette: theme.colors)
    }, toggleLogs: { enabled in
        MTLogSetEnabled(enabled)
        _ = updateLoggingSettings(accountManager: context.sharedContext.accountManager, {
            $0.withUpdatedLogToFile(enabled)
        }).start()
        Logger.shared.logToConsole = false
        Logger.shared.logToFile = enabled
    }, navigateToLogs: {
        NSWorkspace.shared.activateFileViewerSelecting([ApiEnvironment.containerURL!.appendingPathComponent("logs")])
    }, addAccount: {
        verifyAlert(for: context.window, header: strings().editAccountAddAccount, information: nil, ok: strings().navigationAdd, option: strings().developerTestEnvironment, optionIsSelected: false, successHandler: { result in
            context.sharedContext.beginNewAuth(testingEnvironment: result == .thrid)
        })
    }, toggleMenu: { value in
        _ = updateThemeInteractivetly(accountManager: context.sharedContext.accountManager, f: { settings in
            return settings.withUpdatedLegacyMenu(value)
        }).start()
        updateState { current in
            var current = current
            current.legacyMenu = value
            return current
        }
    }, toggleAnimatedInputEmoji: {
        FastSettings.toggleAnimateInputEmoji()
        updateState { current in
            var current = current
            current.animateInputEmoji = FastSettings.animateInputEmoji
            return current
        }
    }, toggleNativeGraphicContext: {
        FastSettings.toggleNativeGraphicContext()
        DeveloperHooks.shared.updateGraphicContext()
        updateState { current in
            var current = current
            current.useNativeGraphicContext = FastSettings.useNativeGraphicContext
            return current
        }
    }, toggleDebugWebApp: {
        FastSettings.toggleDebugWebApp()
        updateState { current in
            var current = current
            current.debugWebApp = FastSettings.debugWebApp
            return current
        }
    }, toggleNetwork: {
        _ = updateNetworkSettingsInteractively(postbox: context.account.postbox, network: context.account.network, { current in
            var current = current
            if let value = current.useNetworkFramework {
                current.useNetworkFramework = !value
            } else {
                current.useNetworkFramework = true
            }
            return current
        }).start()
    }, selectNetworkEngine: { engine in
        if stateValue.with({ $0.networkEngine }) == engine {
            return
        }
        _ = updateNetworkEngineSettings(accountManager: context.sharedContext.accountManager, { current in
            var current = current
            current.engine = engine
            return current
        }).start()
        let network = context.account.network
        if engine != network.engineKind {
            if network.switchEngine(to: engine, reason: "developer settings") {
                updateState { current in
                    var current = current
                    current.activeNetworkEngine = network.engineKind
                    return current
                }
            } else if network.isRustEngineDisabled {
                alert(for: context.window, header: strings().developerNetworkEngine, info: strings().developerNetworkEngineRustDisabled)
            } else {
                verifyAlert(for: context.window, header: strings().developerNetworkEngine, information: strings().developerNetworkEngineRestart, ok: strings().commonRestart, successHandler: { _ in
                    restartApp()
                })
            }
        }
    }, toggleDownloads: {
        _ = updateNetworkSettingsInteractively(postbox: context.account.postbox, network: context.account.network, { current in
            var current = current
            if let value = current.useExperimentalDownload {
                current.useExperimentalDownload = !value
            } else {
                current.useExperimentalDownload = true
            }
            return current
        }).start()
    }, toggleCanViewPeerId: {
        FastSettings.canViewPeerId = !FastSettings.canViewPeerId
        updateState { current in
            var current = current
            current.canViewPeerId = FastSettings.canViewPeerId
            return current
        }
    }, crash: {
        var array: [Int] = []
        array[1] = 0
    }, memoryReport: {
        let report = layerMemoryReport()
        Logger.shared.log("Memory", report)
        alert(for: context.window, header: strings().developerMemoryReport, info: report.split(separator: "\n").prefix(18).joined(separator: "\n"))
    }, toggleAccessibilityTree: {
        FastSettings.accessibilityTreeEnabled = !FastSettings.accessibilityTreeEnabled
        TGUIKitAccessibility.isEnabled = FastSettings.accessibilityTreeEffective
        updateState { current in
            var current = current
            current.accessibilityTree = FastSettings.accessibilityTreeEnabled
            return current
        }
    }, accessibilityAudit: {
        let windows = NSApp.windows.filter { $0.isVisible }
        var lines: [String] = []
        for window in windows {
            for issue in AccessibilityAudit.audit(window) {
                lines.append("[\(window.title.isEmpty ? String(describing: type(of: window)) : window.title)] \(issue)")
            }
        }
        let report = lines.isEmpty ? strings().developerAccessibilityAuditNoIssuesOther(windows.count) : lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        Logger.shared.log("Accessibility", report)
        alert(for: context.window, header: strings().developerAccessibilityAudit, info: lines.isEmpty ? report : strings().developerAccessibilityAuditCopiedOther(lines.count) + "\n\n" + lines.prefix(12).joined(separator: "\n"))
    }, toggleForceRLottieBackend: {
        DeveloperHooks.shared.toggleForceRLottieBackend()
        updateState { current in
            var current = current
            current.forceRLottieBackend = DeveloperHooks.shared.forceRLottieBackend()
            return current
        }
    })

    let networkSignal = context.account.postbox.preferencesView(keys: [PreferencesKeys.networkSettings]) |> map { view -> NetworkSettings in
        return view.values[PreferencesKeys.networkSettings]?.get(NetworkSettings.self) ?? .defaultSettings
    }

    actionsDisposable.add(combineLatest(queue: .mainQueue(),
        context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.loggingSettings, SharedDataKeys.networkEngineSettings]),
        networkSignal
    ).start(next: { sharedData, networkSettings in
        let logging = sharedData.entries[SharedDataKeys.loggingSettings]?.get(LoggingSettings.self) ?? LoggingSettings.defaultSettings
        let networkEngine = sharedData.entries[SharedDataKeys.networkEngineSettings]?.get(NetworkEngineSettings.self) ?? NetworkEngineSettings.defaultSettings
        updateState { current in
            var current = current
            current.logToFile = logging.logToFile
            current.useNetworkFramework = networkSettings.useNetworkFramework ?? false
            current.networkEngine = networkEngine.engine
            current.useExperimentalDownload = networkSettings.useExperimentalDownload ?? false
            return current
        }
    }))

    let signal = combineLatest(statePromise.get(), languageSignal) |> deliverOnPrepareQueue |> map { state, _ in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().developerTitle, hasDone: false)

    controller.getTitle = { strings().developerTitle }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
}


private func layerMemoryReport() -> String {
    struct Entry {
        var count: Int = 0
        var bytes: Int = 0
    }
    var byOwner: [String: Entry] = [:]
    var layerCount = 0
    var totalBytes = 0

    func visit(_ layer: CALayer) {
        layerCount += 1
        if let contents = layer.contents {
            let object = contents as AnyObject
            let bytes: Int
            let kind: String
            if CFGetTypeID(object) == CGImage.typeID {
                let image = object as! CGImage
                bytes = image.bytesPerRow * image.height
                kind = "image"
            } else {
                let scale = layer.contentsScale
                bytes = Int(layer.bounds.width * scale) * Int(layer.bounds.height * scale) * 4
                kind = String(describing: type(of: object))
            }
            if bytes > 0 {
                let owner = (layer.delegate as? NSView).map { String(describing: type(of: $0)) } ?? String(describing: type(of: layer))
                let key = "\(owner) <\(kind)>"
                var entry = byOwner[key] ?? Entry()
                entry.count += 1
                entry.bytes += bytes
                byOwner[key] = entry
                totalBytes += bytes
            }
        }
        for sublayer in layer.sublayers ?? [] {
            visit(sublayer)
        }
    }
    for window in NSApp.windows {
        if let layer = window.contentView?.layer {
            visit(layer)
        }
    }

    var lines: [String] = []
    var vmInfo = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
        }
    }
    if vmResult == KERN_SUCCESS {
        lines.append(String(format: "footprint %.1f MB", Double(vmInfo.phys_footprint) / 1048576))
    }
    var mallocStats = malloc_statistics_t()
    malloc_zone_statistics(nil, &mallocStats)
    lines.append(String(format: "malloc in use %.1f MB, allocated %.1f MB", Double(mallocStats.size_in_use) / 1048576, Double(mallocStats.size_allocated) / 1048576))
    lines.append(String(format: "layer contents %.1f MB in %d layers", Double(totalBytes) / 1048576, layerCount))
    for (key, entry) in byOwner.sorted(by: { $0.value.bytes > $1.value.bytes }).prefix(40) {
        lines.append(String(format: "%7.2f MB x%-4d %@", Double(entry.bytes) / 1048576, entry.count, key))
    }
    return lines.joined(separator: "\n")
}
