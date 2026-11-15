import CoreBluetooth
import Foundation
import WhoopFrames

/// BESLUT B25 · BESLUT B53 · BESLUT B61 · METOD M23 · METOD M43 · METOD M48
/// Det enda stället i Idunn som skriver till bandet. Det tar bara emot en
/// `WhoopCommand` — IdunnKits byggare, som bara kan bygga 145 (hälsningen),
/// 22 (begär historiken) och 23 (kvittensen), IMU-provets 81, 82 och 106, och
/// passets realtidspuls 3 — och skriver dess ram med svar
/// (`.withResponse`) till skrivkarakteristiken. Inga egna byte.
///
/// `tools/kolla_lyssna.py` (Actions) fäller varje skrivning utanför den här
/// filen och varje annan form av anropet nedan.
enum BandSender {
    static let commandCharacteristic = CBUUID(string: WhoopCommand.characteristic)

    /// `false` om karakteristiken inte är skrivkarakteristiken, inte tar
    /// skrivning med svar, eller om bandet inte är anslutet. Då skrivs inget.
    static func send(_ command: WhoopCommand, to band: CBPeripheral, on ch: CBCharacteristic) -> Bool {
        guard ch.uuid == commandCharacteristic, ch.properties.contains(.write), band.state == .connected else {
            return false
        }
        band.writeValue(Data(command.frame), for: ch, type: .withResponse)
        return true
    }
}
