import Foundation
import HeartRate
import WhoopFrames

/// METOD M28 · METOD M24 · METOD M26 · BESLUT B28
/// Från K18:s poster till samma slagsekvens som analysen tar i dag: en
/// `NightRecording` med en notis per sekund, där RR är det K18-posten bär
/// (i15/i16…) och pulsen är i14. Allt efter det (rensningen M3, HRV M4,
/// vilopuls M5, andning M10, kurvan M18, landskapet M22, Poincaré M21) är
/// oförändrat, så att ett tal bara kan skilja sig för att K18 har en annan
/// form än 2A37.
///
/// **Tiden per slag (antagande).** Posten stämplad `t` (i7) antas bära de slag
/// som tog slut under sekunden före `t`, alltså samma tolkning som notisens tid
/// i 2A37 (METOD M3: slagen blev klara före notisen). Därefter läggs slagen ut
/// som förut: intervallen själva är klockan, och en post som ligger mer än
/// `RRCleaning.reanchorSeconds` från den klockan lägger om sina slag. Om
/// bandet i stället stämplar sekunden där slagen börjar skiftar hela axeln
/// högst en sekund, vilket varken HRV eller vilopuls märker; en axel som
/// glider syns som många omläggningar i `RRCleaning.Summary`.
///
/// **Glapp (METOD M3, BESLUT B17).** En sekund utan post är okänd, inte
/// slaglös. Saknas en eller flera sekunder mellan två poster (högst
/// `RRCleaning.gapSeconds`) läggs en notis utan RR in för varje saknad
/// sekund, så att utelämningssökningen (`Omissions`) ser hålet som den ser
/// en rörelsesekund utan RR och märker slagen som fattas: ingen skillnad
/// räknas över dem. Ett glapp över gränsen delar natten i avsnitt som förut.
public enum K18Beats {

    /// METOD M28. En minuts puls ur i14 räknas bara med så här många sekunder.
    /// **Antagande:** en halv minut; en minut med färre är mest glapp.
    public static let minPulseSeconds = 30

    /// En K18-post som den notis den ersätter.
    public static func sample(_ r: K18Record) -> HeartRateSample {
        HeartRateSample(time: Date(timeIntervalSince1970: Double(r.time)), bpm: r.pulse,
                        rrMilliseconds: r.rr.map { (x: Int) -> Double in Double(x) })
    }

    /// METOD M28. Posterna från och med `onset` till före `wake` (Unix-sekunder,
    /// sömnperioden ur METOD M26) som en inspelning. Batteriet saknas.
    public static func recording(_ series: K18Series, onset: Int, wake: Int) -> NightRecording {
        var samples: [HeartRateSample] = []
        var previous: Int?
        for r in series.records where r.time >= onset && r.time < wake {
            if let p = previous, r.time - p > 1, r.time - p <= Int(RRCleaning.gapSeconds) {
                for s in (p + 1)..<r.time {
                    samples.append(HeartRateSample(time: Date(timeIntervalSince1970: Double(s)), bpm: 0,
                                                   rrMilliseconds: []))
                }
            }
            samples.append(sample(r))
            previous = r.time
        }
        return NightRecording(samples: samples)
    }

    /// METOD M28. Pulsen per Unix-minut: medianen av minutens pulsvärden (i14
    /// för K18, 2A37:s puls för en gammal inspelning; 0 räknas inte), för
    /// minuter med minst `minPulseSeconds` värden. Kurvans egen puls (METOD
    /// M18) är fortfarande 60000 / medelintervall; den här serien är bandets
    /// egen siffra, och finns också där RR saknas.
    public static func pulsePerMinute(_ recording: NightRecording) -> [PulseMinute] {
        var byMinute: [Int: [Double]] = [:]
        for s in recording.samples where s.bpm > 0 {
            let minute: Int = Int((s.time.timeIntervalSince1970 / 60).rounded(.down))
            byMinute[minute, default: []].append(Double(s.bpm))
        }
        var out: [PulseMinute] = []
        for minute in byMinute.keys.sorted() {
            let v: [Double] = byMinute[minute] ?? []
            guard v.count >= minPulseSeconds, let med = Statistics.median(v) else { continue }
            out.append(PulseMinute(minute: minute, bpm: med, seconds: v.count))
        }
        return out
    }
}

/// METOD M28. Bandets egen puls för en Unix-minut.
public struct PulseMinute: Equatable, Sendable {
    /// Unix-minuten (`tid / 60`).
    public var minute: Int
    /// Medianen av minutens pulsvärden, slag per minut.
    public var bpm: Double
    /// Antal värden bakom medianen.
    public var seconds: Int

    public var start: Date { Date(timeIntervalSince1970: Double(minute * 60)) }
}
