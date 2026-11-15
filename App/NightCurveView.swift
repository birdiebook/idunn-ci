import SwiftUI
import Charts
import Night
import Sound

/// METOD M18 · METOD M32 · BESLUT B19 · BESLUT B39
/// Nattens kurva: puls minut för minut, HRV och andning per 5-minutersfönster,
/// som små diagram på en gemensam tidsaxel (ingen dubbel axel). Botten är
/// märkt, glappen skuggade i alla diagram, och remsan längst ner visar hur
/// mycket av varje minut som saknas. En natt ur bandets egen historik har
/// också rörelse och hudtemperatur per minut, en remsa för sömnen med de
/// vakna stunderna som avbrott, och glapp färgade efter orsak (M32). Den
/// typiska natten — kvartilerna ur de tidigare nätterna, efter andel av
/// natten — ligger som ett svagt band bakom pulsen och HRV.
///
/// Vyn visar nattens värden och klockslag (BESLUT B19); nattrapporten är den
/// som går att skärmdumpa (BESLUT B3).
struct NightCurveView: View {
    let summary: NightSummary
    @EnvironmentObject private var recorder: Recorder
    @State private var bundle: NightLoader.CurveBundle?
    @State private var loaded = false

    var body: some View {
        Group {
            if let b = bundle {
                CurveCharts(curve: b.curve,
                            typical: Self.typical(b.curve, stem: summary.stem, summaries: recorder.summaries),
                            layers: b.layers, sound: b.sound)
            } else if loaded {
                ContentUnavailableView("Natten gick inte att läsa", systemImage: "moon.zzz")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(summary.titleDate?
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // METOD M21. Poincarémolnet för samma natt.
            NavigationLink { PoincareView(summary: summary) } label: { Image(systemName: "chart.dots.scatter") }
                .accessibilityLabel("Slag för slag")
        }
        .task {
            // METOD M28. Nattens kurva räknas ur dygnsfilerna (K18) eller inspelningen. BESLUT B52: räknar
            // Morgons kontroll redan samma natt (vid start) väntar kurvan på den uträkningen.
            let s = summary
            bundle = await NightLoader.sharedBundle(for: s, priority: .userInitiated)
            loaded = true
        }
    }

    /// METOD M18. De tidigare nätterna, ur sammanfattningarna: en natt per
    /// uppvakningsdag, så att en dag med både K18 och en gammal inspelning inte räknas två gånger.
    static func typical(_ c: NightCurve.Curve, stem: String, summaries: [NightSummary]) -> NightCurve.Typical? {
        let tidigare: [NightSummary] = NightSummary.preferred(summaries).filter { (s: NightSummary) -> Bool in
            s.stem != stem
        }
        let past: [NightCurve.Past] = tidigare.compactMap { (s: NightSummary) -> NightCurve.Past? in s.past }
        return NightCurve.typical(before: Date(timeIntervalSince1970: c.start), nights: past)
    }
}

/// Diagrammen och nyckeltalen. En markerad tid gäller alla diagram.
struct CurveCharts: View {
    let curve: NightCurve.Curve
    let typical: NightCurve.Typical?
    let layers: NightLayers.Layers?
    /// METOD M44. Nattens ljud; `nil` för en natt utan ljud.
    let sound: NightSound?
    @State private var markerad: Date?

    init(curve: NightCurve.Curve, typical: NightCurve.Typical?, layers: NightLayers.Layers? = nil,
         sound: NightSound? = nil) {
        self.curve = curve
        self.typical = typical
        self.layers = layers
        self.sound = sound
    }

    var body: some View {
        ScrollView {
            CurveStack(curve: curve, typical: typical, layers: layers, sound: sound, markerad: $markerad)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// Diagrammen utan rullning, så att `ImageRenderer` kan rita dem (IdunnProv).
struct CurveStack: View {
    let curve: NightCurve.Curve
    let typical: NightCurve.Typical?
    /// METOD M32. Lagren för en natt ur bandets historik; `nil` för en gammal inspelning.
    var layers: NightLayers.Layers? = nil
    /// METOD M44 · BESLUT B54. Nattens ljud: lagret "Ljud" och händelserna under kurvan. `nil` när natten saknar ljud.
    var sound: NightSound? = nil
    @Binding var markerad: Date?

    /// Kurvans spann, och sömnperiodens om den sträcker sig längre (M32).
    private var domän: ClosedRange<Date> {
        let a: TimeInterval = min(curve.start, layers?.start ?? curve.start)
        let b: TimeInterval = max(curve.end, layers?.end ?? curve.end)
        return Date(timeIntervalSince1970: a)...Date(timeIntervalSince1970: max(b, a + 60))
    }

    var body: some View {
        let skuggor: [GapShade] = GapShade.make(curve: curve, layers: layers)
        VStack(alignment: .leading, spacing: 12) {
            KeyFigures(curve: curve, typical: typical)
            HeartRateChart(curve: curve, typical: typical, domän: domän, shades: skuggor, markerad: $markerad)
            HRVChart(curve: curve, typical: typical, domän: domän, shades: skuggor, markerad: $markerad)
            BreathingChart(curve: curve, domän: domän, shades: skuggor, markerad: $markerad)
            if let l = layers {
                MovementChart(layers: l, domän: domän, shades: skuggor, markerad: $markerad)
                SkinChart(layers: l, domän: domän, shades: skuggor, markerad: $markerad)
                if let ljud = sound {
                    SoundChart(sound: ljud, domän: domän, markerad: $markerad)
                }
                if l.stages.isEmpty {
                    SleepStrip(layers: l, domän: domän, markerad: $markerad)
                } else {
                    StageStrip(layers: l, domän: domän, markerad: $markerad)
                }
            }
            MissingStrip(curve: curve, domän: domän, shades: skuggor, markerad: $markerad)
            if let l = layers, !l.gaps.isEmpty {
                GapLegend(layers: l)
            }
            if let ljud = sound {
                SoundReport(sound: ljud)
            }
        }
        .padding()
    }
}

/// METOD M18 · METOD M32. Botten (värde och läge i natten) och fallet, i två
/// lika breda rutor med värdet och enheten på en rad, och förklaringen till
/// den typiska nattens band på en egen rad under. Allt låg förut i en rad med
/// fast bredd (`fixedSize`) som blev för bred och skar bort värdet.
private struct KeyFigures: View {
    let curve: NightCurve.Curve
    let typical: NightCurve.Typical?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let n = curve.nadir {
                    Figure(symbol: "arrow.down.to.line", value: "\(Int(n.heartRate.rounded()))",
                           unit: "bpm · \(pct(n.fraction))", label: "Lägsta puls")
                }
                if let f = curve.fall {
                    Figure(symbol: "arrow.down.right", value: "\(Int((f.seconds / 60).rounded()))",
                           unit: "min · −\(Int(f.drop.rounded()))", label: "Fallet till botten")
                }
            }
            if typical != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(CurveColor.typical)
                        .frame(width: 20, height: 10)
                    Text("vanlig")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Ett nyckeltal: symbol, värdet stort och enheten liten, på en rad. Rutan tar
/// halva bredden; enheten krymper hellre än bryts, och värdet mäts aldrig bort.
private struct Figure: View {
    let symbol: String
    let value: String
    let unit: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
    }
}

/// Ett diagram i kurvan: rubrik med symbol, avläsningen till höger och diagrammet.
private struct CurveCard<Inner: View>: View {
    let title: String
    let symbol: String
    let reading: String?
    @ViewBuilder let inner: Inner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let r = reading {
                    Text(r).font(.headline).monospacedDigit()
                }
            }
            inner
        }
        .padding(12)
        .background(TrendColor.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// METOD M18. Pulsen per minut, den typiska nattens band och botten.
private struct HeartRateChart: View {
    let curve: NightCurve.Curve
    let typical: NightCurve.Typical?
    let domän: ClosedRange<Date>
    let shades: [GapShade]
    @Binding var markerad: Date?

    private var punkter: [CurvePoint] {
        CurvePoint.segmented(curve.minutes.map { ($0.mid, $0.heartRate) })
    }
    private var band: [BandPoint] { BandPoint.make(typical?.heartRate ?? [], curve) }
    private var yDomän: ClosedRange<Double> { CurvePoint.domain(punkter.map(\.value) + band.flatMap { [$0.lower, $0.upper] }) }

    private var avläsning: String? {
        if let t = markerad, let m = närmaste(t) {
            return "\(t.formatted(.dateTime.hour().minute())) · \(Int(m.rounded()))"
        }
        return nil
    }

    private func närmaste(_ t: Date) -> Double? {
        let s = t.timeIntervalSince1970
        return curve.minutes.filter { $0.heartRate != nil }
            .min { abs($0.mid - s) < abs($1.mid - s) }?.heartRate
    }

    var body: some View {
        let y = yDomän
        CurveCard(title: "Puls", symbol: "heart", reading: avläsning) {
            Chart {
                GapMarks(shades: shades, y: y)
                ForEach(band) { b in
                    AreaMark(x: .value("Tid", b.time), yStart: .value("Puls", b.lower), yEnd: .value("Puls", b.upper))
                        .foregroundStyle(CurveColor.typical)
                }
                ForEach(punkter) { p in
                    LineMark(x: .value("Tid", p.time), y: .value("Puls", p.value), series: .value("Serie", p.segment))
                        .foregroundStyle(TrendColor.idun)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                if let n = curve.nadir {
                    PointMark(x: .value("Tid", Date(timeIntervalSince1970: n.time)), y: .value("Puls", n.heartRate))
                        .symbol { NightSymbol(source: .idun, size: 10, ring: true) }
                        .annotation(position: .bottom, spacing: 2) {
                            Text("\(Int(n.heartRate.rounded()))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Lägsta puls")
                        .accessibilityValue("\(Int(n.heartRate.rounded())) bpm")
                }
                Selection(markerad: markerad)
            }
            .curveAxes(domän: domän, y: y, labels: false)
            .tryckMarkering($markerad)
            .frame(height: 140)
        }
    }
}

/// METOD M4 · METOD M18. RMSSD per 5-minutersfönster och den typiska nattens band.
private struct HRVChart: View {
    let curve: NightCurve.Curve
    let typical: NightCurve.Typical?
    let domän: ClosedRange<Date>
    let shades: [GapShade]
    @Binding var markerad: Date?

    private var punkter: [CurvePoint] {
        CurvePoint.segmented(curve.windows.map { ($0.mid, $0.rmssd) })
    }
    private var band: [BandPoint] { BandPoint.make(typical?.rmssd ?? [], curve) }
    private var yDomän: ClosedRange<Double> { CurvePoint.domain(punkter.map(\.value) + band.flatMap { [$0.lower, $0.upper] }) }

    private var avläsning: String? {
        guard let t = markerad else { return nil }
        let s = t.timeIntervalSince1970
        let w = curve.windows.filter { $0.rmssd != nil }.min { abs($0.mid - s) < abs($1.mid - s) }
        return w?.rmssd.map { "\(Int($0.rounded())) ms" }
    }

    var body: some View {
        let y = yDomän
        CurveCard(title: "HRV", symbol: "waveform.path.ecg", reading: avläsning) {
            Chart {
                GapMarks(shades: shades, y: y)
                ForEach(band) { b in
                    AreaMark(x: .value("Tid", b.time), yStart: .value("RMSSD", b.lower), yEnd: .value("RMSSD", b.upper))
                        .foregroundStyle(CurveColor.typical)
                }
                ForEach(punkter) { p in
                    LineMark(x: .value("Tid", p.time), y: .value("RMSSD", p.value), series: .value("Serie", p.segment))
                        .foregroundStyle(TrendColor.idun)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                Selection(markerad: markerad)
            }
            .curveAxes(domän: domän, y: y, labels: false)
            .tryckMarkering($markerad)
            .frame(height: 110)
        }
    }
}

/// METOD M10 · METOD M18. Andningen i fönstren med tydlig topp, som prickar.
private struct BreathingChart: View {
    let curve: NightCurve.Curve
    let domän: ClosedRange<Date>
    let shades: [GapShade]
    @Binding var markerad: Date?

    private var punkter: [CurvePoint] {
        curve.windows.compactMap { (w: NightCurve.WindowPoint) -> CurvePoint? in
            w.breathsPerMinute.map { CurvePoint(time: Date(timeIntervalSince1970: w.mid), value: $0, segment: 0) }
        }
    }

    private var avläsning: String? {
        guard let t = markerad else { return nil }
        let s = t.timeIntervalSince1970
        let w = curve.windows.filter { $0.breathsPerMinute != nil }.min { abs($0.mid - s) < abs($1.mid - s) }
        return w?.breathsPerMinute.map { $0.formatted(.number.precision(.fractionLength(1))) + " /min" }
    }

    var body: some View {
        let y = CurvePoint.domain(punkter.map(\.value))
        CurveCard(title: "Andning", symbol: "lungs", reading: avläsning) {
            Chart {
                GapMarks(shades: shades, y: y)
                ForEach(punkter) { p in
                    PointMark(x: .value("Tid", p.time), y: .value("Andning", p.value))
                        .symbol { NightSymbol(source: .idun, size: 6) }
                }
                Selection(markerad: markerad)
            }
            .curveAxes(domän: domän, y: y, labels: false)
            .tryckMarkering($markerad)
            .frame(height: 90)
        }
    }
}

/// METOD M24 · METOD M32. Rörelsen per minut som staplar (medel av |Δg|); en
/// minut utan bandets data är tom, inte noll. Minuter över gränsen för rörelse
/// har samma färg som glapp med rörelse som orsak. Staplarna har ingen
/// y-skala med tal: höjden jämförs mellan minuterna.
private struct MovementChart: View {
    let layers: NightLayers.Layers
    let domän: ClosedRange<Date>
    let shades: [GapShade]
    @Binding var markerad: Date?

    private var minuter: [NightLayers.Minute] {
        layers.minutes.filter { (m: NightLayers.Minute) -> Bool in m.movement != nil }
    }
    private var yDomän: ClosedRange<Double> {
        let störst: Double = minuter.compactMap { (m: NightLayers.Minute) -> Double? in m.movement }.max() ?? 0
        return 0...max(störst, NightLayers.movementThreshold * 2)
    }

    private var avläsning: String? {
        guard let t = markerad else {
            return layers.coverage.map { (c: Double) -> String in "\(pct(c)) mätt" }
        }
        let klockan: String = t.formatted(.dateTime.hour().minute())
        guard let v = layers.minute(at: t.timeIntervalSince1970)?.movement else { return "\(klockan) · –" }
        return klockan + " · " + v.formatted(.number.precision(.fractionLength(2))) + " g"
    }

    var body: some View {
        let y = yDomän
        CurveCard(title: "Rörelse", symbol: "figure.walk", reading: avläsning) {
            Chart {
                GapMarks(shades: shades, y: y)
                ForEach(minuter, id: \.start) { (m: NightLayers.Minute) in
                    let v: Double = m.movement ?? 0
                    RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: m.start)),
                                  xEnd: .value("Tid", Date(timeIntervalSince1970: m.start + NightCurve.minuteSeconds)),
                                  yStart: .value("Rörelse", 0.0), yEnd: .value("Rörelse", v))
                        .foregroundStyle(v >= NightLayers.movementThreshold ? CurveColor.movement : TrendColor.idun)
                }
                Selection(markerad: markerad)
            }
            .curveAxes(domän: domän, y: y, labels: false, yLabels: false)
            .tryckMarkering($markerad)
            .frame(height: 70)
        }
    }
}

/// METOD M24 · METOD M32. Hudtemperaturen per minut som en linje som bryts där
/// bandets data saknas. En enstaka minut mellan två luckor ritas som en prick.
private struct SkinChart: View {
    let layers: NightLayers.Layers
    let domän: ClosedRange<Date>
    let shades: [GapShade]
    @Binding var markerad: Date?

    private var punkter: [CurvePoint] {
        CurvePoint.segmented(layers.minutes.map { (m: NightLayers.Minute) -> (TimeInterval, Double?) in
            (m.mid, m.skinTemperature)
        })
    }
    /// Punkter som är ensamma i sitt segment: en linje av en punkt syns inte.
    private var ensamma: [CurvePoint] {
        let perSegment: [Int: [CurvePoint]] = Dictionary(grouping: punkter) { (p: CurvePoint) -> Int in p.segment }
        return punkter.filter { (p: CurvePoint) -> Bool in perSegment[p.segment]?.count == 1 }
    }
    private var yDomän: ClosedRange<Double> { CurvePoint.domain(punkter.map(\.value), minLuft: 0.1) }

    private var avläsning: String? {
        guard let t = markerad else { return nil }
        let klockan: String = t.formatted(.dateTime.hour().minute())
        guard let v = layers.minute(at: t.timeIntervalSince1970)?.skinTemperature else { return "\(klockan) · –" }
        return klockan + " · " + v.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    var body: some View {
        let y = yDomän
        CurveCard(title: "Hudtemp", symbol: "thermometer", reading: avläsning) {
            Chart {
                GapMarks(shades: shades, y: y)
                ForEach(punkter) { (p: CurvePoint) in
                    LineMark(x: .value("Tid", p.time), y: .value("Hudtemp", p.value), series: .value("Serie", p.segment))
                        .foregroundStyle(TrendColor.idun)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
                ForEach(ensamma) { (p: CurvePoint) in
                    PointMark(x: .value("Tid", p.time), y: .value("Hudtemp", p.value))
                        .symbol { NightSymbol(source: .idun, size: 4) }
                }
                Selection(markerad: markerad)
            }
            .curveAxes(domän: domän, y: y, labels: false)
            .tryckMarkering($markerad)
            .frame(height: 90)
        }
    }
}

/// METOD M26 · METOD M32. Sömnperioden som en remsa på tidsaxeln: perioden som
/// en svag bakgrund och sömnen som stapel ovanpå, så att de vakna stunderna
/// (och glapp i bandets data) syns som avbrott i den.
private struct SleepStrip: View {
    let layers: NightLayers.Layers
    let domän: ClosedRange<Date>
    @Binding var markerad: Date?

    private var avläsning: String? {
        guard let t = markerad else { return nil }
        let s: TimeInterval = t.timeIntervalSince1970
        if layers.asleep.contains(where: { (r: ClosedRange<TimeInterval>) -> Bool in r.contains(s) }) { return "Sömn" }
        return layers.isAwake(s) ? "Vaken" : nil
    }

    var body: some View {
        CurveCard(title: "Sömn", symbol: "bed.double", reading: avläsning) {
            Chart {
                RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: layers.period.lowerBound)),
                              xEnd: .value("Tid", Date(timeIntervalSince1970: layers.period.upperBound)),
                              yStart: .value("Y", 0.0), yEnd: .value("Y", 1.0))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                ForEach(layers.asleep.indices, id: \.self) { (i: Int) in
                    RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: layers.asleep[i].lowerBound)),
                                  xEnd: .value("Tid", Date(timeIntervalSince1970: layers.asleep[i].upperBound)),
                                  yStart: .value("Y", 0.0), yEnd: .value("Y", 1.0))
                        .foregroundStyle(TrendColor.idun)
                }
                Selection(markerad: markerad)
            }
            .curveAxes(domän: domän, y: 0...1, labels: false, yLabels: false)
            .tryckMarkering($markerad)
            .frame(height: 24)
        }
    }
}

