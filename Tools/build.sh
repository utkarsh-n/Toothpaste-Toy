#!/bin/zsh
# xcodebuild hangs loading projects from this iCloud-synced folder, and Toothpaste Toy depends on ../LabKit by relative
# path, so mirror BOTH folders side by side to a local scratch directory and build there:
#   $TT_BUILD_DIR/src/LabKit         ← AI Stuff/LabKit
#   $TT_BUILD_DIR/src/ToothpasteToy  ← AI Stuff/Toothpaste Toy (without Documentation)
#
#   Tools/build.sh sim                    → Debug build for the simulator (TT_SIM, default "iPhone 17 Pro")
#   Tools/build.sh device                 → Release build for a connected iPhone (generic iOS, team YOUR_TEAM_ID)
#   Tools/build.sh test                   → ToothpasteToyTests + ToothpasteToyUITests on the simulator
#   Tools/build.sh build-for-testing      → build the app and both test bundles for the simulator
#   Tools/build.sh test-without-building  → run the tests of the last build-for-testing
# Anything after the command goes to xcodebuild, e.g.
#   Tools/build.sh test -only-testing:ToothpasteToyTests/PhysTests
# Override the work directory with TT_BUILD_DIR (parallel agents must each use their own) and the simulator with TT_SIM.
# The old names RHEO_BUILD_DIR and RHEO_SIM still work (TT_* wins when both are set).
set -e
APP="$(cd "$(dirname "$0")/.." && pwd)"              # …/AI Stuff/Toothpaste Toy
ROOT="$(cd "$APP/.." && pwd)"                        # …/AI Stuff
WORK="${TT_BUILD_DIR:-${RHEO_BUILD_DIR:-${TMPDIR:-/tmp}/ToothpasteToyBuild}}"
SIM="${TT_SIM:-${RHEO_SIM:-iPhone 17 Pro}}"
CMD="${1:-sim}"
[[ $# -gt 0 ]] && shift
mkdir -p "$WORK/src"
rsync -a --delete --exclude '.build' --exclude '.swiftpm' --exclude '* 2.*' --exclude '* 2' "$ROOT/LabKit/" "$WORK/src/LabKit/"
rsync -a --delete --exclude 'ToothpasteToy.xcodeproj' --exclude 'Rheo.xcodeproj' --exclude '* 2.*' --exclude '* 2' \
  --exclude 'Documentation' "$APP/" "$WORK/src/ToothpasteToy/"
cd "$WORK/src/ToothpasteToy"
xcodegen generate --quiet
SIMDEST="platform=iOS Simulator,name=$SIM"
case "$CMD" in
  sim)
    xcodebuild -project ToothpasteToy.xcodeproj -scheme ToothpasteToy -configuration Debug \
      -destination "$SIMDEST" -derivedDataPath "$WORK/dd" build "$@" ;;
  device)
    xcodebuild -project ToothpasteToy.xcodeproj -scheme ToothpasteToy -configuration Release \
      -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath "$WORK/dd" build "$@" ;;
  test|build-for-testing|test-without-building)
    xcodebuild -project ToothpasteToy.xcodeproj -scheme ToothpasteToy -configuration Debug \
      -destination "$SIMDEST" -derivedDataPath "$WORK/dd" "$CMD" "$@" ;;
  *)
    echo "usage: Tools/build.sh sim|device|test|build-for-testing|test-without-building [xcodebuild args…]" >&2
    exit 2 ;;
esac
