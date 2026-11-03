import AppIntents

// The buttons of the session outside the app (lock screen, Dynamic Island): drawn by the widgets, run by the iPhone
// app (a Live Activity's intents run in the app), which changes its session and what it shows outside.

nonisolated enum SessionAction: Sendable {
    case shortenRest
    case skipRest
    case lengthenRest
    // The set to do, with the values shown.
    case validateSet
}

@MainActor
enum SessionControl {
    // Set by the app when it starts; never in the widgets, which only draw the buttons.
    static var handler: (@MainActor (SessionAction) async -> Void)?

    static func apply(_ action: SessionAction) async {
        await handler?(action)
    }
}

nonisolated struct ShortenRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Remove 15 seconds"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await SessionControl.apply(.shortenRest)
        return .result()
    }
}

nonisolated struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip the rest"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await SessionControl.apply(.skipRest)
        return .result()
    }
}

nonisolated struct LengthenRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 15 seconds"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await SessionControl.apply(.lengthenRest)
        return .result()
    }
}

nonisolated struct ValidateSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Validate the set"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await SessionControl.apply(.validateSet)
        return .result()
    }
}