/// METOD M32 · METOD M37 · BESLUT B43 · BESLUT B46
/// Stadierna som ett band på tidsaxeln: fyra rader (vaken överst, REM, lätt,
/// djup nederst) och en ruta per följd av epoker; opaciteten följer hur säker
/// modellen är, och glapp är tomma.
private struct StageStrip: View {
    let layers: NightLayers.Layers
    let domän: ClosedRange<Date>
    @Binding var markerad: Date?

    private var avläsning: String? {
        guard let t = markerad, let sp = layers.stage(at: t.timeIntervalSince1970) else { return nil }
        let ord: String = StageColor.word(sp.stage)
        return ord.prefix(1).uppercased() + ord.dropFirst()
    }

    /// För VoiceOver: bandet är ett element med minuterna per stadium, inte en ruta per följd
    /// av epoker (hundratals per natt, och stadiet bärs annars bara av färg och höjd).
    private var tillgänglig: String {
        var delar: [String] = []
        for s in [SleepStage.wake, SleepStage.light, SleepStage.deep, SleepStage.rem] {
            var sekunder: TimeInterval = 0
            for sp in layers.stages where sp.stage == s { sekunder += sp.end - sp.start }
            delar.append("\(StageColor.word(s)) \(Int((sekunder / 60).rounded())) min")
        }
        return delar.joined(separator: ", ")
    }

