import Foundation

/// BESLUT B64 · METOD M53
/// Konstanterna för sömnbehovet (PLAN.md H1). Varje värde har sin rad i METOD M53
/// med källa och status; källorna står i docs/KALLOR.md (K39–K47).
public enum SleepNeedRules {
    // MARK: Grundbehovet

    /// METOD M53 · BESLUT B67. Priorns medel för grundbehovet i minuter sovtid: 8 h (användaren 2026-11-08). Van Dongens
    /// 8,16 h (K39) ligger inom en SD.
    public static let priorBaseMinutes: Double = 480
    /// METOD M53 · BESLUT B65. Priorns SD. Antagande, grundat i spridningen 7,29–9,26 h hos Kitamura (K40).
    public static let priorBaseSDMinutes: Double = 30
    /// METOD M53 · BESLUT B67. Mätfelet för Whoops grundbehov som observation. Antagande: Whoop har lärt sig
    /// användaren över många nätter, men metoden är inte publicerad.
    public static let whoopObservationSDMinutes: Double = 15
    /// METOD M53 · BESLUT B67. Så många par (strain, behov − skuld) krävs för Whoops grundbehov. Antagande.
    public static let whoopMinNights = 7

    // MARK: Skulden

    /// METOD M53 · BESLUT B68. Skuldens tidskonstant i nätter: skulden klingar av med
    /// e^(−1/τ) per natt. 1,5 nätter (användaren 2026-11-08): Whoops skuld och nästa morgons
    /// HRV och vilopuls i hans export pekar dit; vår uträkning ur McCauley gav 5 (K44).
    public static let debtTimeConstantNights: Double = 1.5
    /// METOD M53. Högst så mycket av skulden läggs på kvällens behov: den extra
    /// sömn som faktiskt går att få (+52 min med 10 h i säng hos Banks m.fl. 2010, K41).
    public static let debtInTonightCapMinutes: Double = 60

    // MARK: Passet

    /// METOD M53. Zonernas undre gränser som andel av maxpulsen (Edwards zoner, som i
    /// Leota m.fl. 2025, K46): under 50 % är zon 0, 50–60 % zon 1 … 90 % och över zon 5.
    public static let zoneLowerBounds: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]
    /// METOD M53. Två prov längre isär än så räknas inte som tid i en zon (samma
    /// gräns som M47:s ±5 s): ett glapp gissas inte.
    public static let sampleGapSeconds: TimeInterval = 5
    /// METOD M53. Minuter sömn per belastningsenhet: vår anpassning genom origo till
    /// Leotas tabell 2 (pass som slutar 8 och 10 h före vanlig insomning), 0,0098
    /// respektive 0,0132, avrundat till 0,01.
    public static let minutesPerLoad: Double = 0.01
    /// METOD M53. Taket för tillägget: ingen klass hos Leota gav mer än cirka 8,5 min.
    public static let passCapMinutes: Double = 10
    /// METOD M53. Tillägget räknas bara när passet slutar minst så här många timmar före
    /// den vanliga insomningen. Hos Leota var effekten noll vid 6 h och negativ närmare.
    public static let passMinHoursBeforeOnset: Double = 8
    /// METOD M53. Styrkepass: minst så här många enheter per minut, eftersom pulsen
    /// underskattar styrka (Leota, K46). Antagande: som en minut i zon 2.
    public static let strengthLoadPerMinute: Double = 2
    /// METOD M53. Maxpulsen ur passen: medianen av så här många prov i följd, så att
    /// en enstaka spik inte blir maxpuls. Antagande.
    public static let maxPulseMedianSamples = 5

    // MARK: Läggdags

    /// METOD M53. Väcktiden, effektiviteten och den vanliga insomningen är medianer
    /// över så här många av de senaste nätterna. Antagande.
    public static let windowNights = 14
    /// METOD M53. Tiden från läggdags till insomning: Idunn ser inte tiden i säng
    /// före insomningen. Antagande.
    public static let sleepLatencyMinutes: Double = 15

    // MARK: Läggdags för bästa sömnpoäng

    /// METOD M53 · BESLUT B75. Läggdags prövas i steg om så här många minuter, räknat från läggdags för full sömn åt
    /// båda hållen. Antagande: finare än så går inte att följa.
    public static let bestBedtimeStepMinutes: Double = 5
    /// METOD M53 · BESLUT B75. Fönstret som prövas: från så här många timmar före väcktiden … Antagande.
    public static let bestBedtimeEarliestHoursBeforeWake: Double = 12
    /// METOD M53 · BESLUT B75. … till så här många. Antagande.
    public static let bestBedtimeLatestHoursBeforeWake: Double = 4
    /// METOD M53 · BESLUT B75. Två förväntade poäng närmare än så är lika, och läggdags närmast full sömn gäller.
    public static let bestBedtimeTieScore: Double = 1e-9
    /// METOD M53 · BESLUT B84. Trögheten: läggdags för bästa poäng gäller bara när den ger minst så här många poäng mer
    /// än läggdags för full sömn; annars full sömn. Antagande (användaren 2026-11-09): en bråkdel av en poäng är inte
    /// värd att flytta läggdags flera timmar för.
    public static let bestBedtimeMinGainScore: Double = 1

    // MARK: Påminnelsen före läggdags

    /// METOD M53 · BESLUT B103. Påminnelsen kommer så här många minuter före läggdags. Beslut (användaren 2026-11-14).
    public static let bedtimeReminderLeadMinutes: Double = 15
    /// METOD M53 · BESLUT B103. Så här många nätter efter den närmaste får en påminnelse i reserv, räknad på det appen
    /// vet nu, ifall appen inte hinner räkna en ny natt före kvällen. Antagande.
    public static let bedtimeReminderNights = 3
}
