#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091,SC2016,SC2154
#MISE description="Submits app build to TestFlight beta groups resolved from TESTFLIGHT_GROUPS."
#USAGE flag "--platform <platform>" {
#USAGE   help "Platform."
#USAGE   required #true
#USAGE   choices "iOS" "macOS"
#USAGE }
#USAGE flag "--version <version>" {
#USAGE   help "Marketing version. Defaults to current marketing version set in workspace."
#USAGE }
#USAGE flag "--build <build>" {
#USAGE   help "Build number. Defaults to current build number set in workspace."
#USAGE }

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

app_store_connect_require_env

root_dir="$(get_root_dir)"
whattotest_file_path="${root_dir}/TestFlight/WhatToTest.en-US.txt"
platform="${usage_platform}"

echo "Platform: ${platform}"

version="${usage_version:-$(get_marketing_version)}"
echo "Marketing version: ${version}"

build="${usage_build:-$(get_build_number)}"
echo "Build number: ${build}"

groups=()
while IFS= read -r group; do
  [[ -n "${group}" ]] && groups+=("${group}")
done < <(get_testflight_groups "${platform}")

groups_string=$(printf '%s, ' "${groups[@]}")
groups_string=${groups_string%, }
echo "TestFlight groups: $groups_string"

bundle_id="$(get_app_bundle_id)"
echo "Bundle id: ${bundle_id}"

app_id="$(app_store_connect_lookup_app_id "${bundle_id}")"

if [[ -z "${app_id}" ]]; then
  echo "Error: App not found in App Store Connect for bundle identifier ${bundle_id}" >&2
  exit 1
fi

echo "App id: ${app_id}"

app_store_platform="$(app_store_connect_platform_name "${platform}")"

poll_attempt=0
poll_retry_sleep=30
max_poll_attempts=30
build_json=""
build_id=""
processing_state=""

while (( poll_attempt < max_poll_attempts )); do
  poll_attempt=$((poll_attempt + 1))
  build_json="$(app_store_connect_lookup_build "${app_id}" "${app_store_platform}" "${version}" "${build}")"
  build_id="$(printf '%s' "${build_json}" | mise x -- jq -r '.id // empty')"

  if [[ -n "${build_id}" ]]; then
    processing_state="$(printf '%s' "${build_json}" | mise x -- jq -r '.attributes.processingState // empty')"
    case "${processing_state}" in
      VALID)
        break
        ;;
      FAILED|INVALID)
        echo "Error: ${platform} build ${version} (${build}) entered processing state ${processing_state}." >&2
        exit 1
        ;;
      *)
        echo "${platform} build ${version} (${build}) processing state: ${processing_state}"
    esac
  else
    echo "${platform} build ${version} (${build}) was not found in App Store Connect."
  fi

  if (( poll_attempt < max_poll_attempts )); then
    echo "Retrying in ${poll_retry_sleep} seconds..."
    sleep "$poll_retry_sleep"
  fi
done

if [[ -z "${build_id}" ]]; then
  echo "Error: ${platform} build ${version} (${build}) was not found in App Store Connect." >&2
  exit 1
fi

if [[ "${processing_state}" != "VALID" ]]; then
  echo "Error: Timed out waiting for ${platform} build ${version} (${build}) to become available." >&2
  exit 1
fi

if [[ -f "${whattotest_file_path}" ]]; then
  echo "Using What To Test file: ${whattotest_file_path}"
  whattotest_content="$(cat "${whattotest_file_path}")"

  beta_build_localizations_json="$(
    app_store_connect_get_all_pages "builds/${build_id}/betaBuildLocalizations" \
      -G \
      --data-urlencode "limit=200" \
      --data-urlencode "fields[betaBuildLocalizations]=locale,whatsNew"
  )"
  matching_beta_build_localizations_json="$(
    printf '%s' "${beta_build_localizations_json}" \
      | mise x -- jq -c '[.data[] | select(.attributes.locale == "en-US")]'
  )"
  matching_beta_build_localization_count="$(printf '%s' "${matching_beta_build_localizations_json}" | mise x -- jq -r 'length')"

  if (( matching_beta_build_localization_count > 1 )); then
    echo "Error: Multiple beta build localizations found for locale en-US." >&2
    exit 1
  fi

  if (( matching_beta_build_localization_count == 1 )); then
    beta_build_localization_id="$(printf '%s' "${matching_beta_build_localizations_json}" | mise x -- jq -r '.[0].id // empty')"
    current_whattotest_content="$(printf '%s' "${matching_beta_build_localizations_json}" | mise x -- jq -r '.[0].attributes.whatsNew // empty')"

    if [[ "${current_whattotest_content}" == "${whattotest_content}" ]]; then
      echo "What To Test for locale en-US is already up to date."
    else
      echo "Updating What To Test for locale en-US..."
      app_store_connect_api PATCH "betaBuildLocalizations/${beta_build_localization_id}" \
        --data "$(
          mise x -- jq -cn \
            --arg beta_build_localization_id "${beta_build_localization_id}" \
            --arg whattotest_content "${whattotest_content}" \
            '{data:{id:$beta_build_localization_id,type:"betaBuildLocalizations",attributes:{whatsNew:$whattotest_content}}}'
        )" \
        >/dev/null
    fi
  else
    echo "Creating What To Test localization for locale en-US..."
    app_store_connect_api POST "betaBuildLocalizations" \
      --data "$(
        mise x -- jq -cn \
          --arg build_id "${build_id}" \
          --arg whattotest_content "${whattotest_content}" \
          '{data:{type:"betaBuildLocalizations",attributes:{locale:"en-US",whatsNew:$whattotest_content},relationships:{build:{data:{id:$build_id,type:"builds"}}}}}'
      )" \
      >/dev/null
  fi
