import AppIntents

// The buttons of the rest in the Dynamic Island: drawn by the widgets, run by the iPhone app (a Live Activity's
// intents run in the app), which changes its session and what it shows outside.

nonisolated enum RestAction: Sendable {
    case shorten
    case skip
    case lengthen
}

@MainActor
enum RestControl {
    // Set by the app when it starts; never in the widgets, which only draw the buttons.
    static var handler: (@MainActor (RestAction) async -> Void)?

    static func apply(_ action: RestAction) async {
        await handler?(action)
    }
}

nonisolated struct ShortenRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Remove 15 seconds"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestControl.apply(.shorten)
        return .result()
    }
}

nonisolated struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip the rest"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestControl.apply(.skip)
        return .result()
    }
}

nonisolated struct LengthenRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 15 seconds"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await RestControl.apply(.lengthen)
        return .result()
    }
}
