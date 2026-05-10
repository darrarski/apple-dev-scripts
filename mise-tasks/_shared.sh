#!/usr/bin/env bash

get_root_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

sanitize_path_component() {
  printf '%s' "$1" | tr -cs '[:alnum:]._-' '-'
}

sanitize_variable_name_component() {
  printf '%s' "$1" | od -An -tx1 -v | tr -d '[:space:]'
}

require_env_var() {
  local variable_name="$1"
  local variable_value="${!variable_name:-}"

  if [[ -z "${variable_value}" ]]; then
    echo "Error: ${variable_name} is not set." >&2
    exit 1
  fi

  printf '%s\n' "${variable_value}"
}

get_build_root_dir() {
  printf '%s/build\n' "$(get_root_dir)"
}

get_derived_data_path() {
  local base_dir_path
  local dir_path
  local component
  local sanitized

  base_dir_path="$(get_build_root_dir)/DerivedData"
  mkdir -p "${base_dir_path}"

  for component in "$@"; do
    [[ -n "${component}" ]] || continue

    sanitized="$(sanitize_path_component "${component}")"
    [[ -n "${sanitized}" ]] || continue

    if [[ -z "${dir_path}" ]]; then
      dir_path="${sanitized}"
    else
      dir_path+="-${sanitized}"
    fi
  done

  printf '%s/%s\n' "${base_dir_path}" "${dir_path}"
}

get_result_bundle_path() {
  local results_dir
  local filename
  local component
  local sanitized

  results_dir="$(get_build_root_dir)/Results"
  mkdir -p "${results_dir}"

  for component in "$@"; do
    [[ -n "${component}" ]] || continue

    sanitized="$(sanitize_path_component "${component}")"
    [[ -n "${sanitized}" ]] || continue

    if [[ -z "${filename}" ]]; then
      filename="${sanitized}"
    else
      filename+="-${sanitized}"
    fi
  done

  printf '%s/%s.xcresult\n' "${results_dir}" "${filename}"
}

get_log_path() {
  local logs_dir
  local filename
  local component
  local sanitized

  logs_dir="$(get_build_root_dir)/Logs"
  mkdir -p "${logs_dir}"

  for component in "$@"; do
    [[ -n "${component}" ]] || continue

    sanitized="$(sanitize_path_component "${component}")"
    [[ -n "${sanitized}" ]] || continue

    if [[ -z "${filename}" ]]; then
      filename="${sanitized}"
    else
      filename+="-${sanitized}"
    fi
  done

  printf '%s/%s.log\n' "${logs_dir}" "${filename}"
}

xcresult_build_failed() {
  local result_bundle_path="$1"
  local build_results_json

  [[ -d "${result_bundle_path}" ]] || return 1

  if ! build_results_json="$(
    xcrun xcresulttool get build-results \
      --path "${result_bundle_path}" \
      --compact \
      2>/dev/null
  )"; then
    return 1
  fi

  if printf '%s\n' "${build_results_json}" \
    | mise x -- jq -e '((.status // "") != "succeeded") or ((.errorCount // 0) > 0)' \
    >/dev/null
  then
    return 0
  fi

  return 1
}

xcresult_tests_failed() {
  local result_bundle_path="$1"
  local test_results_json

  [[ -d "${result_bundle_path}" ]] || return 1

  if ! test_results_json="$(
    xcrun xcresulttool get test-results summary \
      --path "${result_bundle_path}" \
      --compact \
      2>/dev/null
  )"; then
    return 1
  fi

  if printf '%s\n' "${test_results_json}" \
    | mise x -- jq -e '((.result // "") != "Passed") or ((.failedTests // 0) > 0)' \
    >/dev/null
  then
    return 0
  fi

  return 1
}

