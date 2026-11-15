import HalkoCore
import SwiftData
import SwiftUI

// A folder of workouts: its name and how many workouts it holds.
struct FolderCard: View {
    let folder: Folder
    // A workout held over it, to be put in it.
    let isTarget: Bool
    @Query private var workouts: [Workout]

    init(folder: Folder, isTarget: Bool) {
        self.folder = folder
        self.isTarget = isTarget
        let id: String? = folder.id
        _workouts = Query(filter: #Predicate<Workout> { !$0.removed && $0.folderID == id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "folder")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
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
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, lineWidth: 3)
            }
        }
        .animation(.snappy, value: isTarget)
        .accessibilityElement(children: .combine)
    }
}
