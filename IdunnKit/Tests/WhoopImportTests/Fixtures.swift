// PÅHITTADE testdata med exakt samma kolumner och format som en riktig
// Whoop-export (uppmätt 2026-10-11 utan att läsa ett enda värde, se
// tools/kolla_export.py). Siffrorna är uppfunna. Lägg ALDRIG in riktiga rader
// här — se CLAUDE.md §Dataregeln.
//
// Formen som fixturerna härmar:
// · senast först, en pågående cykel överst med tom sluttid och tomma mått
// · tider som väggklocka + zon i egen kolumn (`UTC+02:00`)
// · decimaltal med punkt, heltal utan decimaler, `true`/`false`
// · flera sömnpass per dygn (tupplur), flera dagbokssvar per dygn
// · en dagboksfråga med kommatecken (citerat fält)
// · ett zonbyte (sommartid → vintertid) mitt i serien. Varje tid på en rad
//   står i RADENS zon, även sluttiden: dygnet som börjar i +02 slutar 23:40
//   (+02), samma ögonblick som nästa dygn börjar 22:40 (+01). Uppmätt på den
//   riktiga exporten 2026-10-11: 275 av 275 dygn slutar där nästa börjar, och
//   vid det enda zonbytet stämmer bara radens egen zon.

enum Fixtures {
    static let cycles = """
    Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Skin temp (celsius),Blood oxygen %,Day Strain,Energy burned (cal),Max HR (bpm),Average HR (bpm),Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %
    2026-10-27 23:05:00,,UTC+01:00,,,,,,,,,,,,,,,,,,,,,,,
    2026-10-25 22:40:00,2026-10-27 23:05:00,UTC+01:00,71,52,63,33.9,96.4,8.2,2410,151,68,2026-10-25 22:40:00,2026-10-26 06:55:00,88,14.6,452,495,231,102,119,43,510,25,91,
    2026-10-24 23:10:00,2026-10-25 23:40:00,UTC+02:00,34,58,41,34.2,95.8,12.7,2890,172,74,2026-10-24 23:10:00,2026-10-25 06:20:00,71,15.1,381,430,210,71,100,49,505,60,88,76
    """

    static let sleeps = """
    Cycle start time,Cycle end time,Cycle timezone,Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %,Nap
    2026-10-25 22:40:00,2026-10-27 23:05:00,UTC+01:00,2026-10-26 14:10:00,2026-10-26 14:35:00,100,14.9,22,25,15,3,4,3,0,0,88,,true
    2026-10-25 22:40:00,2026-10-27 23:05:00,UTC+01:00,2026-10-25 22:40:00,2026-10-26 06:55:00,88,14.6,452,495,231,102,119,43,510,25,91,,false
    2026-10-24 23:10:00,2026-10-25 23:40:00,UTC+02:00,2026-10-24 23:10:00,2026-10-25 06:20:00,71,15.1,381,430,210,71,100,49,505,60,88,76,false
    """

    static let journal = """
    Cycle start time,Cycle end time,Cycle timezone,Question text,Answered yes,Notes
    2026-10-25 22:40:00,2026-10-27 23:05:00,UTC+01:00,Have any alcoholic drinks?,false,
    2026-10-25 22:40:00,2026-10-27 23:05:00,UTC+01:00,"Read (non-screened device, book) while in bed?",true,
    2026-10-24 23:10:00,2026-10-25 23:40:00,UTC+02:00,Have any alcoholic drinks?,true,
    """
}
