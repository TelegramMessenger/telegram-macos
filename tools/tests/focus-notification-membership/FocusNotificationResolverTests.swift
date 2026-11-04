import Foundation

private final class TestFocusObservation: FocusFilterObservation {
    func invalidate() {
    }
}

private final class TestFocusPolicySource: FocusFilterPolicySource {
    var policy: FocusFilterPolicy

    init(_ policy: FocusFilterPolicy) {
        self.policy = policy
    }

    func observe(_ observer: @escaping (FocusFilterPolicy) -> Void) -> any FocusFilterObservation {
        observer(policy)
        return TestFocusObservation()
    }
}

private struct PendingFocusLookup {
    let identifier: FocusChatIdentifier
    let configuration: FocusFilterConfiguration
    let complete: (FocusFilterPolicy?) -> Void
}

enum FocusNotificationResolverTests {
    static func run() {
        let identifier = FocusChatIdentifier(accountId: 71, peerId: 0x10000002a)
        let originalFolder = FocusFolderIdentifier(accountId: 71, folderId: 4)
        let latestFolder = FocusFolderIdentifier(accountId: 71, folderId: 5)
        let originalConfiguration = FocusFilterConfiguration(accountIds: [71], folderIds: [originalFolder], effect: .both)
        let latestConfiguration = FocusFilterConfiguration(accountIds: [71], folderIds: [latestFolder], effect: .both)
        let source = TestFocusPolicySource(FocusFilterPolicy(configuration: originalConfiguration))
        var pending: [PendingFocusLookup] = []
        let resolver = FocusNotificationResolver(policySource: source, isEnabled: true, livePolicyLookup: { identifier, configuration, completion in
            pending.append(PendingFocusLookup(identifier: identifier, configuration: configuration, complete: completion))
        })
        var decisions: [ResolvedFocusNotification] = []
        resolver.resolve(identifier: identifier) { decisions.append($0) }
        precondition(pending.count == 1 && pending[0].identifier == identifier)
        precondition(pending[0].configuration == originalConfiguration && decisions.isEmpty)
        source.policy = FocusFilterPolicy(configuration: latestConfiguration)
        pending[0].complete(FocusFilterPolicy(configuration: originalConfiguration))
        precondition(pending.count == 2 && decisions.isEmpty)
        precondition(pending[1].configuration == latestConfiguration)
        let liveCatalog = FocusFilterCatalog(folders: [.init(id: latestFolder, title: "Current folder", peerIds: [identifier.peerId])])
        pending[1].complete(FocusFilterPolicy(configuration: latestConfiguration, catalog: liveCatalog))
        precondition(decisions.count == 1 && decisions[0].allowsNotification)
        let criteria = decisions[0].filterCriteria!
        precondition(criteria == "telegram-focus:71:4294967338;|folder:71:5|")
        precondition(FocusNotificationFilter(configuration: latestConfiguration).predicate.evaluate(with: criteria))
        print("PASS injected resolver retries changed configuration before producing gate and system criteria")

        decisions.removeAll()
        pending.removeAll()
        source.policy = FocusFilterPolicy(configuration: originalConfiguration)
        resolver.resolve(identifier: identifier) { decisions.append($0) }
        var listOnly = originalConfiguration
        listOnly.effect = .chatList
        source.policy = FocusFilterPolicy(configuration: listOnly)
        pending[0].complete(FocusFilterPolicy(configuration: originalConfiguration))
        precondition(pending.count == 1 && decisions.count == 1 && decisions[0].allowsNotification)
        print("PASS configuration changes that stop notification filtering finish without another live lookup")

        source.policy = FocusFilterPolicy(configuration: originalConfiguration)
        var unavailableAccountLookups = 0
        let unavailableAccountResolver = FocusNotificationResolver(policySource: source, isEnabled: true, livePolicyLookup: { _, configuration, completion in
            unavailableAccountLookups += 1
            precondition(configuration == originalConfiguration)
            completion(nil)
        })
        unavailableAccountResolver.resolve(identifier: identifier) { decision in
            precondition(!decision.allowsNotification)
            precondition(decision.filterCriteria == "telegram-focus:71:4294967338;")
        }
        precondition(unavailableAccountLookups == 1)
        unavailableAccountResolver.resolve(identifier: nil) { decision in
            precondition(decision.allowsNotification && decision.filterCriteria == nil)
        }
        unavailableAccountResolver.resolve(identifier: .init(accountId: 72, peerId: identifier.peerId)) { decision in
            precondition(decision.allowsNotification && decision.filterCriteria == "telegram-focus:72:4294967338;")
        }
        precondition(unavailableAccountLookups == 1)
        let disabledResolver = FocusNotificationResolver(policySource: source, isEnabled: false, livePolicyLookup: { _, _, _ in
            preconditionFailure("Unavailable system filtering must not request membership")
        })
        disabledResolver.resolve(identifier: identifier) { decision in
            precondition(decision.allowsNotification && decision.filterCriteria == nil)
        }
        print("PASS missing account, absent identity, untargeted account and unavailable system retain fallback behavior")

        source.policy = FocusFilterPolicy(configuration: .init(accountIds: [71], chatIds: [identifier], effect: .notifications))
        unavailableAccountResolver.resolve(identifier: identifier) { precondition($0.allowsNotification) }
        unavailableAccountResolver.resolve(identifier: .init(accountId: 71, peerId: 999)) { precondition(!$0.allowsNotification) }
        precondition(unavailableAccountLookups == 1)
        print("PASS explicit-chat-only notification policy avoids live folder lookup")
    }
}
