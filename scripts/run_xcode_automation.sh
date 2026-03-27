#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT}/Roam.xcodeproj"
PBXPROJ_PATH="${PROJECT_PATH}/project.pbxproj"
SCHEME="Roam"
CONFIGURATION="Debug"
SIMULATOR_NAME="iPhone 16"
SIMULATOR_OS="latest"
MODE="simulator"
DEVICE_ID=""
KEEP_SIMULATOR_BOOTED="false"
MIN_FREE_MB=12000
MAC_DESTINATION_ID=""

ARTIFACTS_ROOT="${ROOT}/.artifacts/xcode"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACTS_ROOT}/${TIMESTAMP}"
DERIVED_DATA="${RUN_DIR}/DerivedData"
SPM_CACHE_DIR="${RUN_DIR}/SourcePackages"

usage() {
  cat <<'EOF'
Usage:
  scripts/run_xcode_automation.sh [options]

Options:
  --mode simulator|device|wireless|mac
                              Execution mode (default: simulator)
  --device-id <udid>           Required when --mode device
  --scheme <name>              Xcode scheme (default: Roam)
  --configuration <name>       Build configuration (default: Debug)
  --simulator <name>           Simulator device name (default: iPhone 16)
  --simulator-os <version>     Simulator OS version (default: latest)
  --mac-destination-id <id>    Optional My Mac destination id for mac mode
  --artifacts-dir <path>       Output root directory (default: .artifacts/xcode)
  --min-free-mb <mb>           Minimum free disk space required (default: 12000)
  --keep-booted                Keep simulator booted after run
  --help                       Show this help

Outputs:
  - Build/test logs and xcresult bundles under .artifacts/xcode/<timestamp>/
  - A summary file at .artifacts/xcode/<timestamp>/summary.txt
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --device-id)
      DEVICE_ID="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --simulator)
      SIMULATOR_NAME="$2"
      shift 2
      ;;
    --simulator-os)
      SIMULATOR_OS="$2"
      shift 2
      ;;
    --mac-destination-id)
      MAC_DESTINATION_ID="$2"
      shift 2
      ;;
    --artifacts-dir)
      ARTIFACTS_ROOT="$2"
      RUN_DIR="${ARTIFACTS_ROOT}/${TIMESTAMP}"
      DERIVED_DATA="${RUN_DIR}/DerivedData"
      SPM_CACHE_DIR="${RUN_DIR}/SourcePackages"
      shift 2
      ;;
    --min-free-mb)
      MIN_FREE_MB="$2"
      shift 2
      ;;
    --keep-booted)
      KEEP_SIMULATOR_BOOTED="true"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "${PROJECT_PATH}" ]]; then
  echo "Could not find project at ${PROJECT_PATH}" >&2
  exit 1
fi

if [[ ! -f "${PBXPROJ_PATH}" ]]; then
  echo "Could not find pbxproj at ${PBXPROJ_PATH}" >&2
  exit 1
fi

command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is required" >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "xcrun is required" >&2; exit 1; }

SPACE_CHECK_PATH="${ARTIFACTS_ROOT}"
if [[ ! -e "${SPACE_CHECK_PATH}" ]]; then
  SPACE_CHECK_PATH="$(dirname "${SPACE_CHECK_PATH}")"
fi

FREE_MB="$(df -Pm "${SPACE_CHECK_PATH}" | awk 'NR==2 { print $4 }')"
if [[ -z "${FREE_MB}" ]]; then
  echo "Could not determine free disk space" >&2
  exit 1
fi

if (( FREE_MB < MIN_FREE_MB )); then
  cat >&2 <<EOF
Not enough disk space for Xcode package resolution/build.
Path: ${SPACE_CHECK_PATH}
Free: ${FREE_MB} MB, required: ${MIN_FREE_MB} MB minimum.
Free up space, then rerun this script.
EOF
  exit 2
fi

mkdir -p "${RUN_DIR}"

HAS_TEST_TARGETS="false"
if grep -qE 'com.apple.product-type.bundle.(unit-test|ui-testing)' "${PBXPROJ_PATH}"; then
  HAS_TEST_TARGETS="true"
