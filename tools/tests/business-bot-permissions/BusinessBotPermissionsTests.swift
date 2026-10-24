import XCTest

__RIGHTS__

struct PeerId: Hashable {
    struct Namespace: Hashable {
        var value: Int32
        func _internalGetInt32Value() -> Int32 { value }
    }
    struct Id: Hashable {
        var value: Int64
        static func _internalFromInt64Value(_ value: Int64) -> Id { Id(value: value) }
    }
    var namespace: Namespace
    var id: Id
    init(namespace: Int32, id: Id) {
        self.namespace = Namespace(value: namespace)
        self.id = id
    }
}

struct EnginePeer: Equatable { var id: PeerId }

struct ChatListFilterPeerCategories: OptionSet {
    var rawValue: Int32
    static let Namespace: Int32 = 100
    static let contacts = Self(rawValue: 1)
    static let nonContacts = Self(rawValue: 2)
    static let newChats = Self(rawValue: 4)
    static let existingChats = Self(rawValue: 8)
}

struct TelegramFilterCategory {
    var category: ChatListFilterPeerCategories
    var id: PeerId { PeerId(namespace: ChatListFilterPeerCategories.Namespace, id: ._internalFromInt64Value(Int64(category.rawValue))) }
}

struct TelegramBusinessRecipients: Equatable {
    typealias Categories = ChatListFilterPeerCategories
    var categories: Categories
    var additionalPeers: Set<PeerId>
    var excludePeers: Set<PeerId>
    var exclude: Bool
}

struct TelegramAccountConnectedBot: Equatable {
    var id: PeerId
    var recipients: TelegramBusinessRecipients
    var rights: TelegramBusinessBotRights
    var device: String? = nil
    var date: Int32? = nil
    var location: String? = nil
}

__STATE__

__SEARCH__

@dynamicMemberLookup
struct TestStrings {
    subscript(dynamicMember name: String) -> String { name }
}

func strings() -> TestStrings { TestStrings() }

__MAKE_PERMISSIONS__

final class PermissionEditor {
    var state: State
    var confirmWarning = true
    var warningRights: TelegramBusinessBotRights = []

    init(rights: TelegramBusinessBotRights? = nil) {
        state = State(permissions: makePermissions(rights, []))
    }

    func restore(_ bot: TelegramAccountConnectedBot?) {
        let updateState: ((State) -> State) -> Void = { self.state = $0(self.state) }
        __APPLY_BOT__
        applyBot(bot, peer: bot.map { EnginePeer(id: $0.id) })
    }

    func with<T>(_ f: (State) -> T) -> T { f(state) }

    func toggle(_ id: String) {
        let stateValue = self
        let updateState: ((State) -> State) -> Void = { self.state = $0(self.state) }
        func presentStarGiftsWarningIfNeeded(_ key: TelegramBusinessBotRights, completion: @escaping (Bool) -> Void) -> Bool {
            let needsWarning = !key.intersection([.transferAndUpgradeGifts, .transferStars, .editUsername]).isEmpty
            warningRights = needsWarning ? key : []
            completion(!needsWarning || confirmWarning)
            return needsWarning
        }
        let action: (String) -> Void = __TOGGLE__
        action(id)
    }
}

final class BusinessBotPermissionsTests: XCTestCase {
    let messageRights: TelegramBusinessBotRights = [.reply, .readMessages, .deleteSentMessages, .deleteReceivedMessages]

    func testNewBotOnlyRequestsMessagePermissions() {
        XCTAssertEqual(PermissionEditor().state.botRights, messageRights)
    }

    func testEveryPermissionCombinationSurvivesSavingAndReopening() {
        for mask in 0...TelegramBusinessBotRights.All.rawValue {
            let selected = TelegramBusinessBotRights(rawValue: mask)
            let editor = PermissionEditor(rights: selected)
            let outgoing = editor.state.botRights
            guard outgoing == selected else {
                XCTFail("Selection \(mask) was saved as \(outgoing.rawValue)")
                return
            }
            XCTAssertEqual(PermissionEditor(rights: outgoing).state.permissions, editor.state.permissions)
        }
    }

    func testMessageGroupCanBeFullyDisabledAndRestored() {
        let editor = PermissionEditor()
        editor.toggle("message")
        XCTAssertEqual(editor.state.botRights, [])
        editor.toggle("message")
        XCTAssertEqual(editor.state.botRights, messageRights)
    }

    func testMarkAsReadCanBeDisabledIndependently() {
        let editor = PermissionEditor()
        editor.toggle("mark")
        XCTAssertEqual(editor.state.botRights, [.reply, .deleteSentMessages, .deleteReceivedMessages])
        editor.toggle("mark")
        XCTAssertEqual(editor.state.botRights, messageRights)
    }

