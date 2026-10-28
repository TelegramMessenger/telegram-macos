import Postbox
import SwiftSignalKit
import TelegramCore

func saveDeveloperAppResetBackup(_ backupData: AccountBackupData?, accountId: AccountRecordId, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
    guard let backupData else {
        return .single(false)
    }
    return accountManager.transaction { transaction in
        var saved = false
        transaction.updateRecord(accountId) { record in
            guard let record else {
                return nil
            }
            var attributes = record.attributes.filter { attribute in
                if case .backupData = attribute {
                    return false
                }
                return true
            }
            attributes.append(.backupData(AccountBackupDataAttribute(data: backupData)))
            saved = true
            return AccountRecord(id: record.id, attributes: attributes, temporarySessionId: record.temporarySessionId)
        }
        return saved
    }
}
