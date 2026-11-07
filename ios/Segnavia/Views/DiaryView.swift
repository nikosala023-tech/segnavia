import SwiftUI
import SwiftData

struct Totals {
    var count = 0, distance = 0.0, gain = 0.0, time = 0.0, maxEle = 0.0
    init(_ treks: [Trek]) {
        count = treks.count
        for t in treks { distance += t.distance; gain += t.gain; time += t.timeInMotion; maxEle = max(maxEle, t.maxEle ?? 0) }
    }
}

struct YearPicker: View {
    let years: [String]
    @Binding var selection: String
    var body: some View {
        if years.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["Tutti"] + years, id: \.self) { y in
                        Button { withAnimation(.snappy) { selection = y } } label: {
                            Text(y).font(.subheadline.weight(.bold))
                                .padding(.horizontal, 14).frame(height: 32)
                                .foregroundStyle(selection == y ? Color(uiColor: .systemBackground) : .secondary)
                                .background(selection == y ? Color.primary : .clear, in: Capsule())
                                .overlay(Capsule().stroke(Color.primary.opacity(selection == y ? 0 : 0.15)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

extension Array where Element == Trek {
    var years: [String] { Set(map { String(Calendar.current.component(.year, from: $0.date)) }).sorted(by: >) }
    func inYear(_ y: String) -> [Trek] { y == "Tutti" ? self : filter { String(Calendar.current.component(.year, from: $0.date)) == y } }
}

struct DiaryView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Trek.date, order: .reverse) private var treks: [Trek]
    @AppStorage("year") private var year = "Tutti"
    @State private var search = ""
    @State private var path = NavigationPath()

    private var list: [Trek] { treks.inYear(year) }
    private var shown: [Trek] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { [$0.name, $0.location, $0.region, $0.notes, $0.companions].joined(separator: " ").lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if treks.contains(where: \.isExample) { exampleNote }
                    HStack(alignment: .firstTextBaseline) {
                        Text("Uscite").sectionTitle()
                        Spacer()
                        Text("\(shown.count) trekking").font(.footnote).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                    if shown.isEmpty { EmptyDiary() }
                    LazyVStack(spacing: 12) {
                        ForEach(shown) { t in
                            NavigationLink(value: t) { TrekRow(trek: t) }.buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { context.delete(t) } label: { Label("Elimina", systemImage: "trash") }
                                }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 90)
            }
            .background(Theme.ground)
            .searchable(text: $search, prompt: "Nome, luogo, compagni")
            .navigationDestination(for: Trek.self) { TrekDetailView(trek: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) { TrailMark(); Text("SEGNAVIA").font(.display(22)) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottomTrailing) { AddButton() }
            .onChange(of: app.openTrek) { _, t in if let t { path.append(t); app.openTrek = nil } }
        }
    }

    private var hero: some View {
        let tot = Totals(list)
        let label = year == "Tutti" ? "in totale" : "nel \(year)"
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: -4) {
                Text(tot.count > 0 ? "\(Fmt.m(tot.gain)) metri" : "Il tuo diario").font(.display(48)).textCase(.uppercase)
                Text(tot.count > 0 ? "saliti \(label)" : "di montagna").font(.display(48)).textCase(.uppercase).foregroundStyle(Theme.red)
            }
            .minimumScaleFactor(0.6).lineLimit(1)
            YearPicker(years: treks.years, selection: $year)
            StatGrid(columns: 2) {
                StatCell(value: "\(tot.count)", label: "Uscite", size: 32)
                StatCell(value: Fmt.km(tot.distance), unit: "km", label: "Distanza", size: 32)
                StatCell(value: "\(Int(tot.time / 3600))", unit: "h", label: "In cammino", size: 32)
                StatCell(value: Fmt.m(tot.maxEle), unit: "m", label: "Quota max", size: 32)
            }
        }
        .padding(.top, 8)
    }

    private var exampleNote: some View {
        HStack(spacing: 12) {
            (Text("Dati di esempio. ").bold().foregroundColor(Theme.red) + Text("Quattro uscite finte per mostrarti l'app."))
                .font(.footnote)
            Spacer(minLength: 0)
            Button("Elimina") { withAnimation { treks.filter(\.isExample).forEach(context.delete) } }
                .font(.footnote.weight(.bold)).buttonStyle(.bordered)
        }
        .padding(14).background(Theme.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct AddButton: View {
    @Environment(AppState.self) private var app
    var body: some View {
        Button { app.showAdd = true } label: {
            Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.red, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: Theme.red.opacity(0.4), radius: 12, y: 6)
        }
        .accessibilityLabel("Aggiungi trekking")
        .padding(20)
    }
}

struct TrekRow: View {
    let trek: Trek
    var body: some View {
        HStack(spacing: 14) {
            TrackThumbnail(trek: trek).frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    DifficultyTag(d: trek.difficulty)
                    Text(Fmt.date(trek.date)).font(.footnote).foregroundStyle(.secondary)
                    if trek.isExample { ExampleChip() }
                }
                Text(trek.name.isEmpty ? "Trekking senza nome" : trek.name).font(.headline.weight(.heavy)).lineLimit(2)
                Text(trek.placeLine.isEmpty ? "—" : trek.placeLine).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 14) {
                    small(Fmt.km(trek.distance), "km")
                    small("↑" + Fmt.m(trek.gain), "m")
                    small(Fmt.dur(trek.timeInMotion), "")
                }.padding(.top, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .cardStyle()
    }
    private func small(_ v: String, _ u: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(v).font(.display(19, weight: .semibold)).monospacedDigit()
            if !u.isEmpty { Text(u).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
        }
    }
}

/// Miniatura disegnata della traccia, su curve di livello.
struct TrackThumbnail: View {
    let trek: Trek
    var body: some View {
        Canvas { ctx, size in
            for r in stride(from: 18.0, through: 66, by: 14) {
                ctx.stroke(Path(ellipseIn: CGRect(x: size.width * 0.73 - r, y: size.height * 0.27 - r, width: 2 * r, height: 2 * r)),
                           with: .color(.primary.opacity(0.08)), lineWidth: 1)
            }
            let pts = trek.track
            guard pts.count > 1 else {
                var m = Path(); m.move(to: .init(x: 8, y: size.height - 14)); m.addLine(to: .init(x: size.width * 0.38, y: size.height * 0.4))
                m.addLine(to: .init(x: size.width * 0.52, y: size.height * 0.58)); m.addLine(to: .init(x: size.width * 0.68, y: size.height * 0.3))
                m.addLine(to: .init(x: size.width - 8, y: size.height - 14)); m.closeSubpath()
                ctx.fill(m, with: .color(.primary.opacity(0.12))); return
            }
            let xy = Projection.fit(pts, in: size, padding: 12)
            var path = Path(); path.addLines(xy)
            ctx.stroke(path, with: .color(Theme.card), style: .init(lineWidth: 6, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(Theme.red), style: .init(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            let s = xy[0]
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - 3.5, y: s.y - 3.5, width: 7, height: 7)), with: .color(.primary))
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

enum Projection {
    /// Proiezione equirettangolare corretta per latitudine, centrata nel riquadro.
    static func fit(_ pts: [TrackPoint], in size: CGSize, padding: CGFloat, maxPoints: Int = 200) -> [CGPoint] {
        let step = Swift.max(1, pts.count / maxPoints)
        var s = stride(from: 0, to: pts.count, by: step).map { pts[$0] }; s.append(pts[pts.count - 1])
        let lats = s.map(\.lat), lons = s.map(\.lon)
        let (south, north, west, east) = (lats.min()!, lats.max()!, lons.min()!, lons.max()!)
        let k = cos((south + north) / 2 * .pi / 180)
        let dx = Swift.max((east - west) * k, 1e-6), dy = Swift.max(north - south, 1e-6)
        let sc = Swift.min((size.width - 2 * padding) / dx, (size.height - 2 * padding) / dy)
        let ox = (size.width - dx * sc) / 2, oy = (size.height - dy * sc) / 2
        return s.map { CGPoint(x: ox + ($0.lon - west) * k * sc, y: oy + (north - $0.lat) * sc) }
    }
}

struct EmptyDiary: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(spacing: 12) {
            TrailMark(width: 44)
            Text("Nessun trekking ancora").font(.headline)
            Text("Importa i tuoi allenamenti da Salute o un file GPX, oppure registra il prossimo giro.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Aggiungi il primo") { app.showAdd = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity).padding(28).cardStyle()
    }
}
