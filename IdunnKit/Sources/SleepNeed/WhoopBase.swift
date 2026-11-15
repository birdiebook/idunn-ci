import Foundation
import WhoopImport

/// BESLUT B67 · METOD M53
/// Whoops grundbehov ur den importerade exporten, på telefonen: varje sömnpass som inte är en tupplur ger paret
/// (strain dygnet före, behov − skuld), och `SleepNeed.whoopBase(pairs:)` tar medianen efter de lugnaste dygnen.
/// Talet lämnar aldrig telefonen (dataregeln) och används bara som en observation i grundbehovet.
extension SleepNeed {
    public static func whoopBase(_ export: WhoopExport) -> Double? {
        let cycles = export.cycles.sorted { $0.start < $1.start }
        var index: [Date: Int] = [:]
        for (i, c) in cycles.enumerated() { index[c.start] = i }
        var pairs: [(strain: Double, base: Double)] = []
        for s in export.sleeps where !s.isNap {
            guard let need = s.needMinutes, let debt = s.debtMinutes,
                  let i = index[s.cycleStart], i > 0, let strain = cycles[i - 1].dayStrain else { continue }
            pairs.append((strain: strain, base: Double(need - debt)))
        }
        return whoopBase(pairs: pairs)
    }
}
