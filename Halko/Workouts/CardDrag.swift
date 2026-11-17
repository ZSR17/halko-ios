import HalkoCore
import os
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.zsr.halko", category: "workouts")

// A card of a page of workouts, by the identifier of what it shows.
enum DraggedCard: Hashable {
    case workout(String)
    case folder(String)
}

// The order a page shows once a card is let go, until the queries show it too.
struct DragOrder: Equatable {
    var folderIDs: [String]
    var workoutIDs: [String]
}

// A workout let go on a folder: said for a moment.
struct FiledWorkout: Equatable {
    let workout: String
    let folder: String
}

// Where the cards are drawn while one is held: the place it would take, and where each other goes to leave it room.
private struct DragPlan {
    let slot: Int
    let origins: [DraggedCard: CGPoint]
    let gap: CGRect
}

// A card dragged by its handle, as the exercises of a workout: it follows the finger, the others make room for
// it where it would go, dashed, and it takes that place when let go; the folders among themselves, the workouts among
// themselves. A workout let go on a folder goes in it, last, and the folder under it is in the color of the app.
@Observable
final class CardDrag {
    // Read by the measures of the cards, off the main actor.
    nonisolated static let space = "workout-cards"
    nonisolated private static let spacing: CGFloat = 10

    private(set) var dragged: DraggedCard?
    private(set) var order: DragOrder?
    var filed: FiledWorkout?
    // Scrolls the page while a card is held near its top or bottom.
    let edge = EdgeScroll()
    // Where the finger last moved.
    private var moved = CGPoint.zero
    // Where the finger holds the card, from its top left corner.
    private var grab = CGSize.zero
    // Where each card is laid out, before it is moved aside.
    private var frames: [DraggedCard: CGRect] = [:]

    // Where the finger is on the page, which may have scrolled under it since it moved.
    private var finger: CGPoint {
        CGPoint(x: moved.x, y: moved.y + edge.drift)
    }

    // The folder a workout is held over: in the column of the finger, the one the card covers most, a quarter of it at
    // least, or the one under the finger.
    var targetFolderID: String? {
        guard let dragged, case .workout = dragged, let held = frames[dragged] else { return nil }
        let card = CGRect(x: finger.x - grab.width, y: finger.y - grab.height, width: held.width, height: held.height)
        let finger = finger
        let covered = { (frame: CGRect) in
            frame.contains(finger) ? frame.height : frame.intersection(card).height
        }
        var best: (id: String, covered: CGFloat)?
        for (key, frame) in frames {
            guard case .folder(let id) = key, (frame.minX...frame.maxX).contains(finger.x) else { continue }
            let amount = covered(frame)
            if amount >= frame.height / 4, amount > best?.covered ?? 0 {
                best = (id, amount)
            }
        }
        return best?.id
    }

    func folders(_ folders: [Folder]) -> [Folder] {
        arranged(folders, ids: order?.folderIDs, id: \.id)
    }

    func workouts(_ workouts: [Workout]) -> [Workout] {
        arranged(workouts, ids: order?.workoutIDs, id: \.id)
    }

    func measure(_ card: DraggedCard, frame: CGRect) {
        frames[card] = frame
    }

    func move(_ card: DraggedCard, to location: CGPoint, from start: CGPoint) {
        if dragged == nil, let frame = frames[card] {
            grab = CGSize(width: start.x - frame.minX, height: start.y - frame.minY)
            withAnimation(.snappy) {
                dragged = card
            }
        }
        moved = location
        edge.hold(at: location.y)
    }

    // Where `card` is drawn from its place, among `cards` of its kind in their order.
    func offset(of card: DraggedCard, among cards: [DraggedCard]) -> CGSize {
        guard let dragged, let frame = frames[card] else { return .zero }
        if card == dragged {
            return CGSize(width: finger.x - grab.width - frame.minX, height: finger.y - grab.height - frame.minY)
        }
        guard let origin = plan(among: cards)?.origins[card] else { return .zero }
        return CGSize(width: origin.x - frame.minX, height: origin.y - frame.minY)
    }