fi

APP_INFO_PLIST="${ROOT}/Roam/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_INFO_PLIST}" 2>/dev/null || true)"
if [[ -z "${BUNDLE_ID}" ]]; then
  BUNDLE_ID="roam.app"
fi

echo "mode=${MODE}" >"${RUN_DIR}/summary.txt"
echo "scheme=${SCHEME}" >>"${RUN_DIR}/summary.txt"
echo "configuration=${CONFIGURATION}" >>"${RUN_DIR}/summary.txt"
echo "bundle_id=${BUNDLE_ID}" >>"${RUN_DIR}/summary.txt"
echo "has_test_targets=${HAS_TEST_TARGETS}" >>"${RUN_DIR}/summary.txt"
echo "free_mb=${FREE_MB}" >>"${RUN_DIR}/summary.txt"

build_common_args=(
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -derivedDataPath "${DERIVED_DATA}"
  -clonedSourcePackagesDirPath "${SPM_CACHE_DIR}"
)

run_simulator() {
  local sim_udid
  sim_udid="$(xcrun simctl list devices available | awk -v n="${SIMULATOR_NAME}" 'index($0, n) { if (match($0, /\(([0-9A-F-]+)\)/, m)) { print m[1]; exit } }')"
  if [[ -z "${sim_udid}" ]]; then
    echo "Could not find available simulator named '${SIMULATOR_NAME}'." >&2
    echo "Tip: list devices with: xcrun simctl list devices available" >&2
    exit 3
  fi

  echo "simulator_udid=${sim_udid}" >>"${RUN_DIR}/summary.txt"

  xcodebuild "${build_common_args[@]}" \
    -destination "platform=iOS Simulator,id=${sim_udid},OS=${SIMULATOR_OS}" \
    -resultBundlePath "${RUN_DIR}/build.xcresult" \
    build | tee "${RUN_DIR}/build.log"

  local app_path
  app_path="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphonesimulator/Roam.app"
  if [[ ! -d "${app_path}" ]]; then
    echo "Build succeeded but app bundle not found at ${app_path}" >&2
    exit 4
  fi

  xcrun simctl boot "${sim_udid}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${sim_udid}" -b

  xcrun simctl install "${sim_udid}" "${app_path}" | tee "${RUN_DIR}/install.log"
  xcrun simctl terminate "${sim_udid}" "${BUNDLE_ID}" >/dev/null 2>&1 || true
  xcrun simctl launch "${sim_udid}" "${BUNDLE_ID}" | tee "${RUN_DIR}/launch.log"

  sleep 8
  xcrun simctl spawn "${sim_udid}" log show --style compact --last 3m --predicate "process == \"Roam\"" >"${RUN_DIR}/runtime.log" || true

  if [[ "${HAS_TEST_TARGETS}" == "true" ]]; then
    xcodebuild "${build_common_args[@]}" \
      -destination "platform=iOS Simulator,id=${sim_udid},OS=${SIMULATOR_OS}" \
      -resultBundlePath "${RUN_DIR}/test.xcresult" \
      test | tee "${RUN_DIR}/test.log"
    echo "tests_executed=true" >>"${RUN_DIR}/summary.txt"
  else
    echo "tests_executed=false" >>"${RUN_DIR}/summary.txt"
    echo "test_note=No XCTest/XCUITest targets found. Smoke build+install+launch completed." >>"${RUN_DIR}/summary.txt"
  fi

  if [[ "${KEEP_SIMULATOR_BOOTED}" != "true" ]]; then
    xcrun simctl shutdown "${sim_udid}" >/dev/null 2>&1 || true
  fi
}

