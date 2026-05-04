#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091,SC2154
#MISE description="Uploads the archived app for the selected platform to App Store Connect from the repo-local build directory."
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

app_store_connect_require_env

scheme="${usage_scheme:-$(get_app_scheme)}"
archive_path="$(get_archive_path "${usage_platform}" "${scheme}")"
export_path="$(get_export_path "${usage_platform}" "${scheme}")"
build_temp_dir="$(get_build_temp_dir)"
mkdir -p "$(dirname "${export_path}")" "${build_temp_dir}"
rm -rf "${export_path}"
mkdir -p "${export_path}"
export_options_path="$(mktemp "${build_temp_dir}/upload_archive_export_options.XXXXXX.plist")"
xcodebuild_output_path="$(mktemp "${build_temp_dir}/upload_archive_xcodebuild_output.XXXXXX.log")"

require_build_scheme "${scheme}"
bundle_id="$(get_app_bundle_id "${scheme}")"
marketing_version="$(get_marketing_version "${scheme}")"
build_number="$(get_build_number "${scheme}")"
app_id="$(app_store_connect_get_app_id "${bundle_id}")"
team_id="$(get_development_team "${scheme}")"

if [[ ! -d "${archive_path}" ]]; then
  echo "Error: Archive not found: ${archive_path}. Run: mise run archive_app --scheme ${scheme} --platform ${usage_platform}" >&2
  exit 1
fi

if [[ -z "${team_id}" ]]; then
  echo "Error: DEVELOPMENT_TEAM not found in generated Xcode project." >&2
  exit 1
fi

cat > "${export_options_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${team_id}</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF

cleanup() {
  rm -f "${export_options_path}" "${xcodebuild_output_path}"
}

trap cleanup EXIT

system_tool_path="/usr/bin:/bin:/usr/sbin:/sbin"

set +e
PATH="${system_tool_path}" \
xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist "${export_options_path}" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${APP_STORE_CONNECT_API_PRIVATE_KEY_PATH}" \
  -authenticationKeyID "${APP_STORE_CONNECT_API_KEY_ID}" \
  -authenticationKeyIssuerID "${APP_STORE_CONNECT_API_ISSUER_ID}" \
  2>&1 | tee "${xcodebuild_output_path}"
xcodebuild_exit_code=${PIPESTATUS[0]}
set -e

if (( xcodebuild_exit_code != 0 )); then
  distribution_logs_path="$(sed -n 's|.*Created bundle at path "\(.*\.xcdistributionlogs\)".*|\1|p' "${xcodebuild_output_path}" | tail -n 1)"
  if [[ -n "${distribution_logs_path}" && -d "${distribution_logs_path}" ]]; then
    echo "Xcode distribution logs: ${distribution_logs_path}" >&2
    distribution_diagnostic_log=""
    for candidate in \
      "${distribution_logs_path}/IDEDistributionPipeline.log" \
      "${distribution_logs_path}/IDEDistribution.standard.log" \
      "${distribution_logs_path}/ContentDelivery.log" \
    ; do
      if [[ -f "${candidate}" ]]; then
        distribution_diagnostic_log="${candidate}"
        break
      fi
    done

    if [[ -z "${distribution_diagnostic_log}" ]]; then
      distribution_diagnostic_log="$(find "${distribution_logs_path}" -type f -name "*.log" | sort | head -n 1)"
    fi

    if [[ -n "${distribution_diagnostic_log}" && -f "${distribution_diagnostic_log}" ]]; then
      echo "--- BEGIN Xcode distribution log ---" >&2
      cat "${distribution_diagnostic_log}" >&2
      echo "--- END Xcode distribution log ---" >&2
    fi
  fi

  exit "${xcodebuild_exit_code}"
fi

case "${usage_platform}" in
  iOS)
    exported_package_path="$(find "${export_path}" -maxdepth 1 -type f -name "*.ipa" | head -n 1)"
    altool_platform="ios"
    ;;
  macOS)
    exported_package_path="$(find "${export_path}" -maxdepth 1 -type f -name "*.pkg" | head -n 1)"
    altool_platform="macos"
    ;;
esac

if [[ -z "${exported_package_path:-}" || ! -f "${exported_package_path}" ]]; then
  echo "Error: Exported package not found in ${export_path}" >&2
  find "${export_path}" -maxdepth 2 -print >&2
  exit 1
fi

xcrun altool \
  --upload-package "${exported_package_path}" \
  --platform "${altool_platform}" \
  --apple-id "${app_id}" \
  --bundle-id "${bundle_id}" \
  --bundle-version "${build_number}" \
  --bundle-short-version-string "${marketing_version}" \
  --p8-file-path "${APP_STORE_CONNECT_API_PRIVATE_KEY_PATH}" \
  --api-key "${APP_STORE_CONNECT_API_KEY_ID}" \
  --api-issuer "${APP_STORE_CONNECT_API_ISSUER_ID}"
