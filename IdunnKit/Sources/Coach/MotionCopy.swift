import Foundation

/// BESLUT B148 · METOD M84
/// Passets rörelse till utvecklingen: passets rörelsefil (`PassMotion` i appen, dygnsarkivets form) som kropp i ett
/// anrop till mottagaren `idunn-rorelse`, som lägger den i den privata hinken `rorelse` med ett eget tak. Filen kommer
/// in som byte från appen; `Coach` känner inte dess innehåll.
public enum MotionCopyRules {
    /// **antagande**. Största fil som mottagaren tar emot (ett pass på 3 timmar är runt 15 MB).
    public static let maxBytes: Int = 20 * 1024 * 1024
    public static let path: String = "/functions/v1/idunn-rorelse"

    /// Passets namn `yyyy-MM-dd-HHmmss` (som passets fil, `PassFile.stamp`).
    public static func isValidPass(_ pass: String) -> Bool {
        let delar: [Substring] = pass.split(separator: "-", omittingEmptySubsequences: false)
        guard delar.count == 4, delar[3].count == 6, delar[3].allSatisfy({ (c: Character) -> Bool in
            c >= "0" && c <= "9"
        }) else { return false }
        guard DayCopyRules.isValidDay(delar[0...2].joined(separator: "-")),
              let h = Int(delar[3].prefix(2)), let m = Int(delar[3].dropFirst(2).prefix(2)),
              let s = Int(delar[3].suffix(2)) else { return false }
        return h < 24 && m < 60 && s < 60
    }
}

extension CoachCall {
    /// BESLUT B148 · METOD M84. Laddar upp ett pass rörelse. `nil` när kopplingen är ogiltig, passets namn inte har
    /// formen, eller filen är tom eller större än `MotionCopyRules.maxBytes`.
    public static func motionCopy(config: CoachConfig, pass: String, file: Data) -> CoachCall? {
        guard config.isValid, MotionCopyRules.isValidPass(pass), !file.isEmpty,
              file.count <= MotionCopyRules.maxBytes else { return nil }
        let headers: [String: String] = [
            "apikey": config.key,
            "Content-Type": "application/octet-stream",
            "Accept": "application/json",
            "x-idunn-token": config.token,
            "x-idunn-pass": pass,
            "x-idunn-storlek": String(file.count),
        ]
        return CoachCall(host: config.host, path: MotionCopyRules.path, headers: headers, body: file)
    }
}
