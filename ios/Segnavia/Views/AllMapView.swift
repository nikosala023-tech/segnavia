import SwiftUI
import SwiftData

/// Tutte le tracce su una mappa; tocca una traccia per vederla.
struct AllMapView: View {
    @Query(sort: \Trek.date, order: .reverse) private var treks: [Trek]
    @AppStorage("mapLayer") private var layerRaw = MapLayer.topo.rawValue
    @AppStorage("trails") private var trails = true
    @State private var selected: UUID?
    @State private var path = NavigationPath()

    private var withTrack: [Trek] { treks.filter(\.hasTrack) }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                TrekMapView(tracks: withTrack.map { MapTrack(trek: $0) }, layer: MapLayer(rawValue: layerRaw) ?? .topo,
                            showTrails: trails, selected: selected, showsUser: true,
                            edgePadding: .init(top: 80, left: 40, bottom: 160, right: 40)) { id in
                    withAnimation(.snappy) { selected = id }
                }
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .topTrailing) { LayerMenu(layerRaw: $layerRaw, trails: $trails).padding(12) }

                if let t = withTrack.first(where: { $0.id == selected }) {
                    NavigationLink(value: t) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.headline).lineLimit(1)
                                Text("\(Fmt.date(t.date)) · \(Fmt.km(t.distance)) km · ↑\(Fmt.m(t.gain)) m").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Apri").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.red, in: Capsule())
                        }
                        .padding(14).cardStyle().padding(12)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if withTrack.isEmpty {
                    Text("Le tracce dei tuoi trekking appariranno qui.").font(.subheadline)
                        .padding(14).frame(maxWidth: .infinity).cardStyle().padding(12)
                }
            }
            .navigationDestination(for: Trek.self) { TrekDetailView(trek: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
