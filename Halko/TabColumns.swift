import SwiftUI

// A tab with room (the iPhone Duo open): two columns, its list on the left and the page chosen in it on the right.
// Without room, its own stack, which opens the pages over the list.
struct TabColumns<Choice: Hashable, Sidebar: View, Detail: View, Stack: View>: View {
    @ViewBuilder let sidebar: (Binding<Choice?>) -> Sidebar
    @ViewBuilder let detail: (Choice) -> Detail
    @ViewBuilder let stack: () -> Stack
    @Environment(\.horizontalSizeClass) private var sizeClass
    // Until something is chosen in the list: the page shown first.
    @State private var chosen: Choice?

    init(
        first: Choice? = nil,
        @ViewBuilder sidebar: @escaping (Binding<Choice?>) -> Sidebar,
        @ViewBuilder detail: @escaping (Choice) -> Detail,
        @ViewBuilder stack: @escaping () -> Stack
    ) {
        _chosen = State(initialValue: first)
        self.sidebar = sidebar
        self.detail = detail
        self.stack = stack
    }

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                sidebar($chosen)
                    .toolbarTitleDisplayMode(.inlineLarge)
            } detail: {
                NavigationStack {
                    if let chosen {
                        detail(chosen)
                    }
                }
                // Another page chosen: it opens alone, without the pages opened from the one before.
                .id(chosen)
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack {
                stack()
                    .toolbarTitleDisplayMode(.inlineLarge)
            }
        }
    }
}

// A line of a list in the left column, which shows its page in the right one: marked while it is shown, by a grey
// background, or by an outline around a card, which has its own background.
struct ChoiceRow<Choice: Hashable, Label: View>: View {
    let value: Choice
    @Binding var chosen: Choice?
    var card = false
    @ViewBuilder let label: Label

    var body: some View {
        let isChosen = chosen == value
        Button {
            chosen = value
        } label: {
            if card {
                label
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.tint, lineWidth: 2)
                            .opacity(isChosen ? 1 : 0)
                    }
                    .contentShape(.rect)
            } else {
                label
                    .padding(.horizontal, 10)
                    .background(isChosen ? Color(.secondarySystemFill) : .clear, in: .rect(cornerRadius: 12))
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}
