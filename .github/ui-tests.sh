#!/usr/bin/env bash
# The interface tests a pull request needs, from the files it changes (one per line on stdin): the test classes of
# the screens it changes, "all" for a change every screen depends on, nothing when it changes no screen. The run on
# master, after the merge, runs them all.
set -eu

tests=()
while IFS= read -r file; do
  case "$file" in
    # No screen: their own checks run anyway (HalkoCore's tests, the watch app's build, the icons).
    *.md | docs/* | LICENSE | NOTICE | .gitignore | .gitattributes | AppIcon.icon/* | HalkoWatch/* | Packages/HalkoCore/*) ;;
    # The texts: the screens showing a new one are changed with it.
    Halko/Localizable.xcstrings) ;;
    HalkoUITests/TestSupport.swift)
      echo all
      exit
      ;;
    HalkoUITests/*Tests.swift)
      # Not a test removed.
      if [ -f "$file" ]; then
        name=${file##*/}
        tests+=("${name%.swift}")
      fi
      ;;
    # Opened from the workout editor only.
    Halko/Exercises/ExercisePicker.swift) tests+=(WorkoutEditorTests) ;;
    Halko/Exercises/AddToWorkout.swift) tests+=(AddToWorkoutTests) ;;
    Halko/Exercises/ExerciseEditor.swift) tests+=(ExerciseEditorTests) ;;
    # The list and the page of an exercise, which the editor and « Add to a workout » open from.
    Halko/Exercises/*) tests+=(ExercisesTests ExerciseEditorTests AddToWorkoutTests) ;;
    # The workout editor, which « Add to a workout » opens too.
    Halko/Workouts/WorkoutEditor.swift | Halko/Workouts/ItemEditor.swift)
      tests+=(WorkoutEditorTests AddToWorkoutTests)
      ;;
    # Its boxes and the swipe to delete a set, which the session uses too.
    Halko/Workouts/ValueField.swift) tests+=(WorkoutEditorTests AddToWorkoutTests LiveSessionTests) ;;
    # The tab and the page of a workout, which the editor and the session open from.
    Halko/Workouts/*) tests+=(WorkoutsTests WorkoutEditorTests LiveSessionTests) ;;
    Halko/Session/*) tests+=(LiveSessionTests) ;;
    # Anything else (the views shared by the screens, the colours, the sample data, the project, the CI): all.
    *)
      echo all
      exit
      ;;
  esac
done

if [ ${#tests[@]} -gt 0 ]; then
  printf '%s\n' "${tests[@]}" | sort -u
fi