else
  echo "What To Test file not found, skipping localized TestFlight notes: ${whattotest_file_path}"
fi

beta_groups_json="$(
  app_store_connect_get_all_pages "apps/${app_id}/betaGroups" \
    -G \
    --data-urlencode "limit=200" \
    --data-urlencode "fields[betaGroups]=hasAccessToAllBuilds,isInternalGroup,name"
)"

available_group_names=()
while IFS= read -r group_name; do
  [[ -n "${group_name}" ]] && available_group_names+=("${group_name}")
done < <(printf '%s' "${beta_groups_json}" | mise x -- jq -r '.data[].attributes.name // empty')

group_ids_to_submit=()
group_names_to_submit=()
requested_external_group_names=()
for group_name in "${groups[@]}"; do
  matching_groups_json="$(
    printf '%s' "${beta_groups_json}" \
      | mise x -- jq -c --arg group_name "${group_name}" '[.data[] | select(.attributes.name == $group_name)]'
  )"
  matching_group_count="$(printf '%s' "${matching_groups_json}" | mise x -- jq -r 'length')"

  if (( matching_group_count == 0 )); then
    echo "Error: TestFlight group not found: ${group_name}" >&2
    if (( ${#available_group_names[@]} > 0 )); then
      echo "Available groups:" >&2
      printf '%s\n' "${available_group_names[@]}" >&2
    fi
    exit 1
  fi

  if (( matching_group_count > 1 )); then
    echo "Error: Multiple TestFlight groups found with name: ${group_name}" >&2
    exit 1
  fi

  group_id="$(printf '%s' "${matching_groups_json}" | mise x -- jq -r '.[0].id // empty')"
  group_access_all_builds="$(printf '%s' "${matching_groups_json}" | mise x -- jq -r '.[0].attributes.hasAccessToAllBuilds // false')"
  group_is_internal="$(printf '%s' "${matching_groups_json}" | mise x -- jq -r '.[0].attributes.isInternalGroup // false')"

  if [[ "${group_is_internal}" == "true" ]]; then
    group_kind="internal"
  else
    group_kind="external"
    requested_external_group_names+=("${group_name}")
  fi

  if [[ "${group_access_all_builds}" == "true" ]]; then
    echo "Skipping group \"${group_name}\" (${group_kind}): it already has access to all builds."
    continue
  fi

  group_build_ids="$(
    app_store_connect_get_all_pages "betaGroups/${group_id}/relationships/builds" \
      -G \
      --data-urlencode "limit=200" \
      | mise x -- jq -r '.data[].id // empty'
  )"

  if printf '%s\n' "${group_build_ids}" | grep -Fxq "${build_id}"; then
    echo "Skipping group \"${group_name}\": ${platform} build ${version} (${build}) is already assigned."
    continue
  fi

  echo "Will assign ${platform} build ${version} (${build}) to group \"${group_name}\" (${group_kind})."
  group_ids_to_submit+=("${group_id}")
  group_names_to_submit+=("${group_name}")
done

if (( ${#group_ids_to_submit[@]} == 0 )); then
  echo "No TestFlight group updates were necessary."
fi

for group_index in "${!group_ids_to_submit[@]}"; do
  group_id="${group_ids_to_submit[$group_index]}"
  group_name="${group_names_to_submit[$group_index]}"
  group_is_internal="$(printf '%s' "${beta_groups_json}" | mise x -- jq -r --arg group_id "${group_id}" '.data[] | select(.id == $group_id) | .attributes.isInternalGroup // false')"

  if [[ "${group_is_internal}" == "true" ]]; then
    group_kind="internal"
  else
    group_kind="external"
  fi

  echo "Assigning ${platform} build ${version} (${build}) to group \"${group_name}\" (${group_kind})..."

  app_store_connect_api POST "betaGroups/${group_id}/relationships/builds" \
    --data "$(
      mise x -- jq -cn \
        --arg build_id "${build_id}" \
        '{data:[{id:$build_id,type:"builds"}]}'
    )" \
    >/dev/null
done

if (( ${#requested_external_group_names[@]} == 0 )); then
  echo "${platform} build ${version} (${build}) submitted to the requested TestFlight groups."
  exit 0
fi

beta_app_review_submission_json="$(
  app_store_connect_api GET "betaAppReviewSubmissions" \
    -G \
    --data-urlencode "filter[build]=${build_id}" \
    --data-urlencode "limit=1" \
    --data-urlencode "fields[betaAppReviewSubmissions]=betaReviewState,submittedDate"
)"
beta_app_review_submission_id="$(printf '%s' "${beta_app_review_submission_json}" | mise x -- jq -r '.data[0].id // empty')"

if [[ -n "${beta_app_review_submission_id}" ]]; then
  beta_review_state="$(printf '%s' "${beta_app_review_submission_json}" | mise x -- jq -r '.data[0].attributes.betaReviewState // empty')"
  echo "External TestFlight review submission already exists for ${platform} build ${version} (${build}) with state: ${beta_review_state}"
  echo "${platform} build ${version} (${build}) submitted to the requested TestFlight groups."
  exit 0
fi

echo "Submitting ${platform} build ${version} (${build}) for external TestFlight review..."

app_store_connect_api POST "betaAppReviewSubmissions" \
  --data "$(
    mise x -- jq -cn \
      --arg build_id "${build_id}" \
      '{data:{type:"betaAppReviewSubmissions",relationships:{build:{data:{id:$build_id,type:"builds"}}}}}'
  )" \
  >/dev/null

echo "External TestFlight review submission created for ${platform} build ${version} (${build})."
echo "${platform} build ${version} (${build}) submitted to the requested TestFlight groups."
