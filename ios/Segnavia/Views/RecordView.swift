import SwiftUI
import SwiftData
import CoreLocation

struct RecordView: View {
    var onFinish: (Trek) -> Void
    @Environment(\.modelContext) private var context
    @State private var rec = Recorder()
    @State private var confirmDiscard = false
    @AppStorage("mapLayer") private var layerRaw = MapLayer.topo.rawValue
    private let recID = UUID()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let st = rec.stats
            VStack(spacing: 16) {
                TrekMapView(tracks: [MapTrack(id: recID, coords: rec.points.map(\.coordinate))], layer: MapLayer(rawValue: layerRaw) ?? .topo,
                            showsUser: true, follow: rec.state == .running)
                .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 8) {
                    if rec.state == .running { Circle().fill(Theme.red).frame(width: 10, height: 10) }
                    Text(clock(rec.elapsed)).font(.display(64)).monospacedDigit()
                }
                StatGrid(columns: 3) {
                    StatCell(value: Fmt.km(st.distance), unit: "km", label: "Distanza")
                    StatCell(value: Fmt.m(st.gain), unit: "m", label: "D+")
                    StatCell(value: Fmt.m(rec.points.last?.ele), unit: "m", label: "Quota")
                }
                Text(status).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                controls
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle("Registra")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(rec.state != .idle)
        .confirmationDialog("Scartare la registrazione?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Scarta", role: .destructive) { rec.reset() }
        }
    }

    private var status: String {
        if rec.authDenied { return "Permesso posizione negato: abilitalo in Impostazioni → Segnavia → Posizione." }
        if let a = rec.accuracy { return a > 40 ? "Segnale GPS debole (±\(Int(a)) m), aspetto…" : "GPS ok, precisione ±\(Int(a)) m. Puoi spegnere lo schermo." }
        return rec.state == .idle ? "La traccia continua a registrarsi anche con lo schermo spento." : "Cerco il segnale GPS…"
    }

    @ViewBuilder private var controls: some View {
        switch rec.state {
        case .idle:
            Button { rec.start() } label: { Label("Inizia a registrare", systemImage: "record.circle").frame(maxWidth: .infinity).frame(height: 36) }
                .buttonStyle(.borderedProminent)
        case .running:
            HStack {
                Button { rec.pause() } label: { Text("Pausa").frame(maxWidth: .infinity).frame(height: 36) }.buttonStyle(.bordered)
                Button { finish() } label: { Text("Termina").frame(maxWidth: .infinity).frame(height: 36) }.buttonStyle(.borderedProminent)
            }
        case .paused:
            VStack {
                HStack {
                    Button { rec.resume() } label: { Text("Riprendi").frame(maxWidth: .infinity).frame(height: 36) }.buttonStyle(.bordered)
                    Button { finish() } label: { Text("Termina e salva").frame(maxWidth: .infinity).frame(height: 36) }.buttonStyle(.borderedProminent)
                }
                Button("Scarta registrazione", role: .destructive) { confirmDiscard = true }.font(.footnote)
            }
        }
    }

    private func finish() {
        let (pts, moving) = rec.finish()
        guard pts.count > 1 else { return }
        let t = TrekFactory.make(points: pts, name: "", source: .recorded)
        if moving > 0 { t.moving = moving }
        context.insert(t)
        onFinish(t)
    }

    private func clock(_ s: TimeInterval) -> String {
        let i = Int(s); return String(format: "%02d:%02d:%02d", i / 3600, (i % 3600) / 60, i % 60)
    }
}