    var body: some View {
        CurveCard(title: "Sömn", symbol: "bed.double", reading: avläsning) {
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: layers.period.lowerBound)),
                                  xEnd: .value("Tid", Date(timeIntervalSince1970: layers.period.upperBound)),
                                  yStart: .value("Y", 0.0), yEnd: .value("Y", 4.0))
                        .foregroundStyle(Color.secondary.opacity(0.08))
                    StageMarks(spans: layers.stages)
                    Selection(markerad: markerad)
                }
                .curveAxes(domän: domän, y: 0...4, labels: false, yLabels: false)
                .tryckMarkering($markerad)
                .frame(height: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sömn")
                .accessibilityValue(tillgänglig)
                StageLegend()
            }
        }
    }
}

/// METOD M37 · BESLUT B46. En ruta per följd av epoker, på stadiets rad.
private struct StageMarks: ChartContent {
    let spans: [NightLayers.StageSpan]

    @ChartContentBuilder var body: some ChartContent {
        ForEach(spans.indices, id: \.self) { (i: Int) in
            RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: spans[i].start)),
                          xEnd: .value("Tid", Date(timeIntervalSince1970: spans[i].end)),
                          yStart: .value("Y", StageColor.lane(spans[i].stage) + 0.1),
                          yEnd: .value("Y", StageColor.lane(spans[i].stage) + 0.9))
                .foregroundStyle(StageColor.color(spans[i].stage).opacity(StageColor.level(spans[i].certainty)))
        }
    }
}

