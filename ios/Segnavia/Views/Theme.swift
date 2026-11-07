import SwiftUI

enum Theme {
    static let red = Color("AccentColor")             // rosso segnavia CAI
    static let ground = Color("Ground")               // fondo granito
    static let card = Color("Card")
    static let startGreen = Color(red: 0.12, green: 0.62, blue: 0.35)

    static func difficulty(_ d: Difficulty) -> Color {
        switch d {
        case .T: Color(red: 0.24, green: 0.56, blue: 0.36)
        case .E: Color(red: 0.79, green: 0.54, blue: 0.07)
        case .EE: red
        case .EEA: .primary
        }
    }
    static func grade(_ g: Double) -> Color {
        let a = abs(g)
        return a < 0.10 ? difficulty(.T) : a < 0.20 ? difficulty(.E) : red
    }
}

extension Font {
    /// Numeri e titoli: SF condensato, come i cartelli dei sentieri.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

enum Fmt {
    static let it = Locale(identifier: "it_IT")
    static func km(_ m: Double) -> String { (m / 1000).formatted(.number.precision(.fractionLength(1)).locale(it)) }
    static func m(_ v: Double?) -> String { v.map { Int($0.rounded()).formatted(.number.locale(it)) } ?? "–" }
    static func dur(_ s: Double) -> String {
        guard s > 0 else { return "–" }
        let h = Int(s) / 3600, mi = (Int(s) % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", mi))" : "\(mi) min"
    }
    static func date(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).year().locale(it)) }
    static func longDate(_ d: Date) -> String { d.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(it)).capitalized(with: it) }
    static func clock(_ d: Date) -> String { d.formatted(.dateTime.hour().minute().locale(it)) }
}

/// Bandierina bianco-rossa dei sentieri CAI.
struct TrailMark: View {
    var width: CGFloat = 26
    var body: some View {
        VStack(spacing: 0) {
            Theme.red; Color.white; Theme.red
        }
        .frame(width: width, height: width * 0.75)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.08)))
    }
}

struct DifficultyTag: View {
    let d: Difficulty
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.difficulty(d)).frame(width: 9, height: 9)
            Text(d.rawValue).font(.display(15, weight: .bold))
        }
        .accessibilityLabel("Difficoltà \(d.name)")
    }
}

struct ExampleChip: View {
    var body: some View {
        Text("Esempio").font(.caption2.weight(.bold)).foregroundStyle(Theme.red)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.red.opacity(0.12), in: Capsule())
    }
}

/// Valore grande + unità piccola + etichetta.
struct StatCell: View {
    let value: String
    var unit: String = ""
    let label: String
    var size: CGFloat = 28
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.display(size)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.display(size * 0.5, weight: .semibold)).foregroundStyle(.secondary) }
            }
            Text(label.uppercased()).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card)
    }
}

/// Griglia di StatCell separate da linee sottili.
struct StatGrid<Content: View>: View {
    let columns: Int
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns), spacing: 1) { content }
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension View {
    func cardStyle() -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
    func sectionTitle() -> some View { font(.display(22, weight: .bold)).textCase(.uppercase) }
}