    // Where the dragged card would go, among `cards` of its kind.
    func gap(among cards: [DraggedCard]) -> CGRect? {
        plan(among: cards)?.gap
    }

    // Let go: in a folder, or at its place, written.
    func end(in context: ModelContext, folders: [Folder], workouts: [Workout]) {
        guard let dragged else { return }
        defer {
            edge.release()
        }
        let folderCards = folders.map { DraggedCard.folder($0.id) }
        let workoutCards = workouts.map { DraggedCard.workout($0.id) }
        var order = DragOrder(folderIDs: folders.map(\.id), workoutIDs: workouts.map(\.id))
        switch dragged {
        case .workout(let id):
            if let folderID = targetFolderID, let workout = workouts.first(where: { $0.id == id }),
               let folder = folders.first(where: { $0.id == folderID }) {
                change {
                    try context.moveWorkout(workout, to: folderID)
                    filed = FiledWorkout(workout: workout.name, folder: folder.name)
                }
                withAnimation(.snappy) {
                    self.dragged = nil
                }
                return
            }
            if let slot = plan(among: workoutCards)?.slot {
                order.workoutIDs = Self.moved(id, to: slot, in: order.workoutIDs)
            }
        case .folder(let id):
            if let slot = plan(among: folderCards)?.slot {
                order.folderIDs = Self.moved(id, to: slot, in: order.folderIDs)
            }
        }
        withAnimation(.snappy) {
            self.order = order
            self.dragged = nil
        }
        let byID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        change {
            try context.order(folders: order.folderIDs.compactMap { foldersByID[$0] }, workouts: order.workoutIDs.compactMap { byID[$0] })
        }
    }

    // Reordering left before the card was let go.
    func cancel() {
        dragged = nil
        edge.release()
    }

    // Once the queries show the order written.
    func settle() {
        order = nil
    }

    private func plan(among cards: [DraggedCard]) -> DragPlan? {
        guard let dragged, cards.contains(dragged), targetFolderID == nil, let held = frames[dragged] else { return nil }
        let others = cards.filter { $0 != dragged }
        let center = CGPoint(x: finger.x - grab.width + held.width / 2, y: finger.y - grab.height + held.height / 2)
        switch dragged {
        case .workout:
            return listPlan(others: others, cards: cards, held: held, centerY: center.y)
        case .folder:
            return gridPlan(others: others, cards: cards, center: center)
        }
    }

    // A column: each place under the cards above it, of their own heights.
    private func listPlan(others: [DraggedCard], cards: [DraggedCard], held: CGRect, centerY: CGFloat) -> DragPlan? {
        guard let top = cards.first.flatMap({ frames[$0]?.minY }) else { return nil }
        var tops = [top]
        for card in others {
            tops.append(tops[tops.count - 1] + (frames[card]?.height ?? 0) + Self.spacing)
        }
        let slot = tops.indices.min { abs(tops[$0] + held.height / 2 - centerY) < abs(tops[$1] + held.height / 2 - centerY) } ?? 0
        var origins: [DraggedCard: CGPoint] = [:]
        for (index, card) in others.enumerated() {
            origins[card] = CGPoint(x: frames[card]?.minX ?? 0, y: tops[index] + (index >= slot ? held.height + Self.spacing : 0))
        }
        return DragPlan(slot: slot, origins: origins, gap: CGRect(x: held.minX, y: tops[slot], width: held.width, height: held.height))
    }

    // A grid: the places are those of the cards, in their order.
    private func gridPlan(others: [DraggedCard], cards: [DraggedCard], center: CGPoint) -> DragPlan? {
        let cells = cards.compactMap { frames[$0] }
        guard cells.count == cards.count else { return nil }
        let distance = { (cell: CGRect) in hypot(cell.midX - center.x, cell.midY - center.y) }
        let slot = cells.indices.min { distance(cells[$0]) < distance(cells[$1]) } ?? 0
        var origins: [DraggedCard: CGPoint] = [:]
        for (index, card) in others.enumerated() {
            origins[card] = cells[index >= slot ? index + 1 : index].origin
        }
        return DragPlan(slot: slot, origins: origins, gap: cells[slot])
    }