/// METOD M37 · BESLUT B46. Fyra rutor med orden för stadierna, som glappens förklaring.
private struct StageLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach([SleepStage.wake, SleepStage.light, SleepStage.deep, SleepStage.rem], id: \.rawValue) { (s: SleepStage) in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(StageColor.color(s).opacity(0.9))
                        .frame(width: 12, height: 8)
                    Text(StageColor.word(s))
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// METOD M18. Det som saknas per minut (kastade och utelämnade slag), och
/// glappen helt mörka. Tidsaxelns klockslag står här, under alla diagram.
private struct MissingStrip: View {
    let curve: NightCurve.Curve
    let domän: ClosedRange<Date>
    let shades: [GapShade]
    @Binding var markerad: Date?

    private var minuter: [NightCurve.Minute] {
        curve.minutes.filter { $0.missingShare >= 0.02 }
    }

    var body: some View {
        CurveCard(title: "Saknas", symbol: "eye.slash", reading: nil) {
            Chart {
                GapMarks(shades: shades, y: 0...1, strong: true)
                ForEach(minuter, id: \.start) { m in
                    RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: m.start)),
                                  xEnd: .value("Tid", Date(timeIntervalSince1970: m.start + NightCurve.minuteSeconds)),
                                  yStart: .value("Andel", 0.0), yEnd: .value("Andel", 1.0))
                        .foregroundStyle(Color.secondary.opacity(0.15 + 0.6 * min(1, m.missingShare)))
                }
                Selection(markerad: markerad)
            }
            .curveAxes(domän: domän, y: 0...1, labels: true, yLabels: false)
            .tryckMarkering($markerad)
            .frame(height: 44)
        }
    }
}

