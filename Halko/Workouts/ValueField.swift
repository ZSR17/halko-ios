import HalkoCore
import SwiftUI

// A box of the workout editor that has the keyboard.
enum EditorField: Hashable {
    case name
    case note(ItemDraft.ID)
    case setCount(ItemDraft.ID)
    case sidesPause(ItemDraft.ID)
    // `set` nil: the value of every set, in simple mode.
    case value(ItemDraft.ID, set: Int?, SetField)
}

// A value of the planned sets, typed in a box: what is typed is kept as soon as it reads as a value, and shown again
// in its usual form once the box loses the keyboard. Emptied, a value that can be worked out goes back to that.
struct ValueField: View {
    let label: Text
    let value: Double?
    let format: (Double?) -> String
    let parse: (String) -> Double?
    let keyboard: UIKeyboardType
    // Worked out from the working sets: in gray italics until typed in.
    let workedOut: Bool
    let canWorkOut: Bool
    let focus: FocusState<EditorField?>.Binding
    let field: EditorField
    // When the box gets the keyboard, before anything is typed.
    let begin: () -> Void
    let commit: (Double?) -> Void
    @State private var text: String
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 44

    init(
        _ label: Text,
        value: Double?,
        format: @escaping (Double?) -> String,
        parse: @escaping (String) -> Double?,
        keyboard: UIKeyboardType = .numberPad,
        workedOut: Bool = false,
        canWorkOut: Bool = false,
        focus: FocusState<EditorField?>.Binding,
        field: EditorField,
        begin: @escaping () -> Void = {},
        commit: @escaping (Double?) -> Void
    ) {
        self.label = label
        self.value = value
        self.format = format
        self.parse = parse
        self.keyboard = keyboard
        self.workedOut = workedOut
        self.canWorkOut = canWorkOut
        self.focus = focus
        self.field = field
        self.begin = begin
        self.commit = commit
        _text = State(initialValue: format(value))
    }

    private var isFocused: Bool {
        focus.wrappedValue == field
    }

    var body: some View {
        let dimmed = workedOut && !isFocused
        // Without a value, a dash rather than the label.
        TextField(text: $text, prompt: Text(verbatim: "–").foregroundStyle(Color(.secondaryText))) {
            label
        }
        .focused(focus, equals: field)
        .keyboardType(keyboard)
        .multilineTextAlignment(.center)
        .font(dimmed ? .body.italic() : .body.weight(.semibold))
        .foregroundStyle(dimmed ? Color(.secondaryText) : .primary)
        .monospacedDigit()
        .padding(.horizontal, 4)
        .frame(minHeight: max(44, height))
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 10))
        .accessibilityHint(workedOut ? Text("Worked out from the first working set. Type a value to set it.") : Text(verbatim: ""))
        .onChange(of: isFocused) { _, focused in
            if focused {
                begin()
            } else {
                text = format(value)
            }
        }
        .onChange(of: value) { _, value in
            if !isFocused {
                text = format(value)
            }
        }
        .onChange(of: text) { _, text in
            guard isFocused else { return }
            if let typed = parse(text) {
                commit(typed)
            } else if canWorkOut && text.trimmingCharacters(in: .whitespaces).isEmpty {
                commit(nil)
            }
        }
    }
}

// A set of the table, swiped left to show its Delete button: its boxes keep their size and move aside, only the
// button widens as it is pulled. Pulled far, it deletes the set at once.
struct SwipeToDelete<Content: View>: View {
    let enabled: Bool
    @Binding var isOpen: Bool
    let delete: () -> Void
    @ViewBuilder let content: Content
    @State private var pull: CGFloat = 0

    private static var openWidth: CGFloat {
        92
    }

    private static var deleteWidth: CGFloat {
        200
    }

    private var width: CGFloat {
        max(0, (isOpen ? Self.openWidth : 0) - pull)
    }

    var body: some View {
        content
            .offset(x: -width)
            .overlay(alignment: .trailing) {
                Button("Delete", role: .destructive) {
                    delete()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: max(0, width - 6))
                .frame(maxHeight: .infinity)
                .background(Color(.deleteFill), in: .rect(cornerRadius: 10))
                .opacity(width > 0 ? 1 : 0)
                .accessibilityHidden(width == 0)
            }
            .clipped()
            .gesture(SidewaysPan(enabled: enabled) { translation in
                pull = translation
            } ended: {
                let pulled = width
                withAnimation(.snappy) {
                    pull = 0
                    if pulled > Self.deleteWidth {
                        isOpen = false
                        delete()
                    } else {
                        isOpen = pulled > Self.openWidth / 2
                    }
                }
            })
    }
}

// A pan that starts only when the finger first moves sideways. One that starts up or down fails at once, so the scroll
// view gets it untouched, rather than a SwiftUI drag holding the touch until the boxes and buttons under it take it.
private struct SidewaysPan: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var enabled = true

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard enabled, let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        context.coordinator.enabled = enabled
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.enabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed:
            changed(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed:
            ended()
        default:
            break
        }
    }
}
