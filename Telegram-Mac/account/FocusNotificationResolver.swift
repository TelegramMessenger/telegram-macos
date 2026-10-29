import Foundation
import FocusFilterCore
import FocusFilterInfrastructure

enum ResolvedFocusNotification {
    case unidentified
    case chat(FocusChatIdentifier, FocusFilterPolicy)

    var allowsNotification: Bool {
        switch self {
        case .unidentified:
            return true
        case let .chat(identifier, policy):
            return policy.includes(accountId: identifier.accountId, peerId: identifier.peerId, effect: .notifications)
        }
    }

    var filterCriteria: String? {
        switch self {
        case .unidentified:
            return nil
        case let .chat(identifier, policy):
            return FocusNotificationFilter(configuration: policy.configuration).criteria(for: identifier, catalog: policy.catalog)
        }
    }
}

final class FocusNotificationResolver {
    typealias LivePolicyLookup = (FocusChatIdentifier, FocusFilterConfiguration, @escaping (FocusFilterPolicy?) -> Void) -> Void

    private let policySource: any FocusFilterPolicySource
    private let isEnabled: Bool
    private let livePolicyLookup: LivePolicyLookup

    init(policySource: any FocusFilterPolicySource, isEnabled: Bool, livePolicyLookup: @escaping LivePolicyLookup) {
        self.policySource = policySource
        self.isEnabled = isEnabled
        self.livePolicyLookup = livePolicyLookup
    }

    func resolve(identifier: FocusChatIdentifier?, completion: @escaping (ResolvedFocusNotification) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.resolve(identifier: identifier, completion: completion)
            }
            return
        }
        guard isEnabled, let identifier = identifier else {
            completion(.unidentified)
            return
        }
        let currentPolicy = policySource.policy
        let configuration = currentPolicy.configuration
        guard configuration.effect.contains(.notifications),
              configuration.accountIds.contains(identifier.accountId),
              configuration.folderIds.contains(where: { $0.accountId == identifier.accountId }) else {
            completion(.chat(identifier, currentPolicy))
            return
        }
        livePolicyLookup(identifier, configuration) { policy in
            guard self.policySource.policy.configuration == configuration else {
                self.resolve(identifier: identifier, completion: completion)
                return
            }
            completion(.chat(identifier, policy ?? currentPolicy))
        }
    }
}
