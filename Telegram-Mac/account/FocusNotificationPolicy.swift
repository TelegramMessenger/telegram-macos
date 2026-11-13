import FocusFilterCore
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramUtils

func focusNotificationPolicy(account: Account, peerId: PeerId, configuration: FocusFilterConfiguration) -> Signal<FocusFilterPolicy, NoError> {
    combineLatest(
        TelegramEngine(account: account).peers.updatedChatListFilters() |> take(1),
        communityFilterCategories(account: account) |> take(1)
    ) |> take(1) |> mapToSignal { filters, categories in
        account.postbox.transaction { transaction in
            focusNotificationPolicy(transaction: transaction, request: .init(chat: .init(accountId: account.id.int64, peerId: peerId.toInt64()), configuration: configuration, filters: filters, communityCategories: categories))
        }
    }
}

extension FocusNotificationResolver {
    convenience init(policySource: any FocusFilterPolicySource, accounts: @escaping () -> [(AccountRecordId, Account)]) {
        let isEnabled: Bool
        if #available(macOS 13.0, *) {
            isEnabled = true
        } else {
            isEnabled = false
        }
        self.init(policySource: policySource, isEnabled: isEnabled, livePolicyLookup: { identifier, configuration, completion in
            guard let account = accounts().first(where: { $0.0.int64 == identifier.accountId })?.1 else {
                completion(nil)
                return
            }
            _ = (focusNotificationPolicy(account: account, peerId: PeerId(identifier.peerId), configuration: configuration) |> deliverOnMainQueue).start(next: { policy in
                completion(policy)
            })
        })
    }
}
