#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091,SC2154
#MISE description="Warms Tuist binary cache for external dependencies."
#USAGE arg "<configuration>" {
#USAGE   help "Configuration to warm. Pass Debug, Release, or both." 
#USAGE   var #true
#USAGE   var_min 1
#USAGE   choices "Debug" "Release"
#USAGE }
#USAGE flag "--no-install" {
#USAGE   help "Skip installing any remote content (e.g. dependencies)."
#USAGE }

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

warm_debug=false
warm_release=false

eval "set -- ${usage_configuration}"

for configuration in "$@"; do
  case "${configuration}" in
    Debug)
      warm_debug=true
      ;;
    Release)
      warm_release=true
      ;;
    *)
      echo "Error: Unsupported configuration '${configuration}'. Expected Debug or Release." >&2
      exit 1
      ;;
  esac
done

if [[ "${warm_debug}" != "true" && "${warm_release}" != "true" ]]; then
  echo "Error: At least one configuration is required. Expected Debug or Release." >&2
  exit 1
fi

status=0

if [[ ! "${usage_no_install:-false}" == "true" ]]; then
  tuist_install || exit "$?"
fi

if [[ "${warm_debug}" == "true" ]]; then
  tuist_cache_warm_external Debug || status="$?"
fi

if [[ "${warm_release}" == "true" ]]; then
  tuist_cache_warm_external Release || status="$?"
fi

exit "${status}"
