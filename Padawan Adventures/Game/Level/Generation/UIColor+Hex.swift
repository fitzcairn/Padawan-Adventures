import Foundation
import UIKit
import Yams

extension UIColor {
    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA` hex strings.
    nonisolated convenience init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 3 || raw.count == 6 || raw.count == 8,
              let value = UInt64(raw, radix: 16) else {
            return nil
        }

        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat

        switch raw.count {
        case 3:
            r = CGFloat((value >> 8) & 0xF) / 15
            g = CGFloat((value >> 4) & 0xF) / 15
            b = CGFloat(value & 0xF) / 15
            a = 1
        case 6:
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        default:
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
