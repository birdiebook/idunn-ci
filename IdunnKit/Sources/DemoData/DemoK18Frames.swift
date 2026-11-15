// PÅHITTADE K18-ramar ur påhittade K18-poster (METOD M28, BESLUT B20). Inget
// kommer från ett riktigt band: posterna är `DemoK18Nights`/`DemoSleep`, här
// skrivs de som hela ramar med riktiga kontrollsummor (som `DemoListener`), i
// samma byteordning som `K18Record.decode` läser. Lägg ALDRIG in riktiga
// värden här — se CLAUDE.md §Dataregeln.
//
// Används av proven av appens väg: dygnsfiler (`.t2.jsonl`) som läses
// strömmande och blir en natt (`K18Days`, `NightLedger`), och av förhandsvisningen
// som ritar K18-nätter ur filer som appen själv skulle ha skrivit.

import Foundation
import WhoopFrames

public enum DemoK18Frames {

    /// Postens inre del (typ 47, familj 18, 112 byte): tid i i7, puls i i14,
    /// antal RR i i15 och RR i i16…, gravitationen som f32 i i37/41/45, bandets
    /// temperatur i i61 (/10) och hudens i i65 (/100).
    public static func inner(_ r: K18Record) -> [UInt8] {
        var b: [UInt8] = [UInt8](repeating: 0, count: 112)
        b[0] = UInt8(K18Record.packetType)
        b[1] = UInt8(K18Record.family)
        put32(&b, 7, UInt32(truncatingIfNeeded: r.time))
        b[14] = UInt8(max(0, min(255, r.pulse)))
        let rr: [Int] = Array(r.rr.prefix(4))
        b[15] = UInt8(rr.count)
        for (k, x) in rr.enumerated() { put16(&b, 16 + 2 * k, UInt16(max(0, min(65_535, x)))) }
        put32(&b, 37, Float(r.gravity.x).bitPattern)
        put32(&b, 41, Float(r.gravity.y).bitPattern)
        put32(&b, 45, Float(r.gravity.z).bitPattern)
        put16(&b, 61, UInt16(max(0, min(65_535, (r.bandTemperature * 10).rounded()))))
        put16(&b, 65, UInt16(max(0, min(65_535, (r.skinTemperature * 100).rounded()))))
        return b
    }

    /// En notis med en hel ram, hörd (av telefonen) vid `heard`.
    public static func notification(_ r: K18Record, heard: Double) -> RawFrame {
        DemoListener.note(heard, inner(r))
    }

    /// Posterna som notiser, var och en hörd samma sekund som den mättes plus
    /// `delay` sekunder (en synk som hörs efteråt).
    public static func notifications(_ records: [K18Record], delay: Double = 0) -> [RawFrame] {
        records.map { (r: K18Record) -> RawFrame in notification(r, heard: Double(r.time) + delay) }
    }

    /// Notiserna som en dygnsfils innehåll (`.t2.jsonl`).
    public static func log(_ notes: [RawFrame]) -> Data {
        var d = Data()
        for n in notes { d.append(RawFrameLog.line(n)) }
        return d
    }

    static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for k in 0..<4 { b[o + k] = UInt8((v >> UInt32(8 * k)) & 0xFF) }
    }

    static func put16(_ b: inout [UInt8], _ o: Int, _ v: UInt16) {
        b[o] = UInt8(v & 0xFF)
        b[o + 1] = UInt8(v >> 8)
    }
}
