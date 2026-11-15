// PÅHITTAD Whoop-historik för förhandsvisningen (målet IdunnProv). Samma
// kolumner och format som en riktig export (WhoopImportTests/Fixtures.swift),
// men varje värde räknas fram ur en formel och en seedad slumpgenerator. Lägg
// ALDRIG in riktiga rader här — se CLAUDE.md §Dataregeln.
//
// Formen: HRV och vilopuls som svänger långsamt, en sjukvecka med låg HRV och
// hög vilopuls, fyra nätter utan band (tomma mått), senare läggdags på helger,
// en tupplur då och då, och överst det pågående dygnet med tom sluttid.
// Texten går genom den riktiga tolkningen (`WhoopExport.parseCycles`).

import Foundation
import WhoopImport

public enum DemoWhoop {
    /// Dygnens zon: sommartid hela perioden.
    public static let utcOffsetSeconds = DemoNights.utcOffsetSeconds

    /// Exporten tolkad, äldst först. `days` morgnar som slutar
    /// `DemoNights.lastWakeDayUTC`.
    public static func export(days: Int = 150, seed: UInt64 = 2) -> WhoopExport {
        let csv = files(days: days, seed: seed)
        // Formatet är exportens; går det inte att tolka är generatorn trasig.
        // swiftlint:disable:next force_try
        return WhoopExport(cycles: try! WhoopExport.parseCycles(csv.cycles),
                           sleeps: try! WhoopExport.parseSleeps(csv.sleeps),
                           journal: [])
    }

    /// Filerna som text, senast först som i en riktig export.
    public static func files(days: Int = 150, seed: UInt64 = 2) -> (cycles: String, sleeps: String) {
        var r = Seeded(seed)
        let zon = zoneText(utcOffsetSeconds)

        struct Natt {
            var onset: TimeInterval
            var wake: TimeInterval
            var hasData: Bool
            var hrv: Int
            var rhr: Int
            var resp: Double
            var skin: Double
            var spo2: Double
            var strain: Double
            var recovery: Int
            var nap: (TimeInterval, Int)?
        }

        var nätter: [Natt] = []
        for k in (0..<days).reversed() {
            let d = days - 1 - k   // 0 = äldsta
            let midnatt: TimeInterval = DemoNights.lastWakeDayUTC - Double(k) * 86_400 - Double(utcOffsetSeconds)
            // Veckodag för uppvakningsdagen (1970-01-01 var en torsdag): lördag
            // och söndag morgon följer en sen kväll.
            let dag = Int((DemoNights.lastWakeDayUTC - Double(k) * 86_400) / 86_400)
            let veckodag = (dag + 4) % 7   // 0 = söndag
            let helg = veckodag == 0 || veckodag == 6
            let onset: TimeInterval = midnatt - 3_600 + (helg ? 2_700 : 0) + 1_800 * DemoNights.clamp(r.gauss(), -2, 2)
            let wake: TimeInterval = onset + 3_600 * (7.8 + 0.5 * DemoNights.clamp(r.gauss(), -2.4, 2.4))

            let svaj: Double = 0.10 * sin(2 * Double.pi * Double(d) / 41)
            let sjuk: Double = (100...106).contains(d) ? 1 : 0
            let lnHRV: Double = log(58) + svaj - 0.32 * sjuk + 0.14 * r.gauss()
            let hrv = Int(exp(lnHRV).rounded())
            let rhr = Int((52 - 18 * svaj + 5 * sjuk + 1.6 * r.gauss()).rounded())
            let z: Double = (lnHRV - log(58)) / 0.16
            let recovery = Int(min(99, max(2, 62 + 22 * z - 2 * Double(rhr - 52))).rounded())
            let nap: (TimeInterval, Int)? = d % 9 == 4 ? (midnatt + 14 * 3_600, 20 + Int(r.uniform() * 15)) : nil
            nätter.append(Natt(onset: onset, wake: wake, hasData: !(60...63).contains(d),
                               hrv: hrv, rhr: rhr,
                               resp: 14.6 + 0.3 * r.gauss() + 1.1 * sjuk,
                               skin: 33.9 + 0.25 * r.gauss() + 0.6 * sjuk,
                               spo2: 96.2 + 0.6 * r.gauss(),
                               strain: 6 + 4 * r.uniform() + (veckodag == 3 ? 6 : 0),
                               recovery: recovery, nap: nap))
        }

        var cykler: [String] = [
            "Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Resting heart rate (bpm),"
            + "Heart rate variability (ms),Skin temp (celsius),Blood oxygen %,Day Strain,Energy burned (cal),"
            + "Max HR (bpm),Average HR (bpm),Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),"
            + "Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),"
            + "REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,"
            + "Sleep consistency %",
        ]
        var sömn: [String] = [
            "Cycle start time,Cycle end time,Cycle timezone,Sleep onset,Wake onset,Sleep performance %,"
            + "Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),"
            + "Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),"
            + "Sleep debt (min),Sleep efficiency %,Sleep consistency %,Nap",
        ]

        // Det pågående dygnet: började i kväll, ingen sluttid, inga mått.
        let ikväll: TimeInterval = DemoNights.lastWakeDayUTC - Double(utcOffsetSeconds) + 23 * 3_600
        cykler.append("\(wall(ikväll)),,\(zon)" + String(repeating: ",", count: 23))

        var nästaStart = ikväll
        for n in nätter.reversed() {
            let start = wall(n.onset)
            let slut = wall(nästaStart)
            nästaStart = n.onset
            let iSäng = Int(((n.wake - n.onset) / 60).rounded())
            let vaken = 25 + Int(r.uniform() * 30)
            let sover = iSäng - vaken
            let djup = Int(Double(sover) * (0.19 + 0.04 * r.uniform()))
            let rem = Int(Double(sover) * (0.22 + 0.05 * r.uniform()))
            let lätt = sover - djup - rem
            let behov = 490 + Int(r.uniform() * 30)
            let skuld = max(0, behov - sover)
            let prestation = min(100, Int((100 * Double(sover) / Double(behov)).rounded()))
            let effektivitet = Int((100 * Double(sover) / Double(iSäng)).rounded())
            let jämnhet = 70 + Int(r.uniform() * 20)
            guard n.hasData else {
                cykler.append("\(start),\(slut),\(zon)" + String(repeating: ",", count: 23))
                continue
            }
            let sömnfält = "\(prestation),\(f1(n.resp)),\(sover),\(iSäng),\(lätt),\(djup),\(rem),\(vaken),"
                + "\(behov),\(skuld),\(effektivitet),\(jämnhet)"
            cykler.append("\(start),\(slut),\(zon),\(n.recovery),\(n.rhr),\(n.hrv),\(f1(n.skin)),\(f1(n.spo2)),"
                + "\(f1(n.strain)),\(1900 + Int(r.uniform() * 900)),\(140 + Int(r.uniform() * 40)),"
                + "\(n.rhr + 14),\(wall(n.onset)),\(wall(n.wake)),\(sömnfält)")
            if let nap = n.nap {
                let (napStart, napMin) = nap
                sömn.append("\(start),\(slut),\(zon),\(wall(napStart)),\(wall(napStart + Double(napMin + 3) * 60)),"
                    + "100,\(f1(n.resp)),\(napMin),\(napMin + 3),\(napMin - 6),3,3,3,0,0,88,,true")
            }
            sömn.append("\(start),\(slut),\(zon),\(wall(n.onset)),\(wall(n.wake)),\(sömnfält),false")
        }
        return (cykler.joined(separator: "\n") + "\n", sömn.joined(separator: "\n") + "\n")
    }

