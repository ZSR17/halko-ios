import HalkoCore
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

// A card of a page of workouts, by the identifier of what it shows.
enum DraggedCard: Hashable {
    case workout(String)
    case folder(String)
}

// The order a page shows while a card is dragged over it, not written yet.
struct DragOrder: Equatable {
    var folderIDs: [String]
    var workoutIDs: [String]
}

// A workout let go on a folder: said for a moment.
struct FiledWorkout: Equatable {
    let workout: String
    let folder: String
}

// A card touched and held, then dragged: over another, it takes its place, the folders among themselves, the workouts
// among themselves; a workout let go on a folder goes in it, last. The order is written once the cards stop moving, so a
// card let go away from the page keeps the order shown. While over the page, the card is only under the finger: its
// place on the page stays empty.
@Observable
final class CardDrag {
    private(set) var dragged: DraggedCard?
    // The folder a workout is held over.
    private(set) var targetFolderID: String?
    private(set) var order: DragOrder?
    var filed: FiledWorkout?
    // The cards, and the page (nil), the dragged card is over: one at a time, but told in no set order.
    private var over: Set<DraggedCard?> = []

    // The dragged card, over the page: shown under the finger only, from its own place on. Seen again over the bars,
    // where it is not let go.
    func isLifted(_ card: DraggedCard) -> Bool {
        dragged == card && !over.isEmpty
    }

    // The other cards, while a workout is held over a folder.
    func isPale(_ card: DraggedCard) -> Bool {
        guard let targetFolderID else { return false }
        return card != .folder(targetFolderID)
    }

    func folders(_ folders: [Folder]) -> [Folder] {
        arranged(folders, ids: order?.folderIDs, id: \.id)
    }

    func workouts(_ workouts: [Workout]) -> [Workout] {
        arranged(workouts, ids: order?.workoutIDs, id: \.id)
    }

    func start(_ card: DraggedCard) -> NSItemProvider {
        dragged = card
        targetFolderID = nil
        over = []
        switch card {
        case .workout(let id), .folder(let id):
            return NSItemProvider(object: id as NSString)
        }
    }

    func enter(_ target: DraggedCard?, folders: [Folder], workouts: [Workout]) {
        over.insert(target)
        guard let target, let dragged, dragged != target else { return }
        var order = order ?? DragOrder(folderIDs: folders.map(\.id), workoutIDs: workouts.map(\.id))
        switch (dragged, target) {
        case (.workout(let id), .workout(let targetID)):
            Self.move(id, to: targetID, in: &order.workoutIDs)
        case (.folder(let id), .folder(let targetID)):
            Self.move(id, to: targetID, in: &order.folderIDs)
        case (.workout, .folder(let folderID)):
            targetFolderID = folderID
            return
        case (.folder, .workout):
            return
        }
        withAnimation(.snappy) {
            self.order = order
        }
    }

    func exit(_ target: DraggedCard?) {
        over.remove(target)
        if case .folder(let id)? = target, targetFolderID == id {
            targetFolderID = nil
        }
    }

    // Let go on the page (`target` nil) or on a card.
    func drop(on target: DraggedCard?, in context: ModelContext, folders: [Folder], workouts: [Workout]) -> Bool {
        defer {
            dragged = nil
            targetFolderID = nil
            over = []
        }
        guard let dragged else { return false }
        save(in: context, folders: folders, workouts: workouts)
        if case .workout(let id) = dragged, case .folder(let folderID)? = target,
           let workout = workouts.first(where: { $0.id == id }), let folder = folders.first(where: { $0.id == folderID }) {
            change {
                try context.moveWorkout(workout, to: folderID)
                filed = FiledWorkout(workout: workout.name, folder: folder.name)
            }
        }
        return true
    }

    func save(in context: ModelContext, folders: [Folder], workouts: [Workout]) {
        guard order != nil else { return }
        let folders = self.folders(folders)
        let workouts = self.workouts(workouts)
        change { try context.order(folders: folders, workouts: workouts) }
        order = nil
    }

    private func arranged<Model>(_ models: [Model], ids: [String]?, id: KeyPath<Model, String>) -> [Model] {
        guard let ids else { return models }
        let ranks = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // Stable: one the drag does not know yet stays where it is among the others.
        return models.sorted { (ranks[$0[keyPath: id]] ?? .max) < (ranks[$1[keyPath: id]] ?? .max) }
    }

