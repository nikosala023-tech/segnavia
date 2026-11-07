import SwiftUI
import SwiftData

/// Modifica (o completa dopo un import) un trekking.
struct TrekEditView: View {
    @Bindable var trek: Trek
    let isNew: Bool
    var onSaved: ((Trek) -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var hours = ""
    @State private var minutes = ""
    @State private var km = ""
    @State private var gain = ""
    @State private var maxEle = ""

    var body: some View {
        Form {
            if trek.hasTrack {
                Section {
                    HStack(spacing: 12) {
                        TrackThumbnail(trek: trek).frame(width: 64, height: 64)
                        VStack(alignment: .leading) {
                            Text("\(Fmt.km(trek.distance)) km · ↑\(Fmt.m(trek.gain)) m").font(.headline)
                            Text("\(trek.track.count) punti GPS · quota max \(Fmt.m(trek.maxEle)) m").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Il giro") {
                TextField("Nome, es. Anello del Lago di Braies", text: $trek.name)
                TextField("Località", text: $trek.location)
                TextField("Zona o regione", text: $trek.region)
                DatePicker("Data", selection: $trek.date, displayedComponents: .date)
            }
            Section("Difficoltà (scala CAI)") {
                HStack(spacing: 6) {
                    ForEach(Difficulty.allCases) { d in
                        Button { trek.difficulty = d } label: {
                            VStack(spacing: 0) {
                                Text(d.rawValue).font(.display(20, weight: .bold))
                                Text(d.short).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 12).fill(trek.difficulty == d ? Theme.difficulty(d).opacity(0.14) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(trek.difficulty == d ? Theme.difficulty(d) : Color.primary.opacity(0.12), lineWidth: trek.difficulty == d ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(.init(top: 10, leading: 12, bottom: 10, trailing: 12))
                HStack {
                    Text("Voto")
                    Spacer()
                    ForEach(1...5, id: \.self) { i in
                        Button { trek.rating = trek.rating == i ? 0 : i } label: {
                            Image(systemName: "star.fill").font(.title3).foregroundStyle(i <= trek.rating ? Theme.red : Color.primary.opacity(0.15))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Section("Numeri") {
                if !trek.hasTrack {
                    field("Km", $km, .decimalPad)
                    field("Dislivello positivo (m)", $gain, .numberPad)
                    field("Quota massima (m)", $maxEle, .numberPad)
                }
                HStack {
                    Text("Tempo di cammino")
                    Spacer()
                    TextField("ore", text: $hours).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 50)
                    Text("h").foregroundStyle(.secondary)
                    TextField("min", text: $minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 50)
                    Text("min").foregroundStyle(.secondary)
                }
            }
            Section("Ricordi") {
                TextField("Con chi, es. Giulia, Marco", text: $trek.companions)
                TextField("Note: sentiero, rifugio, condizioni", text: $trek.notes, axis: .vertical).lineLimit(4...10)
            }
        }
        .navigationTitle(isNew ? "Nuovo trekking" : "Modifica")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { if isNew { context.delete(trek) }; dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() }.bold() }
        }
        .onAppear(perform: load)
        .task { if isNew { await TrekFactory.fillPlace(trek) } }
    }

    private func field(_ label: String, _ text: Binding<String>, _ kb: UIKeyboardType) -> some View {
        HStack { Text(label); Spacer(); TextField("0", text: text).keyboardType(kb).multilineTextAlignment(.trailing).frame(maxWidth: 120) }
    }

    private func load() {
        let s = Int(trek.timeInMotion)
        if s > 0 { hours = "\(s / 3600)"; minutes = "\((s % 3600) / 60)" }
        if !trek.hasTrack {
            if trek.distance > 0 { km = Fmt.km(trek.distance) }
            if trek.gain > 0 { gain = "\(Int(trek.gain))" }
            if let m = trek.maxEle { maxEle = "\(Int(m))" }
        }
    }

    private func save() {
        func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) }
        if !trek.hasTrack {
            trek.distance = (Double(km.replacingOccurrences(of: ",", with: ".")) ?? 0) * 1000
            trek.gain = num(gain) ?? 0
            trek.maxEle = num(maxEle)
        }
        let sec = Double((Int(hours) ?? 0) * 3600 + (Int(minutes) ?? 0) * 60)
        if sec > 0, abs(sec - trek.timeInMotion) > 59 { trek.moving = sec; if trek.duration < sec { trek.duration = sec } }
        if trek.name.trimmingCharacters(in: .whitespaces).isEmpty { trek.name = trek.location.isEmpty ? "Trekking" : "Giro da \(trek.location)" }
        if trek.source == .example { trek.sourceRaw = TrekSource.manual.rawValue }
        try? context.save()
        onSaved?(trek)
        dismiss()
    }
}
