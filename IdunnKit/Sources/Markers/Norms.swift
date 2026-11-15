import Foundation

/// BESLUT B104 · METOD M59
/// Normtabellerna som profilen använder. Varje tabell är läst i original (docs/KALLOR.md K57, K58) och står med sina
/// tal i METOD M59; `MarkersTests` jämför dem med källans tal. En ny tabell läggs in först när artikeln är läst:
/// hellre ingen plats bland jämnåriga än en ur ett tal ingen har sett.
public enum Norms {
    /// Tabellerna i bruk. HRV och vilopuls har ingen: se METOD M59.
    public static let published: [NormTable] = [gripStrength, vo2max].compactMap { (t: NormTable?) -> NormTable? in t }

    /// METOD M59 · KALLOR K57. Greppstyrka i kg: Dodds m.fl. 2014 (PLoS ONE 9(12):e113637), tabell 2. Tolv brittiska
    /// studier, centilerna 10, 25, 50, 75 och 90 vid exakta åldrar 5–90 år, bästa försöket (oftast sex försök, båda
    /// händerna). Raderna är skrivna av ett skript ur artikelns XML, inte för hand.
    static let gripStrength: NormTable? = NormTable(
        marker: .gripStrength, source: "Dodds m.fl. 2014", percentiles: [10, 25, 50, 75, 90], trend: .declines,
        ages: 5...90,
        rows: [
            .male: [
                NormTable.Row(age: 5, [6, 7, 8, 9, 10]),
                NormTable.Row(age: 10, [12, 15, 17, 20, 22]),
                NormTable.Row(age: 15, [21, 25, 29, 33, 38]),
                NormTable.Row(age: 20, [30, 35, 40, 46, 52]),
                NormTable.Row(age: 25, [36, 41, 48, 55, 61]),
                NormTable.Row(age: 30, [38, 44, 51, 58, 64]),
                NormTable.Row(age: 35, [39, 45, 51, 58, 64]),
                NormTable.Row(age: 40, [38, 44, 50, 57, 63]),
                NormTable.Row(age: 45, [36, 42, 49, 56, 61]),
                NormTable.Row(age: 50, [35, 41, 48, 54, 60]),
                NormTable.Row(age: 55, [34, 40, 47, 53, 59]),
                NormTable.Row(age: 60, [33, 39, 45, 51, 56]),
                NormTable.Row(age: 65, [31, 37, 43, 48, 53]),
                NormTable.Row(age: 70, [29, 34, 39, 44, 49]),
                NormTable.Row(age: 75, [26, 31, 35, 41, 45]),
                NormTable.Row(age: 80, [23, 27, 32, 37, 42]),
                NormTable.Row(age: 85, [19, 24, 29, 33, 38]),
                NormTable.Row(age: 90, [16, 20, 25, 29, 33]),
            ],
            .female: [
                NormTable.Row(age: 5, [6, 7, 8, 9, 10]),
                NormTable.Row(age: 10, [12, 14, 16, 19, 21]),
                NormTable.Row(age: 15, [17, 20, 24, 27, 30]),
                NormTable.Row(age: 20, [21, 24, 28, 32, 36]),
                NormTable.Row(age: 25, [23, 26, 30, 35, 38]),
                NormTable.Row(age: 30, [24, 27, 31, 35, 39]),
                NormTable.Row(age: 35, [23, 27, 31, 35, 39]),
                NormTable.Row(age: 40, [23, 27, 31, 35, 39]),
                NormTable.Row(age: 45, [22, 26, 30, 34, 38]),
                NormTable.Row(age: 50, [21, 25, 29, 33, 37]),
                NormTable.Row(age: 55, [19, 23, 28, 32, 35]),
                NormTable.Row(age: 60, [18, 22, 27, 31, 34]),
                NormTable.Row(age: 65, [17, 21, 25, 29, 33]),
                NormTable.Row(age: 70, [16, 20, 24, 27, 31]),
                NormTable.Row(age: 75, [14, 18, 21, 25, 28]),
                NormTable.Row(age: 80, [13, 16, 19, 23, 26]),
                NormTable.Row(age: 85, [11, 14, 17, 20, 23]),
                NormTable.Row(age: 90, [9, 11, 14, 17, 20]),
            ],
        ])

    /// METOD M59 · KALLOR K58. VO2 max i ml/kg/min: Loe m.fl. 2013 (PLoS ONE 8(5):e64319), tabell 2. 3 816 friska
    /// norrmän (HUNT 3), mätt syreupptagning på löpband till utmattning. Källan ger medel ± standardavvikelse per
    /// tioårsband och säger att måttet är normalfördelat; percentilerna räknas ur det (`normalRow`). Raderna står vid
    /// bandens mitt. Den äldsta gruppen är "+70 år" i en studie av 20–90-åringar: raden står vid 75 (**antagande**).
    static let vo2max: NormTable? = NormTable(
        marker: .vo2max, source: "Loe m.fl. 2013", percentiles: NormTable.normalPercentiles, trend: .declines,
        ages: 20...90,
        rows: [
            .male: [
                NormTable.normalRow(age: 25, mean: 54.4, sd: 8.4),
                NormTable.normalRow(age: 35, mean: 49.1, sd: 7.5),
                NormTable.normalRow(age: 45, mean: 47.2, sd: 7.7),
                NormTable.normalRow(age: 55, mean: 42.6, sd: 7.4),
                NormTable.normalRow(age: 65, mean: 39.2, sd: 6.7),
                NormTable.normalRow(age: 75, mean: 35.3, sd: 6.5),
            ],
            .female: [
                NormTable.normalRow(age: 25, mean: 43.0, sd: 7.7),
                NormTable.normalRow(age: 35, mean: 40.0, sd: 6.8),
                NormTable.normalRow(age: 45, mean: 38.4, sd: 6.9),
                NormTable.normalRow(age: 55, mean: 34.4, sd: 5.7),
                NormTable.normalRow(age: 65, mean: 31.1, sd: 5.1),
                NormTable.normalRow(age: 75, mean: 28.3, sd: 5.2),
            ],
        ])
}
