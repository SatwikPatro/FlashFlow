import SwiftUI

// MARK: - App Theme
struct FlashFlowTheme {
    // Deck palette for auto-assignment
    static let deckColors: [String] = [
        "#6366F1", "#8B5CF6", "#EC4899", "#F43F5E",
        "#F97316", "#EAB308", "#22C55E", "#14B8A6",
        "#06B6D4", "#3B82F6", "#A855F7", "#D946EF"
    ]
}

// MARK: - Color Hex Extension
extension Color {
    init(hexString: String) {
        let hex = hexString.replacingOccurrences(of: "#", with: "")
        guard hex.count == 6,
              let value = UInt32(hex, radix: 16) else {
            self.init(.gray)
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
