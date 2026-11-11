import Foundation

struct WebAppTitleLayout {
    let size: CGSize
    let titleFrame: CGRect
    let verificationFrame: CGRect?
    let statusFrame: CGRect?

    static func reservedWidth(verificationSize: CGSize?, statusSize: CGSize?, statusSpacing: CGFloat = 2) -> CGFloat {
        return (verificationSize.map { $0.width + 4 } ?? 0) + (statusSize.map { $0.width + statusSpacing } ?? 0)
    }

    init(titleSize: CGSize, verificationSize: CGSize?, statusSize: CGSize?, statusSpacing: CGFloat = 2) {
        let height = max(titleSize.height, verificationSize?.height ?? 0, statusSize?.height ?? 0)
        let leadingWidth = verificationSize.map { $0.width + 4 } ?? 0
        self.size = CGSize(width: titleSize.width + Self.reservedWidth(verificationSize: verificationSize, statusSize: statusSize, statusSpacing: statusSpacing), height: height)
        self.titleFrame = CGRect(x: leadingWidth, y: floor((height - titleSize.height) / 2), width: titleSize.width, height: titleSize.height)
        self.verificationFrame = verificationSize.map { size in
            return CGRect(x: 0, y: floor((height - size.height) / 2), width: size.width, height: size.height)
        }
        self.statusFrame = statusSize.map { size in
            return CGRect(x: leadingWidth + titleSize.width + statusSpacing, y: floor((height - size.height) / 2), width: size.width, height: size.height)
        }
    }
}
