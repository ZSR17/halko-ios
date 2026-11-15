import HalkoCore
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

// A card of a page of workouts, by the identifier of what it shows.
enum DraggedCard: Equatable {
    case workout(String)
    case folder(String)
}

// The order a page shows while a card is dragged over it, not written yet.
struct DragOrder: Equatable {
    var folderIDs: [String]
    var workoutIDs: [String]
}

// A card touched and held, then dragged: over another, it takes its place, the folders among themselves, the workouts
// among themselves; a workout let go on a folder goes in it, last. The order is written once the cards stop moving, so a
// card let go away from the page keeps the order shown.
@Observable
final class CardDrag {
    private(set) var dragged: DraggedCard?
    // The folder a workout is held over.
    private(set) var targetFolderID: String?
    private(set) var order: DragOrder?

    func folders(_ folders: [Folder]) -> [Folder] {
        arranged(folders, ids: order?.folderIDs, id: \.id)
    }

    func workouts(_ workouts: [Workout]) -> [Workout] {
        arranged(workouts, ids: order?.workoutIDs, id: \.id)
    }

    func start(_ card: DraggedCard) -> NSItemProvider {
        dragged = card
        targetFolderID = nil
        switch card {
        case .workout(let id), .folder(let id):
            return NSItemProvider(object: id as NSString)
        }
    }

    func enter(_ target: DraggedCard, folders: [Folder], workouts: [Workout]) {
        guard let dragged, dragged != target else { return }
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

    func exit(_ target: DraggedCard) {
        if case .folder(let id) = target, targetFolderID == id {
            targetFolderID = nil
        }
    }

    // Let go on the page (`target` nil) or on a card.
    func drop(on target: DraggedCard?, in context: ModelContext, folders: [Folder], workouts: [Workout]) -> Bool {
        defer {
            dragged = nil
            targetFolderID = nil
        }
        guard let dragged else { return false }
        save(in: context, folders: folders, workouts: workouts)
        if case .workout(let id) = dragged, case .folder(let folderID)? = target,
           let workout = workouts.first(where: { $0.id == id }) {
            change { try context.moveWorkout(workout, to: folderID) }
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
    // A card that can be touched and held to be dragged, and over which another can be.
    func draggableCard(_ card: DraggedCard, drag: CardDrag, folders: [Folder], workouts: [Workout]) -> some View {
        modifier(DraggableCard(card: card, drag: drag, folders: folders, workouts: workouts))
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

private struct DraggableCard: ViewModifier {
    let card: DraggedCard
    let drag: CardDrag
    let folders: [Folder]
    let workouts: [Workout]
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            // Lifted with the rounded corners of the card.
            .contentShape(.dragPreview, .rect(cornerRadius: 16))
            .onDrag {
                drag.start(card)
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
        if let target {
            drag.enter(target, folders: folders, workouts: workouts)
        }
    }

    func dropExited(info: DropInfo) {
        if let target {
            drag.exit(target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.drop(on: target, in: context, folders: folders, workouts: workouts)
    }
}
