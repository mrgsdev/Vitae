import AppKit
import SwiftUI

enum Theme {
    /// Фон рабочей области (как в «Здоровье» на Mac): светло-серый / почти чёрный.
    static let pageBackground = Color(nsColor: NSColor(name: "ht.page") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1)
            : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    })

    /// Фон карточек.
    static let cardBackground = Color(nsColor: NSColor(name: "ht.card") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.173, green: 0.173, blue: 0.18, alpha: 1)
            : NSColor.white
    })

    static let separator = Color.primary.opacity(0.08)
    static let cornerRadius: CGFloat = 12
    static let gridHeader = Color.primary.opacity(0.045)

    static func bigNumber(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

extension ResultStatus {
    var color: Color {
        switch self {
        case .inRange: .green
        case .below: .blue
        case .above: .orange
        case .outsideReference: .purple
        case .noReference: .gray
        case .pending: .secondary
        }
    }
}

extension ExaminationStatus {
    var color: Color {
        switch self {
        case .draft: .gray
        case .awaitingResults: .indigo
        case .completed: .green
        }
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Фон рабочей области раздела.
    func pageBackground() -> some View {
        background(Theme.pageBackground)
    }
}
