import HalkoCore
import SwiftUI

extension EnvironmentValues {
    // The units weights and distances are shown and typed in.
    @Entry var units = Units(defaults: .standard, locale: .current)
}

// Gives the views below the units chosen in the settings, or those of the region, and follows their changes (on the
// watch, those received from the iPhone).
struct ChosenUnits: ViewModifier {
    @AppStorage(Units.weightKey) private var weight: WeightUnit?
    @AppStorage(Units.distanceKey) private var distance: DistanceUnit?
    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content
            .environment(\.units, Units(weight: weight ?? .preferred(for: locale), distance: distance ?? .preferred(for: locale)))
    }
}
