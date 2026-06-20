#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091,SC2154
#MISE description="Warms Tuist binary cache."
#USAGE flag "-c --configuration <configuration>" {
#USAGE   help "Build configuration to warm (eg. Debug, Release). Defaults to the value of TUIST_CACHE_CONFIGURATION environment variable." 
#USAGE }
#USAGE flag "-p --cache-profile <cache-profile>" {
#USAGE   help "Tuist cache profile. Defaults to the value of TUIST_CACHE_PROFILE environment variable."
#USAGE }
#USAGE flag "--no-install" {
#USAGE   help "Skip installing any remote content (e.g. dependencies)."
#USAGE }

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

configuration="${usage_configuration:-$(require_env_var "TUIST_CACHE_CONFIGURATION")}"
cache_profile="${usage_cache_profile:-$(require_env_var "TUIST_CACHE_PROFILE")}"

if [[ ! "${usage_no_install:-false}" == "true" ]]; then
  tuist_install || exit "$?"
fi

tuist_cache_warm "$configuration" "$cache_profile" || exit "$?"
