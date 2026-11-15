import Foundation

/// BESLUT B123 · METOD M70
/// Bandets batteri: när det är lågt (rött under 20 %) och när telefonen påminner om att ladda (vid 20, 10 och 5 %,
/// en gång per gräns och urladdning). Bara Foundation; nivån kommer in som ett heltal och notisen läggs av appen
/// (App/Batteripaminnelse.swift).
public enum BandBattery {
    /// Under den här nivån är batteriet lågt: `level < lowLimit`.
    public static let lowLimit: Int = 20
    /// Gränserna som ger en påminnelse, högst först.
    public static let reminderLimits: [Int] = [20, 10, 5]

    /// Batteriet är lågt (rött).
    public static func isLow(_ level: Int) -> Bool {
        level < lowLimit
    }

    /// Utfallet av en ny läsning: det nya tillståndet och gränsen som ger en påminnelse nu (`nil` om ingen).
    public struct Step: Equatable, Sendable {
        /// Lägsta gräns som redan gett en påminnelse i den här urladdningen; `nil` om ingen. Gränser på och över
        /// den räknas som avklarade.
        public var state: Int?
        public var reminder: Int?

        public init(state: Int?, reminder: Int?) {
            self.state = state
            self.reminder = reminder
        }
    }

    /// Räknar en ny läsning mot förra tillståndet.
    /// - En påminnelse när nivån ligger under en gräns som ännu inte påmint; under flera på en gång ges en, för den
    ///   lägsta (25 → 8 ger 10, och 20 är då avklarad).
    /// - När nivån är på eller över en gräns (bandet har laddats) blir den och alla lägre gränser beväpnade igen.
    /// - Nivåer utanför 0...100 ignoreras: tillståndet oförändrat, ingen påminnelse.
    public static func step(state: Int?, level: Int) -> Step {
        guard (0...100).contains(level) else { return Step(state: state, reminder: nil) }
        // Avklarade gränser är de på och över `state`; de som nivån nått upp till igen släpps.
        let avklarade: [Int] = reminderLimits.filter { (g: Int) -> Bool in
            guard let s = state else { return false }
            return g >= s && g > level
        }
        // Gränser nivån ligger under och som inte påmint än.
        let kandidater: [Int] = reminderLimits.filter { (g: Int) -> Bool in
            level < g && !avklarade.contains(g)
        }
        if let g = kandidater.min() {
            return Step(state: g, reminder: g)
        }
        return Step(state: avklarade.min(), reminder: nil)
    }
}
