import XCTest
import Cocoa
import WalletContext
import TelegramCore
import Localization
@testable import WalletUI

private func repositoryRoot() -> URL {
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func submoduleStrings() throws -> [String: String] {
    let data = try Data(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/Telegram/Telegram-iOS/en.lproj/Localizable.strings"))
    return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

private func nativeEnglishStrings() throws -> [String: String] {
    let data = try Data(contentsOf: repositoryRoot().appendingPathComponent("Telegram-Mac/en.lproj/Localizable.strings"))
    return try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

private func source(_ path: String) throws -> String {
    return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
}

private func submoduleFormat(_ format: String, _ arguments: String...) -> String {
    var result = format
    for (index, argument) in arguments.enumerated() {
        result = result.replacingOccurrences(of: "%\(index + 1)$@", with: argument)
    }
    if let first = arguments.first {
        result = result.replacingOccurrences(of: "%@", with: first)
    }
    return result
}

private func submoduleAfterTime(_ value: Int32, strings: [String: String]) -> String {
    func plural(_ key: String, _ count: Int32) -> String {
        return submoduleFormat(strings[key + (count == 1 ? "_1" : "_any")]!, "\(count)")
    }
    if value < 60 {
        return plural("Time.AfterSeconds", max(1, value))
    } else if value < 60 * 60 {
        return plural("Time.AfterMinutes", max(1, value / 60))
    } else if value < 60 * 60 * 24 {
        return plural("Time.AfterHours", max(1, value / (60 * 60)))
    } else if value < 60 * 60 * 24 * 7 {
        return plural("Time.AfterDays", max(1, value / (60 * 60 * 24)))
    } else if value < 60 * 60 * 24 * 30 {
        return plural("Time.AfterWeeks", max(1, value / (60 * 60 * 24 * 7)))
    } else if value < 60 * 60 * 24 * 365 {
        return plural("Time.AfterMonths", max(1, value / (60 * 60 * 24 * 30)))
    } else {
        return plural("Time.AfterYears", max(1, value / (60 * 60 * 24 * 365)))
    }
}

private func submoduleAuthorizationErrorMessage(_ error: WalletContext.WalletError, strings: [String: String]) -> (title: String, text: String)? {
    switch error {
    case .recoveryPhraseOutdated:
        return (strings["Wallet.Import.PhraseChangedTitle"]!, strings["Wallet.Import.PhraseChangedText"]!)
    case .twoStepAuthMissing:
        return (strings["Wallet.Authorization.TwoStepRequiredTitle"]!, strings["Wallet.Authorization.TwoStepRequiredText"]!)
    case let .passwordTooFresh(timeout):
        return (strings["Wallet.Authorization.PasswordTooNewTitle"]!, submoduleFormat(strings["Wallet.Authorization.PasswordRetryAfter"]!, submoduleAfterTime(timeout, strings: strings)))
    case let .sessionTooFresh(timeout):
        return (strings["Wallet.Authorization.SessionTooNewTitle"]!, submoduleFormat(strings["Wallet.Authorization.SessionRetryAfter"]!, submoduleAfterTime(timeout, strings: strings)))
    case .backupDisabled:
        return (strings["Wallet.Authorization.BackupDisabledTitle"]!, strings["Wallet.Authorization.BackupDisabledText"]!)
    case .backupNotAvailable:
        return (strings["Wallet.Authorization.BackupUnavailableTitle"]!, strings["Wallet.Authorization.BackupUnavailableText"]!)
    case .keyRotationFailed:
        return (strings["Wallet.Backup.UpdatePhraseErrorTitle"]!, strings["Wallet.Authorization.UpdatePhraseErrorText"]!)
    case .proofInvalid:
        return (strings["Wallet.Authorization.VerifyWalletErrorTitle"]!, strings["Wallet.Authorization.VerifyWalletErrorText"]!)
    case .proofExpired:
        return (strings["Wallet.Authorization.VerificationExpiredTitle"]!, strings["Wallet.Authorization.VerificationExpiredText"]!)
    default:
        return nil
    }
}

private func submoduleBackupEnableErrorMessage(_ error: WalletContext.WalletError, strings: [String: String]) -> (title: String, text: String) {
    switch error {
    case .walletKeyMismatch, .recoveryPhraseOutdated, .storage(.identityMismatch), .proofInvalid:
        return (strings["Wallet.Backup.VerifyPhraseErrorTitle"]!, strings["Wallet.Backup.VerifyPhraseErrorText"]!)
    case .rotationNotFound:
        return (strings["Wallet.Backup.PhraseUpdatePendingTitle"]!, strings["Wallet.Backup.EnablePhraseUpdatePendingText"]!)
    case .proofExpired:
        return (strings["Wallet.Authorization.VerificationExpiredTitle"]!, strings["Wallet.Backup.EnableVerificationExpiredText"]!)
    case .invalidMnemonic:
        return (strings["Wallet.Import.InvalidPhraseTitle"]!, strings["Wallet.Backup.InvalidPhraseText"]!)
    case .unavailable:
        return (strings["Wallet.Backup.WalletChangedTitle"]!, strings["Wallet.Backup.EnableWalletChangedText"]!)
    default:
        return submoduleAuthorizationErrorMessage(error, strings: strings) ?? (strings["Wallet.Backup.EnableErrorTitle"]!, strings["Wallet.NetworkError"]!)
    }
}

private func submodulePreviewRow(_ item: WalletTransferPresentation.PreviewItem, fallbackDestination: String, strings: [String: String]) -> (title: String, subtitle: String?) {
    let title: String
    var subtitle: String?
    switch item.kind {
    case .transfer:
        switch item.direction {
        case .some(.outgoing):
            title = walletTransferShortAddress(item.address ?? fallbackDestination)
            subtitle = strings["Wallet.Transaction.Withdrawal"]!
        case .some(.incoming):
            title = item.address.map(walletTransferShortAddress) ?? strings["Wallet.Transaction.Transfer"]!
            subtitle = strings["Wallet.Transaction.Deposit"]!
        case nil:
            title = strings["Wallet.Transaction.Transfer"]!
            subtitle = item.address.map(walletTransferShortAddress)
        }
    case .callContract:
        title = strings["Wallet.Transaction.CallContract"]!
    case .deployContract:
        title = strings["Wallet.Transaction.DeployContract"]!
    case .excess:
        title = strings["Wallet.Transaction.Excess"]!
    case .unknown:
        title = strings["Wallet.Transaction.UnknownOperation"]!
    }
    if !item.succeeded {
        subtitle = subtitle.map { submoduleFormat(strings["Wallet.Transaction.FailedOperation"]!, $0) } ?? strings["Wallet.Transaction.Failed"]!
    }
    return (title, subtitle)
}

private func submoduleShowsEarningsBanner(availableEarnings: Int64?) -> Bool {
    guard let availableEarnings else {
        return false
    }
    return availableEarnings >= 10_000_000_000
}

private func submoduleAcceptsPastedPhrase(wordCount: Int) -> Bool {
    return wordCount == 12 || wordCount == 24
}

private func typographic(_ text: String) -> String {
    return text.replacingOccurrences(of: "’", with: "'")
}

private func applyEnglish(_ strings: [String: String]) {
    let entries = strings.map { LocalizationEntry.string(key: $0.key, value: $0.value) }
    let component = LocalizationComponent(languageCode: "en", localizedName: "English", localization: TelegramCore.Localization(version: 0, entries: entries), customPluralizationCode: nil)
    applyUILocalization(LocalizationSettings(primaryComponent: component, secondaryComponent: nil))
}

final class WalletTextSubmoduleCompatibilityTests: XCTestCase {
    override func setUp() {
        super.setUp()
        applyMacEnglishStrings()
    }

    override func tearDown() {
        applyMacEnglishStrings([:])
        super.tearDown()
    }

    func testTooNewWaitTimesReadLikeSubmodule() throws {
        let strings = try submoduleStrings()
        let actualStrings = try XCTUnwrap(NSDictionary(contentsOf: repositoryRoot().appendingPathComponent("Telegram-Mac/en.lproj/Localizable.strings")) as? [String: String])
        applyEnglish(actualStrings)
        defer { applyEnglish([:]) }
        for timeout: Int32 in [5, 30, 59, 120, 3599, 7200, 36000, 2 * 86400, 5 * 86400, 14 * 86400, 60 * 86400] {
            for error in [WalletContext.WalletError.passwordTooFresh(timeout), .sessionTooFresh(timeout)] {
                let actual = try XCTUnwrap(walletAuthorizationErrorMessage(error), "\(error)")
                let submodule = try XCTUnwrap(submoduleAuthorizationErrorMessage(error, strings: strings))
                XCTAssertEqual(actual.title, submodule.title, "\(error)")
                XCTAssertEqual(actual.text, submodule.text, "\(error)")
            }
        }
    }

    func testTooNewSingleUnitWaitTimesReadLikeSubmodule() throws {
        let strings = try submoduleStrings()
        var actualStrings = try XCTUnwrap(NSDictionary(contentsOf: repositoryRoot().appendingPathComponent("Telegram-Mac/en.lproj/Localizable.strings")) as? [String: String])
        for (unit, name) in [("Seconds", "second"), ("Minutes", "minute"), ("Hours", "hour"), ("Days", "day"), ("Weeks", "week"), ("Months", "month")] {
            actualStrings["Timer.\(unit)_one"] = "%d \(name)"
        }
        applyEnglish(actualStrings)
        defer { applyEnglish([:]) }
        for timeout: Int32 in [1, 60, 3600, 86400, 7 * 86400, 30 * 86400] {
            for error in [WalletContext.WalletError.passwordTooFresh(timeout), .sessionTooFresh(timeout)] {
                let actual = try XCTUnwrap(walletAuthorizationErrorMessage(error), "\(error)")
                let submodule = try XCTUnwrap(submoduleAuthorizationErrorMessage(error, strings: strings))
                XCTAssertEqual(actual.text, submodule.text, "\(error)")
            }
        }
    }

    func testAuthorizationErrorTextsMatchSubmodule() throws {
        let strings = try submoduleStrings()
        let errors: [WalletContext.WalletError] = [.recoveryPhraseOutdated, .twoStepAuthMissing, .backupDisabled, .backupNotAvailable, .keyRotationFailed, .proofInvalid, .proofExpired]
        for error in errors {
            let actual = try XCTUnwrap(walletAuthorizationErrorMessage(error), "\(error)")
            let submodule = try XCTUnwrap(submoduleAuthorizationErrorMessage(error, strings: strings), "\(error)")
            XCTAssertEqual(typographic(actual.title), submodule.title, "\(error)")
            XCTAssertEqual(typographic(actual.text), submodule.text, "\(error)")
        }
    }

    func testBackupEnableErrorTextsMatchSubmodule() throws {
        let strings = try submoduleStrings()
        let errors: [WalletContext.WalletError] = [.walletKeyMismatch, .recoveryPhraseOutdated, .storage(.identityMismatch), .proofInvalid, .rotationNotFound, .proofExpired, .invalidMnemonic, .unavailable, .network, .twoStepAuthMissing, .keyRotationFailed]
        for error in errors {
            let actual = walletBackupEnableErrorMessage(error)
            let submodule = submoduleBackupEnableErrorMessage(error, strings: strings)
            XCTAssertEqual(typographic(actual.title), submodule.title, "\(error)")
            XCTAssertEqual(typographic(actual.text), submodule.text, "\(error)")
        }
    }

    func testSigningExplanationsMatchSubmodule() throws {
        let strings = try submoduleStrings()
        XCTAssertEqual(WalletTransferPresentation.SigningContent.text("hello").explanation, strings["Wallet.Sign.TextExplanation"])
        XCTAssertEqual(WalletTransferPresentation.SigningContent.message([]).explanation, strings["Wallet.Sign.MessageExplanation"])
        XCTAssertNil(WalletTransferPresentation.SigningContent.binary.explanation)
    }

    func testTransferPreviewRowsMatchSubmodule() throws {
        let strings = try submoduleStrings()
        let address = "UQAREREREREREREREREREREREREREREREREREREREREREbvW"
        let fallback = "EQBvW8Z5huBkMJYdnfAEM5JqTNkuWX3diqYENkWsIL0XggGG"
        let kinds: [WalletTransferPresentation.PreviewItem.Kind] = [.transfer, .callContract, .deployContract, .excess, .unknown]
        let directions: [WalletTransferPresentation.PreviewItem.Direction?] = [.outgoing, .incoming, nil]
        for kind in kinds {
            for direction in directions {
                for itemAddress in [address, nil] {
                    for succeeded in [true, false] {
                        let item = WalletTransferPresentation.PreviewItem(id: "1", kind: kind, direction: direction, address: itemAddress, amount: "1000000000", comment: nil, succeeded: succeeded)
                        let actual = walletTransferPreviewRowContent(item, fallbackDestination: fallback)
                        let submodule = submodulePreviewRow(item, fallbackDestination: fallback, strings: strings)
                        let label = "\(kind) \(String(describing: direction)) \(itemAddress ?? "nil") \(succeeded)"
                        XCTAssertEqual(actual.title, submodule.title, label)
                        XCTAssertEqual(actual.subtitle, submodule.subtitle, label)
                    }
                }
            }
        }
    }

    func testEarningsBannerNeedsTenGramsLikeSubmodule() {
        for earnings: Int64? in [nil, 0, 1, 9_999_999_999, 10_000_000_000, 25_000_000_000] {
            var state = WalletHomeState()
            state.availableEarnings = earnings
            XCTAssertEqual(walletHomeBanners(state).contains(.earnings), submoduleShowsEarningsBanner(availableEarnings: earnings), "\(String(describing: earnings))")
        }
    }

    func testPastedPhraseLengthsMatchSubmoduleInEveryImportMode() {
        for count in [2, 11, 12, 13, 18, 23, 24, 25] {
            var state = WalletImportState(words: Array(repeating: "", count: 12), displayNumbers: Array(1 ... 12))
            let words = (0 ..< count).map { "word\($0)" }
            let result = walletDistributeRecoveryWords(&state, index: 3, words: words, verification: false)
            if submoduleAcceptsPastedPhrase(wordCount: count) {
                XCTAssertEqual(result, .inserted(0 ..< count), "\(count)")
                XCTAssertEqual(state.words, words, "\(count)")
                XCTAssertEqual(state.displayNumbers, Array(1 ... count), "\(count)")
            } else {
                XCTAssertEqual(result, .invalidCount, "\(count)")
                XCTAssertEqual(state.words.count, 12, "\(count)")
            }
        }
    }

    func testCancelDisablingBackupAlertMatchesSubmodule() throws {
        let strings = try submoduleStrings()
        let submodule = try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletWordsScreen/Sources/WalletWordsScreen.swift")
        for line in [
            "guard case .backupDisable = self.mode, !self.isDismissingProgrammatically else {",
            "title: strings.Wallet_Backup_CancelDisablingTitle,",
            "text: strings.Wallet_Backup_CancelDisablingText,",
            "TextAlertAction(type: .defaultAction, title: strings.Wallet_Backup_CancelDisabling, action: completion),",
            "TextAlertAction(type: .genericAction, title: strings.Wallet_Continue, action: {})",
            "controller.requestDismiss(completion: animateDismissal)",
            "self.isDismissingProgrammatically = true"
        ] {
            XCTAssertTrue(submodule.contains(line), line)
        }
        let actual = try source("packages/WalletUI/Sources/WalletUI/WalletWordsController.swift")
        let title = try XCTUnwrap(strings["Wallet.Backup.CancelDisablingTitle"])
        let text = try XCTUnwrap(strings["Wallet.Backup.CancelDisablingText"])
        let confirm = try XCTUnwrap(strings["Wallet.Backup.CancelDisabling"])
        let stay = try XCTUnwrap(strings["Wallet.Continue"])
        let english = try nativeEnglishStrings()
        XCTAssertEqual(english["Wallet.WordsController.CancelDisablingTitle"], title)
        XCTAssertEqual(english["Wallet.WordsController.CancelDisablingInfo"], text)
        XCTAssertEqual(english["Wallet.WordsController.CancelDisabling"], confirm)
        XCTAssertEqual(english["Wallet.WordsController.Continue"], stay)
        XCTAssertTrue(actual.contains("header: strings().walletWordsControllerCancelDisablingTitle, information: strings().walletWordsControllerCancelDisablingInfo, ok: strings().walletWordsControllerCancelDisabling, cancel: strings().walletWordsControllerContinue"))
    }

    func testWithdrawalMinimumMessageMatchesSubmodule() throws {
        let strings = try submoduleStrings()
        let message = try XCTUnwrap(strings["Monetization.Withdraw.AmountTooSmallError"])
        let submodule = try source("submodules/telegram-ios/submodules/StatisticsUI/Sources/RevenueWithdrawalController.swift")
        XCTAssertTrue(submodule.contains("requestStarsRevenueWithdrawalUrl(peerId: peerId, ton: true"))
        XCTAssertTrue(submodule.contains("case .amountTooSmall:\n                errorTextAndActions = (strings.Monetization_Withdraw_AmountTooSmallError"))
        let submoduleStars = try source("submodules/telegram-ios/submodules/TelegramUI/Components/Stars/StarsWithdrawalScreen/Sources/StarsRevenueWithdrawalController.swift")
        XCTAssertFalse(submoduleStars.contains("AmountTooSmallError"))

        for (path, tonFlows) in [("packages/StarsUI/Sources/StarsUI/Star_ListScreen.swift", 1), ("packages/MonetizationUI/Sources/MonetizationUI/FragmentMonetizationController.swift", 2), ("packages/MonetizationUI/Sources/MonetizationUI/FragmentStarMonetizationController.swift", 0)] {
            let actual = try source(path)
            let requests = actual.components(separatedBy: "requestStarsRevenueWithdrawalUrl(").dropFirst()
            let ton = requests.filter { $0.prefix(while: { $0 != "\n" }).contains("ton: true") }
            XCTAssertEqual(ton.count, tonFlows, path)
            for request in ton {
                let mapping = try XCTUnwrap(request.components(separatedBy: "default:").first, path)
                XCTAssertTrue(mapping.contains("case .amountTooSmall:"), path)
                let accessor = path.contains("Star_ListScreen") ? "strings().starListScreenWithdrawMinimumGrams" : "strings().fragmentMonetizationControllerWithdrawMinimum"
                XCTAssertTrue(mapping.contains("return .custom(\(accessor))"), path)
                let key = path.contains("Star_ListScreen") ? "Star.ListScreen.WithdrawMinimumGrams" : "FragmentMonetization.Controller.WithdrawMinimum"
                XCTAssertEqual(try nativeEnglishStrings()[key], message, path)
            }
            for request in requests where !request.prefix(while: { $0 != "\n" }).contains("ton: true") {
                let mapping = request.components(separatedBy: "default:").first ?? ""
                XCTAssertFalse(mapping.contains("case .amountTooSmall:"), path)
            }
        }
    }

    func testDisableBackupConfirmationMatchesSubmodule() throws {
        let strings = try submoduleStrings()
        XCTAssertEqual(walletDisableBackupConfirmationText(updateSecretPhrase: true), try XCTUnwrap(strings["Wallet.Backup.DisableWithNewPhraseText"]))
        XCTAssertEqual(walletDisableBackupConfirmationText(updateSecretPhrase: false), try XCTUnwrap(strings["Wallet.Backup.DisableConfirmationText"]))

        let submodule = try source("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletSettingsScreen/Sources/WalletSettingsScreen.swift")
        let submoduleConfirmation = try XCTUnwrap(submodule.components(separatedBy: "let text = prepared.updateSecretPhrase").dropFirst().first?.components(separatedBy: "let alertController = AlertScreen(").first)
        XCTAssertTrue(submoduleConfirmation.contains("strings.Wallet_Backup_DisableWithNewPhraseText"))
        XCTAssertFalse(submoduleConfirmation.contains("NetworkFee"))
        let actual = try source("packages/WalletUI/Sources/WalletUI/WalletSettingsController.swift")
        let actualConfirmation = try XCTUnwrap(actual.components(separatedBy: "presentFinalDisableBackupConfirmation = {").dropFirst().first?.components(separatedBy: "environment.verifyAlert(").first)
        XCTAssertTrue(actualConfirmation.contains("let information = walletDisableBackupConfirmationText(updateSecretPhrase: prepared.updateSecretPhrase)"))
        XCTAssertFalse(actualConfirmation.contains("disableBackupFeeText"))
    }

    func testRecipientNoResultsTextsMatchSubmodule() throws {
        let strings = try submoduleStrings()
        for query in ["alice", "@bob", "Alice Example"] {
            XCTAssertEqual(walletRecipientNoResultsText(query: query), submoduleFormat(try XCTUnwrap(strings["Wallet.Recipient.NoResultsText"]), query))
        }
        for query in ["UQ" + String(repeating: "x", count: 40), "0:abc", "ton://transfer/x", String(repeating: "a", count: 48)] {
            XCTAssertEqual(walletRecipientNoResultsText(query: query), try XCTUnwrap(strings["Wallet.Recipient.InvalidAddressText"]))
        }
    }

    func testTermsLineMatchesSubmodule() throws {
        let strings = try submoduleStrings()
        let text = try XCTUnwrap(strings["Wallet.TermsText"])
        let url = try XCTUnwrap(strings["Wallet.TermsText_URL"])
        XCTAssertEqual(text.components(separatedBy: "]()").count, 2)
        let template = try XCTUnwrap(try nativeEnglishStrings()["Wallet.Controller.TermsAgreement"])
        XCTAssertEqual(template.replacingOccurrences(of: "%1$@", with: url), text.replacingOccurrences(of: "]()", with: "](\(url))"))
        XCTAssertTrue(try source("packages/WalletUI/Sources/WalletUI/WalletController.swift").contains("let walletTermsText = strings().walletControllerTermsAgreement(walletTermsOfServiceUrl)"))
    }
}
