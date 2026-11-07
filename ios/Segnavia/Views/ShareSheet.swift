import SwiftUI

/// Card 4:5 per storie e chat: traccia, profilo, nome e numeri.
struct ShareCard: View {
    let trek: Trek
    private let ink = Color(red: 0.07, green: 0.09, blue: 0.08)
    private let paper = Color(red: 0.95, green: 0.95, blue: 0.93)
    private let red = Color(red: 0.88, green: 0.15, blue: 0.18)

    var body: some View {
        ZStack(alignment: .topLeading) {
            ink
            Canvas { ctx, size in
                for r in stride(from: 60.0, to: 1500, by: 46) {
                    let rect = CGRect(x: 780 - r * 1.15, y: 360 - r * 0.8, width: r * 2.3, height: r * 1.6)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.06)), lineWidth: 2)
                }
                let pts = trek.track
                guard pts.count > 1 else { return }
                let xy = Projection.fit(pts, in: CGSize(width: size.width, height: 760), padding: 110, maxPoints: 1500).map { CGPoint(x: $0.x, y: $0.y + 70) }
                var p = Path(); p.addLines(xy)
                ctx.stroke(p, with: .color(.white), style: .init(lineWidth: 20, lineCap: .round, lineJoin: .round))
                ctx.stroke(p, with: .color(red), style: .init(lineWidth: 10, lineCap: .round, lineJoin: .round))
                let s = xy[0]
                let dot = Path(ellipseIn: CGRect(x: s.x - 16, y: s.y - 16, width: 32, height: 32))
                ctx.fill(dot, with: .color(Theme.startGreen)); ctx.stroke(dot, with: .color(.white), lineWidth: 6)
                // profilo
                let ele = pts.compactMap(\.ele)
                if let lo = ele.min(), let hi = ele.max() {
                    let cum = TrackMath.cumulative(pts); let total = max(cum.last ?? 1, 1)
                    var prof = Path(); prof.move(to: CGPoint(x: 80, y: 960))
                    for (i, pt) in pts.enumerated() { if let e = pt.ele { prof.addLine(to: CGPoint(x: 80 + cum[i] / total * (size.width - 160), y: 960 - (e - lo) / max(1, hi - lo) * 100)) } }
                    prof.addLine(to: CGPoint(x: size.width - 80, y: 960)); prof.closeSubpath()
                    ctx.fill(prof, with: .color(red.opacity(0.28)))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 16) {
                    VStack(spacing: 0) { red; Color.white; red }.frame(width: 64, height: 54)
                    Text("SEGNAVIA").font(.system(size: 34, weight: .heavy).width(.condensed)).foregroundStyle(paper)
                    Spacer()
                    Text(Fmt.date(trek.date)).font(.system(size: 30, weight: .semibold)).foregroundStyle(paper.opacity(0.7))
                }
                Spacer()
                Text(trek.name.uppercased()).font(.system(size: 92, weight: .heavy).width(.condensed)).foregroundStyle(paper)
                    .lineLimit(2).minimumScaleFactor(0.55).lineSpacing(-10)
                Text(trek.placeLine.replacingOccurrences(of: " · ", with: ", ")).font(.system(size: 30, weight: .semibold)).foregroundStyle(paper.opacity(0.7))
                    .padding(.top, 6)
                HStack(alignment: .top, spacing: 0) {
                    cell(Fmt.km(trek.distance), "KM")
                    cell(Fmt.m(trek.gain), "M D+")
                    cell(Fmt.dur(trek.timeInMotion).replacingOccurrences(of: " ", with: ""), "TEMPO")
                    cell(Fmt.m(trek.maxEle), "M QUOTA MAX")
                }
                .padding(.top, 44)
            }
            .padding(80)
        }
        .frame(width: 1080, height: 1350)
    }

    private func cell(_ v: String, _ k: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).font(.system(size: 70, weight: .heavy).width(.condensed)).foregroundStyle(paper).lineLimit(1).minimumScaleFactor(0.5)
            Text(k).font(.system(size: 22, weight: .heavy)).foregroundStyle(red)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor static func render(_ trek: Trek) -> UIImage? {
        let r = ImageRenderer(content: ShareCard(trek: trek))
        r.scale = 1
        return r.uiImage
    }
}

struct ShareSheet: View {
    let trek: Trek
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    private var summary: String {
        var s = "⛰️ \(trek.name)\n📍 \(trek.placeLine.replacingOccurrences(of: " · ", with: ", ")) · \(Fmt.date(trek.date))\n"
        s += "\(Fmt.km(trek.distance)) km · ↑\(Fmt.m(trek.gain)) m · \(Fmt.dur(trek.timeInMotion))"
        if let m = trek.maxEle { s += " · quota max \(Fmt.m(m)) m" }
        return s + "\nDifficoltà \(trek.difficulty.rawValue)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Group {
                        if let image { Image(uiImage: image).resizable().scaledToFit() }
                        else { ProgressView().frame(height: 300) }
                    }
                    .frame(maxWidth: 260).clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

                    if let image {
                        let img = Image(uiImage: image)
                        ShareLink(item: img, preview: SharePreview(trek.name, image: img)) {
                            row("photo", "Card con mappa e numeri", "Per storie Instagram, WhatsApp, Messaggi")
                        }
                    }
                    if trek.hasTrack, let url = try? GPXWriter.fileURL(for: trek) {
                        ShareLink(item: url) { row("arrow.down.doc", "Traccia GPX", "Per chi vuole rifare il giro con Komoot, Garmin, Strava") }
                    }
                    ShareLink(item: summary) { row("text.alignleft", "Testo riassuntivo", "Nome, luogo e numeri") }
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("Condividi").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fatto") { dismiss() } } }
            .task { image = ShareCard.render(trek) }
        }
    }

    private func row(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.red)
                .frame(width: 46, height: 46).background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(desc).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14).cardStyle()
    }
}
