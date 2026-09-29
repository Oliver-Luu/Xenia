#!/bin/bash
#
# Location-based testing for Xenia's arrival-reminder notifications.
#
# Three layers, cheapest first:
#
#   1. logic       the pure decision math — which places are watched, radius
#                  clamping, visit matching, how long the delay should be
#   2. events      real CoreLocation delegate events, the real
#                  UNUserNotificationCenter, the real cooldown, the real store:
#                  arriving, leaving, drive-bys, jitter, cooldowns, visits
#   3. fences      what the app actually registers with CoreLocation
#
# Layers 2 and 3 need permissions a simulator only takes once: `simctl privacy`
# covers location, and notifications have no simctl equivalent at all, so the
# NotificationPermissionBootstrap UI test taps the alert. This script does both.
#
# It runs on its own dedicated simulator, which it erases first. That is not
# tidiness — layer 3 registers real geofences, and the simulator's CoreLocation
# stops accepting registrations after a couple of register/unregister cycles.
# Once wedged it reports an empty `monitoredRegions` while the system still
# holds the old ones, so nothing can release them and the layer-3 tests fail on
# a simulator that looks clean. A fresh device each run is the only fix. Your own
# simulators are never touched.
#
# Usage:
#   scripts/test-location-notifications.sh              # layers 1–3
#   scripts/test-location-notifications.sh --live       # plus a real geofence crossing
#   scripts/test-location-notifications.sh --keep       # don't erase first (faster, layer 3 may fail)
#
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

BUNDLE_ID="OliverLuu.Xenia"
SIM_NAME="Xenia Location Tests"
RUN_LIVE=0
ERASE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --live) RUN_LIVE=1; shift ;;
        --keep) ERASE=0; shift ;;
        -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

