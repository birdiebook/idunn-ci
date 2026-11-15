// PÅHITTADE notiser för lyssnarens vy (BESLUT B20, B30). Inget kommer från ett
// riktigt band: en K18-post per minut med bara tiden satt, och en färdig synk
// (HISTORY_COMPLETE). Lägg ALDRIG in riktiga värden här — se CLAUDE.md
// §Dataregeln.

import Foundation
import WhoopFrames

public enum DemoListener {

    /// En K18-post per minut i `[start, end)`, utom där `gap` (andelar av
    /// intervallet, 0…1) ligger, och en färdig synk vid `syncAt`. Hörda när de
    /// mäts, på `…0005`, med riktiga kontrollsummor.
    public static func notifications(start: Date, end: Date, gap: ClosedRange<Double>? = nil,
                                     syncAt: Date? = nil) -> [RawFrame] {
        let first: Int = Int((start.timeIntervalSince1970 / 60).rounded(.up))
        let last: Int = Int((end.timeIntervalSince1970 / 60).rounded(.down))
        var ut: [RawFrame] = []
        if last > first {
            for minut in first..<last {
                let andel: Double = Double(minut - first) / Double(last - first)
                if let g = gap, g.contains(andel) { continue }
                let t: Int = minut * 60
                ut.append(note(Double(t), k18(time: t)))
            }
        }
        if let s = syncAt {
            ut.append(note(s.timeIntervalSince1970, complete(time: Int(s.timeIntervalSince1970))))
        }
        return ut
    }

    static func note(_ heard: Double, _ inner: [UInt8]) -> RawFrame {
        RawFrame(time: Date(timeIntervalSince1970: heard), characteristic: "fd4b0005", bytes: frame(inner))
    }

    /// K18 (typ 47, familj 18, 112 byte) med tiden i i7.
    static func k18(time: Int) -> [UInt8] {
        var b: [UInt8] = [UInt8](repeating: 0, count: 112)
        b[0] = 47
        b[1] = 18
        put32(&b, 7, UInt32(time))
        return b
    }

    /// HISTORY_COMPLETE (typ 49, i2 = 3, 12 byte).
    static func complete(time: Int) -> [UInt8] {
        var b: [UInt8] = [UInt8](repeating: 0, count: 12)
        b[0] = 49
        b[2] = 3
        put32(&b, 3, UInt32(time))
        return b
    }

    static func put32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        for k in 0..<4 { b[o + k] = UInt8((v >> UInt32(8 * k)) & 0xFF) }
    }

    /// En hel ram med båda kontrollsummorna (METOD M12).
    static func frame(_ inner: [UInt8]) -> [UInt8] {
        let length: Int = inner.count + 4
        var b: [UInt8] = [0xAA, 0x01, UInt8(length & 0xFF), UInt8(length >> 8), 0x00, 0x01]
        let h: UInt16 = FrameAssembly.crc16Modbus(b)
        b += [UInt8(h & 0xFF), UInt8(h >> 8)]
        b += inner
        let c: UInt32 = FrameAssembly.crc32(inner)
        for k in 0..<4 { b.append(UInt8((c >> UInt32(8 * k)) & 0xFF)) }
        return b
    }
}