    private static func move(_ id: String, to targetID: String, in ids: inout [String]) {
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: targetID) else { return }
        ids.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
    }

    private func change(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            logger.error("Cannot reorder the workouts: \(String(describing: error))")
        }
    }
}

extension View {
    // A card that can be touched and held to be dragged, and over which another can be. `preview`: the card under the
    // finger, drawn apart from the one on the page, which leaves its place.
    func draggableCard<Preview: View>(
        _ card: DraggedCard, drag: CardDrag, folders: [Folder], workouts: [Workout], @ViewBuilder preview: () -> Preview
    ) -> some View {
        modifier(DraggableCard(card: card, drag: drag, folders: folders, workouts: workouts, preview: preview()))
    }

    // The page the cards are dragged on: a card let go between two keeps the order shown.
    func cardDrops(_ drag: CardDrag, folders: [Folder], workouts: [Workout]) -> some View {
        modifier(CardDrops(drag: drag, folders: folders, workouts: workouts))
    }

    // Moves for VoiceOver, which cannot drag: one place before or after, where there is one.
    func moveActions(index: Int, count: Int, horizontal: Bool = false, move: @escaping (Int) -> Void) -> some View {
        accessibilityActions {
            if index > 0 {
                Button(horizontal ? "Move left" : "Move up") {
                    move(-1)
                }
            }
            if index < count - 1 {
                Button(horizontal ? "Move right" : "Move down") {
                    move(1)
                }
            }
        }
    }
}

private struct DraggableCard<Preview: View>: ViewModifier {
    let card: DraggedCard
    let drag: CardDrag
    let folders: [Folder]
    let workouts: [Workout]
    let preview: Preview
    @State private var width: CGFloat?
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accent) private var accent
    @Environment(\.onAccent) private var onAccent

    func body(content: Content) -> some View {
        content
            .opacity(drag.isLifted(card) ? 0 : drag.isPale(card) ? 0.55 : 1)
            .animation(.snappy, value: drag.isPale(card))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // Lifted with the rounded corners of the card.
            .contentShape(.dragPreview, .rect(cornerRadius: 16))
            .onDrag {
                drag.start(card)
            } preview: {
                // Drawn outside the page: its width, data and colors given again.
                preview
                    .frame(width: width)
                    .contentShape(.dragPreview, .rect(cornerRadius: 16))
                    .modelContainer(context.container)
                    .environment(\.colorScheme, colorScheme)
                    .tint(accent)
                    .environment(\.accent, accent)
                    .environment(\.onAccent, onAccent)
            }
            .onDrop(of: [.plainText], delegate: CardDrop(target: card, drag: drag, folders: folders, workouts: workouts, context: context))
    }
}

private struct CardDrops: ViewModifier {
    let drag: CardDrag
    let folders: [Folder]
    let workouts: [Workout]
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.plainText], delegate: CardDrop(target: nil, drag: drag, folders: folders, workouts: workouts, context: context))
            .task(id: drag.order) {
                guard drag.order != nil else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                drag.save(in: context, folders: folders, workouts: workouts)
            }
            // A light tap when a workout comes over a folder.
            .sensoryFeedback(.impact(weight: .light), trigger: drag.targetFolderID) { _, folderID in
                folderID != nil
            }
            .overlay(alignment: .bottom) {
                if let filed = drag.filed {
                    FiledBanner(filed: filed) {
                        drag.filed = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: drag.filed)
    }
}

// Where a workout let go on a folder went, for a few seconds; VoiceOver says it.
private struct FiledBanner: View {
    let filed: FiledWorkout
    let done: () -> Void

    var body: some View {
        let text = Text("“\(filed.workout)” moved to \(Text(filed.folder).bold())")
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            text
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .padding()
        .accessibilityElement(children: .combine)
        .task(id: filed) {
            AccessibilityNotification.Announcement(String(localized: "“\(filed.workout)” moved to \(filed.folder)")).post()
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            done()
        }
    }
}

// Only a card of the page: nothing from another app.
private struct CardDrop: DropDelegate {
    let target: DraggedCard?
    let drag: CardDrag
    let folders: [Folder]
    let workouts: [Workout]
    let context: ModelContext

    func validateDrop(info: DropInfo) -> Bool {
        drag.dragged != nil
    }

    func dropEntered(info: DropInfo) {
        drag.enter(target, folders: folders, workouts: workouts)
    }

    func dropExited(info: DropInfo) {
        drag.exit(target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.drop(on: target, in: context, folders: folders, workouts: workouts)
    }
}