FAILED=0
step() { printf '\n\033[1m=== %s ===\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
bad()  { printf '\033[31m    FAILED: %s\033[0m\n' "$*"; FAILED=1; }
filter() { grep -E "✔ Test run|✘|error:|BUILD (SUCCEEDED|FAILED)|^Test Case.*(passed|failed)"; }

# ---------------------------------------------------------------- simulator

step "Dedicated simulator"
DEVICE=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for runtime, devices in json.load(sys.stdin)['devices'].items():
    for d in devices:
        if d['name'] == '''$SIM_NAME''':
            print(d['udid']); raise SystemExit
")

if [[ -z "$DEVICE" ]]; then
    # Take the device type and runtime from a simulator that already exists and
    # is available, so the pair is guaranteed to be a legal combination.
    read -r TYPE RUNTIME < <(xcrun simctl list devices available -j | python3 -c "
import json,sys
for runtime, devices in sorted(json.load(sys.stdin)['devices'].items(), reverse=True):
    if 'iOS' not in runtime: continue
    for d in devices:
        if d['name'].startswith('iPhone'):
            print(d['deviceTypeIdentifier'], runtime); raise SystemExit
")
    if [[ -z "${TYPE:-}" ]]; then
        echo "no available iPhone simulator to model the test device on" >&2
        exit 1
    fi
    DEVICE=$(xcrun simctl create "$SIM_NAME" "$TYPE" "$RUNTIME")
    note "created \"$SIM_NAME\" ($DEVICE)"
else
    note "reusing \"$SIM_NAME\" ($DEVICE)"
fi

# Anything but a udid here means creation failed; carrying on would produce a
# confusing wall of xcodebuild destination errors.
if ! [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
    echo "could not obtain a simulator: $DEVICE" >&2
    exit 1
fi

DEST="platform=iOS Simulator,id=$DEVICE"

if [[ "$ERASE" -eq 1 ]]; then
    xcrun simctl shutdown "$DEVICE" 2>/dev/null
    xcrun simctl erase "$DEVICE" && note "erased — CoreLocation starts clean"
fi
xcrun simctl boot "$DEVICE" 2>/dev/null
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1
# Region monitoring needs the device to have a position at all.
xcrun simctl location "$DEVICE" set 37.33182,-122.03118
note "booted and located"

# ---------------------------------------------------------------- build

step "Build for testing"
xcodebuild build-for-testing -project Xenia.xcodeproj -scheme Xenia \
    -destination "$DEST" 2>&1 | filter || true

# ---------------------------------------------------------------- permissions

step "Permissions"
xcrun simctl privacy "$DEVICE" grant location-always "$BUNDLE_ID" \
    && note "location: Always (via simctl)" \
    || bad "could not grant location"

# Notifications have no simctl equivalent — the alert has to be tapped.
xcodebuild test-without-building -project Xenia.xcodeproj -scheme Xenia \
    -destination "$DEST" -parallel-testing-enabled NO \
    -only-testing:XeniaUITests/NotificationPermissionBootstrap 2>&1 | filter \
    || bad "notification permission bootstrap"

# ---------------------------------------------------------------- layers

step "Layers 1 & 2 — decision logic, location events, currency and units"
# Everything except the geofence-registration suite, which is held back for
# layer 3 so it stays the only thing that registers real regions (see the note
# at the top about wedging CoreLocation). Listing it as a skip rather than
# naming every other suite means new suites are picked up automatically.
xcodebuild test-without-building -project Xenia.xcodeproj -scheme Xenia \
    -destination "$DEST" -parallel-testing-enabled NO \
    -only-testing:XeniaTests \
    -skip-testing:XeniaTests/ArrivalRegionMonitoringTests 2>&1 | filter \
    || bad "logic / event layers"

step "Layer 3 — geofences actually registered with CoreLocation"
xcodebuild test-without-building -project Xenia.xcodeproj -scheme Xenia \
    -destination "$DEST" -parallel-testing-enabled NO \
    -only-testing:XeniaTests/ArrivalRegionMonitoringTests 2>&1 | filter \
    || bad "geofence registration layer"

# ---------------------------------------------------------------- live drive

if [[ "$RUN_LIVE" -eq 1 ]]; then
    LAT=37.33182
    LON=-122.03118
    FAR_LAT=37.40000    # ~7.5 km north, well outside any allowed radius

    step "Live — a real geofence crossing"
    # The gate has to be readable by the app hosting the unit tests, and
    # xcodebuild's TEST_RUNNER_ environment prefix only reaches a UI test runner.
    xcrun simctl spawn "$DEVICE" defaults write "$BUNDLE_ID" xeniaLiveGeofence -bool YES
    note "seeding a place at $LAT,$LON and registering its fence"
    xcodebuild test-without-building -project Xenia.xcodeproj -scheme Xenia \
        -destination "$DEST" -parallel-testing-enabled NO \
        -only-testing:"XeniaTests/ArrivalLiveGeofenceTests/seedAPlaceAndRegisterItsGeofence()" 2>&1 \
        | filter || bad "live seed"

    note "starting outside the fence"
    xcrun simctl location "$DEVICE" set "$FAR_LAT,$LON"
    xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1
    sleep 10

    note "crossing in"
    xcrun simctl location "$DEVICE" set "$LAT,$LON"

    # The seeded category asks for 1 minute, floored at the 45 s minimum dwell,
    # so the reminder is due about a minute after the crossing.
    note "waiting 100s for the reminder to fire"
    sleep 100
    mkdir -p build
    xcrun simctl io "$DEVICE" screenshot build/live-geofence.png >/dev/null 2>&1 \
        && note "screenshot: build/live-geofence.png"

    xcodebuild test-without-building -project Xenia.xcodeproj -scheme Xenia \
        -destination "$DEST" -parallel-testing-enabled NO \
        -only-testing:"XeniaTests/ArrivalLiveGeofenceTests/theReminderArrivedAfterTheRealCrossing()" \
        -only-testing:"XeniaTests/ArrivalLiveGeofenceTests/removeTheSeededPlace()" 2>&1 \
        | filter || bad "live verification"

    xcrun simctl location "$DEVICE" clear 2>/dev/null
    xcrun simctl spawn "$DEVICE" defaults delete "$BUNDLE_ID" xeniaLiveGeofence 2>/dev/null
fi

step "Result"
if [[ "$FAILED" -eq 0 ]]; then
    printf '\033[32m    all layers passed\033[0m\n'
else
    printf '\033[31m    some layers failed — see above\033[0m\n'
fi
exit "$FAILED"