/// METOD M32. Vad glappens färger betyder; bara de orsaker som finns i natten.
private struct GapLegend: View {
    let layers: NightLayers.Layers

    private func har(_ orsak: NightLayers.GapCause) -> Bool {
        layers.gaps.contains { (g: NightLayers.Gap) -> Bool in g.cause == orsak }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Glapp")
            if har(.movement) { swatch(CurveColor.movement.opacity(0.55), "rörelse") }
            if har(.unknown) { swatch(Color.secondary.opacity(0.4), "okänd") }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func swatch(_ färg: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(färg).frame(width: 20, height: 10)
            Text(text)
        }
    }
}

/// METOD M44 · BESLUT B54
/// Ljudet på tidsaxeln: nivån över nattens golv som en tunn yta (högsta sekunden per minut), snarkningen som ett
/// band med ägarens färg (din blå, någon annans grönblå, okänd grå), och övriga händelser som en symbol per
/// klass. Symbolen är gul när händelsen följdes av ett uppvaknande och har en gul kant när pulsen steg (METOD M40).
/// Ett tryck på en symbol spelar klippet, om det finns kvar (14 dagar). Hållet och draget markerar tiden som i
/// de andra diagrammen (BESLUT B49).
private struct SoundChart: View {
    let sound: NightSound
    let domän: ClosedRange<Date>
    @Binding var markerad: Date?
    @Environment(\.clipExists) private var clipExists
    @ObservedObject private var spelare = ClipPlayer.shared

    /// Nivåer över detta klipps, så att en enstaka smäll inte plattar ut resten.
    private static let tak: Double = 36
    /// Raderna i diagrammet: nivån 0–36, snarkbandet, symbolerna. En andra symbolrad finns bara när två
    /// symboler annars hade legat på varandra; diagrammet blir då högre, med samma skala (2 pt per enhet).
    private static let bandFrån: Double = 40
    private static let bandTill: Double = 44
    private static let symbolRader: [Double] = [53, 66]
    /// Den andel av tidsaxeln en symbol tar (en gul skiva är cirka 26 pt av en ritbredd på cirka 350 pt).
    private static let symbolAndel: Double = 0.075

    private var snarkning: [NightSound.Event] {
        sound.events.filter { (e: NightSound.Event) -> Bool in e.isSnoring }
    }

    /// Allt utom snarkning, andning och övrigt visas som symbol; snarkning och övrigt när de följdes av något.
    private var symboler: [NightSound.Event] {
        sound.events.filter { (e: NightSound.Event) -> Bool in
            if e.followed { return true }
            return !e.isSnoring && e.soundClass != NightSound.otherClass && e.soundClass != NightSound.breathingClass
        }
    }

    private var spelbara: [NightSound.Event] {
        symboler.filter { (e: NightSound.Event) -> Bool in clipExists(e.clip) }
    }

