import SwiftUI
import SwiftData
import Charts
import PhotosUI
import CoreLocation

struct TrekDetailView: View {
    @Bindable var trek: Trek
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mapLayer") private var layerRaw = MapLayer.topo.rawValue
    @AppStorage("trails") private var trails = true
    @State private var cursor: CLLocationCoordinate2D?
    @State private var editing = false
    @State private var sharing = false
    @State private var confirmDelete = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var openPhoto: TrekPhoto?
    @State private var mapFull = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if trek.hasTrack {
                    ZStack(alignment: .topTrailing) {
                        TrekMapView(tracks: [MapTrack(trek: trek, withSummit: true)], layer: MapLayer(rawValue: layerRaw) ?? .topo,
                                    showTrails: trails, cursor: cursor)
                        .frame(height: 380)
                        LayerMenu(layerRaw: $layerRaw, trails: $trails).padding(12).padding(.top, 50)
                    }
                }
                VStack(alignment: .leading, spacing: 22) {
                    header
                    StatGrid(columns: 3) {
                        StatCell(value: Fmt.km(trek.distance), unit: "km", label: "Distanza")
                        StatCell(value: Fmt.m(trek.gain), unit: "m", label: "Dislivello +")
                        StatCell(value: Fmt.dur(trek.timeInMotion), label: trek.moving > 0 ? "In movimento" : "Durata")
                        StatCell(value: Fmt.m(trek.maxEle), unit: "m", label: "Quota max")
                        StatCell(value: trek.loss > 0 ? Fmt.m(trek.loss) : "–", unit: "m", label: "Dislivello −")
                        StatCell(value: vam.map { Fmt.m($0) } ?? "–", unit: "m/h", label: "Vel. salita")
                    }
                    if trek.hasTrack, trek.track.contains(where: { $0.ele != nil }) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("Profilo").sectionTitle(); Spacer(); Text("Colore = pendenza").font(.caption).foregroundStyle(.secondary) }
                            ElevationProfile(track: trek.track, cursor: $cursor).padding(14).cardStyle()
                        }
                    }
                    photos
                    if !trek.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Note").sectionTitle()
                            Text(trek.notes).frame(maxWidth: .infinity, alignment: .leading).padding(16).cardStyle()
                        }
                    }
                    footer
                }
                .padding(16)
                .padding(.top, trek.hasTrack ? -40 : 0)
            }
        }
        .background(Theme.ground)
        .ignoresSafeArea(edges: trek.hasTrack ? .top : [])
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                Menu {
                    Button { editing = true } label: { Label("Modifica", systemImage: "pencil") }
                    if trek.hasTrack, let url = try? GPXWriter.fileURL(for: trek) {
                        ShareLink(item: url) { Label("Esporta GPX", systemImage: "arrow.down.doc") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $editing) { NavigationStack { TrekEditView(trek: trek, isNew: false) } }
        .sheet(isPresented: $sharing) { ShareSheet(trek: trek).presentationDetents([.large]) }
        .fullScreenCover(item: $openPhoto) { p in PhotoViewer(photo: p, trek: trek) }
        .confirmationDialog("Eliminare “\(trek.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) { context.delete(trek); dismiss() }
        } message: { Text("Traccia, note e foto verranno cancellate.") }
        .onChange(of: photoItems) { _, items in Task { await addPhotos(items) } }
    }

    private var vam: Double? { trek.moving > 0 && trek.gain > 0 ? trek.gain / (trek.moving / 3600) : nil }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DifficultyTag(d: trek.difficulty)
                Text(trek.difficulty.name).font(.footnote).foregroundStyle(.secondary)
                if trek.isExample { ExampleChip() }
            }
            Text(trek.name.isEmpty ? "Trekking senza nome" : trek.name).font(.display(40)).textCase(.uppercase).lineLimit(3).minimumScaleFactor(0.6)
            Text([trek.placeLine.isEmpty ? "Luogo non indicato" : trek.placeLine, Fmt.longDate(trek.date)].joined(separator: " · "))
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if trek.rating > 0 || !trek.companions.isEmpty {
                HStack(spacing: 12) {
                    if trek.rating > 0 { Stars(value: trek.rating) }
                    if !trek.companions.isEmpty { Text("con \(trek.companions)").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).cardStyle()
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Foto").sectionTitle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(trek.photos.sorted { $0.order < $1.order }) { p in
                    Button { openPhoto = p } label: {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                            .overlay { if let img = UIImage(data: p.data) { Image(uiImage: img).resizable().scaledToFill() } }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                PhotosPicker(selection: $photoItems, matching: .images) {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(style: .init(lineWidth: 1.5, dash: [5]))
                        .foregroundStyle(.secondary.opacity(0.5)).aspectRatio(1, contentMode: .fit)
                        .overlay { Label("Aggiungi", systemImage: "plus").font(.footnote.weight(.bold)).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { sharing = true } label: { Label("Condividi", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).frame(height: 30) }
                .buttonStyle(.borderedProminent)
            Text(footnote).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var footnote: String {
        var bits: [String] = []
        if trek.source == .health { bits.append("Importato da Salute.") }
        if let f = trek.fileName { bits.append("Importato da \(f).") }
        if let t = trek.track.first?.time { bits.append("Partenza alle \(Fmt.clock(t)).") }
        if trek.duration > trek.moving, trek.moving > 0 { bits.append("Tempo totale con soste \(Fmt.dur(trek.duration)).") }
        return bits.joined(separator: " ")
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        var order = trek.photos.count
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                  let jpg = img.resized(maxSide: 2000).jpegData(compressionQuality: 0.82) else { continue }
            let p = TrekPhoto(data: jpg, order: order); order += 1
            p.trek = trek; context.insert(p)
        }
        photoItems = []
    }
}

struct Stars: View {
    let value: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in Image(systemName: "star.fill").foregroundStyle(i <= value ? Theme.red : Color.primary.opacity(0.15)) }
        }.font(.caption).accessibilityLabel("\(value) su 5")
    }
}

