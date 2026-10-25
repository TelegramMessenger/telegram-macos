import Foundation
import TGUIKit

public extension NSAttributedString {
    var referenceTrimmed: NSAttributedString {

        let string:NSMutableAttributedString = self.mutableCopy() as! NSMutableAttributedString

        while true {
            let range = string.string.nsstring.range(of: "\u{2028}")
            if range.location != NSNotFound {
                string.replaceCharacters(in: range, with: "\n")
            } else {
                break
            }
        }
        while true {
            let range = string.string.nsstring.range(of: "\u{fffc}", options: .literal)
            if range.location != NSNotFound {
                string.replaceCharacters(in: range, with: "\n")
            } else {
                break
            }
        }
        var range = string.string.nsstring.rangeOfCharacter(from: NSCharacterSet.whitespacesAndNewlines)
        while !string.string.isEmpty, range.location == 0 {
            string.replaceCharacters(in: NSMakeRange(0, 1), with: "")
            range = string.string.nsstring.rangeOfCharacter(from: NSCharacterSet.whitespacesAndNewlines)
        }
        while !string.string.isEmpty, string.string.rangeOfCharacter(from: NSCharacterSet.whitespacesAndNewlines, options: [], range: string.string.index(string.string.endIndex, offsetBy: -1) ..< string.string.endIndex) != nil {
            string.replaceCharacters(in: NSMakeRange(string.string.length - 1, 1), with: "")
        }

        return string
    }

    var referenceTrimNewLinesToSpace: NSAttributedString {
        return referenceReplaceNewlinesWithSpaces(in: self)
    }

    func referenceReplaceNewlinesWithSpaces(in attributedString: NSAttributedString) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)

        let range = NSRange(location: 0, length: mutableAttributedString.length)
        let newlineRegex = try! NSRegularExpression(pattern: "\\n")
        newlineRegex.replaceMatches(in: mutableAttributedString.mutableString, options: [], range: range, withTemplate: " ")

        return mutableAttributedString
    }

}
