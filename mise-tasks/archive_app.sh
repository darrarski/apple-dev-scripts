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
archive_path="$(get_archive_path "${usage_platform}" "${scheme}")"
derived_data_path="$(get_derived_data_path archive "${usage_platform}" "${scheme}")"

require_workspace
require_build_scheme "${scheme}"
app_store_connect_require_env

destination="$(get_build_destination "${usage_platform}")"

mkdir -p "$(dirname "${archive_path}")" "${derived_data_path}"
rm -rf "${archive_path}" "${derived_data_path}"
mkdir -p "$(dirname "${archive_path}")" "${derived_data_path}"

mise x -- tuist xcodebuild archive \
  -workspace "${workspace_path}" \
  -scheme "${scheme}" \
  -configuration "Release" \
  -destination "${destination}" \
  -archivePath "${archive_path}" \
  -derivedDataPath "${derived_data_path}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_API_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"