    /// BESLUT B54. Symbolens rad, per händelse; täta symboler delas på två rader.
    private var rader: [String: Int] {
        let ordnade: [NightSound.Event] = symboler.sorted { (a: NightSound.Event, b: NightSound.Event) -> Bool in
            mitt(a) < mitt(b)
        }
        let spann: TimeInterval = domän.upperBound.timeIntervalSince(domän.lowerBound)
        let rad: [Int] = NightSound.symbolRows(times: ordnade.map { (e: NightSound.Event) -> TimeInterval in
            mitt(e).timeIntervalSince1970
        }, minGap: spann * Self.symbolAndel)
        var ut: [String: Int] = [:]
        for (e, r) in zip(ordnade, rad) { ut[e.id] = r }
        return ut
    }

    private func symbolY(_ e: NightSound.Event, _ rader: [String: Int]) -> Double {
        Self.symbolRader[rader[e.id] ?? 0]
    }

    private func mitt(_ e: NightSound.Event) -> Date {
        Date(timeIntervalSince1970: e.time + Double(max(e.seconds, 1)) / 2)
    }

    private var avläsning: String? {
        guard let t = markerad else { return nil }
        let s: TimeInterval = t.timeIntervalSince1970
        let klockan: String = t.formatted(.dateTime.hour().minute())
        guard let l = sound.levels.first(where: { (l: NightSound.Level) -> Bool in s >= l.start && s < l.start + 60 })
        else { return "\(klockan) · –" }
        return klockan + " · +" + Int(l.aboveFloor.rounded()).formatted() + " dB"
    }

    var body: some View {
        let rader: [String: Int] = self.rader
        let y: ClosedRange<Double> = rader.values.contains(1) ? 0...74 : 0...60
        return CurveCard(title: "Ljud", symbol: "waveform", reading: avläsning) {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    nivån
                    band
                    symbolerna(rader)
                    Selection(markerad: markerad)
                }
                .curveAxes(domän: domän, y: y, labels: false, yLabels: false)
                .tryckMarkering($markerad)
                .chartOverlay(alignment: .topLeading) { (proxy: ChartProxy) in
                    knappar(proxy, rader)
                }
                .frame(height: 2 * y.upperBound)
                SoundLegend(sound: sound)
            }
        }
    }

    @ChartContentBuilder private var nivån: some ChartContent {
        ForEach(sound.levels, id: \.start) { (l: NightSound.Level) in
            RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: l.start)),
                          xEnd: .value("Tid", Date(timeIntervalSince1970: l.start + NightCurve.minuteSeconds)),
                          yStart: .value("Nivå", 0.0), yEnd: .value("Nivå", min(l.aboveFloor, Self.tak)))
                .foregroundStyle(CurveColor.sound)
        }
    }

    @ChartContentBuilder private var band: some ChartContent {
        ForEach(snarkning) { (e: NightSound.Event) in
            RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: e.time)),
                          xEnd: .value("Tid", Date(timeIntervalSince1970: e.time + Double(max(e.seconds, 30)))),
                          yStart: .value("Rad", Self.bandFrån), yEnd: .value("Rad", Self.bandTill))
                .foregroundStyle(SoundLook.ownerColor(e.owner))
        }
    }

    @ChartContentBuilder private func symbolerna(_ rader: [String: Int]) -> some ChartContent {
        ForEach(symboler) { (e: NightSound.Event) in
            PointMark(x: .value("Tid", mitt(e)), y: .value("Rad", symbolY(e, rader)))
                .symbol {
                    SoundGlyph(soundClass: e.soundClass, owner: e.owner, woke: e.woke, pulse: e.pulse,
                               playing: spelare.playing == e.clip.key)
                }
                .accessibilityLabel(SoundLook.word(e.soundClass))
                .accessibilityValue(SoundLook.clock(e.time))
        }
    }

    /// Osynliga tryckytor över symbolerna som har ett klipp. Resten av ritytan faller igenom till markeringen.
    private func knappar(_ proxy: ChartProxy, _ rader: [String: Int]) -> some View {
        GeometryReader { (geo: GeometryProxy) in
            if let plot: Anchor<CGRect> = proxy.plotFrame {
                let ram: CGRect = geo[plot]
                ForEach(spelbara) { (e: NightSound.Event) in
                    if let x: CGFloat = proxy.position(forX: mitt(e)),
                       let y: CGFloat = proxy.position(forY: symbolY(e, rader)) {
                        Button {
                            spelare.toggle(e.clip)
                        } label: {
                            Color.clear.frame(width: 34, height: 34).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: ram.minX + x, y: ram.minY + y)
                        .accessibilityLabel("Spela \(SoundLook.word(e.soundClass)) \(SoundLook.clock(e.time))")
                    }
                }
            }
        }
    }
}

/// BESLUT B63. Ljudlagret för måttet över natten: samma diagram som i Nattens kurva (nivån, snarkningens band, symbolerna
/// och knapparna till klippen), på kurvans tidsaxel. Hållet och draget markerar tiden som där.
struct SoundLayerView: View {
    let sound: NightSound
    let curve: NightCurve.Curve
    let layers: NightLayers.Layers?
    @State private var markerad: Date?

    private var domän: ClosedRange<Date> {
        let a: TimeInterval = min(curve.start, layers?.start ?? curve.start)
        let b: TimeInterval = max(curve.end, layers?.end ?? curve.end)
        return Date(timeIntervalSince1970: a)...Date(timeIntervalSince1970: max(b, a + 60))
    }

    var body: some View {
        SoundChart(sound: sound, domän: domän, markerad: $markerad)
    }
}

/// BESLUT B54. Teckenförklaringen under ljuddiagrammet: bara det som finns i natten.
private struct SoundLegend: View {
    let sound: NightSound

