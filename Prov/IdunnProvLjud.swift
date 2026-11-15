// PROVET FÖR LJUDET UNDER NATTEN (PLAN.md J2, BESLUT B47). Körs i simulatorn av
// `ios-prov` (python tools/prov.py), där mikrofonen saknas: lyssnaren matas i stället
// med en påhittad ljudfil som provet själv skriver (seedat brus, en hög stund i
// mitten), och allt efter mikrofonen går samma väg som på telefonen — konvertering
// till 16 kHz, måtten per sekund, SoundAnalysis, `.ljud`-filen, händelserna och
// AAC-klippen. Inget ljud är riktigt; det finns inga bilder här.
//
// Det andra provet jämför varje identifierare i klasstabellen (METOD M38) med de
// klasser SoundAnalysis faktiskt har, och skriver ut dem båda så att tabellen
// kan rättas på en gång (PROV-rader i loggen).

import XCTest
import AVFoundation
import SoundAnalysis
import DemoData
import Sound
@testable import Idunn

final class IdunnProvLjud: XCTestCase {

    /// 56 sekunder, 48 kHz mono 16-bit: 40 s tyst brus, 4 s högt, 12 s tyst.
    func writeWav(to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        var random = Seeded(7)
        let n = 48_000
        for sekund in 0..<56 {
            let amplitud: Double = (sekund >= 40 && sekund < 44) ? 0.3 : 0.002
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                        frameCapacity: AVAudioFrameCount(n)))
            let kanal = try XCTUnwrap(buffer.floatChannelData)
            for i in 0..<n { kanal[0][i] = Float(max(-1, min(1, amplitud * random.gauss()))) }
            buffer.frameLength = AVAudioFrameCount(n)
            try file.write(from: buffer)
        }
    }

    func testLyssnarenSkriverFilenOchKlippenUrEnLjudfil() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("idun-ljudprov-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let wav = tmp.appendingPathComponent("natt.wav")
        try writeWav(to: wav)

        let suiteName = "se.birdiebook.idun.ljudprov"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        defer { suite.removePersistentDomain(forName: suiteName) }
        let listener = SoundListener(root: tmp.appendingPathComponent("app", isDirectory: true), defaults: suite)
        let start = 1_791_662_400
        let t0 = Date()
        let r = try listener.process(file: wav, start: Date(timeIntervalSince1970: Double(start)))
        print("PROV: ljud körd på \(Int(Date().timeIntervalSince(t0))) s: \(r.seconds) sekunder, "
              + "\(r.events) händelser, \(r.clips) klipp, klassning \(r.classified ? "ja" : "NEJ")")

        // `.ljud`-filen finns, har rätt huvud och 54–56 sekunder (tolkningen av filens
        // sista halvsekund och omräkningen till 16 kHz kan kosta en sekund).
        XCTAssertTrue(FileManager.default.fileExists(atPath: r.measureFile.path), ".ljud-filen skrevs")
        let innehåll = try SoundFile.decode(try Data(contentsOf: r.measureFile))
        XCTAssertEqual(innehåll.start, start)
        XCTAssertEqual(innehåll.truncatedBytes, 0)
        XCTAssertGreaterThanOrEqual(innehåll.seconds.count, 54)
        XCTAssertLessThanOrEqual(innehåll.seconds.count, 56)
        XCTAssertEqual(innehåll.seconds.count, r.seconds)
        for (a, b) in zip(innehåll.seconds, innehåll.seconds.dropFirst()) {
            XCTAssertEqual(b.second - a.second, 1, "inga hål i en obruten ström")
        }
        let tyst = innehåll.seconds[10]
        let högt = innehåll.seconds[41]
        // Vitt brus i 48 kHz: omräkningen till 16 kHz behåller bara bandet upp till
        // 8 kHz, en tredjedel av effekten (−4,8 dB), och filtret tar lite till nära
        // 8 kHz. Första körningen (6acf32b3…) gav −59,8 och −16,3.
        XCTAssertEqual(tyst.levelDB, -58.8, accuracy: 2, "0,002 i brus är −54 dBFS i 48 kHz, −58,8 i 16 kHz")
        XCTAssertEqual(högt.levelDB, -15.2, accuracy: 2, "0,3 i brus är −10,5 dBFS i 48 kHz, −15,2 i 16 kHz")
        XCTAssertEqual(tyst.classes.count, 12)

        // Den höga stunden är en händelse i måtten, och ett klipp skrevs.
        let händelser = SoundEvents.detect(innehåll.seconds)
        XCTAssertGreaterThanOrEqual(händelser.count, 1, "händelser: \(händelser)")
        XCTAssertGreaterThanOrEqual(r.clips, 1, "minst ett klipp")
        let klipp = try FileManager.default.contentsOfDirectory(atPath: r.clipFolder.path).filter {
            $0.hasSuffix(".m4a")
        }
        XCTAssertFalse(klipp.isEmpty)
        if let första = klipp.sorted().first {
            let url = r.clipFolder.appendingPathComponent(första)
            let fil = try AVAudioFile(forReading: url)
            XCTAssertEqual(fil.processingFormat.sampleRate, 16_000, accuracy: 1)
            XCTAssertGreaterThan(fil.length, 16_000 * 5, "ett klipp på minst fem sekunder")
            XCTAssertLessThanOrEqual(fil.length, 16_000 * 30 + 1_000)
            let bytes = ProvFil.of(url)
            print("PROV: ljud klipp \(första): \(fil.length) prov, \(bytes) byte")
            let sekunder = Double(fil.length) / 16_000
            // METOD M38. Simulatorns kodare följer inte takten: 6,8 kB/s för brus i
            // två körningar (6acf32b3…, 6acf66e7…), med och utan fast takt. Gränsen är
            // det uppmätta med marginal; takten mäts igen på telefonen.
            XCTAssertLessThan(Double(bytes), 8_000 * sekunder + 2_000,
                              "klippen tar högst cirka 8 kB/s")
        }

        // Mapparna är undantagna från iCloud-kopian.
        XCTAssertTrue(ProvFil.excluded(listener.measureFolder), "ljud/ följer inte med säkerhetskopian")
        XCTAssertTrue(ProvFil.excluded(listener.clipRoot), "ljudklipp/ följer inte med säkerhetskopian")
        print("PROV: ljud ok")
    }

    func testKlasstabellensIdentifierareFinnsIKnownClassifications() throws {
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let kända = Set(request.knownClassifications)
        let saknas: [String] = SoundClasses.allIdentifiers.filter { (id: String) -> Bool in !kända.contains(id) }
        let utanför: [String] = kända.subtracting(SoundClasses.allIdentifiers).sorted()
        print("PROV: ljud kända klasser (\(kända.count)): " + kända.sorted().joined(separator: ","))
        print("PROV: ljud saknas i klassificeraren (\(saknas.count)): " + saknas.joined(separator: ","))
        print("PROV: ljud utanför tabellen, räknas som övrigt (\(utanför.count)): " + utanför.joined(separator: ","))
        XCTAssertGreaterThan(kända.count, 250, "klassificeraren har 303 klasser")
        XCTAssertEqual(saknas, [], "identifierare i SoundClasses som SoundAnalysis inte känner: \(saknas)")
    }
}

/// Små hjälpare för provet: filstorlek och om en mapp är undantagen från säkerhetskopian.
enum ProvFil {
    static func of(_ url: URL) -> Int {
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attr?[.size] as? NSNumber)?.intValue ?? 0
    }

    static func excluded(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        return v?.isExcludedFromBackup ?? false
    }
}
