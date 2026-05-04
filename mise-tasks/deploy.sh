#!/usr/bin/env -S usage bash
# shellcheck shell=bash disable=SC1091,SC2154
#MISE description="Runs the local deploy pipeline for debugging and manual release verification."
#USAGE

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=./_shared.sh
source "${script_dir}/_shared.sh"

app_store_connect_require_env

mise run generate_workspace
mise run set_next_build_number
mise run archive_app --platform macOS
mise run archive_app --platform iOS
mise run upload_archive --platform macOS
mise run upload_archive --platform iOS
mise run add_release_tag
mise run generate_whattotest
mise run submit_to_testflight --platform macOS
mise run submit_to_testflight --platform iOS
