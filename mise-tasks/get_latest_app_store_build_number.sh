#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091,SC2154
#MISE description="Gets the latest App Store Connect build or build upload number for the selected platform."
#USAGE flag "--platform <platform>" {
#USAGE   help "Platform."
#USAGE   required #true
#USAGE   choices "iOS" "macOS"
#USAGE }

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

bundle_id="$(get_app_bundle_id)"
marketing_version="$(get_marketing_version)"
app_id="$(app_store_connect_get_app_id "${bundle_id}")"

app_store_platform="$(app_store_connect_platform_name "${usage_platform}")"

latest_uploaded_build_number="$(
  app_store_connect_api GET "builds" \
    -G \
    --data-urlencode "filter[app]=${app_id}" \
    --data-urlencode "filter[preReleaseVersion.platform]=${app_store_platform}" \
    --data-urlencode "filter[preReleaseVersion.version]=${marketing_version}" \
    --data-urlencode "limit=200" \
    --data-urlencode "fields[builds]=uploadedDate,version" \
    | mise x -- jq -r '([.data[].attributes.version | tonumber?] | max // 0)'
)"

latest_build_upload_number="$(
  app_store_connect_api GET "apps/${app_id}/buildUploads" \
    -G \
    --data-urlencode "filter[cfBundleShortVersionString]=${marketing_version}" \
    --data-urlencode "filter[platform]=${app_store_platform}" \
    --data-urlencode "limit=200" \
    | mise x -- jq -r '([.data[].attributes.cfBundleVersion | tonumber?] | max // 0)'
)"

if (( latest_uploaded_build_number > latest_build_upload_number )); then
  latest_build_number="${latest_uploaded_build_number}"
else
  latest_build_number="${latest_build_upload_number}"
fi

printf '%s\n' "${latest_build_number}"
