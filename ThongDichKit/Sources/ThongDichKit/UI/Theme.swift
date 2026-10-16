import SwiftUI

/// Colors and type styles. Every color adapts to Light and Dark mode.
enum Theme {
    static func accent(_ mode: TranslationMode) -> Color {
        switch mode {
        case .everyday: return Color(light: rgb(0.00, 0.55, 0.52), dark: rgb(0.25, 0.82, 0.76))
        case .work: return Color(light: rgb(0.27, 0.33, 0.86), dark: rgb(0.52, 0.58, 1.00))
        case .mass: return Color(light: rgb(0.62, 0.40, 0.08), dark: rgb(0.93, 0.74, 0.36))
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func gradient(_ mode: TranslationMode) -> LinearGradient {
        let c = accent(mode)
        return LinearGradient(colors: [c.opacity(0.95), c.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let subtle = Color(uiColor: .tertiarySystemFill)
    static let secondaryText = Color(uiColor: .secondaryLabel)

    /// Font for the Vietnamese text: serif for Mass (reverent), rounded for everyday, default for work.
    static func vietnameseFont(_ mode: TranslationMode, scale: Double, large: Bool = false) -> Font {
        let size = (large ? 34 : 22) * scale
        switch mode {
        case .mass: return .system(size: size, weight: .semibold, design: .serif)
        case .everyday: return .system(size: size, weight: .semibold, design: .rounded)
        case .work: return .system(size: size, weight: .semibold, design: .default)
        }
    }

    static func sourceFont(scale: Double) -> Font {
        .system(size: 15 * max(0.85, min(scale, 1.4)), weight: .regular)
    }
}

extension Color {
    /// A color with separate Light and Dark appearances.
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Rounded card container used throughout the app.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Small capsule label.
struct Chip: View {
    var icon: String?
    var text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.caption.weight(.semibold)) }
            Text(text).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