run_device() {
  if [[ -z "${DEVICE_ID}" ]]; then
    echo "--device-id is required in device mode" >&2
    echo "Find IDs with: xcrun xctrace list devices" >&2
    exit 5
  fi

  if ! xcrun xctrace list devices | grep -q "${DEVICE_ID}"; then
    cat >&2 <<EOF
Device '${DEVICE_ID}' is not currently visible to Xcode.
Check that the iPhone is connected, unlocked, trusted, and has Developer Mode enabled,
then run: xcrun xctrace list devices
EOF
    exit 7
  fi

  echo "device_id=${DEVICE_ID}" >>"${RUN_DIR}/summary.txt"

  xcodebuild "${build_common_args[@]}" \
    -destination "id=${DEVICE_ID}" \
    -resultBundlePath "${RUN_DIR}/build-device.xcresult" \
    build | tee "${RUN_DIR}/build-device.log"

  if [[ "${HAS_TEST_TARGETS}" == "true" ]]; then
    xcodebuild "${build_common_args[@]}" \
      -destination "id=${DEVICE_ID}" \
      -resultBundlePath "${RUN_DIR}/test-device.xcresult" \
      test | tee "${RUN_DIR}/test-device.log"
    echo "tests_executed=true" >>"${RUN_DIR}/summary.txt"
  else
    echo "tests_executed=false" >>"${RUN_DIR}/summary.txt"
    echo "test_note=No XCTest/XCUITest targets found. Device build-only completed." >>"${RUN_DIR}/summary.txt"
  fi
}

run_wireless() {
  if [[ -n "${DEVICE_ID}" ]]; then
    run_device
    return
  fi

  local discovered_device_id
  discovered_device_id="$(xcrun xctrace list devices | sed -n '1,80p' | awk '/iPhone/ && $0 !~ /Simulator/ { if (match($0, /\(([0-9A-F-]+)\)$/, m)) { print m[1]; exit } }')"

  if [[ -z "${discovered_device_id}" ]]; then
    cat >&2 <<EOF
No wireless iPhone is currently visible to Xcode.
If the device was previously paired for wireless debugging, make sure the phone and Mac
are on the same Wi-Fi network, the phone is unlocked, and Xcode is open.
Then run: xcrun xctrace list devices
EOF
    exit 8
  fi

  DEVICE_ID="${discovered_device_id}"
  run_device
}

run_mac() {
  local destination
  if [[ -n "${MAC_DESTINATION_ID}" ]]; then
    destination="id=${MAC_DESTINATION_ID}"
  else
    destination="platform=macOS,name=My Mac"
  fi

  echo "mac_destination=${destination}" >>"${RUN_DIR}/summary.txt"

  xcodebuild "${build_common_args[@]}" \
    -destination "${destination}" \
    -resultBundlePath "${RUN_DIR}/build-mac.xcresult" \
    build | tee "${RUN_DIR}/build-mac.log"

  local app_path
  app_path="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/Roam.app"
  if [[ ! -d "${app_path}" ]]; then
    echo "Build succeeded but mac app bundle not found at ${app_path}" >&2
    exit 9
  fi

  open -n "${app_path}"
  sleep 8
  log show --style compact --last 3m --predicate 'process == "Roam"' >"${RUN_DIR}/runtime-mac.log" || true

  if [[ "${HAS_TEST_TARGETS}" == "true" ]]; then
    xcodebuild "${build_common_args[@]}" \
      -destination "${destination}" \
      -resultBundlePath "${RUN_DIR}/test-mac.xcresult" \
      test | tee "${RUN_DIR}/test-mac.log"
    echo "tests_executed=true" >>"${RUN_DIR}/summary.txt"
  else
    echo "tests_executed=false" >>"${RUN_DIR}/summary.txt"
    echo "test_note=No XCTest/XCUITest targets found. Mac designed-for-iPhone smoke build+launch completed." >>"${RUN_DIR}/summary.txt"
  fi
}

case "${MODE}" in
  simulator)
    run_simulator
    ;;
  device)
    run_device
    ;;
  wireless)
    run_wireless
    ;;
  mac)
    run_mac
    ;;
  *)
    echo "Invalid mode: ${MODE}. Use simulator, device, wireless, or mac." >&2
    exit 6
    ;;
esac

cat <<EOF
Automation run complete.
Artifacts: ${RUN_DIR}
Summary:   ${RUN_DIR}/summary.txt
EOF
