import SwiftUI

enum CaveGlyph: String, CaseIterable {
    case barcode = "CaveBarcode"
    case voice = "CaveVoice"
    case meal = "CaveMeal"
    case search = "CaveSearch"
    case plus = "CavePlus"
    case slash = "CaveSlash"
    case pencil = "CavePencil"
    case chevronLeft = "CaveChevronLeft"
    case chevronRight = "CaveChevronRight"
    case arrowRight = "CaveArrowRight"
    case arrowUpLeft = "CaveArrowUpLeft"
    case camera = "CaveCamera"
    case circle = "CaveCircle"
    case check = "CaveCheck"
    case lightning = "CaveLightning"
    case meals = "CaveMeals"
    case stop = "CaveStop"
    case cloud = "CaveCloud"
    case phone = "CavePhone"
    case warning = "CaveWarning"
    case gear = "CaveGear"
    case person = "CavePerson"
    case protein = "CaveProtein"
    case carbs = "CaveCarbs"
    case fat = "CaveFat"
}

/// Single-color vector artwork inherits its parent's foreground style in either appearance.
struct CaveIcon: View {
    let glyph: CaveGlyph
    var size: CGFloat = 24
    init(_ glyph: CaveGlyph, size: CGFloat = 24) { self.glyph = glyph; self.size = size }
    var body: some View {
        Image(glyph.rawValue).renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct CaveSearchAddIcon: View {
    var size: CGFloat = 20
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 0 : 3) {
            CaveIcon(.search, size: size)
            CaveIcon(.slash, size: size * 0.7)
                .frame(width: size * 0.35)
                .padding(.horizontal, compact ? 0 : 3)
            CaveIcon(.plus, size: size)
        }.accessibilityHidden(true)
    }
}

extension LoggingAction {
    var caveGlyph: CaveGlyph {
        switch self {
        case .barcode: .barcode
        case .voice: .voice
        case .image: .meal
        case .add: .plus
        }
    }
}

/// Shared, Dynamic Type-aware typography for app-owned text.
extension Font {
    static func cave(_ style: Font.TextStyle = .body) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 36
        case .title: size = 30
        case .title2: size = 25
        case .title3: size = 22
        case .headline, .body: size = 20
        case .subheadline, .callout: size = 18
        case .footnote: size = 15
        case .caption: size = 14
        case .caption2: size = 13
        @unknown default: size = 20
        }
        return .custom("Schoolbell-Regular", size: size, relativeTo: style)
    }
}

// Warm "cave" palette. Dark variants keep the same character without a bright cream screen at night.
extension Color {
    static let caveOrange = Color(light: (0.769, 0.325, 0.106), dark: (0.878, 0.420, 0.180))
    static let caveBackground = Color(light: (0.961, 0.925, 0.863), dark: (0.110, 0.086, 0.067))
    static let caveSurface = Color(light: (0.984, 0.965, 0.925), dark: (0.165, 0.133, 0.106))

    private init(light: (Double, Double, Double), dark: (Double, Double, Double)) {
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
