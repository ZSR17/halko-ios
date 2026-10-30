import Testing
@testable import HalkoCore

struct ExerciseFilterTests {
    let bench = Exercise(id: "bench", name: "Barbell Bench Press", exerciseType: .weightReps, equipment: ["barbell"], primaryMuscles: [.chest], secondaryMuscles: [.shoulders, .triceps], translations: ["fr": ExerciseText(name: "Développé couché", instructions: [])])
    let curl = Exercise(id: "curl", name: "Dumbbell Curl", exerciseType: .weightReps, equipment: ["dumbbell"], primaryMuscles: [.biceps])
    let pushup = Exercise(id: "pushup", name: "Pushups", exerciseType: .bodyweightReps, equipment: ["body only"], primaryMuscles: [.chest], secondaryMuscles: [.triceps])
    let stretch = Exercise(id: "stretch", name: "Chest Stretch", exerciseType: .duration, primaryMuscles: [.chest])
    let crunch = Exercise(id: "crunch", name: "Ball Crunch", exerciseType: .bodyweightReps, equipment: ["exercise ball", "rings"], primaryMuscles: [.abs])

    func chosen(_ filter: ExerciseFilter) -> [String] {
        [bench, curl, pushup, stretch, crunch].filter(filter.chooses).map(\.id)
    }

    @Test("Picks an area as primary, then secondary, then lets it go")
    func pickCycle() {
        var filter = ExerciseFilter()
        filter.cycle([.lats, .middleback])
        #expect(filter.pick.primary == [.lats, .middleback])
        #expect(filter.pick.role(of: [.lats, .middleback]) == .primary)
        filter.cycle([.chest])
        filter.cycle([.lats, .middleback])
        #expect(filter.pick.primary == [.chest])
        #expect(filter.pick.secondary == [.lats, .middleback])
        filter.cycle([.lats, .middleback])
        #expect(filter.pick.role(of: [.lats, .middleback]) == nil)
        #expect(!filter.pick.isEmpty)
        filter.clearPick()
        #expect(filter.isAllMuscles)
    }

    @Test("Finds the exercises working the areas picked in the roles picked, as on the website")
    func worksAsPicked() {
        // Picked on the body: the glutes area also stands for the abductors.
        var pick = MusclePick()
        pick.cycle([.quads])
        pick.cycle([.glutes, .abductors])
        pick.cycle([.glutes, .abductors])
        pick.cycle([.hamstrings])
        pick.cycle([.hamstrings])
        #expect(pick.isWorked(primary: [.quads], secondary: [.glutes, .hamstrings]))
        // Other muscles too: still found.
        #expect(pick.isWorked(primary: [.quads, .chest], secondary: [.calves, .glutes, .hamstrings, .lowerback]))
        // A picked muscle missing, or in the other role: not found.
        #expect(!pick.isWorked(primary: [.quads], secondary: [.glutes]))
        #expect(!pick.isWorked(primary: [.quads, .glutes], secondary: [.hamstrings]))

        // Lats and middle back are one area; a primary muscle also listed as secondary is a primary one.
        var back = MusclePick()
        back.cycle([.lats, .middleback])
        #expect(back.isWorked(primary: [.lats], secondary: [.middleback]))
        back.cycle([.lats, .middleback])
        #expect(!back.isWorked(primary: [.lats], secondary: [.middleback]))
    }

    @Test("Chooses a group or muscles picked, not both")
    func groupOrPick() {
        var filter = ExerciseFilter()
        #expect(chosen(filter).count == 5)
        filter.choose(.chest)
        #expect(chosen(filter) == ["bench", "pushup", "stretch"])
        filter.cycle([.triceps])
        #expect(filter.group == nil)
        // Triceps primary: none.
        #expect(chosen(filter).isEmpty)
        filter.cycle([.triceps])
        #expect(chosen(filter) == ["bench", "pushup"])
        filter.choose(.arms)
        #expect(filter.pick.isEmpty)
        #expect(chosen(filter) == ["curl"])
    }

    @Test("Keeps the exercises the equipment at hand is all there for")
    func equipment() {
        var filter = ExerciseFilter()
        filter.equipment = [.barbell]
        #expect(chosen(filter) == ["bench"])
        // Without equipment: those listing none, or only the body.
        filter.equipment = [.bodyOnly]
        #expect(chosen(filter) == ["pushup", "stretch"])
        filter.equipment = [.barbell, .dumbbell, .bodyOnly]
        #expect(chosen(filter) == ["bench", "curl", "pushup", "stretch"])
        // Equipment outside the list is never at hand.
        filter.equipment = [.exerciseBall]
        #expect(chosen(filter).isEmpty)
    }

    @Test("Searches without case or accents")
    func search() {
        var filter = ExerciseFilter()
        #expect(filter.queryKey.isEmpty)
        filter.query = "  DÉVELOPPÉ cou "
        #expect(filter.queryKey == "developpe cou")
        #expect(ExerciseFilter.searchKey(bench.name(in: "fr")).contains(filter.queryKey))
        #expect(ExerciseFilter.searchKey("Écarté à la poulie") == "ecarte a la poulie")
    }
}
