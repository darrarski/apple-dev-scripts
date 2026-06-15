#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091,SC2154
#MISE description="Archives the app for the selected platform under the repo-local build directory."
#USAGE flag "--scheme <scheme>" {
#USAGE   help "Xcode scheme name. Defaults to XCODE_APP_SCHEME."
#USAGE }
#USAGE complete "scheme" run="mise run --output quiet list_build_schemes"
#USAGE flag "--platform <platform>" {
#USAGE   help "Platform."
#USAGE   required #true
#USAGE   choices "iOS" "macOS"
#USAGE }

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

scheme="${usage_scheme:-$(get_app_scheme)}"
workspace_path="$(get_workspace_path)"
platform="${usage_platform}"
archive_path="$(get_archive_path "${platform}" "${scheme}")"
derived_data_path="$(get_derived_data_path archive "${platform}" "${scheme}")"
result_bundle_path="$(get_result_bundle_path archive "${platform}" "${scheme}")"
log_path="$(get_log_path archive "${platform}" "${scheme}")"

require_workspace
require_build_scheme "${scheme}"
app_store_connect_require_env

destination="$(get_build_destination "${platform}")"

mkdir -p "$(dirname "${archive_path}")" "${derived_data_path}" "$(dirname "${result_bundle_path}")" "$(dirname "${log_path}")"
rm -rf "${archive_path}" "${result_bundle_path}" "${log_path}"
mkdir -p "$(dirname "${archive_path}")" "${derived_data_path}"

printf 'archive_path: %s\n' "${archive_path}"
printf 'derived_data_path: %s\n' "${derived_data_path}"
printf 'result_bundle_path: %s\n' "${result_bundle_path}"
printf 'log_path: %s\n' "${log_path}"

set +e

mise x -- tuist xcodebuild archive \
  -workspace "${workspace_path}" \
  -scheme "${scheme}" \
  -configuration "Release" \
  -destination "${destination}" \
  -archivePath "${archive_path}" \
  -derivedDataPath "${derived_data_path}" \
  -resultBundlePath "${result_bundle_path}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_API_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID" \
  >"${log_path}" \
  2>&1

xcodebuild_status="$?"
set -e
status=0

printf 'command_status:\n'
printf '  xcodebuild: %s\n' "${xcodebuild_status}"

if (( xcodebuild_status != 0 )); then
  status="${xcodebuild_status}"
elif xcresult_build_failed "${result_bundle_path}"; then
  status=65
fi

print_xcodebuild_diagnostics \
  archive \
  "${result_bundle_path}" \
  "${log_path}"

exit "$status"
