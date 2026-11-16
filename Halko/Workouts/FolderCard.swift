import HalkoCore
import SwiftData
import SwiftUI

// A folder of workouts: its name and how many workouts it holds. While the cards are reordered, `grip` across from its
// icon; a workout held over it: in the color of the app.
struct FolderCard<Grip: View>: View {
    let folder: Folder
    // A workout held over it, to be put in it.
    let isTarget: Bool
    let grip: Grip?
    @Query private var workouts: [Workout]

    init(folder: Folder, isTarget: Bool, @ViewBuilder grip: () -> Grip) {
        self.init(folder: folder, isTarget: isTarget, grip: grip())
    }

    fileprivate init(folder: Folder, isTarget: Bool, grip: Grip?) {
        self.folder = folder
        self.isTarget = isTarget
        self.grip = grip
        let id: String? = folder.id
        _workouts = Query(filter: #Predicate<Workout> { !$0.removed && $0.folderID == id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Spacer()
                if let grip {
                    // Its touch area over the margins of the card, not making the line taller.
                    grip
                        .padding(.vertical, -10)
                        .padding(.trailing, -8)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.headline)
                Text("\(workouts.count) workouts")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryText))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            if isTarget {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.tint.opacity(0.15))
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .animation(.snappy, value: isTarget)
        .accessibilityElement(children: .combine)
    }
}

extension FolderCard where Grip == EmptyView {
    init(folder: Folder) {
        self.init(folder: folder, isTarget: false, grip: nil)
    }
}
