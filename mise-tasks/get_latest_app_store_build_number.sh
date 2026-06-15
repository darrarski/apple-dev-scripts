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
app_id="$(app_store_connect_get_app_id "${bundle_id}")"
platform="${usage_platform}"
app_store_platform="$(app_store_connect_platform_name "${platform}")"

latest_uploaded_build_number="$(
  app_store_connect_api GET "builds" \
    -G \
    --data-urlencode "filter[app]=${app_id}" \
    --data-urlencode "filter[preReleaseVersion.platform]=${app_store_platform}" \
    --data-urlencode "limit=1" \
    --data-urlencode "sort=-uploadedDate" \
    --data-urlencode "fields[builds]=uploadedDate,version" \
    | mise x -- jq -r '(.data[0].attributes.version // "0") | tonumber? // 0'
)"

latest_build_upload_number="$(
  app_store_connect_api GET "apps/${app_id}/buildUploads" \
    -G \
    --data-urlencode "filter[platform]=${app_store_platform}" \
    --data-urlencode "limit=1" \
    --data-urlencode "sort=-uploadedDate" \
    --data-urlencode "fields[buildUploads]=cfBundleVersion,uploadedDate" \
    | mise x -- jq -r '(.data[0].attributes.cfBundleVersion // "0") | tonumber? // 0'
)"

if (( latest_uploaded_build_number > latest_build_upload_number )); then
  latest_build_number="${latest_uploaded_build_number}"
else
  latest_build_number="${latest_build_upload_number}"
fi

printf '%s\n' "${latest_build_number}"
