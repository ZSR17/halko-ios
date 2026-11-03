import ActivityKit
import SwiftUI
import WidgetKit

// The session in progress outside the app. During a rest: its countdown (an absolute end: the same as in the app and
// on the watch), what comes next, and in the Dynamic Island −15 s, Skip, +15 s. Else the set to do. The rest is shown
// until its end only (the content is stale from then), even if the app could not say so in time.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionActivityView(context: context)
                .widgetURL(SessionActivityAttributes.sessionURL)
        } dynamicIsland: { context in
            let state = SessionGlimpse(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(state: state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if state.rest != nil {
                        RestButtons()
                            .padding(.top, 8)
                    } else {
                        SessionLine(state: state)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                HalkoMark()
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                if let rest = state.rest {
                    Countdown(end: rest.end)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.rest))
                        .frame(maxWidth: 52)
                } else if let set = state.content.set {
                    Text(verbatim: set)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            } minimal: {
                if let rest = state.rest {
                    Countdown(end: rest.end)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(.rest))
                        .frame(maxWidth: 40)
                } else {
                    HalkoMark()
                        .frame(width: 16, height: 16)
                }
            }
            .keylineTint(Color.accentColor)
            .widgetURL(SessionActivityAttributes.sessionURL)
        }
        // The watch's Smart Stack, and CarPlay.
        .supplementalActivityFamilies([.small])
    }
}

// What a content shows, once its rest is known to be over or not.
struct SessionGlimpse {
    struct Rest {
        let end: Date
        let totalS: Int
    }

    let content: SessionActivityAttributes.ContentState
    let startedAt: Date
    let rest: Rest?

    init(context: ActivityViewContext<SessionActivityAttributes>) {
        content = context.state
        startedAt = context.attributes.startedAt
        rest = context.isStale ? nil : context.state.restEndsAt.map { Rest(end: $0, totalS: context.state.restTotalS) }
    }

    var allDone: Bool {
        content.exercise == nil
    }

    // "Set 3 · 80 kg × 8".
    var setText: String? {
        guard let set = content.set else { return nil }
        guard let values = content.values else { return set }
        return "\(set) · \(values)"
    }
}

// Lock screen, and the watch's Smart Stack.
private struct SessionActivityView: View {
    let context: ActivityViewContext<SessionActivityAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        let state = SessionGlimpse(context: context)
        switch family {
        case .small:
            SmallView(state: state)
                .padding(8)
        default:
            LockScreenView(state: state)
                .padding(16)
        }
    }
}

private struct LockScreenView: View {
    let state: SessionGlimpse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Headline(state: state, size: .largeTitle)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    if let exercise = state.content.exercise {
                        Text(verbatim: exercise)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                    if state.rest != nil, let next = state.setText {
                        Text("Next: \(next)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    SessionLine(state: state)
                }
            }
            if let rest = state.rest {
                RestProgress(rest: rest)
            }
        }
    }
}

// The rest's countdown, or the set to do, or the end: a small title above a big text.
private struct Headline: View {
    let state: SessionGlimpse
    let size: Font.TextStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let rest = state.rest {
                Text("Rest")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(.rest))
                Countdown(end: rest.end)
                    .font(.system(size, weight: .bold))
            } else if state.allDone {
                Text("All sets done")
                    .font(.headline)
            } else {
                if let set = state.content.set {
                    Text(verbatim: set)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.accentColor)
                }
                if let values = state.content.values {
                    Text(verbatim: values)
                        .font(.system(size == .largeTitle ? .title : .title3, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SmallView: View {
    let state: SessionGlimpse

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Headline(state: state, size: .title2)
            if let exercise = state.content.exercise {
                Text(verbatim: exercise)
                    .font(.caption)
                    .lineLimit(1)
            }
            if state.rest != nil, let next = state.setText {
                Text("Next: \(next)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExpandedLeading: View {
    let state: SessionGlimpse

    var body: some View {
        Headline(state: state, size: .title)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExpandedTrailing: View {
    let state: SessionGlimpse

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if state.rest != nil {
                Text("Next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let set = state.content.set {
                    Text(verbatim: set)
                        .font(.subheadline.weight(.semibold))
                }
                if let values = state.content.values {
                    Text(verbatim: values)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let exercise = state.content.exercise {
                Text(verbatim: exercise)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

// "Session 24:12 · ♥ 128".
private struct SessionLine: View {
    let state: SessionGlimpse

    var body: some View {
        HStack(spacing: 6) {
            Text("Session \(Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false))")
                .monospacedDigit()
            if let heartRate = state.content.heartRate {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text(verbatim: heartRate.formatted())
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Heart rate"))
                .accessibilityValue(Text("\(heartRate) beats per minute"))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

// Time left, never counting from a date already past.
private struct Countdown: View {
    let end: Date

    var body: some View {
        Text(timerInterval: min(Date.now, end)...end, countsDown: true)
            .monospacedDigit()
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
    }
}

private struct RestProgress: View {
    let rest: SessionGlimpse.Rest

    var body: some View {
        ProgressView(timerInterval: min(rest.end - Double(rest.totalS), rest.end)...rest.end, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .tint(Color(.rest))
        .accessibilityHidden(true)
    }
}

private struct RestButtons: View {
    var body: some View {
        HStack(spacing: 10) {
            Button(intent: ShortenRestIntent()) {
                Text(verbatim: "−15 s")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel(Text("Remove 15 seconds"))
            .buttonStyle(.bordered)
            .tint(.white)
            Button(intent: SkipRestIntent()) {
                Text("Skip")
                    .foregroundStyle(Color(.onRest))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(.rest))
            Button(intent: LengthenRestIntent()) {
                Text(verbatim: "+15 s")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel(Text("Add 15 seconds"))
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .font(.subheadline.weight(.semibold))
        .buttonBorderShape(.capsule)
    }
}

// The H of Halko's icon.
struct HalkoMark: View {
    var body: some View {
        HalkoMarkShape()
            .fill(Color.accentColor)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "Halko"))
    }
}

nonisolated private struct HalkoMarkShape: Shape {
    // The bars of the icon, in its box of 120 (drawn from 20 to 100).
    private static let bars: [(CGRect, CGFloat)] = [
        (CGRect(x: 27, y: 24, width: 22, height: 72), 9),
        (CGRect(x: 71, y: 24, width: 22, height: 72), 9),
        (CGRect(x: 45, y: 51, width: 30, height: 18), 0),
    ]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 80
        let origin = CGPoint(x: rect.midX - 40 * scale, y: rect.midY - 40 * scale)
        var path = Path()
        for (bar, radius) in Self.bars {
            let frame = CGRect(
                x: origin.x + (bar.minX - 20) * scale,
                y: origin.y + (bar.minY - 20) * scale,
                width: bar.width * scale,
                height: bar.height * scale
            )
            path.addRoundedRect(in: frame, cornerSize: CGSize(width: radius * scale, height: radius * scale))
        }
        return path
    }
}
