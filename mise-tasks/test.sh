#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091,SC2154
#MISE description="Run tests using provided scheme and platform with derived data under the repo-local build directory."
#USAGE flag "--scheme <scheme>" {
#USAGE   help "Xcode scheme name. Defaults to \"{WorkspaceName}-Workspace\" derived from the workspace file name."
#USAGE }
#USAGE complete "scheme" run="mise run --output quiet list_build_schemes"
#USAGE flag "--platform <platform>" {
#USAGE   help "Platform. iOS tests use IOS_SIMULATOR_NAME environment variable."
#USAGE   required #true
#USAGE   choices "macOS" "iOS"
#USAGE }

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

workspace_path="$(get_workspace_path)"
scheme="${usage_scheme:-$(get_workspace_scheme)}"
derived_data_path="$(get_derived_data_path test "${usage_platform}" "${scheme}")"
result_bundle_path="$(get_result_bundle_path test "${usage_platform}" "${scheme}")"
log_path="$(get_log_path test "${usage_platform}" "${scheme}")"

require_workspace
require_build_scheme "${scheme}"
destination="$(get_test_destination "${usage_platform}")"

mkdir -p "${derived_data_path}" "$(dirname "${result_bundle_path}")" "$(dirname "${log_path}")"
rm -rf "${result_bundle_path}"
rm -rf "${log_path}"

printf 'derived_data_path: "%s"\n' "${derived_data_path}"
printf 'result_bundle_path: "%s"\n' "${result_bundle_path}"
printf 'log_path: "%s"\n' "${log_path}"

set +e

NSUnbufferedIO=YES \
  mise x -- tuist xcodebuild test \
    -workspace "$workspace_path" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$derived_data_path" \
    -resultBundlePath "$result_bundle_path" \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 \
| tee "$log_path" \
| mise x -- xcsift \
    --format toon \
    --xcbeautify

pipeline_status=("${PIPESTATUS[@]}")
set -e
xcodebuild_status="${pipeline_status[0]:-1}"
tee_status="${pipeline_status[1]:-1}"
xcsift_status="${pipeline_status[2]:-1}"
status=0

printf 'command_status:\n'
printf '  xcodebuild: %s\n' "${xcodebuild_status}"
printf '  tee: %s\n' "${tee_status}"
printf '  xcsift: %s\n' "${xcsift_status}"

if (( xcodebuild_status != 0 )); then
  status="${xcodebuild_status}"
elif (( xcsift_status != 0 )); then
  status="${xcsift_status}"
elif (( tee_status != 0 )); then
  status="${tee_status}"
elif xcresult_tests_failed "${result_bundle_path}"; then
  status=65
elif xcresult_build_failed "${result_bundle_path}"; then
  status=65
fi

if (( status != 0 )); then
  print_xcodebuild_failure_diagnostics \
    test \
    "${result_bundle_path}" \
    "${log_path}"
fi

exit "$status"
