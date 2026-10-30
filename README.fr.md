<div align="center">

[English](README.md) · Français

# Halko pour iPhone et Apple Watch

**L'app native de [Halko](https://github.com/ZSR17/halko), le suivi de musculation auto-hébergé.**

[![Licence Apache 2.0](https://img.shields.io/badge/licence-Apache%202.0-blue.svg)](LICENSE)
[![CI](https://github.com/ZSR17/halko-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/ZSR17/halko-ios/actions/workflows/ci.yml)

</div>

Halko pour iPhone et Apple Watch suit tes séances en direct, seule et entièrement hors ligne, ou synchronisée
avec ton serveur Halko s'il est configuré dans l'app. L'app montre fonctionne sans l'iPhone à portée.

En cours de développement : rien à installer pour l'instant.

## Compiler

Le projet Xcode est généré à partir de `project.yml` par [XcodeGen](https://github.com/yonaskolb/XcodeGen) ;
il ne fait pas partie du dépôt.

```sh
brew install xcodegen
xcodegen generate
open Halko.xcodeproj
```

Prérequis : Xcode 26 ou plus récent ; les apps tournent sur iOS 26 et watchOS 26.

- `Halko/` : l'app iPhone.
- `HalkoWatch/` : l'app Apple Watch, installée avec l'app iPhone.
- `Packages/HalkoCore/` : le code commun aux deux apps (données, synchro, logique des séances), testé par `swift test`.
- `HalkoUITests/` : les tests d'interface ; chaque écran testé est gardé en capture dans l'exécution de la CI.
- `ExerciseImages/` et `Packages/HalkoCore/Sources/HalkoCore/Resources/exercises.json` : la bibliothèque
  d'exercices, embarquée pour que les apps marchent sans serveur, avec les mêmes identifiants que sur tout serveur
  Halko. Les deux sont faits par le serveur : `npm run export:library -- --out <dossier>` dans le dépôt
  [Halko](https://github.com/ZSR17/halko), puis copier `<dossier>/images/` dans `ExerciseImages/` et
  `<dossier>/exercises.json` ici.

## Licence

[Apache 2.0](LICENSE).