    private var ägare: [NightSound.Owner] {
        [NightSound.Owner.yours, .someoneElse, .unknown].filter { (o: NightSound.Owner) -> Bool in
            sound.events.contains { (e: NightSound.Event) -> Bool in e.isSnoring && e.owner == o }
        }
    }

    /// Klasserna med en symbol i diagrammet, de vanligaste först, högst fem.
    private var klasser: [Int] {
        var antal: [Int: Int] = [:]
        for e in sound.events where !e.isSnoring && e.soundClass != NightSound.breathingClass
            && e.soundClass != NightSound.otherClass {
            antal[e.soundClass, default: 0] += 1
        }
        let ordnade: [Int] = antal.keys.sorted { (a: Int, b: Int) -> Bool in
            let na: Int = antal[a] ?? 0
            let nb: Int = antal[b] ?? 0
            return na != nb ? na > nb : a < b
        }
        return Array(ordnade.prefix(5))
    }

    private var väckte: Bool { sound.events.contains { (e: NightSound.Event) -> Bool in e.woke } }
    private var baraPuls: Bool { sound.events.contains { (e: NightSound.Event) -> Bool in e.pulse && !e.woke } }

    var body: some View {
        FlowLayout(spacing: 10, lineSpacing: 6) {
            if !ägare.isEmpty {
                Image(systemName: SoundLook.symbol(NightSound.snoringClass))
                ForEach(ägare, id: \.self) { (o: NightSound.Owner) in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(SoundLook.ownerColor(o)).frame(width: 14, height: 8)
                        Text(SoundLook.ownerWord(o))
                    }
                }
            }
            ForEach(klasser, id: \.self) { (c: Int) in
                HStack(spacing: 3) {
                    Image(systemName: SoundLook.symbol(c))
                    Text(SoundLook.word(c))
                }
            }
            if väckte {
                HStack(spacing: 4) {
                    Circle().fill(TrendColor.warning).frame(width: 8, height: 8)
                    Text("väckte")
                }
            }
            if baraPuls {
                HStack(spacing: 4) {
                    Circle().strokeBorder(TrendColor.warning, lineWidth: 1.5).frame(width: 8, height: 8)
                    Text("puls")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Barnen på rad, och en ny rad när de inte ryms: teckenförklaringen ska aldrig kapa ett ord.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var ut: [[Int]] = [[]]
        var x: CGFloat = 0
        for i in subviews.indices {
            let w: CGFloat = subviews[i].sizeThatFits(.unspecified).width
            if x > 0 && x + w > width { ut.append([]); x = 0 }
            ut[ut.count - 1].append(i)
            x += w + spacing
        }
        return ut
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let bredd: CGFloat = proposal.width ?? 10_000
        var höjd: CGFloat = 0
        for rad in rows(subviews, width: bredd) {
            let h: CGFloat = rad.map { (i: Int) -> CGFloat in subviews[i].sizeThatFits(.unspecified).height }.max() ?? 0
            höjd += h + lineSpacing
        }
        return CGSize(width: bredd == 10_000 ? 0 : bredd, height: max(0, höjd - lineSpacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y: CGFloat = bounds.minY
        for rad in rows(subviews, width: bounds.width) {
            var x: CGFloat = bounds.minX
            var h: CGFloat = 0
            for i in rad {
                let size: CGSize = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                h = max(h, size.height)
            }
            y += h + lineSpacing
        }
    }
}

// MARK: Delarna

/// En punkt på en linje; `segment` bryter linjen där värden saknas.
private struct CurvePoint: Identifiable {
    var time: Date
    var value: Double
    var segment: Int
    var id: Double { time.timeIntervalSince1970 }

    /// Ett nytt segment efter varje lucka, så att linjen inte dras över den.
    static func segmented(_ x: [(TimeInterval, Double?)]) -> [CurvePoint] {
        var ut: [CurvePoint] = []
        var segment = 0
        var förra = false
        for (t, v) in x {
            guard let v else { förra = false; continue }
            if !förra { segment += 1 }
            ut.append(CurvePoint(time: Date(timeIntervalSince1970: t), value: v, segment: segment))
            förra = true
        }
        return ut
    }

    /// Y-axelns spann med lite luft (minst `minLuft`, 1 om inget annat anges);
    /// utan värden 0–1. Hudtemperaturen rör sig några tiondelar och tar en liten luft.
    static func domain(_ x: [Double], minLuft: Double = 1) -> ClosedRange<Double> {
        guard let lo = x.min(), let hi = x.max() else { return 0...1 }
        let luft = max(minLuft, (hi - lo) * 0.08)
        return (lo - luft)...(hi + luft)
    }
}

/// En del av den typiska natten, lagd på den här nattens tidsaxel.
private struct BandPoint: Identifiable {
    var time: Date
    var lower: Double
    var upper: Double
    var id: Double { time.timeIntervalSince1970 }

    static func make(_ band: [NightCurve.Band], _ c: NightCurve.Curve) -> [BandPoint] {
        band.map { (b: NightCurve.Band) -> BandPoint in
            BandPoint(time: Date(timeIntervalSince1970: c.time(atFraction: b.fraction)), lower: b.lower, upper: b.upper)
        }
    }
}

/// Ett glapp att skugga: tiden, och orsaken om natten har lager (M32). Utan
/// orsak (en gammal inspelning) är glappet grått som förut.
private struct GapShade {
    var range: ClosedRange<TimeInterval>
    var cause: NightLayers.GapCause?

    static func make(curve: NightCurve.Curve, layers: NightLayers.Layers?) -> [GapShade] {
        if let l = layers {
            return l.gaps.map { (g: NightLayers.Gap) -> GapShade in GapShade(range: g.range, cause: g.cause) }
        }
        return curve.gaps.map { (r: ClosedRange<TimeInterval>) -> GapShade in GapShade(range: r, cause: nil) }
    }

    func color(strong: Bool) -> Color {
        if cause == .movement { return CurveColor.movement.opacity(strong ? 0.55 : 0.22) }
        return Color.secondary.opacity(strong ? 0.6 : 0.12)
    }
}

/// METOD M13 · METOD M32. Glappen som rutor över hela diagrammets höjd, färgade
/// efter orsak när natten har lager.
private struct GapMarks: ChartContent {
    let shades: [GapShade]
    let y: ClosedRange<Double>
    var strong: Bool = false

    @ChartContentBuilder var body: some ChartContent {
        ForEach(shades.indices, id: \.self) { (i: Int) in
            RectangleMark(xStart: .value("Tid", Date(timeIntervalSince1970: shades[i].range.lowerBound)),
                          xEnd: .value("Tid", Date(timeIntervalSince1970: shades[i].range.upperBound)),
                          yStart: .value("Y", y.lowerBound), yEnd: .value("Y", y.upperBound))
                .foregroundStyle(shades[i].color(strong: strong))
        }
    }
}

/// Den markerade tiden som en hårfin linje.
private struct Selection: ChartContent {
    let markerad: Date?

    @ChartContentBuilder var body: some ChartContent {
        if let t = markerad {
            RuleMark(x: .value("Tid", t))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }
}

/// Klockslagets etikett är centrerad på sin linje; inom 3,5 % av tidsaxeln från högerkanten kapas den (till
/// vänster ryms den, provet 2026-10-15).
private func rymsEtikett(_ t: Date, domän: ClosedRange<Date>) -> Bool {
    let spann: TimeInterval = domän.upperBound.timeIntervalSince(domän.lowerBound)
    return domän.upperBound.timeIntervalSince(t) >= spann * 0.035
}

private extension View {
    /// Gemensam tidsaxel: samma spann i alla diagram, hårfina timlinjer, och
    /// klockslagen bara under det sista. Y-axelns tal har fast bredd, så att
    /// diagrammens tidsaxlar ligger exakt under varandra.
    func curveAxes(domän: ClosedRange<Date>, y: ClosedRange<Double>, labels: Bool, yLabels: Bool = true) -> some View {
        self
            .chartXScale(domain: domän)
            .chartYScale(domain: y)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { v in
                    AxisGridLine()
                    // Ett klockslag precis vid kanten kapas (granskningen 2026-10-15: "02" blev "("), så det står
                    // bara där etiketten ryms.
                    if labels, let t: Date = v.as(Date.self), rymsEtikett(t, domän: domän) {
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { v in
                    if yLabels {
                        AxisGridLine()
                    }
                    AxisValueLabel {
                        // En decimal när spannet är smalt (andningen), annars
                        // blir etiketterna lika (provet 2026-10-12: 14, 14, 13, 13).
                        Text(yLabels ? (v.as(Double.self).map {
                            $0.formatted(.number.precision(.fractionLength(y.upperBound - y.lowerBound < 6 ? 1 : 0)))
                        } ?? "") : "")
                            .font(.caption2)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
    }
}

/// Den typiska natten: grå, för att den är sammanhang och inte en serie.
enum CurveColor {
    static let typical = Color.secondary.opacity(0.22)
    /// METOD M32. Rörelse: stapeln över gränsen och glappen med rörelse som orsak.
    static let movement = Color(red: 0.98, green: 0.70, blue: 0.10)
    /// METOD M44. Ljudets nivå över golvet: en neutral yta, eftersom händelserna bär färgen.
    static let sound = Color.secondary.opacity(0.5)
}

/// METOD M37 · BESLUT B46. Stadiernas färger och ordning. Nivån (index) ger
/// opaciteten: bandet bleknar där modellen är osäker. Lätt och djup är skilda i båda lägena: i mörkt läge var
/// de två blå nästan lika (CIELAB-avstånd 17), nu ljusblå mot mörkblå (48, mer än i ljust läge, 42); ordningen
/// och betydelsen är B46:s. Djupet mot ytan #1c1c1e: kontrast 3,3 (grafik kräver 3).
enum StageColor {
    /// BESLUT B63. Skissens stadiefärger (App/Tema.swift), samma i hela appen.
    static func color(_ s: SleepStage) -> Color {
        switch s {
        case .wake: return Tema.awake
        case .light: return Tema.light
        case .deep: return Tema.deep
        case .rem: return Tema.rem
        }
    }

    /// Opaciteten per nivå (0, 1, 2).
    static let opacity: [Double] = [0.35, 0.6, 0.9]

    /// Opaciteten för en nivå, begränsad till 0…2.
    static func level(_ n: Int) -> Double {
        opacity[min(max(n, 0), opacity.count - 1)]
    }

    /// Raden i bandet, nerifrån: djup, lätt, REM, vaken.
    static func lane(_ s: SleepStage) -> Double {
        switch s {
        case .deep: return 0
        case .light: return 1
        case .rem: return 2
        case .wake: return 3
        }
    }

    static func word(_ s: SleepStage) -> String {
        switch s {
        case .wake: return "vaken"
        case .light: return "lätt"
        case .deep: return "djup"
        case .rem: return "REM"
        }
    }
}
