#!/usr/bin/env bash
# Whether a pull request needs the watch app's interface tests, from the files it changes (one per line on stdin):
# "true", unless every file is one the watch app is not built with. The run on master, after the merge, runs them anyway.
set -eu

# The files of the iPhone app the watch app is built with too, as project.yml lists them.
shared=$(sed -nE 's/^ +- (path: )?(Halko\/[^ ]+)$/\2/p' project.yml)

needed=false
while IFS= read -r file; do
  case "$file" in
    # Neither the watch app nor its tests: the documentation, the iPhone app's tests, its widgets, what only they use,
    # and the choice of the iPhone app's tests.
    *.md | docs/* | LICENSE | NOTICE | .gitignore | .gitattributes | HalkoUITests/* | HalkoWidgets/* | Shared/* | .github/ui-tests.sh) ;;
    Halko/*)
      for path in $shared; do
        if [ "$file" = "$path" ] || [ "${file#"$path"/}" != "$file" ]; then
          needed=true
        fi
      done
      ;;
    # Anything else (the watch app, HalkoCore, the project, the CI, the icon): the watch app may change.
    *) needed=true ;;
  esac
done

echo "$needed"
