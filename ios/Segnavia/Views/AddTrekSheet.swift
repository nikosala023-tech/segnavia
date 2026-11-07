import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Foglio "+": Salute, file GPX, registrazione, a mano.
struct AddTrekSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()
    @State private var importingFile = false
    @State private var error: String?
    @State private var newTrek: Trek?

    enum Route: Hashable { case health, record }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: -4) {
                        Text("Nuovo").font(.display(46)).textCase(.uppercase)
                        Text("trekking").font(.display(46)).textCase(.uppercase).foregroundStyle(Theme.red)
                    }.padding(.bottom, 8)
                    choice("heart.fill", "Importa da Salute", "I tuoi allenamenti di escursionismo e camminata con il percorso GPS. Anche da Apple Watch e dalle app collegate a Salute.") { path.append(Route.health) }
                    choice("doc.badge.plus", "Importa file GPX o TCX", "Da Garmin Connect, Strava, Komoot, Wikiloc. Anche più file insieme.") { importingFile = true }
                    choice("record.circle", "Registra adesso", "Traccia GPS anche con lo schermo spento.") { path.append(Route.record) }
                    choice("pencil.line", "Inserisci a mano", "Senza traccia: nome, luogo, km e dislivello.") {
                        let t = Trek(); context.insert(t); newTrek = t
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.red).padding(.top, 4) }
                }
                .padding(16)
            }
            .background(Theme.ground)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .navigationDestination(for: Route.self) { r in
                switch r {
                case .health: HealthImportView { dismiss() }
                case .record: RecordView { t in newTrek = t }
                }
            }
            .navigationDestination(item: $newTrek) { t in
                TrekEditView(trek: t, isNew: true) { saved in app.openTrek = saved; dismiss() }
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, UTType(filenameExtension: "tcx") ?? .xml, .xml],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .task {
            if let url = app.incomingFile { app.incomingFile = nil; importFiles([url]) }
        }
    }

    private func choice(_ icon: String, _ title: String, _ desc: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.red)
                    .frame(width: 48, height: 48).background(Theme.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(desc).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16).cardStyle()
        }.buttonStyle(.plain)
    }

    private func importFiles(_ urls: [URL]) {
        error = nil
        var made: [Trek] = []; var errs: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let parsed = try TrackFileParser.parse(data: data, fileName: url.lastPathComponent)
                let t = TrekFactory.make(points: parsed.points, name: parsed.name, source: .gpx, fileName: url.lastPathComponent)
                context.insert(t); made.append(t)
            } catch { errs.append(error.localizedDescription) }
        }
        if made.count == 1 { newTrek = made[0] }
        else if made.count > 1 {
            Task { for t in made { await TrekFactory.fillPlace(t) }; try? context.save() }
            dismiss()
        }
        if !errs.isEmpty { error = errs.joined(separator: "\n") }
    }
}

/// Elenco degli allenamenti di Salute da importare.
struct HealthImportView: View {
    var onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Query private var treks: [Trek]
    @State private var items: [HealthCandidate] = []
    @State private var picked: Set<UUID> = []
    @State private var state: LoadState = .loading
    @State private var importing = false
    @State private var progress = 0

    enum LoadState { case loading, ready, unavailable, failed(String) }

    private var existing: Set<UUID> { Set(treks.compactMap(\.healthWorkoutID)) }

    var body: some View {
        Group {
            switch state {
            case .loading: ProgressView("Leggo Salute…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable: message("Salute non è disponibile su questo dispositivo.")
            case .failed(let m): message(m)
            case .ready:
                if items.isEmpty {
                    message("Nessun allenamento di escursionismo o camminata trovato. Se non vedi nulla, controlla in Impostazioni → Salute → Accesso ai dati → Segnavia che la lettura di Allenamenti e Percorsi sia attiva.")
                } else { list }
            }
        }
        .background(Theme.ground)
        .navigationTitle("Da Salute")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var list: some View {
        List {
            Section {
                ForEach(items) { c in
                    let done = existing.contains(c.id)
                    Button { toggle(c.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: picked.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(picked.contains(c.id) ? Theme.red : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Fmt.longDate(c.start)).font(.subheadline.weight(.semibold))
                                Text("\(c.isHiking ? "Escursionismo" : "Camminata") · \(Fmt.km(c.distance)) km\(c.ascent.map { " · ↑\(Fmt.m($0)) m" } ?? "") · \(Fmt.dur(c.duration))")
                                    .font(.footnote).foregroundStyle(.secondary)
                                if done { Text("Già nel diario").font(.caption.weight(.bold)).foregroundStyle(Theme.red) }
                            }
                        }
                    }
                    .buttonStyle(.plain).disabled(done).opacity(done ? 0.5 : 1)
                }
            } header: {
                Text("Ho selezionato quelli che sembrano trekking: escursionismo, o camminate con più di 200 m di dislivello.")
                    .textCase(nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await importPicked() }
            } label: {
                Text(importing ? "Importo \(progress)/\(picked.count)…" : "Importa \(picked.count) trekking").frame(maxWidth: .infinity).frame(height: 34)
            }
            .buttonStyle(.borderedProminent).disabled(picked.isEmpty || importing)
            .padding(16).background(.bar)
        }
    }

    private func message(_ m: String) -> some View {
        Text(m).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(_ id: UUID) { if picked.contains(id) { picked.remove(id) } else { picked.insert(id) } }

    private func load() async {
        let hs = HealthService.shared
        guard hs.isAvailable else { state = .unavailable; return }
        do {
            try await hs.requestAuthorization()
            let since = Calendar.current.date(byAdding: .year, value: -5, to: .now) ?? .distantPast
            items = try await hs.candidates(since: since)
            picked = Set(items.filter { $0.looksLikeTrek && !existing.contains($0.id) }.map(\.id))
            state = .ready
        } catch { state = .failed("Non riesco a leggere Salute: \(error.localizedDescription)") }
    }

    private func importPicked() async {
        importing = true; progress = 0
        for c in items where picked.contains(c.id) {
            progress += 1
            let pts = (try? await HealthService.shared.route(for: c.workout)) ?? []
            let t: Trek
            if pts.count > 1 {
                t = TrekFactory.make(points: pts, name: "", source: .health, healthID: c.id)
                t.duration = c.duration
                if let a = c.ascent, a > 0 { t.gain = a }   // il dislivello del barometro è più preciso del GPS
            } else {
                t = Trek(date: c.start, distance: c.distance, gain: c.ascent ?? 0, duration: c.duration, moving: c.duration, source: .health, healthWorkoutID: c.id)
            }
            context.insert(t)
            await TrekFactory.fillPlace(t)
            if t.name.isEmpty { t.name = "Trekking del \(Fmt.date(c.start))" }
        }
        try? context.save()
        importing = false
        onDone()
    }
}
