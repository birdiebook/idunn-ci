// PÅHITTADE K18-nätter med RR (METOD M28, BESLUT B28). Inget kommer från ett
// riktigt band: gravitationerna är `DemoSleep`:s faser (en post per sekund),
// och slagen är `DemoNights`:s formel och seedade slumpgenerator. Lägg ALDRIG
// in riktiga värden här — se CLAUDE.md §Dataregeln.
//
// Samma slag kan ges som K18-poster (RR i hela millisekunder, högst fyra per
// sekund, pulsen i i14) och som 2A37-mätningar (RR i 1/1024 s, eller i hela
// millisekunder när provet vill isolera allt utom formen), så att provet kan
// räkna en natt båda vägarna. En post eller notis bär de slag som tog slut
// under sekunden före dess tid. Slag i sekunder utan post (glappen) är
// förlorade i båda.
//
// Formen: uppe en stund, två till tre timmars sömn, ett glapp på 3–7 minuter,
// en orolig stund, mer sömn (med två korta glapp om `shortGaps`) och uppe igen.
// RR finns bara under sömnen: en arm i rörelse ger inga RR (PROTOKOLL_W5 §6).
// Med `movementBout` rör sig armen `boutMinutes` minuter (förvalt fyra) mitt i sömnen och bandet ger då
// inga RR, så att kurvan får ett glapp vars orsak är rörelse (METOD M32) och natten har minuter i
// rörelse (METOD M42). `nights(…, movementBouts: true)` ger varje natt ett sådant avsnitt med olika längd.
// Med `stages` följer slagen ett påhittat hypnogram (`DemoStages`, METOD M37),
// så att stadiemodellen ger vaken, lätt, djup och REM; gravitationen är densamma.

import Foundation
import HeartRate
import WhoopFrames

public enum DemoK18Nights {

    /// Hur RR skrivs i 2A37-mätningarna.
    public enum RRForm: Sendable {
        /// Hela millisekunder, som K18 bär dem: allt utom formen är lika.
        case wholeMilliseconds
        /// Bandets 1/1024 s (METOD M1), som en riktig 2A37-notis.
        case units1024
    }

    public struct Night: Equatable, Sendable {
        /// Zonen natten är påhittad i.
        public var utcOffsetSeconds: Int
        /// Facit: första sömnsekunden och sekunden efter den sista.
        public var onset: Int
        public var wake: Int
        /// K18-posterna, en per sekund utom i glappen.
        public var records: [K18Record]
        /// De sanna slagen (millisekunder, ej avrundade) i varje post, i samma
        /// ordning som `records`.
        public var beats: [[Double]]

        /// Samma sekunder som 2A37-mätningar. `jitter` lägger en slumpad
        /// ankomsttid mellan 0 och `jitter` sekunder på varje notis, som
        /// radion gör; 0 ger heltalssekunder som K18.
        public func measurements(_ form: RRForm = .wholeMilliseconds, jitter: Double = 0,
                                 seed: UInt64 = 1) -> [(time: Date, measurement: HeartRateMeasurement)] {
            var r = Seeded(seed)
            var out: [(time: Date, measurement: HeartRateMeasurement)] = []
            out.reserveCapacity(records.count)
            for (i, rec) in records.enumerated() {
                let rr: [Double] = beats[i].prefix(4).map { (ms: Double) -> Double in
                    switch form {
                    case .wholeMilliseconds: return ms.rounded()
                    case .units1024: return DemoNights.quantized(ms)
                    }
                }
                let late: Double = jitter > 0 ? jitter * r.uniform() : 0
                let m = HeartRateMeasurement(bpm: rec.pulse, sensorContact: .detected, rrMilliseconds: rr,
                                             flags: rr.isEmpty ? 0x06 : 0x16)
                out.append((time: Date(timeIntervalSince1970: Double(rec.time) + late), measurement: m))
            }
            return out
        }
    }

    /// `count` nätter, en per morgon, äldst först; den sista vaknar
    /// `DemoNights.lastWakeDayUTC`. Samma seed ger samma nätter. Med `movementBouts` har varje natt ett
    /// avsnitt med armen i rörelse av olika längd (`boutMinutes(daysBeforeLast:seed:)`), så att Morgon och
    /// Över tid får minuter i rörelse som varierar (METOD M42); utan är nätterna som förut.
    public static func nights(count: Int, seed: UInt64 = 1, shortGaps: Bool = true,
                              stages: Bool = false, movementBouts: Bool = false) -> [Night] {
        (0..<count).reversed().map { (k: Int) -> Night in
            night(daysBeforeLast: k, seed: seed, shortGaps: shortGaps, movementBout: movementBouts,
                  boutMinutes: boutMinutes(daysBeforeLast: k, seed: seed), stages: stages)
        }
    }

    /// METOD M42. Hur många minuter armen rör sig i natten `k` morgnar före den sista när `movementBouts` är
    /// på: 1 till 12, kring sex. En egen slumpström, så att ingen annan natt ändras av att den finns.
    public static func boutMinutes(daysBeforeLast k: Int, seed: UInt64 = 1) -> Int {
        var r = Seeded(seed &+ UInt64(k) &* 6151 &+ 4242)
        let n: Int = 6 + Int((2.5 * r.gauss()).rounded())
        return min(12, max(1, n))
    }

