#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091
#MISE description="Installs dependencies, generates Xcode workspace, and inspects configuration."
#USAGE flag "--no-inspect" {
#USAGE   help "Skip inspecting implicit and redundant dependencies in Tuist projects."
#USAGE }
#USAGE flag "--no-install" {
#USAGE   help "Skip installing any remote content (e.g. dependencies)."
#USAGE }
#USAGE flag "-o --open" {
#USAGE   help "Open generated workspace."
#USAGE }

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

root_dir="$(get_root_dir)"

if [[ ! "${usage_no_install:-false}" == "true" ]]; then
  mise x -- tuist install \
    --path "$root_dir" \
    --no-update
fi

if [[ ! "${usage_no_inspect:-false}" == "true" ]]; then
  mise x -- tuist inspect dependencies \
    --path "$root_dir"
fi

mise x -- tuist generate \
  --path "$root_dir" \
  --no-open

if [[ "${usage_open:-false}" == "true" ]]; then
  open "$(get_workspace_path)"
fi
