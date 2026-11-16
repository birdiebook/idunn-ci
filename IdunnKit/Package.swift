// swift-tools-version:5.9
//
// IdunnKit — appens logik, fri från UI och Bluetooth så att den går att testa
// på Linux (GitHub Actions) och utan telefon. Appen i App/ är ett tunt skal.
import PackageDescription

let package = Package(
    name: "IdunnKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WhoopImport", targets: ["WhoopImport"]),
        .library(name: "HeartRate", targets: ["HeartRate"]),
        .library(name: "Night", targets: ["Night"]),
        .library(name: "WhoopFrames", targets: ["WhoopFrames"]),
        .library(name: "Sound", targets: ["Sound"]),
        .library(name: "Pass", targets: ["Pass"]),
        .library(name: "SleepNeed", targets: ["SleepNeed"]),
        .library(name: "Fitness", targets: ["Fitness"]),
        .library(name: "Markers", targets: ["Markers"]),
        .library(name: "Band", targets: ["Band"]),
        .library(name: "Coach", targets: ["Coach"]),
        .library(name: "Journal", targets: ["Journal"]),
        .library(name: "DemoData", targets: ["DemoData"]),
    ],
    targets: [
        // Läser Whoops CSV-export (Data Export i Whoop-appen).
        .target(name: "WhoopImport"),
        .testTarget(name: "WhoopImportTests", dependencies: ["WhoopImport"]),
        // Nattinspelningen (PLAN.md I2): tolkningen av pulsnotisen 2A37, nattens
        // notiser som värdetyper, och kontrollerna av glapp och RR-intervall.
        // Bluetooth-skalet ligger i appen.
        .target(name: "HeartRate"),
        .testTarget(name: "HeartRateTests", dependencies: ["HeartRate", "DemoData"]),
        // Natten i siffror (PLAN.md I3) och återhämtningens räkning (I4): rensade
        // RR, RMSSD och vilopuls per 5-minutersfönster, andningen, baslinjen och
        // jämförelsen mot Whoops dygn, och sömnperioden ur K18:s rörelse (R4,
        // METOD M26; därför beroendet på WhoopFrames). Visningen ligger i appen.
        .target(name: "Night", dependencies: ["HeartRate", "WhoopImport", "WhoopFrames"]),
        .testTarget(name: "NightTests", dependencies: ["Night", "HeartRate", "WhoopImport", "WhoopFrames", "DemoData"]),
        // T2 (PLAN.md §2): Whoops egna ramar som Idunn hör passivt, och räkningen
        // per karakteristik och pakettyp, ramarnas ihopfogning och nattens export
        // (BESLUT B22). Idunn skriver aldrig till bandet (BESLUT B14).
        .target(name: "WhoopFrames", dependencies: ["HeartRate"]),
        .testTarget(name: "WhoopFramesTests", dependencies: ["WhoopFrames", "HeartRate"]),
        // PÅHITTADE nätter och Whoop-historik (BESLUT B20): förhandsvisningens
        // data (målet IdunnProv i project.yml) och testernas slumpgenerator.
        // Appen länkar aldrig in den.
        .target(name: "DemoData", dependencies: ["HeartRate", "WhoopImport", "WhoopFrames", "Night", "Sound"]),
        .testTarget(name: "DemoDataTests", dependencies: ["DemoData", "Night", "HeartRate", "WhoopImport", "WhoopFrames"]),
        // Ljudet under natten (PLAN.md spåret J, BESLUT B47, METOD M38–M40): måtten per
        // sekund ur 16 000 prov, klasserna, `.ljud`-filen, händelserna och klippen,
        // vems snarkningen är (fasen mot K18:s andning), klockskillnaden och vad som
        // följde ljuden. Bara Foundation, så att det går på Linux. Mikrofonen och
        // SoundAnalysis ligger i appen (App/SoundListener.swift).
        .target(name: "Sound", dependencies: ["Night", "WhoopFrames", "HeartRate"]),
        .testTarget(name: "SoundTests", dependencies: ["Sound", "DemoData", "Night", "WhoopFrames", "HeartRate"]),
        // Pass med puls (PLAN.md spåret P, BESLUT B58, METOD M47): passet som värdetyp,
        // lägsta/snitt/högsta, pulsens återhämtning efter stopp, tillståndsmaskinen
        // (start, stopp, 10 minuter efter) och filen. Bara Foundation. Pulsen från bandet
        // och skärmen ligger i appen (App/PassController.swift, App/PassView.swift).
        .target(name: "Pass", dependencies: ["HeartRate"]),
        .testTarget(name: "PassTests", dependencies: ["Pass", "HeartRate"]),
        // Sömnbehovet (PLAN.md H1, BESLUT B64, METOD M53): grundbehovet ur en
        // förlängningsvecka, passets belastning, skulden natt för natt och kvällens
        // läggdags. Tar nätter och pass som värden; vyerna ligger i appen.
        // Idunns nätter in (BESLUT B65) och Whoops grundbehov ur exporten (B67): därför Night och WhoopImport.
        .target(name: "SleepNeed", dependencies: ["Pass", "Night", "WhoopImport"]),
        .testTarget(name: "SleepNeedTests", dependencies: ["SleepNeed", "Pass", "Night", "WhoopImport"]),
        // VO2 max (PLAN.md spåret O, BESLUT B106, METOD M60–M64): profilen, maxpulsen, den passiva
        // skattningen ur nattens vilopuls (Nes formel) och filen med profilen och de avskrivna
        // Whoop-talen. Bara Foundation; tar vilopulsen som värden, så inget beroende på Night.
        // Steptestet (M62), puls mot fart (M63) och talet som visas (M64) läser passet: därför Pass.
        .target(name: "Fitness", dependencies: ["Pass"]),
        .testTarget(name: "FitnessTests", dependencies: ["Fitness", "Pass", "HeartRate"]),
        // Markörerna mot jämnåriga (PLAN.md spåret Å, BESLUT B104, METOD M59): personen (födelseår, kön),
        // markörerna, loggen över det som skrivs in för hand (VO2 max, greppstyrka, egna), normtabellen med
        // percentil och motsvarande ålder, kvartalets nivå och profilens kort. Bara Foundation och inga andra mål:
        // nätternas och passens värden kommer in som dag och tal. Vyn och filen ligger i appen (Å2).
        .target(name: "Markers"),
        .testTarget(name: "MarkersTests", dependencies: ["Markers"]),
        // Bandets batteri (BESLUT B123, METOD M70): när det är lågt (rött under 20 %) och när telefonen påminner om att
        // ladda (vid 20, 10 och 5 %, en gång per gräns och urladdning). Bara Foundation och inga andra mål.
        .target(name: "Band"),
        .testTarget(name: "BandTests", dependencies: ["Band"]),
        // Coachen (PLAN.md spåret C, BESLUT B127, METOD M73): det Idunn skickar av sig själv till användaren egen databas,
        // så att Claude kan läsa det. Bara sammanfattningar: en natt, ett pass, en inskriven mätning och profilen som
        // dokument utan fält för slag, pulsprov, positioner eller ljud; kopplingen, anropet, svaret och loggen över det
        // skickade. Bara Foundation och inget nätverk: sändaren ligger i appen (App/CoachSandare.swift).
        .target(name: "Coach", dependencies: ["Night", "Pass", "SleepNeed", "Markers", "Fitness"]),
        .testTarget(name: "CoachTests", dependencies: ["Coach", "Night", "Pass", "SleepNeed", "Markers", "Fitness"]),
        // Dagboken (PLAN.md spåret U, BESLUT B130, METOD M75): kvällens taggar och morgonens skattning, filen
        // `dagbok.json`, och när appen frågar. Bara Foundation och inga andra mål; vyerna ligger i appen.
        .target(name: "Journal"),
        .testTarget(name: "JournalTests", dependencies: ["Journal"]),
    ]
)