    /// Natten som slutar `k` morgnar före den sista. Med `shortGaps` ligger två
    /// korta glapp (6 och 25 sekunder) i sömnen, utöver det långa. Med `movementBout` rör sig armen
    /// `boutMinutes` minuter efter den oroliga stunden. Med `stages` följer slagen ett påhittat hypnogram
    /// (METOD M37); utan är natten som förut.
    public static func night(daysBeforeLast k: Int, seed: UInt64 = 1, shortGaps: Bool = true,
                             movementBout: Bool = false, boutMinutes: Int = 4, stages: Bool = false) -> Night {
        var r = Seeded(seed &+ UInt64(k) &* 6151 &+ 17)
        let minute: Int = 60
        let offset: Int = DemoNights.utcOffsetSeconds
        let midnatt: Int = Int(DemoNights.lastWakeDayUTC) - k * 86_400 - offset
        let start: Int = midnatt - 9_000 // 21:30 lokal tid
        let up: Int = (20 + Int(r.uniform() * 20)) * minute
        let a: Int = (150 + Int(r.uniform() * 60)) * minute
        let longGap: Int = 180 + Int(r.uniform() * 240)
        let rest: Int = (10 + Int(r.uniform() * 10)) * minute
        let b: Int = (150 + Int(r.uniform() * 90)) * minute
        let after: Int = 25 * minute

        var phases: [DemoSleep.Phase] = [
            .active(seconds: up),
            .still(seconds: a / 2), .turn, .still(seconds: a / 2),
            .gap(seconds: longGap),
            .restless(seconds: rest, every: 100),
        ]
        var sleepSeconds: Int = 2 * (a / 2) + longGap + rest
        // `boutMinutes` minuter med armen i rörelse efter den oroliga stunden: inga RR.
        let boutSeconds: Int = boutMinutes * minute
        let boutStart: Int = start + up + sleepSeconds
        if movementBout {
            phases.append(.active(seconds: boutSeconds))
            sleepSeconds += boutSeconds
        }
        if shortGaps {
            phases += [.still(seconds: b / 4), .gap(seconds: 6), .still(seconds: b / 4), .turn,
                       .still(seconds: b / 4), .gap(seconds: 25), .still(seconds: b / 4)]
            sleepSeconds += 4 * (b / 4) + 31
        } else {
            phases += [.still(seconds: b / 2), .turn, .still(seconds: b / 2)]
            sleepSeconds += 2 * (b / 2)
        }
        phases.append(.active(seconds: after))
        let onset: Int = start + up
        let wake: Int = onset + sleepSeconds

        let base: [K18Record] = DemoSleep.records(start: start, phases: phases, seed: seed &+ UInt64(k))

        // Slagen under sömnen, med tid i sekunder efter insomning. Ett slag
        // hör till sekunden som slutar efter att det tog slut.
        var rb = Seeded(seed &+ UInt64(k) &* 6151 &+ 99)
        let ms: [Double]
        if stages {
            // METOD M37. Hypnogrammet har en egen ström: slagens slumpdrag ligger i `rb`;
            // den oroliga stunden (`restless`) är vaken.
            var rh = Seeded(seed &+ UInt64(k) &* 6151 &+ 7)
            let oroligStart: Int = 2 * (a / 2) + longGap
            let hypnogram: [DemoStages.Stage] = DemoStages.hypnogram(
                epochs: sleepSeconds / 30 + 2, wakeWindows: [(from: oroligStart, to: oroligStart + rest)], random: &rh)
            ms = DemoStages.beats(seconds: Double(sleepSeconds), hypnogram: hypnogram, random: &rb)
        } else {
            ms = DemoNights.beats(seconds: Double(sleepSeconds), random: &rb)
        }
        var second: [Int] = []
        var omitted: [Bool] = []
        var t: Double = 0
        for x in ms {
            t += x / 1000
            second.append(onset + Int(t.rounded(.up)))
            // Bandet hoppar över enstaka slag (METOD M3): tiden går, intervallet kommer inte.
            omitted.append(rb.uniform() < 0.003)
        }

        var records: [K18Record] = []
        var trueBeats: [[Double]] = []
        records.reserveCapacity(base.count)
        var p: Int = 0
        var recent: [Double] = []
        for var rec in base {
            var mine: [Double] = []
            while p < ms.count && second[p] <= rec.time {
                let rörelse: Bool = movementBout && rec.time >= boutStart && rec.time < boutStart + boutSeconds
                if second[p] == rec.time && !omitted[p] && !rörelse { mine.append(ms[p]) }
                recent.append(ms[p])
                if recent.count > 5 { recent.removeFirst() }
                p += 1
            }
            var sum: Double = 0
            for x in recent { sum += x }
            if rec.time < onset || rec.time >= wake {
                rec.pulse = awakePulse(rec.time)
            } else {
                rec.pulse = recent.isEmpty ? 62 : Int((60_000 / (sum / Double(recent.count))).rounded())
            }
            rec.rr = mine.prefix(4).map { (x: Double) -> Int in Int(x.rounded()) }
            records.append(rec)
            trueBeats.append(mine)
        }
        return Night(utcOffsetSeconds: offset, onset: onset, wake: wake, records: records, beats: trueBeats)
    }

    /// BESLUT B99. Bandets puls när demonatten är vaken, före insomningen och efter uppvaknandet: kring 72 slag per
    /// minut med långsamma och snabbare svängningar, så att provets kanter (pulsen utanför sömnen) visar en kurva som
    /// rör sig och inte en rak linje. Utan slump, så att nattens andra slumpströmmar står still.
    static func awakePulse(_ t: Int) -> Int {
        let s: Double = Double(t)
        return Int((72 + 7 * sin(s / 400) + 4 * sin(s / 97) + 2 * sin(s / 23)).rounded())
    }
}
