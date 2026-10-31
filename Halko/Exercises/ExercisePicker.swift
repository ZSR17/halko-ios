import HalkoCore
import SwiftUI

// The exercises to add to a workout, chosen in the list of the Exercises tab: as many as wanted, added in the order
// they were chosen.
struct ExercisePicker: View {
    let add: ([Exercise]) -> Void
    @State private var chosen: [Exercise] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseBrowser { entry in
                let isChosen = chosen.contains { $0.id == entry.id }
                Button {
                    if isChosen {
                        chosen.removeAll { $0.id == entry.id }
                    } else {
                        chosen.append(entry.exercise)
                    }
                } label: {
                    ExerciseListRow(entry: entry, chosen: isChosen)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
            // ✕ and Add stay while searching.
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle("Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                    .accessibilityLabel(Text("Cancel"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        add(chosen)
                        dismiss()
                    } label: {
                        Text("Add \(chosen.count)")
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
    }
}
