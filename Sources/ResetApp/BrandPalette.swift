import SwiftUI

/// The five approved ResetMe brand colors. System menus retain native appearance.
enum BrandPalette {
    static let olive = color(0x606c38)
    static let forest = color(0x283618)
    static let cream = color(0xfefae0)
    static let sand = color(0xdda15e)
    static let copper = color(0xbc6c25)
    private static func color(_ hex: Int) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