    private static func moved(_ id: String, to slot: Int, in ids: [String]) -> [String] {
        var ids = ids.filter { $0 != id }
        ids.insert(id, at: min(slot, ids.count))
        return ids
    }

    private func arranged<Model>(_ models: [Model], ids: [String]?, id: KeyPath<Model, String>) -> [Model] {
        guard let ids else { return models }
        let ranks = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // Stable: one the drag does not know yet stays where it is among the others.
        return models.sorted { (ranks[$0[keyPath: id]] ?? .max) < (ranks[$1[keyPath: id]] ?? .max) }
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
    // A card dragged by its handle among `cards`, those of its kind on the page in their order.
    func draggableCard(_ card: DraggedCard, drag: CardDrag, cards: [DraggedCard]) -> some View {
        modifier(DraggableCard(card: card, drag: drag, cards: cards))
    }

    // The page the cards are dragged on, `cards` those of each kind in their order: where the one held would go,
    // dashed. Put on the stack of the cards, not padded.
    func cardDragSpace(_ drag: CardDrag, folders: [DraggedCard], workouts: [DraggedCard]) -> some View {
        modifier(CardDragSpace(drag: drag, folders: folders, workouts: workouts))
    }

    // Where a workout let go on a folder went, for a few seconds.
    func filedBanner(_ drag: CardDrag) -> some View {
        modifier(FiledBannerModifier(drag: drag))
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

// The handle of a card: held and dragged, it moves the card, at once, as on the page of a workout; the rest of the card
// scrolls the page. VoiceOver moves the card by its actions.
struct CardGrip: View {
    let card: DraggedCard
    let drag: CardDrag
    let folders: [Folder]
    let workouts: [Workout]
    @Environment(\.modelContext) private var context

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.title3)
            .foregroundStyle(drag.dragged == card ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.secondaryText)))
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(CardDrag.space)).onChanged { value in
                drag.move(card, to: value.location, from: value.startLocation)
            }.onEnded { _ in
                drag.end(in: context, folders: folders, workouts: workouts)
            })
            .accessibilityHidden(true)
    }
}

private struct DraggableCard: ViewModifier {
    let card: DraggedCard
    let drag: CardDrag
    let cards: [DraggedCard]

    func body(content: Content) -> some View {
        let held = drag.dragged == card
        let offset = drag.offset(of: card, among: cards)
        content
            // Lifted; smaller over a folder, to go in it.
            .scaleEffect(held ? (drag.targetFolderID == nil ? 1.03 : 0.8) : 1)
            .shadow(color: .black.opacity(held ? 0.25 : 0), radius: 16, y: 8)
            .animation(.snappy, value: drag.targetFolderID)
            .offset(offset)
            // Under the finger as it moves; the others to their place.
            .animation(held ? nil : .snappy, value: offset)
            .zIndex(held ? 1 : 0)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(CardDrag.space)) } action: { frame in
                drag.measure(card, frame: frame)
            }
    }
}

private struct CardDragSpace: ViewModifier {
    let drag: CardDrag
    let folders: [DraggedCard]
    let workouts: [DraggedCard]

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(CardDrag.space))
            .edgeScrollSpace(drag.edge)
            .overlay(alignment: .topLeading) {
                if let gap = drag.gap(among: folders) ?? drag.gap(among: workouts) {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: gap.width, height: gap.height)
                        .offset(x: gap.minX, y: gap.minY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // The order shown when let go, until the queries show it too.
            .task(id: drag.order) {
                guard drag.order != nil else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                drag.settle()
            }
    }
}

private struct FiledBannerModifier: ViewModifier {
    let drag: CardDrag

    func body(content: Content) -> some View {
        content
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
