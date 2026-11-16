import Foundation
import Coach

/// BESLUT B127 · METOD M73
/// Appens enda väg ut på nätet. Den tar ett färdigt `CoachCall` ur IdunnKit och skickar det över TLS till värden
/// som kopplingen pekade ut; mer än så kan den inte. Den läser inga filer och känner inga nätter: det som kan stå i
/// ett anrop avgörs av `Coach`-dokumenten, som inte har något fält för slag, pulsprov, positioner eller ljud.
///
/// `tools/kolla_lyssna.py` håller det så: nätverkstyperna får bara stå i den här filen, filen får bara importera
/// Foundation och Coach, och ingången är `skicka(_ anrop: CoachCall)`.
enum CoachSändare {
    /// Ingen kaka, ingen cache och inget sparat mellan anropen.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 60
        return URLSession(configuration: c)
    }()

    static func skicka(_ anrop: CoachCall) async -> CoachReply {
        var delar = URLComponents()
        delar.scheme = "https"
        delar.host = anrop.host
        delar.path = anrop.path
        guard let adress = delar.url else { return .unreachable }
        var fråga = URLRequest(url: adress)
        fråga.httpMethod = "POST"
        fråga.httpBody = anrop.body
        for (namn, värde) in anrop.headers {
            fråga.setValue(värde, forHTTPHeaderField: namn)
        }
        do {
            let (data, svar): (Data, URLResponse) = try await session.data(for: fråga)
            guard let http = svar as? HTTPURLResponse else { return .unreachable }
            return CoachReply.parse(status: http.statusCode, body: data)
        } catch {
            return .unreachable
        }
    }
}
