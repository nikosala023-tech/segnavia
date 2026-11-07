import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query(sort: \Trek.date, order: .reverse) private var treks: [Trek]
    @AppStorage("year") private var year = "Tutti"
    @AppStorage("metric") private var metric = "gain"
    @State private var path = NavigationPath()

    struct Bucket: Identifiable { let id: String; let label: String; let value: Double }

    private var list: [Trek] { treks.inYear(year) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    let tot = Totals(list)
                    VStack(alignment: .leading, spacing: -4) {
                        Text("I tuoi").font(.display(48)).textCase(.uppercase)
                        Text("numeri").font(.display(48)).textCase(.uppercase).foregroundStyle(Theme.red)
                    }
                    YearPicker(years: treks.years, selection: $year)
                    StatGrid(columns: 2) {
                        StatCell(value: "\(tot.count)", label: "Uscite", size: 32)
                        StatCell(value: Fmt.m(tot.gain), unit: "m", label: "D+ totale", size: 32)
                        StatCell(value: Fmt.km(tot.distance), unit: "km", label: "Distanza", size: 32)
                        StatCell(value: (tot.gain / 8849).formatted(.number.precision(.fractionLength(1)).locale(Fmt.it)), unit: "×", label: "Everest saliti", size: 32)
                    }
                    chart
                    records
                    difficulty
                }
                .padding(16).padding(.bottom, 40)
            }
            .background(Theme.ground)
            .navigationDestination(for: Trek.self) { TrekDetailView(trek: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var buckets: [Bucket] {
        func val(_ ts: [Trek]) -> Double {
            switch metric {
            case "n": Double(ts.count)
            case "distance": ts.reduce(0) { $0 + $1.distance } / 1000
            default: ts.reduce(0) { $0 + $1.gain }
            }
        }
        let cal = Calendar.current
        let ys = treks.years
        if year == "Tutti" && ys.count > 1 {
            return ys.reversed().map { y in Bucket(id: y, label: y, value: val(treks.inYear(y))) }
        }
        let y = Int(year) ?? Int(ys.first ?? "") ?? cal.component(.year, from: .now)
        let months = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]
        return months.enumerated().map { i, m in
            Bucket(id: m, label: m, value: val(treks.filter { cal.component(.year, from: $0.date) == y && cal.component(.month, from: $0.date) == i + 1 }))
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(year == "Tutti" && treks.years.count > 1 ? "Per anno" : "Per mese").sectionTitle()
                Spacer()
                Picker("Metrica", selection: $metric) {
                    Text("D+").tag("gain"); Text("Km").tag("distance"); Text("Uscite").tag("n")
                }.pickerStyle(.segmented).frame(width: 190)
            }
            Chart(buckets) { b in
                BarMark(x: .value("Periodo", b.label), y: .value("Valore", b.value), width: .ratio(0.62))
                    .foregroundStyle(b.value > 0 ? Theme.red : Theme.red.opacity(0.25))
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        if b.value > 0 {
                            Text(metric == "distance" ? b.value.formatted(.number.precision(.fractionLength(0)).locale(Fmt.it)) : Fmt.m(b.value))
                                .font(.display(12, weight: .bold))
                        }
                    }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 220)
            .padding(16).cardStyle()
        }
    }

    private var records: some View {
        func best(_ f: (Trek) -> Double) -> Trek? { list.filter { f($0) > 0 }.max { f($0) < f($1) } }
        let items: [(String, Trek?, (Trek) -> (String, String))] = [
            ("Più dislivello", best { $0.gain }, { (Fmt.m($0.gain), "m") }),
            ("Più lungo", best { $0.distance }, { (Fmt.km($0.distance), "km") }),
            ("Più in alto", best { $0.maxEle ?? 0 }, { (Fmt.m($0.maxEle), "m") }),
            ("Più ore in cammino", best { $0.timeInMotion }, { (Fmt.dur($0.timeInMotion), "") }),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Record").sectionTitle()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(items.indices, id: \.self) { i in
                    if let t = items[i].1 {
                        let vu = items[i].2(t)
                        NavigationLink(value: t) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(items[i].0.uppercased()).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(vu.0).font(.display(30)); Text(vu.1).font(.display(15, weight: .semibold)).foregroundStyle(.secondary)
                                }
                                Text(t.name).font(.footnote.weight(.bold)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14).cardStyle()
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var difficulty: some View {
        let counts = Difficulty.allCases.map { d in (d, list.filter { $0.difficulty == d }.count) }
        let mx = max(1, counts.map(\.1).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Difficoltà").sectionTitle()
            VStack(spacing: 12) {
                ForEach(counts, id: \.0) { item in
                    let d = item.0, n = item.1
                    HStack(spacing: 10) {
                        DifficultyTag(d: d).frame(width: 52, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                Capsule().fill(Theme.difficulty(d)).frame(width: g.size.width * CGFloat(n) / CGFloat(mx))
                            }
                        }.frame(height: 10)
                        Text("\(n)").font(.display(18, weight: .bold)).frame(width: 30, alignment: .trailing)
                    }
                }
            }
            .padding(16).cardStyle()
        }
    }
}
