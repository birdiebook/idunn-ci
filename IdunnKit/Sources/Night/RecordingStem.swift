import Foundation
import WhoopFrames

/// METOD M28 · BESLUT B48
/// Namnet på en gammal inspelning (appens `NightFiles.stem(for:)`): starten i
/// UTC, `2026-10-12T19-47-05Z`, med bindestreck där ISO 8601 har kolon så att
/// namnet går att använda som filnamn. Inspelningar gjordes före dygnsfilerna
/// (A1, BESLUT B30); de ligger kvar bredvid dygnen och har egna K18-notiser i
/// `<stam>.t2.jsonl`. Här bor tolkningen av namnet, för hand (BESLUT B6), så att
/// IdunnKit kan avgöra vilka nätter en inspelning berör utan att öppna den.
public enum RecordingStem {

    /// Ögonblicket inspelningen började, ur namnet. `nil` för allt som inte är
    /// `yyyy-MM-ddTHH-mm-ssZ`: dygnsfiler (`dygn-…`), nätter (`natt-…`) och
    /// okända namn.
    public static func start(ofStem s: String) -> Date? {
        let b: [UInt8] = Array(s.utf8)
        guard b.count == 20, b[4] == 45, b[7] == 45, b[10] == 84, b[13] == 45, b[16] == 45, b[19] == 90 else {
            return nil
        }
        func tal(_ från: Int, _ till: Int) -> Int? {
            var v: Int = 0
            for i in från..<till {
                guard b[i] >= 48, b[i] <= 57 else { return nil }
                v = v * 10 + Int(b[i] - 48)
            }
            return v
        }
        guard let y = tal(0, 4), let mo = tal(5, 7), let d = tal(8, 10),
              let h = tal(11, 13), let mi = tal(14, 16), let sek = tal(17, 19),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, sek < 60 else { return nil }
        return DayLog.date(of: DayLog.Day(year: y, month: mo, day: d), hour: h, minute: mi, utcOffsetSeconds: 0)
            .addingTimeInterval(Double(sek))
    }

    /// Namnet för en start. Det appen skriver är detsamma (ISO 8601 i UTC,
    /// kolon som bindestreck); den här skrivs för hand och används av proven.
    public static func stem(for start: Date) -> String {
        let sekunder: Int = Int(start.timeIntervalSince1970.rounded(.down))
        let dag: Int = Int((Double(sekunder) / 86_400).rounded(.down))
        let isDygnet: Int = sekunder - dag * 86_400
        func två(_ v: Int) -> String { v < 10 ? "0" + String(v) : String(v) }
        let d = DayLog.Day(daysSince1970: dag)
        let timme: String = två(isDygnet / 3600)
        let minut: String = två((isDygnet % 3600) / 60)
        let sekund: String = två(isDygnet % 60)
        return "\(d.text)T\(timme)-\(minut)-\(sekund)Z"
    }
}
