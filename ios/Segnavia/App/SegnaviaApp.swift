import SwiftUI
import SwiftData

@main
struct SegnaviaApp: App {
    let container: ModelContainer = {
        do { return try ModelContainer(for: Trek.self, TrekPhoto.self) }
        catch { fatalError("Impossibile aprire il database: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.red)
                .task { Examples.seedIfNeeded(container.mainContext) }
        }
        .modelContainer(container)
    }
}

/// Router condiviso: tab corrente, foglio "aggiungi", import da file condivisi.
@Observable
final class AppState {
    enum Tab: Hashable { case diary, map, stats, more }
    var tab: Tab = .diary
    var showAdd = false
    var openTrek: Trek?
    var incomingFile: URL?
}

struct ContentView: View {
    @State private var app = AppState()
    @AppStorage("theme") private var theme = "system"

    var body: some View {
        TabView(selection: $app.tab) {
            DiaryView().tag(AppState.Tab.diary)
                .tabItem { Label("Diario", systemImage: "book.closed") }
            AllMapView().tag(AppState.Tab.map)
                .tabItem { Label("Mappa", systemImage: "map") }
            StatsView().tag(AppState.Tab.stats)
                .tabItem { Label("Numeri", systemImage: "chart.xyaxis.line") }
            SettingsView().tag(AppState.Tab.more)
                .tabItem { Label("Altro", systemImage: "gearshape") }
        }
        .environment(app)
        .sheet(isPresented: $app.showAdd) { AddTrekSheet().environment(app) }
        .onOpenURL { url in app.incomingFile = url; app.tab = .diary; app.showAdd = true }
        .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
    }
}
