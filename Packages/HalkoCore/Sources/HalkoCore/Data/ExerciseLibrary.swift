import Foundation
import os
import SwiftData

// The exercise library embedded in the apps, there from the first launch without a server. `exercises.json` is
// made by the server (`npm run export:library` in the Halko repository): the same exercises as on every server,
// with the same ids (`lib-<sourceRef>`) and media ids; the iPhone app holds the pictures (`ExerciseImages/`).
public enum ExerciseLibrary {
    private static let logger = Logger(subsystem: "com.zsr.halko", category: "library")

    static func rows() throws -> [ExerciseRow] {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([ExerciseRow].self, from: Data(contentsOf: url))
    }

    // At every launch, in the background: does nothing once this version of the library is there.
    public static func install(in container: ModelContainer) async {
        do {
            try await LibraryInstaller(modelContainer: container).install()
        } catch {
            logger.error("Cannot install the exercise library: \(String(describing: error))")
        }
    }
}

@ModelActor
private actor LibraryInstaller {
    func install() throws {
        try modelContext.installLibrary(ExerciseLibrary.rows())
    }
}

extension ModelContext {
    // Adds the library exercises the device lacks, and brings the others to a more recent library, except the
    // ones the user changed: a new library never undoes their version.
    func installLibrary(_ rows: [ExerciseRow]) throws {
        let stored = try fetch(FetchDescriptor(predicate: Exercise.withIDs(rows.map(\.id))))
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for row in rows {
            if let exercise = byID[row.id] {
                if !exercise.customized && row.updatedAt > exercise.updatedAt.epochMilliseconds {
                    exercise.update(from: row)
                }
            } else {
                insert(Exercise(row))
            }
        }
        if hasChanges {
            try save()
        }
    }
}
