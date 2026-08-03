#!/usr/bin/env bash
#
# Runs the Padawan Adventures unit test suite.
#
#   ./scripts/run_tests.sh                              # full suite
#   ./scripts/run_tests.sh SpriteSystemTests            # one suite
#   ./scripts/run_tests.sh SpriteSystemTests/loadsIdle  # one test
#
# Override the simulator with SIMULATOR_NAME / SIMULATOR_OS.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

SCHEME="${SCHEME:-Padawan Adventures}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_OS="${SIMULATOR_OS:-26.5}"
DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${SIMULATOR_OS}"

workdir="$(mktemp -d -t padawan-tests)"
log="$workdir/xcodebuild.log"
resultBundle="$workdir/Test.xcresult"
keep_workdir=0
cleanup() { [ "$keep_workdir" -eq 1 ] || rm -rf "$workdir"; }
trap cleanup EXIT

args=(
  test
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -resultBundlePath "$resultBundle"
)

for filter in "$@"; do
  args+=(-only-testing:"Padawan AdventuresTests/$filter")
done

echo "Running: xcodebuild ${args[*]}"
set +e
xcodebuild "${args[@]}" >"$log" 2>&1
status=$?
set -e

# xcodebuild's raw log buries results, so surface the parts that matter.
# Match only compiler diagnostics (file:line:col: error:); runtime log lines
# also contain the bare word "error:".
if grep -qE '^[^[:space:]]+:[0-9]+:[0-9]+: error:' "$log"; then
  echo
  echo "--- compile errors ---"
  grep -E '^[^[:space:]]+:[0-9]+:[0-9]+: error:' "$log" | sort -u | head -40
fi

if [ "$status" -eq 0 ]; then
  echo "** ALL TESTS PASSED **"
  exit 0
fi

# Assertion messages live in the result bundle, not the log.
if [ -d "$resultBundle" ]; then
  echo
  echo "--- failures ---"
  xcrun xcresulttool get test-results tests --path "$resultBundle" --format json \
    2>/dev/null | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)

failed = []
def walk(node):
    if isinstance(node, dict):
        if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
            failed.append(node)
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for child in node:
            walk(child)
walk(data)

seen = set()
for case in failed:
    name = case.get("name", "?")
    if name in seen:
        continue
    seen.add(name)
    print(name)
    messages, shown = [], set()
    for child in case.get("children", []):
        text = child.get("name", "")
        if text and text not in shown:
            shown.add(text)
            messages.append(text)
    for text in messages[:5]:
        print("    " + text)
    if len(messages) > 5:
        print("    ... and %d more" % (len(messages) - 5))
'
fi

echo
echo "Logs kept in: $workdir"
keep_workdir=1
exit "$status"
