
enum AccountConnectedBotError { case generic, server(String) }

enum SaveValidation {
    enum Failure {
        case doSomething((@escaping (SaveValidation) -> Void) -> Void)
        case alert(String)
    }
    enum Success { case navigationBack }
    case none, fail(Failure), success(Success)
}

final class SaveNavigation {
    weak var controller: SaveController?
}

final class SaveController {
    var navigationController: SaveNavigation?
    var validateData: (Int) -> SaveValidation = { _ in .none }
    var onDeinit: () -> Void = {}
    var completions = 0
    var alerts: [String] = []

    func save() {
        if case let .fail(.doSomething(action)) = validateData(0) {
            action { [weak self] result in
                self?.completions += 1
                if case let .fail(.alert(text)) = result {
                    self?.alerts.append(text)
                }
            }
        }
    }

    deinit { onDeinit() }
}

final class PendingSave<Value> {
    var subscriber: Subscriber<Value, AccountConnectedBotError>?
    var disposed = false
    var started = false
    var signal: Signal<Value, AccountConnectedBotError> {
        Signal { subscriber in
            self.started = true
            self.subscriber = subscriber
            return ActionDisposable { self.disposed = true }
        }
    }
    func succeed(_ value: Value) {
        subscriber?.putNext(value)
        subscriber?.putCompletion()
    }
    func fail() { subscriber?.putError(.server("TEST_ERROR")) }
}

final class SaveAccountData {
    let write = PendingSave<Bool>()
    let readback = PendingSave<TelegramAccountConnectedBot?>()
    var cachedBot: TelegramAccountConnectedBot?

    func updateAccountConnectedBot(bot: TelegramAccountConnectedBot?) -> Signal<TelegramAccountConnectedBot?, AccountConnectedBotError> {
        write.signal
        |> mapToSignal { _ in self.readback.signal }
        |> map { bot in
            self.cachedBot = bot
            return bot
        }
    }
}

final class SaveEngine { let accountData = SaveAccountData() }
final class SaveWindow { var toasts: [String] = [] }
final class SaveContext {
    let engine = SaveEngine()
    let window = SaveWindow()
    var reloads = 0
}

func showModalText(for window: SaveWindow, text: String) { window.toasts.append(text) }

final class SaveScreen {
    let context = SaveContext()
    let editor = PermissionEditor()
    let navigation = SaveNavigation()
    var controller: SaveController?

    init() {
        let controller = SaveController()
        self.controller = controller
        controller.navigationController = navigation
        navigation.controller = controller
        let context = self.context
        let stateValue = editor
        let actionsDisposable = DisposableSet()
        let updateState: ((State) -> State) -> Void = { stateValue.state = $0(stateValue.state) }
        func loadBot() { context.reloads += 1 }
        func resolveBot(_ bot: TelegramAccountConnectedBot?) -> Signal<(TelegramAccountConnectedBot?, EnginePeer?), NoError> {
            .single((bot, bot.map { EnginePeer(id: $0.id) }))
        }
        func applyBot(_ bot: TelegramAccountConnectedBot?, peer: EnginePeer?) { stateValue.restore(bot) }
        __VALIDATE_DATA__
        __ON_DEINIT__
        editor.restore(TelegramAccountConnectedBot(
            id: PeerId(namespace: 0, id: ._internalFromInt64Value(2)),
            recipients: .init(categories: [], additionalPeers: [], excludePeers: [], exclude: true),
            rights: [.reply]
        ))
        editor.toggle("view")
    }
}

final class BusinessBotSaveTests: XCTestCase {
    func drainMainQueue() {
        let drained = expectation(description: "Main queue callbacks")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }

    func testClosingBeforeWriteResponseStillReadsBackAndCaches() {
        let screen = SaveScreen()
        let requested = screen.editor.state.mapped
        weak var controller = screen.controller
        screen.controller?.save()
        screen.controller = nil
        XCTAssertNil(controller)
        let data = screen.context.engine.accountData
        XCTAssertFalse(data.write.disposed)
        data.write.succeed(true)
        XCTAssertTrue(data.readback.started)
        data.readback.succeed(requested)
        drainMainQueue()
        XCTAssertEqual(data.cachedBot, requested)
        XCTAssertTrue(screen.context.window.toasts.isEmpty)
    }

    func testClosingDuringReadbackStillCachesServerState() {
        let screen = SaveScreen()
        let requested = screen.editor.state.mapped
        screen.controller?.save()
        let data = screen.context.engine.accountData
        data.write.succeed(true)
        screen.controller = nil
        XCTAssertFalse(data.readback.disposed)
        data.readback.succeed(requested)
        drainMainQueue()
        XCTAssertEqual(data.cachedBot, requested)
        XCTAssertTrue(screen.context.window.toasts.isEmpty)
    }

    func testVisibleScreenCompletesAndShowsSuccess() {
        let screen = SaveScreen()
        let requested = screen.editor.state.mapped
        screen.controller?.save()
        screen.context.engine.accountData.write.succeed(true)
        screen.context.engine.accountData.readback.succeed(requested)
        drainMainQueue()
        XCTAssertEqual(screen.controller?.completions, 1)
        XCTAssertEqual(screen.context.window.toasts.count, 1)
        XCTAssertFalse(screen.editor.state.isSaving)
    }

    func testServerRefusalRestoresRightsWithoutSuccessToast() {
        let screen = SaveScreen()
        let previous = screen.editor.state.initialBot
        screen.controller?.save()
        screen.context.engine.accountData.write.succeed(true)
        screen.context.engine.accountData.readback.succeed(previous)
        drainMainQueue()
        XCTAssertEqual(screen.editor.state.mapped?.rights, previous?.rights)
        XCTAssertTrue(screen.context.window.toasts.isEmpty)
        XCTAssertEqual(screen.controller?.completions, 1)
    }

    func testHiddenRetainedScreenDoesNotNavigateAnotherScreenBack() {
        let screen = SaveScreen()
        let requested = screen.editor.state.mapped
        screen.controller?.save()
        screen.navigation.controller = nil
        screen.context.engine.accountData.write.succeed(true)
        screen.context.engine.accountData.readback.succeed(requested)
        drainMainQueue()
        XCTAssertEqual(screen.controller?.completions, 0)
        XCTAssertTrue(screen.context.window.toasts.isEmpty)
        XCTAssertFalse(screen.editor.state.isSaving)
    }

    func testErrorAfterClosingDoesNotReloadOrShowFeedback() {
        let screen = SaveScreen()
        screen.controller?.save()
        screen.controller = nil
        screen.context.engine.accountData.write.fail()
        drainMainQueue()
        XCTAssertEqual(screen.context.reloads, 0)
        XCTAssertTrue(screen.context.window.toasts.isEmpty)
    }

    func testVisibleScreenStillShowsErrors() {
        let screen = SaveScreen()
        screen.controller?.save()
        screen.context.engine.accountData.write.fail()
        drainMainQueue()
        XCTAssertEqual(screen.context.reloads, 1)
        XCTAssertEqual(screen.controller?.alerts, ["TEST_ERROR"])
        XCTAssertFalse(screen.editor.state.isSaving)
    }
}
