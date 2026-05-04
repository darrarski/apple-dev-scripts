#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091
#MISE description="Sets build number in generated Xcode workspace."
#USAGE arg "<build_number>" {
#USAGE   help "Build number. Defaults to current build number + 1."
#USAGE   required #false
#USAGE }

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

require_project

project_path="$(get_project_path)"
current_build_number="$(get_build_number)"

echo "Current build number: ${current_build_number}"

if [[ -n "${usage_build_number:-}" ]]; then
  new_build_number="${usage_build_number}"
else
  new_build_number=$((current_build_number + 1))
fi

echo "New build number: ${new_build_number}"

sed -i '' "s/CURRENT_PROJECT_VERSION = ${current_build_number};/CURRENT_PROJECT_VERSION = ${new_build_number};/g" "${project_path}"
