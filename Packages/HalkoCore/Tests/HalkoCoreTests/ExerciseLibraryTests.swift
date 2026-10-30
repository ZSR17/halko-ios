import Foundation
import SwiftData
import Testing
@testable import HalkoCore

struct ExerciseLibraryTests {
    let container: ModelContainer
    let context: ModelContext
    let library: [ExerciseRow]

    init() throws {
        container = try HalkoStore.container(inMemory: true)
        context = ModelContext(container)
        library = try ExerciseLibrary.rows()
    }

    func exercises() throws -> [String: Exercise] {
        Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Exercise>()).map { ($0.id, $0) })
    }

    @Test("Embeds the library with the ids of every server")
    func embedded() {
        #expect(library.count == 876)
        #expect(Set(library.map(\.id)).count == library.count)
        #expect(library.allSatisfy { $0.source == .builtin && $0.id == "lib-\($0.sourceRef ?? "")" })
        #expect(library.allSatisfy { $0.translations["fr"] != nil && !$0.customized && !$0.deleted })
        #expect(library.first { $0.id == "lib-Barbell_Squat" }?.primaryMuscles == [.quads])
    }

    @Test("Installs every exercise once, then leaves them alone")
    func install() throws {
        try context.installLibrary(library)
        try context.installLibrary(library)

        let stored = try exercises()
        #expect(stored.count == library.count)
        #expect(!context.hasChanges)
    }

    @Test("Brings exercises to a newer library, except the ones the user changed")
    func newerLibrary() throws {
        let squat = try #require(library.first { $0.id == "lib-Barbell_Squat" })
        let bench = try #require(library.first { $0.id == "lib-Barbell_Bench_Press_-_Medium_Grip" })
        try context.installLibrary([squat, bench])
        let stored = try exercises()
        stored[bench.id]?.customized = true
        stored[bench.id]?.name = "My bench"
        stored[bench.id]?.updatedAt = Date(epochMilliseconds: bench.updatedAt + 1)

        var newer = [squat, bench]
        for index in newer.indices {
            newer[index].updatedAt += 10
            newer[index].name += " (new)"
        }
        try context.installLibrary(newer)

        #expect(stored[squat.id]?.name == "Barbell Squat (new)")
        #expect(stored[bench.id]?.name == "My bench")
    }

    @Test("Keeps a more recent copy received from a server")
    func olderLibrary() throws {
        let squat = try #require(library.first { $0.id == "lib-Barbell_Squat" })
        var fromServer = squat
        fromServer.updatedAt += 10
        fromServer.instructions = ["Fixed on the server."]
        try context.apply([fromServer], to: Exercise.self)

        try context.installLibrary([squat])

        #expect(try exercises()[squat.id]?.instructions == ["Fixed on the server."])
    }
}