print_xcresult_test_diagnostics() {
  local result_bundle_path="$1"
  local test_results_json

  [[ -d "${result_bundle_path}" ]] || return 0

  if ! test_results_json="$(
    xcrun xcresulttool get test-results summary \
      --path "${result_bundle_path}" \
      --compact \
      2>/dev/null
  )"; then
    return 0
  fi

  printf '%s\n' "${test_results_json}" | mise x -- jq -r '
    "  test_results:",
    "    result: \(.result // "unknown")",
    "    total_tests: \(.totalTestCount // 0)",
    "    passed_tests: \(.passedTests // 0)",
    "    failed_tests: \(.failedTests // 0)",
    "    skipped_tests: \(.skippedTests // 0)",
    (
      if ((.testFailures // []) | length) > 0 then
        "    failures[\((.testFailures // []) | length)]:",
        (
          (.testFailures // [])[] |
          "      - target: \(.targetName // "unknown")",
          "        test: \(.testIdentifierString // .testName // "unknown")",
          (
            if ((.failureText // "") | length) > 0 then
              "        message: |",
              (.failureText | tostring | split("\n")[] | "          \(.)")
            else
              empty
            end
          )
        )
      else
        empty
      end
    )
  '
}

print_xcresult_build_diagnostics() {
  local result_bundle_path="$1"
  local build_results_json

  [[ -d "${result_bundle_path}" ]] || return 0

  if ! build_results_json="$(
    xcrun xcresulttool get build-results \
      --path "${result_bundle_path}" \
      --compact \
      2>/dev/null
  )"; then
    return 0
  fi

  printf '%s\n' "${build_results_json}" | mise x -- jq -r '
    def issue_details:
      "      - message: \(.message // "unknown")",
      (
        if ((.issueType // "") | length) > 0 then
          "        type: \(.issueType)"
        else
          empty
        end
      ),
      (
        if ((.sourceURL // "") | length) > 0 then
          "        source: \(.sourceURL)"
        else
          empty
        end
      );

    "  build_results:",
    "    status: \(.status // "unknown")",
    "    errors: \(.errorCount // ((.errors // []) | length))",
    "    warnings: \(.warningCount // ((.warnings // []) | length))",
    (
      if ((.errors // []) | length) > 0 then
        "    error_details[\((.errors // []) | length)]:",
        ((.errors // [])[] | issue_details)
      else
        empty
      end
    ),
    (
      if ((.warnings // []) | length) > 0 then
        "    warning_details[\((.warnings // []) | length)]:",
        ((.warnings // [])[] | issue_details)
      else
        empty
      end
    )
  '
}

print_log_excerpt() {
  local log_path="$1"

  [[ -f "${log_path}" ]] || return 0

  printf 'log_excerpt:\n'
  tail -n 40 "${log_path}" | sed 's/^/  /'
}

print_xcodebuild_diagnostics() {
  local action="$1"
  local result_bundle_path="$2"
  local log_path="$3"

  if [[ -d "${result_bundle_path}" ]]; then
    printf 'xcresult_diagnostics:\n'
    if [[ "${action}" == "test" ]]; then
      print_xcresult_test_diagnostics "${result_bundle_path}"
    fi
    print_xcresult_build_diagnostics "${result_bundle_path}"
  else
    print_log_excerpt "${log_path}"
  fi
}

get_build_temp_dir() {
  printf '%s/tmp\n' "$(get_build_root_dir)"
}

get_workspace_path() {
  if [[ -n "${WORKSPACE_PATH_CACHE:-}" ]]; then
    printf '%s\n' "${WORKSPACE_PATH_CACHE}"
    return
  fi

  local root_dir
  local workspaces=()
  local workspace_path

  root_dir="$(get_root_dir)"

  while IFS= read -r workspace_path; do
    [[ -n "${workspace_path}" ]] && workspaces+=("${workspace_path}")
  done < <(find "${root_dir}" -maxdepth 1 -type d -name '*.xcworkspace' | sort)

  if (( ${#workspaces[@]} == 0 )); then
    echo "Error: Xcode workspace not found. Generate the workspace by running: mise run generate_workspace" >&2
    exit 1
  fi

  if (( ${#workspaces[@]} > 1 )); then
    echo "Error: Multiple Xcode workspaces found under repository root:" >&2
    printf '%s\n' "${workspaces[@]}" >&2
    exit 1
  fi

  WORKSPACE_PATH_CACHE="${workspaces[0]}"
  printf '%s\n' "${WORKSPACE_PATH_CACHE}"
}

get_workspace_name() {
  local workspace_path

  workspace_path="$(get_workspace_path)"
  printf '%s\n' "${workspace_path##*/}" | sed 's/\.xcworkspace$//'
}

get_workspace_scheme() {
  printf '%s-Workspace\n' "$(get_workspace_name)"
}

get_app_scheme() {
  local app_scheme="${1:-${XCODE_APP_SCHEME:-}}"

  if [[ -z "${app_scheme}" ]]; then
    echo "Error: XCODE_APP_SCHEME is not set." >&2
    exit 1
  fi

  printf '%s\n' "${app_scheme}"
}

require_workspace() {
  get_workspace_path >/dev/null
}

show_app_build_settings() {
  local app_scheme="${1:-$(get_app_scheme)}"
  local cache_variable_name
  local derived_data_path
  local app_build_settings_json

  cache_variable_name="APP_BUILD_SETTINGS_JSON_$(sanitize_variable_name_component "${app_scheme}")"
  if [[ -n "${!cache_variable_name:-}" ]]; then
    printf '%s\n' "${!cache_variable_name}"
    return
  fi

  require_workspace
  require_build_scheme "${app_scheme}"

  derived_data_path="$(get_derived_data_path build "${app_scheme}")"
  mkdir -p "${derived_data_path}"

  app_build_settings_json="$(
    xcodebuild \
      -workspace "$(get_workspace_path)" \
      -scheme "${app_scheme}" \
      -configuration "Release" \
      -derivedDataPath "${derived_data_path}" \
      -showBuildSettings \
      -json
  )"

  printf -v "${cache_variable_name}" '%s' "${app_build_settings_json}"
  printf '%s\n' "${app_build_settings_json}"
}

get_app_build_setting() {
  local setting_name="$1"
  local app_scheme="${2:-$(get_app_scheme)}"

  # shellcheck disable=SC2016
  show_app_build_settings "${app_scheme}" | mise x -- jq -r --arg setting_name "${setting_name}" '.[0].buildSettings[$setting_name] // empty'
}

get_app_project_container_path() {
  local app_scheme="${1:-$(get_app_scheme)}"
  local project_container_path

  project_container_path="$(get_app_build_setting "PROJECT_FILE_PATH" "${app_scheme}")"
  if [[ -z "${project_container_path}" ]]; then
    echo "Error: PROJECT_FILE_PATH not found in app build settings." >&2
    exit 1
  fi

  if [[ "${project_container_path}" != /* ]]; then
    project_container_path="$(get_root_dir)/${project_container_path}"
  fi

  printf '%s\n' "${project_container_path}"
}

get_project_path() {
  local app_scheme="${1:-$(get_app_scheme)}"

  printf '%s/project.pbxproj\n' "$(get_app_project_container_path "${app_scheme}")"
}

require_project() {
  local project_path

  project_path="$(get_project_path)"
  if [[ ! -f "${project_path}" ]]; then
    echo "Error: Xcode project not found at ${project_path}." >&2
    exit 1
  fi
}

get_app_bundle_id() {
  local app_scheme="${1:-$(get_app_scheme)}"

  get_app_build_setting "PRODUCT_BUNDLE_IDENTIFIER" "${app_scheme}"
}

get_marketing_version() {
  local app_scheme="${1:-$(get_app_scheme)}"

  get_app_build_setting "MARKETING_VERSION" "${app_scheme}"
}

get_build_number() {
  local app_scheme="${1:-$(get_app_scheme)}"

  get_app_build_setting "CURRENT_PROJECT_VERSION" "${app_scheme}"
}

get_build_tag() {
  printf 'v%s-%s' "$(get_marketing_version)" "$(get_build_number)"
}

get_development_team() {
  local app_scheme="${1:-$(get_app_scheme)}"

  get_app_build_setting "DEVELOPMENT_TEAM" "${app_scheme}"
}

get_archive_path() {
  local platform="$1"
  local app_scheme="${2:-$(get_app_scheme)}"

  printf '%s/archives/%s/%s.xcarchive\n' \
    "$(get_build_root_dir)" \
    "$(sanitize_path_component "${platform}")" \
    "$(sanitize_path_component "${app_scheme}")"
}

get_export_path() {
  local platform="$1"
  local app_scheme="${2:-$(get_app_scheme)}"

  printf '%s/exports/%s/%s\n' \
    "$(get_build_root_dir)" \
    "$(sanitize_path_component "${platform}")" \
    "$(sanitize_path_component "${app_scheme}")"
}

require_archive() {
  local platform="$1"
  local archive_path

  archive_path="$(get_archive_path "${platform}")"
  if [[ ! -d "${archive_path}" ]]; then
    echo "Error: Archive not found: ${archive_path}. Run: mise run archive_app --platform ${platform}" >&2
    exit 1
  fi
}

list_available_build_schemes() {
  mise run --output quiet list_build_schemes
}

require_build_scheme() {
  local expected_scheme="$1"
  local available_schemes=()
  local scheme

  while IFS= read -r scheme; do
    [[ -n "${scheme}" ]] && available_schemes+=("${scheme}")
  done < <(list_available_build_schemes)

  for scheme in "${available_schemes[@]}"; do
    if [[ "${scheme}" == "${expected_scheme}" ]]; then
      return
    fi
  done

  echo "Error: Scheme \"${expected_scheme}\" not found." >&2
  if (( ${#available_schemes[@]} > 0 )); then
    echo "Available schemes:" >&2
    printf '%s\n' "${available_schemes[@]}" >&2
  else
    echo "No build schemes found. Generate the workspace by running: mise run generate_workspace" >&2
  fi
  exit 1
}

get_build_destination() {
  case "$1" in
    macOS)
      printf 'generic/platform=macOS'
      ;;
    iOS)
      printf 'generic/platform=iOS'
      ;;
    *)
      echo "Error: Unsupported platform: $1" >&2
      exit 1
      ;;
  esac
}

get_test_destination() {
  case "$1" in
    macOS)
      printf 'platform=macOS'
      ;;
    iOS)
      printf 'platform=iOS Simulator,name=%s' "$(require_env_var "IOS_SIMULATOR_NAME")"
      ;;
    *)
      echo "Error: Unsupported platform: $1" >&2
      exit 1
      ;;
  esac
}

get_testflight_groups() {
  local env_value
  local groups

  env_value="$(require_env_var "TESTFLIGHT_GROUPS")"
  groups="$(printf '%s' "${env_value}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d')"

  if [[ -z "${groups}" ]]; then
    echo "Error: TESTFLIGHT_GROUPS does not define any TestFlight groups." >&2
    exit 1
  fi

  printf '%s\n' "${groups}"
}

app_store_connect_require_env() {
  local missing=()
  local variable_value

  for variable_name in \
    APP_STORE_CONNECT_API_KEY_ID \
    APP_STORE_CONNECT_API_ISSUER_ID \
    APP_STORE_CONNECT_API_PRIVATE_KEY_PATH \
  ; do
    variable_value="$(printenv "${variable_name}" || true)"
    if [[ -z "${variable_value}" ]]; then
      missing+=("$variable_name")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "Error: Missing required App Store Connect environment variables:" >&2
    printf '%s\n' "${missing[@]}" >&2
    exit 1
  fi

  if [[ ! -f "${APP_STORE_CONNECT_API_PRIVATE_KEY_PATH}" ]]; then
    echo "Error: App Store Connect private key file not found: ${APP_STORE_CONNECT_API_PRIVATE_KEY_PATH}" >&2
    exit 1
  fi
}

app_store_connect_base64url() {
  openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

app_store_connect_der_parse_length() {
  local offset="$1"
  local first_byte
  first_byte=$((16#${APP_STORE_CONNECT_DER_BYTES[$offset]}))

  if (( (first_byte & 0x80) == 0 )); then
    APP_STORE_CONNECT_DER_LENGTH="${first_byte}"
    APP_STORE_CONNECT_DER_LENGTH_BYTES=1
    return
  fi

  local length_of_length=$((first_byte & 0x7F))
  local value=0
  local index
  for ((index = 1; index <= length_of_length; index++)); do
    value=$(( (value << 8) + 16#${APP_STORE_CONNECT_DER_BYTES[$((offset + index))]} ))
  done

  APP_STORE_CONNECT_DER_LENGTH="${value}"
  APP_STORE_CONNECT_DER_LENGTH_BYTES=$((length_of_length + 1))
}

app_store_connect_der_integer_to_jose_hex() {
  local component_hex=("$@")

  while (( ${#component_hex[@]} > 32 )) && [[ "${component_hex[0]}" == "00" ]]; do
    component_hex=("${component_hex[@]:1}")
  done

  if (( ${#component_hex[@]} > 32 )); then
    echo "Error: DER integer is too large to convert to ES256 JOSE signature." >&2
    exit 1
  fi

  local hex=""
  local byte
  for byte in "${component_hex[@]}"; do
    hex+="${byte}"
  done

  printf '%064s' "${hex}" | tr ' ' '0'
}

app_store_connect_create_jwt() {
  app_store_connect_require_env

  local now expiration_time header payload header_base64 payload_base64 signing_input
  now="$(date -u +%s)"
  expiration_time="$((now + 1200))"

  # shellcheck disable=SC2016
  header="$(mise x -- jq -cn --arg key_id "${APP_STORE_CONNECT_API_KEY_ID}" '{alg:"ES256", kid:$key_id, typ:"JWT"}')"
  # shellcheck disable=SC2016
  payload="$(mise x -- jq -cn \
    --arg issuer_id "${APP_STORE_CONNECT_API_ISSUER_ID}" \
    --argjson issued_at "${now}" \
    --argjson expiration_time "${expiration_time}" \
    '{iss:$issuer_id, iat:$issued_at, exp:$expiration_time, aud:"appstoreconnect-v1"}')"

  header_base64="$(printf '%s' "${header}" | app_store_connect_base64url)"
  payload_base64="$(printf '%s' "${payload}" | app_store_connect_base64url)"
  signing_input="${header_base64}.${payload_base64}"

  local der_signature_file
  der_signature_file="$(mktemp "${TMPDIR:-/tmp}/app-store-connect-jwt-signature.XXXXXX.der")"
  trap 'rm -f "${der_signature_file}"' RETURN

  printf '%s' "${signing_input}" \
    | openssl dgst -binary -sha256 -sign "${APP_STORE_CONNECT_API_PRIVATE_KEY_PATH}" \
    > "${der_signature_file}"

  APP_STORE_CONNECT_DER_BYTES=()
  local byte
  while IFS= read -r byte; do
    if [[ -n "${byte}" ]]; then
      APP_STORE_CONNECT_DER_BYTES+=("${byte}")
    fi
  done < <(od -An -tx1 -v "${der_signature_file}" | tr -s '[:space:]' '\n')

  if (( ${#APP_STORE_CONNECT_DER_BYTES[@]} < 8 )) || [[ "${APP_STORE_CONNECT_DER_BYTES[0]}" != "30" ]]; then
    echo "Error: Invalid DER-encoded ECDSA signature." >&2
    exit 1
  fi

  local offset=1
  app_store_connect_der_parse_length "${offset}"
  offset=$((offset + APP_STORE_CONNECT_DER_LENGTH_BYTES))

  if [[ "${APP_STORE_CONNECT_DER_BYTES[$offset]}" != "02" ]]; then
    echo "Error: Invalid DER signature format for R component." >&2
    exit 1
  fi

  offset=$((offset + 1))
  app_store_connect_der_parse_length "${offset}"
  offset=$((offset + APP_STORE_CONNECT_DER_LENGTH_BYTES))

  local r_length="${APP_STORE_CONNECT_DER_LENGTH}"
  local r_bytes=("${APP_STORE_CONNECT_DER_BYTES[@]:${offset}:${r_length}}")
  offset=$((offset + r_length))

  if [[ "${APP_STORE_CONNECT_DER_BYTES[$offset]}" != "02" ]]; then
    echo "Error: Invalid DER signature format for S component." >&2
    exit 1
  fi

  offset=$((offset + 1))
  app_store_connect_der_parse_length "${offset}"
  offset=$((offset + APP_STORE_CONNECT_DER_LENGTH_BYTES))

  local s_length="${APP_STORE_CONNECT_DER_LENGTH}"
  local s_bytes=("${APP_STORE_CONNECT_DER_BYTES[@]:${offset}:${s_length}}")

  local jose_signature_escaped=""

  local normalized_r_hex normalized_s_hex
  normalized_r_hex="$(app_store_connect_der_integer_to_jose_hex "${r_bytes[@]}")"
  normalized_s_hex="$(app_store_connect_der_integer_to_jose_hex "${s_bytes[@]}")"

  local index hex_pair
  for ((index = 0; index < ${#normalized_r_hex}; index += 2)); do
    hex_pair="${normalized_r_hex:${index}:2}"
    jose_signature_escaped+="\\x${hex_pair}"
  done
  for ((index = 0; index < ${#normalized_s_hex}; index += 2)); do
    hex_pair="${normalized_s_hex:${index}:2}"
    jose_signature_escaped+="\\x${hex_pair}"
  done

  printf '%s.%s\n' \
    "${signing_input}" \
    "$(printf '%b' "${jose_signature_escaped}" | app_store_connect_base64url)"
}

app_store_connect_api() {
  local method="$1"
  local endpoint="$2"
  shift 2

  local jwt_token
  jwt_token="$(app_store_connect_create_jwt)"

  curl -fsS \
    -X "${method}" \
    -H "Authorization: Bearer ${jwt_token}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "https://api.appstoreconnect.apple.com/v1/${endpoint}" \
    "$@"
}

app_store_connect_get_all_pages() {
  local endpoint="$1"
  shift

  local request_args=("$@")
  local response page_data next_url all_data_json
  all_data_json='[]'

  while :; do
    response="$(app_store_connect_api GET "${endpoint}" "${request_args[@]}")"
    page_data="$(printf '%s' "${response}" | mise x -- jq -c '.data // []')"
    all_data_json="$(printf '%s\n%s\n' "${all_data_json}" "${page_data}" | mise x -- jq -sc '.[0] + .[1]')"

    next_url="$(printf '%s' "${response}" | mise x -- jq -r '.links.next // empty')"
    if [[ -z "${next_url}" ]]; then
      break
    fi

    endpoint="${next_url#https://api.appstoreconnect.apple.com/v1/}"
    request_args=()
  done

  # shellcheck disable=SC2016
  mise x -- jq -cn --argjson data "${all_data_json}" '{data:$data}'
}

app_store_connect_platform_name() {
  case "$1" in
    iOS)
      printf 'IOS'
      ;;
    macOS)
      printf 'MAC_OS'
      ;;
    *)
      echo "Error: Unsupported platform: $1" >&2
      exit 1
      ;;
  esac
}

app_store_connect_lookup_app_id() {
  local bundle_id="$1"

  app_store_connect_api GET "apps" \
    -G \
    --data-urlencode "filter[bundleId]=${bundle_id}" \
    --data-urlencode "limit=1" \
    | mise x -- jq -r '.data[0].id // empty'
}

app_store_connect_get_app_id() {
  local bundle_id
  local app_id

  if (( $# > 0 )); then
    bundle_id="$1"
  else
    bundle_id="$(get_app_bundle_id)"
  fi

  app_id="$(app_store_connect_lookup_app_id "${bundle_id}")"
  if [[ -z "${app_id}" ]]; then
    echo "Error: App not found in App Store Connect for bundle identifier ${bundle_id}" >&2
    exit 1
  fi

  printf '%s\n' "${app_id}"
}

app_store_connect_lookup_build() {
  local app_id="$1"
  local platform="$2"
  local marketing_version="$3"
  local build_number="$4"

  app_store_connect_api GET "builds" \
    -G \
    --data-urlencode "filter[app]=${app_id}" \
    --data-urlencode "filter[preReleaseVersion.platform]=${platform}" \
    --data-urlencode "filter[preReleaseVersion.version]=${marketing_version}" \
    --data-urlencode "filter[version]=${build_number}" \
    --data-urlencode "limit=1" \
    --data-urlencode "fields[builds]=processingState,uploadedDate,version" \
    | mise x -- jq -c '.data[0] // {}'
}
