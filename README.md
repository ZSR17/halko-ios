<div align="center">

English · [Français](README.fr.md)

# Halko for iPhone and Apple Watch

**The native app of [Halko](https://github.com/ZSR17/halko), the self-hosted workout tracker.**

[![Apache 2.0 License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![CI](https://github.com/ZSR17/halko-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/ZSR17/halko-ios/actions/workflows/ci.yml)

</div>

Halko for iPhone and Apple Watch follows your workouts live, on its own and fully offline, or synced with
your Halko server when one is set up in the app. The watch app works without the iPhone nearby.

Work in progress: nothing to install yet.

## Building

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen); it is
not part of the repository.

```sh
brew install xcodegen
xcodegen generate
open Halko.xcodeproj
```

Requirements: Xcode 26 or later; the apps run on iOS 26 and watchOS 26.

- `Halko/`: the iPhone app.
- `HalkoWatch/`: the Apple Watch app, installed with the iPhone app.
- `Packages/HalkoCore/`: the code both apps share (data, sync, workout logic), tested with `swift test`.
- `HalkoUITests/`: the interface tests; each screen tested is kept as a screenshot in the CI run.
- `ExerciseImages/` and `Packages/HalkoCore/Sources/HalkoCore/Resources/exercises.json`: the exercise library,
  embedded so that the apps work without a server, with the same ids as on every Halko server. Both are made by
  the server: `npm run export:library -- --out <folder>` in the [Halko](https://github.com/ZSR17/halko)
  repository, then copy `<folder>/images/` to `ExerciseImages/` and `<folder>/exercises.json` here.

## License

[Apache 2.0](LICENSE).