    // MARK: Formatet

    /// Väggklockan `yyyy-MM-dd HH:mm:ss` i dygnens zon, räknad för hand så att
    /// telefonens språk och zon inte spelar in (som `WhoopTime`).
    static func wall(_ t: TimeInterval) -> String {
        let s = Int((t + Double(utcOffsetSeconds)).rounded(.down))
        let dagar = s >= 0 ? s / 86_400 : (s - 86_399) / 86_400
        let sek = s - dagar * 86_400
        let (y, m, d) = civil(dagar)
        return "\(pad(y, 4))-\(pad(m))-\(pad(d)) \(pad(sek / 3_600)):\(pad(sek % 3_600 / 60)):\(pad(sek % 60))"
    }

    /// Dagar sedan 1970-01-01 som år, månad och dag (Hinnants `civil_from_days`).
    static func civil(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (y, m, d)
    }

    static func zoneText(_ offset: Int) -> String {
        let tecken = offset < 0 ? "-" : "+"
        let a = abs(offset)
        return "UTC\(tecken)\(pad(a / 3_600)):\(pad(a % 3_600 / 60))"
    }

    static func pad(_ x: Int, _ n: Int = 2) -> String {
        let s = String(x)
        return String(repeating: "0", count: max(0, n - s.count)) + s
    }

    /// En decimal med punkt, som i exporten.
    static func f1(_ x: Double) -> String {
        let tiondelar = Int((x * 10).rounded())
        let tecken = tiondelar < 0 ? "-" : ""
        let a = abs(tiondelar)
        return "\(tecken)\(a / 10).\(a % 10)"
    }
}