    func testStoriesCanBeEnabledAndDisabled() {
        let editor = PermissionEditor()
        editor.toggle("stories")
        XCTAssertEqual(editor.state.botRights, messageRights.union(.manageStories))
        editor.toggle("stories")
        XCTAssertEqual(editor.state.botRights, messageRights)
    }

    func testPartialGroupsKeepOnlySelectedRights() {
        let editor = PermissionEditor()
        editor.toggle("name")
        editor.toggle("view")
        XCTAssertEqual(editor.state.botRights, messageRights.union([.editName, .viewGifts]))
        let reopened = PermissionEditor(rights: editor.state.botRights)
        XCTAssertEqual(reopened.state.permissions, editor.state.permissions)
        reopened.toggle("name")
        reopened.toggle("view")
        XCTAssertEqual(reopened.state.botRights, messageRights)
    }

    func testGiftAndStarRightsRequireExplicitSelection() {
        let cases: [(String, TelegramBusinessBotRights)] = [
            ("sell", .sellGifts),
            ("settings", .changeGiftSettings),
            ("transfer", .transferAndUpgradeGifts),
            ("transferStars", .transferStars)
        ]
        for (id, right) in cases {
            let editor = PermissionEditor()
            editor.toggle(id)
            XCTAssertEqual(editor.state.botRights, messageRights.union(right))
            editor.toggle(id)
            XCTAssertEqual(editor.state.botRights, messageRights)
            XCTAssertEqual(editor.warningRights, [])
        }
    }

    func testCancellingWarningPreservesSelection() {
        for id in ["transfer", "transferStars", "username", "gifts", "profile"] {
            let editor = PermissionEditor()
            editor.confirmWarning = false
            let before = editor.state.permissions
            editor.toggle(id)
            XCTAssertFalse(editor.warningRights.isEmpty)
            XCTAssertEqual(editor.state.permissions, before)
            XCTAssertEqual(editor.state.botRights, messageRights)
        }
    }

    func testGiftGroupCanBeEnabledAndDisabledAfterConfirmation() {
        let editor = PermissionEditor()
        editor.toggle("gifts")
        XCTAssertEqual(editor.state.botRights, messageRights.union([.viewGifts, .sellGifts, .changeGiftSettings, .transferAndUpgradeGifts, .transferStars]))
        editor.toggle("gifts")
        XCTAssertEqual(editor.state.botRights, messageRights)
    }
}

final class BusinessBotRestorationTests: XCTestCase {
    func id(_ value: Int64) -> PeerId { PeerId(namespace: 0, id: ._internalFromInt64Value(value)) }
    func bot(exclude: Bool) -> TelegramAccountConnectedBot {
        TelegramAccountConnectedBot(
            id: id(2),
            recipients: .init(categories: [.contacts, .newChats], additionalPeers: [id(3)], excludePeers: [id(4)], exclude: exclude),
            rights: [.reply, .viewGifts],
            device: "Mac", date: 123, location: "Tashkent"
        )
    }

    func testServerSettingsRoundTripWithoutUnsavedChanges() {
        for exclude in [true, false] {
            let editor = PermissionEditor()
            let saved = bot(exclude: exclude)
            editor.restore(saved)
            XCTAssertEqual(editor.state.mapped?.id, saved.id)
            XCTAssertEqual(editor.state.mapped?.recipients, saved.recipients)
            XCTAssertEqual(editor.state.mapped?.rights, saved.rights)
            XCTAssertFalse(editor.state.hasChanges)
            XCTAssertFalse(editor.state.isLoading)
            editor.toggle("settings")
            XCTAssertTrue(editor.state.hasChanges)
        }
    }

    func testRefusedRightsAreRemovedFromSwitches() {
        let editor = PermissionEditor()
        let saved = bot(exclude: false)
        editor.restore(saved)
        editor.toggle("settings")
        editor.toggle("sell")
        editor.state.isSaving = true
        editor.restore(saved)
        XCTAssertFalse(editor.state.botRights.contains(.changeGiftSettings))
        XCTAssertFalse(editor.state.botRights.contains(.sellGifts))
        XCTAssertTrue(editor.state.botRights.contains(.viewGifts))
        XCTAssertFalse(editor.state.hasChanges)
        XCTAssertFalse(editor.state.isSaving)
    }

    func testServerDisconnectClearsBotAndRecipients() {
        let editor = PermissionEditor()
        editor.restore(bot(exclude: false))
        editor.state.isSaving = true
        editor.restore(nil)
        XCTAssertNil(editor.state.bot)
        XCTAssertNil(editor.state.initialBot)
        XCTAssertNil(editor.state.botsResult)
        XCTAssertNil(editor.state.mapped)
        XCTAssertTrue(editor.state.includeIds.isEmpty)
        XCTAssertTrue(editor.state.excludeIds.isEmpty)
        XCTAssertTrue(editor.state.disableIds.isEmpty)
        XCTAssertFalse(editor.state.hasChanges)
        XCTAssertFalse(editor.state.isSaving)
    }


}