struct LayerMenu: View {
    @Binding var layerRaw: String
    @Binding var trails: Bool
    var body: some View {
        Menu {
            Picker("Mappa", selection: $layerRaw) { ForEach(MapLayer.allCases) { Text($0.label).tag($0.rawValue) } }
            Toggle("Sentieri escursionistici", isOn: $trails)
        } label: {
            Image(systemName: "square.3.layers.3d").font(.body.weight(.semibold)).frame(width: 40, height: 40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Profilo altimetrico colorato per pendenza; trascinando si muove il cursore sulla mappa.
struct ElevationProfile: View {
    let track: [TrackPoint]
    @Binding var cursor: CLLocationCoordinate2D?
    @State private var data: [Sample] = []
    @State private var selected: Sample?

    struct Sample: Identifiable { let id: Int; let km: Double; let ele: Double; let grade: Double; let coord: CLLocationCoordinate2D }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let s = selected {
                    Text("km **\(s.km.formatted(.number.precision(.fractionLength(1))))** · quota **\(Fmt.m(s.ele)) m**")
                    Spacer()
                    Text("pendenza **\(Int((s.grade * 100).rounded()))%**")
                } else { Text("Trascina sul grafico") }
            }
            .font(.footnote).foregroundStyle(.secondary).frame(height: 18)
            Chart {
                ForEach(data) { s in
                    AreaMark(x: .value("km", s.km), yStart: .value("base", yDomain.lowerBound), yEnd: .value("quota", s.ele))
                        .foregroundStyle(Theme.red.opacity(0.12))
                }
                // un segmento per coppia di punti, così ogni tratto ha il colore della sua pendenza
                ForEach(Array(zip(data, data.dropFirst())), id: \.0.id) { pair in
                    let a = pair.0, b = pair.1
                    LineMark(x: .value("km", a.km), y: .value("quota", a.ele), series: .value("seg", a.id))
                        .foregroundStyle(Theme.grade(b.grade))
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round))
                    LineMark(x: .value("km", b.km), y: .value("quota", b.ele), series: .value("seg", a.id))
                        .foregroundStyle(Theme.grade(b.grade))
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round))
                }
                if let s = selected {
                    RuleMark(x: .value("km", s.km)).foregroundStyle(.primary.opacity(0.4)).lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("km", s.km), y: .value("quota", s.ele)).foregroundStyle(.primary).symbolSize(50)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text("\(d.formatted()) km") } } } }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 190)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                guard let plot = proxy.plotFrame else { return }
                                let x = g.location.x - geo[plot].origin.x
                                guard let km: Double = proxy.value(atX: x) else { return }
                                let s = data.min { abs($0.km - km) < abs($1.km - km) }
                                selected = s; cursor = s?.coord
                            }
                            .onEnded { _ in selected = nil; cursor = nil })
                }
            }
        }
        .task(id: track.count) { data = Self.samples(track) }
    }

    private var yDomain: ClosedRange<Double> {
        let e = data.map(\.ele)
        guard let lo = e.min(), let hi = e.max() else { return 0...100 }
        return (floor((lo - 20) / 100) * 100)...(ceil((hi + 20) / 100) * 100)
    }

    static func samples(_ pts: [TrackPoint]) -> [Sample] {
        let cum = TrackMath.cumulative(pts)
        let ele = TrackMath.smoothedElevation(pts, window: 2)
        let grades = TrackMath.grades(pts, cum: cum, ele: ele)
        let step = max(1, pts.count / 400)
        return stride(from: 0, to: pts.count, by: step).compactMap { i in
            guard let e = ele[i] else { return nil }
            return Sample(id: i, km: cum[i] / 1000, ele: e, grade: grades[i], coord: pts[i].coordinate)
        }
    }
}

struct PhotoViewer: View {
    let photo: TrekPhoto
    let trek: Trek
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = UIImage(data: photo.data) { Image(uiImage: img).resizable().scaledToFit() }
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    if let img = UIImage(data: photo.data) {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview(trek.name, image: Image(uiImage: img))) { Label("Condividi", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { context.delete(photo); dismiss() } label: { Label("Elimina", systemImage: "trash") }
                    Button("Chiudi") { dismiss() }
                }
                .buttonStyle(.bordered).tint(.white).padding()
            }
        }
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let s = min(1, maxSide / max(size.width, size.height))
        guard s < 1 else { return self }
        let newSize = CGSize(width: size.width * s, height: size.height * s)
        return UIGraphicsImageRenderer(size: newSize).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
