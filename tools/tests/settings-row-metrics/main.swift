import Foundation

let titleHeight: CGFloat = 16
assert(SettingsRowMetrics.height(presentation: .content, hasIcon: false, titleHeight: titleHeight) == 38)
assert(SettingsRowMetrics.height(presentation: .content, hasIcon: true, titleHeight: titleHeight) == 43)
assert(SettingsRowMetrics.height(presentation: .content, hasIcon: true, titleHeight: titleHeight, subtitleHeight: 14) == 53)
assert(SettingsRowMetrics.height(presentation: .content, hasIcon: true, titleHeight: titleHeight, subtitleHeight: 70) == 109)
assert(SettingsRowMetrics.height(presentation: .hub, hasIcon: true, titleHeight: titleHeight) == 45)
assert(SettingsRowMetrics.height(presentation: .sidebar, hasIcon: true, titleHeight: titleHeight) == 32)
assert(SettingsRowMetrics.iconSize(presentation: .content) == 20)
assert(SettingsRowMetrics.iconSize(presentation: .hub) == 24)
assert(SettingsRowMetrics.iconSize(presentation: .sidebar) == 20)
assert(SettingsRowMetrics.textInset(presentation: .content, hasIcon: true) == 30)
assert(SettingsRowMetrics.textInset(presentation: .hub, hasIcon: true) == 38)
assert(SettingsRowMetrics.textInset(presentation: .sidebar, hasIcon: true) == 28)
assert(SettingsRowMetrics.textInset(presentation: .content, hasIcon: false) == 0)
assert(SettingsRowMetrics.sidebarInset + SettingsRowMetrics.sidebarContentInset == 19)
assert(SettingsRowMetrics.deviceIconSize == 26)
print("Settings row metrics: 15 checks passed")
