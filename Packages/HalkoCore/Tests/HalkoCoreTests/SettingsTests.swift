import Foundation
import Testing
@testable import HalkoCore

struct SettingsTests {
    private func defaults() throws -> UserDefaults {
        let name = "SettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Takes the units chosen, each one apart, else those of the region")
    func units() throws {
        let defaults = try defaults()
        let britain = Locale(identifier: "en_GB")
        #expect(Units(defaults: defaults, locale: britain) == Units(weight: .kg, distance: .mi))
        #expect(Units(defaults: defaults, locale: Locale(identifier: "en_US")) == Units(weight: .lb, distance: .mi))
        defaults.set("lb", forKey: Units.weightKey)
        #expect(Units(defaults: defaults, locale: britain) == Units(weight: .lb, distance: .mi))
        defaults.set("km", forKey: Units.distanceKey)
        #expect(Units(defaults: defaults, locale: britain) == Units(weight: .lb, distance: .km))
    }

    @Test("Sets the language where the system reads it, and gives it back to the device")
    func language() throws {
        let defaults = try defaults()
        #expect(AppLanguage(defaults: defaults) == .system)
        AppLanguage.fr.save(to: defaults)
        #expect(AppLanguage(defaults: defaults) == .fr)
        #expect(defaults.stringArray(forKey: AppLanguage.systemKey) == ["fr"])
        AppLanguage.system.save(to: defaults)
        #expect(AppLanguage(defaults: defaults) == .system)
        #expect(defaults.object(forKey: AppLanguage.systemKey) == nil)
    }

    @Test("Copies the settings to the watch, those left out going back to their defaults")
    func shared() throws {
        let phone = try defaults()
        let watch = try defaults()
        watch.set(true, forKey: SetTimerSettings.stopsAtTargetKey)
        phone.set("lb", forKey: Units.weightKey)
        AppLanguage.en.save(to: phone)
        phone.set("ignored", forKey: "somethingElse")
        let values = SharedSettings.values(in: phone)
        #expect(Set(values.keys) == [Units.weightKey, AppLanguage.key])
        SharedSettings.save(values, to: watch)
        #expect(watch.string(forKey: Units.weightKey) == "lb")
        #expect(watch.stringArray(forKey: AppLanguage.systemKey) == ["en"])
        #expect(watch.object(forKey: SetTimerSettings.stopsAtTargetKey) == nil)
    }
}
