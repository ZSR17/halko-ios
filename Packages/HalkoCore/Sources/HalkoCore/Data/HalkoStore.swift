import SwiftData

// The local database, the source of truth on each device (iPhone and watch). A change to a model adds a schema
// version and its migration stage, so that the data of an earlier version is kept.
public enum HalkoSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Exercise.self, Folder.self, Workout.self, WorkoutItem.self, Session.self, SetLog.self]
    }
}

public enum HalkoMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [HalkoSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum HalkoStore {
    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: HalkoSchemaV1.self),
            migrationPlan: HalkoMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }
}
