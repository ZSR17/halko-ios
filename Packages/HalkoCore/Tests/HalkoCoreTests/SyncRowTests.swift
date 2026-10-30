import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct SyncRowTests {
    // A fresh in-memory database for each test, kept alive as long as its context.
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
    }

    // Rows as the server sends them (`shared/src/sync.ts`).
    static let exerciseJSON = """
        {"id":"e1","createdAt":1761700000000,"updatedAt":1761700000123,"deleted":false,"source":"builtin",
        "name":"Barbell Squat","sport":"strength","exerciseType":"weight_reps","category":"strength","level":null,
        "equipment":["barbell"],"primaryMuscles":["quads"],"secondaryMuscles":["glutes","hamstrings"],
        "instructions":["Stand up."],"mediaIds":[],"mediaUrls":[],"unilateral":false,"customized":false,
        "translations":{"fr":{"name":"Squat barre","instructions":["Relève-toi."]}},"sourceRef":"Barbell_Squat"}
        """
    static let folderJSON = """
        {"id":"f1","createdAt":1,"updatedAt":2,"deleted":false,"name":"Push","position":0}
        """
    static let workoutJSON = """
        {"id":"w1","createdAt":1,"updatedAt":2,"deleted":false,"folderId":null,"sport":"strength","name":"Legs",
        "note":null,"position":3}
        """
    static let workoutItemJSON = """
        {"id":"i1","createdAt":1,"updatedAt":2,"deleted":false,"workoutId":"w1","exerciseId":"e1","position":0,
        "mode":"per_set","supersetGroup":null,"targets":[{"kind":"warmup","reps":10},
        {"kind":"normal","reps":5,"weightG":100000,"restS":120}],"bySide":null,"switchS":null,"note":"Slow"}
        """
    static let sessionJSON = """
        {"id":"s1","createdAt":1,"updatedAt":2,"deleted":false,"workoutId":"w1","sport":"strength","name":"Legs",
        "startedAt":1761700000000,"endedAt":null,"note":null}
        """
    static let setLogJSON = """
        {"id":"l1","createdAt":1,"updatedAt":2,"deleted":false,"sessionId":"s1","exerciseId":"e1",
        "workoutItemId":null,"position":0,"setIndex":1,"kind":"normal","reps":5,"weightG":100000,
        "durationS":12.5,"completedAt":1761700300000}
        """

    // Decodes the JSON into a row, stores it in a model, and gives back the JSON of the model's row.
    func roundTrip<Model: SyncedModel>(_ json: String, as _: Model.Type) throws -> String {
        let row = try JSONDecoder().decode(Model.Row.self, from: Data(json.utf8))
        let model = Model(row)
        #expect(model.row == row)
        return String(decoding: try JSONEncoder().encode(model.row), as: UTF8.self)
    }

    func sameJSON(_ a: String, _ b: String) throws -> Bool {
        let objectA = try JSONSerialization.jsonObject(with: Data(a.utf8)) as? NSDictionary
        let objectB = try JSONSerialization.jsonObject(with: Data(b.utf8)) as? NSDictionary
        return objectA != nil && objectA == objectB
    }

    @Test("Keeps each table's rows as the server sends them, nulls included")
    func rows() throws {
        #expect(try sameJSON(roundTrip(Self.exerciseJSON, as: Exercise.self), Self.exerciseJSON))
        #expect(try sameJSON(roundTrip(Self.folderJSON, as: Folder.self), Self.folderJSON))
        #expect(try sameJSON(roundTrip(Self.workoutJSON, as: Workout.self), Self.workoutJSON))
        #expect(try sameJSON(roundTrip(Self.workoutItemJSON, as: WorkoutItem.self), Self.workoutItemJSON))
        #expect(try sameJSON(roundTrip(Self.sessionJSON, as: Session.self), Self.sessionJSON))
        #expect(try sameJSON(roundTrip(Self.setLogJSON, as: SetLog.self), Self.setLogJSON))
    }

    @Test("Leaves the absent measures of a set out of the JSON")
    func absentMeasures() throws {
        let json = try roundTrip(Self.setLogJSON, as: SetLog.self)
        #expect(!json.contains("distanceM"))
        #expect(!json.contains("unilateral"))
        #expect(json.contains(#""workoutItemId":null"#))
    }

    @Test("Keeps milliseconds exact", arguments: [0, 1, 999, 1_761_700_000_123, 4_102_444_799_999])
    func milliseconds(value: Int) {
        #expect(Date(epochMilliseconds: value).epochMilliseconds == value)
    }

    func folder(_ id: String, name: String, updatedAt: Int, deleted: Bool = false) -> FolderRow {
        FolderRow(id: id, createdAt: 1, updatedAt: updatedAt, deleted: deleted, name: name, position: 0)
    }

    func folders() throws -> [String: Folder] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Folder>()).map { ($0.id, $0) })
    }

    @Test("Keeps the most recent version of each row")
    func latestWins() throws {
        try context.apply([folder("a", name: "A1", updatedAt: 10), folder("b", name: "B1", updatedAt: 10)], to: Folder.self)
        try context.apply([folder("a", name: "A2", updatedAt: 20), folder("b", name: "B0", updatedAt: 5), folder("c", name: "C1", updatedAt: 1)], to: Folder.self)

        let stored = try folders()
        #expect(stored.count == 3)
        #expect(stored["a"]?.name == "A2")
        #expect(stored["b"]?.name == "B1")
        #expect(stored["c"]?.name == "C1")
    }

    @Test("Stores a row received twice in one batch once, the most recent version")
    func duplicateInBatch() throws {
        try context.apply([folder("a", name: "A2", updatedAt: 20), folder("a", name: "A1", updatedAt: 10)], to: Folder.self)
        try context.save()

        let stored = try folders()
        #expect(stored.count == 1)
        #expect(stored["a"]?.name == "A2")
    }

    @Test("Keeps a deleted row, marked deleted")
    func deletion() throws {
        try context.apply([folder("a", name: "A", updatedAt: 10)], to: Folder.self)
        try context.apply([folder("a", name: "A", updatedAt: 20, deleted: true)], to: Folder.self)
        try context.save()

        #expect(try folders()["a"]?.removed == true)
        #expect(try folders()["a"]?.row.deleted == true)
    }
}
