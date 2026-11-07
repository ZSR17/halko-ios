#!/usr/bin/env bash
# The interface tests of a test report that failed, then passed when tried again: the run stays green, but a test that
# does so often hides a screen gone slow or a test to make steadier. Listed in the summary of the run and as warnings;
# never fails.
# Usage: retried-tests.sh <report.xcresult> <what was tested>
set -u
report=$1
tested=$2

if ! json=$(xcrun xcresulttool get test-results tests --path "$report" 2>/dev/null); then
  echo "$tested: cannot read $report."
  exit 0
fi
retried=$(jq -r '
  .. | objects | select(.nodeType == "Test Case" and .result == "Passed")
  | select([.children[]? | select(.nodeType == "Repetition" and .result == "Failed")] | length > 0)
  | .nodeIdentifier // .name' <<< "$json" | sort -u)

if [ -z "$retried" ]; then
  echo "$tested: no test passed only when tried again."
  exit 0
fi
{
  echo "### $tested: passed only when tried again"
  echo
  sed 's/^/- /' <<< "$retried"
} >> "$GITHUB_STEP_SUMMARY"
while IFS= read -r test; do
  echo "::warning title=Passed when tried again::$tested: $test"
done <<< "$retried"
