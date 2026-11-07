import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var treks: [Trek]
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    howto("heart.fill", .pink, "Apple Salute e Apple Watch",
                          "Tocca + → Importa da Salute. Leggo da solo gli allenamenti di escursionismo e camminata con il percorso GPS.")
                    howto("applewatch", .blue, "Garmin",
                          "Garmin Connect non passa il percorso GPS a Salute. Dal sito connect.garmin.com apri l'attività → ingranaggio → Esporta in GPX, poi + → Importa file.")
                    howto("figure.hiking", .orange, "Strava, Komoot, Wikiloc",
                          "Esporta l'attività o il tour in GPX e aprilo con Segnavia dal menu Condividi, oppure + → Importa file.")
                } header: { Text("Collega le tue app") }

                Section("Aspetto") {
                    Picker("Tema", selection: $theme) {
                        Text("Automatico").tag("system"); Text("Chiaro").tag("light"); Text("Scuro").tag("dark")
                    }.pickerStyle(.segmented)
                }

                Section {
                    if treks.contains(where: \.isExample) {
                        Button("Elimina i trekking di esempio", role: .destructive) { treks.filter(\.isExample).forEach(context.delete) }
                    } else {
                        Button("Mostra di nuovo gli esempi") { Examples.insert(context) }
                    }
                } footer: {
                    Text("I dati restano sul tuo iPhone e finiscono nel backup di iCloud del telefono.")
                }

                Section {
                    Text("Mappe © OpenStreetMap, OpenTopoMap (CC-BY-SA), Waymarked Trails, Apple. Difficoltà secondo la scala CAI.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Altro")
        }
    }

    private func howto(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 26).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
