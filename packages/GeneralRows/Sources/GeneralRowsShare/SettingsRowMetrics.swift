import Foundation

public enum SettingsRowPresentation: Equatable {
    case content
    case hub
    case sidebar
}

public enum SettingsRowMetrics {
    public static let contentInset: CGFloat = 10
    public static let cardGap: CGFloat = 10
    public static let iconGap: CGFloat = 10
    public static let iconSize: CGFloat = 20
    public static let deviceIconSize: CGFloat = 26
    public static let titleSize: CGFloat = 13
    public static let subtitleSize: CGFloat = 11
    public static let subtitleGap: CGFloat = 3
    public static let verticalInset: CGFloat = 10
    public static let sidebarHeight: CGFloat = 32
    public static let sidebarInset: CGFloat = 10
    public static let sidebarContentInset: CGFloat = 9
    public static let sidebarIconGap: CGFloat = 8
    public static let cardCornerRadius: CGFloat = 12
    public static let sidebarCornerRadius: CGFloat = 8
    public static let cornerSmoothing: CGFloat = 0.6

    public static func height(presentation: SettingsRowPresentation, hasIcon: Bool, titleHeight: CGFloat, subtitleHeight: CGFloat = 0) -> CGFloat {
        switch presentation {
        case .sidebar:
            return sidebarHeight
        case .hub:
            return max(45, titleHeight + 2 * verticalInset)
        case .content:
            if subtitleHeight > 0 {
                return max(53, titleHeight + subtitleGap + subtitleHeight + 2 * verticalInset)
            }
            return max(hasIcon ? 43 : 38, titleHeight + 2 * verticalInset)
        }
    }

    public static func iconSize(presentation: SettingsRowPresentation) -> CGFloat {
        return presentation == .hub ? 24 : iconSize
    }

    public static func textInset(presentation: SettingsRowPresentation, hasIcon: Bool) -> CGFloat {
        guard hasIcon else { return 0 }
        switch presentation {
        case .sidebar:
            return iconSize + sidebarIconGap
        case .hub:
            return 24 + 14
        case .content:
            return iconSize + iconGap
        }
    }
}

public extension String {
    var settingsSentenceCase: String {
        guard rangeOfCharacter(from: .lowercaseLetters) == nil else {
            return self
        }
        let lowered = lowercased()
        return lowered.prefix(1).uppercased() + lowered.dropFirst()
    }
}

public extension String {
    var settingsTitleCase: String {
        guard rangeOfCharacter(from: .lowercaseLetters) == nil else {
            return self
        }
        guard rangeOfCharacter(from: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")) != nil else {
            return settingsSentenceCase
        }
        let minor: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "in", "nor", "of", "on", "or", "the", "to", "with"]
        var result: [String] = []
        for (index, word) in lowercased().split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            let word = String(word)
            if index > 0, minor.contains(word) {
                result.append(word)
            } else {
                result.append(word.prefix(1).uppercased() + word.dropFirst())
            }
        }
        return result.joined(separator: " ")
    }
}
