import Foundation

/// METOD M28 · METOD M29 · BESLUT B48
/// Vilken natt som gäller en uppvakningsdag när både en natt ur K18 och en
/// gammal inspelning (2A37) finns för den. Förut gick K18 alltid före
/// (`Trends.idunPerDay`). Nu går K18 före bara när den hördes tillräckligt:
/// täckningen över sömnperioden når `ListenerCheck.minCoverage`. En natt som
/// bandet bara hörde till en tredjedel är ett sämre underlag än inspelningen
/// som låg på hela natten, och Morgon ska inte byta det mot det.
///
/// Appen tar bort de nätter som `outvoted` ger (`Recorder.chosen`; `eligible`
/// är samma sak för kandidaterna) och låter `Trends.idunPerDay` göra resten
/// (nätter under minsta antal fönster utsorterade, K18 före inspelning, flest
/// fönster av samma källa). Samma funktioner prövas av vakten i
/// `NattvalVaktTests`, så provet kör det telefonen kör.
public enum NightChoice {

    /// En natt som kan väljas: appens id (sammanfattningens stam), dagen,
    /// källan, hur stor del av sömnperioden K18 täckte (`NightDigest.coverage`;
    /// `nil` för en inspelning och när den inte räknats) och antalet giltiga
    /// fönster (`Trends.minValidWindows` avgör om natten räknas alls).
    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var day: WakeDay
        public var source: NightSource
        public var coverage: Double?
        public var validWindows: Int

        public init(id: String, day: WakeDay, source: NightSource, coverage: Double?, validWindows: Int) {
            self.id = id
            self.day = day
            self.source = source
            self.coverage = coverage
            self.validWindows = validWindows
        }
    }

    /// Hördes K18-natten tillräckligt för att gå före en inspelning? Utan en
    /// täckning (`nil`) räknas den som obevisad.
    public static func k18Qualifies(coverage: Double?) -> Bool {
        (coverage ?? 0) >= ListenerCheck.minCoverage
    }

    /// Nätterna ur K18 som viker sig för en inspelning samma dag: täckningen
    /// når inte `ListenerCheck.minCoverage`, och inspelningen räknas själv
    /// som en natt (minst `Trends.minValidWindows` giltiga fönster). Finns ingen
    /// sådan inspelning blir K18-natten kvar hur lite den hördes, för då finns
    /// inget bättre att visa. Ger id:n.
    public static func outvoted(_ nights: [Candidate]) -> Set<String> {
        var inspelningar: Set<WakeDay> = []
        for n in nights where n.source != .k18 && n.validWindows >= Trends.minValidWindows {
            inspelningar.insert(n.day)
        }
        var ut: Set<String> = []
        for n in nights where n.source == .k18 && !k18Qualifies(coverage: n.coverage) && inspelningar.contains(n.day) {
            ut.insert(n.id)
        }
        return ut
    }

    /// Nätterna som är kvar när de som viker sig tagits bort, i ordningen de kom.
    public static func eligible(_ nights: [Candidate]) -> [Candidate] {
        let viker: Set<String> = outvoted(nights)
        return nights.filter { (n: Candidate) -> Bool in !viker.contains(n.id) }
    }

    /// METOD M32 · BESLUT B52. En natt ur K18 ska ha lager på kurvans tidsaxel (rörelse,
    /// temperatur, glapp med orsak); en gammal inspelning har inga och ritas
    /// som förut. Sant när natten *borde* ha lager men inte har: en K18-natt
    /// vars kurva inte gick att räkna om ur filerna (`layers` är då `nil`, också när hela
    /// resultatet saknas). Morgon säger det som en felrad (`ListenerAlert.missingLayers`).
    public static func lacksLayers(source: NightSource, layers: NightLayers.Layers?) -> Bool {
        source == .k18 && layers == nil
    }
}
